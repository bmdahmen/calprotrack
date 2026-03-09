const GOOGLE_CLIENT_ID = '156334413688-usb68f1fldmrhic94mn925l75hnk82pk.apps.googleusercontent.com';

async function verifyGoogleToken(token) {
  const res = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${token}`);
  if (!res.ok) throw new Error('Invalid token');
  const data = await res.json();
  if (data.aud !== GOOGLE_CLIENT_ID) throw new Error('Token audience mismatch');
  if (data.exp < Date.now() / 1000) throw new Error('Token expired');
  return { google_id: data.sub, name: data.name, email: data.email, avatar: data.picture };
}

function uid() { return crypto.randomUUID().replace(/-/g, '').substring(0, 16); }

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
      'Access-Control-Allow-Headers': 'Content-Type',
    };
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });
    if (request.method !== 'POST') return new Response('Not allowed', { status: 405 });

    const url = new URL(request.url);
    const path = url.pathname;
    const body = await request.json();
    const json = (data, status = 200) => new Response(JSON.stringify(data), {
      status, headers: { 'Content-Type': 'application/json', ...cors }
    });

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
        return json({ ok: true, is_new, user });
      } catch(e) {
        return json({ error: e.message }, 401);
      }
    }

    if (path === '/auth/profile') {
      const { user_id, tdee, pro_target, age, weight_lbs, height_in, activity, goal_mode, aggressiveness, theme } = body;
      await env.DB.prepare(
        'UPDATE users SET tdee=?, pro_target=?, age=?, weight_lbs=?, height_in=?, activity=?, goal_mode=?, aggressiveness=?, theme=? WHERE id=?'
      ).bind(tdee||2100, pro_target||120, age||35, weight_lbs||170, height_in||66, activity||'sedentary', goal_mode||'deficit', aggressiveness||'moderate', theme||'dark', user_id).run();
      return json({ ok: true });
    }

    if (path === '/auth/migrate') {
      const { user_id } = body;
      await env.DB.prepare("UPDATE meals SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE measurements SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE history SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE cache SET user_id=? WHERE user_id='default'").bind(user_id).run();
      return json({ ok: true });
    }

    if (path === '/' || path === '/ai') {
      const { user_id = 'default', _type } = body;
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
      const modelCascade = {
        image:    ['claude-opus-4-6', 'claude-sonnet-4-6', 'claude-haiku-4-5-20251001'],
        food:     ['claude-haiku-4-5-20251001', 'claude-sonnet-4-6'],
        ai_coach: ['claude-haiku-4-5-20251001', 'claude-sonnet-4-6'],
        default:  ['claude-haiku-4-5-20251001', 'claude-sonnet-4-6'],
      };
      const models = modelCascade[_type] || modelCascade.default;

      const aiBody = { ...body };
      delete aiBody._type; delete aiBody.user_id;

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
          if (!overloaded) return json(lastResult); // success or non-overload error
          // Overloaded — wait then retry same model, or move to next model on last attempt
          if (attempt < 2) await new Promise(r => setTimeout(r, delay));
          delay *= 2;
        }
        // All retries on this model failed with overload — try next model
      }
      return json({ ...lastResult, error: { ...(lastResult?.error||{}), message: 'Claude is busy right now — please try again in a moment.' } });
    }

    if (path === '/usage/today') {
      const { user_id } = body;
      const today = new Date().toISOString().slice(0, 10);
      const row = await env.DB.prepare('SELECT * FROM rate_limits WHERE user_id=? AND date=?').bind(user_id, today).first();
      const user = await env.DB.prepare('SELECT lim_ai_coach, lim_images, lim_food_prompts FROM users WHERE id=?').bind(user_id).first();
      return json({ usage: row || {}, limits: user || {} });
    }

    if (path === '/cache/get') {
      const { key, user_id = 'default' } = body;
      const row = await env.DB.prepare('SELECT * FROM cache WHERE key=? AND user_id=?').bind(key, user_id).first();
      return json(row || null);
    }
    if (path === '/cache/set') {
      const { key, value, fingerprint, user_id = 'default' } = body;
      await env.DB.prepare(
        'INSERT INTO cache (key,value,fingerprint,updated_at,user_id) VALUES (?,?,?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,fingerprint=excluded.fingerprint,updated_at=excluded.updated_at'
      ).bind(key, value, fingerprint, new Date().toISOString(), user_id).run();
      return json({ ok: true });
    }

    if (path === '/meals/save') {
      const { meals, date, user_id = 'default' } = body;
      await env.DB.prepare('DELETE FROM meals WHERE date=? AND user_id=?').bind(date, user_id).run();
      for (const m of meals) {
        await env.DB.prepare('INSERT INTO meals (id,date,desc,cal,pro,time,user_id) VALUES (?,?,?,?,?,?,?)')
          .bind(String(m.id), date, m.desc, m.cal, m.pro, m.time, user_id).run();
      }
      return json({ ok: true });
    }
    if (path === '/meals/load') {
      const { date, user_id = 'default' } = body;
      const { results } = await env.DB.prepare('SELECT * FROM meals WHERE date=? AND user_id=? ORDER BY rowid').bind(date, user_id).all();
      return json(results);
    }

    if (path === '/meas/save') {
      const { date, user_id = 'default', weightAM, weightPM, waistNavel, waistSmallest, notes, dailyActivity } = body;
      await env.DB.prepare(
        'INSERT INTO measurements (date,weightAM,weightPM,waistNavel,waistSmallest,notes,user_id,dailyActivity) VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(date) DO UPDATE SET weightAM=excluded.weightAM,weightPM=excluded.weightPM,waistNavel=excluded.waistNavel,waistSmallest=excluded.waistSmallest,notes=excluded.notes,dailyActivity=excluded.dailyActivity'
      ).bind(date, weightAM||null, weightPM||null, waistNavel||null, waistSmallest||null, notes||null, user_id, dailyActivity||'sedentary').run();
      return json({ ok: true });
    }
    if (path === '/meas/load') {
      const { date, user_id = 'default' } = body;
      const result = await env.DB.prepare('SELECT * FROM measurements WHERE date=? AND user_id=?').bind(date, user_id).first();
      return json(result || {});
    }

    if (path === '/history/save') {
      const { date, user_id = 'default', calories, protein, weightAM, weightPM, waistNavel, waistSmallest, notes } = body;
      await env.DB.prepare(
        'INSERT INTO history (date,calories,protein,weightAM,weightPM,waistNavel,waistSmallest,notes,user_id) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(date) DO UPDATE SET calories=excluded.calories,protein=excluded.protein,weightAM=excluded.weightAM,weightPM=excluded.weightPM,waistNavel=excluded.waistNavel,waistSmallest=excluded.waistSmallest,notes=excluded.notes,user_id=excluded.user_id'
      ).bind(date, calories||null, protein||null, weightAM||null, weightPM||null, waistNavel||null, waistSmallest||null, notes||null, user_id).run();
      return json({ ok: true });
    }
    if (path === '/history/load') {
      const { user_id = 'default' } = body;
      const { results } = await env.DB.prepare('SELECT * FROM history WHERE user_id=? ORDER BY date ASC').bind(user_id).all();
      return json(results);
    }

    return new Response('Not found', { status: 404, headers: cors });
  },
};
