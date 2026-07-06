{ inputs, lib, ... }:
{
  host.bootstrap = {
    description = "Minimal NixOS installation ISO with remote SSH access.";
    primaryUser = "root";
    stateVersion = "26.11";
    capabilities.isoWriter = true;

    modules = [
      inputs.self.modules.nixos.isolive-minimal
      inputs.self.modules.nixos.ssh-host

      (
        { config, pkgs, ... }:
        {
          image.fileName = lib.mkForce (
            "${config.hostIdentity.name}-${pkgs.stdenv.hostPlatform.system}"
          );

          services.openssh.settings.PermitRootLogin = "prohibit-password";
          boot.kexec.enable = lib.mkForce true;
          ssh-host.allowUsers = [ config.hostIdentity.primaryUser ];
          services.getty.autologinUser = lib.mkForce config.hostIdentity.primaryUser;
        }
      )
    ];
  };
}
