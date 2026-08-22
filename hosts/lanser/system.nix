{ inputs, tailnet }:
{
  config,
  pkgs,
  ...
}:
let
  username = config.hostIdentity.primaryUser;
  secretPath = inputs.self.secrets.path;
in
{
  age = {
    identityPaths = [ config.ssh-host.hostKeyPath ];
    secrets = {
      lanser-torrenting-wireguard-config = {
        file = secretPath "vpn_P2PUSCA560.conf.age";
        mode = "0400";
      };
      lanser-headplane-cookie-secret = {
        file = secretPath "headplane_cookie-secret.age";
        owner = "headscale";
        group = "headscale";
        mode = "0400";
      };
    };
  };

  services = {
    displayManager = {
      defaultSession = "lxqt";
      autoLogin = {
        enable = true;
        user = username;
      };
    };
    xserver = {
      enable = true;
      desktopManager.lxqt.enable = true;
      displayManager.lightdm.enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    git
    openssh
    pinentry-tty
    btop
    iftop
    ghostty
    tmux
    home-manager
    p7zip
    unrar
    unar
    mozlz4a
    chromium
  ];

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
  };

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  ssh-host = {
    allowUsers = [ username ];
    comment = "lanser-hostkey";
  };

  nas = {
    server = "192.168.2.200";
    vault = {
      enable = true;
      readonly = true;
    };
    pocket.enable = true;
    services.enable = true;
  };

  serve = {
    caddy = {
      enable = true;
      bindAddress = "172.16.0.4"; # TODO: should host identity contain static/reserved ip?
    };
    cinny.enable = true;
    filebrowser.enable = true;
    headscale = {
      enable = true;
      adminAllowedCIDRs = [ # TODO(global): somewhere to define LAN?
        "172.16.0.0/24"
      ];
      cookieSecretFile = config.age.secrets.lanser-headplane-cookie-secret.path;
    };
    jellyfin.enable = true;
    matrix.enable = true;
    static-site.enable = true;
    torrenting = {
      enable = true;
      wireguardConfigFile = config.age.secrets.lanser-torrenting-wireguard-config.path;
    };
  };

  services = {
    headscale.settings = { # TODO(domains): delegate headscale subdomain config to domain
      server_url = tailnet.coordinationUrl;
      dns = {
        magic_dns = true;
        base_domain = tailnet.dnsSuffix;
        override_local_dns = true;
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
      trusted_proxies = [ "127.0.0.1/32" ];
    };

    headplane.settings = {
      server.base_url = tailnet.coordinationUrl;
      headscale.public_url = tailnet.coordinationUrl;
    };
  };
}
