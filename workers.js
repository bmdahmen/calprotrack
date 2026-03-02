const GOOGLE_CLIENT_ID = '156334413688-usb68f1fldmrhic94mn925l75hnk82pk.apps.googleusercontent.com';

// Verify Google ID token by checking Google's public endpoint
async function verifyGoogleToken(token) {
  const res = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${token}`);
  if (!res.ok) throw new Error('Invalid token');
  const data = await res.json();
  if (data.aud !== GOOGLE_CLIENT_ID) throw new Error('Token audience mismatch');
  if (data.exp < Date.now() / 1000) throw new Error('Token expired');
  return { google_id: data.sub, name: data.name, email: data.email, avatar: data.picture };
}

function uid() {
  return crypto.randomUUID().replace(/-/g, '').substring(0, 16);
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

    // ── Google Auth ───────────────────────────────────────────────────────────
    if (path === '/auth/google') {
      try {
        const { token } = body;
        const profile = await verifyGoogleToken(token);

        // Find or create user
        let user = await env.DB.prepare(
          'SELECT * FROM users WHERE google_id = ?'
        ).bind(profile.google_id).first();

        let is_new = false;
        if (!user) {
          is_new = true;
          const id = uid();
          await env.DB.prepare(
            'INSERT INTO users (id, google_id, name, email, avatar, created_at, privacy) VALUES (?,?,?,?,?,?,?)'
          ).bind(id, profile.google_id, profile.name, profile.email, profile.avatar, new Date().toISOString(), 'private').run();
          user = await env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
        }

        return json({ ok: true, is_new, user });
      } catch(e) {
        return json({ error: e.message }, 401);
      }
    }

    // ── Update profile ────────────────────────────────────────────────────────
    if (path === '/auth/profile') {
      const { user_id, privacy, tdee, pro_target, age, weight_lbs, height_in, activity } = body;
      await env.DB.prepare(
        'UPDATE users SET privacy=?, tdee=?, pro_target=?, age=?, weight_lbs=?, height_in=?, activity=? WHERE id=?'
      ).bind(privacy||'private', tdee||2100, pro_target||120, age||35, weight_lbs||170, height_in||66, activity||'sedentary', user_id).run();
      return json({ ok: true });
    }

    // ── Migrate default data to user ─────────────────────────────────────────
    if (path === '/auth/migrate') {
      const { user_id } = body;
      await env.DB.prepare("UPDATE meals SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE measurements SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE history SET user_id=? WHERE user_id='default'").bind(user_id).run();
      await env.DB.prepare("UPDATE cache SET user_id=? WHERE user_id='default'").bind(user_id).run();
      return json({ ok: true });
    }

    // ── AI proxy ──────────────────────────────────────────────────────────────
    if (path === '/' || path === '/ai') {
      const res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01' },
        body: JSON.stringify(body),
      });
      return json(await res.json());
    }

    // ── Cache ─────────────────────────────────────────────────────────────────
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

    // ── Meals ─────────────────────────────────────────────────────────────────
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

    // ── Measurements ──────────────────────────────────────────────────────────
    if (path === '/meas/save') {
      const { date, user_id = 'default', weightAM, weightPM, waistNavel, waistSmallest, notes } = body;
      await env.DB.prepare(
        'INSERT INTO measurements (date,weightAM,weightPM,waistNavel,waistSmallest,notes,user_id) VALUES (?,?,?,?,?,?,?) ON CONFLICT(date) DO UPDATE SET weightAM=excluded.weightAM,weightPM=excluded.weightPM,waistNavel=excluded.waistNavel,waistSmallest=excluded.waistSmallest,notes=excluded.notes'
      ).bind(date, weightAM||null, weightPM||null, waistNavel||null, waistSmallest||null, notes||null, user_id).run();
      return json({ ok: true });
    }
    if (path === '/meas/load') {
      const { date, user_id = 'default' } = body;
      const result = await env.DB.prepare('SELECT * FROM measurements WHERE date=? AND user_id=?').bind(date, user_id).first();
      return json(result || {});
    }

    // ── History ───────────────────────────────────────────────────────────────
    if (path === '/history/save') {
      const { date, user_id = 'default', calories, protein, weightAM, weightPM, waistNavel, waistSmallest, notes } = body;
      await env.DB.prepare(
        'INSERT INTO history (date,calories,protein,weightAM,weightPM,waistNavel,waistSmallest,notes,user_id) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(user_id,date) DO UPDATE SET calories=excluded.calories,protein=excluded.protein,weightAM=excluded.weightAM,weightPM=excluded.weightPM,waistNavel=excluded.waistNavel,waistSmallest=excluded.waistSmallest,notes=excluded.notes'
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
