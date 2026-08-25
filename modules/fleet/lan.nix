/**
  Public facts for the fleet's general LAN.

  Before this, the same three addresses were written out independently in
  seven places, in three different subnets, with no single source of truth
  (`apc`'s gateway, `lanser`'s gateway, and the NAS's general-LAN address all
  duplicated `172.16.0.0/24`/`.1`/`.2`). This is that source of truth for the
  facts that are genuinely shared. It deliberately does not include
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
  };
}
