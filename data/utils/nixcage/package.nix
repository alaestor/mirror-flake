# (Originally from github:hamidr/nixcage/859d5bc6fab3623997890ab39d4aa6daeda3f2cf GPL-3.0)
#
# Vendored from the upstream flake's default package. Upstream built this in
# `flake.nix` from the whole repository checkout; here only the CLI and the
# base VM module are vendored, and the wrapper pins `NIXCAGE_BASE_MODULE` to
# the vendored module's store path (LOCAL DEVIATION — see the CLI header).
{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  gnused,
  jq,
  openssh,
  nix,
}:
stdenvNoCC.mkDerivation {
  pname = "nixcage";
  version = "1.2.0";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 nixcage $out/bin/nixcage
    install -Dm644 vm-base.nix $out/share/nixcage/vm-base.nix

    wrapProgram $out/bin/nixcage \
      --set NIXCAGE_BASE_MODULE $out/share/nixcage/vm-base.nix \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          gnused
          jq
          openssh
          nix
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "NixOS microVM environments for AI coding agents";
    homepage = "https://github.com/hamidr/nixcage";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.unix;
    mainProgram = "nixcage";
  };
}
