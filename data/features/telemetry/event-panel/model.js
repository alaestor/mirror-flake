// AMD in Grafana, CommonJS in the dependency-free Node tests.
(function (factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof module === 'object') {
    module.exports = factory();
  }
})(function () {
  'use strict';

  const preferenceKey = 'event-family-view-v1';
  const defaults = () => ({ version: 1, dimmed: [], showDimmed: true });
  const severity = priority => /^[0-7]$/.test(String(priority))
    ? ['fatal', 'fatal', 'critical', 'error', 'warn', 'info', 'info', 'debug'][Number(priority)] : 'unknown';

  function parsePreferences(raw) {
    if (raw === null) return defaults();
    const value = JSON.parse(raw);
    if (value?.version !== 1 || typeof value.showDimmed !== 'boolean'
        || !Array.isArray(value.dimmed) || !value.dimmed.every(key => typeof key === 'string')) {
      throw new Error('Unrecognized dimming preferences');
    }
    return { version: 1, dimmed: [...new Set(value.dimmed)], showDimmed: value.showDimmed };
  }

  function familyKey(row) {
    // No counts, time range, panel ID or links: the same class survives refreshes
    // and matches in both the fleet overview and repeated host panels.
    return JSON.stringify([1, row.host, row.unit, row.source, row.priority, row.event]);
  }

  function rowsFromFrames(frames) {
    const rows = [];
    for (const frame of frames) {
      const field = (...names) => frame.fields.find(f => names.includes(f.name) || names.includes(f.config?.displayName));
      const event = field('event', 'Event family');
      const count = field('Count', 'Value', 'Value #A');
      if (!event || !count) throw new Error('Event query is missing the event or count field');
      const fields = {
        host: field('host', 'Host'), unit: field('unit'), source: field('source', 'Source'),
        priority: field('priority', 'Severity'), event, count,
      };
      for (let index = 0; index < frame.length; index++) {
        const row = Object.fromEntries(Object.entries(fields).map(([key, f]) => [key, String(f?.values[index] ?? '')]));
        if (!row.count.trim()) throw new Error('Event query returned an invalid count');
        row.count = Number(row.count);
        if (!Number.isFinite(row.count)) throw new Error('Event query returned an invalid count');
        row.key = familyKey(row);
        row.href = event.getLinks?.({ valueRowIndex: index })?.[0]?.href;
        rows.push(row);
      }
    }
    return rows;
  }

  function selectRows(rows, preferences, filters, sort) {
    const dimmed = new Set(preferences.dimmed);
    return rows.filter(row => (preferences.showDimmed || !dimmed.has(row.key))
      && Object.entries(filters).every(([key, value]) => (key === 'priority' ? `${row.priority} ${severity(row.priority)}` : String(row[key])).toLowerCase().includes(value.toLowerCase())))
      .sort((left, right) => {
        const order = sort.key === 'count' ? left.count - right.count
          : String(left[sort.key]).localeCompare(String(right[sort.key]), undefined, { numeric: true });
        return (sort.desc ? -order : order) || left.key.localeCompare(right.key);
      });
  }

  function createPreferenceStore() {
    let snapshot = { preferences: defaults(), ready: false, busy: false, operation: null, error: '' };
    let pending = null;
    const listeners = new Set();
    const publish = patch => {
      snapshot = { ...snapshot, ...patch };
      for (const listener of listeners) listener();
    };
    async function run(storage, change) {
      if (pending) return pending;
      publish({ busy: true, operation: change ? 'save' : 'load', error: '' });
      pending = (async () => {
        try {
          let preferences;
          // updateItem performs a fresh read and optimistic-concurrency retry.
          // Unlike setItem/getItem it does not silently fall back to localStorage
          // after a server error. Returning undefined performs a read only.
          await storage.updateItem(preferenceKey, raw => {
            preferences = parsePreferences(raw);
            if (!change) return undefined;
            preferences = change(preferences);
            return JSON.stringify(preferences);
          });
          publish({ preferences, ready: true, error: '' });
        } catch (error) {
          const patch = change ? {} : { preferences: defaults(), ready: false };
          publish({ ...patch, error: `Could not ${change ? 'save' : 'load'} dimming preferences. ${change ? 'Your change was not applied.' : 'All families remain visible.'}` });
        } finally {
          pending = null;
          publish({ busy: false, operation: null });
        }
      })();
      return pending;
    }
    return {
      subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener); },
      getSnapshot: () => snapshot,
      load: storage => run(storage),
      setDimmed: (storage, key, dim) => run(storage, preferences => ({
        ...preferences,
        dimmed: dim ? [...new Set([...preferences.dimmed, key])] : preferences.dimmed.filter(item => item !== key),
      })),
      setShowDimmed: (storage, showDimmed) => run(storage, preferences => ({ ...preferences, showDimmed })),
    };
  }

  function paginateRows(rows, requestedPage) {
    const pageSize = 100;
    const pages = Math.max(1, Math.ceil(rows.length / pageSize));
    const page = Math.max(0, Math.min(requestedPage, pages - 1));
    return { page, pages, rows: rows.slice(page * pageSize, (page + 1) * pageSize) };
  }

  return { preferenceKey, severity, parsePreferences, familyKey, rowsFromFrames, selectRows, paginateRows, createPreferenceStore };
});
