(function () {
  const API = '/api';
  const TOKEN_KEY = 'ksd_token';

  const TITLES = {
    dashboard: 'Обзор',
    domains: 'Домены',
    upstreams: 'Upstream-профили',
    test: 'Проверка DNS',
    settings: 'Настройки',
  };

  let state = { domains: [], status: null, yaml: '' };
  let selectedUpstream = null;

  function token() {
    return localStorage.getItem(TOKEN_KEY) || '';
  }

  function headers() {
    const h = { Accept: 'application/json' };
    const t = token();
    if (t) h.Authorization = 'Bearer ' + t;
    return h;
  }

  async function api(path, opts = {}) {
    const res = await fetch(API + path, {
      ...opts,
      headers: { ...headers(), ...(opts.headers || {}) },
    });
    if (res.status === 401) {
      document.getElementById('auth-gate').classList.remove('hidden');
      throw new Error('unauthorized');
    }
    const text = await res.text();
    try {
      return JSON.parse(text);
    } catch {
      return { ok: false, raw: text };
    }
  }

  function toast(msg) {
    const t = document.getElementById('toast');
    t.textContent = '✓ ' + msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), 2800);
  }

  function setStatusBadge(running) {
    const el = document.getElementById('status-badge');
    el.textContent = running ? 'SmartDNS работает' : 'SmartDNS остановлен';
    el.className = 'badge badge-dot ' + (running ? 'badge-running' : 'badge-stopped');
  }

  async function refreshStatus() {
    const s = await api('/status');
    state.status = s;
    const running = s.smartdns && s.smartdns.running;
    setStatusBadge(running);
    document.getElementById('stat-status').textContent = running ? 'Работает' : 'Остановлен';
    document.getElementById('stat-status').style.color = running ? 'var(--success)' : 'var(--danger)';
    document.getElementById('stat-pid').textContent = 'PID ' + (s.smartdns?.pid || '—');
    document.getElementById('stat-domains').textContent = s.domains ?? '—';
    document.getElementById('stat-url').textContent = s.url || '—';
    document.getElementById('topbar-sub').textContent = s.url ? s.url.replace('http://', '') + ' · lighttpd + CGI' : 'Keenetic Split DNS';
    if (s.web_port) document.getElementById('sidebar-port').textContent = s.web_port;
    const logEl = document.getElementById('log-container');
    if (logEl) {
      const lines = Array.isArray(s.logs) ? s.logs : [];
      if (lines.length) {
        logEl.innerHTML = lines
          .map((msg) => {
            const m = String(msg);
            const time = m.match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/);
            return `<motion class="log-line"><span class="log-time">${esc(time ? time[1] : '—')}</span> ${esc(time ? m.slice(time[1].length).trim() : m)}</div>`;
          })
          .join('');
      } else if (s.last_apply) {
        logEl.innerHTML = `<motion class="log-line"><span class="log-time">—</span> ${esc(s.last_apply)}</motion>`;
      } else {
        logEl.innerHTML = '<div class="log-line"><span class="log-time">—</span> Журнал пуст — нажмите «Применить»</motion>';
      }
    }
  }

  async function refreshDomains() {
    const d = await api('/domains');
    state.domains = d.domains || [];
    renderDomainsTable();
    renderUpstreams();
    const ups = new Set(state.domains.map((x) => x.upstream));
    document.getElementById('stat-upstreams').textContent = ups.size;
    document.getElementById('stat-upstream-names').textContent = [...ups].join(', ') || '—';
  }

  function renderDomainsTable(filter = '') {
    const tbody = document.querySelector('#domains-table tbody');
    const q = filter.toLowerCase();
    tbody.innerHTML = state.domains
      .filter((x) => !q || x.domain.includes(q))
      .map(
        (x) =>
          `<tr><td><code>${esc(x.domain)}</code></td><td>${esc(x.group)}</td><td><span class="badge-policy">${esc(x.upstream)}</span></td></tr>`
      )
      .join('');
  }

  function renderUpstreams() {
    const ups = [...new Set(state.domains.map((x) => x.upstream))];
    const defaultUp = 'isp-default';
    if (!ups.includes(defaultUp)) ups.push(defaultUp);
    const list = document.getElementById('upstream-list');
    list.innerHTML = ups
      .map(
        (u) =>
          `<li data-up="${esc(u)}" class="${u === selectedUpstream ? 'active' : ''}"><code>${esc(u)}</code></li>`
      )
      .join('');
    list.querySelectorAll('li').forEach((li) => {
      li.addEventListener('click', () => selectUpstream(li.dataset.up));
    });
    if (!selectedUpstream && ups.length) selectUpstream(ups[0]);
  }

  function selectUpstream(id) {
    selectedUpstream = id;
    document.querySelectorAll('#upstream-list li').forEach((li) => {
      li.classList.toggle('active', li.dataset.up === id);
    });
    document.getElementById('upstream-detail-title').textContent = id + ' — домены';
    const rows = state.domains.filter((x) => x.upstream === id);
    document.getElementById('upstream-domains-tbody').innerHTML = rows
      .map((x) => `<tr><td><code>${esc(x.domain)}</code></td><td>${esc(x.group)}</td></tr>`)
      .join('') || '<tr><td colspan="2" class="hint">Нет доменов (остальной трафик — default upstream)</td></tr>';
    document.getElementById('upstream-detail-body').innerHTML =
      '<p class="hint">Профили задаются в config.yaml → upstreams. Домены группы ru-services используют yandex-dot по умолчанию.</p>';
  }

  async function loadConfigYaml() {
    const res = await fetch(API + '/config', { headers: headers() });
    if (res.status === 401) {
      document.getElementById('auth-gate').classList.remove('hidden');
      return;
    }
    state.yaml = await res.text();
    document.getElementById('config-yaml').value = state.yaml;
  }

  async function applyConfig() {
    await api('/reload', { method: 'POST' });
    toast('Конфиг применён, SmartDNS перезагружен');
    await refreshAll();
  }

  async function saveConfig() {
    const yaml = document.getElementById('config-yaml').value;
    await api('/config', {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain' },
      body: yaml,
    });
    toast('YAML сохранён — нажмите Применить');
  }

  async function runTest() {
    const domain = document.getElementById('test-domain').value.trim() || 'vk.com';
    const type = document.getElementById('test-type').value;
    const r = await api('/test?domain=' + encodeURIComponent(domain) + '&type=' + type);
    const out = document.getElementById('test-output');
    if (r.output) {
      out.textContent = r.output.replace(/\\n/g, '\n');
      document.getElementById('test-latency').textContent = (r.ms || '—') + ' ms';
    } else {
      out.textContent = JSON.stringify(r, null, 2);
    }
  }

  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/"/g, '&quot;');
  }

  async function refreshAll() {
    await refreshStatus();
    await refreshDomains();
  }

  // Nav
  document.querySelectorAll('.nav-item').forEach((btn) => {
    btn.addEventListener('click', () => {
      const tab = btn.dataset.tab;
      document.querySelectorAll('.nav-item').forEach((b) => b.classList.remove('active'));
      document.querySelectorAll('.panel').forEach((p) => p.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById('panel-' + tab).classList.add('active');
      document.getElementById('page-title').textContent = TITLES[tab];
      if (tab === 'settings') loadConfigYaml();
    });
  });

  document.getElementById('domain-search')?.addEventListener('input', (e) => renderDomainsTable(e.target.value));
  document.getElementById('theme-btn').addEventListener('click', () => {
    const html = document.documentElement;
    html.dataset.theme = html.dataset.theme === 'dark' ? 'light' : 'dark';
  });

  ['apply-top', 'apply-settings'].forEach((id) => {
    document.getElementById(id)?.addEventListener('click', () => applyConfig().catch((e) => toast(e.message)));
  });

  document.getElementById('save-config')?.addEventListener('click', () => saveConfig().catch((e) => toast(e.message)));
  document.getElementById('run-test')?.addEventListener('click', () => runTest().catch((e) => toast(e.message)));
  document.querySelectorAll('.quick-test').forEach((b) => {
    b.addEventListener('click', () => {
      document.getElementById('test-domain').value = b.dataset.d;
      runTest();
    });
  });

  document.getElementById('auth-save')?.addEventListener('click', () => {
    const v = document.getElementById('auth-token-input').value.trim();
    if (v) {
      localStorage.setItem(TOKEN_KEY, v);
      document.getElementById('auth-gate').classList.add('hidden');
      refreshAll();
    }
  });

  document.getElementById('save-token')?.addEventListener('click', () => {
    const v = document.getElementById('settings-token').value.trim();
    if (v) {
      localStorage.setItem(TOKEN_KEY, v);
      toast('Токен сохранён');
    }
  });

  document.getElementById('btn-add-upstream')?.addEventListener('click', () => {
    toast('Профили upstream задаются в config.yaml → upstreams');
    document.querySelector('.nav-item[data-tab="settings"]')?.click();
  });

  document.getElementById('btn-export-domains')?.addEventListener('click', () => {
    const text = state.domains.map((x) => x.domain).join('\n');
    const a = document.createElement('a');
    a.href = 'data:text/plain;charset=utf-8,' + encodeURIComponent(text);
    a.download = 'domains.txt';
    a.click();
  });

  // Init
  if (token()) {
    document.getElementById('auth-gate').classList.add('hidden');
    document.getElementById('settings-token').value = token();
  }
  refreshAll().catch(() => {});
})();
