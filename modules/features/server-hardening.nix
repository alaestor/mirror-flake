/**
  Baseline kernel and service hardening for network-facing server hosts.

  Routing and address-family policy belong to the host. AppArmor is available
  for service-owned profiles; enabling it does not confine every workload.
  See docs/security-hardening.md for the policy and validation requirements.
*/
{
  flake.modules.nixos.server-hardening =
    { lib, pkgs, ... }:
    {
      boot = {
        kernelModules = [ "dns_resolver" ];
        kernelParams = [
          "slab_nomerge"
          # Page poisoning overrides the kernel's default heap initialization.
          "page_alloc.shuffle=1"
          "debugfs=off"
        ];
        blacklistedKernelModules = [
          "ax25"
          "netrom"
          "rose"
          "adfs"
          "affs"
          "bfs"
          "befs"
          "cramfs"
          "efs"
          "erofs"
          "exofs"
          "freevxfs"
          "f2fs"
          "hfs"
          "hpfs"
          "jfs"
          "minix"
          "nilfs2"
          "omfs"
          "qnx4"
          "qnx6"
          "sysv"
          "ufs"
        ];
        kernel.sysctl = {
          "kernel.kptr_restrict" = lib.mkOverride 500 2;
          "net.core.bpf_jit_enable" = false;
          # Recent kernels reject disabling ftrace through its former sysctl.
          "net.ipv4.conf.all.log_martians" = true;
          "net.ipv4.conf.default.log_martians" = true;
          "net.ipv4.icmp_echo_ignore_broadcasts" = true;
          "net.ipv4.conf.all.accept_redirects" = lib.mkDefault false;
          "net.ipv4.conf.all.secure_redirects" = lib.mkDefault false;
          "net.ipv4.conf.default.accept_redirects" = lib.mkDefault false;
          "net.ipv4.conf.default.secure_redirects" = lib.mkDefault false;
          "net.ipv6.conf.all.accept_redirects" = lib.mkDefault false;
          "net.ipv6.conf.default.accept_redirects" = lib.mkDefault false;
          "net.ipv4.conf.all.send_redirects" = false;
          "net.ipv4.conf.default.send_redirects" = false;
        };
      };

      security = {
        protectKernelImage = true;
        forcePageTableIsolation = true;
        sudo.enable = false;
        sudo-rs = {
          enable = true;
          package = pkgs.sudo-rs;
          execWheelOnly = true;
        };
        apparmor = {
          enable = true;
          killUnconfinedConfinables = true;
        };
      };

      services = {
        avahi.enable = lib.mkForce false;
        printing = {
          browsed.enable = lib.mkForce false;
          browsing = lib.mkForce false;
        };
      };

      networking.firewall.enable = lib.mkForce true;
    };
}
