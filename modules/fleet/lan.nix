/**
  Public facts for the fleet's general LAN.

  Records the shared subnet, gateway, NAS address, and known host reservations.
  Reservations describe externally managed address assignments; this module
  does not configure a DHCP server or host interfaces. It deliberately excludes
  `lanser`'s direct-attach link to the NAS (`192.168.2.0/23`,
  `192.168.2.200`): that is a dedicated point-to-point subnet between two
  specific machines, not a fact about the LAN, and stays local to `lanser`'s
  own fragment.
*/
{
  flake.fleet.lan = {
    cidr = "172.16.0.0/24";
    gateway = "172.16.0.1";
    nas = "172.16.0.2";
    reservations.lanser = "172.16.0.4";
  };
}
