/**
  Public facts for the 0x04.cc tailnet.

  Fleet declarations define shared facts only. Hosts retain ownership of
  service credentials, storage paths, and machine-specific topology.
*/
{
  flake.fleet.tailnets."0x04cc" = {
    coordinationUrl = "https://headscale.0x04.cc";
    dnsSuffix = "tailnet.0x04.cc";
  };
}
