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
    }
    {
      name = "filebrowser";
      module = nixos.serve-filebrowser;
      activationPaths = [ [ "services" "filebrowser" "enable" ] ];
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
      name = "static-site";
      module = nixos.serve-static-site;
    }
    {
      name = "torrenting";
      module = nixos.serve-torrenting;
      activationPaths = [ [ "services" "qbittorrent" "enable" ] ];
    }
  ];

  serviceAssertions = lib.concatMap harness.serviceCase cases;

  domainDisabled = harness.evaluate [ nixos.domain-0x04cc ];
  domainHeadscale = harness.evaluate [
    nixos.domain-0x04cc
    { serve.headscale.enable = true; }
  ];
  domainMatrix = harness.evaluate [
    nixos.domain-0x04cc
    { serve.matrix.enable = true; }
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
