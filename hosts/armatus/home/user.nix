{ lib, pkgs, ... }:
{
  deepseek-harness.enableSandbox = false;

  # The upstream pnpm dependency closure currently hashes differently on
  # armatus than on other builders.
  programs.librewolf.profiles.default.extensions.packages = lib.mkForce [ ];

  home.packages = with pkgs; [
    keepassxc
    lmstudio
  ];
}
