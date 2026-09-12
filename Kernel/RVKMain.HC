// RVKMain: RISC-V analogue of KMain() (bucket 1: tables + Adam + first Spawn).
// Included last in Kernel_RV.PRJ (after RVFb/RVGr) so boot can call RVSysGrInit.
// Helpers (RVBootTask*, RVMountRAMDisk, RVKSpawn, heap/MAlloc) live in KBootRV.HC.
U0 RVKMain()
{
  // KMain()'s first act is adam_task=Fs. Adam is the root CTask; establish it and Fs before anything
  // allocates, because the real ACAlloc/CAlloc used during heap setup allocate against adam_task.
  CTask *adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  // Linear arena (KBootRV MAlloc). Full BlkPool/HeapCtrl/MemPag only on non-thin boots —
  // thin Jump path never pages through MemPagTaskAlloc.
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
#ifdef RV_THIN_LOADER
  the_heap->hc_signature = HEAP_CTRL_SIGNATURE_VAL;
  adam->code_heap = the_heap;
  adam->data_heap = the_heap;
#else
  CBlkPool *bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  CHeapCtrl *ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  // TaskInit reads the init FPU state from here (see PRJ note)
#endif
  // Create Adam via TaskInit (full KTask, or KThinTaskStubs under RV_THIN_LOADER).
  TaskInit(adam, 0);
  // Per-CPU block (Gs): the scheduler reads Gs->seth_task. KMain sets this up via Core0Init.
  CCPU *gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  // wire the kernel's Yield() to &Fs
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
  // 1 ms jiffy from Kconfig timebase
  RVKernelInit();
  // portable tables + UART console (needs Fs valid and the heap up)
#ifndef RV_THIN_LOADER
  RVFbPlatApplyPresent();
  // Kconfig FB present kind (ramfb on virt; none elsewhere)
#endif
  // Bring up storage and mount the file system (KMain's BlkDevsInitAll / DskChg). On the QEMU virt
  // machine this is a RAM disk auto-formatted with the kernel's own RedSea — a real, mounted drive A.
#ifdef RV_THIN_LOADER
#ifdef RV_THIN_EMBED_BIN
  // G9: Kernel.BIN linked at KERNEL_EMBED_ADDR — no thin MMIO+raw chicken-egg.
  // SoftCall re-Inits virtio + first RedSea mount after Jump.
  Print("RVKMain: thin embed Kernel.BIN; SoftCall owns virtio.\n");
#else
  // G9 chicken-egg libs: RVThinVirtioBlk (MMIO) + RVRedSeaRaw + linear arena.
  // SoftCall owns first RedSea mount after Jump; no BlkDevAdd / DskVirtioRV here.
  if (VirtioBlkInit()) {
    Print("RVKMain: thin loader VirtioBlkInit FAILED (no virtio-blk).\n");
    return;
  }
  Print("RVKMain: thin MMIO+raw+arena OK; defer first mount to SoftCall.\n");
#endif
  RVThinLoader;
  // Unreachable when Stay holds (Jump + KernelEntry HLT).
  Print("RVKMain: thin loader returned (FAIL); skipping Boot/Spin task wait.\n");
  return;
#else
#ifdef RV_PHASE3
#define RV_REDSEA_VIRTIO_BOOT 1
#endif
#ifdef RV_REDSEA_VIRTIO_BOOT
  // G9: prefer virtio-blk RedSea image (ships Compiler.BIN + Kernel.BIN) over blank RAM.
  // phase3 smokes attach build/*_redsea.img; no virtio → RAM fallback.
  RVMountVirtioDisk('A');
  if (!Fs->cur_dv || Fs->cur_dv->dv_signature != DRV_SIGNATURE_VAL) {
    RVMountRAMDisk('A', 16384);
    // 8 MB — guest Cmp + Adam/MakeOS need room
  }
#else
  RVMountRAMDisk('A', 4096);
  // 2 MB RedSea disk on drive 'A'
#endif
  // Prove the booted kernel has a working filesystem: write a file and read it back through the
  // kernel's own FileWrite/FileRead (the Load/ExeFile path). Runs as Adam, whose cur_dv the mount set.
  
  {
    U8 *msg = "booted with a mounted RedSea filesystem";
    FileWrite("A:/BOOT.TXT", msg, StrLen(msg));
    I64 sz = 0;
    U8 *back = FileRead("A:/BOOT.TXT", &sz, NULL);
    if (back && sz == StrLen(msg) && !StrNCmp(back, msg, StrLen(msg)))
      Print("RVKMain: mounted RedSea on A:, wrote and read A:/BOOT.TXT back OK (%d bytes).\n", sz);
  }
  RVHomeBringUp('A');
#ifdef RV_PHASE3
  RVPhase3;
  /* Skip WinInit here: fw_cfg/ramfb probe can stall under -nographic; FB Adam path is win-smoke. */
  Print("RVKMain: phase3 smoke complete; skipping Boot/Spin task wait.\n");
  return;
#endif
  // x86: SysGlblsInit / Mem32DevInit / UncachedAliasAlloc / LoadKernel / SysGrInit — VGA display.
  // RISC-V: after Compiler/StartOS (TempleOS StartOS owns WinMgr spawn). Soft term if no present.
  if (!RVSysWinInit())
    RVSysGrInit();
  // Arm the machine-timer preemption (the RISC-V analogue of IntInit2/IntsInit installing the timer
  // trap handler via mtvec/CLINT) BEFORE spawning, so a task that never yields is forced to share the CPU. Without this the
  // self-booted kernel would be cooperative-only — one runaway task would hang Adam forever, which is
  // not a scheduler TempleOS's real workload could run on.
  RVPreemptReal(400000);
  Print("RVKMain: spawning Adam's tasks via the kernel's own Spawn()...\n");
  CTask *t = RVKSpawn(&RVBootTask, "Boot Task", adam);
  // yields + exits
  CTask *t2 = RVKSpawn(&RVBootTask2, "Spin Task", adam);
  // never yields -> only preemption runs the rest
  // Schedule: Adam yields until BOTH children have run and exited. The kernel's Yield() skips a killed
  // child on the next lap; the spin task advances only in the slices the timer preempts it out of.
  while (!(t->task_flags & (1 << TASKf_KILL_TASK)) || !(t2->task_flags & (1 << TASKf_KILL_TASK))) {
    // Keep WinMgr interactive while Boot/Spin run (virtio-keyboard / tablet when present).
    if (rv_winmgr.ready)
      RVWinMgrPumpInput(16);
    Yield;
  }
  Print("RVKMain: tasks finished; Adam is scheduling (spin task preempted over %d iterations).\n", rv_boot_spins);
  // Interactive hosts: call RVWinMgrRun(0) from a demo, or pass virtio-keyboard and
  // invoke Run after boot. Do not block here — headless selfboot smoke must exit.
  if (rv_winmgr.ready)
    RVWinMgrPumpInput(8);
#endif
}
