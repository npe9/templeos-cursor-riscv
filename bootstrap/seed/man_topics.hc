// man_topics.hc -- Man("Topic") pages for symbols / hardware (not HTT_FUN).
// Loaded into memfs with other seeds; Man/DocFileFor scan `// Name --` anchors
// case-insensitively. Edit this file, then Man("CLINT") again (no Run needed).
//
// Topics here: CLINT, MEM_CLINT, MEM_MTIME, MEM_MTIMECMP, PLIC, MEM_PLIC, MTIE, MIE,
//   MemMap (driver column overview — also Man on the MemMap fun in sym.hc), SiFive.
// MemMap -- MemMap (region ↔ driver)
// NAME
//   MemMap - memory / MMIO map with HolyC driver column
// SYNOPSIS
//   MemMap;  MemMapDrv;  MemMapDrvFind("uart");  MemMapFind("clint");
// DESCRIPTION
//   MemMap prints each MEM_* window and, in the last column, which HolyC driver
//   or subsystem owns it. Default seed profile (typical virt-style map):
//     MEM_UART / MEM_CLINT / MEM_PLIC / MEM_VIRTIO / MEM_FB / MEM_FW_CFG
//     (absolute bases: Print("%X\n", MEM_UART); MemMapFind("uart");)
//   Soft arenas (FS/HEAP/trap snaps) point at seed files. Other boards: Kconfig
//   selects under Kernel/Drv/*Selected.HH; Kernel/Drv/RVMemMap.HC mirrors them.
//   On sifive_u / sifive_e the UART/CLINT/PLIC column points at RVSifivePlat
//   (Man("SiFive")).
// EXAMPLE
//   MemMap;
//   Print("%X\n", MEM_UART);
//   Print("%s\n", MemMapDrvFind("uart"));
//   Man("CLINT");  Man("PLIC");  Man("SiFive");
// CROSS-REFS
//   MemMapDrv  MemMapDrvFind  MemMapFind  CLINT  PLIC  RegHelp
// BUGS
//   REPL MemMap is host-slot C with live JIT sizes; seed MemMapDrv* is the
//   portable driver legend. Addresses above are this board profile’s MEM_* —
//   see PLATFORM.md.
// CLINT -- CLINT (Core-Local Interruptor)
// NAME
//   CLINT - Core-Local Interruptor (machine timer + soft IRQ)
// SYNOPSIS
//   Man("CLINT");  Man("Clint");  Man("clint");
//   // also: MEM_CLINT, MEM_MTIME, MEM_MTIMECMP, TimerArm, TrapInit, SetTrap, OnTick
// DESCRIPTION
//   CLINT is the RISC-V Core-Local Interruptor. This port uses the standard
//   SiFive-style layout at MEM_CLINT (board profile via csr.hc / Kconfig):
//     mtime     @ MEM_MTIME     (= MEM_CLINT+MEM_CLINT_MTIME_OFF)
//     mtimecmp  @ MEM_MTIMECMP  (= MEM_CLINT+MEM_CLINT_MTIMECMP_OFF, hart0)
//   Programming a periodic machine timer from the UART REPL:
//     1. Write a HolyC handler I64 OnTick(I64 cause,I64 epc,I64 tval) that re-arms
//        mtimecmp (see Run("timer.hc") for a stock OnTick).
//     2. SetTrap("OnTick");     // C trapvec resolves the name live
//     3. TrapInit();            // mtvec -> TrapVec, enable mstatus.MIE
//     4. TimerArm(interval);    // mtimecmp = mtime + interval; enable mie.MTIE
//     5. Idle with asm { wfi } or keep typing; each tick calls OnTick then mret.
//   TimerArm / the C trapvec also re-arm; your handler should still write a future
//   mtimecmp or the IRQ stays pending and you livelock.
// EXAMPLE
//   SetTrap("OnTick");
//   TrapInit();
//   TimerArm(1000000);   // ~0.1 s at ~10 MHz mtime (this board’s timebase)
//   // Or re-arm by hand: *(I64 *)MEM_MTIMECMP=*(I64 *)MEM_MTIME+1000000;
//   asm { wfi }
//   // Or: Run("timer.hc"); SetTrap("OnTick"); TrapInit(); TimerArm(1000000);
// CROSS-REFS
//   TimerArm  TrapInit  SetTrap  OnTick  MEM_CLINT  MEM_MTIME  MEM_MTIMECMP  MTIE  MIE
//   Kernel: RVTimer.HC / CONFIG_CLINT_* (same MEM_* via Kconfig on this profile).
//   MemMap last column: "RVTimer / CLINT". Man("MemMap"); MemMapDrvFind("clint");
// BUGS
//   Addresses above are MEM_* defaults baked into trap.hc / csr.hc for the
//   typical virt-style map. Other boards use Kconfig CLINT base/offsets —
//   see templeos-riscv/PLATFORM.md. Soft IRQ (msip) is not wrapped by TimerArm.
//   Do not call TrapInit at file-load time during boot.
// MEM_CLINT -- MEM_CLINT
// NAME
//   MEM_CLINT - base address of the CLINT MMIO window
// SYNOPSIS
//   #define MEM_CLINT 0x02000000   // csr.hc (this board profile)
//   MemMapFind("clint");          // -> MEM_CLINT
// DESCRIPTION
//   Base of the Core-Local Interruptor. Timer registers used by this port:
//     MEM_MTIME    = MEM_CLINT + MEM_CLINT_MTIME_OFF
//     MEM_MTIMECMP = MEM_CLINT + MEM_CLINT_MTIMECMP_OFF  (hart0)
//   Full programming walkthrough: Man("CLINT").
// CROSS-REFS
//   CLINT  MEM_MTIME  MEM_MTIMECMP  TimerArm  MemMapFind
// BUGS
//   #define only — not an HTT_FUN. Man page is topic text in man_topics.hc.
// MEM_MTIME -- MEM_MTIME
// NAME
//   MEM_MTIME - CLINT mtime register address
// SYNOPSIS
//   #define MEM_MTIME 0x0200BFF8
//   I64 t=*(I64 *)MEM_MTIME;
// DESCRIPTION
//   Free-running machine timer counter. Typical virt-style map ~10 MHz
//   (CONFIG_TIMEBASE_FREQ on Kernel boards). TimerArm reads mtime
//   then writes mtimecmp = mtime + interval. See Man("CLINT").
// CROSS-REFS
//   CLINT  MEM_MTIMECMP  MEM_CLINT  TimerArm
// BUGS
//   Topic-only (#define in csr.hc).
// MEM_MTIMECMP -- MEM_MTIMECMP
// NAME
//   MEM_MTIMECMP - CLINT hart0 mtimecmp address
// SYNOPSIS
//   #define MEM_MTIMECMP 0x02004000
//   *(I64 *)MEM_MTIMECMP=*(I64 *)MEM_MTIME+1000000;
// DESCRIPTION
//   Compare register for hart 0. When mtime >= mtimecmp, mip.MTIP is set; with
//   mie.MTIE and mstatus.MIE the trapvec runs your SetTrap handler. Re-arm in the
//   handler (OnTick) or you will spin. See Man("CLINT") and Man("TimerArm").
// CROSS-REFS
//   CLINT  MEM_MTIME  TimerArm  OnTick  MTIE
// BUGS
//   Topic-only (#define in csr.hc). Only hart0 compare is used by TimerArm.
// PLIC -- PLIC (Platform-Level Interrupt Controller)
// NAME
//   PLIC - Platform-Level Interrupt Controller (external IRQs)
// SYNOPSIS
//   Man("PLIC");  MemMapFind("plic");  // MEM_PLIC on this board profile
// DESCRIPTION
//   PLIC fans out external interrupts (UART, virtio, …) to harts. CLINT is local
//   (timer / soft); PLIC is platform-wide. This board’s PLIC MMIO base is
//   MEM_PLIC. The UART REPL timer path does not program the PLIC —
//   use TimerArm/CLINT for machine timer. Kernel drivers: Kernel/Drv/RVPlic*.HC
//   and Kconfig CONFIG_PLIC_*.
// CROSS-REFS
//   MEM_PLIC  CLINT  TrapInit  SetTrap
// BUGS
//   No full HolyC PLIC programming walkthrough in the REPL yet; this page is the
//   map + distinction from CLINT. Board stubs exist for machines without a PLIC.
// MEM_PLIC -- MEM_PLIC
// NAME
//   MEM_PLIC - PLIC MMIO base
// SYNOPSIS
//   #define MEM_PLIC 0x0C000000   // csr.hc (Print("%X\n", MEM_PLIC);)
// DESCRIPTION
//   Base of the Platform-Level Interrupt Controller. See Man("PLIC").
// CROSS-REFS
//   PLIC  MEM_CLINT  MemMapFind
// BUGS
//   Topic-only (#define in csr.hc).
// MTIE -- MTIE (mie bit 7)
// NAME
//   MTIE - Machine Timer Interrupt Enable (CSR mie bit 7)
// SYNOPSIS
//   // TimerArm enables MTIE via HcCsrsMieTimer (csrs mie, 1<<7)
//   GetMie;  CSRGet(CSR_MIE);
// DESCRIPTION
//   Bit 7 of CSR mie (0x304). Cleared: timer pending bits do not trap. TimerArm
//   sets MTIE after programming mtimecmp. Pair with mstatus.MIE (Man("MIE")) and
//   TrapInit. See Man("CLINT").
// CROSS-REFS
//   MIE  TimerArm  TrapInit  CLINT  CSR_MIE  GetMie
// BUGS
//   Topic name only — not a callable. Value is (1<<7)==128.
// MIE -- MIE (mstatus bit 3)
// NAME
//   MIE - global Machine Interrupt Enable (CSR mstatus bit 3)
// SYNOPSIS
//   TrapInit();           // csrs mstatus, MIE
//   GetMStatus; Reg("mstatus");
// DESCRIPTION
//   Bit 3 of CSR mstatus (0x300). TrapInit enables it so machine interrupts
//   (including the timer when mie.MTIE is set) can fire. Distinct from CSR mie
//   (per-cause enables) and from mie.MTIE (Man("MTIE")).
// CROSS-REFS
//   MTIE  TrapInit  CLINT  CSR_MSTATUS  GetMStatus  RegHelp
// BUGS
//   Topic name only — not a callable. Value is (1<<3)==8.
// SiFive -- SiFive (platform interface)
// NAME
//   SiFive - HolyC platform facade for sifive_u / sifive_e boards
// SYNOPSIS
//   Man("SiFive");  Man("sifive");
//   // Kernel: #include "Drv/RVSifivePlat.HC"
//   //   RVSifivePresent; RVSifiveUartInit; RVSifiveUartPutS(s);
//   //   RVSifiveClintArmTicks(n); RVSifivePlicEnable(irq,1);
// DESCRIPTION
//   Named API over SiFive UART0 + CLINT + PLIC (bases from Kconfig /
//   Kernel/RVAutoConf.HH). On PLATFORM_SIFIVE_U / PLATFORM_SIFIVE_E,
//   RVSifiveSelected.HH pulls RVSifiveYes.HC; other machines get RVSifiveNo
//   stubs (Present=FALSE). Generic RVUart* on those boards thin-wraps
//   RVSifiveUart*. MemMap driver column: "RVSifivePlat". Smoke:
//   make kernel-plat-sifive-u-smoke. See templeos-riscv/PLATFORM.md.
// CROSS-REFS
//   MemMap  CLINT  PLIC  RVMemMap  RVUartSifive  RVTimer  RVPlicHw
// BUGS
//   REPL Man topic is documentation only — live RVSifive* symbols live in the
//   Kernel/Drv HolyC tree, not the default REPL seed. sifive_e DTIM is too small
//   for full Kernel_RV.
