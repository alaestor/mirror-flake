{ inputs, pkgs, system, ... }:
let
  lib = inputs.nixpkgs.lib;
  config = (lib.nixosSystem {
    inherit system;
    modules = [ inputs.self.modules.nixos.server-hardening ];
  }).config;
  sysctl = config.boot.kernel.sysctl;
  checks = [
    {
      assertion = !(lib.elem "page_poison=1" config.boot.kernelParams);
      message = "Hardening must preserve the kernel's default heap initialization";
    }
    {
      assertion = !(sysctl ? "kernel.ftrace_enabled");
      message = "Hardening must not write the unsupported ftrace disable sysctl";
    }
    {
      assertion = builtins.all (name: !(builtins.hasAttr name sysctl)) [
        "net.ipv4.conf.all.rp_filter"
        "net.ipv4.conf.default.rp_filter"
        "net.ipv6.conf.all.accept_ra"
        "net.ipv6.conf.default.accept_ra"
      ];
      message = "Hardening must leave reverse-path and IPv6 discovery policy to the network owner";
    }
    {
      assertion = config.security.virtualisation.flushL1DataCache == null;
      message = "Generic hardening must not force an Intel-only KVM mitigation";
    }
    {
      assertion = config.networking.firewall.enable
        && !config.security.apparmor.enable
        && config.security.sudo-rs.enable
        && !config.security.sudo.enable
        && config.security.sudo-rs.execWheelOnly
        && config.security.protectKernelImage;
      message = "Hardening must retain firewall/sudo/kexec protection without enabling unused AppArmor";
    }
  ];
  failures = map (check: check.message) (builtins.filter (check: !check.assertion) checks);
in
pkgs.runCommand "server-hardening-test" {
  passAsFile = [ "failureReport" ];
  failureReport = lib.concatStringsSep "\n" failures;
} ''
  if [[ -s "$failureReportPath" ]]; then
    cat "$failureReportPath" >&2
    exit 1
  fi
  touch "$out"
''
