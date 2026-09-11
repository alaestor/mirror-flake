/**
  DeepSeek Harness (`dsh`) serving its browser UI, wrapped so a session runs
  in the agent VM.

  `ds` boots the web profile inside the guest and forwards its port back out;
  `ds-native` is the unsandboxed escape hatch, exactly as with `cc` and `cx`.
  Neither takes selectors: the UI is where a model, an effort level, or a
  profile gets chosen, so a command line that duplicated those choices would
  only be a second place for them to disagree.

  `$DSH_HOME` (`~/.dsh`) is a shared state directory rather than a guest-local
  volume, which is what makes `dsh plugin ... add` on either side visible to
  the other. See `stateDirs.deepseek` in `libagents.nix` for the SQLite
  caveat that comes with putting it on virtiofs.
*/
{ inputs, self, ... }:
{
  flake.modules.homeManager.deepseek-harness =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      agents = self.lib.agents;
      cfg = config.deepseek-harness;
      sandboxWritableRoots = agents.sandboxWritableRootsFor "$HOME";

      dsh = inputs.deepseek-harness.packages.${pkgs.stdenv.hostPlatform.system}.dsh;

      port = agents.webPorts.deepseek;

      wrappers = agents.mkHarnessWrappers pkgs {
        name = "ds";
        runtimeInputs = [ dsh ]
        ++ agents.tools pkgs
        ++ [
          pkgs.rtk
          pkgs.tlrc
        ];
        nativeText = ''
          export BASH_ENV=${agents.findGuardBashEnv pkgs}

          # Without this the guest has no git identity at all and `git
          # commit` fails; see `gitEnvironmentText` (`libagents.nix`).
          ${agents.gitEnvironmentText config}

          dsh_args=( --profile web --port ${toString port} )

          # dsh accepts no bind address but `127.0.0.1`: its webserver schema
          # admits only that and `0.0.0.0`, and the CLI refuses `0.0.0.0`
          # outright as unreviewed remote code execution. Reaching the UI
          # from outside the guest is therefore an ssh forward's job, not a
          # bind's — see the `--forward` argument in `sandbox` below.
          dsh_args+=( --host 127.0.0.1 )

          if [[ "''${AGENT_VM_GUEST:-}" == 1 ]]; then
            # Nothing in the guest can open a browser.
            dsh_args+=( --no-open )
          fi

          ${lib.concatMapStringsSep "\n" (host: ''
            dsh_args+=( --trusted-host ${lib.escapeShellArg host} )
          '') cfg.trustedHosts}

          # Caller arguments last so a repeated flag takes the caller's value.
          exec ${lib.getExe dsh} "''${dsh_args[@]}" "$@"
        '';

        sandbox = native: ''
          cwd="$(${pkgs.coreutils}/bin/realpath "$PWD")"
          in_root=0
          sandbox_writable=(
            ${lib.concatMapStringsSep "\n            " (root: ''"${root}"'') sandboxWritableRoots}
          )

          for root in "''${sandbox_writable[@]}"; do
            [[ -d "$root" ]] || continue
            root="$(${pkgs.coreutils}/bin/realpath "$root")"
            if [[ "$cwd" == "$root" || "$cwd" == "$root"/* ]]; then
              in_root=1
              break
            fi
          done

          if [[ "$in_root" -ne 1 ]]; then
            echo "ds: refusing to run $cwd in the agent VM — it is outside every shared root:" >&2
            printf '  %s\n' "''${sandbox_writable[@]}" >&2
            echo "cd into one of them, or run ds-native to bypass the VM instead." >&2
            exit 1
          fi

          echo "ds: serving the DeepSeek Harness web UI on http://127.0.0.1:${toString port}" >&2
          ${lib.concatMapStringsSep "\n" (host: ''
            echo "ds: also reachable at http://${host}" >&2
          '') cfg.trustedHosts}

          # The forward's host-side bind is every address rather than
          # loopback so a phone can reach it. That is only as wide as the
          # firewall lets it be: nothing admits this port on a LAN
          # interface, and the forward exists only while this session runs.
          exec agent-vm-session \
            --forward '0.0.0.0:${toString port}:127.0.0.1:${toString port}' \
            -- bash -c 'cd "$1" && shift && exec "$@"' bash "$cwd" \
            ${lib.getExe native} "$@"
        '';
      };
    in
    {
      options.deepseek-harness.trustedHosts = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [ ];
        example = [ "workstation.example.net:3080" ];
        description = ''
          Extra authorities (`host` or `host:port`) accepted by the web UI's
          browser-trust fence. Needed for every name other than the bound
          address a browser may use to reach the UI; requests carrying an
          unlisted `Host` are refused by `/api` even though the page loads.
        '';
      };

      config.home.packages = [
        wrappers.native
        wrappers.wrapped
      ];
    };
}
