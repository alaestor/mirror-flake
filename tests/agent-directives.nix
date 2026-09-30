{ inputs, pkgs, ... }:
let
  package = inputs.self.lib.agents.directives pkgs;
  collision = builtins.tryEval (builtins.attrNames (import (inputs.self.data.path "agents/directives/default.nix") {
    inherit pkgs;
    root = "${inputs.self}/tests/fixtures/directives-collision";
  }));
  responder = pkgs.writeShellScriptBin "directive-responder" ''
    printf 'reply completed\n' >&2
    printf 'arg=<%s>\n' "$1"
  '';
  failing = pkgs.writeShellScriptBin "directive-failing" ''
    echo 'deliberate failure' >&2
    exit 7
  '';
  mutator = pkgs.writeShellScriptBin "directive-mutator" ''
    printf '%s' "$1" > changed.txt
  '';
  fixture = pkgs.writeText "directive-fixture.json" (builtins.toJSON [
    {
      name = "reply";
      description = "Echo raw arguments";
      command = pkgs.lib.getExe responder;
    }
    {
      name = "broken";
      description = "Fail for testing";
      command = pkgs.lib.getExe failing;
    }
    {
      name = "say";
      description = "Alias for reply";
      alias = "reply";
    }
    {
      name = "change";
      description = "Write a file without context";
      command = pkgs.lib.getExe mutator;
    }
  ]);
