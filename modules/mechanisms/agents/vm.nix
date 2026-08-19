/**
  # flake.lib.agents.mkAgentVm

  Phases 4 and 5 of `__reference/microvm/implementation-guide.md`: the VM
  layer. Must never mention `~/.claude`, headroom, or a model name — that's
  the harness layer's job (`libagents.nix`, `selector-loop.nix`). This layer
  only knows about shares, networking, channels, and the guest's own NixOS
  configuration; it must never be handed a harness's prompt text or tool
  list.

  `mkAgentVm { name, hostUser, projectRoots, uid ? null, authorizedKeys ? [],
  vcpu ? 2, mem ? 4096, stateDirs ? [], guestEnvironment ? {}, channels ? {},
  lifecycle ? {} }`
  returns a NixOS module (a plain guest config, not a `nixosConfigurations.*`
  entry — the caller decides how to instantiate it, matching how every other
  module in this flake stays a value rather than wiring itself in).

  **Shares and identity (Phase 4).** Store share (read-only virtiofs + a
  tmpfs-backed writable overlay, so the guide's "known failure mode" —
  overlayfs upper dir on virtiofs/9p — never applies here, since the
  overlay's upper directory lives on the guest's own root instead of a
  share), one virtiofs share per `projectRoots` entry mounted at the
  **identical host path**, SSH reachable via a forwarded port over QEMU user
  networking, and a guest user whose **name and home path** match `hostUser`.

  **Channels (Phase 5).** `channels` is the seam the harness layer eventually
  declares through: it says *what capability the guest needs*, and this
  function decides that the capability is a vsock proxy. Each channel is a
  unix socket in the guest, socket-activated per connection, forwarded to a
  listener on the host (`vm-host.nix`); the constants both ends share live in
  `vm-channels.nix`.

  ```nix
  channels = {
    nixDaemon.enable = true;
    gpgAgent = {
      enable = true;
      certificates = [ "<armored public key>" ];
      ultimatelyTrusted = [ "<fingerprint>" ];
    };
  };
  ```

  - `nixDaemon` replaces the guest's own `nix-daemon` with a proxy onto the
    **host's** daemon, so a build in the guest lands in the host store and is
    already there when the guest is gone. The guest's local daemon is
    disabled outright rather than left running on another path: two daemons
    over one store is how you corrupt a database, and a fallback that
    silently builds locally would hide a broken channel behind a slow build.
    `NIX_REMOTE=daemon` is set explicitly because nix's own heuristic
    ("is the store writable?") sees a read-only `/nix/store` share and a
    writable overlay and is not worth trusting to guess right.
  - `gpgAgent` forwards the **restricted** agent socket. The guest gets the
    public keyring built from the certificates passed in — never copied out
    of anyone's `$HOME` — so `git commit -S` finds the key, while the private
    key stays on the host's smartcard and every signature needs whatever the
    host's agent asks for (a touch, a PIN). `certificates` and
    `ultimatelyTrusted` are parameters rather than a reach into
    `self.data.identities` so this layer keeps knowing nothing about who its
    caller is; the host module supplies the defaults.

  Enabling any channel sets `microvm.vsock.cid` (derived from `name`, so it
  is stable and unique without a registry), which makes QEMU want
  `/dev/vhost-vsock` — see `vm-host.nix` for the host-side permissions that
  need.

  **State directories (Phase 6).** `stateDirs` is a list of host directories
  shared read-write at the identical path, exactly like `projectRoots` — the
  distinction is entirely in who contributes them and why, not in what this
  function does with them, so they are kept as two lists rather than merged
  into one. They carry the agent's memory, sessions and credentials across
  guest restarts.

  This function must never *name* one of those directories: which state a
  harness keeps, and where, is the harness layer's fact
  (`flake.lib.agents.stateDirs`). Same for `guestEnvironment`, an opaque
  attrset of `name = value` pairs written into the guest's
  `environment.variables`; the host passes `CLAUDE_CONFIG_DIR` through it
  without this layer learning what claude is.

  The guest runs **no Home Manager**, and that is load-bearing rather than
  incidental: Home Manager symlinks at file granularity, so a guest
  generation over the same shared `~/.claude` would rename the host
  generation's `settings.json` out of the way on every boot. The host's
  generation is the sole manager; the guest gets packages and wrappers only.

  **`lifecycle` stays unwired.** Phase 7 turned out to need nothing from the
  guest side at all: the VM starts and stops as a host-managed systemd unit
  (`microvm@<name>.service`), refcounted by host-side transient units the
  guest never hears about — see `vm-host.nix`'s "Lifecycle (Phase 7)"
  section. The parameter is kept, still accepting and ignoring whatever is
  passed, so a caller built against the documented signature doesn't break;
  nothing currently passes it.

  `uid`, if given, is the host user's numeric uid. The default virtiofs
  `securityModel = "none"` preserves numeric ownership as-is rather than
  translating it, so a mismatched guest uid makes shared files look
  wrong-owned from inside the guest even though the bytes are identical;
  passing it keeps a `touch`'d file's ownership sane on both sides. Leaving
  it `null` still boots and shares files, just without that cosmetic
  guarantee — acceptable for this phase's "any VM boots, path identity
  holds" bar.
*/
{
  inputs,
  self,
  lib,
  ...
}:
let
  # A guest-unique QEMU MAC, stable per VM name so re-evaluation doesn't
  # reassign it. Locally administered (the `02` prefix), not globally unique
  # in any real sense — fine for a single-host user-mode NIC.
  macFor =
    name:
    let
      hash = builtins.hashString "sha256" name;
      byte = offset: builtins.substring offset 2 hash;
    in
    "02:${byte 0}:${byte 2}:${byte 4}:${byte 6}:${byte 8}";

  # A virtiofs tag derived from a host path. The **leading** separator must
  # go: the guest mounts a share by passing its tag to `mount(8)` as the
  # device argument, so a tag like `-home-user-Projects` is parsed as option
  # clustering (`-h` → prints usage) and the mount unit dies with
  # "Mount process finished, but is no mount". Tags are also capped at 36
  # bytes by the virtio-fs spec, so anything longer collapses to a hash
  # suffix rather than silently truncating into a collision.
  tagFor =
    root:
    let
      flat = builtins.replaceStrings [ "/" ] [ "-" ] (
        builtins.substring 1 (builtins.stringLength root) root
      );
    in
    if builtins.stringLength flat <= 36 then
      flat
    else
      builtins.substring 0 36 "fs-${builtins.hashString "sha256" root}";

  inherit (self.lib.agents.vmChannels) hostCid ports cidFor;

  # One socket-activated proxy per connection: systemd owns the listening
  # socket, accepts, and hands the connection to socat on stdin/stdout, which
  # dials the host. `Accept = true` (one instance per connection) rather than
  # a single long-lived proxy because both protocols multiplex nothing — a
  # shared proxy would need to demultiplex streams itself, and a crash would
  # take every session with it.
  proxyService = pkgs: description: target: {
    inherit description;
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.socat} - ${target}";
      StandardInput = "socket";
      StandardOutput = "socket";
      # A proxy that keeps failing is a channel that is down; it should be
      # visible in `systemctl` rather than restarting behind the user's
      # back. The socket unit stays up regardless, so the next connection
      # still gets a fresh attempt.
      Restart = "no";
    };
  };

  # The guest's own nix-daemon is switched off and its socket path taken over
  # by the proxy, so every nix client in the guest — including ones that
  # hardcode the path — reaches the host daemon. Mode 0666 matches what
  # NixOS's own nix-daemon.socket uses: access control is the host daemon's
  # job (it decides what an untrusted user may ask for), not this socket's.
  nixDaemonGuest =
    { pkgs, ... }:
    {
      systemd.sockets.nix-daemon.enable = false;
      systemd.services.nix-daemon.enable = false;

      environment.variables.NIX_REMOTE = "daemon";

      # The channel exists so the guest can run nix; a guest that then has to
      # be told `--extra-experimental-features nix-command` for every
      # invocation is a channel with a paper cut stapled to it. These are
      # client-side settings, not restricted ones, so an untrusted client
      # setting them changes nothing about the host's trust model.
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      systemd.sockets.agent-vm-nix-daemon = {
        description = "Host nix daemon channel (vsock)";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "/nix/var/nix/daemon-socket/socket";
          SocketMode = "0666";
          Accept = true;
        };
      };

      systemd.services."agent-vm-nix-daemon@" =
        proxyService pkgs "Host nix daemon channel (vsock) connection %i"
          "VSOCK-CONNECT:${toString hostCid}:${toString ports.nixDaemon}";
    };

  # Built from the certificates the caller passed, in a throwaway GNUPGHOME,
  # so what lands in the guest is reproducible from the repository instead of
  # being whatever state a developer's keyring had accumulated.
  gpgPublicHome =
    pkgs: certificates: ultimatelyTrusted:
    pkgs.runCommand "agent-vm-gnupg-public"
      {
        nativeBuildInputs = [ pkgs.gnupg ];
        certs = pkgs.writeText "agent-vm-certificates.asc" (lib.concatStringsSep "\n" certificates);
        # Trailing newline is load-bearing: gpg reads ownertrust
        # line-wise and reports an unterminated final line as "line too
        # long" rather than as a missing newline.
        ownertrust = pkgs.writeText "agent-vm-ownertrust" (
          lib.concatMapStrings (fpr: "${fpr}:6:\n") ultimatelyTrusted
        );
      }
      ''
        export GNUPGHOME=$(mktemp -d)
        gpg --batch --quiet --import "$certs"
        gpg --batch --quiet --import-ownertrust "$ownertrust"
        # gpg only materializes the trustdb lazily; force it so the guest
        # gets a complete keyring rather than one that rebuilds (and warns)
        # on first use.
        gpg --batch --quiet --check-trustdb
        mkdir -p "$out"
        cp "$GNUPGHOME/pubring.kbx" "$GNUPGHOME/trustdb.gpg" "$out/"
      '';

  # `%t` is the user's runtime directory, which is exactly where `gpgconf
  # --list-dirs agent-socket` points once that directory exists — so this
  # lands the proxy at the path gpg looks in, without hardcoding a uid. A
  # user unit (not a system one) because the path is per-session and vanishes
  # with the session; a system unit would be racing logind for the directory.
  #
  # No gpg-agent runs in the guest: gpg connects to an existing socket before
  # it tries to spawn one, so the proxy simply wins.
  gpgAgentGuest =
    hostUser: certificates: ultimatelyTrusted:
    { pkgs, ... }:
    let
      home = gpgPublicHome pkgs certificates ultimatelyTrusted;
    in
    {
      environment.systemPackages = [ pkgs.gnupg ];

      systemd.user.sockets.agent-vm-gpg-agent = {
        description = "Host gpg-agent channel (vsock)";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "%t/gnupg/S.gpg-agent";
          SocketMode = "0600";
          # 0700, not systemd's default 0755, and this is the difference
          # between the channel working and gpg quietly ignoring it. gnupg
          # refuses to use a socket directory that is group- or
          # other-accessible: it falls back to ~/.gnupg silently, so
          # `gpgconf --list-dirs agent-socket` points somewhere the proxy is
          # not, gpg finds no agent there, starts a *local* one with an empty
          # keyring, and signing fails with "No secret key" — which names
          # neither the socket nor the directory that caused it.
          DirectoryMode = "0700";
          Accept = true;
          # 0600 because gpg refuses an agent socket it considers reachable
          # by anyone else; RemoveOnStop because a stale socket file left
          # behind makes gpg hang on connect instead of failing cleanly.
          RemoveOnStop = true;
        };
      };

      systemd.user.services."agent-vm-gpg-agent@" =
        proxyService pkgs "Host gpg-agent channel (vsock) connection %i"
          "VSOCK-CONNECT:${toString hostCid}:${toString ports.gpgAgent}";

      # Copied rather than symlinked: gpg rewrites its own keyring and
      # trustdb (import, trust changes) and dies on a read-only store path.
      # `C+` re-copies on every boot, so the guest's copy can never drift
      # into being the source of truth.
      systemd.tmpfiles.rules = [
        "d /home/${hostUser}/.gnupg 0700 ${hostUser} users - -"
        "C+ /home/${hostUser}/.gnupg/pubring.kbx 0600 ${hostUser} users - ${home}/pubring.kbx"
        "C+ /home/${hostUser}/.gnupg/trustdb.gpg 0600 ${hostUser} users - ${home}/trustdb.gpg"
      ];
    };

  # A deterministic, reproducible Ed25519 keypair for one VM's sshd host
  # identity, generated at build time rather than left to sshd's own
  # first-boot generation. Pure in `pkgs` and `name`: called identically
  # from this guest's own config (below) and from `vm-host.nix`'s
  # `agent-vm-session`, so both sides derive the same key without one
  # copying it from the other. Not a secret in any meaningful sense — its
  # only job is a stable identity behind a host-only port forward that is
  # already inside the trust boundary — so living in the world-readable
  # Nix store costs nothing real.
  mkAgentVmHostKey =
    pkgs: name:
    let
      dir =
        pkgs.runCommand "agent-vm-host-key-${name}"
          {
            nativeBuildInputs = [ pkgs.openssh ];
          }
          ''
            mkdir -p "$out"
            ssh-keygen -q -N "" -t ed25519 -C ${lib.escapeShellArg name} \
              -f "$out/ssh_host_ed25519_key"
          '';
    in
    {
      privateKeyPath = "${dir}/ssh_host_ed25519_key";
      publicKeyPath = "${dir}/ssh_host_ed25519_key.pub";
      # Forces the tiny keygen derivation to build at evaluation time
      # (import-from-derivation) so the literal key text is available to
      # embed in a known-hosts file; acceptable for something this small
      # and this rarely rebuilt (only when `name` changes).
      publicKey = lib.removeSuffix "\n" (builtins.readFile "${dir}/ssh_host_ed25519_key.pub");
    };

  mkAgentVm =
    {
      name,
      hostUser,
      projectRoots,
      uid ? null,
      authorizedKeys ? [ ],
      vcpu ? 2,
      mem ? 4096,
      sshHostPort ? 2222,
      stateDirs ? [ ],
      guestEnvironment ? { },
      channels ? { },
      lifecycle ? { },
      # `null` (the default) keeps the store-resident, non-reproducible
      # generated key below — needed for a bootstrap checkout and for
      # throwaway guests like the smoke test, neither of which has ciphertext
      # to decrypt. A caller with a deployed secret
      # (`vm-host.nix`/`self.secrets.sshHostVm`) passes `{ path; publicKey;
      # }`: `path` is the *runtime* plaintext path on the host (e.g.
      # `/run/agenix/agent-vm-host-key`, read by QEMU as root at VM start,
      # never entering the store), `publicKey` is the committed public half
      # used to pin `known_hosts` on the other side of the same call. This
      # function stays ignorant of Agenix/secrets entirely — resolving the
      # secret is `vm-host.nix`'s job, not the VM layer's.
      hostKey ? null,
    }:
    {
      lib,
      pkgs,
      ...
    }:
    let
      anyChannel = lib.any (c: c.enable or false) (builtins.attrValues channels);
      useNixDaemon = channels.nixDaemon.enable or false;
      generatedHostKey = mkAgentVmHostKey pkgs name;
      useDeployedHostKey = hostKey != null;
      hostKeyCredentialName = "agent_vm_ssh_host_key";
    in
    {
      imports = [
        inputs.microvm.nixosModules.microvm
      ]
      ++ lib.optional useNixDaemon nixDaemonGuest
      ++ lib.optional (channels.gpgAgent.enable or false) (
        gpgAgentGuest hostUser (channels.gpgAgent.certificates or [ ]) (
          channels.gpgAgent.ultimatelyTrusted or [ ]
        )
      );

      # `lifecycle` is accepted but intentionally unwired — see the doc
      # comment above. Nix doesn't warn on unused arguments, so no
      # bookkeeping is needed to "use" it; it exists purely so Phase 7
      # doesn't have to change this function's call signature.
      networking.hostName = name;
      # Matches the guide's other guest examples; bump when a real upgrade
      # path exists.
      system.stateVersion = lib.trivial.release;

      microvm = {
        inherit vcpu mem;
        hypervisor = "qemu";

        # Only set when something actually needs it: a CID makes QEMU open
        # /dev/vhost-vsock, which a channel-less guest has no reason to
        # require of whoever runs it.
        vsock.cid = lib.mkIf anyChannel (cidFor name);
        interfaces = [
          {
            type = "user";
            id = "qemu";
            mac = macFor name;
          }
        ];
        forwardPorts = [
          {
            from = "host";
            proto = "tcp";
            host.address = "127.0.0.1";
            host.port = sshHostPort;
            guest.port = 22;
          }
        ];

        # With the nix daemon channel, the guest never writes to the store
        # itself — the host daemon does, on the host side — so the share is
        # mounted straight at /nix/store with no overlay above it, and
        # read-only at the virtiofs level so nothing in the guest can scribble
        # into the host store behind the daemon's back.
        #
        # The overlay is not merely unnecessary here, it is actively wrong:
        # overlayfs documents the behavior of a *lower* layer that changes
        # underneath it as undefined, and the whole point of the channel is
        # that the host store gains paths while the guest is running. A build
        # that succeeds and then cannot be found in /nix/store is exactly the
        # failure that would produce.
        #
        # Without the channel the guest has to be able to build for itself, so
        # the overlay comes back. Its upper directory lives on the guest's own
        # (tmpfs) root rather than on a share, which is what keeps the guide's
        # known failure mode ("upper fs missing required features", overlayfs
        # with its upper dir on virtiofs/9p) from ever applying.
        writableStoreOverlay = if useNixDaemon then null else "/nix/.rw-store";

        shares = [
          {
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = if useNixDaemon then "/nix/store" else "/nix/.ro-store";
            readOnly = useNixDaemon;
            proto = "virtiofs";
          }
        ]
        ++ map (root: {
          tag = tagFor root;
          source = root;
          mountPoint = root;
          proto = "virtiofs";
        }) (projectRoots ++ stateDirs);
      };

      users.users.${hostUser} = {
        isNormalUser = true;
        home = "/home/${hostUser}";
        uid = lib.mkIf (uid != null) uid;
        openssh.authorizedKeys.keys = authorizedKeys;
      };

      # ssh from a modern terminal (ghostty, kitty, foot) otherwise lands in a
      # guest that has never heard of $TERM, and every program that asks
      # ncurses for a screen size — `systemctl status` above all — prints
      # "unknown terminal type" and nothing else. The terminfo database is in
      # the shared host store, so this costs the guest nothing to carry.
      # Opaque to this layer by construction: the caller says
      # `CLAUDE_CONFIG_DIR = ...`, this writes it out, and the VM never
      # learns which harness cares. `mkDefault` so a guest-side module (a
      # channel, or a harness wrapper in a later phase) can still override
      # one without a conflict.
      environment.variables = lib.mapAttrs (_: lib.mkDefault) guestEnvironment;

      environment.enableAllTerminfo = true;

      # A fixed host key rather than whatever the ephemeral (tmpfs) root
      # would otherwise generate fresh on every boot. `agent-vm-session`
      # (`vm-host.nix`, Phase 7) pins the matching public key — the
      # committed `data/identities/ssh-host-vm` identity when `hostKey` is
      # deployed, `generatedHostKey.publicKey` otherwise — in a scratch
      # known-hosts file, so the two sides always agree without either
      # copying the other's key material. Without this, every reboot is a
      # new identity: ssh either has to prompt on the first connection after
      # each one, or (worse, and what actually happened the first time this
      # was tried) fail outright, because the caller's `~/.ssh/known_hosts`
      # is a Home Manager–managed file ssh cannot append a TOFU entry to.
      #
      # Two delivery paths, chosen by whether the caller passed `hostKey`:
      #
      # - Deployed (`useDeployedHostKey`): the plaintext never enters the
      #   store. `microvm.credentialFiles` hands QEMU the *host* runtime
      #   path (`/run/agenix/...`, root-only) at VM start via
      #   `-fw_cfg name=opt/io.systemd.credentials/...`
      #   (`vm-host-key-age.md`); the guest's pid 1 receives it as a system
      #   credential, and this oneshot materializes it before sshd starts.
      #   `requiredBy` (not just `before`) is what makes this fail *closed*:
      #   if the credential is missing or the oneshot fails, sshd is pulled
      #   down with it rather than falling back to a fresh, unpinned key.
      # - Generated (fallback, no `hostKey`): the old behaviour — a
      #   store-resident, non-reproducible keypair copied into `/etc/ssh`
      #   with `C+` (always overwrite) rather than pointed at directly,
      #   because sshd's own host key handling is far less forgiving of a
      #   world-readable Nix store path's permissions than the fact that
      #   this key has no real secrecy to protect (its only job is a stable
      #   identity behind a host-only port forward) would suggest. Only
      #   reached by a bootstrap checkout or a throwaway guest (the smoke
      #   test) with no ciphertext to decrypt.
      systemd.tmpfiles.rules = lib.optionals (!useDeployedHostKey) [
        "C+ /etc/ssh/ssh_host_ed25519_key 0600 root root - ${generatedHostKey.privateKeyPath}"
        "C+ /etc/ssh/ssh_host_ed25519_key.pub 0644 root root - ${generatedHostKey.publicKeyPath}"
      ];

      microvm.credentialFiles = lib.mkIf useDeployedHostKey {
        ${hostKeyCredentialName} = hostKey.path;
      };

      systemd.services.agent-vm-host-key = lib.mkIf useDeployedHostKey {
        description = "Materialize the deployed sshd host key from its systemd credential";
        before = [ "sshd.service" ];
        requiredBy = [ "sshd.service" ];
        unitConfig.ConditionPathExists = "!/etc/ssh/ssh_host_ed25519_key";
        serviceConfig = {
          Type = "oneshot";
          ImportCredential = hostKeyCredentialName;
        };
        script = ''
          install -Dm0600 -o root -g root \
            "$CREDENTIALS_DIRECTORY/${hostKeyCredentialName}" \
            /etc/ssh/ssh_host_ed25519_key
        '';
      };

      services.openssh = {
        enable = true;
        hostKeys = [
          {
            path = "/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "no";
        };
      };
    };
in
{
  flake.lib.agents = {
    inherit
      mkAgentVm
      mkAgentVmHostKey
      ;
  };
}
