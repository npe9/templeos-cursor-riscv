// man_topics.hc -- Man("Topic") pages for symbols / hardware (not HTT_FUN).
// Loaded into memfs with other seeds; Man/DocFileFor scan `// Name --` anchors
// case-insensitively. Edit this file, then Man("CLINT") again (no Run needed).
//
// Topics: MemMap, CLINT, MEM_*, PLIC, UART, MTIE, MIE, SiFive, Virtio*, ErrGo, CSR, Reset…
// MemMap -- MemMap (region ↔ driver)
// NAME
//   MemMap - memory / MMIO map with HolyC driver column
// SYNOPSIS
//   MemMap;  MemMapDrv;  MemMapDrvFind("uart");  MemMapFind("clint");
// DESCRIPTION
//   Prints where RAM, heap, UART, timer (CLINT), interrupt controller (PLIC), and
//   other devices live on this board profile. The last column names the HolyC driver
//   that owns that window. Use MemMap when something "should be at address X" and you
//   want the board's answer — not a host emulator monitor. Soft arenas (FS/heap) point
//   at seed files; SiFive boards retarget UART/CLINT/PLIC via RVSifivePlat.
// EXAMPLES
//   MemMap;
//   Print("%X\n", MEM_UART);
//   Print("%s\n", MemMapDrvFind("uart"));
// SEE ALSO
//   MemMapDrv  MemMapDrvFind  MemMapFind  CLINT  PLIC  UART  RegHelp  SiFive
// BUGS
//   REPL MemMap uses host slots for live JIT sizes. Addresses are this profile's MEM_*.
// CLINT -- CLINT (Core-Local Interruptor)
// NAME
//   CLINT - Core-Local Interruptor (machine timer + soft IRQ)
// SYNOPSIS
//   Man("CLINT");  Man("Clint");  Man("clint");
// DESCRIPTION
//   CLINT is the on-chip timer block every hart sees. Think "alarm clock for the CPU":
//   free-running mtime counts up; mtimecmp is the wake-up time. When mtime catches up,
//   a timer interrupt can fire if you enabled it. This port maps CLINT at MEM_CLINT:
//     mtime     @ MEM_MTIME     (= MEM_CLINT+MEM_CLINT_MTIME_OFF)
//     mtimecmp  @ MEM_MTIMECMP  (= MEM_CLINT+MEM_CLINT_MTIMECMP_OFF, hart0)
//   mtime is read-only wall ticks; write mtimecmp to set the next alarm. After the IRQ,
//   re-arm mtimecmp or it stays pending and the CPU livelocks. Also need mie.MTIE and
//   mstatus.MIE (TrapInit). Soft IRQ (msip @ MEM_CLINT+0) is separate from TimerArm.
// EXAMPLES
//   // MMIO — read the free-running counter, then poke the alarm
//   Print("%X\n", *(I64 *)MEM_MTIME);
//   *(I64 *)MEM_MTIMECMP=*(I64 *)MEM_MTIME+1000000;  // wake when mtime catches up
//   // High-level — SetTrap → TrapInit → TimerArm → idle
//   SetTrap("OnTick");
//   TrapInit();
//   TimerArm(1000000);   // ~0.1 s at ~10 MHz mtime on this board's timebase
//   asm { wfi }
// SEE ALSO
//   TimerArm  TrapInit  SetTrap  OnTick  MEM_CLINT  MEM_MTIME  MEM_MTIMECMP  MTIE  MIE
//   PLIC (MEM_PLIC_CLAIM_OFF)  UART (UART_LSR_THRE)  VirtioNet (VIRTIO_MAGIC)
// BUGS
//   Soft IRQ (msip) is not wrapped by TimerArm. Do not call TrapInit at file-load during boot.
// MEM_CLINT -- MEM_CLINT
// NAME
//   MEM_CLINT - base address of the CLINT MMIO window
// SYNOPSIS
//   #define MEM_CLINT 0x02000000   // csr.hc (this board profile)
//   MemMapFind("clint");
// DESCRIPTION
//   Start of the timer/soft-IRQ device window. Timer registers used here:
//     MEM_MTIME    = MEM_CLINT + MEM_CLINT_MTIME_OFF
//     MEM_MTIMECMP = MEM_CLINT + MEM_CLINT_MTIMECMP_OFF  (hart0)
// EXAMPLES
//   Print("%X\n", MEM_CLINT);
//   Print("%X\n", *(I64 *)(MEM_CLINT+MEM_CLINT_MTIME_OFF));  // same as MEM_MTIME
//   Man("CLINT");
// SEE ALSO
//   CLINT  MEM_MTIME  MEM_MTIMECMP  TimerArm  MemMapFind
// BUGS
//   #define only — not a callable function.
// MEM_MTIME -- MEM_MTIME
// NAME
//   MEM_MTIME - CLINT mtime register address
// SYNOPSIS
//   #define MEM_MTIME 0x0200BFF8
//   I64 t=*(I64 *)MEM_MTIME;
// DESCRIPTION
//   Free-running machine timer counter (ticks forever). Read with a 64-bit load.
//   TimerArm reads this, then sets mtimecmp = mtime + interval. Typical board timebase
//   ~10 MHz (CONFIG_TIMEBASE_FREQ).
// EXAMPLES
//   // MMIO
//   Print("%X\n", *(I64 *)MEM_MTIME);
//   Man("CLINT");
// SEE ALSO
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
//   Compare / alarm register for hart 0. Write an absolute tick value; when
//   mtime >= mtimecmp the timer pending bit rises. With mie.MTIE and mstatus.MIE your
//   SetTrap handler runs. Re-arm inside the handler (OnTick) or you will spin.
// EXAMPLES
//   // MMIO — absolute alarm = now + interval
//   *(I64 *)MEM_MTIMECMP=*(I64 *)MEM_MTIME+1000000;
//   // High-level
//   Man("TimerArm");
// SEE ALSO
//   CLINT  MEM_MTIME  TimerArm  OnTick  MTIE
// BUGS
//   Topic-only. Only hart0 compare is used by TimerArm.
// PLIC -- PLIC (Platform-Level Interrupt Controller)
// NAME
//   PLIC - Platform-Level Interrupt Controller (external IRQs)
// SYNOPSIS
//   Man("PLIC");  MemMapFind("plic");
// DESCRIPTION
//   PLIC routes device interrupts (UART, virtio disk/net, …) to CPUs. CLINT is the
//   local timer/soft path; PLIC is the shared "which device woke me?" path. Base is
//   MEM_PLIC. This port's RVPlicHw (and SiFive twin) programs M-mode context 0:
//     priority[irq] @ MEM_PLIC+irq*4
//     pending bits  @ MEM_PLIC+MEM_PLIC_PENDING_OFF   (read)
//     enable bit    @ MEM_PLIC+MEM_PLIC_ENABLE_OFF    (OR 1<<irq)
//     threshold     @ MEM_PLIC+MEM_PLIC_THRESHOLD_OFF (0 = accept prio>0)
//     claim/complete@ MEM_PLIC+MEM_PLIC_CLAIM_OFF     (read=claim, write=done)
//   Virt UART IRQ is typically 10 (CONFIG_UART_IRQ). Also enable mie.MEIE + mstatus.MIE.
// EXAMPLES
//   // MMIO — enable UART IRQ 10 (matches RVPlicHw)
//   *(U32 *)(MEM_PLIC+10*4)=1;
//   *(U32 *)(MEM_PLIC+MEM_PLIC_ENABLE_OFF)=*(U32 *)(MEM_PLIC+MEM_PLIC_ENABLE_OFF)|(1<<10);
//   *(U32 *)(MEM_PLIC+MEM_PLIC_THRESHOLD_OFF)=0;
//   Print("%X\n", *(U32 *)(MEM_PLIC+MEM_PLIC_PENDING_OFF));  // pending word 0
//   I64 irq=*(U32 *)(MEM_PLIC+MEM_PLIC_CLAIM_OFF);  // claim
//   *(U32 *)(MEM_PLIC+MEM_PLIC_CLAIM_OFF)=irq;       // complete
//   // High-level (Kernel/Drv): RVPlicEnable(10,1); RVPlicClaim; RVPlicComplete(irq);
// SEE ALSO
//   MEM_PLIC  UART  CLINT  TrapInit  SetTrap  VirtioNet  SiFive
// BUGS
//   REPL host already claims UART for Ctrl-C; casual claim loops can steal that IRQ.
// MEM_PLIC -- MEM_PLIC
// NAME
//   MEM_PLIC - PLIC MMIO base
// SYNOPSIS
//   #define MEM_PLIC 0x0C000000
// DESCRIPTION
//   Base of the Platform-Level Interrupt Controller window. Offsets: see Man("PLIC")
//   (MEM_PLIC_ENABLE_OFF / THRESHOLD_OFF / CLAIM_OFF / PENDING_OFF in csr.hc).
// EXAMPLES
//   Print("%X\n", MEM_PLIC);
//   Print("%X\n", *(U32 *)(MEM_PLIC+MEM_PLIC_CLAIM_OFF));  // claim (0 = none)
//   Man("PLIC");
// SEE ALSO
//   PLIC  MEM_CLINT  MemMapFind
// BUGS
//   Topic-only (#define in csr.hc).
// UART -- UART (NS16550A)
// NAME
//   UART - 16550 serial MMIO (TX/RX console)
// SYNOPSIS
//   Man("UART");  Man("Uart");  Print("%X\n", MEM_UART);
// DESCRIPTION
//   On virt-style boards the console is an NS16550A at MEM_UART. Byte registers:
//     THR/RBR @ MEM_UART+0     (write=TX, read=RX)
//     LSR     @ MEM_UART+UART_LSR_OFF  (line status)
//   Before writing a character, wait until LSR bit UART_LSR_THRE (0x20) is set — that
//   means the Transmit Holding Register is empty. Bit UART_LSR_DR (0x01) means RX data
//   ready. Seed PutCh/Print already do this; SiFive boards use a different UART layout
//   (Man("SiFive")). IRQ path goes through the PLIC (CONFIG_UART_IRQ, often 10).
// EXAMPLES
//   // MMIO — wait THRE then poke THR (same as UartPut)
//   while (!(*(U8 *)(MEM_UART+UART_LSR_OFF) & UART_LSR_THRE))
//     ;
//   *(U8 *)MEM_UART='!';
//   Print("%X\n", *(U8 *)(MEM_UART+UART_LSR_OFF));  // peek LSR
//   // High-level
//   PutCh('!');  Print("hi\n");
// SEE ALSO
//   PutCh  Print  MEM_UART  PLIC  SiFive  MemMapFind
// BUGS
//   Poking THR without waiting THRE can drop characters. Do not reprogram baud in REPL.
// MTIE -- MTIE (mie bit 7)
// NAME
//   MTIE - Machine Timer Interrupt Enable (CSR mie bit 7)
// SYNOPSIS
//   GetMie;  CSRGet(CSR_MIE);
// DESCRIPTION
//   Bit 7 of the mie CSR. Cleared: timer pending bits do not trap. TimerArm sets MTIE
//   after programming mtimecmp. You also need global MIE in mstatus (TrapInit).
// EXAMPLES
//   Print("%X\n", GetMie());
//   Man("CLINT");
// SEE ALSO
//   MIE  TimerArm  TrapInit  CLINT  CSR_MIE  GetMie
// BUGS
//   Topic name only — not a callable. Value is (1<<7)==128.
// MIE -- MIE (mstatus bit 3)
// NAME
//   MIE - global Machine Interrupt Enable (CSR mstatus bit 3)
// SYNOPSIS
//   TrapInit();  GetMStatus; Reg("mstatus");
// DESCRIPTION
//   Master "allow interrupts" bit in mstatus. TrapInit turns it on. Distinct from the
//   mie CSR (per-cause enables) and from mie.MTIE (timer enable alone).
// EXAMPLES
//   Print("%X\n", GetMStatus());
//   Reg("mstatus");
// SEE ALSO
//   MTIE  TrapInit  CLINT  CSR_MSTATUS  GetMStatus  RegHelp
// BUGS
//   Topic name only — not a callable. Value is (1<<3)==8.
// CSR -- CSR (control/status registers)
// NAME
//   CSR - RISC-V CSR named Get/Set and CSR_* constants
// SYNOPSIS
//   Man("CSR");  GetMStatus;  GetMedeleg;  GetSStatus;  GetMCycle;
//   CSRGet(CSR_MSTATUS);  Reg("mcycle");  RegHelp;
// DESCRIPTION
//   HolyC seed csr.hc exposes M-mode trap/timer CSRs plus delegation
//   (medeleg/mideleg/mcounteren), counters (mcycle/minstret and cycle/instret),
//   and S-mode mirrors (sstatus/sie/stvec/sepc/scause/stval/sip) even while the
//   REPL stays M-mode. Dig-down: Reg("name"); Man("Regs").
// EXAMPLES
//   Regs;
//   Reg("mstatus");
//   Print("%X\n", GetMCycle());
//   Print("%X\n", CSRGet(CSR_MEDELEG));
// SEE ALSO
//   Regs  Reg  RegHelp  CSRGet  CSRSet  GetMStatus  AsmRV  MIE  MTIE
// BUGS
//   Unknown CSRGet numbers return 0 (no illegal-instruction probe).
// AsmRV -- AsmRV (asm{} mnemonics)
// NAME
//   AsmRV - host/guest asm{} mnemonic surface (RV64IM + A subset)
// SYNOPSIS
//   Man("AsmRV");
//   asm { lui t0,1  auipc t1,0  lrd t0,(a0)  amoswapd t0,t1,(a0)  csrrwi a0,0x300,8 }
// DESCRIPTION
//   Host TryAssembleRiscV and guest Compiler/Asm_RV.HC assemble RV64IM core,
//   CSR forms (incl. csrrwi/csrsi), lui/auipc, and A-ext LR/SC + AMO (dotted
//   lr.d / undotted lrd). No V/RVC emit; D subset remains host-heavy.
// EXAMPLES
//   asm { lui a0,1  csrrwi t0,0x300,0  ret }
// SEE ALSO
//   CSR  VirtioNet  Asm  AsmDoc
// BUGS
//   Guest Asm_RV is thinner than host for branches/F64 in places.
// Asm -- Asm (asm{} docs + Tab completion)
// NAME
//   Asm - structured asm{} instruction catalog and Tab completion
// SYNOPSIS
//   Man("Asm");
//   AsmDoc("addi");  AsmList();  AsmDocHelp();
// DESCRIPTION
//   seed/asm_doc.hc holds per-mnemonic templates, encodings, immediate ranges,
//   GNU gas expansions (pseudos), and notes. seed/asm_complete.hc drives Tab
//   completion inside asm { }: mnemonics, GPR/FPR ABI names, CSR names; operand-
//   aware (imm/label positions suppress completion). Tab lists show templates.
//   REPL readline mirrors completion in C (worry_dream_repl.c rl_asm_*).
// EXAMPLES
//   asm { addi a0, a1, 42 };  Reg("a0");
//   AsmDoc("mv");   AsmDoc("li");
//   // In Vi/Ed inside asm{}: Tab on "ad" → add/addi list with templates
// SEE ALSO
//   AsmRV  AsmDoc  AsmList  Disasm  gnu_diff.jsonl
// BUGS
//   Label completion is manual (no symbol table for asm labels yet).
// SiFive -- SiFive (platform interface)
// NAME
//   SiFive - HolyC platform facade for sifive_u / sifive_e boards
// SYNOPSIS
//   Man("SiFive");  Man("sifive");
// DESCRIPTION
//   Named board API for SiFive UART0, CLINT, PLIC, and reset/halt/fault. On
//   PLATFORM_SIFIVE_U / _E the Kernel pulls RVSifiveYes; other machines get stubs
//   (Present=FALSE). Soft REPL Reset; only re-enters Boot — use HardReset or
//   RVSifiveReset for hardware-ish reset paths. MemMap driver column: "RVSifivePlat".
//   UART0 is word MMIO (not 16550): TXDATA@+0, RXDATA@+4, TXCTRL@+8, RXCTRL@+12.
//   TXDATA bit31=full (wait clear before write). Reset: test finisher, AON WDT, or
//   GPIO active-low (OUTPUT_EN then clear PORT bit) — see RVSifivePlat.HH.
// EXAMPLES
//   // MMIO — SiFive UART0 TX (CONFIG_UART_BASE; Kernel boards only)
//   // while (*(U32 *)uart & 0x80000000) ;  *(U32 *)uart='A';
//   // *(U32 *)(uart+8)=1;  *(U32 *)(uart+12)=1;  // TXCTRL / RXCTRL enable
//   // GPIO reset poke (sifive_u): OUTPUT_EN |= bit; PORT &= ~bit;
//   MemMap;           // look for RVSifivePlat in the driver column
//   Man("UART");      // virt 16550 contrast
//   Man("CLINT");
// SEE ALSO
//   MemMap  CLINT  PLIC  UART  Reset  Halt  Fault
// BUGS
//   Live RVSifive* symbols are in Kernel/Drv, not the default REPL seed.
// VirtioNet -- VirtioNet (virtio-mmio network)
// NAME
//   VirtioNet - HolyC virtio-mmio net driver (DeviceID 1)
// SYNOPSIS
//   Man("VirtioNet");  VirtioNetInit;  VirtioNetTxProbe;  VirtioNetRxDrain(8);
// DESCRIPTION
//   Kernel/Drv/VirtioNet.HC: legacy virtio-mmio net. Scans Kconfig virtio-mmio
//   slots (MEM_VIRTIO..), brings up RX/TX queues, TX/RX ethernet frames (10-byte
//   virtio_net_hdr + payload). Polled RX: VirtioNetRx / VirtioNetRxDrain +
//   VirtioNetSetRxCb. PLIC helpers: VirtioNetIrqInit / IrqAck / IrqService
//   (trap-vector MEIE wire-up still deferred). Smoke: make kernel-virtio-net-smoke
//   (UART: virtio-net: tx_ok + rx_ok via RxSelfTest). Enable: CONFIG_HAS_VIRTIO_NET.
// EXAMPLES
//   // MMIO — identity (read-only safe); DeviceID 1 = net
//   Print("%X\n", *(U32 *)(MEM_VIRTIO+VIRTIO_REG_MAGIC));     // expect VIRTIO_MAGIC
//   Print("%X\n", *(U32 *)(MEM_VIRTIO+VIRTIO_REG_VERSION));   // 1 = legacy
//   Print("%X\n", *(U32 *)(MEM_VIRTIO+VIRTIO_REG_DEVICE_ID)); // 1=net 2=blk 18=input
//   // One prep write (GuestPageSize) — do not Status=0 mid-flight (resets device)
//   *(U32 *)(MEM_VIRTIO+VIRTIO_REG_GUEST_PGSZ)=4096;
//   // High-level (Kernel/Drv)
//   // VirtioNetInit;  VirtioNetSetRxCb(&MyRx);  VirtioNetRxSelfTest;
// SEE ALSO
//   VirtioInput  VirtioBlk  MemMap  DskVirtioRV  RVVirtioPlat
// BUGS
//   Callable VirtioNet* live under Kernel/Drv (not the default REPL seed).
//   VirtioNetIrqInit enables PLIC — needs RVTrapInit+MEIE or the guest may hang.
// NAME
//   VirtioInput - HolyC virtio-mmio input (keyboard/mouse) driver
// SYNOPSIS
//   Man("VirtioInput");  VirtioInputInit;  VirtioInputPoll(8);
// DESCRIPTION
//   Kernel/Drv/VirtioInput.HC: DeviceID 18 event queue. Poll prints EV_KEY /
//   EV_REL / EV_ABS / EV_SYN to UART. Smoke: make kernel-virtio-input-smoke
//   (UART: virtio-input: ready). Attach virtio-keyboard-device on virtio-mmio.
// EXAMPLES
//   // MMIO — scan slots for DeviceID 18 (same Magic/Version as net/blk)
//   Print("%X\n", *(U32 *)(MEM_VIRTIO+VIRTIO_REG_MAGIC));
//   Print("%X\n", *(U32 *)(MEM_VIRTIO+MEM_VIRTIO_STRIDE+VIRTIO_REG_DEVICE_ID));
//   *(U32 *)(MEM_VIRTIO+VIRTIO_REG_GUEST_PGSZ)=4096;  // prep write only
//   // High-level
//   // VirtioInputInit;  VirtioInputPoll(8);
// SEE ALSO
//   VirtioNet  VirtioBlk  MemMap  RVVirtioPlat
// BUGS
//   Callable VirtioInput* live under Kernel/Drv; smoke does not inject keys.
// VirtioBlk -- VirtioBlk (virtio-mmio block)
// NAME
//   VirtioBlk - legacy virtio-mmio block (DeviceID 2)
// SYNOPSIS
//   Man("VirtioBlk");  VirtioBlkInit;  // DskVirtioRV.HC
// DESCRIPTION
//   Kernel/BlkDev/DskVirtioRV.HC drives virtio-blk over the same MMIO slots as net
//   /input. MagicValue VIRTIO_MAGIC, Version 1 (legacy), DeviceID 2. Queue setup
//   uses QueueSel/Num/Align/PFN then Status DRIVER_OK — full init is in VirtioBlkInit.
// EXAMPLES
//   // MMIO — find blk by DeviceID (scan MEM_VIRTIO + n*MEM_VIRTIO_STRIDE)
//   Print("%X\n", *(U32 *)(MEM_VIRTIO+VIRTIO_REG_MAGIC));
//   Print("%X\n", *(U32 *)(MEM_VIRTIO+VIRTIO_REG_DEVICE_ID));  // 2 when blk is slot0
//   *(U32 *)(MEM_VIRTIO+VIRTIO_REG_GUEST_PGSZ)=4096;
//   // High-level
//   // VirtioBlkInit;  // then VirtioBlkReq / disk APIs
// SEE ALSO
//   VirtioNet  VirtioInput  MemMap  DskVirtioRV
// BUGS
//   Do not write Status=0 or QueueNotify from the REPL unless you own the device.
// SMP -- SMP (topic)
// NAME
//   SMP - multi-hart master/Seth bring-up (Phase G)
// SYNOPSIS
//   RVHartId;  RVSmpAlive;  RVSmpWake(&Fn,arg);  RVSmpWait;  RVAmoAddI64(&x,1);
//   lock x++;   LXchgI64(&x,v);   LBts(bits,n);
// DESCRIPTION
//   TempleOS-shaped multicore: hart 0 is master (UART REPL / OS). Secondaries park
//   on per-hart stacks (crt0_smp / startup.s) then run one mailbox job — not N REPLs.
//   QEMU virt: -smp N -bios none. Mailbox @ 0x87001E00. CLINT MSIP wakes WFI when
//   mie.MSIE is set; the smoke path also busy-polls the mailbox.
//   Atomics: LXchgI64=amoswap.d, LBts/LBtr/LBtc=LR/SC, lock=amoswap spin @ 0x87001F00.
//   Optional smoke: make kernel-smp-smoke. OpenSBI HSM is for firmware-hosted boards.
// EXAMPLES
//   Man("SMP");
//   Man("RVSmpWake");
// SEE ALSO
//   RVHartId  RVSmpWake  LXchgI64  LBts  lock  CLINT
// BUGS
//   Single mailbox only — full Seth JobQue / mp_cnt finalize still TODO.
// LXchgI64 -- LXchgI64 (topic)
// NAME
//   LXchgI64 - atomic exchange (amoswap.d)
// SYNOPSIS
//   I64 LXchgI64(I64 *dst,I64 v);
// DESCRIPTION
//   Swaps *dst with v and returns the old value using the A extension. Locked bit
//   ops: LBts/LBtr/LBtc (LR.W/SC.W). HolyC lock stmt uses a separate amoswap spin.
// EXAMPLES
//   I64 o=LXchgI64(&x,1);
// SEE ALSO
//   LBts  RVAmoAddI64  lock  SMP
// lock -- lock (topic)
// NAME
//   lock - atomic statement prefix (amoswap spin)
// SYNOPSIS
//   lock x++;
//   lock { shared+=n; }
// DESCRIPTION
//   Emits IC_LOCK_ENTER/LEAVE around the next statement or block: spin with
//   amoswap.d on 0x87001F00. Prefer LXchgI64 / LBts / RVAmoAddI64 for single-var RMW.
// SEE ALSO
//   LXchgI64  LBts  SMP  RVCritEnter
// ErrGo -- ErrGo()
// NAME
//   ErrGo - jump to the last compile error site
// SYNOPSIS
//   ErrGo;
// DESCRIPTION
//   After a compile failure that printed file:line:col, ErrGo opens the preferred
//   editor on that location. Handy when a Run("….hc") fails and you want the site
//   without re-typing the path. Reads host err metadata slots; HolyC opens the editor.
// EXAMPLES
//   Run("missing.hc");   // provoke an error, then:
//   ErrGo;
// SEE ALSO
//   Run  Src  Edit  Vi  Ed
// BUGS
//   Prints "ErrGo: no error" if nothing jumpable was recorded yet.
// Reset -- Reset (soft + board)
// NAME
//   Reset - soft Boot re-entry; board HW via RVSifiveReset / HardReset
// SYNOPSIS
//   Reset;  HardReset;  Halt;  Fault;
// DESCRIPTION
//   Soft Reset re-enters Boot (REPL stack clean) — not a chip power cycle. HardReset
//   pokes the MEM_TEST finisher when present. SiFive board HW paths: Man("SiFive").
// EXAMPLES
//   Man("Reset");   // see trap.hc page for the live U0 Reset()
//   Help;
// SEE ALSO
//   SiFive  Halt  Fault  Boot  HardReset
// Halt -- Halt (topic)
// NAME
//   Halt - park CPU in wfi (see trap.hc Halt / RVSifiveHalt)
// SYNOPSIS
//   Halt;
// DESCRIPTION
//   Infinite wait-for-interrupt. With IRQs off this never returns.
// EXAMPLES
//   Man("Halt");    // live function page is in trap.hc
// SEE ALSO
//   Reset  HardReset  SiFive
// Fault -- Fault (topic)
// NAME
//   Fault - deliberate illegal insn for trap testing
// SYNOPSIS
//   SetTrap("OnTrap"); TrapInit; Fault;
// DESCRIPTION
//   Forces an illegal-instruction trap so you can test SetTrap handlers.
// EXAMPLES
//   SetTrap("OnTrap"); TrapInit; Fault;
// SEE ALSO
//   SetTrap  TrapInit  Break  SiFive  pc
// pc -- pc (last trap PC)
// NAME
//   pc - last trap/fault program counter (_RIP analogue)
// SYNOPSIS
//   pc;  U(pc-16);  U(_RIP);
// DESCRIPTION
//   RISC-V stand-in for TempleOS _RIP. Every trap publishes mepc into the HolyC
//   global pc before resume rewrites the CSR. After a fault dump, dig-down with
//   U(pc-16); or U(_RIP);. Assemblable paste: UA(pc-16);. Alias: #define _RIP pc (trap.hc).
// EXAMPLES
//   pc;
//   U(pc-16);
//   UA(pc-16);
//   Man("U");
// SEE ALSO
//   U  UA  Uf  _RIP  Dr  Regs  Fault  GetMepc
// BUGS
//   Not a live sampler of the REPL eval IP — only last trap epc (and boot seed).
// Tutorial -- Tutorial (curriculum)
// NAME
//   Tutorial - Software Foundations–style HolyC labs (ISA / CSAPP / Beck)
// SYNOPSIS
//   Tutorial;  SF;  Run("A01_RV64I.hc");
// DESCRIPTION
//   Executable curriculum: each chapter is a .hc lesson under memfs (from
//   bootstrap/seed/tutorials/). Run the file, complete TODO/Fill_in exercises,
//   Run again. Part A = RISC-V ISA; Part B = CSAPP 3e chapters; Part C = Beck 3e.
// EXAMPLES
//   Tutorial;
//   Run("B02_DataRep.hc");
// SEE ALSO
//   Help  SF  Run  Dir  Man
// BUGS
//   After editing tutorial seeds: make repl-blob && rebuild Makefile.repl.
// Datasheet -- Datasheet (bitfield decode)
// NAME
//   Datasheet - OS-owned register field tables for DsDecode / Bits
// SYNOPSIS
//   Man("Datasheet");
//   DsFind("uart");  DsShow("mstatus");  DsDecode("mstatus");
//   DsDecode("uart.lsr", 0x21);  Bits("mie");
// DESCRIPTION
//   The REPL ships structured datasheets (not a static PDF): CSR fields from the
//   privileged ISA, UART/CLINT/PLIC MMIO fields keyed to MEM_* anchors. Each
//   sheet lists bit ranges and optional enum maps so a raw value becomes hex,
//   decimal, and symbolic names. Engine: ds.hc. Sheets: ds_csr.hc, ds_uart.hc,
//   ds_clint.hc, ds_plic.hc (also under bootstrap/seed/datasheet/). Edit a sheet,
//   Run("ds_uart.hc"); then DsDecode again. Live peek uses CSRGet or an MMIO
//   byte/word load when you omit the value. Format: docs/DATASHEET.md.
// EXAMPLES
//   DsFind("");
//   DsShow("mstatus");
//   DsDecode("mstatus");                    // live CSR
//   DsDecode("uart.lsr", UART_LSR_THRE|UART_LSR_DR);
//   DsFieldGet("uart.lsr", "THRE", 0x21);   // → 1
//   Bits("plic.claim");
// SEE ALSO
//   DsDecode  DsShow  DsFind  Bits  Reg  CSRGet  MemMap  UART  CLINT  PLIC
// BUGS
//   Subset of fields only; extend sheets rather than hardcoding in C.
