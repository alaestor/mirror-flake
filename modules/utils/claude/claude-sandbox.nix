/**
  # claude-sandbox

  Vendored from [claude-sandbox](https://github.com/mrquentin/claude-sandbox)
  (MIT). Exports the disabled-by-default NixOS `claude-sandbox` feature and the
  `claude-sandbox` package/app.

  The sandbox runs Claude Code under bubblewrap with namespace isolation, a
  read-only filesystem view, a build-time seccomp filter, git-config
  sanitization, optional command filtering and optional egress filtering
  through a userspace network namespace.

  One derivation embeds all three tool profiles (`minimal`, `default`, `full`);
  the profile is chosen at runtime, so the NixOS module only has to pass flags.
  Importing the NixOS module does not install anything.

  `flake.lib.mkClaudeSandbox` builds the sandbox for a given `pkgs`, so a Home
  Manager module can reach it without a NixOS system in between.

  Upstream shell, Python and seccomp sources live in `data/utils/claude-sandbox/`
  alongside the `package.nix` derived from the upstream flake. They carry a
  license tag and changes marked `LOCAL DEVIATION`:

  - `~/.claude` (and `~/.claude.json`) is bound read-write directly from the
    host instead of upstream's ro-bind-plus-scratch-copy — the copy approach
    silently broke OAuth: a token refresh inside the sandbox rotates the
    refresh token server-side, but the new pair only ever landed in the
    throwaway copy, stranding the host's now-invalid refresh token and
    breaking auth everywhere until a fresh host-side login. This has the
    same trust boundary as running claude unsandboxed. Settings files that
    are store symlinks (Home Manager-managed) stay readable-but-unwritable
    through the bind, same as on the host.
  - gpg-agent's socket is forwarded (mirroring upstream's SSH agent
    forwarding) and `~/.gnupg/{pubring.kbx,trustdb.gpg}` are exposed
    read-only, so `git commit -S` works against a hardware-token-backed key.
  - The sanitized global gitconfig merges `~/.config/git/config` (XDG) and
    `~/.gitconfig`, since `GIT_CONFIG_GLOBAL` (pinned to the sanitized file)
    makes git skip its normal XDG lookup — identity kept in the XDG file
    would otherwise silently vanish inside the sandbox.
*/
{ self, ... }:

let
  packageFile = self.data.path "utils/claude-sandbox/package.nix";

  # Tool profiles available inside the sandbox. `minimal` is the floor every
  # profile builds on; `default` adds a C/Python/Node toolchain; `full` adds
  # the remaining language toolchains and interactive tooling.
  toolProfiles = pkgs: rec {
    minimal = with pkgs; [
      bashInteractive
      coreutils
      findutils
      gnugrep
      gnused
      gawk
      git
      ripgrep
      fd
      jq
      curl
      cacert
    ];

    default =
      minimal
      ++ (with pkgs; [
        gcc
        gnumake
        cmake
        python3
        nodejs
        tree
        less
        diffutils
        patch
        gnutar
        gzip
        which
        file
        procps
      ]);

    full =
      default
      ++ (with pkgs; [
        clang
        rustc
        cargo
        go
        ninja
        pkg-config
        neovim
        tmux
        htop
        wget
        openssh
        docker-client
      ]);
  };

  mkSandbox =
    pkgs:
    let
      profiles = toolProfiles pkgs;
    in
    pkgs.callPackage packageFile {
      minimalTools = profiles.minimal;
      defaultTools = profiles.default;
      fullTools = profiles.full;
    };
in
{
  flake.lib.mkClaudeSandbox = mkSandbox;

  flake.modules.nixos.claude-sandbox =
    { config, lib, pkgs, ... }:
    let
      cfg = config.claude-sandbox;
      sandbox = mkSandbox pkgs;

      # Applies the declared options as CLI flags and environment variables,
      # delegating to the sandbox entry point.
      wrapper = pkgs.writeShellApplication {
        name = "claude-sandbox";
        text = ''
          args=(--profile ${lib.escapeShellArg cfg.profile})
          ${lib.optionalString (!cfg.forwardSSHAgent) "args+=(--no-ssh-agent)"}
          ${lib.concatMapStringsSep "\n          " (
            dir: "args+=(--extra-bind ${lib.escapeShellArg dir})"
          ) cfg.extraBindMounts}
          ${lib.concatMapStringsSep "\n          " (
            dir: "args+=(--extra-ro ${lib.escapeShellArg dir})"
          ) cfg.extraReadOnlyMounts}
          ${lib.optionalString (cfg.extraPackages != [ ]) ''
            export CLAUDE_SANDBOX_EXTRA_PATH=${
              lib.escapeShellArg (lib.makeBinPath cfg.extraPackages)
            }
          ''}
          exec ${lib.getExe sandbox} "''${args[@]}" "$@"
        '';
      };
    in
    {
      options.claude-sandbox = {
        enable = lib.mkEnableOption "the bubblewrap sandbox for Claude Code";

        package = lib.mkOption {
          type = lib.types.package;
          default = wrapper;
          defaultText = lib.literalExpression "wrapper applying the configured options";
          description = ''
            Sandbox package to install. Defaults to a wrapper that applies the
            configured profile and mounts; override only for a custom build.
          '';
        };

        profile = lib.mkOption {
          type = lib.types.enum [ "minimal" "default" "full" ];
          default = "default";
          description = ''
            Tool profile made available inside the sandbox: `minimal` is basic
            CLI tooling, `default` adds gcc, make, cmake, python3 and nodejs,
            `full` adds clang, rust, go and interactive tooling.
          '';
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          example = lib.literalExpression "[ pkgs.sqlite ]";
          description = "Extra packages whose `bin` directories join the sandbox PATH.";
        };

        forwardSSHAgent = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to forward `SSH_AUTH_SOCK` into the sandbox. The agent
            socket is fully usable once forwarded: a read-only bind prevents
            file writes, not socket traffic.
          '';
        };

        extraBindMounts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "/home/user/shared-libs" ];
          description = "Directories bind-mounted read-write into the sandbox.";
        };

        extraReadOnlyMounts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "/opt/datasets" ];
          description = "Directories bind-mounted read-only into the sandbox.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          cfg.package
          pkgs.bubblewrap
        ];

        # Unprivileged user namespaces carry the whole isolation model.
        security.allowUserNamespaces = true;

        # Required by the optional FUSE-backed overlay mode.
        programs.fuse.userAllowOther = lib.mkDefault true;
      };
    };

  perSystem =
    { lib, pkgs, ... }:
    let
      sandbox = mkSandbox pkgs;
    in
    {
      packages.claude-sandbox = sandbox;
      apps.claude-sandbox = {
        meta.description = "Launch Claude Code inside the bubblewrap sandbox";
        program = lib.getExe sandbox;
      };
    };
}
