/**
  Public bokunopi.co domain composition: static site (meme site).
*/
{ inputs, ... }:
{
  flake.modules.nixos.domain-bokunopi =
    { config, lib, ... }:
    let
      domain = "bokunopi.co";

      staticSiteEnabled = config.serve.static-site-bokunopi.enable;
      staticSite = config.serve.static-site-bokunopi;
    in
    {
      imports = with inputs.self.modules.nixos; [
        serve-static-site-bokunopi
      ];

      networking.firewall.allowedTCPPorts = lib.optionals staticSiteEnabled [
        80
        443
      ];

      services.caddy.virtualHosts = lib.optionalAttrs staticSiteEnabled {
        "${domain}".extraConfig = ''
          handle {
            root * ${staticSite.root}
            try_files {path} /index.html
            file_server
          }

          handle_errors {
            @404 {
              expression {err.status_code} == 404
            }
            handle @404 {
              rewrite * /404.html
              file_server
            }
          }
        '';
      };
    };
}
