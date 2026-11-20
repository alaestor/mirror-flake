/**
  Public remotehost media composition: Dufs downloads and Jellyfin.
*/
{ inputs, ... }:
{
  flake.modules.nixos.domain-remotehost =
    { config, lib, ... }:
    let
      dufsEnabled = config.serve.dufs.enable;
      jellyfinEnabled = config.serve.jellyfin.enable;
      publicHttpEnabled = dufsEnabled || jellyfinEnabled;

      dufs = config.serve.dufs;
      jellyfin = config.serve.jellyfin;
      ports = inputs.self.fleet.ports.shared;
      jellyfinAltPort = toString ports.jellyfin-https-alt;

      domain = {
        primary = "remotehost.cc";
        secondary = "shota.zip"; # TODO: may become primary domain for media in the future; shorter to type, meme-factor memorability
      };
    in
    {
      imports = with inputs.self.modules.nixos; [
        serve-dufs
        serve-jellyfin
      ];

      networking.firewall.allowedTCPPorts =
        lib.optionals publicHttpEnabled [
          ports.caddy-http
          ports.caddy-https
        ]
        ++ lib.optional jellyfinEnabled ports.jellyfin-https-alt;

      services.caddy.virtualHosts = lib.optionalAttrs dufsEnabled {
        "media.${domain.primary}" = {
          serverAliases = [ "download.${domain.secondary}" ];
          extraConfig = ''
            handle_path /.cerberus/* {
              cerberus_endpoint
            }
            @challenge {
              not path /.cerberus/*
            }
            cerberus @challenge {
              base_url "/.cerberus"
            }
            reverse_proxy ${dufs.address}:${toString dufs.port}
          '';
        };
      }
      // lib.optionalAttrs jellyfinEnabled {
        "jellyfin.${domain.primary}, jellyfin.${domain.primary}:${jellyfinAltPort}, ${domain.secondary}, ${domain.secondary}:${jellyfinAltPort}" = {
          extraConfig = ''
            tls {
              key_type rsa4096
            }
            reverse_proxy localhost:${toString jellyfin.port}
          '';
        };
      };
    };
}
