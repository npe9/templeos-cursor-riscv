// kernel_repl_exepubs_demo.hc — A2 vertical slice:
// guest Compiler_RV ExePutS owns a UART REPL compile loop (not jit.hc).
// Smoke pipes HolyC lines; each line is ExePutS'd. See docs/SELF_HOST.md A2.
#include "/Kernel/Kernel_RV.PRJ"
#include "/Compiler/RISCVRegs.HH"
// Order matters: each of these uses the ones above it (RVAsmReplUi wants Cls/DbgDm from
// RVDbgView, which wants the renderer and the pane). AsmStep lives on the compiler side, which
// is included last, so the UI calls it through a pointer installed at run time.
#include "/Kernel/RVDocVT.HC"
#include "/Kernel/RVDocText.HC"
#include "/Kernel/RVRegPane.HC"
#include "/Kernel/RVDbgView.HC"
#include "/Kernel/RVDolAnsi.HC"
#include "/Kernel/RVLineEd.HC"
#include "/Kernel/RVComplete.HC"
#include "/Kernel/RVAsmReplUi.HC"
#include "/Compiler/Compiler_RV_Body.PRJ"
#define MEM_UART 0x10000000
extern U0 RVTrapInit();
extern I64 RVTrapRecoverArm();
extern U0 RVUartIrqInit();
extern U0 RVUartIrqOff();
extern I64 RVUartGetBuffered();
extern I64 RVSetDbgHook(I64 fn);
extern U0 RVLexNewlineSemi(I64 on);
extern U0 RVTrapRecoverDisarm();
extern I64 RVTrapRecoverCause();
extern I64 RVTrapRecoverEpc();
extern I64 RVTrapRecoverTval();
extern I64 RVTrapRecoverRa();
U0 UartPutC(I64 ch)
{
  U8 *uart = MEM_UART;
  *uart = ch;
}

