{
  userPreferences.alaestor.modules = [
    {
      pgp.primaryFingerprint = "4E4AAED523F37DB64B329CCFA9B285CEFFACEEC5"; # TODO: pull ssh fingerprint from data identities
      ssh-client.identityFile = "~/.ssh/ssh_sk";  # TODO(secrets): integration for ssh ident file

      programs.git.settings.user = {
        name = "Alaestor Weissman";
        email = "alaestor@0x04.cc";
      };
    }
  ];
}
