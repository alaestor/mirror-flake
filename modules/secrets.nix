{ lib, self, ... }:
{
  options.flake.secrets = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
    description = "Paths and public recipient metadata for encrypted secrets.";
  };

  config.flake.secrets = rec {
    path = subpath: "${self}/secrets/${subpath}";
    exists = subpath: builtins.pathExists (path subpath);

    recipients = {
      administrators = self.data.vars.administrativeAgeRecipients;
      hosts = self.data.vars.sshHostPublicKeys;
    };
  };
}
