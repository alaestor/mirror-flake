{
  userPreferences.alaestor.modules = [
    {
      pgp.primaryFingerprint = "4E4AAED523F37DB64B329CCFA9B285CEFFACEEC5";
      ssh-client.identityFile = "~/.ssh/ssh_sk";  #TODO secrets flake

      programs.git.settings.user = {
        name = "Alaestor Weissman";
        email = "alaestor@0x04.cc";
      };
    }
  ];
}
