/**
  # flake.lib.agents.mkAgentVm

  Phase 4 of `__reference/microvm/implementation-guide.md`: the VM
  layer. Must never mention `~/.claude`, headroom, or a model name — that's
  the harness layer's job (`libagents.nix`, `selector-loop.nix`). This layer
  only knows about shares, networking, and the guest's own NixOS
  configuration; it must never be handed a harness's prompt text or tool
  list.

  `mkAgentVm { name, hostUser, projectRoots, uid ? null, authorizedKeys ? [],
  vcpu ? 2, mem ? 4096, stateDirs ? [], channels ? {}, lifecycle ? {} }`
  returns a NixOS module (a plain guest config, not a `nixosConfigurations.*`
  entry — the caller decides how to instantiate it, matching how every other
  module in this flake stays a value rather than wiring itself in).

  **Implemented this phase** (see the guide's Phase 4 acceptance criteria):
  store share (read-only virtiofs + a tmpfs-backed writable overlay, so the
  guide's "known failure mode" — overlayfs upper dir on virtiofs/9p — never
  applies here, since the overlay's upper directory lives on the guest's own
  root instead of a share), one virtiofs share per `projectRoots` entry
  mounted at the **identical host path**, SSH reachable via a forwarded port
  over QEMU user networking, and a guest user whose **name and home path**
  match `hostUser`.

  **Deliberately unimplemented** (accepted as parameters so later phases
  don't need to change this function's shape, but not wired to anything
  yet): `stateDirs`, `channels`, `lifecycle` — these are Phases 5/6's job
  (vsock channels for the nix daemon and gpg-agent, state directory
  persistence, VM lifecycle management). Don't guess ahead of those phases;
  see the handoff on Phase 3 for why speculative fields were avoided there
  too.

  `uid`, if given, is the host user's numeric uid. The default virtiofs
  `securityModel = "none"` preserves numeric ownership as-is rather than
  translating it, so a mismatched guest uid makes shared files look
  wrong-owned from inside the guest even though the bytes are identical;
  passing it keeps a `touch`'d file's ownership sane on both sides. Leaving
  it `null` still boots and shares files, just without that cosmetic
  guarantee — acceptable for this phase's "any VM boots, path identity
  holds" bar.
*/
{ inputs, self, ... }:
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
      channels ? { },
      lifecycle ? { },
    }:
    {
      lib,
      ...
    }:
    {
      imports = [ inputs.microvm.nixosModules.microvm ];

      # `stateDirs`/`channels`/`lifecycle` are accepted but intentionally
      # unwired this phase — see the doc comment above. Nix doesn't warn on
      # unused arguments, so no bookkeeping is needed to "use" them; they
      # exist purely so Phases 5/6 don't have to change this function's
      # call signature when they start consuming them.
      networking.hostName = name;
      # Matches the guide's other guest examples; bump when a real upgrade
      # path exists.
      system.stateVersion = lib.trivial.release;

      microvm = {
        inherit vcpu mem;
        hypervisor = "qemu";
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
            host.port = sshHostPort;
            guest.port = 22;
          }
        ];

        # The known failure mode in the guide ("upper fs missing required
        # features") is specifically overlayfs with its upper directory *on*
        # a virtiofs/9p share. `writableStoreOverlay` lives on the guest's
        # own (tmpfs) root instead, so the ro-store share stays read-only
        # and this never hits that path.
        writableStoreOverlay = "/nix/.rw-store";

        shares = [
          {
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
          }
        ]
        ++ map (root: {
          tag = tagFor root;
          source = root;
          mountPoint = root;
          proto = "virtiofs";
        }) projectRoots;
      };

      users.users.${hostUser} = {
        isNormalUser = true;
        home = "/home/${hostUser}";
        uid = lib.mkIf (uid != null) uid;
        openssh.authorizedKeys.keys = authorizedKeys;
      };

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "no";
        };
      };
    };
in
{
  flake.lib.agents = {
    inherit mkAgentVm;
  };
}
