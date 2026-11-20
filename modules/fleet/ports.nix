/**
  Fixed port assignments for concrete deployments. Local and remote ports
  live together; this table never opens a firewall or enables a service.
*/
{
  flake.fleet.ports = {
    shared = {
      # Protocol ports and ports that clients and servers must agree on.
      caddy-http = 80;
      caddy-https = 443;
      matrix-federation = 8448;
      jellyfin-https-alt = 44344;
      telemetry-metrics = 9100;
      telemetry-ingress = 3100;
      lm-studio = 1234;
      deepseek-web = 3080;
      agent-vm-guest-ssh = 22;
    };

    apc = {
      # Network-facing and firewall entries.
      ssh = 22;
      tailscale = 41641;
      nix-cache = 5000;
      soulseek = 2234;

      # Loopback only.
      agent-vm-ssh = 2222;
      alloy-http = 12345;
      cups = 631;
      node-exporter = 19100;
    };

    armatus = {
      # Network-facing, including SSH in the initrd.
      ssh = 22;
      ssh-initrd = 2222;
      tailscale = 41641;

      # Loopback only.
      alloy-http = 12345;
      node-exporter = 19100;
    };

    lanser = {
      # Network-facing, externally advertised, or opened in the firewall.
      ssh = 22;
      tailscale = 41641;
      forgejo-ssh-public = 38502;
      grafana = 3030;
      wireguard-firewall = 51820; # Firewall only; no listener configured here.

      # Local backends.
      alloy-http = 12345;
      dufs = 8087;
      forgejo = 3001;
      grafana-backend = 3031;
      headplane = 3000;
      headscale = 8092;
      jellyfin = 8096;
      loki = 3101;
      matrix = 6167;
      node-exporter = 19100;
      prometheus = 9090;
      telemetry-ingress-backend = 13100;

      # VPN namespace; the web port is mapped back to the host.
      qbittorrent-peers = 16868;
      qbittorrent-web = 58080;
    };

    bootstrap.ssh = 22;
    cryptid.ssh = 22;
    noblesse.ssh = 8022;
  };
}
