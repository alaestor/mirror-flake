/**
  # jail.nix

  Vendored from [jail.nix](https://git.sr.ht/~alexdavid/jail.nix) (GPL-3.0).
  Exposes the upstream library as `flake.lib.jail`, a helper for wrapping
  derivations in [bubblewrap](https://github.com/containers/bubblewrap).

  Only the bare minimum permissions are granted by default; capabilities are
  added by passing *combinators* (network, gui, gpu, readonly, rw-bind, ...)
  when jailing a package:

  ```nix
  jail = self.lib.jail.init pkgs;
  jailed = jail "my-jail" untrusted-package (with jail.combinators; [
    network
    gui
    (readonly "/var/log/journal")
    (rw-bind (noescape "~/foo") "/bar")
  ]);
  ```

  Interface (upstream `lib/default.nix`):

  - `init pkgs` — the jail function for a given `pkgs`, carrying `.combinators`.
  - `extend { pkgs, additionalCombinators ? ..., basePermissions ? ...,
    bubblewrapPackage ? ... }` — same, with the defaults overridden.
  - `mkOverlay { final, prev, packages }` — a nixpkgs overlay replacing the
    named packages with jailed variants (each keeps `.jailed` / `.unjailed`).

  The upstream `lib/` tree lives verbatim under `data/utils/jail-nix/`, one
  file per combinator, each tagged with its provenance. It is imported rather
  than inlined because `combinators.nix` discovers combinators by reading its
  own directory.
*/
{ self, ... }:
{
  flake.lib.jail = import (self.data.path "utils/jail-nix");
}
