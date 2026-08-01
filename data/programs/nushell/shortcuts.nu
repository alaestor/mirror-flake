$env.CURRENT_FLAKE = "@CURRENT_FLAKE@"
$env.STABLE_NIXPKGS = "@STABLE_NIXPKGS@"
$env.UNSTABLE_NIXPKGS = "@UNSTABLE_NIXPKGS@"

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

# ssh without verifying fingerprint or adding to knownhosts
#def sshu [...args] {
#  ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" ...$args
#}

# Resolve s.<package> and u.<package> against this flake's pinned Nixpkgs inputs.
def nix-installable [package: string] {
  if ($package | str starts-with "s.") {
    $"($env.STABLE_NIXPKGS)#($package | str substring 2..)"
  } else if ($package | str starts-with "u.") {
    $"($env.UNSTABLE_NIXPKGS)#($package | str substring 2..)"
  } else {
    $"($env.CURRENT_FLAKE)#($package)"
  }
}

# Run a package from stable Nixpkgs, unstable Nixpkgs, or this flake.
def nr [package: string, ...args: string] {
  let installable = nix-installable $package
  if ($args | is-empty) {
    nix run $installable
  } else {
    nix run $installable -- ...$args
  }
}

# Open a shell containing packages from stable/unstable Nixpkgs or this flake.
def ns [...packages: string] {
  let installables = $packages | each { |package| nix-installable $package }
  nix shell ...$installables
}
