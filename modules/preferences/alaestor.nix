{ self, ... }:
{
  userPreferences.alaestor.modules = [
    {
      pgp.primaryFingerprint = self.data.vars.identities.administrative.pgp.fingerprint;
      ssh-client.identityFile = "~/.ssh/ssh_sk";

      programs.git.settings.user = {
        name = "Alaestor Weissman";
        email = "alaestor@0x04.cc";
      };
    }
  ];
}
