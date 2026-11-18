{ inputs, pkgs, system }:
let
  lib = inputs.nixpkgs.lib;
  fixture = adminAllowedCIDRs: (lib.nixosSystem {
    inherit system;
    modules = [
      inputs.self.modules.nixos.serve-caddy
      inputs.self.modules.nixos.domain-0x04
      {
        serve = {
          caddy.enable = true;
          static-site-0x04 = {
            enable = true;
            root = toString (pkgs.writeTextDir "index.html" "static-fixture");
          };
          headscale = { enable = true; inherit adminAllowedCIDRs; };
          forgejo = { enable = true; port = 18581; };
          matrix = { enable = true; port = 18581; };
          cinny.enable = true;
        };
        services = {
          headscale.port = 18581;
          headplane.settings.server.port = 18581;
        };
      }
    ];
  }).config;
  denied = fixture [ ];
  allowed = fixture [ "127.0.0.1/32" ];
  otherNetwork = fixture [ "192.0.2.0/24" ];
in
pkgs.runCommand "domain-ingress-test" {
  nativeBuildInputs = [ pkgs.python3 ];
  DOMAIN_CADDY = lib.getExe denied.services.caddy.package;
  DOMAIN_CONFIGS = builtins.toJSON (lib.mapAttrs (_: config:
    config.environment.etc."caddy/caddy_config".source
  ) { inherit denied allowed otherNetwork; });
} ''
  python3 ${./lib/domain-ingress.py}
  touch "$out"
''
