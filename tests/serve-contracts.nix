{
  inputs,
  pkgs,
  system,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
  harness = import ./lib/serve-contract.nix { inherit inputs system; };
  nixos = inputs.self.modules.nixos;

  cases = [
    {
      name = "caddy";
      module = nixos.serve-caddy;
      activationPaths = [ [ "services" "caddy" "enable" ] ];
    }
    {
      name = "cinny";
      module = nixos.serve-cinny;
      enabledConfig.homeserver = "example.test";
      # No discrete boolean activation surface: enabling it only builds a
      # package (serve.cinny.package), consumed by a domain composition.
      activationPaths = [ ];
    }
    {
      name = "filebrowser";
      module = nixos.serve-filebrowser;
      activationPaths = [ [ "services" "filebrowser" "enable" ] ];
    }
    {
      name = "forgejo";
      module = nixos.serve-forgejo;
      activationPaths = [ [ "services" "forgejo" "enable" ] ];
      enabledConfig.domain = "git.example.test";
    }
    {
      name = "headscale";
      module = nixos.serve-headscale;
      activationPaths = [
        [ "services" "headscale" "enable" ]
        [ "services" "headplane" "enable" ]
      ];
      enabledAssertions = [
        (config: {
          assertion = config.services.headscale.enable && config.services.headplane.enable;
          message = "serve-headscale did not configure both workloads when enabled";
        })
      ];
    }
    {
      name = "jellyfin";
      module = nixos.serve-jellyfin;
      activationPaths = [ [ "services" "jellyfin" "enable" ] ];
    }
    {
      name = "matrix";
      module = nixos.serve-matrix;
      activationPaths = [ [ "services" "matrix-tuwunel" "enable" ] ];
      enabledConfig.serverName = "example.test";
      enabledAssertions = [
        (config: {
          assertion = config.services.matrix-tuwunel.enable;
          message = "serve-matrix did not configure its workload when enabled";
        })
      ];
    }
    {
      name = "nix-cache";
      module = nixos.serve-nix-cache;
      activationPaths = [ [ "services" "nix-serve" "enable" ] ];
      enabledConfig.authority = "cache.example.test";
    }
    {
      name = "static-site-0x04";
      module = nixos.serve-static-site-0x04;
      # Pure content-root data module; no boolean activation surface.
      activationPaths = [ ];
    }
    {
      name = "static-site-bokunopi";
      module = nixos.serve-static-site-bokunopi;
      activationPaths = [ ];
    }
    {
      name = "torrenting";
      module = nixos.serve-torrenting;
      activationPaths = [ [ "services" "qbittorrent" "enable" ] ];
    }
  ];

  serviceAssertions = lib.concatMap harness.serviceCase cases;

  domainDisabled = harness.evaluate [ nixos.domain-0x04 ];
  domainHeadscale = harness.evaluate [
    nixos.domain-0x04
    { serve.headscale.enable = true; }
  ];
  domainMatrix = harness.evaluate [
    nixos.domain-0x04
    { serve.matrix.enable = true; }
  ];

  bokunopiDisabled = harness.evaluate [ nixos.domain-bokunopi ];
  bokunopiEnabled = harness.evaluate [
    nixos.domain-bokunopi
    { serve.static-site-bokunopi.enable = true; }
  ];

  remotehostDisabled = harness.evaluate [ nixos.domain-remotehost ];
  remotehostEnabled = harness.evaluate [
    nixos.domain-remotehost
    {
      serve.filebrowser.enable = true;
      serve.jellyfin.enable = true;
    }
  ];

  domainAssertions = [
    {
      assertion = domainDisabled.services.caddy.virtualHosts == { };
      message = "domain-0x04cc creates routes with all members disabled";
    }
    {
      assertion = domainDisabled.networking.firewall.allowedTCPPorts == [ ];
      message = "domain-0x04cc opens public ingress with all members disabled";
    }
    {
      assertion = builtins.attrNames domainHeadscale.services.caddy.virtualHosts == [ "headscale.0x04.cc" ];
      message = "domain-0x04cc did not create only the Headscale route";
    }
    {
      assertion = domainHeadscale.networking.firewall.allowedTCPPorts == [ 80 443 ];
      message = "domain-0x04cc Headscale ingress differs from ports 80 and 443";
    }
    {
      assertion = domainMatrix.services.matrix-tuwunel.enable;
      message = "domain-0x04cc did not configure Matrix when enabled";
    }
    {
      assertion = domainMatrix.networking.firewall.allowedTCPPorts == [ 80 443 8448 ];
      message = "domain-0x04cc Matrix ingress differs from ports 80, 443, and 8448";
    }
    {
      assertion = bokunopiDisabled.services.caddy.virtualHosts == { };
      message = "domain-bokunopi creates routes with all members disabled";
    }
    {
      assertion = bokunopiDisabled.networking.firewall.allowedTCPPorts == [ ];
      message = "domain-bokunopi opens public ingress with all members disabled";
    }
    {
      assertion = builtins.attrNames bokunopiEnabled.services.caddy.virtualHosts == [ "bokunopi.co" ];
      message = "domain-bokunopi did not create only the static-site route";
    }
    {
      assertion = bokunopiEnabled.networking.firewall.allowedTCPPorts == [ 80 443 ];
      message = "domain-bokunopi ingress differs from ports 80 and 443";
    }
    {
      assertion = remotehostDisabled.services.caddy.virtualHosts == { };
      message = "domain-remotehost creates routes with all members disabled";
    }
    {
      assertion = remotehostDisabled.networking.firewall.allowedTCPPorts == [ ];
      message = "domain-remotehost opens public ingress with all members disabled";
    }
    {
      assertion = builtins.attrNames remotehostEnabled.services.caddy.virtualHosts == [
        "jellyfin.remotehost.cc, jellyfin.remotehost.cc:44344, shota.zip, shota.zip:44344"
        "media.remotehost.cc"
      ];
      message = "domain-remotehost did not create the Filebrowser and Jellyfin routes";
    }
    {
      assertion = remotehostEnabled.networking.firewall.allowedTCPPorts == [ 80 443 44344 ];
      message = "domain-remotehost ingress differs from ports 80, 443, and 44344";
    }
  ];

  failures = map (result: result.message) (
    builtins.filter (result: !result.assertion) (serviceAssertions ++ domainAssertions)
  );
in
pkgs.runCommand "serve-contracts-test"
  {
    passAsFile = [ "failureReport" ];
    failureReport = builtins.concatStringsSep "\n" failures;
  }
  ''
    if [[ -s "$failureReportPath" ]]; then
      cat "$failureReportPath" >&2
      exit 1
    fi
    touch "$out"
  ''
