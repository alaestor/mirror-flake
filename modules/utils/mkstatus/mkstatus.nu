def html-safe-json [] {
  to json
  | str replace --all '&' '\u0026'
  | str replace --all '<' '\u003c'
  | str replace --all '>' '\u003e'
}

def repository-root [requested: path] {
  let expanded = ($requested | path expand)
  let discovered = (^git -C $expanded rev-parse --show-toplevel | complete)
  if $discovered.exit_code == 0 {
    $discovered.stdout | str trim
  } else {
    $expanded
  }
}

def repository-revision [root: path] {
  let result = (^git -C $root rev-parse HEAD | complete)
  if $result.exit_code == 0 {
    $result.stdout | str trim
  } else {
    null
  }
}

def scan [root: path] {
  let pattern = '(?i)(?:#|//|--|;|/\*+|\*|<!--)\s*(TODO|WARN|NOTE)(?:\(([A-Za-z0-9][A-Za-z0-9._-]*)\))?\s*:?\s*(.+?)\s*(?:-->)?$'
  let result = (^rg --json --line-number --no-heading --color never $pattern $root | complete)
  if $result.exit_code not-in [0 1] {
    error make {msg: ($result.stderr | str trim)}
  }

  $result.stdout
  | lines
  | where {|line| $line | is-not-empty }
  | each {|line| $line | from json }
  | where type == "match"
  | each {|event|
      let matched = ($event.data.lines.text | parse --regex $pattern | first)
      let absolute = ($event.data.path.text | path expand)
      let relative = ($absolute | path relative-to $root)
      let directory = ($relative | path dirname)
      let scope = ($matched.capture1 | default "" | str lowercase)
      {
        marker: ($matched.capture0 | str uppercase)
        scope: (if ($scope | is-empty) { "unscoped" } else { $scope })
        message: ($matched.capture2 | str trim)
        file: $relative
        line: $event.data.line_number
        directory: (if $directory == "." { "root" } else { $directory })
      }
    }
  | sort-by file line
}

def main [
  --template: path
  --root: path = "."
  --output: path = "STATUS.html"
  --format: string = "html"
  --group: string = "scope"
] {
  if $format not-in ["html" "json"] {
    error make {msg: $"unsupported format '($format)'; expected html or json"}
  }
  if $group not-in ["scope" "directory"] {
    error make {msg: $"unsupported group '($group)'; expected scope or directory"}
  }

  let root = (repository-root $root)
  let annotations = (scan $root)
  let report = {
    title: "Repository status"
    defaultGroup: $group
    revision: (repository-revision $root)
    annotations: $annotations
  }

  if $format == "json" {
    $report | to json --indent 2 | save --force $output
  } else {
    let data = ($report | html-safe-json)
    open --raw $template
    | str replace '__STATUS_DATA__' $data
    | save --force $output
  }
  print $"Wrote ($output) with ($annotations | length) annotations."
}
