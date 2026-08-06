$env.LOCAL_FLAKE = "@LOCAL_FLAKE@"

 # update nix flake lockfile
def nup [] {
  cd $env.LOCAL_FLAKE
  nix flake update
}

# rebuild home-manager
def hbuild [] {
  cd $env.LOCAL_FLAKE
  home-manager build --flake .
}
