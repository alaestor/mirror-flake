/**
    # flake.lib.agents.mkAgentVm

    The VM layer. Must never mention `~/.claude`, headroom, or a model name — that's
    the harness layer's job (`libagents.nix`, `selector-loop.nix`). This layer
    only knows about shares, networking, channels, and the guest's own NixOS
    configuration; it must never be handed a harness's prompt text or tool
    list.

 `mkAgentVm { name, hostUser, projectRoots, hostKey, uid ? null,
 authorizedKeys ? [], vcpu ? 2, mem ? 4096, stateDirs ? [],
 localStateDirs ? [], guestEnvironment ? {}, guestEtc ? {}, channels ? {} }`
    returns a NixOS module (a plain guest config, not a `nixosConfigurations.*`
    entry — the caller decides how to instantiate it, matching how every other
    module in this flake stays a value rather than wiring itself in).

    **Shares and identity.** Store share (read-only virtiofs + a
    tmpfs-backed writable overlay, so an overlayfs upper directory on
    overlayfs upper dir on virtiofs/9p — never applies here, since the
    overlay's upper directory lives on the guest's own root instead of a
    share), one virtiofs share per `projectRoots` entry mounted at the
    **identical host path**, SSH reachable via a forwarded port over QEMU user
    networking, and a guest user whose **name and home path** match `hostUser`.

    **Channels.** `channels` is the seam the harness layer
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

    **State directories.** `stateDirs` is a list of host directories
    shared read-write at the identical path, exactly like `projectRoots` — the
    distinction is entirely in who contributes them and why, not in what this
    function does with them, so they are kept as two lists rather than merged
    into one. They carry the agent's memory, sessions and credentials across
  guest restarts. `localStateDirs` instead creates persistent guest block volumes
  for state, such as SQLite WAL databases, that cannot safely use virtiofs.

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

    `uid`, if given, is the host user's numeric uid. The default virtiofs
    `securityModel = "none"` preserves numeric ownership as-is rather than
    translating it, so a mismatched guest uid makes shared files look
    wrong-owned from inside the guest even though the bytes are identical;
    passing it keeps a `touch`'d file's ownership sane on both sides. Leaving
    it `null` still boots and shares files, just without that cosmetic
    guarantee — acceptable for a smoke test that only requires booting and
    path identity.
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
        self.lib.agents.vmChannels.proxyService pkgs "Host nix daemon channel (vsock) connection %i"
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
        self.lib.agents.vmChannels.proxyService pkgs "Host gpg-agent channel (vsock) connection %i"
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
      path = "${dir}/ssh_host_ed25519_key";
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
      localStateDirs ? [ ],
      guestEnvironment ? { },
      guestEtc ? { },
      channels ? { },
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
    hostKey,
    }:
    {
      lib,
      pkgs,
      ...
    }:
    let
      anyChannel = lib.any (c: c.enable or false) (builtins.attrValues channels);
      useNixDaemon = channels.nixDaemon.enable or false;
      hostKeyCredentialName = "agent_vm_ssh_host_key";

      # `stateDirs` shares directories at the identical path, but only the
      # leaf itself — e.g. `.cache/claude-cli-nodejs` is a share, `.cache`
      # is not. Virtiofs carries the host's real ownership across for a
      # share's own mountpoint, but any *intermediate* parent a share nests
      # under (like `.cache` here) has no share of its own, so nothing but
      # the systemd-generated mount unit's own mkdir ever creates it — as
      # root, 0755, before `hostUser`'s session exists. That leaves the
      # parent owned by root while everything inside it is owned correctly,
      # and any write directly under it (`nix flake check`'s
      # `~/.cache/nix`, for one) fails with EACCES. Pre-creating every such
      # parent, owned by `hostUser`, closes that gap for whatever nests
      # under home now or in the future, not just `.cache`.
      home = "/home/${hostUser}";
      parentsOf =
        path:
        let
          go = p: if p == home || p == "/" || p == "." then [ ] else [ p ] ++ go (builtins.dirOf p);
        in
        go (builtins.dirOf path);
      stateDirParents = lib.unique (lib.concatMap parentsOf stateDirs);
      localStateDirParents = lib.unique (lib.concatMap (entry: parentsOf entry.path) localStateDirs);
      guestUid = if uid == null then 1000 else uid;
    in
    {
      imports = [
        inputs.microvm.nixosModules.microvm
        inputs.self.modules.nixos.memory-manager
      ]
      ++ lib.optional useNixDaemon nixDaemonGuest
      ++ lib.optional (channels.gpgAgent.enable or false) (
        gpgAgentGuest hostUser (channels.gpgAgent.certificates or [ ]) (
          channels.gpgAgent.ultimatelyTrusted or [ ]
        )
      );

      # `lifecycle` is accepted but intentionally unwired — see the doc
      # comment above. Nix doesn't warn on unused arguments, so no
      # bookkeeping is needed to "use" it; it preserves the documented
      # function signature.
      networking.hostName = name;
      # Bump when a real upgrade path exists.
      system.stateVersion = lib.trivial.release;

      # An agent's working set is spiky — a `nix eval` over a whole flake can
      # briefly want several times what the guest is idling at. zram lets that
      # spike compress instead of becoming an instant kill, and earlyoom picks
      # the evaluator over whatever else is resident once it can't. No
      # notifications: nothing in the guest would display them.
      memory-manager.earlyoom.notifications = false;

      microvm = {
        inherit vcpu mem;
        hypervisor = "qemu";

        # Free-page reporting hands pages the guest is no longer using back to
        # the host, so a generous `mem` ceiling costs the host only what the
        # guest actually touches. deflate-on-oom keeps the balloon from
        # holding memory hostage when the guest needs it back in a hurry.
        balloon = true;
        deflateOnOOM = true;

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
        # (tmpfs) root rather than on a share, so overlayfs never uses a
        # virtiofs/9p upper directory.
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

        volumes = map (entry: {
          image = "${tagFor entry.path}.img";
          mountPoint = entry.path;
          inherit (entry) size;
          fsType = "ext4";
          mkfsExtraArgs = [
            "-E"
            "root_owner=${toString guestUid}:100"
          ];
        }) localStateDirs;
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
      # channel or a harness wrapper) can still override
      # one without a conflict.
      environment.variables = lib.mapAttrs (_: lib.mkDefault) guestEnvironment // {
        AGENT_VM_GUEST = "1";
      };

      # Same contract as `guestEnvironment`, for state a harness cannot express
      # as an environment variable: an attribute name is an `/etc`-relative
      # path and its value a store path to place there. Opaque by
      # construction, so this layer still never learns which harness needs a
      # system-level config file or why.
      environment.etc = lib.mapAttrs (_: source: { inherit source; }) guestEtc;

      environment.enableAllTerminfo = true;
      # The credential path never enters the store. The materialization service
      # fails closed: sshd is required by it and cannot generate an unpinned key.
      systemd.tmpfiles.rules =
        map (p: "d ${p} 0755 ${hostUser} users - -") (stateDirParents ++ localStateDirParents);

      microvm.credentialFiles = {
        ${hostKeyCredentialName} = hostKey.path;
      };

      systemd.services.agent-vm-host-key = {
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
