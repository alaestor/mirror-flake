/** Maximum history shared by local journals and the central log collector. */
{
  flake.fleet.logging = {
    retentionDays = 365;
    journalRotationDays = 7;
    journalMaxUse = "15G";
    runtimeJournalMaxUse = "128M";
  };
}
