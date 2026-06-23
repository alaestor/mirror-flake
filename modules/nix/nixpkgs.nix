{ inputs, ... } : {
  flake-file.inputs =
  let
    stable-version = "26.05";
  in
  {
    stable-nixpkgs.url   = "nixpkgs/nixos-${stable-version}";
    unstable-nixpkgs.url = "nixpkgs/nixos-unstable";
  };
}
