// Grafana's supported AMD entry point. Runtime dependencies come from Grafana;
// this small panel needs no npm dependencies, bundler or backend service.
define(['exports', 'react', '@grafana/data', '@grafana/runtime', '@grafana/ui', './model.js'],
  function (exports, React, grafana, runtime, ui, model) {
    'use strict';
    const h = React.createElement;
    const stores = new Map();
    const columns = [
      ['host', 'Host', '11%'], ['source', 'Source', '16%'], ['priority', 'Severity', '90px'],
      ['event', 'Event family', null], ['count', 'Count', '90px'],
    ];

    function EventFamiliesPanel({ data, height }) {
      const storage = runtime.usePluginUserStorage();
      const theme = ui.useTheme2();
      const user = runtime.config.bootData.user;
      const userKey = String(user.uid || user.id);
      if (!stores.has(userKey)) stores.set(userKey, model.createPreferenceStore());
      const store = stores.get(userKey);
      const state = React.useSyncExternalStore(store.subscribe, store.getSnapshot);
      const [filters, setFilters] = React.useState({});
      const [sort, setSort] = React.useState({ key: 'count', desc: true });
      React.useEffect(() => {
        if (!store.getSnapshot().ready) store.load(storage);
        const refresh = () => store.load(storage);
        window.addEventListener('focus', refresh);
        return () => window.removeEventListener('focus', refresh);
      }, [store, storage]);
      let rows = [], queryError = data.error?.message || '';
      try { rows = model.rowsFromFrames(data.series); }
      catch (error) { queryError = error.message; }
      const visible = model.selectRows(rows, state.preferences, filters, sort);
      const dimmed = new Set(state.preferences.dimmed);
      const disabled = !state.ready || state.busy;
      const cell = { overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis', padding: '6px 8px', borderBottom: `1px solid ${theme.colors.border.weak}`, height: 32 };
      const button = { background: 'transparent', color: 'inherit', border: `1px solid ${theme.colors.border.medium}`, borderRadius: 3, padding: '2px 6px', cursor: 'pointer' };
      const text = { ...button, width: '100%', minWidth: 0, padding: '2px 4px', fontWeight: 'normal' };
      const message = [state.error, queryError].filter(Boolean).join(' ');
      return h('div', { 'data-testid': 'event-families', style: { height, display: 'flex', flexDirection: 'column', minHeight: 0, color: theme.colors.text.primary } },
        h('div', { style: { display: 'flex', alignItems: 'center', gap: 12, padding: '0 8px 8px', flexShrink: 0 } },
          h('label', { style: { display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' } },
            h('input', { type: 'checkbox', checked: state.preferences.showDimmed, disabled,
              onChange: event => store.setShowDimmed(storage, event.target.checked) }), 'Show dimmed'),
          h('span', { style: { color: theme.colors.text.secondary } }, `${visible.length} of ${rows.length} families`),
          state.busy && h('span', { role: 'status' }, state.operation === 'save' ? 'Saving…' : 'Loading view preferences…')),
        message && h('div', { role: 'alert', style: { color: theme.colors.error.text, padding: '0 8px 8px' } },
          message, state.error && h('button', { type: 'button', disabled: state.busy, style: { ...button, marginLeft: 8 }, onClick: () => store.load(storage) }, 'Retry')),
        h('div', { 'data-testid': 'event-scroll', style: { overflow: 'auto', flex: 1, minHeight: 0 } },
          h('table', { style: { width: '100%', tableLayout: 'fixed', borderCollapse: 'separate', borderSpacing: 0 } },
            h('colgroup', null, ...columns.map(([key, , width]) => h('col', { key, style: width ? { width } : {} })), h('col', { style: { width: 112 } })),
            h('thead', { style: { position: 'sticky', top: 0, zIndex: 1, background: theme.colors.background.primary } },
              h('tr', null, ...columns.map(([key, name]) => h('th', { key, scope: 'col', style: { ...cell, textAlign: key === 'count' ? 'right' : 'left', verticalAlign: 'top' }, 'aria-sort': sort.key === key ? (sort.desc ? 'descending' : 'ascending') : 'none' },
                h('button', { type: 'button', style: { ...button, border: 0, padding: 0 }, onClick: () => setSort({ key, desc: sort.key === key ? !sort.desc : key === 'count' }) }, name, sort.key === key ? (sort.desc ? ' ↓' : ' ↑') : ''),
                h('input', { type: 'search', 'aria-label': `Filter ${name}`, placeholder: 'Filter', value: filters[key] || '',
                  style: { ...text, display: 'block', marginTop: 4 }, onChange: event => setFilters({ ...filters, [key]: event.target.value }) }))),
                h('th', { scope: 'col', style: cell }, 'Dim family'))),
            h('tbody', null, ...visible.map(row => {
              const dim = dimmed.has(row.key);
              const level = model.severity(row.priority);
              const color = /^[0-3]$/.test(row.priority) ? theme.colors.error.text
                : row.priority === '4' ? theme.colors.warning.text
                  : /^[56]$/.test(row.priority) ? theme.colors.success.text
                    : row.priority === '7' ? theme.colors.primary.text : theme.colors.text.secondary;
              return h('tr', { key: row.key, 'data-family-key': row.key, 'data-dimmed': String(dim) },
                ...columns.map(([key]) => h('td', { key, style: { ...cell, opacity: dim ? 0.35 : 1, textAlign: key === 'count' ? 'right' : 'left', color: key === 'priority' ? color : undefined }, title: key === 'priority' ? level : String(row[key]) },
                  key === 'event' && row.href ? h('a', { href: row.href, title: row.event, style: { color: theme.colors.primary.text } }, row.event)
                    : key === 'priority' ? level : String(row[key]))),
                h('td', { style: cell }, h('button', { type: 'button', style: button, disabled, 'aria-pressed': dim,
                  onClick: () => store.setDimmed(storage, row.key, !dim) }, dim ? 'Undim family' : 'Dim family')));
            })))));
    }
    exports.plugin = new grafana.PanelPlugin(EventFamiliesPanel).useFieldConfig();
  });
