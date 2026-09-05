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
//   MemMapDrv  MemMapDrvFind  MemMapFind  CLINT  PLIC  UART  RegHelp  SiFive  Regs
// BUGS
//   REPL MemMap uses host slots for live JIT sizes. Addresses are this profile's MEM_*.
// Regs -- Regs()
// NAME
//   Regs - dump GPRs and M-mode CSRs
// SYNOPSIS
//   Regs;  Dr;
// DESCRIPTION
//   Snapshots general-purpose registers at stub entry into MEM_REGS_SNAP, prints
//   each as xN/abi (e.g. x10/a0) with a one-line role hint, then M-mode CSRs
//   with CsrExplainVal bitfield decode (set fields only). Reg("name") accepts
//   any alias: x10, a0, fp (→s0), REG_SP, case-insensitive. CSR dig-down also
//   via CsrExplain("mstatus") or Bits("mstatus") (datasheet tables).
//   Values are frozen at Regs/Reg stub entry (snap+restore) — not mid-expression.
//   Dig-down: RegHelp; Man("ABI"); Man("Reg"); docs/DEBUGGER.md.
// EXAMPLES
//   Regs;
//   asm { li a0, 42 }; Reg("a0"); Reg("x10");
//   Reg("mstatus");  CsrExplain("mcause");
//   Man("ABI");
// SEE ALSO
//   Reg  RegHelp  ABI  MemMap  StkRep  CLINT  CSR  Debugger
// BUGS
//   FPR names (fa0, ft0) are asm{} / RegHelp only — not Reg() GPR dig-down yet.
// ABI -- ABI (RISC-V calling convention)
// NAME
//   ABI - RISC-V integer register naming and calling convention
// SYNOPSIS
//   Man("ABI");  RegHelp;  Run("A02_RegsABI.hc");
// DESCRIPTION
//   RV64 has 32 GPRs (x0..x31). The psABI gives each a role:
//     x0 / zero — hardwired 0; writes discarded
//     ra (x1)   — return address (jal link)
//     sp (x2)   — stack pointer
//     gp (x3)   — global pointer; tp (x4) — thread pointer
//     t0..t6    — temporaries (caller-saved; clobbered across calls)
//     s0..s11   — saved registers (callee-saved); s0 is also fp (frame pointer)
//     a0..a7    — function arguments and return values
//   Calling convention (integer, this REPL/compiler):
//     • First eight integer args in a0..a7; additional args on the stack.
//     • Return value in a0 (a1 for 128-bit pairs when used).
//     • Callee saves s0..s11 (and must preserve sp); may clobber t* and a*.
//     • ra holds the return address; sp must stay valid across calls.
//   Reg("name") resolves xN, ABI names, fp→s0, and REG_* constants. Regs prints
//   xN/abi pairs. Tutorial lab: Run("A02_RegsABI.hc") under /Tutorials.
// EXAMPLES
//   Man("ABI");
//   asm { li a0, 1; li a1, 2; add a0, a0, a1 }; Reg("a0");
//   Reg("fp"); Reg("x08");
// SEE ALSO
//   Reg  Regs  RegHelp  A02_RegsABI  Asm  Debugger  CSR
// BUGS
//   Float ABI (fa0..fa7, fs*) is for asm{} only here — no Reg("fa0") yet.
// Reg -- Reg(name)
// NAME
//   Reg - read one GPR or named CSR by symbolic name
// SYNOPSIS
//   I64 Reg(U8 *name);
// DESCRIPTION
//   Snap+restore one register (same stub entry as Regs). Accepts:
//     • Numeric: x0..x31 (case-insensitive x10 / X10)
//     • ABI: zero, ra, sp, gp, tp, t0..t6, s0..s11, a0..a7
//     • Synonyms: fp → s0 (x08); REG_SP, REG_A0, … (REG_ prefix optional)
//   Prints xN/abi = value plus a short role line. CSRs: mstatus, mepc, mcause,
//   mie, mip, mtvec, mtval, mscratch, misa, satp, mhartid, mtime (MMIO).
//   CSR names auto-decode set bitfields (MIE, MPP, MEIE, mcause code names, …).
//   CsrExplain("mstatus"); and Bits("mie"); use the same field tables.
//   Returns the value (or -1 on unknown name). Use on the same eval line as
//   asm{} before the REPL clobbers caller-saved regs.
// EXAMPLES
//   asm { li a7, 20; addi a7, a7, -4 }; Reg("a7");
//   Reg("x10");   // same GPR as Reg("a0")
//   Reg("sp"); Reg("mstatus");
//   CsrExplain("mcause");  Bits("mie");
//   Man("ABI"); RegHelp;
// SEE ALSO
//   Regs  Reg  RegHelp  ABI  Bits  CsrExplain  GetMStatus  Debugger
// BUGS
//   Stub-entry snap only — not live mid-prologue. Same-line asm{…}; Reg required.
// a0 -- a0 (x10, first argument / return)
// NAME
//   a0 - first integer argument and primary return register
// SYNOPSIS
//   Reg("a0");  Reg("x10");
// DESCRIPTION
//   a0 is x10 in the numeric encoding. HolyC passes the first integer argument
//   in a0 and returns scalar results in a0 (TempleOS / RISC-V psABI). Caller-saved:
//   callees may overwrite it unless they are leaf functions you control. After
//   asm { … }; on the same REPL line, Reg("a0") shows what your snippet left there.
// EXAMPLES
//   asm { li a0, 99 }; Reg("a0");
//   I64 Echo(I64 x) { return x; } Echo(42);  // result in a0 at machine level
// SEE ALSO
//   ABI  Reg  Regs  A02_RegsABI
// BUGS
//   Topic-only — use Reg("a0") for live dig-down, not Man("a0") as a function.
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
//   REPL stays M-mode. Dig-down: Reg("name"); CsrExplain("mstatus");
//   Bits("mie"); Man("Regs"). CsrDecode* prints set bitfields (MIE/MPP/FS,
//   mcause exception names, mtvec MODE/BASE, …). Datasheet tables: ds_csr.hc.
// EXAMPLES
//   Regs;
//   Reg("mstatus");
//   CsrExplain("mcause");
//   CsrDecodeMstatus(GetMStatus());
//   Print("%X\n", GetMCycle());
//   Print("%X\n", CSRGet(CSR_MEDELEG));
// SEE ALSO
//   Regs  Reg  RegHelp  CSRGet  CSRSet  GetMStatus  CsrExplain  Bits  AsmRV  MIE  MTIE
// BUGS
//   Unknown CSRGet numbers return 0 (no illegal-instruction probe). Hypervisor
//   CSRs (hstatus, hedeleg, …) not decoded yet.
// mstatus -- mstatus (machine status CSR)
// NAME
//   mstatus - machine status register (CSR 0x300)
// SYNOPSIS
//   Reg("mstatus");  GetMStatus;  CsrExplain("mstatus");  Bits("mstatus");
// DESCRIPTION
//   Global interrupt enables (UIE/SIE/MIE), prior IE bits (UPIE/SPIE/MPIE),
//   prior privilege (MPP/SPP), FP/vector/extension dirty state (FS/VS/XS),
//   VM helpers (MPRV/SUM/MXR/TVM/TW/TSR), and XLEN fields (UXL/SXL/SD).
//   Reg and Regs auto-decode set fields via CsrDecodeMstatus. TrapInit sets MIE.
// EXAMPLES
//   Reg("mstatus");
//   CsrDecodeMstatus(0x8000000A00006088);
// SEE ALSO
//   MIE  MTIE  CSR  Reg  Bits  Man("CSR")
// BUGS
//   Topic-only — use Reg/GetMStatus for live values.
// mcause -- mcause (trap cause CSR)
// NAME
//   mcause - trap cause register (CSR 0x342)
// SYNOPSIS
//   Reg("mcause");  GetMcause;  CsrExplain("mcause");
// DESCRIPTION
//   Bit 63: interrupt (1) vs exception (0). Low bits: cause code. CsrDecodeMcause
//   names common codes (breakpoint=3, ecall U/S/M=8/9/11, load fault=5, MEI=11, …).
//   Pair with mepc (return PC) and mtval (faulting addr or insn bits).
// EXAMPLES
//   Reg("mcause");
//   CsrDecodeMcause(0x800000000000000B);  // MEI
// SEE ALSO
//   mepc  mtval  TrapDump  CSR  Reg
// BUGS
//   Custom platform interrupt codes may show as numeric only.
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
//   (IrqInit sets mie.MEIE; trap ACK via HolyServiceExternal / RVVirtioPciIsrReg
//   for PCI INTx). AIA MSI-X→IMSIC deferred on virt PLIC. Smoke: kernel-virtio-net-smoke
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
// NAME
//   VirtioConsole - HolyC virtio-mmio console (DeviceID 3)
// SYNOPSIS
//   Man("VirtioConsole");  VirtioConsoleInit;  VirtioConsolePuts("hi");
// DESCRIPTION
//   Kernel/Drv/VirtioConsole.HC: port-0 receiveq/transmitq. TX via
//   VirtioConsoleWrite/Puts; RX via VirtioConsoleRead. PLIC helpers match
//   VirtioNet. Smoke: make kernel-virtio-console-smoke (UART: virtio-console: tx_ok).
// SEE ALSO
//   VirtioNet  VirtioInput  MemMap  RVVirtioPlat
// NAME
//   VirtioBalloon - HolyC virtio-mmio balloon (DeviceID 5)
// SYNOPSIS
//   Man("VirtioBalloon");  VirtioBalloonInit;  VirtioBalloonInflate(1);
// DESCRIPTION
//   Kernel/Drv/VirtioBalloon.HC: inflate/deflate PFN lists from a fixed page pool.
//   Smoke: make kernel-virtio-balloon-smoke (UART: virtio-balloon: ok).
// SEE ALSO
//   VirtioConsole  VirtioScsi  MemMap
// NAME
//   VirtioScsi - HolyC virtio-mmio SCSI HBA (DeviceID 8)
// SYNOPSIS
//   Man("VirtioScsi");  VirtioScsiInit;  VirtioScsiInquiry;  VirtioScsiReadLba;
// DESCRIPTION
//   Kernel/Drv/VirtioScsi.HC: control/event/request queues; INQUIRY + READ(10).
//   Smoke: make kernel-virtio-scsi-smoke (UART: virtio-scsi: ok).
// SEE ALSO
//   VirtioBlk  DskVirtioRV  MemMap
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
//   mie.MSIE is set (crt0_smp enables it on secondaries).
//   Atomics: LXchgI64=amoswap.d, LBts/LBtr/LBtc=LR/SC, lock=amoswap spin @ 0x87001F00.
//   Optional smoke: make kernel-smp-smoke. OpenSBI HSM is for firmware-hosted boards.
// EXAMPLES
//   Man("SMP");
//   Man("RVSmpWake");
// SEE ALSO
//   RVHartId  RVSmpWake  RVSmpWakeHart  RVSmpMpCnt  LXchgI64  LBts  lock  CLINT
// BUGS
//   Single mailbox only — full Seth JobQue / TempleOS mp_cnt finalize still TODO.
// GoldfishRTC -- GoldfishRTC (topic)
// NAME
//   GoldfishRTC - QEMU virt wall-clock RTC
// SYNOPSIS
//   RVRtcReadNs;  RVRtcPresent;  Now;
// DESCRIPTION
//   Goldfish RTC @ CONFIG_RTC_BASE (virt 0x101000). TIME_LOW latches TIME_HIGH.
//   KDate NowDateTimeStruct uses RVRtc when CONFIG_HAS_GOLDFISH_RTC.
//   Smoke: make kernel-rtc-smoke.
// SEE ALSO
//   Now  NowDateTimeStruct  MemMap  fw_cfg
// fw_cfg -- fw_cfg (topic)
// NAME
//   fw_cfg - QEMU firmware config DMA
// SYNOPSIS
//   RVFwCfgSigOk;  RVFwCfgFind("etc/ramfb");  RVFwCfgFileCount;
// DESCRIPTION
//   MMIO @ CONFIG_FW_CFG_BASE. DMA descriptor + file-dir Find/Read/Write.
//   ramfb present uses Find+WriteSel. Smoke: make kernel-fwcfg-smoke.
// SEE ALSO
//   RVFb  MemMap  GoldfishRTC
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
// SafeMode -- SafeMode (ops recovery)
// NAME
//   SafeMode - UART operate-through: FsCheckpoint + export/reset recipe
// SYNOPSIS
//   SafeMode;
// DESCRIPTION
//   Live U0 SafeMode() is in ops.hc (full UART REPL boot blob). Pins a
//   "safemode" epoch when the memfs journal is ready. No WinMgr. Export with
//   FsChanges / DumpChanges before Reset. Soft reseed: Man("Recover").
// EXAMPLES
//   Man("SafeMode");
//   SafeMode;
// SEE ALSO
//   Recover  FsRecover  FsReplay  Reset  FsChanges  FsCheckpoint  DumpChanges
// BUGS
//   Topic mirrors ops.hc; prefer Man("SafeMode") after Run of boot blob.
// Recover -- Recover (soft reseal)
// NAME
//   Recover - drop non-snap session files and FsEpochSealNamed(RECOVER)
// SYNOPSIS
//   Recover;
// DESCRIPTION
//   MEMFS_LOG P6. ops.hc Recover calls FsRecover: drops slots not in the snap
//   table, reseals a bumped epoch labeled RECOVER. FsReplay verifies journal
//   vs tree (no body rewrite). Mutated snap seeds stay until power-cycle.
// EXAMPLES
//   DumpChanges;
//   FsReplay;
//   Recover;
// SEE ALSO
//   FsRecover  FsReplay  SafeMode  Reset  FsSnap  FsEpochSealNamed
// BUGS
//   No host-blob reinstall of pristine seed bytes — honest soft recover only.
// FsReplay -- FsReplay (journal verify)
// NAME
//   FsReplay - check memfs against the change journal since an epoch
// SYNOPSIS
//   FsReplay;  FsReplay(0);
// DESCRIPTION
//   Walks journal records and reports OK / MISS / DRIFT. Does not rewrite
//   file bodies (log has metadata only). See fs.hc / MEMFS_LOG P6.
// EXAMPLES
//   FileWrite("Home/t.hc", "x", 1);
//   FsReplay;
// SEE ALSO
//   FsRecover  Recover  FsLog  FsChanges
// BUGS
//   WRAP means history was compacted — remaining ring only.
// Reset -- Reset (soft + board)
// NAME
//   Reset - soft Boot re-entry; board HW via RVSifiveReset / HardReset
// SYNOPSIS
//   Reset;  HardReset;  Halt;  Fault;
// DESCRIPTION
//   Soft Reset re-enters Boot (REPL stack clean) — not a chip power cycle. HardReset
//   pokes the MEM_TEST finisher RESET (0x7777). Quit/Exit/PowerOff write PASS (0x5555)
//   to end QEMU; Fail writes FAIL. SiFive board HW paths: Man("SiFive").
//   Operate-through: Man("SafeMode"); Man("Recover"); docs/OPS.md.
// EXAMPLES
//   Man("Reset");   // see trap.hc page for the live U0 Reset()
//   Quit;           // leave QEMU (SiFive test PASS)
//   Help;
// SEE ALSO
//   SafeMode  Recover  SiFive  Halt  Fault  Boot  HardReset  Quit  Exit  Fail
// Quit -- Quit (topic)
// NAME
//   Quit - end QEMU via SiFive test PASS @ MEM_TEST
// SYNOPSIS
//   Quit;  Exit;  PowerOff;  Fail;  HardReset;
// DESCRIPTION
//   On QEMU -M virt, MEM_TEST is sifive_test @ 0x100000. Quit writes 0x5555 (PASS /
//   host exit 0). Fail writes 0x10003333. HardReset writes 0x7777 (guest reset).
//   Soft Reset; only re-enters Boot — use Quit to leave the emulator session.
// EXAMPLES
//   Quit;
// SEE ALSO
//   Exit  Fail  HardReset  Reset  Halt  MEM_TEST  SiFive
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
// Debugger -- Debugger (topic)
// NAME
//   Debugger - UART REPL dig-down (Regs Bt Bp Watch Step TrapDump CrashMon)
// SYNOPSIS
//   Man("Debugger");
//   DbgHelp;  Regs;  Bt;  Bp(&Fn);  Watch(&x);  Step;  TrapDump;
//   CrashHelp;  Fault;  // crash> md/mw/regs/bt/go
//   HwTrigProbe;  HwHelp;  // hardware triggers / host gdb twin
// DESCRIPTION
//   In-guest debugger for the HolyC UART REPL. Regs/Reg snap+restore GPRs
//   (MEM_REGS_SNAP). Bp patches ebreak; DbgTrap dumps and continues (BpStop
//   aborts to prompt). Bt walks FP frames (trap freeze or live). Watch is a
//   soft compare; HwWatch/HwBreak use Sdtrig mcontrol when present (hwdbg.hc).
//   Step/StepOver arm one-shot next-insn / ra breakpoints (not dcsr.step).
//   TrapDump prints mcause/mepc/mtval + saved GPRs. Product path default
//   CrashOnTrap dumps + crash> monitor (CONSOLE #9). Full matrix: docs/DEBUGGER.md.
//   Host gdb/OpenOCD: make hwdbg-smoke / docs/BAREMETAL.md.
//   UART GDB RSP: GdbStub; / make gdb-uart-smoke.
// EXAMPLES
//   DbgHelp;
//   I64 Add(I64 a,I64 b){return a+b;} Bp(&Add); Add(11,22);
//   I64 w; Watch(&w); w=3; WatchChk;
//   Fault;  // crash> go
//   HwTrigProbe; HwHelp;
//   GdbHelp;
// SEE ALSO
//   Regs  Bt  Bp  Watch  Step  TrapDump  CrashMon  DbgHelp  HwDbg  GdbStub  StkRep  RegHelp
// BUGS
//   No interactive Dbg shell; dcsr.step is Debug-mode only (use host gdb stepi).
// CrashMon -- CrashMon (topic)
// NAME
//   CrashMon - post-fault UART monitor (md/mw/regs/bt/reboot)
// SYNOPSIS
//   Man("CrashMon");  CrashHelp;  Fault;  CrashDump;  CrashMon;
// DESCRIPTION
//   CONSOLE wishlist #9 on product repl-holyc. Boot SetTrapFn(&CrashOnTrap)
//   (no mtvec); TrapInitOnce on Fault keeps the handler. Sync faults print
//   cause/PC/SP/regs/bt then crash>. Commands: help regs bt pc dump|snap
//   md [ADDR|pc|sp|fp|snap] [N]  da ADDR [N]  mw ADDR VAL
//   go|cont|q reboot|reset hard|hardreset. Seed: bootstrap/seed/crash.hc.
//   FB twin: Kernel RVWinSerial + host RVCrashMon* (same cmd vocabulary while
//   WinMgr runs — BOARD_FB.md). Not the AOT ExePutS REPL.
// EXAMPLES
//   CrashMon;          // crash> md / go
//   Fault;             // needs G2 TrapInitOnce for auto-enter
//   CrashHelp; Man("CrashMon");
// SEE ALSO
//   CrashDump  CrashOnTrap  Md  Mw  TrapDump  Regs  Bt  Reset  Debugger  Fault
// BUGS
//   Auto Fault→crash> blocked while G2 mtvec install is WIP. Nested faults
//   possible if md/mw leave DRAM; no JIT eval inside crash>.
// HwDbg -- HwDbg (topic)
// NAME
//   HwDbg - hardware triggers (Sdtrig) + host gdbstub twin
// SYNOPSIS
//   Man("HwDbg");  HwHelp;  HwTrigProbe;  HwWatch(&x);  HwBreak(&F);
// DESCRIPTION
//   Guest APIs in hwdbg.hc program tselect/tdata1/tdata2 for M-mode store or
//   execute match (action=breakpoint → DbgTrap). Probe with HwTrigProbe (QEMU
//   virt typically tinfo=0x44). Soft Watch/Bp/Step remain in debug.hc. Host:
//   make hwdbg-smoke attaches riscv64-*-gdb to QEMU -S -gdb.
// EXAMPLES
//   HwTrigProbe;
//   I64 w; HwWatch(&w); w=1; HwClr;
// SEE ALSO
//   Debugger  Watch  Bp  Step  HwHelp  GdbStub  docs/DEBUGGER.md
// BUGS
//   dcsr not writable from M-mode; FE310 needs OpenOCD for JTAG attach.
// GdbStub -- GdbStub (topic)
// NAME
//   GdbStub - GDB remote serial protocol over UART
// SYNOPSIS
//   Man("GdbStub");  GdbHelp;  GdbStub;
// DESCRIPTION
//   Cooperative guest RSP stub (gdbstub.hc). Emits $HC_GDB$, speaks ?, g, G, m,
//   M, p, Z0/z0 (soft Bp), soft-step s, c→S05, qSupported (swbreak+), D on raw
//   UART. GdbUseMux ch2 flag (TX still raw). Host: uart_gdb_proxy.py /
//   make gdb-uart-smoke. Soft Regs/Bp unchanged; qemu -gdb is hwdbg-smoke.
// EXAMPLES
//   GdbHelp; GdbStub;
// SEE ALSO
//   GdbHelp  Debugger  HwDbg  Regs  Bp  Step
// BUGS
//   No live resume while attached; soft-step is arm-only; PC is trap mepc or ra.
// Fault -- Fault (topic)
// NAME
//   Fault - deliberate illegal insn for trap testing
// SYNOPSIS
//   Fault;   // product: CrashOnTrap → dump → crash>
//   SetTrap("OnTrap"); TrapInit; Fault;
// DESCRIPTION
//   Forces an illegal-instruction trap so you can test SetTrap handlers.
//   On repl-holyc, default CrashOnTrap dumps + enters CrashMon (type go).
// EXAMPLES
//   Fault;  // crash> go
//   SetTrap("OnTrap"); TrapInit; Fault;
// SEE ALSO
//   CrashMon  CrashOnTrap  SetTrap  TrapInit  Break  SiFive  pc
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
// Sys -- Sys (/proc-ish inspection)
// NAME
//   Sys - UART OS system inspection (uptime / mem / irq / devices / cnts)
// SYNOPSIS
//   Sys;  Uptime; MemRep; IrqRep; DevRep; Cnts;  SysHelp;
// DESCRIPTION
//   /proc-like helpers for the UART console (CONSOLE.md #10). Seed: sys.hc.
//   Sys dumps everything; individuals print one section. No ps/task table yet
//   (single REPL). Timebase ≈ SYS_TIMEBASE (10 MHz virt). Prefer MemMap for
//   address dig-down; DevRep is the compact device inventory.
// EXAMPLES
//   Sys;
//   Uptime; MemRep;
//   Man("Sys");
// SEE ALSO
//   Uptime  MemRep  IrqRep  DevRep  Cnts  CpuRep  MemMap  DMesg  Help
// BUGS
//   No mounts/ps; PLIC claim not read (would claim IRQ).
// Term -- Term (size / type negotiation)
// NAME
//   Term - UART terminal geometry and type (rows/cols/termname)
// SYNOPSIS
//   TermSize(80,24);  TermSetSize(24,80);  TermNameAnsi; TermNameXterm;
//   TermRows; TermCols; TermName; TermRep; TermQuery; TermProbe; TermHelp;
// DESCRIPTION
//   Guest stores COLUMNS×LINES and a TERM-ish name (CONSOLE.md #11). Defaults
//   80×24 / "ansi". HolyC TermSize is cols-first; TermSetSize is rows-first.
//   Optional query: TermQuery / TermProbe (DSR CPR + ESC[18t) needs a real PTY.
//   Host push while TermProbe/editors own RX:
//     ESC [ 8 ; rows ; cols t
//     ESC ] 777 ; cols ; rows ; name BEL
// EXAMPLES
//   TermSize(80,24); TermSetName("xterm"); TermRep;
//   TermQuery;  // or TermProbe;
//   Man("Term"); TermHelp;
// SEE ALSO
//   TermSize  TermSetSize  TermName  TermRep  TermProbe  TermQuery  TermHelp  Help
// BUGS
//   Piped QEMU smoke has no emulator reply — probe times out, defaults stick.
// Vt -- Vt (soft console mux)
// NAME
//   Vt - soft-switch virtual terminals over one UART (tmux-ish stub)
// SYNOPSIS
//   Vt(1);  VtAttach(1);  VtDetach;  VtNext; VtPrev;  VtList;
//   VtPutStr("note");  VtCapture(1);  VtKeys(1);  VtPane(0,1);  VtClear;  VtHelp;
// DESCRIPTION
//   CONSOLE.md #4 / G25. Four soft VTs (VT0=REPL). Switch prints a banner and
//   replays that VT's scrollback. VtAttach aliases Vt; VtDetach returns to VT0.
//   VtCapture(1) dual-writes Print/UartStr into the current VT (PutCh hook;
//   still emits UART). VtKeys(1) enables Ctrl-A then 0-3/n/p/d/l in readline
//   (default off). VtPane(a,b) records host-side split layout (framed P\\ta\\tb
//   when UartMuxOn); no guest ANSI TTY split — use uart_mux.py --vt-panes.
//   With UartMuxOn, also FrameSend(ch0, "V\\tN").
// EXAMPLES
//   Vt(1); VtPutStr("side-session"); VtDetach;
//   VtCapture(1); Print("cap\\n"); VtCapture(0);
//   VtKeys(1);  // then Ctrl-A 1 at the prompt
//   VtPane(0,1); VtPaneOff;
//   Man("Vt");
// SEE ALSO
//   VtAttach  VtDetach  VtCapture  VtKeys  VtPane  VtNext  VtList  UartMuxOn  Help
// BUGS
//   No guest ANSI panes (host --vt-panes only). Capture/keys default off.
//   Print never hidden (serial primacy).
// Tutorial -- Tutorial (curriculum)
// NAME
//   Tutorial - Software Foundations–style HolyC labs (ISA / CSAPP / Beck)
// SYNOPSIS
//   Tutorial;  SF;  Cd("Tutorials"); Run("A01_RV64I.hc");
// DESCRIPTION
//   Executable curriculum: each chapter is a .hc lesson under /Tutorials
//   (bootstrap/seed/tutorials/). Run the file, complete TODO/Fill_in exercises,
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
// Zmodem -- Zmodem (UART file export)
// NAME
//   Zmodem - guest→host memfs export (sz / rz / trzsz --zmodem)
// SYNOPSIS
//   ZmodemSend("boot.hc");
//   ZmodemSendDir("Tutorials");
//   FsChanges;  ZmodemSendChanges;  DumpChanges;
// DESCRIPTION
//   UartPut writes raw bytes to the 16550 THR — no CRLF mangling — so a
//   ZMODEM sender on the guest can talk to host `rz` or this repo's
//   tools/uart_recv_zmodem.py. For native trzsz (no --zmodem), see Trzsz /
//   TrzszSend. Session writes: HolyC FileWrite journals after FsEpochSeal
//   (end of boot); dirty bits still drive ZmodemSendChanges (P3). UART batch:
//   DumpChanges (P2) emits $$HC_CHANGES$$ then DumpFile bodies. Workflow: edit →
//   FsChanges → DumpChanges or ZmodemSendChanges → host file → git diff.
// EXAMPLES
//   FileWrite("Tmp/note.txt", "hi\n", 3);
//   FsChanges;
//   ZmodemSend("Tmp/note.txt");
//   DumpChanges;
// SEE ALSO
//   ZmodemSend  Trzsz  TrzszSend  ExportFs  FsChanges  FsLog  DumpFile  DumpChanges
// BUGS
//   Sender times out if no receiver answers ZRINIT. Unified text diff is
//   host-side (git); FsDiff; is size/hash vs snap; FsDiff(a,b) is epoch-range.
// Trzsz -- Trzsz (native UART file export)
// NAME
//   Trzsz - guest→host memfs export (native tsz / stock trzsz)
// SYNOPSIS
//   TrzszSend("boot.hc");
//   TrzszSendDir("Tutorials");
//   TrzszSendChanges;
// DESCRIPTION
//   Speaks real trzsz wire protocol (::TRZSZ:TRANSFER:S, #ACT/#CFG JSON,
//   zlib+base64 #DATA, MD5) so stock trzsz clients work without --zmodem.
//   Host recipe: tools/uart_recv_trzsz.py / make trzsz-smoke. Send-only
//   (no guest trz upload). ZMODEM remains ZmodemSend.
// EXAMPLES
//   TrzszSend("boot.hc");
//   FileWrite("Tmp/n.txt","x",1); TrzszSendChanges;
// SEE ALSO
//   TrzszSend  Zmodem  ZmodemSend  DumpFile  FsChanges
// BUGS
//   Full UART REPL only; times out if no host client answers #ACT.
