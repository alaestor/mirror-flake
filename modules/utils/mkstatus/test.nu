use std/assert

def main [script: path, template: path] {
  let fixture = (mktemp --directory)
  mkdir ($fixture | path join "modules" "nested")
  let todo = ("TO" + "DO")
  let warn = ("WA" + "RN")
  ($"# ($todo)" + "(secrets): see [credential guidance](docs/credentials.md)\nvalue = true; # " + $warn + "(security): accepted risk\n# NOTE(architecture): intentional design\n# NOTE(empty)\n# ordinary comment\n") | save ($fixture | path join "modules" "sample.nix")
  $"// ($todo): nested task\nlet text = \"($todo): not a comment\";\n" | save ($fixture | path join "modules" "nested" "sample.js")
  ^git -C $fixture init --quiet
  ^git -C $fixture config user.email "test@example.com"
  ^git -C $fixture config user.name "mkstatus test"
  ^git -C $fixture add .
  ^git -C $fixture -c commit.gpgsign=false commit --quiet -m "fixture"
  let output = ($fixture | path join "status.json")

  ^nu $script --template $template --root $fixture --format json --output $output
  let report = (open $output)
  let revision = (^git -C $fixture rev-parse HEAD | str trim)
  assert equal ($report.annotations | length) 5
  assert equal $report.revision $revision
  assert equal ($report.annotations | get marker | sort) ["NOTE" "NOTE" "TODO" "TODO" "WARN"]
  assert equal ($report.annotations | get scope | sort) ["architecture" "empty" "secrets" "security" "unscoped"]
  assert equal ($report.annotations | where scope == "empty" | first | get message) ""
  assert equal ($report.annotations | where scope == "unscoped" | first | get directory) "modules/nested"
  assert equal ($report.annotations | where scope == "secrets" | first | get message) "see [credential guidance](docs/credentials.md)"
  let templateContents = ($template | open --raw)
  assert ($templateContents | str contains 'renderMarkdownLinks(item.message)')
  assert ($templateContents | str contains 'id="links"')
  assert ($templateContents | str contains 'id="revision-link"')
  assert ($templateContents | str contains 'id="edit-revision"')
  assert ($templateContents | str contains 'id="reset-revision"')
  assert ($templateContents | str contains "editRevision.disabled = localLinks")
  assert ($templateContents | str contains "revisionLink.classList.toggle('disabled', localLinks)")
  assert ($templateContents | str contains 'https://codeberg.org/alaestor/flake/src/commit/${encodeURIComponent(value)}')

  let invalid = (^nu $script --template $template --root $fixture --format yaml --output $output | complete)
  assert ($invalid.exit_code != 0)
}
