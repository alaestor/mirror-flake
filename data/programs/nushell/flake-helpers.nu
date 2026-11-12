$env.LOCAL_FLAKE = "@LOCAL_FLAKE@"

# Refresh only the plugin source, not the whole host or Caddy executable.
def nup-refresh-caddy [] {
  let target = ".#nixosConfigurations.lanser.config.services.caddy.package.src"
  let hash_file = "data/serve/caddy/source.json"
  let original = open --raw $hash_file
  let hash = ($original | from json | get hash)
  let evaluation = (^nix eval --raw $"($target).drvPath" | complete)
  if $evaluation.exit_code != 0 {
    print --stderr --no-newline $evaluation.stderr
    error make {msg: "Could not evaluate Caddy's plugin source"}
  }
  let drv = ($evaluation.stdout | str trim)
  let build = (^nix build --no-link $target | complete)
  print --stderr --no-newline $build.stderr
  if $build.exit_code == 0 { return }

  # Never accept a hash from a dependency failure or an unrelated diagnostic.
  let mismatches = ($build.stderr
    | parse --regex "error: hash mismatch in fixed-output derivation '(?<drv>[^']+)':\\s+specified:\\s+(?<specified>\\S+)\\s+got:\\s+(?<got>sha256-[A-Za-z0-9+/]{43}=)"
    | where drv == $drv and specified == $hash)
  if ($mismatches | length) != 1 {
    error make {msg: "Caddy source build failed without a matching hash mismatch; hash left unchanged"}
  }
  let replacement = ($mismatches | first | get got)
  if $replacement == $hash {
    error make {msg: "Caddy reported the existing source hash; hash left unchanged"}
  }
  {hash: $replacement} | to json | save --force $hash_file
  print $"Updated Caddy plugin source hash to ($replacement); verifying..."
  try {
    let verification = (^nix build --no-link $target | complete)
    print --stderr --no-newline $verification.stderr
    if $verification.exit_code != 0 {
      error make {msg: "Caddy source verification failed"}
    }
  } catch {|err|
    $original | save --force $hash_file
    error make {msg: $"($err.msg); restored the previous Caddy hash. The updated flake.lock is retained"}
  }
}

# Update the lockfile and its dependent Caddy plugin source hash.
def nup [] {
  cd $env.LOCAL_FLAKE
  ^nix flake update
  if $env.LAST_EXIT_CODE != 0 {
    error make {msg: "Flake update failed; Caddy hash left unchanged"}
  }
  nup-refresh-caddy
}

# rebuild home-manager
def hbuild [] {
  cd $env.LOCAL_FLAKE
  home-manager build --flake .
}
