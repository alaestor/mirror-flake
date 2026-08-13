/**
  The release channels this repository tracks.

  Input families that ship both a stable and an unstable edition pin the stable
  edition to `stable`, so the release is stated once rather than repeated at
  every input declaration, and consumers can read the pin from the flake
  without evaluating a host.
*/
{
  flake.fleet.channels.stable = "26.05";
}
