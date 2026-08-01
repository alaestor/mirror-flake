{ inputs, ... } :
{

  # Yubikey tooling
  flake.modules.nixos.crypto-yubikey-cli = { pkgs, ... } : {
    environment.systemPackages = with pkgs; [
      pcsc-tools
      yubikey-manager
      age-plugin-yubikey
    ];
    hardware.gpgSmartcards.enable = true;
    services.pcscd.enable = true;
  };
  flake.modules.nixos.crypto-yubikey = { pkgs, ... } : {
  imports =  with inputs.self.modules.nixos; [ crypto-yubikey-cli ];
    #environment.systemPackages = with pkgs; [];
    services.udev.packages = [ pkgs.yubikey-personalization ];
  };

  # Crypto
  flake.modules.nixos.crypto-cli = {config, pkgs, ... } : {
    environment.systemPackages = with pkgs; [
      pinentry-tty
      gnupg
      age
    ];
  };
  flake.modules.nixos.crypto = {config, pkgs, ... } : {
    imports =  with inputs.self.modules.nixos; [ crypto-cli ];
    environment.systemPackages = with pkgs; [
      veracrypt
    ];
  };

}
