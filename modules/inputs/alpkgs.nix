/** Declares the alpkgs flake input, this author's personal package overlay. */
{
  nucleus.inputs.alpkgs = {
    url = "git+https://git.0x04.cc/alaestor/pkgs.git";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
