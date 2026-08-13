/**
  Fleet-aware Tailscale client composition.

  Configures the shared tailnet's coordination URL and DNS suffix for NixOS
  clients. When an environment imports `ssh-client`, NixOS user environments
  add known-host entries for every registered SSH host identity at its tailnet
  DNS name. SSH client identity deployment remains an explicit host concern.
  The Nix-on-Droid composition configures terminal integration only:
  Android's Tailscale application owns the VPN lifecycle.
*/
{ config, inputs, self, ... }:
let
  tailnet = config.flake.fleet.tailnets."0x04cc";
in
{
  flake.modules.nixos.tailnet-client =
    { lib, ... }:
    let
      homeModule = { config, ... }:
        {
          imports = [ inputs.self.modules.homeManager.ssh-known-hosts ];

          ssh-client.knownHosts.${tailnet.dnsSuffix} = lib.mkIf config.ssh-client.knowTailnetHosts (
            lib.mapAttrs' (hostName: publicKey: {
              name = "${hostName}.${tailnet.dnsSuffix}";
              value = [ publicKey ];
            }) self.data.vars.sshHostPublicKeys
          );
        };
    in
    {
      imports = [ inputs.self.modules.nixos.tailscale ];

      tailscale = {
        enable = lib.mkDefault true;
        loginServer = lib.mkDefault tailnet.coordinationUrl;
        tailnetDomain = lib.mkDefault tailnet.dnsSuffix;
      };

      userEnvironment.sharedModules = [ homeModule ];
    };

  flake.modules.nixOnDroid.tailnet-client =
    { lib, ... }:
    {
      imports = [ inputs.self.modules.nixOnDroid.standard-terminal ];

      environment.etc."resolv.conf".text = lib.mkForce ''
        nameserver 100.100.100.100
      '';

      home-manager.config.standard-terminal.tailscale.domain = tailnet.dnsSuffix;
    };
}
