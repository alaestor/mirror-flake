{ inputs, pkgs, ... }:
let
  # All private material is disposable test data, never a deployed identity.
  keys = pkgs.runCommand "agent-vm-fixture-keys" {
    nativeBuildInputs = [ pkgs.openssh pkgs.gnupg ];
  } ''
    mkdir -m700 "$out" "$out/gnupg"
    ssh-keygen -q -t ed25519 -N "" -f "$out/id_ed25519"
    export GNUPGHOME="$out/gnupg"
    gpg --batch --pinentry-mode loopback --passphrase "" \
      --quick-generate-key 'Disposable VM fixture <fixture@example.test>' ed25519 sign 0
    fingerprint=$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" {print $10; exit}')
    gpg --batch --pinentry-mode loopback --passphrase "" --quick-add-key "$fingerprint" cv25519 encr 0
    gpg --armor --export > "$out/public.asc"
    gpgconf --kill all
    # Sockets and agent locks must not enter a Nix output.
    rm -f "$out/gnupg/S.gpg-agent" "$out/gnupg/S.gpg-agent.extra" \
      "$out/gnupg/S.gpg-agent.browser" "$out/gnupg/S.gpg-agent.ssh"
  '';
  dbusPython = pkgs.python3.withPackages (p: [ p.dbus-python ]);
  authority = pkgs.writeScriptBin "agent-vm-authority-test" ''
    #!${dbusPython}/bin/python3
    ${builtins.readFile ./agent-vm/authority.py}
  '';
in
pkgs.testers.runNixOSTest {
  name = "agent-vm";
  nodes.machine = { lib, pkgs, ... }: {
    imports = [ inputs.self.modules.nixos.agent-vm inputs.agenix.nixosModules.default ];
    options = {
      hostIdentity = lib.mkOption { type = lib.types.attrs; };
      userEnvironment.sharedModules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
      };
    };
    config = {
      hostIdentity = { primaryUser = "fixture"; name = "fixture"; };
      users.users.fixture = { isNormalUser = true; uid = 1000; extraGroups = [ "kvm" ]; };
      users.users.other = { isNormalUser = true; uid = 1001; };
      # No admin group, no passwordless sudo, no extra polkit grants.
      agent-vm = {
        enable = true;
        name = "acceptance";
        hostUser = "fixture";
        projectRoots = [ "/home/fixture/Projects" ];
        stateDirs = [ "/home/fixture/shared-state" ];
        localStateDirs = [ { path = "/home/fixture/local-state"; size = 64; } ];
        authorizedKeys = [ (builtins.readFile "${keys}/id_ed25519.pub") ];
        vcpu = 2;
        mem = 768;
        lifecycle = { lingerSeconds = 4; readyTimeoutSeconds = 180; };
        hostKey.file = null;
        channels.gpgAgent = {
          certificates = [ (builtins.readFile "${keys}/public.asc") ];
          ultimatelyTrusted = [ ];
        };
      };
      microvm.vms.acceptance.extraModules = [ ({ lib, pkgs, ... }: {
        # The real production machine and CPU settings require nested KVM.
        environment.systemPackages = [ pkgs.util-linux ];
        systemd.services.sshd.preStart = lib.mkBefore "sleep 7";
        systemd.services.store-readonly-probe = {
          wantedBy = [ "multi-user.target" ];
          after = [ "nix-store.mount" ];
          serviceConfig.Type = "oneshot";
          script = ''
            touch /run/root-write-positive
            if touch /nix/store/guest-write-forbidden; then exit 1; fi
            touch /run/store-readonly-passed
          '';
        };
      }) ];
      virtualisation = {
        memorySize = 3072;
        diskSize = 4096;
        cores = 2;
        qemu.options = [ "-cpu" "host" ];
      };
      nix.settings = {
        experimental-features = [ "nix-command" ];
        substituters = lib.mkForce [ ];
        trusted-users = [ "root" ];
      };
      environment.systemPackages = [ pkgs.gnupg pkgs.openssh authority ];
      environment.etc."agent-vm-fixture-id".source = "${keys}/id_ed25519";
      system.extraDependencies = [ keys ];
      systemd.tmpfiles.rules = [
        "d /home/fixture/Projects 0755 fixture users -"
        "d /home/fixture/hidden 0755 fixture users -"
        "f /home/fixture/hidden/sentinel 0644 fixture users - host-only"
      ];
      # Disposable key import occurs at runtime so the proxy uses the ordinary
      # per-user runtime extra-socket path, just like a personal host session.
      systemd.services.fixture-gpg = {
        requires = [ "user@1000.service" ];
        after = [ "user@1000.service" ];
        serviceConfig = { User = "fixture"; Type = "forking"; };
        script = ''
          install -dm0700 /home/fixture/.gnupg /run/user/1000/gnupg
          cp -r ${keys}/gnupg/private-keys-v1.d ${keys}/gnupg/pubring.kbx /home/fixture/.gnupg/
          chmod -R u+rwX /home/fixture/.gnupg
          exec ${pkgs.gnupg}/bin/gpg-agent --daemon --no-detach \
            --extra-socket /run/user/1000/gnupg/S.gpg-agent.extra
        '';
      };
      systemd.services.fixture-ssh-agent = {
        requires = [ "user@1000.service" ];
        after = [ "user@1000.service" ];
        serviceConfig = {
          User = "fixture";
          ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a /run/user/1000/fixture-ssh-agent";
        };
      };
      # Inject a slow/failing root-owned unit prerequisite. The lifecycle
      # scripts, installed VM definition and policy remain the production ones.
      systemd.services."microvm@acceptance".serviceConfig.ExecStartPre = [
        "+${pkgs.writeShellScript "fixture-boot-gate" ''
          if test -e /run/fixture-fail-start; then exit 1; fi
        ''}"
      ];
    };
  };
  testScript = builtins.readFile ./agent-vm/runtime.py;
}
