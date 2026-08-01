/**
  Public 0x04.cc domain composition: static site, Matrix, and Cinny.
*/
{ inputs, ... }:
{
  flake.modules.nixos.domain-0x04cc =
    { config, lib, options, ... }:
    let
      domain = "0x04.cc";
      matrixDomain = "matrix.${domain}";
      matrix = config.serve.matrix;
      hasHeadscale = lib.hasAttrByPath [ "serve" "headscale" "enable" ] options;
      headscaleEnabled = hasHeadscale && config.serve.headscale.enable;
      headscale = config.services.headscale;
      headplane = config.services.headplane;
      adminAllowedCIDRs = config.serve.headscale.adminAllowedCIDRs;
      adminRoute =
        if adminAllowedCIDRs == [ ] then
          ''
            @headplane-admin path /admin*
            handle @headplane-admin {
              respond "Headplane is not published" 403
            }
          ''
        else
          ''
            @headplane-admin-private {
              path /admin*
              remote_ip ${lib.concatStringsSep " " adminAllowedCIDRs}
            }
            handle @headplane-admin-private {
              reverse_proxy ${headplane.settings.server.host}:${toString headplane.settings.server.port}
            }

            @headplane-admin path /admin*
            handle @headplane-admin {
              respond "Forbidden" 403
            }
          '';
    in
    {
      imports = with inputs.self.modules.nixos; [
        serve-matrix
        serve-cinny
        serve-static-site
      ];

      serve = {
        matrix.serverName = domain;
        cinny.homeserver = domain;
      };

      networking.firewall.allowedTCPPorts = [
        80
        443
        8448
      ];

      services.caddy.virtualHosts = {
        "${domain}".extraConfig = ''
          handle /.well-known/matrix/server {
            header Content-Type application/json
            respond `{"m.server": "${matrixDomain}:8448"}` 200
          }

          handle /.well-known/matrix/client {
            @options method OPTIONS
            respond @options 204
            header {
              Content-Type application/json
              Access-Control-Allow-Origin *
              Access-Control-Allow-Methods "GET, OPTIONS"
              Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization"
              Access-Control-Max-Age 1728000
            }
            respond `{"m.homeserver": {"base_url": "https://${matrixDomain}"}}` 200
          }

          handle /.well-known/matrix/support {
            header Content-Type application/json
            respond `{"contacts":[{"role":"m.role.admin","email_address":"admin@${domain}","matrix_id":"@administrator:${domain}"}]}` 200
          }

          handle {
            root * ${config.serve.static-site.root}
            try_files {path} /index.html
            file_server
          }
        '';

        "${matrixDomain}, ${matrixDomain}:8448".extraConfig = ''
          handle /_matrix/* {
            reverse_proxy ${matrix.address}:${toString matrix.port}
          }
          handle /_synapse/client/* {
            reverse_proxy ${matrix.address}:${toString matrix.port}
          }

          request_body {
            max_size ${toString matrix.maxRequestSize}B
          }

          handle_path /.cerberus/* {
            cerberus_endpoint
          }
          @challenge {
            not path /.cerberus/*
            not path /_matrix/*
            not path /_synapse/*
          }
          cerberus @challenge {
            base_url "/.cerberus"
          }

          handle {
            root * ${config.serve.cinny.package}
            try_files {path} /index.html
            file_server
          }
        '';
      }
      // lib.optionalAttrs headscaleEnabled {
        "headscale.${domain}".extraConfig = ''
          ${adminRoute}

          handle {
            reverse_proxy ${headscale.address}:${toString headscale.port}
          }
        '';
      };
    };
}
