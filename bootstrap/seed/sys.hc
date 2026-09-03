// sys.hc -- /proc-ish system inspection for the UART OS (CONSOLE.md #10).
// Uptime, heap mem summary, IRQ/device list, counters. No ps/task table yet.
// Virt CLINT timebase ≈ 10 MHz (CONFIG_TIMEBASE_FREQ on virt).
#define SYS_TIMEBASE 10000000
#define SYS_UART_IRQ 10
I64 g_boot_mtime;
I64 g_sys_inited;
// SysInit -- SysInit()
// NAME
//   SysInit - pin boot mtime for Uptime (idempotent)
// SYNOPSIS
//   U0 SysInit();
// DESCRIPTION
//   Records CLINT mtime at first call so Uptime / UptimeTicks measure since boot
//   of this seed path. Boot and Sys call this; safe mid-session (does not reset
//   the pin once set — use SysInitForce to re-pin).
// EXAMPLES
//   SysInit;
// SEE ALSO
//   Uptime  Sys  MEM_MTIME
U0 SysInit()
{
  if (g_sys_inited)
    return;
  if (MEM_MTIME)
    g_boot_mtime = *(I64 *)MEM_MTIME;
  else
    g_boot_mtime = 0;
  g_sys_inited = 1;
}

U0 SysInitForce()
{
  g_sys_inited = 0;
  SysInit;
}
// UptimeTicks -- UptimeTicks()
// NAME
//   UptimeTicks - CLINT mtime delta since SysInit
// SYNOPSIS
//   I64 UptimeTicks();
// DESCRIPTION
//   Raw cycle-counter ticks (mtime). Divide by SYS_TIMEBASE (~10e6 on virt) for
//   seconds. Returns 0 if MEM_MTIME missing.
// EXAMPLES
//   Print("%X\n", UptimeTicks);
// SEE ALSO
//   Uptime  UptimeSecs  SysInit
I64 UptimeTicks()
{
  I64 now;
  if (!g_sys_inited)
    SysInit;
  if (!MEM_MTIME)
    return 0;
  now = *(I64 *)MEM_MTIME;
  if (now < g_boot_mtime)
    return 0;
  return now - g_boot_mtime;
}
// UptimeSecs -- UptimeSecs()
// NAME
//   UptimeSecs - approximate seconds since SysInit
// SYNOPSIS
//   I64 UptimeSecs();
// DESCRIPTION
//   UptimeTicks / SYS_TIMEBASE (integer). Honest approx for virt-style maps.
// EXAMPLES
//   Print("%d\n", UptimeSecs);
// SEE ALSO
//   Uptime  UptimeTicks
I64 UptimeSecs()
{
  return UptimeTicks() / SYS_TIMEBASE;
}
// Uptime -- Uptime()
// NAME
//   Uptime - print UART uptime (mtime-based)
// SYNOPSIS
//   U0 Uptime();
// DESCRIPTION
//   /proc/uptime-ish one-liner: seconds + raw ticks + boot mtime pin. Not wall
//   clock (see MEM_RTC / LogNow for that).
// EXAMPLES
//   Uptime;
// SEE ALSO
//   Sys  Cnts  MEM_MTIME  LogNow
U0 Uptime()
{
  I64 t, s;
  if (!g_sys_inited)
    SysInit;
  t = UptimeTicks();
  s = t / SYS_TIMEBASE;
  UartStr("--- uptime ---\n");
  "  up %d s  (%X ticks @ ~%d Hz)\n", s, t, SYS_TIMEBASE;
  "  boot_mtime=%X  now=%X\n", g_boot_mtime, MEM_MTIME ? *(I64 *)MEM_MTIME : 0;
}
// MemRep -- MemRep()
// NAME
//   MemRep - HolyC heap summary (/proc/meminfo-ish)
// SYNOPSIS
//   U0 MemRep();
// DESCRIPTION
//   Reports HEAP_BASE..HEAP_END bump usage (hc_heap_brk) and free-list reclaim.
//   Soft arenas only — not a full page allocator. Dig-down: MemMap; MAlloc.
// EXAMPLES
//   MemRep;
// SEE ALSO
//   Sys  MemMap  MAlloc  HEAP_BASE
U0 MemRep()
{
  I64 used, room, free_n, free_b;
  CHolyBlk *b;
  used = hc_heap_brk - HEAP_BASE;
  room = HEAP_END - hc_heap_brk;
  free_n = 0;
  free_b = 0;
  b = hc_free_list;
  while (b) {
    free_n++;
    free_b += b->size;
    b = b->next;
  }
  UartStr("--- mem ---\n");
  "  heap  base=%X  brk=%X  end=%X\n", HEAP_BASE, hc_heap_brk, HEAP_END;
  "  used=%X  bump_free=%X  freelist=%d blks / %X B\n", used, room, free_n, free_b;
  "  MEM_FS=%X  MEM_RAM=%X\n", MEM_FS, MEM_RAM;
}
// IrqRep -- IrqRep()
// NAME
//   IrqRep - PLIC enable/pending + machine IE bits
// SYNOPSIS
//   U0 IrqRep();
// DESCRIPTION
//   Inventory of PLIC base, UART IRQ number, and register offsets. Does not
//   poke live PLIC enable/pending (can hang before TrapInit on some images).
//   Dig-down: MemMap; TrapInit; peek enable/pending; never read CLAIM.
//   mie/mstatus: CpuRep; / Reg("mie");
// EXAMPLES
//   IrqRep;
// SEE ALSO
//   DevRep  Sys  PLIC  TrapInit  CpuRep
// BUGS
//   Live pending/enable bits not printed yet — offsets only until safe peek.
U0 IrqRep()
{
  UartStr("--- irq ---\n");
  // Inventory only: live PLIC MMIO peeks can hang on some qemu/maps before TrapInit.
  // Dig-down: MemMap; TrapInit; then *(U32 *)(MEM_PLIC+MEM_PLIC_ENABLE_OFF).
  "  MEM_PLIC=0x%X  uart_irq=%d\n", MEM_PLIC, SYS_UART_IRQ;
  if (MEM_PLIC) {
    "  enable@+0x%X  pending@+0x%X  thr@+0x%X\n", MEM_PLIC_ENABLE_OFF, MEM_PLIC_PENDING_OFF, MEM_PLIC_THRESHOLD_OFF;
    UartStr("  (live bits after TrapInit: peek enable/pending; never read CLAIM)\n");
  } else
    UartStr("  (no PLIC on this map)\n");
  UartStr("  mie/mstatus: CpuRep; / Reg(\"mie\");\n");
}

