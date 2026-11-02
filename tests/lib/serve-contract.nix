{ inputs, system }:
let
  lib = inputs.nixpkgs.lib;
  evaluate = modules: (lib.nixosSystem { inherit system modules; }).config;
in
{
  serviceCase =
    {
      name,
      module,
      # No default: each case must say explicitly which config paths flip
      # on when enabled. Artifact-only cases use enabledAssertions instead;
      # an empty list must not silently turn activation tests into no-ops.
      activationPaths,
      enabledConfig ? { },
      enabledAssertions ? [ ],
    }:
    let
      disabled = evaluate [ module ];
      enabled = evaluate [ module { serve.${name} = { enable = true; } // enabledConfig; } ];
      isActive = config: path: lib.attrByPath path false config == true;
    in
    assert lib.assertMsg (activationPaths != [ ] || enabledAssertions != [ ])
      "serve-${name}: define a workload or an enabled artifact assertion";
    [
      {
        assertion = disabled.serve.${name}.enable == false;
        message = "serve-${name} is not disabled by default";
      }
      {
        assertion = disabled.networking.firewall.allowedTCPPorts == [ ];
        message = "serve-${name} opens public TCP ingress while disabled";
      }
      {
        assertion = disabled.networking.firewall.allowedUDPPorts == [ ];
        message = "serve-${name} opens public UDP ingress while disabled";
      }
      {
        assertion = enabled.networking.firewall.allowedTCPPorts == [ ];
        message = "serve-${name} independently opens public TCP ingress";
      }
      {
        assertion = enabled.networking.firewall.allowedUDPPorts == [ ];
        message = "serve-${name} independently opens public UDP ingress";
      }
    ]
    ++ lib.optionals (activationPaths != [ ]) [
      {
        assertion = builtins.all (path: !isActive disabled path) activationPaths;
        message = "serve-${name} activates a workload while disabled";
      }
      {
        assertion = builtins.all (path: isActive enabled path) activationPaths;
        message = "serve-${name} does not activate its workload when enabled";
      }
    ]
    ++ map (assertion: assertion enabled) enabledAssertions;

  inherit evaluate;
}
