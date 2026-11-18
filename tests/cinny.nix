{ inputs, pkgs, system }:
let
  lib = inputs.nixpkgs.lib;
  harness = import ./lib/serve-contract.nix { inherit inputs system; };
  disabled = harness.evaluate [ inputs.self.modules.nixos.serve-cinny ];
  enabled = harness.evaluate [
    inputs.self.modules.nixos.serve-cinny
    { serve.cinny = { enable = true; homeserver = "restricted.example.test"; }; }
  ];
in
assert lib.assertMsg (!disabled.serve.cinny.enable) "Cinny must be disabled by default";
assert lib.assertMsg (builtins.all (config:
  config.networking.firewall.allowedTCPPorts == [ ]
  && config.networking.firewall.allowedUDPPorts == [ ]
) [ disabled enabled ]) "Cinny must not independently open ingress";
pkgs.runCommand "cinny-artifact-test" { nativeBuildInputs = [ pkgs.jq ]; } ''
  test -s ${enabled.serve.cinny.package}/index.html
  jq --exit-status --arg homeserver restricted.example.test '
    .defaultHomeserver == 0
    and .homeserverList == [$homeserver]
    and .allowCustomHomeservers == false
    and .featuredCommunities.servers == [$homeserver]
  ' ${enabled.serve.cinny.package}/config.json
  touch "$out"
''
