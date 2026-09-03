// ops.hc -- SafeMode / Recover (UART-only operate-through; no WinMgr).
// Full UART REPL seed path (BOOT_ORDER). See docs/OPS.md / MEMFS_LOG.md P6.
// SafeMode -- SafeMode()
// NAME
//   SafeMode - UART ops recovery: checkpoint memfs, print export/reset recipe
// SYNOPSIS
//   SafeMode;
// DESCRIPTION
//   Operate-through helper when the prompt still works but the session feels
//   wedged. UART-only (this REPL has no WinMgr). Pins FsCheckpoint("safemode")
//   when the journal is ready, else FsSnap. Does not wipe memfs and does not
//   call Reset — export first (FsChanges / DumpChanges / ZmodemSendChanges),
//   then Reset if you need a clean Boot stack. Soft reseed: Recover / FsRecover.
// EXAMPLES
//   FsChanges;
//   SafeMode;
//   DumpChanges;
//   Reset;
// SEE ALSO
//   Recover  FsRecover  Reset  FsChanges  FsCheckpoint  FsSnap  DumpChanges
// BUGS
//   Does not disable editors or IRQs — banner + epoch pin only. See docs/OPS.md.
U0 SafeMode()
{
  UartStr("SafeMode — UART ops recovery (no WinMgr)\n");
  UartStr("  Export   FsChanges;  DumpChanges;  or ZmodemSendChanges;\n");
  UartStr("  Soft     Reset;      // Boot re-entry; memfs kept\n");
  UartStr("  Reseed   Recover;    // drop non-snap + FsEpochSeal(RECOVER)\n");
  if (FsLogReady)
    FsCheckpoint("safemode");
  else
    FsSnap;
  UartStr("SafeMode: epoch pinned. Export session work before Reset/Recover.\n");
}
// Recover -- Recover()
// NAME
//   Recover - soft recover: drop session files and reseal RECOVER epoch
// SYNOPSIS
//   Recover;
// DESCRIPTION
//   MEMFS_LOG P6 soft recover. Calls FsRecover: deletes slots not in the current
//   snap table, then seals a new epoch labeled RECOVER (journal cleared, snap
//   rebuilt). Does not reinstall pristine seed bytes from the host blob —
//   mutated snap files stay until power-cycle / image rebuild. Export first
//   (DumpChanges / ZmodemSendChanges). FsReplay verifies journal vs tree
//   without rewriting bodies.
// EXAMPLES
//   FsChanges;
//   DumpChanges;
//   FsReplay;
//   Recover;
//   FsChanges;   // (none)
// SEE ALSO
//   FsRecover  FsReplay  SafeMode  Reset  FsSnap  FsEpochSealNamed
// BUGS
//   No guest ROM reseed of seed bodies — honest limit; see docs/MEMFS_LOG.md.
U0 Recover()
{
  UartStr("Recover — soft memfs clean + RECOVER reseal (MEMFS_LOG P6)\n");
  UartStr("  Prefer: FsChanges; DumpChanges; or ZmodemSendChanges; first\n");
  UartStr("  Verify: FsReplay;   // journal vs tree (no body rewrite)\n");
  FsRecover;
  UartStr("  Hard pristine reseed: rebuild/reflash image or power-cycle\n");
}
