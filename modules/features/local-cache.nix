/**
  # local-cache

  Exports enabled-on-import NixOS and Nix-on-Droid modules for a trusted HTTP
  binary cache. Defaults target APC's tailnet cache and first signing-key
  rotation. If the public key has not been committed yet, the module warns and
  leaves Nix's substituters unchanged.
*/
{ lib, self, ... }:

let
  options = config: {
    authority = lib.mkOption {
      type = lib.types.str;
      default = "apc.${self.fleet.tailnets."0x04cc".dnsSuffix}";
      description = "DNS name of the trusted local binary cache.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "HTTP port of the trusted local binary cache.";
    };
    rotation = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Trusted cache signing-key rotation counter.";
    };
    keyName = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${config.local-cache.authority}-${toString config.local-cache.rotation}";
      description = "Trusted Nix signing-key name.";
    };
    publicKeyFile = lib.mkOption {
      type = lib.types.path;
      default = self.data.path "identities/nix-store-signing/${config.local-cache.keyName}.nsk.pub";
      description = "Public Nix signing-key file for the cache.";
    };
    url = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://${config.local-cache.authority}:${toString config.local-cache.port}";
      description = "Binary-cache substituter URL.";
    };
  };

  values = config:
    let
      cfg = config.local-cache;
      publicKeyExists = builtins.pathExists cfg.publicKeyFile;
      publicKey = builtins.head (self.data.vars.identityLines (builtins.readFile cfg.publicKeyFile));
    in
    {
      inherit cfg publicKey publicKeyExists;
    };
in
{
  flake.modules.nixos.local-cache =
    { config, ... }:
    let
      cache = values config;
    in
    {
      options.local-cache = options config;
      config = {
        warnings = lib.optional (!cache.publicKeyExists)
          "local-cache: public key is absent: ${toString cache.cfg.publicKeyFile}; cache remains disabled";
        nix.settings = lib.mkIf cache.publicKeyExists {
          substituters = lib.mkAfter [ cache.cfg.url ];
          trusted-public-keys = lib.mkAfter [ cache.publicKey ];
        };
      };
    };

  flake.modules.nixOnDroid.local-cache =
    { config, ... }:
    let
      cache = values config;
    in
    {
      options.local-cache = options config;
      config = {
        warnings = lib.optional (!cache.publicKeyExists)
          "local-cache: public key is absent: ${toString cache.cfg.publicKeyFile}; cache remains disabled";
        nix = lib.mkIf cache.publicKeyExists {
          substituters = lib.mkAfter [ cache.cfg.url ];
          trustedPublicKeys = lib.mkAfter [ cache.publicKey ];
        };
      };
    };
}
