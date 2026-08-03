use std/assert

def main [script: path, template: path] {
  let fixture = (mktemp --directory)
  mkdir ($fixture | path join "modules" "nested")
  let todo = ("TO" + "DO")
  let warn = ("WA" + "RN")
  let note = ("NO" + "TE")
  ($"# ($todo)" + "(secrets): see [credential guidance](docs/credentials.md)\nvalue = true; # " + $warn + "(security): accepted risk\n# " + $note + "(architecture): intentional design\n# " + $note + "(empty)\n# ordinary comment\n") | save ($fixture | path join "modules" "sample.nix")
  $"// ($todo): nested task\nlet text = \"($todo): not a comment\";\n" | save ($fixture | path join "modules" "nested" "sample.js")
  ^git -C $fixture init --quiet
  ^git -C $fixture config user.email "test@example.com"
  ^git -C $fixture config user.name "mkstatus test"
  ^git -C $fixture add .
  ^git -C $fixture -c commit.gpgsign=false commit --quiet -m "fixture"
  ^git -C $fixture remote add origin "git@codeberg.org:example/fixture.git"
  let output = ($fixture | path join "status.json")

  ^nu $script --template $template --root $fixture --format json --output $output
  let report = (open $output)
  let revision = (^git -C $fixture rev-parse HEAD | str trim)
  assert equal ($report.annotations | length) 5
  assert equal $report.repository "https://codeberg.org/example/fixture"
  assert equal $report.revision $revision
  assert ($report.generatedAt | str starts-with "20")
  assert equal ($report.annotations | get marker | sort) ["NOTE" "NOTE" "TODO" "TODO" "WARN"]
  assert equal ($report.annotations | get scope | sort) ["architecture" "empty" "secrets" "security" "unscoped"]
  assert equal ($report.annotations | where scope == "empty" | first | get message) ""
  assert equal ($report.annotations | where scope == "unscoped" | first | get directory) "modules/nested"
  assert equal ($report.annotations | where scope == "secrets" | first | get message) "see [credential guidance](docs/credentials.md)"
  let templateContents = ($template | open --raw)
  assert ($templateContents | str contains 'renderMarkdownLinks(item.message)')
  assert ($templateContents | str contains 'id="links"')
  assert ($templateContents | str contains 'id="generated"')
  assert ($templateContents | str contains 'generated ${data.generatedAt}')
  assert ($templateContents | str contains 'id="repository-link"')
  assert ($templateContents | str contains 'id="edit-repository"')
  assert ($templateContents | str contains 'id="revision-link"')
  assert ($templateContents | str contains 'id="edit-revision"')
  assert ($templateContents | str contains "editRepository.disabled = localLinks")
  assert ($templateContents | str contains 'src/commit/${encodeURIComponent(value)}')

  let overridden = (^nu $script --template $template --root $fixture --format json --output $output --url "https://example.com/override" --rev "override" | complete)
  assert equal $overridden.exit_code 0
  assert ($overridden.stderr | str contains "links use revision override")
  let overriddenReport = (open $output)
  assert equal $overriddenReport.repository "https://example.com/override"
  assert equal $overriddenReport.revision "override"

  let invalid = (^nu $script --template $template --root $fixture --format yaml --output $output | complete)
  assert ($invalid.exit_code != 0)
}
