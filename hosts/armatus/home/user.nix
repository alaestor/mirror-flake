{ pkgs, ... }:
{
  deepseek-harness.enableSandbox = false;

  home.packages = with pkgs; [
    keepassxc
    lmstudio
  ];
}
