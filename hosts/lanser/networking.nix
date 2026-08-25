{ lan }:
{
  networking = {
    enableIPv6 = false;
    useDHCP = false;
    wireless.enable = false;
    interfaces = {
      enp4s0.useDHCP = true;
      enp1s0 = { };
      # Dedicated, direct-attach point-to-point link to the NAS
      # (192.168.2.200 below and in system.nix) — not the general LAN
      # `lan.cidr` covers, so it stays a local fact rather than a fleet one.
      enp1s0d1.ipv4.addresses = [
        {
          address = "192.168.2.100";
          prefixLength = 23;
        }
      ];
    };
    defaultGateway = {
      address = lan.gateway;
      interface = "enp4s0";
    };
    firewall = {
      allowedUDPPorts = [ 51820 ];
      checkReversePath = false;
    };
  };
}
