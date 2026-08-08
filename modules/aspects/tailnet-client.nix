/**
  Fleet-aware Tailscale client composition.

  Configures the shared tailnet's coordination URL and DNS suffix for NixOS
  clients. NixOS user environments also receive the SSH client and synthesize
  known-host entries for every registered SSH host identity at its tailnet DNS
  name. The Nix-on-Droid composition configures terminal integration only:
  Android's Tailscale application owns the VPN lifecycle.
*/
{ config, inputs, lib, self, ... }:
let
  tailnet = config.flake.fleet.tailnets."0x04cc";
  sshKnownHosts = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      hostName: publicKey: "${hostName}.${tailnet.dnsSuffix} ${publicKey}"
    ) self.data.vars.sshHostPublicKeys
  ) + "\n";
in
{
  flake.modules.nixos.tailnet-client =
    { lib, ... }:
    let
      homeModule = {
        home.file.".ssh/known_hosts".text = sshKnownHosts;
      };
    in
    {
      imports = [
        inputs.self.modules.nixos.ssh-client
        inputs.self.modules.nixos.tailscale
      ];

      tailscale = {
        enable = lib.mkDefault true;
        loginServer = lib.mkDefault tailnet.coordinationUrl;
        tailnetDomain = lib.mkDefault tailnet.dnsSuffix;
      };

      userEnvironment.sharedModules = [ homeModule ];
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
