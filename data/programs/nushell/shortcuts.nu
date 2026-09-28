# List removable block devices.
def lsblkrm [] {
  lsblk -d -l -o NAME,SIZE,MODEL,TRAN,RM,RO --json
    | from json
    | get blockdevices
    | where rm == true
    | select name size model tran ro
}

# These Nushell commands are a prototype, not the long-term implementation.
# Keep the wrappers independent: `lo` reads `.lo.toml` and applies
# systemd's IPAddressAllow policy, while `bu` reads `.bu.toml` and builds
# Bubblewrap filesystem arguments. `lobu` can compose them later. The config
# files are intentionally small TOML descriptions, not native systemd or
# Bubblewrap config files. The eventual reusable implementation should be
# packaged as descriptive scripts, likely with Nix writeShellApplication;
# this flake can keep the short `lo` and `bu` aliases.
#
# `.lo.toml` uses `allow` for additional IP addresses or CIDRs. Localhost
# remains allowed by default. `.bu.toml` uses `[[mount]]` entries with
# `hostPath`, `sandboxPath`, and `mode`. `bind` writes through to the host
# path. `tmp-overlay` exposes a writable temporary overlay whose changes are
# discarded when the command exits. Paths must be absolute; tmp-overlay
# requires a directory. A sandboxPath must already exist, or lie under
# `/tmp`, where Bubblewrap can create it. Without `.bu.toml`, `bu` exposes
# the host filesystem read-only, except for a private `/tmp`.
def lo-init [] {
  let path = ".lo.toml"
  let template = '# Additional IP addresses or CIDRs allowed by `lo`.
# Localhost is always allowed.
allow = ["192.168.1.20", "192.168.1.0/24"]
'

  if ($path | path exists) {
    error make {msg: $"($path) already exists; refusing to overwrite it"}
  }

  $template | save --raw $path
  print $"Wrote ($path)"
}

def bu-init [] {
  let path = ".bu.toml"
  let template = '# Mount host paths at paths visible inside the Bubblewrap sandbox.
# `bind` writes through to the host path.
# `tmp-overlay` needs a directory and discards writes when the command exits.
# The sandbox path must already exist, or be under `/tmp`.
[[mount]]
hostPath = "/path/on/host"
sandboxPath = "/tmp/path/in/sandbox"
mode = "bind" # `bind` or `tmp-overlay`

# [[mount]]
# hostPath = "/path/to/cache"
# sandboxPath = "/tmp/cache"
# mode = "tmp-overlay"
'

  if ($path | path exists) {
    error make {msg: $"($path) already exists; refusing to overwrite it"}
  }

  $template | save --raw $path
  print $"Wrote ($path)"
}

# Run a command in a transient systemd unit, allowing localhost and the IPs
# listed in `.lo.toml`.
def --wrapped lo [...args: string] {
  if ($args | is-empty) {
    error make {msg: "lo requires a command"}
  }

  let allowed = if (".lo.toml" | path exists) {
    let config = open .lo.toml
    if $config.allow? == null { [] } else { $config.allow }
  } else {
    []
  }
  if not ($allowed | describe | str starts-with "list") {
    error make {msg: ".lo.toml: allow must be a list of IP addresses or CIDRs"}
  }

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

  mut allow_args = []
  for ip in $allowed {
    if (($ip | describe) != "string") or ($ip | is-empty) {
      error make {msg: ".lo.toml: every allow entry must be a nonempty string"}
    }
    $allow_args = ($allow_args ++ ["-p" $"IPAddressAllow=($ip)"])
  }

  sudo systemd-run ...$systemd_args ...$allow_args -- ...$args
}

# Expose the host filesystem read-only, then add the configured writable
# mounts. Bubblewrap leaves networking alone so `lo` can supply that policy.
def --wrapped bu [...args: string] {
  if ($args | is-empty) {
    error make {msg: "bu requires a command"}
  }

  let mounts = if (".bu.toml" | path exists) {
    let config = open .bu.toml
    if $config.mount? == null { [] } else { $config.mount }
  } else {
    []
  }
  let mount_type = $mounts | describe
  if not (($mount_type | str starts-with "table") or ($mount_type == "list<any>")) {
    error make {msg: ".bu.toml: mount must be a list of tables"}
  }

  mut bwrap_args = ["--ro-bind" "/" "/" "--dev" "/dev" "--proc" "/proc" "--tmpfs" "/tmp"]
  if ($env.PWD | str starts-with "/tmp/") {
    $bwrap_args = ($bwrap_args ++ ["--ro-bind" $env.PWD $env.PWD])
  }
  for mount in $mounts {
    let host_path = $mount.hostPath?
    let sandbox_path = $mount.sandboxPath?
    let mode = $mount.mode?
    if (($host_path | describe) != "string") or (($sandbox_path | describe) != "string") {
      error make {msg: ".bu.toml: each mount needs string hostPath and sandboxPath"}
    }
    if not (($host_path | str starts-with "/") and ($sandbox_path | str starts-with "/")) {
      error make {msg: ".bu.toml: mount paths must be absolute"}
    }
    if not ($host_path | path exists) {
      error make {msg: $".bu.toml: hostPath does not exist: ($host_path)"}
    }

    match $mode {
      "bind" => { $bwrap_args = ($bwrap_args ++ ["--bind" $host_path $sandbox_path]) }
      "tmp-overlay" => {
        if ($host_path | path type) != "dir" {
          error make {msg: $".bu.toml: tmp-overlay needs a directory: ($host_path)"}
        }
        $bwrap_args = ($bwrap_args ++ ["--overlay-src" $host_path "--tmp-overlay" $sandbox_path])
      }
      _ => { error make {msg: ".bu.toml: mode must be bind or tmp-overlay"} }
    }
  }

  bwrap ...$bwrap_args -- ...$args
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
