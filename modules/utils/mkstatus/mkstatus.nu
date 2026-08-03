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

def normalize-repository-url [url: string] {
  let trimmed = ($url | str trim)
  let ssh = ($trimmed | parse --regex '^(?:ssh://)?git@(?<host>[^:/]+)[:/](?<path>.+)$')
  let web = if ($ssh | is-not-empty) {
    let match = ($ssh | first)
    $"https://($match.host)/($match.path)"
  } else {
    $trimmed
  }
  $web | str replace --regex '\.git/?$' ''
}

def repository-origin [root: path] {
  let result = (^git -C $root remote get-url origin | complete)
  if $result.exit_code == 0 {
    normalize-repository-url $result.stdout
  } else {
    null
  }
}

def print-link-warnings [root: path, revision: string] {
  let head = (repository-revision $root)
  if $head != null and $revision != $head {
    print --stderr $"warning: links use revision ($revision), but annotations were scanned from HEAD ($head)"
  }

  let dirty = (^git -C $root status --porcelain | complete)
  if $dirty.exit_code == 0 and ($dirty.stdout | str trim | is-not-empty) {
    print --stderr "warning: the working tree has uncommitted changes; remote links may not match annotations"
  }

  let unpushed = (^git -C $root rev-list --count '@{upstream}..HEAD' | complete)
  if $unpushed.exit_code == 0 and ($unpushed.stdout | str trim) != "0" {
    print --stderr $"warning: HEAD has ($unpushed.stdout | str trim) unpushed commit(s); remote links may not resolve yet"
  }
}

def scan [root: path] {
  let pattern = '(?i)(?:#|//|--|;|/\*+|\*|<!--)\s*(TODO|WARN|NOTE)(?:\(([A-Za-z0-9][A-Za-z0-9._-]*)\))?\s*:?\s*(.*?)\s*(?:-->)?$'
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
        message: ($matched.capture2 | default "" | str trim)
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
  --url: string
  --rev: string
] {
  if $format not-in ["html" "json"] {
    error make {msg: $"unsupported format '($format)'; expected html or json"}
  }
  if $group not-in ["scope" "directory"] {
    error make {msg: $"unsupported group '($group)'; expected scope or directory"}
  }

  let root = (repository-root $root)
  let annotations = (scan $root)
  let repository = ($url | default (repository-origin $root))
  let revision = ($rev | default (repository-revision $root))
  if $revision != null {
    print-link-warnings $root $revision
  }
  let report = {
    title: "Repository status"
    generatedAt: (date now | format date "%Y-%m-%dT%H:%M:%S%z")
    defaultGroup: $group
    repository: $repository
    revision: $revision
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
