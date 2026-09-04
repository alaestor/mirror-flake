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
  (Phase 7) becomes meaningless. Harnesses contribute the facts that are
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

  ## Lifecycle (Phase 7)

  The VM starts on demand and stops once nothing needs it. `agent-vm-session`
  (`environment.systemPackages`) is the one entry point: `agent-vm-session --
  <command>` starts the guest if it is not already up, waits for its sshd,
  and runs `<command>` over ssh in a `systemd-run --scope` of its own — see
  that script's doc comment (next to `mkSessionScript` above) for why a scope
  needs no explicit release step, what `agent-vm-linger-hold.service` is for,
  and the two traps in microvm.nix's generated unit (`Restart = "always"`,
  `StopWhenUnneeded`'s lack of a grace period) that shaped it. Not yet called
  by any harness wrapper — that wiring is Phase 8's cutover, not this
  module's.

  `agent-vm-stop` (`mkStopScript`, next to `mkSessionScript`) is the manual
  counterpart: drops the linger-hold reference immediately rather than
  waiting out `lifecycle.lingerSeconds`, for a human who knows they are done
  for a while and would rather not leave the guest idling. It is a pure
  early-release, not a kill — an active session's own referrer keeps the
  guest up regardless, exactly as if the automatic linger had simply expired
  sooner.

  `agent-vm-restart` (`mkRestartScript`) is recovery rather than a third
  lifecycle verb — there is deliberately no `agent-vm-start`, since a session
  boots the guest itself. It takes the guest down and bounces the virtiofsd
  supervisord, the one wedged state a session cannot recover from on its own.
  `StopWhenUnneeded` on `microvm-virtiofsd@<name>` is what stops that state
  from arising in the first place; both carry the full reasoning.

  The `security.polkit.extraConfig` rule is what lets `hostUser` — an
  unprivileged account — start and stop these specific units at all;
  `systemctl start/stop` on a system unit is refused by default otherwise.

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
      committedHostPublicKey =
        self.data.vars.identities.ssh-host-vm.${guestKeyName} or null;

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

      # `vmUnitName` is the `systemd.services.<name>` attribute (no
      # `.service` suffix — NixOS appends it); `vmUnit` is the resulting unit
      # name, used everywhere a unit is *referenced* (`Wants=`, polkit, the
      # session script) rather than defined.
      vmUnitName = "microvm@${cfg.name}";
      vmUnit = "${vmUnitName}.service";
      # microvm.nix names the virtiofsd unit after the same instance. It is
      # only ever *referenced* here, never defined — see `mkRestartScript`.
      virtiofsdUnit = "microvm-virtiofsd@${cfg.name}.service";
      lingerHoldUnitName = "agent-vm-linger-hold";
      lingerHoldUnit = "${lingerHoldUnitName}.service";
      sessionPrefix = "agent-vm-session-";
      lingerCheckPrefix = "agent-vm-linger-check-";

      # Reference-counted lifecycle. Two systemd facts drove the shape, both
      # traps to check before trusting the naive design:
      #
      # 1. microvm.nix's generated `microvm@.service` sets `Restart =
      #    "always"`. `StopWhenUnneeded` issues an ordinary stop job, which
      #    that policy would just restart — so the instance override below
      #    forces `Restart = "no"` first, or the guest would never actually
      #    go down.
      # 2. `StopWhenUnneeded` reacts the moment the last referrer becomes
      #    inactive, with no grace period of its own. A session that exits
      #    and is immediately followed by another would re-boot the guest
      #    for no reason. `agent-vm-linger-hold.service` is the fix: a
      #    second, independent `Wants=`/`After=` referrer that a session
      #    keeps alive and that only drops itself `lingerSeconds` after a
      #    check finds no session scope still running — re-checked at
      #    fire-time, so a new session started inside the window is simply
      #    seen as still active and the drop is skipped, no cancellation
      #    bookkeeping required.
      #
      # Each session is its own `agent-vm-session-*.scope`, created with
      # `systemd-run --scope` around the interactive ssh command rather than
      # any tracking file: a scope's lifetime is its cgroup's, so it goes
      # away — cleanly, and just as well if the wrapper around it is
      # SIGKILLed — the instant the ssh process does, with no release call
      # of ours required to make that true. That is also why this needs no
      # "release" step at all: acquiring is the only verb, and cleanup falls
      # out of scope death plus the linger-hold's own periodic check.
      mkSessionScript =
        pkgs:
        let
          # When a deployed host key is configured, `committedHostPublicKey`
          # (the `data/identities/ssh-host-vm` entry `vm.nix` also pins as
          # its `microvm.credentialFiles` source) is what the guest actually
          # presents — see `mkAgentVm`'s `hostKey` argument. Otherwise fall
          # back to the same generated-key call the guest side makes for
          # itself (same `pkgs`, same `name`, a pure function of both), so
          # the two sides always agree without either copying the other's
          # key material.
          hostPublicKey =
            if cfg.hostKey.file != null && committedHostPublicKey != null then
              lib.removeSuffix "\n" committedHostPublicKey
            else
              (self.lib.agents.mkAgentVmHostKey pkgs cfg.name).publicKey;
          # A scratch, single-entry known_hosts pinned to that exact key,
          # not `~/.ssh/known_hosts`: that file is Home Manager–managed
          # (`ssh-client.nix`) and read-only from ssh's point of view, which
          # is why the very first run of this script failed with "Failed to
          # add the host to the list of known hosts" right before failing
          # auth too. Pinning here means every connection is silently
          # verified against a key that is only ever regenerated when
          # `cfg.name` changes, never on a guest reboot — no prompt, no
          # write, and no possibility of trusting the *wrong* ephemeral
          # guest that happened to be listening on this port.
          knownHosts = pkgs.writeText "agent-vm-known-hosts-${cfg.name}" ''
            [localhost]:${toString cfg.sshHostPort} ${hostPublicKey}
          '';
        in
        pkgs.writeShellApplication {
          name = "agent-vm-session";
          runtimeInputs = [
            pkgs.openssh
            pkgs.systemd
          ];
          text = ''
            if [[ $# -eq 0 ]]; then
              echo "usage: agent-vm-session -- <command to run inside ${cfg.name}>" >&2
              exit 2
            fi

            # The documented usage is `agent-vm-session -- <command>`, but
            # the `ssh` invocation below already inserts its own `--` before
            # "$@" as the separator between ssh's own options and the remote
            # command. Without this, a caller following the documented usage
            # ends up with two `--`s, and the remote command actually run is
            # the literal string `-- <command>` rather than `<command>` —
            # strip one leading `--` here so both `agent-vm-session --
            # <command>` and `agent-vm-session <command>` do the same thing.
            if [[ "$1" == "--" ]]; then
              shift
            fi

            # Bumping the VM unit and the linger-hold reference is
            # idempotent — an already-running unit just no-ops the start
            # job — so nothing here needs to check state first.
            systemctl start --no-block ${lib.escapeShellArg vmUnit}
            systemctl start ${lib.escapeShellArg lingerHoldUnit}

            # Scheduled unconditionally on every acquire, not just on
            # release: the check re-verifies "any session scope still
            # active" at fire-time regardless of who scheduled it, so a
            # wrapper that never gets to run a release step (SIGKILLed
            # mid-session) is still covered by the check the *next*
            # acquire's own linger scheduled, or — if there is no next
            # acquire — by this one.
            systemd-run --on-active=${toString cfg.lifecycle.lingerSeconds} \
              --unit="${lingerCheckPrefix}$$-''${RANDOM}" --collect \
              -- ${pkgs.writeShellScript "agent-vm-linger-check" ''
                systemctl=${lib.getExe' pkgs.systemd "systemctl"}
                if ! "$systemctl" list-units '${sessionPrefix}*.scope' \
                    --state=active --no-legend --plain \
                    | ${lib.getExe pkgs.gnugrep} -q .
                then
                  "$systemctl" stop ${lib.escapeShellArg lingerHoldUnit}
                fi
              ''} \
              >/dev/null

            # ssh does not retry a refused connection, and a cold boot can
            # easily take longer than one attempt — poll instead. No
            # fallback to a native session on timeout: silently degrading
            # isolation is the one thing Phase 7 explicitly forbids.
            ready=0
            for _ in $(seq 1 60); do
              if (exec 3<>"/dev/tcp/127.0.0.1/${toString cfg.sshHostPort}") 2>/dev/null; then
                exec 3<&- 3>&-
                ready=1
                break
              fi
              sleep 1
            done
            if [[ "$ready" -ne 1 ]]; then
              echo "agent-vm-session: ${cfg.name} did not become reachable on port ${toString cfg.sshHostPort} within 60s" >&2
              exit 1
            fi

            # ssh does not preserve trailing arguments as separate argv
            # entries the way `exec` does — it space-joins them verbatim
            # into one string and hands that to the remote shell, so any
            # argument containing whitespace (a `claude` prompt, for
            # instance) silently splits into several. Re-quote each argument
            # with `printf %q` and join into a single pre-escaped string so
            # the remote shell reconstructs exactly the argv this script
            # received, not ssh's naive concatenation of it.
            remote_cmd=""
            for arg in "$@"; do
              printf -v quoted_arg '%q' "$arg"
              remote_cmd+="$quoted_arg "
            done

            exec systemd-run --scope --collect \
              --unit="${sessionPrefix}$$-''${RANDOM}" \
              --property=Wants=${lib.escapeShellArg vmUnit} \
              --property=After=${lib.escapeShellArg vmUnit} \
              -- ssh -tA -p ${toString cfg.sshHostPort} \
                   -o UserKnownHostsFile=${knownHosts} \
                   -o StrictHostKeyChecking=yes \
                   ${cfg.hostUser}@localhost -- "$remote_cmd"
          '';
        };

      # A manual counterpart to `mkSessionScript`'s automatic linger: drops
      # the linger-hold reference right away instead of waiting
      # `lifecycle.lingerSeconds` for the scheduled check to notice no
      # session scope is active. Only ever *releases* a reference —
      # `StopWhenUnneeded` on `vmUnit` is what actually stops the guest, and
      # only once every other referrer (an active session's own `Wants=`) is
      # also gone, so this is safe to run with a session still attached: it
      # just no-ops the eventual teardown instead of forcing it. The same
      # polkit rule that lets `agent-vm-session` stop `lingerHoldUnit`
      # already covers this.
      mkStopScript =
        pkgs:
        pkgs.writeShellApplication {
          name = "agent-vm-stop";
          runtimeInputs = [ pkgs.systemd ];
          text = ''
            systemctl stop ${lib.escapeShellArg lingerHoldUnit}
          '';
        };

      # Recovery, not a lifecycle verb: nothing in normal operation needs
      # this, because `agent-vm-session` boots the guest on demand and
      # `StopWhenUnneeded` takes both the guest and its shares back down.
      #
      # It stays because that teardown is the only thing standing between a
      # stopped guest and a virtiofsd unit left running with no daemons
      # behind it — a state whose symptom is every subsequent boot dying on
      # `Failed connect to 'agent-vm-virtiofs-*.sock': Connection refused`,
      # and which no session script can repair on its own. See the
      # `microvm-virtiofsd@` override below for why it arises and why
      # `StopWhenUnneeded` is what prevents it. A hand-run bounce is the
      # remedy if it ever arises anyway (a host that predates the override,
      # or a share that wedges some other way).
      #
      # Stop/start rather than `systemctl restart`: the polkit rule below
      # grants those two verbs only, and widening it to a third for a
      # script that can express itself in the existing two would trade a
      # standing privilege for nothing.
      mkRestartScript =
        pkgs:
        pkgs.writeShellApplication {
          name = "agent-vm-restart";
          runtimeInputs = [ pkgs.systemd ];
          text = ''
            # Drops the linger reference first so the guest is not brought
            # straight back up by it while virtiofsd is being replaced.
            systemctl stop ${lib.escapeShellArg lingerHoldUnit}
            systemctl stop ${lib.escapeShellArg vmUnit}

            # Stopping the guest already stops the shares via
            # `StopWhenUnneeded`; stated anyway, because the whole point of
            # this script is to be the thing that works when the state the
            # override maintains has somehow not been maintained.
            systemctl stop ${lib.escapeShellArg virtiofsdUnit}
            systemctl start ${lib.escapeShellArg virtiofsdUnit}

            # Deliberately left down: the next `agent-vm-session` boots it
            # with a live linger reference attached, whereas starting it
            # here would produce a guest no referrer is holding, which
            # `StopWhenUnneeded` may collect at any moment.
            echo "agent-vm-restart: shares replaced; the next session will boot ${cfg.name}." >&2
          '';
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
            self.lib.agents.stateDirsFor "/home/user" [ "claude" "headroom" ]
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
          lingerSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 120;
            description = ''
              How long the guest is kept running after the last agent session
              exits, so exiting one session and immediately starting another
              does not re-boot it. See `agent-vm-session`'s doc comment for
              the mechanism.
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
                  guestEnvironment
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
                    null;
              };
            };

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

            # Phase 7. Instance-specific config for the *particular*
            # `microvm@<name>.service` this module declares, not the
            # `microvm@.service` template — NixOS's systemd module merges a
            # `"unit@instance"` definition as that instance's own drop-in, so
            # this only ever touches this VM's unit. See `mkSessionScript`'s
            # doc comment for why both settings are here.
            systemd.services.${vmUnitName} = {
              serviceConfig.Restart = lib.mkForce "no";
              unitConfig.StopWhenUnneeded = true;
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
            systemd.services."microvm-virtiofsd@${cfg.name}".unitConfig.StopWhenUnneeded = true;

            # A `Wants=`/`After=` referrer of its own, started and dropped by
            # `agent-vm-session` — never at boot, hence no `wantedBy`.
            systemd.services.${lingerHoldUnitName} = {
              description = "Keeps ${cfg.name} up for ${toString cfg.lifecycle.lingerSeconds}s after the last agent session exits";
              unitConfig = {
                Wants = vmUnit;
                After = vmUnit;
              };
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.coreutils}/bin/true";
              };
            };

            environment.systemPackages = [
              (mkSessionScript pkgs)
              (mkStopScript pkgs)
              (mkRestartScript pkgs)
            ];

            # Grants exactly what `agent-vm-session` needs and nothing more:
            # starting/stopping the VM unit, its virtiofsd unit
            # (`agent-vm-restart`) and the linger-hold reference by their
            # fixed names, and creating the transient session scopes
            # and linger-check units it names with these prefixes. Anyone
            # else's unit, and any other verb (restart, kill, ...), falls
            # through to the default policy — which on a desktop system
            # means "ask", not "deny", so this rule only ever *widens* what
            # `hostUser` may do, never narrows it.
            security.polkit.extraConfig = ''
              polkit.addRule(function(action, subject) {
                if (action.id != "org.freedesktop.systemd1.manage-units") {
                  return;
                }
                if (subject.user != ${builtins.toJSON cfg.hostUser}) {
                  return;
                }
                var verb = action.lookup("verb");
                if (verb != "start" && verb != "stop") {
                  return;
                }
                var unit = action.lookup("unit");
                if (unit == ${builtins.toJSON vmUnit}
                 || unit == ${builtins.toJSON lingerHoldUnit}
                 || unit == ${builtins.toJSON virtiofsdUnit}) {
                  return polkit.Result.YES;
                }
                if (unit && (unit.indexOf(${builtins.toJSON sessionPrefix}) == 0
                          || unit.indexOf(${builtins.toJSON lingerCheckPrefix}) == 0)) {
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
