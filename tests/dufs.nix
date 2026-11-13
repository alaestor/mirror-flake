{ inputs, pkgs, system }:
let
  harness = import ./lib/serve-contract.nix { inherit inputs system; };
  fixture = harness.evaluate [
    inputs.self.modules.nixos.serve-dufs
    {
      serve.dufs = {
        enable = true;
        authFile = "/run/secrets/fixture-dufs.env";
        shares.Media = "/srv/fixture-media";
      };
    }
  ];
in
pkgs.runCommand "dufs-test"
  {
    nativeBuildInputs = [ pkgs.python3 pkgs.openssl ];
    DUFS_TEST_COMMAND = fixture.systemd.services.dufs.serviceConfig.ExecStart;
    DUFS_TEST_VALIDATOR = fixture.systemd.services.dufs.serviceConfig.ExecStartPre;
  }
  ''
    python ${./dufs/test_dufs.py}
    touch "$out"
  ''
