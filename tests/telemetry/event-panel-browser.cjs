// Real Grafana and Chromium, synthetic Loki responses. No production credentials
// or services are used. The VM suite separately verifies the real LogQL queries.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { randomBytes } = require('node:crypto');

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function waitFor(check, message) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    try { const value = await check(); if (value) return value; } catch {}
    await sleep(250);
  }
  throw new Error(message);
}

async function main() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'telemetry-panel-'));
  console.log('Browser test artifacts:', root);
  const children = [];
  const sockets = [];
  const password = randomBytes(24).toString('hex');
  const packagePath = process.env.TELEMETRY_GRAFANA_PACKAGE;
  const pluginPaths = JSON.parse(process.env.TELEMETRY_PLUGIN_PATHS);
  const base = { host: 'example', unit: 'user@1000.service', source: 'broker', priority: '3', event: 'Ignoring duplicate name <name>' };
  const fixtures = [base, ...['host', 'unit', 'source', 'priority'].map(key => ({ ...base, [key]: key === 'priority' ? '4' : 'different' })),
    ...Array.from({ length: 100 }, (_, index) => ({ ...base, event: `Other family ${index}: ` + 'long diagnostic detail '.repeat(30) }))];
  const mock = http.createServer((request, response) => {
    const url = new URL(request.url, 'http://localhost');
    const query = url.searchParams.get('query') || '';
    let result;
    if (url.pathname.endsWith('/labels')) result = { status: 'success', data: ['host', 'unit', 'priority'] };
    else if (url.pathname.includes('/label/')) result = { status: 'success', data: ['example'] };
    else result = { status: 'success', data: { resultType: 'vector', result: query.includes('event,details') ? fixtures.map((fixture, index) => ({
      metric: { ...fixture, details: encodeURIComponent(JSON.stringify(`{job="journal",host=${JSON.stringify(fixture.host)}} |= ${JSON.stringify(fixture.event)}`)) },
      value: [Date.now() / 1000, String(1000 - index)],
    })) : [] } };
    response.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(result));
  });
  await new Promise(resolve => mock.listen(0, '127.0.0.1', resolve));
  const probe = http.createServer();
  await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const origin = `http://127.0.0.1:${port}`;
  const mockURL = `http://127.0.0.1:${mock.address().port}`;
  async function write(file, content) {
    await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, content);
  }
  function child(command, args, name) {
    const process = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    children.push(process);
    const log = require('node:fs').createWriteStream(path.join(root, name + '.log'));
    process.stdout.pipe(log); process.stderr.pipe(log);
    return process;
  }
  const headers = { Authorization: 'Basic ' + Buffer.from('admin:' + password).toString('base64'), 'Content-Type': 'application/json' };
  async function api(endpoint, body) {
    const response = await fetch(origin + endpoint, { headers, method: body ? 'POST' : 'GET', body: body ? JSON.stringify(body) : undefined });
    assert.ok(response.ok, `Grafana API ${endpoint}: ${response.status}`);
    return response.json();
  }
  try {
    for (const dir of ['plugins', 'provisioning/datasources', 'provisioning/dashboards', 'provisioning/plugins', 'provisioning/alerting']) await fs.mkdir(path.join(root, dir), { recursive: true });
    for (const [index, plugin] of pluginPaths.entries()) await fs.symlink(plugin, path.join(root, 'plugins', String(index)));
    const dashboard = JSON.parse(await fs.readFile(process.env.TELEMETRY_DASHBOARD, 'utf8'));
    // Keep both real overview panels, without the outer repeated-host layout.
    dashboard.panels = dashboard.panels.filter(panel => [1, 15].includes(panel.id));
    await write(path.join(root, 'dashboards/fleet.json'), JSON.stringify(dashboard));
    await write(path.join(root, 'provisioning/datasources/test.yaml'), JSON.stringify({ apiVersion: 1, datasources: [
      { name: 'Logs', type: 'loki', uid: 'telemetry-loki', access: 'proxy', url: mockURL },
      { name: 'Metrics', type: 'prometheus', uid: 'telemetry-prometheus', access: 'proxy', url: mockURL },
    ] }));
    await write(path.join(root, 'provisioning/dashboards/test.yaml'), JSON.stringify({ apiVersion: 1, providers: [{ name: 'test', options: { path: path.join(root, 'dashboards') } }] }));
    await write(path.join(root, 'grafana.ini'), `[server]
http_addr = 127.0.0.1
http_port = ${port}
[paths]
data = ${root}/data
logs = ${root}/logs
plugins = ${root}/plugins
provisioning = ${root}/provisioning
[security]
admin_password = ${password}
[auth.anonymous]
enabled = false
[users]
allow_sign_up = false
[analytics]
reporting_enabled = false
check_for_updates = false
check_for_plugin_updates = false
[plugins]
preinstall_disabled = true
allow_loading_unsigned_plugins = fleet-event-families-panel
`);
    child(packagePath + '/bin/grafana', ['server', '--homepath', packagePath + '/share/grafana', '--config', path.join(root, 'grafana.ini')], 'grafana');
    await waitFor(async () => (await fetch(origin + '/api/health')).ok, 'Grafana startup');
    await api('/api/admin/users', { name: 'Viewer A', login: 'viewer-a', password });
    await api('/api/admin/users', { name: 'Viewer B', login: 'viewer-b', password });

    let browserIndex = 0;
    async function browser(user) {
      const index = browserIndex++, profile = path.join(root, 'profile-' + index);
      // Nix builds have no writable home. Give Crashpad its own directory too;
      // --user-data-dir alone does not control the crash database location.
      await fs.mkdir(path.join(profile, 'crashes'), { recursive: true });
      const chrome = child(process.env.TELEMETRY_CHROMIUM, ['--headless', '--no-sandbox', '--breakpad-dump-location=' + path.join(profile, 'crashes'), '--disable-dev-shm-usage', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0', '--user-data-dir=' + profile, '--window-size=1600,1000', 'about:blank'], 'chromium-' + index);
      const debugPort = await waitFor(async () => (await fs.readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0], 'Chromium startup');
      const targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
      const ws = new WebSocket(targets.find(target => target.type === 'page').webSocketDebuggerUrl);
      sockets.push(ws);
      await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
      let sequence = 0, failure = '';
      const pending = new Map();
      ws.onmessage = event => {
        const message = JSON.parse(event.data);
        if (message.id) {
          const waiter = pending.get(message.id);
          if (!waiter) return;
          pending.delete(message.id);
          if (message.error) waiter.reject(new Error(message.error.message)); else waiter.resolve(message.result);
        } else if (message.method === 'Fetch.requestPaused') {
          const block = failure === 'all' || (failure === 'write' && ['PATCH', 'POST'].includes(message.params.request.method));
          send(block ? 'Fetch.failRequest' : 'Fetch.continueRequest', { requestId: message.params.requestId, ...(block ? { errorReason: 'Failed' } : {}) }).catch(() => {});
        }
      };
      function send(method, params = {}) {
        const id = ++sequence;
        return new Promise((resolve, reject) => {
          const timer = setTimeout(() => { pending.delete(id); reject(new Error('Chromium request timed out: ' + method)); }, 10000);
          pending.set(id, {
            resolve: value => { clearTimeout(timer); resolve(value); },
            reject: error => { clearTimeout(timer); reject(error); },
          });
          ws.send(JSON.stringify({ id, method, params }));
        });
      }
      async function evaluate(expression) {
        const result = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
        if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || 'Browser evaluation failed');
        return result.result.value;
      }
      async function navigate(panel) {
        await send('Page.navigate', { url: `${origin}/d-solo/telemetry-fleet/fleet-telemetry?panelId=${panel}&from=now-1h&to=now` });
        await waitFor(() => evaluate('document.querySelectorAll("tbody tr[data-family-key]").length >= 100 && !document.querySelector("tbody button").disabled'), 'Event panel ready');
      }
      await send('Page.enable'); await send('Runtime.enable');
      await send('Page.navigate', { url: origin + '/login' });
      await waitFor(() => evaluate('location.origin === ' + JSON.stringify(origin)), 'Login page');
      const login = await evaluate(`fetch('/login', { method: 'POST', headers: {'Content-Type':'application/json'}, body: ${JSON.stringify(JSON.stringify({ user, password }))} }).then(r => r.status)`);
      assert.equal(login, 200, 'Viewer login');
      const account = await evaluate('fetch("/api/user").then(r => r.json())');
      const orgs = await evaluate('fetch("/api/user/orgs").then(r => r.json())');
      assert.equal(orgs.find(org => org.orgId === 1).role, 'Viewer');
      await navigate(1);
      return {
        account, evaluate, navigate, send,
        async fail(mode) { failure = mode; await send('Fetch.enable', { patterns: [{ urlPattern: '*user-storage*' }] }); },
        async recover() { failure = ''; await send('Fetch.disable'); },
        close() { ws.close(); chrome.kill(); },
      };
    }
    const key = JSON.stringify([1, base.host, base.unit, base.source, base.priority, base.event]);
    const target = `Array.from(document.querySelectorAll('tbody tr')).find(row => row.dataset.familyKey === ${JSON.stringify(key)})`;
    const rowCount = "document.querySelectorAll('tbody tr').length";
    const first = await browser('viewer-a');
    assert.equal(await first.evaluate("document.querySelectorAll('thead th').length"), 6, 'No helper columns');
    await first.evaluate("document.querySelector('[aria-label=\"Filter Event family\"]').focus()");
    await first.send('Input.insertText', { text: 'Other family 99' });
    await waitFor(() => first.evaluate(rowCount + ' === 1'), 'Column filter');
    await first.evaluate("document.querySelector('[aria-label=\"Filter Event family\"]').select()");
    await first.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Backspace', code: 'Backspace', windowsVirtualKeyCode: 8 });
    await waitFor(() => first.evaluate(rowCount + ' === 105'), 'Clear column filter');
    await first.evaluate("document.querySelectorAll('thead button')[4].click()");
    assert.equal(await first.evaluate("document.querySelector('tbody tr').children[4].textContent"), '896', 'Numeric ascending count sort');
    await first.evaluate("document.querySelectorAll('thead button')[4].click()");
    await first.evaluate(`${target}.querySelector('button').click()`);
    await waitFor(() => first.evaluate(`${target}?.dataset.dimmed === 'true'`), 'Family dimmed');
    assert.equal(await first.evaluate("document.querySelectorAll('tr[data-dimmed=true]').length"), 1, 'Scope isolation');
    assert.equal(await first.evaluate(`${target}.children[4].textContent`), '1000', 'Counts unchanged');
    assert.ok(await first.evaluate(`Number(getComputedStyle(${target}.children[3]).opacity) < 1`));
    assert.equal(await first.evaluate(`getComputedStyle(${target}.children[3]).whiteSpace`), 'nowrap');
    assert.ok(await first.evaluate(`(() => { const box = document.querySelector('[data-testid=event-scroll]'); return box.scrollHeight > box.clientHeight; })()`), 'Continuous scrolling');
    const screenshot = await first.send('Page.captureScreenshot');
    await fs.writeFile(path.join(root, 'dimmed.png'), Buffer.from(screenshot.data, 'base64'));
    const href = await first.evaluate(`${target}.querySelector('a').href`);
    const pane = JSON.parse(new URL(href).searchParams.get('panes')).events;
    assert.equal(pane.queries[0].expr, `{job="journal",host="example"} |= ${JSON.stringify(base.event)}`);
    assert.ok(Number(pane.range.to) > Number(pane.range.from), 'Explore time range');
    await first.evaluate("document.querySelector('input[type=checkbox]').click()");
    await waitFor(() => first.evaluate(rowCount + ' === 104'), 'Hide dimmed');
    assert.equal(await first.evaluate(target + ' === undefined'), true);

    const second = await browser('viewer-b');
    assert.equal(await second.evaluate("document.querySelectorAll('tr[data-dimmed=true]').length"), 0, 'Other user unaffected');
    const firstResource = 'fleet-event-families-panel:' + (first.account.uid || first.account.id);
    const status = await second.evaluate(`fetch('/apis/userstorage.grafana.app/v0alpha1/namespaces/default/user-storage/' + ${JSON.stringify(firstResource)}).then(r => r.status)`);
    assert.ok([403, 404].includes(status), 'Other user cannot read preferences');
    second.close();

    // New browser profile: neither cookies nor localStorage from the first one.
    const fresh = await browser('viewer-a');
    assert.equal(await fresh.evaluate(rowCount), 104, 'Preferences persisted in Grafana');
    await fresh.evaluate("document.querySelector('input[type=checkbox]').click()");
    await waitFor(() => fresh.evaluate(rowCount + ' === 105'), 'Show dimmed');
    await fresh.navigate(15);
    assert.equal(await fresh.evaluate(`${target}.dataset.dimmed`), 'true', 'Both panels share preferences');
    await fresh.fail('write');
    await fresh.evaluate("document.querySelector('tr[data-dimmed=false] button').click()");
    await waitFor(() => fresh.evaluate("document.querySelector('[role=alert]')?.textContent.includes('not applied')"), 'Visible save failure');
    assert.equal(await fresh.evaluate("document.querySelectorAll('tr[data-dimmed=true]').length"), 1);
    assert.equal(await fresh.evaluate("Object.keys(localStorage).filter(key => key.includes('fleet-event-families-panel')).length"), 0, 'No silent browser-only save fallback');
    await fresh.recover();
    await fresh.evaluate("document.querySelector('[role=alert] button').click()");
    await waitFor(() => fresh.evaluate("!document.querySelector('[role=alert]')"), 'Save failure recovery');
    await fresh.fail('all');
    await fresh.send('Page.reload');
    await waitFor(() => fresh.evaluate("document.querySelector('[role=alert]')?.textContent.includes('All families remain visible')"), 'Visible load failure');
    assert.equal(await fresh.evaluate(rowCount), 105);
    assert.equal(await fresh.evaluate("document.querySelectorAll('tr[data-dimmed=true]').length"), 0);
    await fresh.recover();
    await fresh.evaluate("document.querySelector('[role=alert] button').click()");
    await waitFor(() => fresh.evaluate(`${target}?.dataset.dimmed === 'true' && !${target}.querySelector('button').disabled`), 'Read failure recovery');
    await fresh.evaluate(`${target}.querySelector('button').click()`);
    await waitFor(() => fresh.evaluate(`${target}?.dataset.dimmed === 'false'`), 'Undim family');
    console.log('PASS: GUI dim/hide/undim, server persistence across profiles, user and family isolation, shared panels, scrolling, truncation, Explore links, and visible storage failures');
  } catch (error) {
    for (const name of await fs.readdir(root)) {
      if (name.startsWith('chromium-') && name.endsWith('.log')) {
        console.error(name + ':\n' + (await fs.readFile(path.join(root, name), 'utf8')).slice(-6000));
      }
    }
    throw error;
  } finally {
    for (const ws of sockets) ws.close();
    for (const process of children) process.kill();
    await new Promise(resolve => mock.close(resolve));
    await Promise.all(children.map(process => new Promise(resolve => { if (process.exitCode !== null || process.signalCode !== null) resolve(); else { process.once('exit', resolve); setTimeout(() => { process.kill('SIGKILL'); resolve(); }, 5000).unref(); } })));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
