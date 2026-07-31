# Flake-wide inputs

This directory tracks flake inputs that provide shared infrastructure or are consumed across a wide-range of modules, such as Nixpkgs and Home Manager. This causes some centralization but reduces the changes of modules getting out of sync or reimporting common objects under different names.

Keep inputs used by a single feature or program alongside that module.
