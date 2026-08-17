# LICENSE: MIT  (github:mrquentin/claude-sandbox 2025)
#
# Vendored from the upstream flake's `sandbox` derivation. Upstream built this
# in `flake.nix`; here it is a `callPackage`-able expression so both the flake
# `packages` output and the NixOS module can instantiate it per system.
{
  lib,
  stdenvNoCC,
  bashInteractive,
  bubblewrap,
  cacert,
  coreutils,
  curl,
  gnugrep,
  gnupg,
  gnused,
  git,
  jq,
  python3,
  slirp4netns,
  callPackage,
  # Tool profiles embedded in the sandbox; selected at runtime by `--profile`.
  minimalTools,
  defaultTools,
  fullTools,
  version ? "0.1.0",
}:

let
  seccompProfile = callPackage ./seccomp.nix { };

  minimalToolPath = lib.makeBinPath minimalTools;
  defaultToolPath = lib.makeBinPath defaultTools;
  fullToolPath = lib.makeBinPath fullTools;
  sslCertFile = "${cacert}/etc/ssl/certs/ca-bundle.crt";
in
stdenvNoCC.mkDerivation {
  pname = "claude-sandbox";
  inherit version;

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib

    # Library scripts, sourced by the entry point at runtime.
    cp detect.sh $out/lib/
    cp sanitize-git.sh $out/lib/
    cp healthcheck.sh $out/lib/
    cp security-tests.sh $out/lib/
    cp command-filter.sh $out/lib/
    cp egress-filter.sh $out/lib/
    cp egress-proxy.py $out/lib/
    cp network-isolation.sh $out/lib/
    cp seccomp-gen.py $out/lib/
    cp config.example.json $out/lib/
    chmod +x $out/lib/*.sh $out/lib/seccomp-gen.py $out/lib/egress-proxy.py

    # Seccomp profile; the sandbox refuses to start without it.
    cp ${seccompProfile}/seccomp.bpf $out/lib/seccomp.bpf

    cp sandbox.sh $out/bin/claude-sandbox
    chmod +x $out/bin/claude-sandbox

    # All tool references are absolute store paths, never PATH lookups.
    substituteInPlace $out/bin/claude-sandbox \
      --replace-fail '@TOOL_PATH_MINIMAL@' '${minimalToolPath}' \
      --replace-fail '@TOOL_PATH_DEFAULT@' '${defaultToolPath}' \
      --replace-fail '@TOOL_PATH_FULL@' '${fullToolPath}' \
      --replace-fail '@BWRAP@' '${bubblewrap}/bin/bwrap' \
      --replace-fail '@SSL_CERT_FILE@' '${sslCertFile}' \
      --replace-fail '@BASH@' '${bashInteractive}/bin/bash' \
      --replace-fail '@LIB_DIR@' "$out/lib" \
      --replace-fail '@COREUTILS@' '${coreutils}' \
      --replace-fail '@GIT@' '${git}' \
      --replace-fail '@GNUSED@' '${gnused}' \
      --replace-fail '@GNUGREP@' '${gnugrep}' \
      --replace-fail '@PYTHON3@' '${python3}/bin/python3' \
      --replace-fail '@JQ@' '${jq}/bin/jq' \
      --replace-fail '@SLIRP4NETNS@' '${slirp4netns}/bin/slirp4netns' \
      --replace-fail '@GPGCONF@' '${gnupg}/bin/gpgconf'

    substituteInPlace $out/lib/detect.sh \
      --replace-fail '@BWRAP@' '${bubblewrap}/bin/bwrap' \
      --replace-fail '@TRUE@' '${coreutils}/bin/true' \
      --replace-fail '@GNUGREP@' '${gnugrep}/bin/grep' \
      --replace-fail '@COREUTILS@' '${coreutils}'

    substituteInPlace $out/lib/egress-filter.sh \
      --replace-fail '@EGRESS_PROXY@' "$out/lib/egress-proxy.py"

    substituteInPlace $out/lib/sanitize-git.sh \
      --replace-fail '@GNUSED@' '${gnused}/bin/sed' \
      --replace-fail '@GNUGREP@' '${gnugrep}/bin/grep'

    substituteInPlace $out/lib/healthcheck.sh \
      --replace-fail '@BWRAP@' '${bubblewrap}/bin/bwrap' \
      --replace-fail '@TOOL_PATH@' '${defaultToolPath}' \
      --replace-fail '@SSL_CERT_FILE@' '${sslCertFile}' \
      --replace-fail '@BASH@' '${bashInteractive}/bin/bash' \
      --replace-fail '@GIT@' '${git}/bin/git' \
      --replace-fail '@CURL@' '${curl}/bin/curl' \
      --replace-fail '@TRUE@' '${coreutils}/bin/true' \
      --replace-fail '@GNUGREP@' '${gnugrep}/bin/grep' \
      --replace-fail '@SLIRP4NETNS@' '${slirp4netns}/bin/slirp4netns'

    runHook postInstall
  '';

  meta = {
    description = "OS-level sandbox for Claude Code using bubblewrap";
    homepage = "https://github.com/mrquentin/claude-sandbox";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "claude-sandbox";
  };
}
