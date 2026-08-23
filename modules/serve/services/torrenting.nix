/**
  qBittorrent confined to a WireGuard VPN namespace.

  This is a private host service, not a public domain composition.
*/
{ inputs, ... }:
{
  nucleus.inputs.vpn-confinement.url = "git+https://git.0x04.cc/alaestor/mirror-VPN-Confinement";

  flake.modules.nixos.serve-torrenting =
    { config, lib, options, pkgs, ... }:
    let
      cfg = config.serve.torrenting;
      hasPocketMountpoint = lib.hasAttrByPath [ "nas" "pocket" "mountpoint" ] options;
    in
    {
      imports = [ inputs.vpn-confinement.nixosModules.default ];

      options.serve.torrenting = {
        enable = lib.mkEnableOption "qBittorrent in a confined WireGuard namespace";

        namespace = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "wgp2p";
          description = "VPN namespace used by qBittorrent.";
        };
        wireguardConfigFile = lib.mkOption {
          type = lib.types.str;
          default = "/etc/custom-secrets/P2PUSCA560.conf";
          description = "Runtime path to the WireGuard configuration.";
        };
        accessibleFrom = lib.mkOption {
          type = lib.types.listOf lib.types.nonEmptyStr;
          default = [ "172.16.0.0/24" ];
          description = "Private networks allowed to reach mapped qBittorrent ports.";
        };
        downloadPath = lib.mkOption {
          type = lib.types.str;
          default =
            if hasPocketMountpoint then
              "${config.nas.pocket.mountpoint}/qbittorrent"
            else
              "/mnt/Pocket/qbittorrent";
          defaultText = lib.literalExpression ''
            if the NAS module is present
            then "''${config.nas.pocket.mountpoint}/qbittorrent"
            else "/mnt/Pocket/qbittorrent"
          '';
          description = "Default qBittorrent download path.";
        };
        webuiPort = lib.mkOption {
          type = lib.types.port;
          default = 58080;
          description = "qBittorrent web interface port.";
        };
        torrentingPort = lib.mkOption {
          type = lib.types.port;
          default = 16868;
          description = "qBittorrent peer port.";
        };
      };

      config = lib.mkIf cfg.enable {
        vpnNamespaces.${cfg.namespace} = {
          enable = true;
          inherit (cfg) wireguardConfigFile accessibleFrom;
          portMappings = [
            {
              from = cfg.webuiPort;
              to = cfg.webuiPort;
            }
          ];
          openVPNPorts = [
            {
              port = cfg.torrentingPort;
              protocol = "both";
            }
          ];
        };

        services.qbittorrent = {
          enable = true;
          package = pkgs.qbittorrent-nox;
          inherit (cfg) webuiPort torrentingPort;
          openFirewall = false;
          extraArgs = [
            "--confirm-legal-notice"
            "--save-path=${cfg.downloadPath}"
          ];
        };

        systemd.services.qbittorrent.vpnConfinement = {
          enable = true;
          vpnNamespace = cfg.namespace;
        };
      };
    };
}
