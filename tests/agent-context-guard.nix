{ inputs, pkgs, ... }:
pkgs.runCommand "agent-context-guard-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - <<'PY'
  import json
  import os
  from pathlib import Path
  import subprocess
  import tempfile

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

  # Test the guard's decision, not just its status-line arithmetic. Each
  # harness must use the latest live request, ignoring cumulative history.
  with tempfile.TemporaryDirectory() as temporary:
      root = Path(temporary)
      os.environ['XDG_STATE_HOME'] = str(root / 'state')
      os.environ['CC_CONTEXT_LIMIT'] = '200000'
      os.environ.pop('AGENT_CONTEXT_THRESHOLD', None)
      for mode in ('claude', 'codex'):
          project = root / mode
          nested = project / 'nested'
          nested.mkdir(parents=True)
          handoffs = project / '.agents/session'
          handoffs.mkdir(parents=True)
          stale = handoffs / 'old.md'
          stale.write_text('Earlier session')
          os.utime(stale, (1, 1))
          transcript = root / (mode + '.jsonl')

          def usage(tokens):
              if mode == 'claude':
                  return {'message': {'usage': {
                      'input_tokens': 1000, 'cache_read_input_tokens': tokens - 1000,
                  }}}
              return {'payload': {'info': {
                  'model_context_window': 200000,
                  'last_token_usage': {'input_tokens': tokens - 1000, 'output_tokens': 1000},
                  'total_token_usage': {'input_tokens': 9000000},
              }}}

          def write_usage(tokens):
              transcript.write_text(json.dumps(usage(190000)) + '\nmalformed\n'
                                    + json.dumps(usage(tokens)) + '\n')

          payload = {
              'session_id': mode, 'cwd': str(project),
              'transcript_path': str(transcript), 'hook_event_name': 'PostToolUse',
          }
          write_usage(10000)
          assert run(mode, payload, '1') == "", mode
          write_usage(166000)
          requested = json.loads(run(mode, payload, '1'))
          context = requested['hookSpecificOutput']['additionalContext']
          assert str(handoffs) in context, context
          assert '166,000' in context, context
          assert 'continue' not in requested and 'decision' not in requested, requested
          # A changed working directory must not relocate this session's handoff.
          payload['cwd'] = str(nested)
          assert run(mode, payload, '1') == "", mode
          current = handoffs / 'current.md'
          current.write_text('Current session handoff')
          # Explicit mtimes avoid filesystem timestamp-resolution races.
          os.utime(current, (2000000000, 2000000000))
          halted = json.loads(run(mode, payload, '1'))
          if mode == 'claude':
              assert halted['continue'] is False, halted
          else:
              assert halted['decision'] == 'block', halted
          payload['hook_event_name'] = 'Stop'
          assert run(mode, payload, '1') == "", mode

      # Stop can request a handoff without a preceding tool, but may not loop.
      payload['session_id'] = 'stop-only'
      payload['cwd'] = str(nested)
      assert json.loads(run('codex', payload))['hookSpecificOutput']['hookEventName'] == 'Stop'
      assert run('codex', payload) == ""
  PY
  touch "$out"
''
