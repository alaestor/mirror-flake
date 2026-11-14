const { test } = require('node:test');
const assert = require('node:assert/strict');
const model = require(process.env.EVENT_PANEL_MODEL || '../../data/features/telemetry/event-panel/model.js');

const row = { host: 'example', unit: 'user@1000.service', source: 'broker', priority: '3', event: 'Duplicate <name>', count: 12 };
const defaultView = () => model.parsePreferences(null);

// An atomic shared backend, with separate stores representing separate tabs.
function backend() {
  let raw = null;
  let queue = Promise.resolve();
  return {
    async updateItem(key, change) {
      assert.equal(key, model.preferenceKey);
      const task = queue.then(() => { const next = change(raw); if (next !== undefined) raw = next; });
      queue = task.catch(() => {});
      await task;
    },
    read: () => model.parsePreferences(raw),
  };
}

test('family identity is stable but includes every grouping dimension', () => {
  const key = model.familyKey(row);
  assert.equal(model.familyKey({ ...row, count: 999, href: '/different-range' }), key);
  for (const field of ['host', 'unit', 'source', 'priority', 'event']) {
    assert.notEqual(model.familyKey({ ...row, [field]: row[field] + 'changed' }), key);
  }
  assert.notEqual(model.familyKey({ ...row, host: 'a,b', unit: 'c' }), model.familyKey({ ...row, host: 'a', unit: 'b,c' }));
});

test('preferences reject malformed or future state instead of overwriting it', () => {
  assert.deepEqual(defaultView(), { version: 1, dimmed: [], showDimmed: true });
  for (const raw of ['broken', '{}', 'null', '{"version":2}', '{"version":1,"dimmed":[3],"showDimmed":true}']) {
    assert.throws(() => model.parsePreferences(raw));
  }
});

test('missing or invalid severity stays unknown rather than becoming fatal', () => {
  for (const value of ['', null, undefined, '9', 'invalid']) assert.equal(model.severity(value), 'unknown');
  assert.equal(model.severity('3'), 'error');
});

test('frame conversion retains raw severity, scoped identity, count and exact data link', () => {
  const fields = Object.entries(row).map(([name, value]) => ({ name, values: [value] }));
  const event = fields.find(f => f.name === 'event');
  event.getLinks = ({ valueRowIndex }) => [{ href: '/explore?row=' + valueRowIndex }];
  fields.find(f => f.name === 'count').name = 'Value #A';
  const [result] = model.rowsFromFrames([{ length: 1, fields }]);
  assert.equal(result.count, 12);
  assert.equal(result.priority, '3');
  assert.equal(result.href, '/explore?row=0');
  assert.equal(result.key, model.familyKey(row));
  assert.throws(() => model.rowsFromFrames([{ length: 1, fields: [] }]));
  fields.find(f => f.name === 'Value #A').values = [null];
  assert.throws(() => model.rowsFromFrames([{ length: 1, fields }]), /invalid count/);
});

test('hiding dims does not mutate rows or counts; filters and numeric sort still work', () => {
  const rows = [row, { ...row, event: 'Unexpected failure', count: 2 }].map(r => ({ ...r, key: model.familyKey(r) }));
  const preferences = { ...defaultView(), dimmed: [rows[0].key] };
  const sort = { key: 'count', desc: true };
  assert.equal(model.selectRows(rows, preferences, {}, sort).length, 2);
  preferences.showDimmed = false;
  assert.deepEqual(model.selectRows(rows, preferences, {}, sort), [rows[1]]);
  assert.deepEqual(model.selectRows(rows, defaultView(), { event: 'UNEXPECTED' }, sort), [rows[1]]);
  assert.equal(model.selectRows(rows, defaultView(), { priority: 'error' }, sort).length, 2);
  assert.equal(rows[0].count, 12);
});

test('saved dimming and view state survive a fresh store and undim restores visibility', async () => {
  const storage = backend(), store = model.createPreferenceStore();
  await store.load(storage);
  await store.setDimmed(storage, model.familyKey(row), true);
  await store.setShowDimmed(storage, false);
  const reloaded = model.createPreferenceStore();
  await reloaded.load(storage);
  assert.deepEqual(reloaded.getSnapshot().preferences, storage.read());
  assert.equal(reloaded.getSnapshot().preferences.showDimmed, false);
  await reloaded.setDimmed(storage, model.familyKey(row), false);
  assert.deepEqual(storage.read().dimmed, []);
});

test('independent tabs merge changes using fresh atomic updates', async () => {
  const storage = backend(), first = model.createPreferenceStore(), second = model.createPreferenceStore();
  await Promise.all([first.load(storage), second.load(storage)]);
  await Promise.all([first.setDimmed(storage, 'first', true), second.setDimmed(storage, 'second', true)]);
  assert.deepEqual(storage.read().dimmed.sort(), ['first', 'second']);
  await first.load(storage);
  assert.deepEqual(first.getSnapshot().preferences, storage.read());
});

test('failed reads keep all families visible; failed writes are not applied or reported saved', async () => {
  const broken = { async updateItem() { throw new Error('offline'); } };
  const store = model.createPreferenceStore();
  await store.load(broken);
  assert.equal(store.getSnapshot().ready, false);
  assert.equal(store.getSnapshot().preferences.showDimmed, true);
  assert.match(store.getSnapshot().error, /Could not load/);
  const storage = backend();
  await store.load(storage);
  await store.setDimmed(broken, 'first', true);
  assert.deepEqual(store.getSnapshot().preferences.dimmed, []);
  assert.match(store.getSnapshot().error, /not applied/);
  assert.equal(store.getSnapshot().busy, false);
  await store.load(storage);
  assert.equal(store.getSnapshot().error, '');
});
