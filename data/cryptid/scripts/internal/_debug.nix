{ context }:
with context;
{
  name = "_debug";
  description = "Set deterministic development values.";
  category = "internal";
  wrapped = false;
  hidden = true;
  content = ''
    # source to declare a bunch of variables to reduce interactions
    export CRYPTID_DEBUG=1
    export ${env.name}="MrDebug"
    export ${env.email}="d@d.com"
    pass="password123"
    export ${env.vaultpass}=$pass
    export ${env.yubi.fido.pin}=$pass
    export ${env.yubi.pgp.pin}=$pass
    export ${env.yubi.piv.pin}=7654321
    echo "Debug vars set"
  '';
}
