$env.LOCAL_FLAKE = "@LOCAL_FLAKE@"

alias ncd = cd $env.LOCAL_FLAKE

 # update nix flake lockfile
def nup [] {
  ncd
  nix flake update
}

# nixos rebuild dry (build and print what would change)
def ndry [] {
  ncd
  nixos-rebuild dry-build --flake .
}

# nixos rebuild test (switch without adding to boot generation list)
def ntest [] {
  ncd
  nixos-rebuild test --flake .
}

# nixos rebuild boot (don't switch runtime)
def nboot [] {
  ncd
  sudo nixos-rebuild boot --flake .
}

# nixos rebuild switch
def nswitch [] {
  ncd
  sudo nixos-rebuild switch --flake .
}

# rebuild home-manager
def hbuild [] {
  ncd
  home-manager build --flake .
}

# switch home-manager
def hswitch [] {
  ncd
  home-manager switch --flake .
}
