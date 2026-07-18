$env.CURRENT_FLAKE = "@CURRENT_FLAKE@"

# List removable block devices.
def lsblkrm [] {
  lsblk -d -l -o NAME,SIZE,MODEL,TRAN,RM,RO --json
    | from json
    | get blockdevices
    | where rm == true
    | select name size model tran ro
}

# Run a command in a transient systemd unit that can only access localhost.
def --wrapped lo [...args: string] {
  let uid = (^id -u | str trim)
  let gid = (^id -g | str trim)
  let display = ($env.DISPLAY? | default "")
  let xauthority = ($env.XAUTHORITY? | default "")
  let systemd_args = [
    "--pty"
    "-p" "IPAddressDeny=any"
    "-p" "IPAddressAllow=localhost"
    "-p" $"User=($uid)"
    "-p" $"Group=($gid)"
    "-p" $"Environment=DISPLAY=($display)"
    "-p" $"Environment=XAUTHORITY=($xauthority)"
    "--setenv=DISPLAY"
    "--setenv=XAUTHORITY"
  ]

  sudo systemd-run ...$systemd_args ...$args
}

# Print up to `limit` spelling suggestions for each misspelled word.
def spell-check [...words: string --limit: int = 5] {
  for word in $words {
    let matches = (
      $word
        | aspell -a
        | lines
        | skip 1
        | where { str starts-with "& " }
        | parse --regex '^& \S+ \d+ \d+: (?P<suggestions>.*)$'
    )

    if not ($matches | is-empty) {
      print $word
      print (
        $matches.0.suggestions
          | split row ", "
          | first $limit
      )
    }
  }
}

# Run a package exposed by this flake.
def nr [package: string, ...args: string] {
  let installable = $"($env.CURRENT_FLAKE)#($package)"
  if ($args | is-empty) {
    nix run $installable
  } else {
    nix run $installable -- ...$args
  }
}

# Open a shell containing packages exposed by this flake.
def ns [...packages: string] {
  let installables = $packages | each { |package| $"($env.CURRENT_FLAKE)#($package)" }
  nix shell ...$installables
}
