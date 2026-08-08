/**
  Fleet-aware Tailscale client composition.

  Configures the shared tailnet's coordination URL and DNS suffix for NixOS
  clients. The Nix-on-Droid composition configures terminal integration only:
  Android's Tailscale application owns the VPN lifecycle.
*/
{ config, inputs, ... }:
let
  tailnet = config.flake.fleet.tailnets."0x04cc";
in
{
  flake.modules.nixos.tailnet-client =
    { lib, ... }:
    {
      imports = [ inputs.self.modules.nixos.tailscale ];

      tailscale = {
        enable = lib.mkDefault true;
        loginServer = lib.mkDefault tailnet.coordinationUrl;
        tailnetDomain = lib.mkDefault tailnet.dnsSuffix;
      };
    };

  flake.nixOnDroidModules.tailnet-client =
    { lib, ... }:
    {
      imports = [ inputs.self.nixOnDroidModules.standard-terminal ];

      environment.etc."resolv.conf".text = lib.mkForce ''
        nameserver 100.100.100.100
      '';

      home-manager.config.standard-terminal.tailscale.domain = tailnet.dnsSuffix;
    };
}
