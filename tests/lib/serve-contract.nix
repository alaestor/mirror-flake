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
      activationPaths ? [ ],
      enabledConfig ? { },
      enabledAssertions ? [ ],
    }:
    let
      disabled = evaluate [ module ];
      enabled = evaluate [ module { serve.${name} = { enable = true; } // enabledConfig; } ];
      isActive = config: path: lib.attrByPath path false config == true;
    in
    [
      {
        assertion = disabled.serve.${name}.enable == false;
        message = "serve-${name} is not disabled by default";
      }
      {
        assertion = builtins.all (path: !isActive disabled path) activationPaths;
        message = "serve-${name} activates a workload while disabled";
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
    ++ map (assertion: assertion enabled) enabledAssertions;

  inherit evaluate;
}
