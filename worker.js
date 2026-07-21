const GOOGLE_CLIENT_ID = '156334413688-usb68f1fldmrhic94mn925l75hnk82pk.apps.googleusercontent.com';

// Default models, used only if the corresponding env var isn't set.
// To roll to new models with no code change/redeploy, set these in your
// Cloudflare Worker environment instead: MODEL_OPUS, MODEL_SONNET.
const DEFAULT_MODELS = {
  opus: 'claude-opus-4-8',
  sonnet: 'claude-sonnet-5',
};

function getModels(env) {
  return {
    opus: env.MODEL_OPUS || DEFAULT_MODELS.opus,
    sonnet: env.MODEL_SONNET || DEFAULT_MODELS.sonnet,
  };
}

function buildModelCascade(env) {
  const m = getModels(env);
  return {
    image: [m.opus, m.sonnet],
    food: [m.sonnet, m.opus],
    ai_coach: [m.sonnet, m.opus],
    default: [m.sonnet, m.opus],
  };
}

async function verifyGoogleToken(token) {
  const res = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${token}`);
  if (!res.ok) throw new Error('Invalid token');
  const data = await res.json();
  if (data.aud !== GOOGLE_CLIENT_ID) throw new Error('Token audience mismatch');
  if (data.exp < Date.now() / 1000) throw new Error('Token expired');
  return { google_id: data.sub, name: data.name, email: data.email, avatar: data.picture };
}

function uid() { return crypto.randomUUID().replace(/-/g, '').substring(0, 16); }

// ── Sessions ─────────────────────────────────────────────────────────────
const SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000; // 90 days

// ENFORCEMENT ON (Phase 3, enabled 2026-07-03). A request that presents no
// valid session token is rejected with 401 AUTH_REQUIRED — endpoints no longer
// fall back to trusting body.user_id, so no client can act as another user by
// claiming an id. The frontend catches AUTH_REQUIRED and routes to re-login.
// Emergency rollback WITHOUT a code deploy: set REQUIRE_SESSIONS=false in the
// Worker's environment variables (that env var overrides this default in
// either direction). Reverting this commit is the equivalent code-side rollback.
const REQUIRE_SESSIONS_DEFAULT = true;

async function sha256Hex(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
}

// Only the SHA-256 of the token is stored, so a leaked sessions table can't
// be replayed as live credentials.
async function createSession(env, user_id) {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const token = [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
  const now = new Date();
  const expires = new Date(now.getTime() + SESSION_TTL_MS);
  await env.DB.prepare(
    'INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?,?,?,?)'
  ).bind(await sha256Hex(token), user_id, now.toISOString(), expires.toISOString()).run();
  return token;
}

// The client sends the token both as an Authorization header and in the JSON
// body — the header is standard, the body copy survives anything that strips
// or blocks custom headers (the CORS failure mode that broke the first
// rollout of sessions).
function getBearerToken(request, body) {
  const header = request.headers.get('Authorization') || '';
  if (header.startsWith('Bearer ')) return header.slice(7);
  return (typeof body?.session_token === 'string' && body.session_token) || null;
}

async function resolveSessionUserId(env, token) {
  if (!token) return null;
  const session = await env.DB.prepare(
    'SELECT user_id, expires_at FROM sessions WHERE token=?'
  ).bind(await sha256Hex(token)).first();
  if (!session || new Date(session.expires_at) < new Date()) return null;
  return session.user_id;
}

// Best-effort failure log — must never throw, so a logging bug can't take
// down the request it's trying to record.
async function logError(env, { user_id, source, type, message, detail }) {
  try {
    await env.DB.prepare(
      'INSERT INTO error_log (user_id, source, type, message, detail, created_at) VALUES (?,?,?,?,?,?)'
    ).bind(
      user_id || null, source, type || null,
      String(message || '').slice(0, 500),
      detail != null ? String(detail).slice(0, 2000) : null,
      new Date().toISOString()
    ).run();
  } catch (e) {}
}

async function checkRateLimit(env, user_id, field, limit) {
  const today = new Date().toISOString().slice(0, 10);
  const row = await env.DB.prepare(
    'SELECT * FROM rate_limits WHERE user_id=? AND date=?'
  ).bind(user_id, today).first();
  const count = row ? (row[field] || 0) : 0;
  if (count >= limit) return { allowed: false, count, limit };
  await env.DB.prepare(
    `INSERT INTO rate_limits (user_id, date, ${field}) VALUES (?, ?, 1) ON CONFLICT(user_id, date) DO UPDATE SET ${field} = COALESCE(${field},0) + 1`
  ).bind(user_id, today).run();
  return { allowed: true, count: count + 1, limit };
}

export default {
  async fetch(request, env) {
    const cors = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Max-Age': '86400',
    };
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });
    if (request.method !== 'POST') return new Response('Not allowed', { status: 405 });

    const url = new URL(request.url);
    const path = url.pathname;
    const body = await request.json();
    const json = (data, status = 200) => new Response(JSON.stringify(data), {
      status, headers: { 'Content-Type': 'application/json', ...cors }
    });

    const requireAuth = env.REQUIRE_SESSIONS != null
      ? env.REQUIRE_SESSIONS === 'true'
      : REQUIRE_SESSIONS_DEFAULT;
    const sessionUserId = await resolveSessionUserId(env, getBearerToken(request, body));
    // A valid session always wins over anything the client claims in the
    // body; the body fallback exists only until enforcement flips on.
    const resolveUser = (bodyUserId) =>
      sessionUserId || (!requireAuth ? (bodyUserId || 'default') : null);
    // The code field lets the client distinguish "sign in again" from other
    // 401s (e.g. a bad Google credential on /auth/google).
    const authError = () => json({ error: 'Please sign in again.', code: 'AUTH_REQUIRED' }, 401);

    if (path === '/auth/google') {
      try {
        const { token } = body;
        const profile = await verifyGoogleToken(token);
        let user = await env.DB.prepare('SELECT * FROM users WHERE google_id = ?').bind(profile.google_id).first();
        let is_new = false;
        if (!user) {
          is_new = true;
          const id = uid();
          await env.DB.prepare(
            'INSERT INTO users (id, google_id, name, email, avatar, created_at, privacy) VALUES (?,?,?,?,?,?,?)'
          ).bind(id, profile.google_id, profile.name, profile.email, profile.avatar, new Date().toISOString(), 'private').run();
          if (profile.email === 'bmdahmen@gmail.com') {
            await env.DB.prepare('UPDATE users SET lim_ai_coach=9999, lim_images=9999, lim_food_prompts=9999 WHERE id=?').bind(id).run();
          }
          user = await env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
        }
        const session_token = await createSession(env, user.id);
        await env.DB.prepare('DELETE FROM sessions WHERE expires_at < ?').bind(new Date().toISOString()).run();
        return json({ ok: true, is_new, user, session_token });
      } catch(e) {
        return json({ error: e.message }, 401);
      }
    }

    if (path === '/auth/logout') {
      const token = getBearerToken(request, body);
      if (token) await env.DB.prepare('DELETE FROM sessions WHERE token=?').bind(await sha256Hex(token)).run();
      return json({ ok: true });
    }

    if (path === '/auth/profile') {
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      const { tdee, pro_target, age, weight_lbs, height_in, activity, goal_mode, aggressiveness, theme, dexa_date, dexa_weight, dexa_bf_pct, muscle_loss_pct, muscle_gain_pct, muscle_maintain_pct, rmr, cal_target_override } = body;
      await env.DB.prepare(
        'UPDATE users SET tdee=?, pro_target=?, age=?, weight_lbs=?, height_in=?, activity=?, goal_mode=?, aggressiveness=?, theme=?, dexa_date=?, dexa_weight=?, dexa_bf_pct=?, muscle_loss_pct=?, muscle_gain_pct=?, muscle_maintain_pct=?, rmr=?, cal_target_override=? WHERE id=?'
      ).bind(tdee||2100, pro_target||120, age||35, weight_lbs||170, height_in||66, activity||'sedentary', goal_mode||'deficit', aggressiveness||'moderate', theme||'dark', dexa_date||null, dexa_weight||null, dexa_bf_pct||null, muscle_loss_pct!=null?muscle_loss_pct:20, muscle_gain_pct!=null?muscle_gain_pct:20, muscle_maintain_pct!=null?muscle_maintain_pct:20, rmr||null, cal_target_override||null, user_id).run();
      return json({ ok: true });
    }

    if (path === '/auth/migrate') {
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      await env.DB.prepare("UPDATE meals SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE measurements SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE history SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE cache SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE food_items SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE presets SET user_id=? WHERE user_id='default'").bind(user_id).run();
      return json({ ok: true });
    }

    if (path === '/' || path === '/ai') {
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      const { _type } = body;
      if (user_id !== 'default') {
        const user = await env.DB.prepare('SELECT lim_ai_coach, lim_images, lim_food_prompts FROM users WHERE id=?').bind(user_id).first();
        if (user && _type) {
          const fieldMap = { ai_coach: ['ai_coach_count', user.lim_ai_coach||25], image: ['image_count', user.lim_images||20], food: ['food_prompt_count', user.lim_food_prompts||100] };
          const [field, limit] = fieldMap[_type] || [];
          if (field) {
            const check = await checkRateLimit(env, user_id, field, limit);
            if (!check.allowed) return json({ error: { message: `Daily limit of ${limit} reached. Resets tomorrow.` }, rate_limited: true }, 429);
          }
        }
      }

      // Model cascade per request type — worker picks model, not client
      const modelCascade = buildModelCascade(env);
      const models = modelCascade[_type] || modelCascade.default;

      const aiBody = { ...body };
      delete aiBody._type; delete aiBody.user_id; delete aiBody.session_token;
      // Server-side ceiling so a tampered client can't request unbounded output
      aiBody.max_tokens = Math.min(parseInt(aiBody.max_tokens) || 1024, 4096);

      // Prompt caching: mark the system prompt, and (for multi-turn requests like
      // the AI coach chat) everything before the newest turn, as cacheable. Below
      // each model's minimum cacheable size this is a no-op, so it's safe to leave
      // on for every request rather than special-casing which _type benefits.
      if (typeof aiBody.system === 'string' && aiBody.system) {
        aiBody.system = [{ type: 'text', text: aiBody.system, cache_control: { type: 'ephemeral' } }];
      }
      if (Array.isArray(aiBody.messages) && aiBody.messages.length > 1) {
        const prior = aiBody.messages[aiBody.messages.length - 2];
        if (prior && typeof prior.content === 'string') {
          prior.content = [{ type: 'text', text: prior.content, cache_control: { type: 'ephemeral' } }];
        } else if (Array.isArray(prior?.content) && prior.content.length) {
          prior.content[prior.content.length - 1].cache_control = { type: 'ephemeral' };
        }
      }

      // Try each model with exponential backoff on overload
      let lastResult = null;
      for (let mi = 0; mi < models.length; mi++) {
        aiBody.model = models[mi];
        let delay = 500;
        for (let attempt = 0; attempt < 3; attempt++) {
          const res = await fetch('https://api.anthropic.com/v1/messages', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01' },
            body: JSON.stringify(aiBody),
          });
          lastResult = await res.json();
          const overloaded = res.status === 529 || lastResult?.error?.type === 'overloaded_error';
          if (!overloaded) {
            if (lastResult?.error) {
              await logError(env, { user_id, source: 'server_ai_call', type: _type, message: lastResult.error.message || lastResult.error.type, detail: JSON.stringify(lastResult.error) });
            }
            return json(lastResult); // success or non-overload error
          }
          // Overloaded — wait then retry same model, or move to next model on last attempt
          if (attempt < 2) await new Promise(r => setTimeout(r, delay));
          delay *= 2;
        }
        // All retries on this model failed with overload — try next model
      }
      await logError(env, { user_id, source: 'server_ai_call', type: _type, message: 'all models overloaded after retries', detail: JSON.stringify(lastResult?.error || lastResult) });
      return json({ ...lastResult, error: { ...(lastResult?.error||{}), message: 'Claude is busy right now — please try again in a moment.' } });
    }

    if (path === '/log/error') {
      const user_id = resolveUser(body.user_id);
      const { source, type, message, detail } = body;
      if (source && message) await logError(env, { user_id, source, type, message, detail });
      return json({ ok: true });
    }

    if (path === '/usage/today') {
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      const today = new Date().toISOString().slice(0, 10);
      const row = await env.DB.prepare('SELECT * FROM rate_limits WHERE user_id=? AND date=?').bind(user_id, today).first();
      const user = await env.DB.prepare('SELECT lim_ai_coach, lim_images, lim_food_prompts FROM users WHERE id=?').bind(user_id).first();
      return json({ usage: row || {}, limits: user || {} });
    }

    if (path === '/cache/get') {
      const { key } = body;
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      const row = await env.DB.prepare('SELECT * FROM cache WHERE key=? AND user_id=?').bind(key, user_id).first();
      return json(row || null);
    }
    if (path === '/cache/set') {
      const { key, value, fingerprint } = body;
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      await env.DB.prepare(
        'INSERT INTO cache (key,value,fingerprint,updated_at,user_id) VALUES (?,?,?,?,?) ON CONFLICT(key,user_id) DO UPDATE SET value=excluded.value,fingerprint=excluded.fingerprint,updated_at=excluded.updated_at'
      ).bind(key, value, fingerprint, new Date().toISOString(), user_id).run();
      return json({ ok: true });
    }

    if (path === '/meals/save') {
      const { meals, date } = body;
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      await env.DB.prepare('DELETE FROM meals WHERE date=? AND user_id=?').bind(date, user_id).run();
      for (const m of meals) {
        await env.DB.prepare('INSERT INTO meals (id,date,desc,cal,pro,time,user_id) VALUES (?,?,?,?,?,?,?)')
          .bind(String(m.id), date, m.desc, m.cal, m.pro, m.time, user_id).run();
      }
      return json({ ok: true });
    }
    if (path === '/meals/load') {
      const { date } = body;
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      const { results } = await env.DB.prepare('SELECT * FROM meals WHERE date=? AND user_id=? ORDER BY rowid').bind(date, user_id).all();
      return json(results);
    }

    if (path === '/fooditems/save') {
      const { food_items } = body;
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      await env.DB.prepare('DELETE FROM food_items WHERE user_id=?').bind(user_id).run();
      for (let i = 0; i < food_items.length; i++) {
        const f = food_items[i];
        await env.DB.prepare('INSERT INTO food_items (id,user_id,name,cal,pro,weight_g,sort_order,created_at) VALUES (?,?,?,?,?,?,?,?)')
          .bind(String(f.id), user_id, f.name, f.cal, f.pro || 0, f.weight_g || null, i, f.created_at || new Date().toISOString()).run();
      }
      return json({ ok: true });
    }
    if (path === '/fooditems/load') {
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      const { results } = await env.DB.prepare('SELECT * FROM food_items WHERE user_id=? ORDER BY sort_order, rowid').bind(user_id).all();
      return json(results);
    }

    if (path === '/presets/save') {
      const { presets } = body;
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      await env.DB.prepare('DELETE FROM presets WHERE user_id=?').bind(user_id).run();
      for (let i = 0; i < presets.length; i++) {
        const p = presets[i];
        await env.DB.prepare('INSERT INTO presets (id,user_id,name,items,sort_order,created_at) VALUES (?,?,?,?,?,?)')
          .bind(String(p.id), user_id, p.name, JSON.stringify(p.items || []), i, p.created_at || new Date().toISOString()).run();
      }
      return json({ ok: true });
    }
    if (path === '/presets/load') {
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      const { results } = await env.DB.prepare('SELECT * FROM presets WHERE user_id=? ORDER BY sort_order, rowid').bind(user_id).all();
      return json(results);
    }

    if (path === '/meas/save') {
      const { date, weightAM, weightPM, waistNavel, waistSmallest, chest, neck, thigh, bicep, hips, restingHR, bpSystolic, bpDiastolic, dailyActivity } = body;
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      await env.DB.prepare(
        'INSERT INTO measurements (date,weightAM,weightPM,waistNavel,waistSmallest,chest,neck,thigh,bicep,hips,restingHR,bpSystolic,bpDiastolic,user_id,dailyActivity) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(date,user_id) DO UPDATE SET weightAM=excluded.weightAM,weightPM=excluded.weightPM,waistNavel=excluded.waistNavel,waistSmallest=excluded.waistSmallest,chest=excluded.chest,neck=excluded.neck,thigh=excluded.thigh,bicep=excluded.bicep,hips=excluded.hips,restingHR=excluded.restingHR,bpSystolic=excluded.bpSystolic,bpDiastolic=excluded.bpDiastolic,dailyActivity=excluded.dailyActivity'
      ).bind(date, weightAM||null, weightPM||null, waistNavel||null, waistSmallest||null, chest||null, neck||null, thigh||null, bicep||null, hips||null, restingHR||null, bpSystolic||null, bpDiastolic||null, user_id, dailyActivity||'sedentary').run();
      return json({ ok: true });
    }
    if (path === '/meas/load') {
      const { date } = body;
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      const result = await env.DB.prepare('SELECT * FROM measurements WHERE date=? AND user_id=?').bind(date, user_id).first();
      return json(result || {});
    }

    if (path === '/history/save') {
      const { date, calories, protein, weightAM, weightPM, waistNavel, waistSmallest, chest, neck, thigh, bicep, hips, restingHR, bpSystolic, bpDiastolic } = body;
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      await env.DB.prepare(
        'INSERT INTO history (date,calories,protein,weightAM,weightPM,waistNavel,waistSmallest,chest,neck,thigh,bicep,hips,restingHR,bpSystolic,bpDiastolic,user_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(date,user_id) DO UPDATE SET calories=excluded.calories,protein=excluded.protein,weightAM=excluded.weightAM,weightPM=excluded.weightPM,waistNavel=excluded.waistNavel,waistSmallest=excluded.waistSmallest,chest=excluded.chest,neck=excluded.neck,thigh=excluded.thigh,bicep=excluded.bicep,hips=excluded.hips,restingHR=excluded.restingHR,bpSystolic=excluded.bpSystolic,bpDiastolic=excluded.bpDiastolic'
      ).bind(date, calories||null, protein||null, weightAM||null, weightPM||null, waistNavel||null, waistSmallest||null, chest||null, neck||null, thigh||null, bicep||null, hips||null, restingHR||null, bpSystolic||null, bpDiastolic||null, user_id).run();
      return json({ ok: true });
    }
    if (path === '/history/load') {
      const user_id = resolveUser(body.user_id);
      if (!user_id) return authError();
      const { results } = await env.DB.prepare('SELECT * FROM history WHERE user_id=? ORDER BY date ASC').bind(user_id).all();
      return json(results);
    }

    return new Response('Not found', { status: 404, headers: cors });
  },
};
