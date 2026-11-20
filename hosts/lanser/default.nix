{ fleet, inputs, ... }:
{
  nixos = [
    ./hardware.nix
    #inputs.self.modules.nixos.lxqt
    inputs.self.modules.nixos.auto-login
    (import ./networking.nix { lan = fleet.lan; ports = fleet.ports.lanser; })
    (import ./system.nix {
      inherit inputs;
      tailnet = fleet.tailnets."0x04cc";
      lan = fleet.lan;
      ports = fleet.ports.lanser;
      sharedPorts = fleet.ports.shared;
    })
  ];

  homeManager = [
    ({ pkgs, ... }: {
      home.packages = [ pkgs.htop ];
      programs.bash.profileExtra = ''
        if [[ $- == *i* ]] && [[ "$(tty)" == /dev/tty1 ]]; then
          ${pkgs.htop}/bin/htop
        fi
      '';
    })
  ];
}
