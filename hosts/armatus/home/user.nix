{ inputs }:
{ pkgs, ... }:
{
  deepseek-harness.enableSandbox = false;

  home.packages = (with pkgs; [
    chromium
    keepassxc
    lmstudio
    obsidian
  ]) ++ [ inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.jellium-desktop ];
}
