{ inputs }:
{ config, lib, ... }:
{
  age.secrets.apc-wireguard-private-key = {
    file = inputs.self.secrets.path "vpn_APC-GT-18_key.age";
    mode = "0400";
  };

  networking = {
    domain = "tailnet.0x04.cc";
    enableIPv6 = true;
    networkmanager.enable = true;
    useDHCP = false;
    interfaces = {
      enp34s0.useDHCP = true;
      enp42s0 = { };
    };
    defaultGateway = {
      address = "172.16.0.1"; # TODO(lan): state: gateway
      interface = "enp34s0";
    };
    wg-quick.interfaces.wg0 = {
      table = "100";
      address = [ "10.2.0.2/32" ];
      privateKeyFile = config.age.secrets.apc-wireguard-private-key.path;
      postUp = ''
        ip rule add from 10.2.0.2/32 table 100
        ip rule add to 89.238.174.2 lookup main priority 100
      '';
      preDown = ''
        ip rule del from 10.2.0.2/32 table 100
        ip rule del to 89.238.174.2 lookup main priority 100
      '';
      peers = [
        {
          publicKey = "UBnjj4fW9ZR7bGnxN7JOD9G9AOwkYWl2gADZRHljEHI=";
          allowedIPs = [
            "0.0.0.0/0"
            "::/0"
          ];
          endpoint = "89.238.174.2:51820";
          persistentKeepalive = 25;
        }
      ];
    };
    hosts = {
      # TODO(apc):  del dumb fake dns
      "172.16.0.1" = [ "router.lan" ];
      "192.168.1.200" = [ "NAS" ];
    };
    # TODO(apc): make a gaming aspect and move this into a steam module
    extraHosts = "0.0.0.0 crash.steampowered.com";
    firewall = {
      enable = lib.mkForce true;
      allowPing = false;
      trustedInterfaces = [ "vmtap2" ];
      allowedTCPPorts = [
        1234
        2234
      ];
    };
  };
}