in
assert !collision.success;
pkgs.runCommand "agent-directives-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - <<'PY'
  import json
  import os
  import subprocess
  import tempfile

  source = '${inputs.self}/data/agents/directives.py'
  fixture = '${fixture}'
  real = '${pkgs.lib.getExe package}'
  catalogue = json.loads(subprocess.run(
      [real, 'list', '--json'], text=True, capture_output=True, check=True,
  ).stdout)
  assert {'pickup', 'handoff', 'what', 'grill', 'list',
          'domain-modeling', 'grill-with-docs',
          'subagents-local',
          'subagents-manual'} <= {item['name'] for item in catalogue}
  assert not {'wait-what', 'grilling', 'grill-me', 'subagents-local-sequential'} & {item['name'] for item in catalogue}
  assert not {'docs', 'unslop', 'general-testing', 'git-conventional-commits',
              'git-howto-change-commit-message-history',
              'nix-flake-component-flake-parts'} & {item['name'] for item in catalogue}
  state_dir = os.path.join(os.getcwd(), 'directive-state')
  os.environ['XDG_STATE_HOME'] = state_dir

  def invoke(*args, payload=None, cwd=None):
      return subprocess.run(
          ['python3', source, '--catalogue', fixture, *args],
          input=json.dumps(payload) if payload is not None else None,
          text=True, capture_output=True, cwd=cwd,
      )

  def call(*args, payload=None, cwd=None):
      result = invoke(*args, payload=payload, cwd=cwd)
      assert result.returncode == 0, result.stderr
      return result.stdout

  # Only the current prompt is parsed; escaped syntax is literal.
  assert call('hook', 'codex', payload={
      'hook_event_name': 'SessionStart', 'prompt': '^^reply'
  }) == ""
  output = json.loads(call('hook', 'codex', payload={
      'hook_event_name': 'UserPromptSubmit',
      'prompt': '^^reply ^^{ say one  two\nthree}',
      'transcript': '^^broken',
  }))
  assert set(output) == {'systemMessage', 'hookSpecificOutput'}
  assert "Directive 'reply':\nreply completed" in output['systemMessage']
  assert 'arg=<' not in output['systemMessage']
  specific = output['hookSpecificOutput']
  assert set(specific) == {'hookEventName', 'additionalContext'}
  assert specific['hookEventName'] == 'UserPromptSubmit'
  assert specific['additionalContext'].startswith('=== BEGIN EXPLICIT DIRECTIVE OUTPUT ===\n')
  assert specific['additionalContext'].endswith('\n=== END EXPLICIT DIRECTIVE OUTPUT ===')
  assert 'The user invoked these directives in the current prompt.' in specific['additionalContext']
  assert specific['additionalContext'].index('[Directive reply]') < specific['additionalContext'].index('[Directive say]')
  assert 'arg=<one  two\nthree>' in specific['additionalContext']
  tabbed = json.loads(call('hook', 'claude', payload={
      'hook_event_name': 'UserPromptSubmit', 'prompt': '^^{reply\tfirst second}'
  }))['hookSpecificOutput']['additionalContext']
  assert 'arg=<first second>' in tabbed
  assert call('hook', 'claude', payload={
      'hook_event_name': 'UserPromptSubmit', 'prompt': r'\^^reply'
  }) == ""
  for harness in ('claude', 'codex'):
      unknown = invoke('hook', harness, payload={
          'hook_event_name': 'UserPromptSubmit', 'prompt': '^^replx ^^brokn'
      })
      assert unknown.returncode == 2 and unknown.stdout == ""
      assert 'Did you mean: reply?' in unknown.stderr
      assert 'Did you mean: broken?' in unknown.stderr
      assert 'Do not improvise' not in unknown.stderr
  long_output = json.loads(call('hook', 'codex', payload={
      'hook_event_name': 'UserPromptSubmit',
      'prompt': '^^{ reply ' + 'x' * 3000 + '}',
  }))
  assert 'x' * 3000 in long_output['hookSpecificOutput']['additionalContext']
  assert 'reply completed' in long_output['systemMessage']
  assert 'x' * 3000 not in long_output['systemMessage']
  assert [item['name'] for item in json.loads(call('list', '--json'))] == ['reply', 'broken', 'say', 'change']
  expanded = json.loads(call('expand', '--json', payload=[
      {'name': 'reply', 'args': 'a  b'}
  ]))
  assert expanded['ok'] is True
  assert 'arg=<a  b>' in expanded['context']
  assert 'reply completed' in expanded['receipt']
  rejected = invoke('expand', '--json', payload=[{'name': 'replx'}])
  assert rejected.returncode == 2
  assert json.loads(rejected.stdout)['ok'] is False
  direct_failure = invoke('run', 'broken')
  assert direct_failure.returncode == 7
  assert 'deliberate failure' in direct_failure.stderr

  # The packaged command executes a real directive in the selected project.
  for harness in ('claude', 'codex'):
      listed = subprocess.run([real, 'hook', harness], input=json.dumps({
          'hook_event_name': 'UserPromptSubmit', 'prompt': '^^list ^^handoff',
      }), text=True, capture_output=True)
      assert listed.returncode == 2 and listed.stdout == ""
      assert '**handoff**\n' in listed.stderr
      assert '**list** [List available directives]' in listed.stderr
      assert '**pickup** [Read the latest handoff into this turn]' in listed.stderr
      assert '**handoff** [' not in listed.stderr
      assert 'handoff instructions loaded' not in listed.stderr
      assert 'BEGIN EXPLICIT DIRECTIVE OUTPUT' not in listed.stderr
      bad_list = subprocess.run([real, 'hook', harness], input=json.dumps({
          'hook_event_name': 'UserPromptSubmit', 'prompt': '^^{ list extra }',
      }), text=True, capture_output=True)
      assert bad_list.returncode == 2 and 'list takes no arguments' in bad_list.stderr
      terminal_list = subprocess.run([real, 'run', 'list'], text=True, capture_output=True, check=True)
      assert terminal_list.stdout == ""
      assert '**list** [List available directives]' in terminal_list.stderr
      result = subprocess.run([real, 'hook', harness], input=json.dumps({
          'hook_event_name': 'UserPromptSubmit', 'prompt': '^^handoff'
      }), text=True, capture_output=True, check=True)
      response = json.loads(result.stdout)
      assert 'handoff instructions loaded.' in response['systemMessage']
      assert 'Write a local handoff' in response['hookSpecificOutput']['additionalContext']
      assert 'Write a handoff' not in response['systemMessage']
  rejected = subprocess.run([real, 'run', 'handoff', 'unexpected'],
                            text=True, capture_output=True)
  assert rejected.returncode == 2 and 'takes no arguments' in rejected.stderr
  for harness in ('claude', 'codex'):
      result = subprocess.run([real, 'hook', harness], input=json.dumps({
          'hook_event_name': 'UserPromptSubmit', 'prompt': '^^what'
      }), text=True, capture_output=True, check=True)
      response = json.loads(result.stdout)
      assert 'what instructions loaded.' in response['systemMessage']
      assert 'did not understand the last explanation' in response['hookSpecificOutput']['additionalContext']
      for name in ('grill', 'domain-modeling', 'grill-with-docs'):
          result = subprocess.run([real, 'hook', harness], input=json.dumps({
              'hook_event_name': 'UserPromptSubmit', 'prompt': '^^' + name,
          }), text=True, capture_output=True, check=True)
          context = json.loads(result.stdout)['hookSpecificOutput']['additionalContext']
          if name != 'domain-modeling':
              assert 'design tree' in context
          if name in ('domain-modeling', 'grill-with-docs'):
              assert '# CONTEXT.md Format' in context and '# ADR Format' in context
          assert 'Call the Skill tool' not in context
      for name, expected in (
          ('subagents-local', 'Only run sequential agents'),
          ('subagents-manual', 'Instead of using the subagent tooling'),
      ):
          result = subprocess.run([real, 'hook', harness], input=json.dumps({
              'hook_event_name': 'UserPromptSubmit', 'prompt': '^^' + name,
          }), text=True, capture_output=True, check=True)
          assert expected in json.loads(result.stdout)['hookSpecificOutput']['additionalContext']

  with tempfile.TemporaryDirectory() as project:
      absent = subprocess.run([real, 'hook', 'codex'], input=json.dumps({
          'hook_event_name': 'UserPromptSubmit', 'cwd': project, 'prompt': '^^pickup'
      }), text=True, capture_output=True)
      assert absent.returncode == 2 and absent.stdout == ""
      assert 'No handoff exists' in absent.stderr

      # A later typo prevents even the first mutating directive from running.
      preflight = invoke('hook', 'codex', payload={
          'hook_event_name': 'UserPromptSubmit', 'cwd': project,
          'prompt': '^^{ change before } ^^replx',
      })
      assert preflight.returncode == 2 and preflight.stdout == ""
      assert 'Did you mean: reply?' in preflight.stderr
      assert not os.path.exists(os.path.join(project, 'changed.txt'))

      # A command failure stops later commands, but cannot roll back earlier ones.
      failed = invoke('hook', 'codex', payload={
          'hook_event_name': 'UserPromptSubmit', 'cwd': project,
          'prompt': '^^{ change before } ^^broken ^^{ change after }',
      })
      assert failed.returncode == 2 and failed.stdout == ""
      assert "Directive 'change' completed" in failed.stderr
      assert 'exit 7' in failed.stderr and 'deliberate failure' in failed.stderr
      assert 'side effects may have occurred' in failed.stderr
      with open(os.path.join(project, 'changed.txt')) as handle:
          assert handle.read() == 'before '

      changed = json.loads(call('hook', 'codex', payload={
          'hook_event_name': 'UserPromptSubmit', 'cwd': project,
          'prompt': '^^{ change raw  text}',
      }))
      assert set(changed) == {'systemMessage'}
      assert "Directive 'change' completed." in changed['systemMessage']
      with open(os.path.join(project, 'changed.txt')) as handle:
          assert handle.read() == 'raw  text'
      assert call('run', 'change', 'terminal text', cwd=project) == ""
      with open(os.path.join(project, 'changed.txt')) as handle:
          assert handle.read() == 'terminal text'
      os.mkdir(os.path.join(project, '.agents'))
      with open(os.path.join(project, '.agents', 'handoff.md'), 'w') as handle:
          handle.write('Resume here.\n')
      direct = subprocess.run([real, 'run', 'pickup'], cwd=project,
                              text=True, capture_output=True, check=True)
      assert 'Resume here.' in direct.stdout
      assert direct.stdout == 'Resume here.\n'
      assert os.path.join(project, '.agents', 'handoff.md') in direct.stderr
      result = subprocess.run([real, 'hook', 'codex'], input=json.dumps({
          'hook_event_name': 'UserPromptSubmit', 'cwd': project, 'prompt': '^^pickup'
      }), text=True, capture_output=True, check=True)
      pickup = json.loads(result.stdout)
      assert 'Resume here.' in pickup['hookSpecificOutput']['additionalContext']
      assert os.path.join(project, '.agents', 'handoff.md') in pickup['systemMessage']
      assert 'Resume here.' not in pickup['systemMessage']
      os.mkdir(os.path.join(project, '.agents', 'session'))
      session = os.path.join(project, '.agents', 'session', 'later.md')
      with open(session, 'w') as handle:
          handle.write('Session handoff.\n')
      os.utime(session, (2_000_000_000, 2_000_000_000))
      result = subprocess.run([real, 'hook', 'claude'], input=json.dumps({
          'hook_event_name': 'UserPromptSubmit', 'cwd': project, 'prompt': '^^pickup'
      }), text=True, capture_output=True, check=True)
      context = json.loads(result.stdout)['hookSpecificOutput']['additionalContext']
      assert 'Session handoff.' in context and 'Resume here.' not in context
      assert session in json.loads(result.stdout)['systemMessage']

  log_path = os.path.join(state_dir, 'agent-directives', 'events.jsonl')
  with open(log_path) as handle:
      events = [json.loads(line) for line in handle]
  assert any(item['source'] == 'codex' and item['outcome'] == 'unknown' for item in events)
  assert any(item['source'] == 'terminal' and item['name'] == 'pickup' and item['outcome'] == 'ok' for item in events)
  assert any(item['name'] == 'broken' and item['outcome'] == 'failed' and item['exit_code'] == 7 for item in events)
  assert all('time' in item and 'batch' in item and 'cwd' in item for item in events)
  assert not any('args' in item or 'stdout' in item or 'stderr' in item for item in events)
  with open(log_path) as handle:
      log_text = handle.read()
  assert 'Resume here.' not in log_text and 'deliberate failure' not in log_text
  assert 'raw  text' not in log_text
  assert 'replx' not in log_text
  assert os.stat(log_path).st_mode & 0o777 == 0o600

  # A missing log cannot silently permit a side-effecting command.
  os.environ['XDG_STATE_HOME'] = fixture
  with tempfile.TemporaryDirectory() as project:
      unavailable = invoke('hook', 'codex', payload={
          'hook_event_name': 'UserPromptSubmit', 'cwd': project,
          'prompt': '^^{ change should-not-run}',
      })
      assert unavailable.returncode == 2
      assert 'Could not write directive log' in unavailable.stderr
      assert not os.path.exists(os.path.join(project, 'changed.txt'))
  PY
  touch "$out"
''
