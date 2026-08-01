{
  flake-file.inputs.alpkgs = {
    url = "git+https://codeberg.org/alaestor/pkgs.git";
    inputs.flake-file.follows = "flake-file";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
