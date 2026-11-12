// Telecomando unico: accesso con l'account e scelta del dispositivo.
// I comandi passano dal cloud (Supabase Realtime, canali privati del solo
// account) al player scelto, che risponde come il telecomando in rete locale.
(() => {
  const SUPABASE_URL = 'https://yrgdckgyiodyeqfarsye.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_ZkX94zQkvxoBO4f_BIQrcQ_bRlx6yGI';
  const KIND_ICON = {tv: '📺', phone: '📱', tablet: '📱', desktop: '💻'};

  const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: {persistSession: true, autoRefreshToken: true, detectSessionInUrl: false},
  });

  let uid = null, lobby = null, chan = null, target = null, devices = [];
  let readyResolve;
  let ready = new Promise((r) => (readyResolve = r));
  const pending = new Map();
  let seq = 0;

  const css = `
  .cl-ov{position:fixed;inset:0;z-index:50;display:flex;align-items:center;justify-content:center;
    background:rgba(5,4,14,.86);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);padding:20px}
  .cl-ov[hidden]{display:none}
  .cl-card{width:100%;max-width:420px;border-radius:26px;padding:22px;border:1px solid var(--stroke);
    background:linear-gradient(160deg,rgba(255,255,255,.11),rgba(255,255,255,.04));box-shadow:inset 0 1px 0 var(--hi)}
  .cl-card h2{margin:0 0 6px;font-size:22px}
  .cl-card p{margin:0 0 14px;color:var(--t2);font-size:14.5px;line-height:1.45}
  .cl-card input{width:100%;height:50px;border-radius:15px;border:1px solid var(--stroke);background:rgba(255,255,255,.07);
    color:var(--t1);font:inherit;font-size:16px;padding:0 15px;outline:0;margin-bottom:12px}
  .cl-btn{width:100%;height:50px;border:0;border-radius:16px;font:inherit;font-weight:650;font-size:16px;color:#fff;background:var(--neon)}
  .cl-btn.ghost{background:rgba(255,255,255,.08);margin-top:10px}
  .cl-err{color:#ff8a8a;font-size:13.5px;margin-top:10px;min-height:1em}
  .cl-dev{display:flex;align-items:center;gap:12px;width:100%;padding:14px;margin-bottom:8px;border-radius:16px;
    border:1px solid var(--stroke);background:rgba(255,255,255,.06);color:var(--t1);font:inherit;font-size:16px;text-align:left}
  .cl-dev.on{border-color:rgba(229,61,245,.6);background:rgba(255,255,255,.12)}
  .cl-dev .i{font-size:22px}
  .cl-st{margin-left:auto;font-size:12px;color:var(--t3)}
  .cl-st.on{color:#3ccf7a}
  .cl-pick{margin-left:auto;border:1px solid var(--stroke);background:rgba(255,255,255,.08);color:var(--t1);
    font:inherit;font-size:13px;border-radius:999px;padding:6px 12px;max-width:55%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  `;
  const st = document.createElement('style');
  st.textContent = css;
  document.head.appendChild(st);

  const ov = document.createElement('div');
  ov.className = 'cl-ov';
  ov.hidden = true;
  const card = document.createElement('div');
  card.className = 'cl-card';
  ov.appendChild(card);
  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
  const show = (html) => { card.innerHTML = html; ov.hidden = false; };
  const hide = () => { ov.hidden = true; };

  let pick;
  const mount = () => {
    document.body.appendChild(ov);
    const brand = document.querySelector('.brand');
    pick = document.createElement('button');
    pick.className = 'cl-pick';
    pick.textContent = 'Scegli dispositivo';
    pick.onclick = () => (uid ? showDevices() : showLogin());
    if (brand) { brand.style.display = 'flex'; brand.style.alignItems = 'center'; brand.appendChild(pick); }
    const off = document.getElementById('offline');
    if (off) off.textContent = 'Il dispositivo non risponde: controlla che sia acceso e collegato a internet, oppure scegline un altro in alto.';
  };

  // --- Accesso -------------------------------------------------------------------
  const showLogin = (email = '', err = '') => {
    show(`<h2>Telecomando unico</h2>
      <p>Accedi con lo stesso account del player: vedrai tutti i tuoi dispositivi accesi, anche fuori casa.</p>
      <input id="cl-email" type="email" inputmode="email" autocomplete="email" placeholder="nome@esempio.it" value="${esc(email)}">
      <button class="cl-btn" id="cl-send">Mandami il codice</button>
      <div class="cl-err" id="cl-err">${esc(err)}</div>`);
    const send = async () => {
      const e = document.getElementById('cl-email').value.trim().toLowerCase();
      document.getElementById('cl-send').disabled = true;
      const {error} = await sb.auth.signInWithOtp({email: e, options: {shouldCreateUser: true}});
      if (error) return showLogin(e, error.message);
      showCode(e);
    };
    document.getElementById('cl-send').onclick = send;
  };

  const showCode = (email, err = '') => {
    show(`<h2>Controlla la posta</h2>
      <p>Abbiamo mandato un codice a ${esc(email)}. Guarda anche nello spam.</p>
      <input id="cl-code" inputmode="numeric" autocomplete="one-time-code" maxlength="10" placeholder="123456">
      <button class="cl-btn" id="cl-ok">Accedi</button>
      <button class="cl-btn ghost" id="cl-back">Altra email</button>
      <div class="cl-err">${esc(err)}</div>`);
    document.getElementById('cl-back').onclick = () => showLogin(email);
    document.getElementById('cl-ok').onclick = async () => {
      const token = document.getElementById('cl-code').value.replace(/\s/g, '');
      let {error} = await sb.auth.verifyOtp({email, token, type: 'email'});
      if (error) ({error} = await sb.auth.verifyOtp({email, token, type: 'signup'}));
      if (error) return showCode(email, 'Codice sbagliato o scaduto');
      const {data} = await sb.auth.getSession();
      await signedIn(data.session);
    };
  };

  // --- Dispositivi ---------------------------------------------------------------
  // Elenco dall'account (tabella devices) più la presenza in tempo reale:
  // così i dispositivi compaiono anche se la presenza tarda ad arrivare.
  let registered = [];
  let online = new Set();
  let cloudErr = '';
  const setName = (t) => { const n = document.getElementById('name'); if (n) n.textContent = t; };

  const loadRegistered = async () => {
    const {data, error} = await sb.from('devices').select('id,name,kind,last_seen').order('last_seen', {ascending: false});
    if (!error && data) registered = data.map((d) => ({device: d.id, name: d.name, kind: d.kind, seen: d.last_seen}));
  };

  const readDevices = () => {
    const state = lobby ? lobby.presenceState() : {};
    const live = new Map();
    for (const metas of Object.values(state)) {
      for (const m of metas) if (m.device) live.set(m.device, m);
    }
    online = new Set(live.keys());
    const out = new Map(registered.map((d) => [d.device, d]));
    for (const [k, m] of live) out.set(k, {...out.get(k), ...m});
    devices = [...out.values()].sort((a, b) =>
      (online.has(b.device) - online.has(a.device)) || String(a.name).localeCompare(b.name));
  };

  const showDevices = () => {
    readDevices();
    const list = devices.length
      ? devices.map((d) => `<button class="cl-dev ${target && target.device === d.device ? 'on' : ''}" data-d="${esc(d.device)}">
          <span class="i">${KIND_ICON[d.kind] || '📺'}</span><span>${esc(d.name)}</span>
          <span class="cl-st ${online.has(d.device) ? 'on' : ''}">${online.has(d.device) ? 'acceso' : ''}</span></button>`).join('')
      : '<p>Nessun dispositivo collegato a questo account. Accendi il player e accedi da Impostazioni → Account.</p>';
    show(`<h2>Quale dispositivo?</h2><p>I dispositivi del tuo account: scegli quello da comandare.</p>${list}
      <div class="cl-err">${esc(cloudErr)}</div>
      <button class="cl-btn ghost" id="cl-out">Esci dall'account</button>`);
    card.querySelectorAll('[data-d]').forEach((b) => (b.onclick = () => {
      const d = devices.find((x) => x.device === b.dataset.d);
      if (d) choose(d);
    }));
    document.getElementById('cl-out').onclick = async () => {
      await sb.auth.signOut();
      location.reload();
    };
  };

  const choose = async (d) => {
    target = d;
    try { localStorage.setItem('cloudTarget', d.device); } catch (_) {}
    pick.textContent = (KIND_ICON[d.kind] || '📺') + ' ' + d.name;
    hide();
    setName('Connessione a ' + d.name + '…');
    if (chan) { await sb.removeChannel(chan); chan = null; }
    const c = sb.channel(`remote:${uid}:${d.device}`, {config: {private: true}});
    chan = c;
    c.on('broadcast', {event: 'res'}, (m) => {
      const p = m.payload || {};
      const w = pending.get(p.id);
      if (!w) return;
      pending.delete(p.id);
      w.resolve(p.data);
    });
    c.subscribe((s, err) => {
      if (c !== chan) return;
      if (s === 'SUBSCRIBED') readyResolve();
      else if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT') {
        setName('Cloud non raggiungibile' + (err && err.message ? ': ' + err.message : ''));
      }
    });
  };

  let decided = false;
  const decide = () => {
    if (decided) return;
    decided = true;
    readDevices();
    let saved = null;
    try { saved = localStorage.getItem('cloudTarget'); } catch (_) {}
    const on = devices.filter((x) => online.has(x.device));
    const d = devices.find((x) => x.device === saved) ||
      (on.length === 1 ? on[0] : null) ||
      (devices.length === 1 ? devices[0] : null);
    if (d) choose(d); else showDevices();
  };

  const signedIn = async (session) => {
    if (!session) return showLogin();
    uid = session.user.id;
    hide();
    pick.textContent = 'Ricerca dispositivi…';
    setName('Ricerca dei dispositivi…');
    try { await sb.realtime.setAuth(session.access_token); } catch (_) {}
    await loadRegistered();
    lobby = sb.channel(`remote:${uid}`, {config: {private: true, presence: {key: 'phone-' + Math.random().toString(36).slice(2)}}});
    lobby.on('presence', {event: 'sync'}, () => {
      readDevices();
      if (!decided) return decide();
      if (!ov.hidden && card.querySelector('.cl-dev')) showDevices();
    });
    lobby.subscribe((s, err) => {
      if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT') {
        cloudErr = 'Presenza non disponibile: ' + ((err && err.message) || s);
        console.warn('telecomando cloud', s, err);
      }
    });
    // Se la presenza non arriva, si va avanti con l'elenco dell'account.
    setTimeout(decide, 3500);
  };

  window.CLOUD = {
    async request(path, body) {
      await ready;
      const [p, qs] = path.split('?');
      const query = Object.fromEntries(new URLSearchParams(qs || ''));
      const id = ++seq + '-' + Date.now();
      const out = new Promise((resolve, reject) => {
        pending.set(id, {resolve});
        setTimeout(() => { if (pending.delete(id)) reject(new Error('timeout')); }, 6000);
      });
      await chan.send({type: 'broadcast', event: 'req', payload: {
        id, path: p, query, method: body === undefined ? 'GET' : 'POST', body: body || {},
      }});
      const data = await out;
      if (data == null) throw new Error('404');
      // I loghi dei canali sono pubblicati accanto alla pagina.
      return JSON.parse(JSON.stringify(data).replace(/"\/chlogo\//g, '"chlogo/'));
    },
  };

  const boot = async () => {
    mount();
    const {data} = await sb.auth.getSession();
    if (data.session) await signedIn(data.session); else showLogin();
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
