/**
  Default collector and explicit scrape membership, without cross-host evaluation.
*/
{
  flake.fleet.telemetry = {
    server = "lanser";
    tailnet = "0x04cc";
    clients = [
      "apc"
      "armatus"
      "lanser"
    ];
  };
}
