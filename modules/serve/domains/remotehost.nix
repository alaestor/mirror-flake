/**
  Public remotehost media composition: Filebrowser and Jellyfin.
*/
{ inputs, ... }:
{
  flake.modules.nixos.domain-remotehost =
    { config, ... }:
    let
      filebrowser = config.serve.filebrowser;
      jellyfin = config.serve.jellyfin;

      domain = {
        primary = "remotehost.cc";
        secondary = "shota.zip"; # TODO: may become primary domain for media in the future; shorter to type, meme-factor memorability
      };

    in
    {
      imports = with inputs.self.modules.nixos; [
        serve-filebrowser
        serve-jellyfin
      ];

      networking.firewall.allowedTCPPorts = [
        80
        443
        44344
      ];

      services.caddy.virtualHosts = {
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
            reverse_proxy ${filebrowser.address}:${toString filebrowser.port}
          '';
        };

        "jellyfin.${domain.primary}, jellyfin.${domain.primary}:44344, ${domain.secondary}, ${domain.secondary}:44344" = {
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