U0 SysDevLine(U8 *name, I64 base, U8 *drv)
{
  UartStr("  ");
  UartStr(name);
  if (!base) {
    UartStr("  (absent)\n");
    return;
  }
  "  0x%X  %s\n", base, drv;
}
// DevRep -- DevRep()
// NAME
//   DevRep - mapped devices / MEM_* presence list
// SYNOPSIS
//   U0 DevRep();
// DESCRIPTION
//   /proc/devices-ish table of board MEM_* windows that are non-zero, with the
//   HolyC driver hint from MemMapSelected. Absent (0) bases are marked. Prefer
//   MemMap for live JIT sizes; this is the compact inventory.
// EXAMPLES
//   DevRep;
// SEE ALSO
//   IrqRep  MemMapDrv  MemMap  Sys
U0 DevRep()
{
  UartStr("--- devices ---\n");
  SysDevLine("UART", MEM_UART, MEMMAP_DRV_UART);
  SysDevLine("CLINT", MEM_CLINT, MEMMAP_DRV_CLINT);
  SysDevLine("PLIC", MEM_PLIC, MEMMAP_DRV_PLIC);
  SysDevLine("VIRTIO", MEM_VIRTIO, MEMMAP_DRV_VIRTIO);
  SysDevLine("FW_CFG", MEM_FW_CFG, MEMMAP_DRV_FW_CFG);
  SysDevLine("RTC", MEM_RTC, MEMMAP_DRV_RTC);
  SysDevLine("FB", MEM_FB, MEMMAP_DRV_FB);
  SysDevLine("FS", MEM_FS, MEMMAP_DRV_FS);
  SysDevLine("HEAP", MEM_HEAP, MEMMAP_DRV_HEAP);
  SysDevLine("TEST", MEM_TEST, MEMMAP_DRV_TEST);
}
// Cnts -- Cnts()
// NAME
//   Cnts - session / CSR counters
// SYNOPSIS
//   U0 Cnts();
// DESCRIPTION
//   Prints dmesg ring depth/dropped and memfs journal depth when FsLogReady.
//   For mcycle/minstret use Reg("mcycle"); / Reg("minstret"); (CSR dig-down).
// EXAMPLES
//   Cnts;
// SEE ALSO
//   Sys  LogCount  Uptime  Reg
U0 Cnts()
{
  I64 logs;
  logs = LogCount();
  UartStr("--- cnts ---\n");
  // mcycle/minstret via Reg when CSR asm is live: Reg("mcycle");
  "  dmesg=%d", logs;
  if (g_log_dropped)
    "  dropped=%d", g_log_dropped;
  PutCh('\n');
  if (FsLogReady)
    "  fs_log=%d  epoch=%d  seq=%d\n", FsLogCount, FsEpoch(), FsSeq();
  else
    UartStr("  fs_log=(not ready)\n");
}
// Sys -- Sys()
// NAME
//   Sys - one-shot /proc-ish system inspection dump
// SYNOPSIS
//   U0 Sys();
// DESCRIPTION
//   Calls Uptime, MemRep, IrqRep, DevRep, Cnts. UART-OS equivalent of peeking
//   /proc/{uptime,meminfo,interrupts,devices}. No ps yet (single REPL task).
// EXAMPLES
//   Sys;
//   Uptime; MemRep; IrqRep;
// SEE ALSO
//   Help  CpuRep  MemMap  DMesg  Man("Sys")
// BUGS
//   No task/mount table; timebase fixed at SYS_TIMEBASE for virt-class boards.
U0 Sys()
{
  if (!g_sys_inited)
    SysInit;
  UartStr("=== sys (UART /proc-ish) ===\n");
  Uptime;
  MemRep;
  IrqRep;
  DevRep;
  Cnts;
  UartStr("=== sys end ===\n");
}
// SysHelp -- SysHelp()
// NAME
//   SysHelp - short cheat sheet for system inspection
// SYNOPSIS
//   U0 SysHelp();
// DESCRIPTION
//   Lists Uptime / MemRep / IrqRep / DevRep / Cnts / Sys entry points.
// EXAMPLES
//   SysHelp;
// SEE ALSO
//   Sys  Help  Man("Sys")
U0 SysHelp()
{
  UartStr("SysHelp — /proc-ish inspection (CONSOLE.md #10)\n");
  UartStr("  Sys;       // all-in-one\n");
  UartStr("  Uptime; MemRep; IrqRep; DevRep; Cnts;\n");
  UartStr("  Man(\"Sys\");  CpuRep;  MemMap;  DMesg;\n");
}
SysInit;
