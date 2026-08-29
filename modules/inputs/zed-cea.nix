/** Declares the zed-cea flake input, this author's Cheat Engine Auto Assembler language tooling. */
{
  nucleus.inputs.zed-cea = {
    url = "git+https://git.0x04.cc/alaestor/zed-cea.git";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
