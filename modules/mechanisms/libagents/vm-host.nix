/**
  # `flake.modules.nixos.agent-vm`

  The host half of the agent VM: it owns the VM declaration and it owns the
  host-side end of every channel. A mechanism rather than a feature — no host
  would name "runs a VM
  manager for coding agents" as a capability it wants; the harnesses want it,
  and this serves them (`docs/modules.md` §"Reusable modules").

  **One owner for the VM** (`docs/modules.md` §"Shared instances"). This
  module declares `microvm.vms.<name>` exactly once. Harness modules must
  never declare a VM of their own: several harnesses are meant to share one
  guest, so a second declaration is either an outright conflict or an
  accidental merge, and anything that refcounts sessions over the instance
  becomes meaningless. Harnesses contribute the facts that are
  theirs — `projectRoots` and `stateDirs` — and may raise `enable` as an
  `mkDefault`. `hostUser`, `uid`, `vcpu`, `mem` and the vsock
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
    ask the host to substitute from any binary cache it likes, which must be
    refused. Untrusted is not read-only: an untrusted
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

  ## Lifecycle

  `agent-vm-session -- <command>` registers a user-manager scope before
  startup, starts the fixed installed VM service, waits for its sshd, and
  executes the command over SSH. Scope lifetime follows its processes, so
  cleanup needs no explicit release from a trap. Slow startup and sessions
  longer than the idle interval retain their reference.

  A supervised user service counts only this VM's active scopes. Once the
  last disappears, it waits `lifecycle.lingerSeconds` before shutdown.
  Acquisition, idle decisions and recovery share one user-owned flock.
  No caller-defined root transient units or dependencies are authorized.
  The system VM is bound to the fixed host user's manager, so manager exit
  tears it down even if the controller has failed. This requires an explicit
  matching host UID and does not enable login linger.

  `--forward <ssh -L spec>` carries a guest endpoint to host loopback for
  the session. Harness wrappers choose the capability and call this entry
  point; the mechanism only transports the forwarding specification.

  `--reverse-forward <ssh -R spec>` carries a host endpoint into guest
  loopback for the session. Its consumer chooses the ports and capability;
  the isolation mechanism treats it as an opaque forwarding specification.

  `agent-vm-stop` stops immediately if there are no sessions. Otherwise it
  requests shutdown after the final scope exits, without the idle delay.
  A new acquisition cancels that early-stop request.

  `agent-vm-restart` is explicitly disruptive recovery. It stops the guest
  and virtiofsd supervisord and leaves them down. The next session starts
  fresh daemons. `StopWhenUnneeded` on the shares also cleans up after an
  unexpected guest exit. The VM itself must not use that setting because
  its references live in a different manager.

  The `security.polkit.extraConfig` rule is what lets `hostUser` — an
  unprivileged account — start and stop these specific units at all;
  `systemctl start/stop` on a system unit is refused by default otherwise.
  It grants only the exact VM start/stop and exact shares stop operations.
  Even the owner cannot replace those installed units with transient ones
  or supply auxiliary services and root execution properties.

  ## Why the microvm.nix host module, this early

  It generates `microvm@<name>.service` with `microvm-virtiofsd@<name>.service`
  as a dependency, so the "start the daemons yourself" problem that
  `packages.agent-vm-run` exists to solve stops being the deployment path
  (`agent-vm-run` stays a dev tool for throwaway guests like the smoke test).
  Those daemons run as root, which is what makes store paths appear correctly
  owned inside the guest. It gives session refcounting exactly one unit to
  hang off.

  `autostart` defaults to **false**: enabling this module should cost a build,
  not a permanently running VM. Sessions decide when the guest actually runs.

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

      # The guest's sshd host key as a deployed secret: a committed public
      # half plus an agenix-encrypted private half, the same shape
      # `modules/features/nix-store-signing.nix` uses for a runtime secret
      # with a public commit — chosen over a store-generated key so the
      # guest's identity is a stable, reproducible fact rather than whatever
      # the first build happened to produce. Named by `cfg.name` with
      # dashes stripped, matching how `data/identities/ssh-host-vm` and
      # `secrets/ssh-host-vm` are keyed — kept distinct from `cfg.name`
      # itself so the file-naming convention (no dashes, matching every
      # other `ssh_host_ed25519_key_<name>` file in the repository) does not
      # have to constrain what a guest may be named.
      guestKeyName = lib.replaceStrings [ "-" ] [ "" ] cfg.name;
      hostKeySecret = self.secrets.sshHostVm guestKeyName;
      committedHostPublicKey = self.data.vars.identities.ssh-host-vm.${guestKeyName} or null;


      # `vmUnitName` is the `systemd.services.<name>` attribute (no
      # `.service` suffix — NixOS appends it); `vmUnit` is the resulting unit
      # name, used everywhere a unit is *referenced* (`Wants=`, polkit, the
      # session script) rather than defined.
      vmUnitName = "microvm@${cfg.name}";
      vmUnit = "${vmUnitName}.service";
      # microvm.nix names the virtiofsd unit after the same instance. It is
      # only ever referenced here, never defined by the lifecycle scripts.
      virtiofsdUnit = "microvm-virtiofsd@${cfg.name}.service";
      runner = config.microvm.vms.${cfg.name}.config.config.microvm.declaredRunner;
      stateDir = toString config.microvm.stateDir;
      sharesRuntime = "agent-vm-shares-${cfg.name}";
      hostPublicKey =
        if cfg.hostKey.file != null && committedHostPublicKey != null then
          lib.removeSuffix "\n" committedHostPublicKey
        else
          (self.lib.agents.mkAgentVmHostKey pkgs cfg.name).publicKey;
      knownHosts = pkgs.writeText "agent-vm-known-hosts-${cfg.name}" ''
        [localhost]:${toString cfg.sshHostPort} ${hostPublicKey}
      '';
      lifecycle = self.lib.agents.mkVmLifecycle pkgs {
        inherit (cfg) name hostUser sshHostPort;
        inherit knownHosts;
        inherit (cfg.lifecycle) lingerSeconds readyTimeoutSeconds;
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

        stateDirs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = lib.literalExpression ''
            self.lib.agents.stateDirsFor "/home/user" [ "claude" ]
          '';
          description = ''
            Host directories holding an agent's live state — sessions,
            memories, caches, credentials — shared into the guest read-write
            at the identical path, so a session survives the guest being
            destroyed.

            Another contribution point, and deliberately *not* defaulted to
            anything: which directories exist is a harness fact
            (`flake.lib.agents.stateDirs`), and this module is forbidden from
            naming one. The host wires the two together, because the host is
            what decides which harnesses are attached in the first place.

            Kept separate from `projectRoots` even though both become the
            same kind of share: the two answer different questions ("what may
            the agent work on" versus "what must outlive the guest"), and a
            single merged list would make it impossible to tell later which
            was which.
          '';
        };

        localStateDirs = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                path = lib.mkOption { type = lib.types.str; };
                size = lib.mkOption { type = lib.types.ints.positive; };
              };
            }
          );
          default = [ ];
          description = ''
            Guest-local durable directories backed by block volumes. Use these
            for state, such as SQLite WAL databases, that is unsafe on virtiofs.
          '';
        };

        guestEnvironment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = lib.literalExpression ''{ CLAUDE_CONFIG_DIR = "/home/user/.claude"; }'';
          description = ''
            Environment variables set in the guest. For values that must be
            *identical* on both sides — a harness that is told where its
            config directory is on the host and disagrees inside the guest
            writes state neither side reads back.

            Opaque strings on purpose: this module passes them through
            without interpreting them, which is what lets the harness layer
            own the meaning (`flake.lib.agents.environmentFor`).
          '';
        };

        guestEtc = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          example = lib.literalExpression ''{ "codex/config.toml" = ./hooks.toml; }'';
          description = ''
            Files placed in the guest's `/etc`, keyed by their `/etc`-relative
            path. For harness configuration that a vendor CLI only honours
            from a system location, which a guest running no Home Manager
            cannot otherwise receive.

            Opaque paths on purpose, for the same reason as
            `guestEnvironment`: this module places them without interpreting
            them.
          '';
        };

        authorizedKeys = lib.mkOption {
          type = lib.types.listOf lib.types.nonEmptyStr;
          default = [ ];
          description = "SSH public keys accepted for the guest user.";
        };

        vcpu = lib.mkOption {
          type = lib.types.ints.positive;
          default = 8;
          description = ''
            Guest vCPU count. Platform policy, not a harness concern. These
            are threads QEMU schedules onto whatever the host has free, not
            reserved cores, so this only caps the guest's parallelism.
          '';
        };

        mem = lib.mkOption {
          type = lib.types.ints.positive;
          default = 24576;
          description = ''
            Guest memory in MiB. A ceiling rather than a reservation: the
            guest balloons pages back to the host when idle, so this is what
            an agent may spike to (a flake-wide `nix eval` is the usual
            reason), not what the VM costs while sitting there.

            Not 2048: microvm.nix warns that QEMU hangs on exactly 2GB
            (upstream issue #171).
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
            sessions, which manage its lifecycle.
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

        hostKey = {
          file = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = if hostKeySecret.exists then hostKeySecret.file else null;
            defaultText = lib.literalExpression ''
              self.secrets.sshHostVm "<name-without-dashes>", if present
            '';
            description = ''
              Encrypted sshd host key for the guest. Absent (a bootstrap
              checkout with no ciphertext yet) falls back to a generated,
              non-reproducible, store-resident key with a build warning —
              never a hard failure, since a fresh checkout has nothing to
              decrypt.
            '';
          };

          runtimePath = lib.mkOption {
            type = lib.types.nonEmptyStr;
            default = "/run/agenix/agent-vm-host-key-${cfg.name}";
            description = "Decrypted runtime path of the guest's sshd host key.";
          };
        };

        lifecycle = {
          readyTimeoutSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 60;
            description = "Maximum time to wait for the guest SSH listener, without host-native fallback.";
          };
          lingerSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 120;
            description = ''
              How long the guest is kept running after the last agent session
              exits, so exiting one session and immediately starting another
              does not re-boot it. Active sessions never expire this way.
            '';
          };
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
                  stateDirs
                  localStateDirs
                  guestEnvironment
                  guestEtc
                  authorizedKeys
                  vcpu
                  mem
                  sshHostPort
                  channels
                  ;
                hostKey =
                  if cfg.hostKey.file != null then
                    {
                      path = cfg.hostKey.runtimePath;
                      publicKey = committedHostPublicKey;
                    }
                  else
                    self.lib.agents.mkAgentVmHostKey pkgs cfg.name;
              };
            };

            # Upstream makes metadata kvm-writable and invokes privileged
            # scripts through current/booted symlinks. kvm membership must
            # not turn this fixed-unit grant into arbitrary root execution.
            # Keep existing image/socket paths, but protect the parent and
            # instance from other kvm users. QEMU retains owner write access.
            systemd.tmpfiles.settings."10-microvm" = {
              ${stateDir}.d = {
                user = lib.mkForce "root";
                group = lib.mkForce "root";
                mode = lib.mkForce "0755";
              };
              "${stateDir}/${cfg.name}".d = {
                user = lib.mkForce "microvm";
                group = lib.mkForce "root";
                mode = lib.mkForce "0755";
              };
            };

            # Even a compromised QEMU process must not replace a later root
            # executable or use supervisor's default relative logs as root
            # symlink-write targets. Only immutable configured scripts run.
            systemd.services."microvm-virtiofsd@${cfg.name}" = {
              unitConfig.StopWhenUnneeded = true;
              serviceConfig = {
                ExecStart = lib.mkForce [
                  ""
                  "${runner}/bin/virtiofsd-run --logfile /dev/null --pidfile /run/${sharesRuntime}/supervisord.pid --childlogdir /run/${sharesRuntime}"
                ];
                RuntimeDirectory = sharesRuntime;
                RuntimeDirectoryMode = "0700";
              };
            };
            systemd.services."microvm-tap-interfaces@${cfg.name}".serviceConfig = {
              ExecStart = lib.mkForce [ "" "${runner}/bin/tap-up" ];
              ExecStop = lib.mkForce [ "" "${runner}/bin/tap-down" ];
            };
            systemd.services."microvm-macvtap-interfaces@${cfg.name}" = {
              overrideStrategy = "asDropin";
              serviceConfig.ExecStart = lib.mkForce [ "" "${runner}/bin/macvtap-up" ];
            };
            systemd.services."microvm-pci-devices@${cfg.name}".serviceConfig.ExecStart =
              lib.mkForce [ "" "${runner}/bin/pci-setup" ];

            warnings = lib.optional (cfg.hostKey.file == null) ''
              agent-vm: no encrypted host key for '${cfg.name}'
              (secrets/ssh-host-vm/ssh_host_ed25519_key_${guestKeyName}.age);
              falling back to a generated, non-reproducible sshd host key.
            '';

            age.secrets."agent-vm-host-key-${cfg.name}" = lib.mkIf (cfg.hostKey.file != null) {
              file = cfg.hostKey.file;
              path = cfg.hostKey.runtimePath;
              # Read by qemu itself via `-fw_cfg ...,file=...` (not by the
              # guest-side ImportCredential unit, which runs inside the VM),
              # so it must be readable by the *host's* microvm/qemu user —
              # microvm.nix's declarative runner runs unprivileged as
              # `microvm:kvm`, not root.
              owner = "microvm";
              group = "kvm";
              mode = "0400";
            };

            # Instance-specific config for the *particular*
            # `microvm@<name>.service` this module declares, not the
            # `microvm@.service` template — NixOS's systemd module merges a
            # `"unit@instance"` definition as that instance's own drop-in, so
            # this only ever touches this VM's unit.
            systemd.services.${vmUnitName} = {
              serviceConfig.Restart = lib.mkForce "no";
              # This guest does not register with machined. The upstream +
              # hooks otherwise execute mutable current/booted paths as root.
              serviceConfig.ExecStartPost = lib.mkForce [ "" ];
              serviceConfig.ExecStopPost = lib.mkForce [ "" ];
              # User scopes cannot reference-count a system-manager unit.
              # The user controller owns idle shutdown; manager exit stops
              # this fixed root-owned unit even if the controller has failed.
              bindsTo = lib.optional (cfg.uid != null) "user@${toString cfg.uid}.service";
              after = lib.optional (cfg.uid != null) "user@${toString cfg.uid}.service";
            };

            # Ties the shares' lifetime to the guest's, the same way the
            # guest's is tied to its sessions. Without this, a stopped guest
            # leaves the virtiofsd unit behind in a state that reads healthy
            # but serves nothing, and every later boot fails against it —
            # the wedge `agent-vm-restart` exists to undo. Two upstream
            # facts combine into it:
            #
            # 1. virtiofsd exits *cleanly* (status 0) when its guest
            #    disconnects, and microvm.nix supervises the shares with a
            #    supervisord whose programs take the default
            #    `autorestart=unexpected` — which restarts only on an exit
            #    code outside `exitcodes` (`0`). A clean exit is by
            #    definition expected, so the shares are never respawned.
            # 2. The supervisord parent stays up regardless, so the unit
            #    remains `active (running)` with no daemon behind it and
            #    systemd's own `Restart=always` sees nothing to act on. The
            #    `.sock` files also outlive their daemons, so qemu gets
            #    `Connection refused` rather than a missing path.
            #
            # `partOf = [ vmUnit ]` upstream does not cover it: that
            # propagates explicit stop and restart *jobs*, and the guest
            # exiting on its own is neither. `StopWhenUnneeded` keys off the
            # only fact that actually holds — `microvm@` (its sole referrer,
            # via `Requires=`) no longer being active — so the unit is torn
            # down whenever the guest goes away, however it went, and the
            # next `Requires=` pulls in a fresh one.
            #
            # Chosen over flipping the shares to `autorestart=true`, which
            # would mean overriding `microvm.binScripts.virtiofsd-run` (a
            # fork of upstream's generator, to drift silently on the next
            # bump) and would leave idle daemons resident with no guest to
            # serve. This is one line against the unit upstream already
            # declares, and it deletes the daemons instead of idling them.

            systemd.user.services.agent-vm-lifecycle = {
              description = "Agent VM idle controller";
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = cfg.hostUser;
              serviceConfig = {
                ExecStart = lib.getExe lifecycle.monitor;
                Restart = "always";
                RestartSec = "1s";
              };
            };

            environment.systemPackages = with lifecycle; [ session stop restart ];

            assertions = [ {
              assertion = cfg.uid != null && cfg.uid == config.users.users.${cfg.hostUser}.uid;
              message = "agent-vm requires a fixed host user UID matching agent-vm.uid for ownership and user-manager lifetime binding";
            } ];

            security.polkit.enable = true;
            security.polkit.extraConfig = ''
              polkit.addRule(function(action, subject) {
                if (action.id != "org.freedesktop.systemd1.manage-units"
                    || subject.user != ${builtins.toJSON cfg.hostUser}) return;
                var verb = action.lookup("verb");
                var unit = action.lookup("unit");
                if ((unit == ${builtins.toJSON vmUnit} && (verb == "start" || verb == "stop"))
                    || (unit == ${builtins.toJSON virtiofsdUnit} && verb == "stop")) {
                  return polkit.Result.YES;
                }
              });
            '';

            # virtiofsd refuses to start on a source directory that does not
            # exist, which would take the whole guest down with it — and a
            # state directory legitimately does not exist until the harness
            # has been run once. Creating them here makes the VM's shares
            # well-defined on a fresh machine.
            #
            # Ownership is `hostUser`, not root: the share passes uids
            # through numerically (`securityModel = "none"`), so a root-owned
            # directory would be root-owned inside the guest too and the
            # agent could not write to it.
            #
            # The mode is `-` (tmpfiles' default, 0755 on creation) rather
            # than a tightened 0700, because tmpfiles applies a stated mode
            # to *existing* directories on every boot as well: enabling the
            # agent VM would then quietly re-chmod the user's live `~/.claude`
            # and `~/.cache`, which is a policy change this module was not
            # asked to make. Ownership is the part the share actually needs.
            #
            # Intermediate directories get a rule of their own because
            # systemd-tmpfiles creates a missing parent as root — which is
            # how sharing `~/.cache/claude-cli-nodejs` on a machine without a
            # `~/.cache` yet would leave the user unable to write to their
            # own cache directory.
            systemd.tmpfiles.rules =
              let
                home = "/home/${cfg.hostUser}";
                ancestors =
                  directory:
                  let
                    parts = lib.splitString "/" (lib.removePrefix "${home}/" directory);
                  in
                  lib.imap1 (index: _: "${home}/${lib.concatStringsSep "/" (lib.take index parts)}") (
                    lib.drop 1 parts
                  );
                inside = lib.filter (directory: lib.hasPrefix "${home}/" directory) cfg.stateDirs;
              in
              lib.unique (
                map (directory: "d ${directory} - ${cfg.hostUser} users - -") (lib.concatMap ancestors inside)
              )
              ++ map (directory: "d ${directory} - ${cfg.hostUser} users - -") cfg.stateDirs;

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
              {
                assertion =
                  let
                    trusted = config.nix.settings.trusted-users;
                    proxy = config.users.users.${cfg.nixProxyUser};
                    groups = [ proxy.group ] ++ proxy.extraGroups
                      ++ builtins.attrNames (lib.filterAttrs
                        (_: group: builtins.elem cfg.nixProxyUser group.members)
                        config.users.groups);
                  in
                  !(builtins.elem "*" trusted || builtins.elem cfg.nixProxyUser trusted
                    || builtins.any (group: builtins.elem "@${group}" trusted) groups);
                message = "agent-vm: the Nix channel proxy must not be a trusted user, directly or through a group";
              }
              {
                assertion = cfg.hostKey.file == null || committedHostPublicKey != null;
                message = ''
                  agent-vm: secrets/ssh-host-vm/ssh_host_ed25519_key_${guestKeyName}.age
                  exists but data/identities/ssh-host-vm has no '${guestKeyName}'
                  entry. Deploying the private half with no committed public
                  half to pin known_hosts against is a mismatch waiting to
                  happen — add the '.pub' and the identities entry, or
                  remove the ciphertext.
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
                (self.lib.agents.vmChannels.proxyService pkgs "Agent VM nix daemon channel connection %i" "UNIX-CONNECT:/nix/var/nix/daemon-socket/socket")
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
