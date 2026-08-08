{
  networking = {
    enableIPv6 = false;
    useDHCP = false;
    wireless.enable = false;
    interfaces = {
      enp4s0.useDHCP = true;
      enp1s0 = { };
      enp1s0d1.ipv4.addresses = [
        {
          address = "192.168.2.100";
          prefixLength = 23;
        }
      ];
    };
    defaultGateway = {
      address = "172.16.0.1";
      interface = "enp4s0";
    };
    firewall = {
      allowedUDPPorts = [ 51820 ];
      checkReversePath = false;
    };
  };
}
