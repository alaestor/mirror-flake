/**
  Baseline kernel and service hardening for network-facing server hosts.
*/
{
  # TODO(security): deep audit of server-hardening module configuration settings
  flake.modules.nixos.server-hardening =
    { lib, pkgs, ... }:
    {
      boot = {
        kernelModules = [ "dns_resolver" ];
        kernelParams = [
          "slab_nomerge"
          "page_poison=1"
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
          "kernel.ftrace_enabled" = false;
          "net.ipv4.conf.all.log_martians" = true;
          "net.ipv4.conf.all.rp_filter" = "1";
          "net.ipv4.conf.default.log_martians" = true;
          "net.ipv4.conf.default.rp_filter" = "1";
          "net.ipv4.icmp_echo_ignore_broadcasts" = true;
          "net.ipv4.conf.all.accept_redirects" = lib.mkDefault false;
          "net.ipv4.conf.all.secure_redirects" = lib.mkDefault false;
          "net.ipv4.conf.default.accept_redirects" = lib.mkDefault false;
          "net.ipv4.conf.default.secure_redirects" = lib.mkDefault false;
          "net.ipv6.conf.all.accept_redirects" = lib.mkDefault false;
          "net.ipv6.conf.default.accept_redirects" = lib.mkDefault false;
          "net.ipv4.conf.all.send_redirects" = false;
          "net.ipv4.conf.default.send_redirects" = false;
          "net.ipv6.conf.all.accept_ra" = 0;
          "net.ipv6.conf.default.accept_ra" = 0;
        };
      };

      security = {
        protectKernelImage = true;
        forcePageTableIsolation = true;
        virtualisation.flushL1DataCache = "always";
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