U0 UartPutS(U8 *s)
{
  while (s && *s) {
    UartPutC (*s);
    s++;
  }
}
// MemMap is now the real RISC-V memory map from Kernel/RVExplore.HC (linked via
// Kernel_RV.PRJ and planted by RVExePubsWire). Funs stays a minimal stub for this
// UART-only artifact (the full symbol table isn't linked here).
public U0 Funs(U8 *filt = NULL)
{
  UartPutS("Funs: ExePutS CInit RVTrapInit MemMap AsmList AsmDoc Mstatus Mcause\n");
  UartPutS("Board: Gpio GpioRd(pin) GpioIe(pin,on) GpioWr(pin,val) GpioArm GpioRelease(pin) PowerOff Pci Eth Temp Rtc Sd SdRd(blk) L2 Pwm(ch,duty) PwmOff Morse(a,b,c) Blink(ch,n) Led(r,g,b) PwmAny(ch,duty) PwmFree(ch,duty) Dump(addr,lines) Peek(addr) PeekU32(addr) FlashMap(on)\n");
}
I64 dbg_view_ready;
I64 main()
{
  I64 r, n, ok = 0, brk;
  U8 buf[64];
  U8 line[160];
  CTask *adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
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
  TaskInit(adam, 0);
  CCPU *gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
  RVKernelInit();
  // The standalone compiler image has no WinSerialInit wrapper. Install the
  // machine trap vector here so a bad ExePutS line returns to the prompt.
  RVTrapInit();
  // Soft RX: PutS/FcPoll must not drop piped stdin before GetLine (A2 REPL).
  RVUartSoftOn(1);
  RVMountRAMDisk('A', 4096);
  CInit();
  // Chain Fs → asm_hash only when distinct (aliasing creates a HashFind self-loop).
  if (cmp.asm_hash)
    cmp.asm_hash->next = NULL;
  if (Fs && Fs->hash_table && cmp.asm_hash && Fs->hash_table != cmp.asm_hash)
    Fs->hash_table->next = cmp.asm_hash;
  RVExePubsWire;
  // Debugger surface: Disasm/DisasmAt/U/UA/FnAddr/Uf/Bp/BpClr (Kernel/RVDisasm.HC).
  // Closes the assemble->disassemble loop in this REPL: `asm{Fn:: ...ret}` then
  // `Disasm("Fn")` / `Uf("Fn")` shows the decoded instructions you just emitted.
  
  {
    // Slots 2 (U) and 3 (UA) are deliberately left 0: they target the win/VT DolDoc
    // renderer this serial image lacks — U emits `$HL$` hyperlink markup then derefs a
    // null DolDoc struct, and UA's label-collection walk runs off the end of RAM. Both
    // fault here, so we do not advertise them. The name-based Disasm/Uf, plain DisasmAt,
    // FnAddr, and Bp/BpClr all work in this environment (each exercised by the smoke).
    I64 dbg[8], di;
    for (di = 0; di < 8; di++)
      dbg[di] = 0;
    dbg[0] = &Disasm;
    dbg[1] = &DisasmAt;
    dbg[4] = &RVDisFnAddr;
    dbg[5] = &RVUf;
    dbg[6] = &RVBp;
    dbg[7] = &RVBpClr;
    StrPrint(buf, "A2 dbg pubs wired n=%d\n", RVExePubsWireDbg(dbg));
    // Board devices at the prompt. These need no WinMgr, so they are registered before the pane
    // block: on a board with no SiFive GPIO they all answer honestly rather than poking address 0.
    //   Gpio;            all 16 lines, with the board's own names for them
    //   GpioRd(pin)      level read back            GpioWr(pin,val)  drive it (1 done, 0 refused)
    //   GpioArm;         permit ONE guarded write   GpioRelease(pin) stop driving
    //   PowerOff;        PMICSHDN, and the board switches off
    {
      CHashFun *gp;
      RVExePubFunNew("Gpio", &Gpio, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("GpioArm", &RVGpioArm, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("PowerOff", &PowerOff, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Pci", &Pci, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Eth", &Eth, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Temp", &Temp, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Rtc", &Rtc, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Sd", &Sd, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("L2", &L2, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Clk", &Clk, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("EthAb", &EthAb, cmp.internal_types[RT_U0], 0);
      {
        CHashFun *sp;
        sp = RVExePubFunNew("SdRd", &SdRd, cmp.internal_types[RT_U0], 1);
        if (sp)
          RVExePubAddArg(sp, "blk", cmp.internal_types[RT_I64], 0, 0);
      }
      {
        CHashFun *wp;
        // Pwm(ch,duty): which channel reaches which LED or fan header is undocumented on this
        // board, so this is the instrument for finding out. Pwm(ch,0) or PwmOff to stop.
        wp = RVExePubFunNew("Pwm", &RVPwmSet, cmp.internal_types[RT_I64], 2);
        if (wp) {
          RVExePubAddArg(wp, "ch", cmp.internal_types[RT_I64]);
          RVExePubAddArg(wp, "duty", cmp.internal_types[RT_I64]);
        }
        RVExePubFunNew("PwmOff", &RVPwmOff, cmp.internal_types[RT_I64], 0);
        // PwmAny(ch,duty): ch 0..7 spans BOTH pwm blocks (0-3 = pwm0, 4-7 = pwm1), for finding
        // out what the four unexplored channels of the second block reach.
        wp = RVExePubFunNew("PwmAny", &RVPwmAnySet, cmp.internal_types[RT_I64], 2);
        if (wp) {
          RVExePubAddArg(wp, "ch", cmp.internal_types[RT_I64]);
          RVExePubAddArg(wp, "duty", cmp.internal_types[RT_I64]);
        }
        // PwmFree(ch,duty): pwm0 with the counter free-running, so channel 0 — the D12 LED —
        // becomes an ordinary brightness instead of a pulse at each period wrap.
        wp = RVExePubFunNew("PwmFree", &RVPwmFreeSet, cmp.internal_types[RT_I64], 2);
        if (wp) {
          RVExePubAddArg(wp, "ch", cmp.internal_types[RT_I64]);
          RVExePubAddArg(wp, "duty", cmp.internal_types[RT_I64]);
        }
        // Morse(c1,c2,c3,reps): a different letter blinking on each LED at once. Defaults spell
        // the first three letters of the system that is blinking them.
        wp = RVExePubFunNew("Morse", &Morse, cmp.internal_types[RT_U0], 4);
        if (wp) {
          RVExePubAddArg(wp, "c1", cmp.internal_types[RT_I64], 0, 'T');
          RVExePubAddArg(wp, "c2", cmp.internal_types[RT_I64], 0, 'E');
          RVExePubAddArg(wp, "c3", cmp.internal_types[RT_I64], 0, 'M');
          RVExePubAddArg(wp, "reps", cmp.internal_types[RT_I64], 0, 3);
          RVExePubAddArg(wp, "unit", cmp.internal_types[RT_I64], 0, 500);
        }
        // Led(r,g,b): the board's RGB LED by colour rather than by channel number. The mapping
        // green=1 red=2 blue=3 was measured by driving each channel and looking at the board.
        wp = RVExePubFunNew("Led", &Led, cmp.internal_types[RT_U0], 3);
        if (wp) {
          RVExePubAddArg(wp, "r", cmp.internal_types[RT_I64], 0, 0);
          RVExePubAddArg(wp, "g", cmp.internal_types[RT_I64], 0, 0);
          RVExePubAddArg(wp, "b", cmp.internal_types[RT_I64], 0, 0);
        }
        // Blink(ch,times): the unambiguous version — one LED, 1 Hz, nothing clever.
        wp = RVExePubFunNew("Blink", &Blink, cmp.internal_types[RT_U0], 2);
        if (wp) {
          RVExePubAddArg(wp, "ch", cmp.internal_types[RT_I64], 0, 1);
          RVExePubAddArg(wp, "times", cmp.internal_types[RT_I64], 0, 10);
        }
      }
      {
        CHashFun *dp;
        dp = RVExePubFunNew("Dump", &Dump, cmp.internal_types[RT_U0], 2);
        if (dp) {
          RVExePubAddArg(dp, "addr", cmp.internal_types[RT_U8] + 1);
          RVExePubAddArg(dp, "lines", cmp.internal_types[RT_I64], 0, 8);
        }
        dp = RVExePubFunNew("Peek", &Peek, cmp.internal_types[RT_I64], 1);
        if (dp)
          RVExePubAddArg(dp, "addr", cmp.internal_types[RT_U8] + 1);
        dp = RVExePubFunNew("PeekU32", &PeekU32, cmp.internal_types[RT_I64], 1);
        if (dp)
          RVExePubAddArg(dp, "addr", cmp.internal_types[RT_U8] + 1);
        // FlashMap(1) turns on QSPI0's direct-mapped reader so Dump(0x20000000) shows the
        // SPI-NOR. Firmware leaves it off; it is a read-path bit and cannot alter the flash.
        dp = RVExePubFunNew("FlashMap", &RVQspiFlashMap, cmp.internal_types[RT_I64], 1);
        if (dp)
          RVExePubAddArg(dp, "on", cmp.internal_types[RT_I64]);
      }
      gp = RVExePubFunNew("GpioRd", &RVGpioRd, cmp.internal_types[RT_I64], 1);
      if (gp)
        RVExePubAddArg(gp, "pin", cmp.internal_types[RT_I64]);
      gp = RVExePubFunNew("GpioRelease", &RVGpioRelease, cmp.internal_types[RT_I64], 1);
      if (gp)
        RVExePubAddArg(gp, "pin", cmp.internal_types[RT_I64]);
      gp = RVExePubFunNew("GpioWr", &RVGpioWr, cmp.internal_types[RT_I64], 2);
      if (gp) {
        RVExePubAddArg(gp, "pin", cmp.internal_types[RT_I64]);
        RVExePubAddArg(gp, "val", cmp.internal_types[RT_I64]);
      }
      // GpioIe(pin,on): look at a pin. Firmware leaves every input buffer off, so this is what
      // makes GpioRd say anything -- e.g. GpioIe(15,1); GpioRd(15) asks whether a card is in the slot.
      gp = RVExePubFunNew("GpioIe", &RVGpioIeSet, cmp.internal_types[RT_I64], 2);
      if (gp) {
        RVExePubAddArg(gp, "pin", cmp.internal_types[RT_I64]);
        RVExePubAddArg(gp, "on", cmp.internal_types[RT_I64]);
      }
    }
    // Live register pane over the same freeze the labels alias: a DolDoc rendered straight to
    // the terminal, repainted by AsmStep's watch hook so a stepped register lights up in place.
    // DolDoc needs the WinMgr grid up, and it needed the `extern U8 doldoc` in RVExePubs.HC to
    // stop shadowing the kernel's real global — see that file.
    if (RVWinMgrLiteInit()) {
      RVVtInit(0, 1);
      // The pane repaints after every stepped instruction, at this prompt and inside AsmRepl:
      // AsmStep itself is the painter (one painter — two would each see "nothing changed since
      // the other" and wash the red out).
      AsmWatchInstall(&RegPaneStep);
      RVExePubFunNew("RegPane", &RegPaneStep, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("RegPaneCost", &RegPaneCost, cmp.internal_types[RT_I64], 0);
      
      {
        // Pane(n): which block the pane starts at — 0 registers, 1 machine state, 2 float.
        // The pane packs whole blocks from there, so this is "show me that one first".
        CHashFun *tp;
        tp = RVExePubFunNew("Pane", &RegPanePage, cmp.internal_types[RT_U0], 1);
        if (tp)
          RVExePubAddArg(tp, "n", cmp.internal_types[RT_I64]);
      }
      // Dbg/G: the stock entry points. A faulting line paints this view automatically below.
      RVExePubFunNew("Dbg", &Dbg, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("G", &G, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Cls", &Cls, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("AsmRepl", &AsmRepl, cmp.internal_types[RT_U0], 0);
      AsmReplInstallStep(&AsmStep);
      // Start the change journal, which also installs its FileWrite hook. Until this runs
      // fsj_write_fn is 0 and FileWrite journals nothing, so an image that does not want a
      // journal simply does not call this.
      FsJournalInit;
      // The pane layout is standing, not something AsmRepl puts up: the registers are live at
      // this prompt too, and a pane in the column the prompt scrolls through gets scribbled
      // over and then looks frozen. Cls puts it back rather than leaving bare rows behind.
      DbgSetRelayout(&AsmUiLayout);
      // The panes go back up at every prompt: output scrolls the screen and a sidebar scrolls
      // with it, so the prompt — the moment the screen is quiet — is where it is put back.
      RVLineEdPrePrompt(&AsmUiPrePrompt);
      // Tab at the HolyC prompt completes from the hash table — every function, global, type
      // and register label the REPL can resolve, including ones defined a moment ago.
      RVLineEdComplete(&RVHashComplete);
      // Hypertext on a terminal: links are numbered as they print, Links lists them, Lk(n)
      // follows one. A DolDoc message is a place you can go, and that should survive the
      // translation to a serial line.
      RVExePubFunNew("Links", &Links, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Lk0", &Lk0, cmp.internal_types[RT_U0], 0);
      
      {
        CHashFun *tl;
        tl = RVExePubFunNew("Lk", &Lk, cmp.internal_types[RT_U0], 1);
        if (tl)
          RVExePubAddArg(tl, "n", cmp.internal_types[RT_I64], MLF_DFT_AVAILABLE, 1);
      }
      // The RISC-V catalog as REPL functions: AsmList() lists the documented mnemonics and
      // AsmDoc("addi") explains one. They are in this image already (Kernel/RVExplore.HC, via
      // Kernel_RV.PRJ) — what was missing was planting them where the guest compiler can
      // resolve them, which is all "enabled in the REPL" means here. The asm REPL completes
      // from the same catalog, so Tab and AsmDoc agree by construction.
      RVExePubFunNew("AsmList", &AsmList, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("AsmClasses", &AsmClasses, cmp.internal_types[RT_U0], 0);
      
      {
        CHashFun *tk;
        tk = RVExePubFunNew("AsmClass", &AsmClass, cmp.internal_types[RT_U0], 1);
        if (tk)
          RVExePubAddArg(tk, "name", cmp.internal_types[RT_U8] + 1);
      }
      RVExePubFunNew("Mstatus", &Mstatus, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Mcause", &Mcause, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Uptime", &Uptime, cmp.internal_types[RT_U0], 0);
      
      {
        // CsrNum(0x7B0): read a CSR by number, by writing the instruction at run time
        CHashFun *tn;
        tn = RVExePubFunNew("CsrNum", &CsrNum, cmp.internal_types[RT_I64], 1);
        if (tn)
          RVExePubAddArg(tn, "num", cmp.internal_types[RT_I64]);
      }
      RVExePubFunNew("Pmp", &Pmp, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Pt", &Pt, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("PtDemo", &PtDemo, cmp.internal_types[RT_I64], 0);
      RVExePubFunNew("PtWalk", &PtWalk, cmp.internal_types[RT_I64], 0);
      RVExePubFunNew("ArgOne", &ArgOne, cmp.internal_types[RT_I64], 0);
      
      {
        CHashFun *te;
        te = RVExePubFunNew("ArgEcho", &ArgEcho, cmp.internal_types[RT_U0], 3);
        if (te) {
          RVExePubAddArg(te, "a", cmp.internal_types[RT_I64]);
          RVExePubAddArg(te, "b", cmp.internal_types[RT_I64]);
          RVExePubAddArg(te, "c", cmp.internal_types[RT_I64]);
        }
      }
      
      {
        // Pg(va) walks the live satp; PgAt(root, levels, va) walks a table you hand it, which
        // is how it can be exercised on a machine with paging off — as this one has.
        CHashFun *tg;
        tg = RVExePubFunNew("Pg", &Pg, cmp.internal_types[RT_I64], 1);
        if (tg)
          RVExePubAddArg(tg, "va", cmp.internal_types[RT_I64]);
        tg = RVExePubFunNew("PgAt", &PgAt, cmp.internal_types[RT_I64], 3);
        if (tg) {
          RVExePubAddArg(tg, "root", cmp.internal_types[RT_I64]);
          RVExePubAddArg(tg, "va", cmp.internal_types[RT_I64]);
          // levels is REQUIRED here even though the C function defaults it: a planted pub's
          // MLF_DFT_AVAILABLE default does not reach the callee — the argument arrives as zero
          // — so a pub that looks optional would silently walk no levels at all.
          RVExePubAddArg(tg, "levels", cmp.internal_types[RT_I64]);
        }
      }
      
      {
        // Fd(n): a float register as a number and as its IEEE-754 fields
        CHashFun *tfd;
        tfd = RVExePubFunNew("Fd", &RegPaneFd, cmp.internal_types[RT_U0], 1);
        if (tfd)
          RVExePubAddArg(tfd, "n", cmp.internal_types[RT_I64], MLF_DFT_AVAILABLE, -1);
      }
      
      {
        // Plic(): the interrupt controller is architectural state too, and nothing could read it
        CHashFun *tp2;
        tp2 = RVExePubFunNew("Plic", &Plic, cmp.internal_types[RT_U0], 1);
        if (tp2)
          RVExePubAddArg(tp2, "max_irq", cmp.internal_types[RT_I64], MLF_DFT_AVAILABLE, 32);
      }
      
      {
        // Csr("mtvec") — a live read, decoded. Machine() is the same registers as they were
        // FROZEN; both are worth having and they answer different questions.
        CHashFun *tc;
        tc = RVExePubFunNew("Csr", &Csr, cmp.internal_types[RT_U0], 1);
        if (tc)
          RVExePubAddArg(tc, "name", cmp.internal_types[RT_U8] + 1);
      }
      
      {
        CHashFun *ta;
        ta = RVExePubFunNew("AsmDoc", &AsmDoc, cmp.internal_types[RT_U0], 1);
        if (ta)
          RVExePubAddArg(ta, "mn", cmp.internal_types[RT_U8] + 1);
        // U8* — the mnemonic comes in as a string constant from the REPL line
      }
      // The stopped machine, decoded: the freeze carries ten more CSRs than it used to, and
      // this is what reads them rather than asking the hardware what it thinks NOW.
      RVExePubFunNew("Machine", &Machine, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("DbgViewCost", &DbgViewCost, cmp.internal_types[RT_I64], 0);
      // Errors and Print() output carry DolDoc markup; translate it to ANSI instead of showing
      // the operator "$LTRED$$BK,1$ERROR:$FG$".
      RVDolAnsiInstall();
      DbgViewInit();
      // StdOut sink so Dbg can put U()'s disassembly in a document
      RVExePubFunNew("DbgDisasmCost", &DbgDisasmCost, cmp.internal_types[RT_I64], 0);
      // Run the debugger INSIDE the trap: prime the docs first (allocating during a fault is
      // how you fault twice), then hand the runtime the hook so G can actually continue.
      DbgViewPrime();
      RVSetDbgHook(&DbgTrapHook);
      
      {
        CHashFun *tf;
        tf = RVExePubFunNew("Dm", &DbgDm, cmp.internal_types[RT_U0], 2);
        if (tf) {
          RVExePubAddArg(tf, "addr", cmp.internal_types[RT_I64]);
          RVExePubAddArg(tf, "n", cmp.internal_types[RT_I64], MLF_DFT_AVAILABLE, 64);
        }
        tf = RVExePubFunNew("D", &DbgD, cmp.internal_types[RT_U0], 2);
        if (tf) {
          RVExePubAddArg(tf, "addr", cmp.internal_types[RT_I64]);
          RVExePubAddArg(tf, "n", cmp.internal_types[RT_I64], MLF_DFT_AVAILABLE, 64);
        }
        tf = RVExePubFunNew("Da", &DbgDa, cmp.internal_types[RT_U0], 2);
        if (tf) {
          RVExePubAddArg(tf, "addr", cmp.internal_types[RT_I64]);
          RVExePubAddArg(tf, "n", cmp.internal_types[RT_I64], MLF_DFT_AVAILABLE, 16);
        }
      }
      dbg_view_ready = 1;
      UartPutS("A2 reg pane wired\n");
    }
    UartPutS(buf);
  }
  // This image has completed the kernel/compiler setup normally performed
  // before KEnd marks the Adam server live.  Without this bit, every compiler
  // diagnostic is prefixed with the misleading boot-phase note.
  LBts(&sys_run_level, RLf_ADAM_SERVER);
  if (!HashFind("I64", cmp.asm_hash, HTT_INTERNAL_TYPE, 1)) {
    UartPutS("A2 ExePutS REPL: I64 FAIL\n");
    return 1;
  }
  // Cmp-distinct: real Compiler_RV ExePutS returns the expr value (Jit bridge maps to -1/0/1).
  UartPutS("A2: Compiler_RV owns ExePutS\n");
  UartPutS("A2 ExePutS REPL\n");
  r = ExePutS("40+2;\n");
  StrPrint(buf, "probe ans=%d\n", r);
  UartPutS(buf);
  if (r != 42) {
    UartPutS("A2 ExePutS REPL: probe FAIL\n");
    return r;
  }
  UartPutS("A2: Cmp compiled 40+2\n");
  UartPutS("A2: type HolyC; 'q' quits\n");
  if (dbg_view_ready) {
    // Ask the terminal how big it is before deciding where anything goes — a sidebar on an
    // 80-column screen is a different layout from one on a 120-column screen, and guessing is
    // how ten registers went missing the first time.
    // A line you type IS a statement, so the newline ends it: `40+2` and `Machine` need no
    // semicolon. Only for what is typed here — nothing the Cmp compiles from a file changes, and
    // inside asm{} the lexer keeps newlines and the rule never runs.
    RVLexNewlineSemi(TRUE);
    RVVtProbeSize(300);
    // ...and hear about it when it changes. A serial guest gets no SIGWINCH, so the terminal
    // has to say so: mode 2048 makes it report every resize in band (and one immediately), and
    // the prompt re-probes for terminals that do not know the mode.
    RVVtOnResize(&AsmUiResized);
    RVVtResizeReports(TRUE);
    AsmUiLayout(0, TRUE);
  }
  while (TRUE) {
    // History + Tab completion at the main prompt too (RVUartGetLine has neither). The prompt
    // belongs to the editor now: it redraws the line, and a line longer than the text column
    // scrolls sideways under the cursor rather than running over the sidebar.
    n = RVLineEd(line, 160, "> ");
    if (n < 0)
      continue;
    if (n <= 0)
      continue;
    if (line[0] == 'q' && (!line[1] || line[1] == ';'))
      break;
    if (RVTrapRecoverArm()) {
      I64 cause = RVTrapRecoverCause();
      // Through the chain, not UartPutS: printed output is kept inside the text column so it
      // cannot be written over the panes beside it.
      "\n*** fault in that line; returning to prompt\n";
      "    mcause=%d mepc=%X mtval=%X ra=%X\n", cause, RVTrapRecoverEpc(), RVTrapRecoverTval(), RVTrapRecoverRa();
      // Land in the debugger view: registers + the decoded fault, then back to this prompt,
      // where _A0 / Dr / U(_PC-16) / AsmStep already work. Stock TempleOS Dbg(), not a modal UI.
      if (dbg_view_ready) {
        Dbg;
        // A fault unwinds past whatever AsmRepl was in the middle of, so the prompt would be
        // left confined to the asm layout's region with Tab still completing mnemonics. Put the
        // prompt's own layout and completion back — this is the only path out of a fault.
        AsmUiLayout(0, FALSE);
        RVLineEdComplete(&RVHashComplete);
      }
      RVTrapRecoverDisarm();
      continue;
    }
    // Give the line back the newline the editor stripped: that newline is what ends the
    // statement (RVLexNewlineSemi), so without it `40+3` reaches the compiler as an unfinished
    // expression and the rule never gets a chance to fire.
    if (StrLen(line) < 158)
      StrCat(line, "\n");
    RVUartIrqInit();
    r = ExePutS(line);
    RVUartIrqOff();
    while ((brk = RVUartGetBuffered()) >= 0)
      RVUartSoftEnqueue(brk & 0xFF);
    RVTrapRecoverDisarm();
    "ans=%d\n", r;
    ok++;
  }
  if (!ok) {
    UartPutS("A2 ExePutS loop: no lines\n");
    return 2;
  }
  UartPutS("A2 ExePutS loop: OK\n");
  return 0;
}
