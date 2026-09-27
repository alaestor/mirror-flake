{ inputs, pkgs, ... }:
pkgs.runCommand "agent-context-guard-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - <<'PY'
  import json
  import os
  import subprocess

  script = '${inputs.self}/data/agents/context-guard.py'
  def run(mode, payload, enabled=None):
      env = dict(os.environ)
      env.pop('AGENT_CONTEXT_GUARD', None)
      if enabled is not None:
          env['AGENT_CONTEXT_GUARD'] = enabled
      result = subprocess.run(
          ['python3', script, mode], input=json.dumps(payload),
          text=True, capture_output=True, env=env, check=True,
      )
      return result.stdout

  # Without opt-in, every registered Claude hook is inert, including compaction.
  for event in ('SessionStart', 'PostToolUse', 'Stop', 'PreCompact'):
      payload = {'hook_event_name': event, 'session_id': 'fixture'}
      assert run('claude', payload) == ""
      assert run('claude', payload, '0') == ""
  payload = {'hook_event_name': 'PreCompact', 'session_id': 'fixture'}
  assert json.loads(run('claude', payload, '1'))['decision'] == 'block'
  # Codex enablement is session config: handler behavior must not depend on
  # whether the shared daemon inherited a flag from another wrapper.
  assert json.loads(run('codex', payload, '0'))['decision'] == 'block'

  status = {
      'model': {'display_name': 'fixture'},
      'context_window': {'total_input_tokens': 150000, 'context_window_size': 200000},
  }
  ordinary = run('statusline', status)
  guarded = run('statusline', status, '1')
  assert '150k/200k' in ordinary and '25% context remaining' in ordinary
  assert 'handoff' not in ordinary
  assert '150k/166k' in guarded and 'until handoff' in guarded
  # Alternate opted-in/default executions to expose accidental persistent state.
  assert run('statusline', status) == ordinary
  assert run('claude', payload) == ""
  # Without a guard, prefer the vendor's live window over wrapper fallback.
  os.environ['CC_CONTEXT_LIMIT'] = '200000'
  status['context_window']['context_window_size'] = 1000000
  assert '150k/1000k' in run('statusline', status)
  PY
  touch "$out"
''
