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
  // Bring up the linear arena the RISC-V MAlloc carves from, plus the kernel's own block pool and
  // heap-control (BlkPoolInit/HeapCtrlInit run unchanged). KMain does this via BlkPoolsInit.
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  CBlkPool *bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  CHeapCtrl *ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  // TaskInit reads the init FPU state from here (see PRJ note)
  // Create Adam through the kernel's OWN TaskInit — the very call KStart64.HC makes for adam. It
  // fills in task_num, rflags, the code/data-heap free-list queues, the FPU save area, the hash
  // table, a real stack (setting rsp), the window fields, and seeds the self-looped next_task/
  // last_task ring. Adam's rsp is re-established at the first context switch away from RVKMain, so
  // the fresh stack TaskInit allocates is only a placeholder here. Everything TaskInit touches is
  // the kernel's own code; only MAlloc and SYS_FIXED_AREA underneath it are RISC-V ports.
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
  RVFbPlatApplyPresent();
  // Kconfig FB present kind (ramfb on virt; none elsewhere)
  // Bring up storage and mount the file system (KMain's BlkDevsInitAll / DskChg). On the QEMU virt
  // machine this is a RAM disk auto-formatted with the kernel's own RedSea — a real, mounted drive A.
#ifdef RV_THIN_LOADER
#define RV_REDSEA_VIRTIO_BOOT 1
#endif
#ifdef RV_PHASE3
#define RV_REDSEA_VIRTIO_BOOT 1
#endif
#ifdef RV_REDSEA_VIRTIO_BOOT
  // G9: prefer virtio-blk RedSea image (ships Compiler.BIN + Kernel.BIN) over blank RAM.
  // phase3 / thin-loader smokes attach build/*_redsea.img; no virtio → RAM fallback.
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
#ifdef RV_THIN_LOADER
  // G9: mount + Load RedSea Kernel.BIN + Call KernelEntry — no Cmp/StartOS.
  RVThinLoader;
  Print("RVKMain: thin loader smoke complete; skipping Boot/Spin task wait.\n");
  return;
#endif
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
}
