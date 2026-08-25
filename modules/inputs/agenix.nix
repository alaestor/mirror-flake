/** Declares the agenix flake input, for secret decryption at activation. */
{ inputs, ... }:
{
  nucleus.inputs.agenix = {
    url = "github:ryantm/agenix";
    inputs.nixpkgs.follows = "unstable-nixpkgs";
    inputs.home-manager.follows = "unstable-home-manager";
  };

  flake.modules = {
    nixos.agenix.imports = [ inputs.agenix.nixosModules.default ];
    nixos.agenix-host-identity =
      { config, lib, ... }:
      {
        imports = [ inputs.self.modules.nixos.agenix ];

        age.identityPaths = lib.mkDefault [
          "/etc/ssh/ssh_host_ed25519_key_${lib.toLower config.hostIdentity.name}"
        ];
      };
    homeManager.agenix.imports = [ inputs.agenix.homeManagerModules.default ];
  };

  perSystem =
    { system, ... }:
    {
      packages.agenix = inputs.agenix.packages.${system}.agenix;
    };
}
