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
extern I64 RVSetDbgHook(I64 fn);
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
}

I64 dbg_view_ready;

I64 main()
{
  I64 r, n, ok = 0;
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
        // Fp(1) / Fp(0): the float block is 16 more rows, so whether it is worth the screen is
        // the operator's call as well as the layout's.
        CHashFun *tp;
        tp = RVExePubFunNew("Fp", &RegPaneFpWant, cmp.internal_types[RT_U0], 1);
        if (tp)
          RVExePubAddArg(tp, "on", cmp.internal_types[RT_I64], MLF_DFT_AVAILABLE, 1);
      }
      // Dbg/G: the stock entry points. A faulting line paints this view automatically below.
      RVExePubFunNew("Dbg", &Dbg, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("G", &G, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Cls", &Cls, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("AsmRepl", &AsmRepl, cmp.internal_types[RT_U0], 0);
      AsmReplInstallStep(&AsmStep);
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
      RVExePubFunNew("Mstatus", &Mstatus, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Mcause", &Mcause, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Uptime", &Uptime, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("Pmp", &Pmp, cmp.internal_types[RT_U0], 0);
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
      "    mcause=%d mepc=%X mtval=%X ra=%X\n", cause, RVTrapRecoverEpc(),
          RVTrapRecoverTval(), RVTrapRecoverRa();
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
    r = ExePutS(line);
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
