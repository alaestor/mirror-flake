{ inputs, pkgs, ... }:
let
  lib = inputs.unstable-nixpkgs.lib;
  client = (lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      inputs.self.modules.nixos.telemetry
      { telemetry.enable = true; }
    ];
  }).config;
in
# Exercise the actual service override, not a second copy of the patch wiring.
# Run from nixpkgs' collector modRoot to use its pinned Go dependency graph.
client.services.alloy.package.overrideAttrs (old: {
  patchPhase = old.patchPhase + ''
    patch -p1 < ${./telemetry/alloy/regressions.patch}
  '';
  buildPhase = ''
    go test -p "$NIX_BUILD_CORES" -race -count=1 -timeout=180s \
      github.com/grafana/alloy/internal/component/common/loki/client/internal/marker \
      github.com/grafana/alloy/internal/component/common/loki/wal \
      github.com/grafana/alloy/internal/component/common/loki/client
  '';
  installPhase = ''mkdir -p "$out"; echo passed > "$out/result"'';
  postInstall = "";
  postFixup = "";
  # The focused race-enabled suite runs above, not buildGoModule's generic phase.
  doCheck = false;
  doInstallCheck = false;
})
