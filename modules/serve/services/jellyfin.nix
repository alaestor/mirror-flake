/**
  Local Jellyfin media service and NAS alias-library builder without public
  ingress policy. Uses a dedicated service account; hosts own any NAS grants
  and migration of existing state when changing the account.
*/
{ lib, self, ... }:
let
  mkJellybuilder =
    {
      pkgs,
      source ? null,
      destination ? null,
    }:
    pkgs.writeShellApplication {
      name = "jellybuilder";
      runtimeInputs = [ pkgs.python3 ];
      text =
        lib.optionalString (source != null) ''
          export JELLYBUILDER_SOURCE=${lib.escapeShellArg source}
        ''
        + lib.optionalString (destination != null) ''
          export JELLYBUILDER_DESTINATION=${lib.escapeShellArg destination}
        ''
        + ''
          exec python3 ${lib.escapeShellArg (self.data.path "serve/jellyfin/jellybuilder.py")} "$@"
        '';
    };
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages.jellybuilder = mkJellybuilder { inherit pkgs; };

      checks.jellybuilder =
        pkgs.runCommand "jellybuilder-tests"
          {
            nativeBuildInputs = [ pkgs.python3 ];
            JELLYBUILDER_SCRIPT = self.data.path "serve/jellyfin/jellybuilder.py";
          }
          ''
            python3 -m unittest discover -v \
              -s ${self}/tests/jellybuilder
            touch "$out"
          '';
    };

  flake.modules.nixos.serve-jellyfin =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.serve.jellyfin;
      hasVaultMountpoint = lib.hasAttrByPath [ "nas" "vault" "mountpoint" ] options;
    in
    {
      options.serve.jellyfin = {
        enable = lib.mkEnableOption "the local Jellyfin media service";

        user = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "jellyfin";
          description = "Account under which Jellyfin runs.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8096;
          description = "Local Jellyfin HTTP port configured through Jellyfin.";
        };

        libraryBuilder = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to install the Jellyfin alias-library builder.";
          };

          source = lib.mkOption {
            type = lib.types.nonEmptyStr;
            default = if hasVaultMountpoint then "${config.nas.vault.mountpoint}/Media" else "/mnt/Vault/Media";
            defaultText = lib.literalExpression ''
              if the NAS module is present
              then "''${config.nas.vault.mountpoint}/Media"
              else "/mnt/Vault/Media"
            '';
            description = "Media root read by jellybuilder.";
          };

          destination = lib.mkOption {
            type = lib.types.nonEmptyStr;
            default = "/var/lib/jellyfin/jellymedia";
            description = "Jellyfin alias-library root written by jellybuilder.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages =
          (with pkgs; [
            jellyfin
            jellyfin-web
            jellyfin-ffmpeg
          ])
          ++ lib.optional cfg.libraryBuilder.enable (mkJellybuilder {
            inherit pkgs;
            inherit (cfg.libraryBuilder) source destination;
          });

        services.jellyfin = {
          enable = true;
          openFirewall = false;
          user = cfg.user;
        };

        # The alias library is a tree of links into `source`, so Jellyfin reads
        # through to it and holds files open there. Without this, nothing stops
        # Jellyfin before that share is unmounted, and the unmount fails.
        systemd.services.jellyfin = {
          serviceConfig.ProtectHome = lib.mkDefault true;
          # Stop before nas-detach lazily detaches network filesystems.
          after = lib.optional cfg.libraryBuilder.enable "nas-detach.service";
          unitConfig.RequiresMountsFor = lib.optional cfg.libraryBuilder.enable cfg.libraryBuilder.source;
        };
      };
    };
}
