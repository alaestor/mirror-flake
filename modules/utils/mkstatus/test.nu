use std/assert

def main [script: path, template: path] {
  let fixture = (mktemp --directory)
  mkdir ($fixture | path join "modules" "nested")
  let todo = ("TO" + "DO")
  let warn = ("WA" + "RN")
  ($"# ($todo)" + "(secrets): move credential\nvalue = true; # " + $warn + "(security): accepted risk\n# ordinary comment\n") | save ($fixture | path join "modules" "sample.nix")
  $"// ($todo): nested task\nlet text = \"($todo): not a comment\";\n" | save ($fixture | path join "modules" "nested" "sample.js")
  let output = ($fixture | path join "status.json")

  ^nu $script --template $template --root $fixture --format json --output $output
  let report = (open $output)
  assert equal ($report.annotations | length) 3
  assert equal ($report.annotations | get marker | sort) ["TODO" "TODO" "WARN"]
  assert equal ($report.annotations | get scope | sort) ["secrets" "security" "unscoped"]
  assert equal ($report.annotations | where scope == "unscoped" | first | get directory) "modules/nested"

  let invalid = (^nu $script --template $template --root $fixture --format yaml --output $output | complete)
  assert ($invalid.exit_code != 0)
}
