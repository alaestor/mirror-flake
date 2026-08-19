/**
  # `flake.modules.nixos.agent-vm`

  The host half of the agent VM: it owns the VM declaration and it owns the
  host-side end of every channel (`__reference/microvm/implementation-guide.md`
  Phase 5). A mechanism rather than a feature — no host would name "runs a VM
  manager for coding agents" as a capability it wants; the harnesses want it,
  and this serves them (`docs/modules.md` §"Reusable modules").

  **One owner for the VM** (`docs/modules.md` §"Shared instances"). This
  module declares `microvm.vms.<name>` exactly once. Harness modules must
  never declare a VM of their own: several harnesses are meant to share one
  guest, so a second declaration is either an outright conflict or an
  accidental merge, and anything that refcounts sessions over the instance
  (Phase 7) becomes meaningless. Harnesses contribute the facts that are
  theirs — `projectRoots` today, state directories in Phase 6 — and may raise
  `enable` as an `mkDefault`. `hostUser`, `uid`, `vcpu`, `mem` and the vsock
  CID are platform policy: this module's defaults, the host's to override, and
  never a harness's business.

  ## The channels

  Both are the same shape: a systemd socket listening on `AF_VSOCK` with
  `Accept = true`, handing each connection to socat, which connects to the
  real unix socket. The guest dials CID 2 on the port; see `vm-channels.nix`
  for why the listener binds any CID rather than the guest's.

  - **nix daemon.** The listener runs as `nixProxyUser`, a system account
    that is deliberately *not* in `nix.settings.trusted-users`. The host
    daemon authenticates by peer credentials, so whatever uid this proxy runs
    as is the identity the whole guest gets: run it as root and the guest can
    ask the host to substitute from any binary cache it likes, which the guide
    is emphatic must be refused. Untrusted is not read-only: an untrusted
    client may still build derivations and add paths, which is the whole
    point — it just cannot tell the daemon *where to trust content from*.
    The account must appear in `allowed-users`, which an assertion checks
    rather than defines (see below).
  - **gpg-agent.** The listener runs as `hostUser` and connects to the
    **restricted** socket — `agent-extra-socket`, which signs and decrypts but
    refuses to export a key — resolved by asking `gpgconf` at connection time
    rather than hardcoding `/run/user/<uid>/gnupg/...`, since that path is
    both uid-dependent and version-dependent. Because it lives under
    `/run/user/<uid>`, the channel only works while that user has a session on
    the host; with no session there is no agent to forward to, and the guest
    sees a connection refused. That is the honest failure — a signature needs
    the human at the machine anyway.

  ## Why the microvm.nix host module, this early

  It generates `microvm@<name>.service` with `microvm-virtiofsd@<name>.service`
  as a dependency, so the "start the daemons yourself" problem that
  `packages.agent-vm-run` exists to solve stops being the deployment path
  (`agent-vm-run` stays a dev tool for throwaway guests like the smoke test).
  Those daemons run as root, which is what makes store paths appear correctly
  owned inside the guest. And it gives Phase 7 exactly one unit to hang
  session refcounting off.

  `autostart` defaults to **false**: enabling this module should cost a build,
  not a permanently running VM. Phase 7 decides when the guest actually runs.

  `boot.kernelModules` and the udev rule exist because a guest with a channel
  has `microvm.vsock.cid` set, so QEMU opens `/dev/vhost-vsock`; without the
  module loaded the node does not exist, and without the rule only root may
  open it, which breaks the unprivileged `agent-vm-run` path for no benefit
  (the `kvm` group already gates who may run VMs at all).
*/
{ inputs, self, ... }:
{
  flake.modules.nixos.agent-vm =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.agent-vm;
      inherit (self.lib.agents.vmChannels) ports;

      # Mirrors the guest side in `vm.nix`: systemd accepts the connection and
      # socat is only responsible for the other end of it.
      proxyService = description: target: {
        inherit description;
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.socat} - ${target}";
          StandardInput = "socket";
          StandardOutput = "socket";
          Restart = "no";
        };
      };
    in
    {
      # microvm.nix's host module, not its guest module: this generates
      # `microvm@<name>.service` and the virtiofsd unit it depends on. It is
      # imported unconditionally so `microvm.vms` exists to be read even on a
      # host that leaves `agent-vm.enable` off; the module itself adds nothing
      # to a host with no VMs declared.
      imports = [ inputs.microvm.nixosModules.host ];

      options.agent-vm = {
        enable = lib.mkEnableOption "the shared agent microVM and its host-side channels";

        name = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "agent-vm";
          description = ''
            Name of the single shared guest. Also seeds its MAC and vsock CID,
            so changing it re-derives both.
          '';
        };

        hostUser = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = config.hostIdentity.primaryUser;
          defaultText = lib.literalExpression "config.hostIdentity.primaryUser";
          description = ''
            The host account the guest mirrors: the guest user takes the same
            name, home path and (with `uid`) numeric id, and the gpg channel
            forwards this account's agent.
          '';
        };

        uid = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = config.users.users.${cfg.hostUser}.uid or null;
          defaultText = lib.literalExpression "the host user's uid, if it is statically known";
          description = ''
            Numeric uid to give the guest user. virtiofs passes ownership
            through numerically, so a mismatch makes shared files look
            wrong-owned inside the guest.
          '';
        };

        projectRoots = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "/home/user/Projects" ];
          description = ''
            Host directories shared into the guest at the identical path.
            This is a contribution point: harness modules add the roots they
            need and the lists merge.
          '';
        };

        authorizedKeys = lib.mkOption {
          type = lib.types.listOf lib.types.nonEmptyStr;
          default = [ ];
          description = "SSH public keys accepted for the guest user.";
        };

        vcpu = lib.mkOption {
          type = lib.types.ints.positive;
          default = 2;
          description = "Guest vCPU count. Platform policy, not a harness concern.";
        };

        mem = lib.mkOption {
          type = lib.types.ints.positive;
          default = 4096;
          description = ''
            Guest memory in MiB. Not 2048: microvm.nix warns that QEMU hangs
            on exactly 2GB (upstream issue #171).
          '';
        };

        sshHostPort = lib.mkOption {
          type = lib.types.port;
          default = 2222;
          description = "Host port forwarded to the guest's sshd.";
        };

        autostart = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Start the guest at boot. Off by default: the VM is a tool for
            sessions, and Phase 7 gives it a lifecycle of its own.
          '';
        };

        nixProxyUser = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "agent-vm-nix";
          description = ''
            System account the nix daemon listener runs as. Its whole purpose
            is to be untrusted; do not add it to `nix.settings.trusted-users`.
          '';
        };

        channels = {
          nixDaemon.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Forward the host's nix daemon into the guest.";
          };

          gpgAgent = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Forward the host user's restricted gpg-agent socket into the guest.";
            };

            certificates = lib.mkOption {
              type = lib.types.listOf lib.types.nonEmptyStr;
              default = [ self.data.vars.identities.administrative.pgp.certificate ];
              defaultText = lib.literalExpression "the administrative OpenPGP certificate";
              description = ''
                Armored public certificates to build the guest's keyring
                from. Public material only, and from the repository rather
                than from anyone's `$HOME`.
              '';
            };

            ultimatelyTrusted = lib.mkOption {
              type = lib.types.listOf lib.types.nonEmptyStr;
              default = [ self.data.vars.identities.administrative.pgp.fingerprint ];
              defaultText = lib.literalExpression "the administrative OpenPGP fingerprint";
              description = "Fingerprints to mark ultimately trusted in the guest's trustdb.";
            };
          };
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            microvm.host.enable = true;
            microvm.vms.${cfg.name} = {
              inherit (cfg) autostart;
              config = self.lib.agents.mkAgentVm {
                inherit (cfg)
                  name
                  hostUser
                  uid
                  projectRoots
                  authorizedKeys
                  vcpu
                  mem
                  sshHostPort
                  channels
                  ;
              };
            };

            boot.kernelModules = [ "vhost_vsock" ];
            services.udev.extraRules = ''
              KERNEL=="vhost-vsock", GROUP="kvm", MODE="0660"
            '';
          }

          (lib.mkIf cfg.channels.nixDaemon.enable {
            users.users.${cfg.nixProxyUser} = {
              isSystemUser = true;
              group = cfg.nixProxyUser;
              description = "Untrusted nix client for agent VMs";
            };
            users.groups.${cfg.nixProxyUser} = { };

            # Deliberately an assertion rather than a definition: defining
            # `allowed-users` here would *replace* the option's `[ "*" ]`
            # default on a host that has not narrowed it, silently locking
            # every other account out of the daemon. A host that has narrowed
            # it has made a policy decision this module has no business
            # editing — it just refuses to build until the decision covers
            # the proxy user.
            assertions = [
              {
                assertion =
                  let
                    allowed = config.nix.settings.allowed-users;
                  in
                  builtins.elem "*" allowed || builtins.elem cfg.nixProxyUser allowed;
                message = ''
                  agent-vm: nix.settings.allowed-users does not permit
                  '${cfg.nixProxyUser}', so the guest's nix daemon channel
                  would be refused by the host daemon. Add it to
                  nix.settings.allowed-users (and *not* to trusted-users).
                '';
              }
            ];

            systemd.sockets.agent-vm-nix-daemon = {
              description = "Agent VM nix daemon channel";
              wantedBy = [ "sockets.target" ];
              socketConfig = {
                # Any CID: one listener serves every guest, and the guest's
                # identity would not be worth anything here anyway.
                ListenStream = "vsock::${toString ports.nixDaemon}";
                Accept = true;
              };
            };

            systemd.services."agent-vm-nix-daemon@" =
              lib.recursiveUpdate
                (proxyService "Agent VM nix daemon channel connection %i" "UNIX-CONNECT:/nix/var/nix/daemon-socket/socket")
                { serviceConfig.User = cfg.nixProxyUser; };
          })

          (lib.mkIf cfg.channels.gpgAgent.enable {
            # The restricted socket does not exist unless gpg-agent is asked
            # for it (`--extra-socket`), and it is a Home Manager setting on a
            # per-user service, so the channel has to reach across to the
            # user's environment to get its own prerequisite. This is the
            # documented direction of travel — NixOS contributes to Home
            # Manager, never the reverse (`docs/hosts-and-homes.md`
            # §"Feature contributions and host context").
            #
            # Guarded by username: contributions apply to *every* environment
            # attached to the host, and only the account whose agent is being
            # forwarded has any use for the socket.
            #
            # Without it the proxy connects to a path that does not exist and
            # the guest's gpg, having failed to reach any agent, reports
            # "No secret key" — which reads like a missing keyring rather
            # than a missing socket.
            userEnvironment.sharedModules = [
              (
                { config, lib, ... }:
                lib.mkIf (config.home.username == cfg.hostUser) {
                  services.gpg-agent.enableExtraSocket = lib.mkDefault true;
                }
              )
            ];

            systemd.sockets.agent-vm-gpg-agent = {
              description = "Agent VM gpg-agent channel";
              wantedBy = [ "sockets.target" ];
              socketConfig = {
                ListenStream = "vsock::${toString ports.gpgAgent}";
                Accept = true;
              };
            };

            # Not built through `proxyService`: the target path is only
            # knowable at connection time (the restricted socket lives under
            # /run/user/<uid> and gnupg has moved it between versions), so
            # this asks gpgconf and then becomes socat.
            systemd.services."agent-vm-gpg-agent@" = {
              description = "Agent VM gpg-agent channel connection %i";
              serviceConfig = {
                ExecStart = pkgs.writeShellScript "agent-vm-gpg-agent-connect" ''
                  exec ${lib.getExe pkgs.socat} - \
                    "UNIX-CONNECT:$(${lib.getExe' pkgs.gnupg "gpgconf"} --list-dirs agent-extra-socket)"
                '';
                StandardInput = "socket";
                StandardOutput = "socket";
                Restart = "no";
                User = cfg.hostUser;
              };
            };
          })
        ]
      );
    };
}
