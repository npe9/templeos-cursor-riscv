// kernel_repl_exepubs_demo.hc — A2 vertical slice:
// guest Compiler_RV ExePutS owns a UART REPL compile loop (not jit.hc).
// Smoke pipes HolyC lines; each line is ExePutS'd. See docs/SELF_HOST.md A2.
#include "/Kernel/Kernel_RV.PRJ"
#include "/Compiler/RISCVRegs.HH"
#include "/Kernel/RVDocVT.HC"
#include "/Kernel/RVDocText.HC"
#include "/Kernel/RVRegPane.HC"
#include "/Kernel/RVDbgView.HC"
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
      AsmWatchInstall(&RegPaneUpdate);
      RVExePubFunNew("RegPane", &RegPaneUpdate, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("RegPaneCost", &RegPaneCost, cmp.internal_types[RT_I64], 0);
      // Dbg/G: the stock entry points. A faulting line paints this view automatically below.
      RVExePubFunNew("Dbg", &Dbg, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("G", &G, cmp.internal_types[RT_U0], 0);
      RVExePubFunNew("DbgViewCost", &DbgViewCost, cmp.internal_types[RT_I64], 0);
      DbgViewInit();
      // StdOut sink so Dbg can put U()'s disassembly in a document
      RVExePubFunNew("DbgDisasmCost", &DbgDisasmCost, cmp.internal_types[RT_I64], 0);
      // Run the debugger INSIDE the trap: prime the docs first (allocating during a fault is
      // how you fault twice), then hand the runtime the hook so G can actually continue.
      DbgViewPrime();
      RVSetDbgHook(&DbgTrapHook);
      RVExePubFunNew("Dm", &DbgDm, cmp.internal_types[RT_U0], 2);
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
  while (TRUE) {
    UartPutS("> ");
    n = RVUartGetLine(line, 160);
    if (n <= 0)
      continue;
    if (line[0] == 'q' && (!line[1] || line[1] == ';'))
      break;
    if (RVTrapRecoverArm()) {
      I64 cause = RVTrapRecoverCause();
      UartPutS("\n*** fault in that line; returning to prompt\n");
      StrPrint(buf, "    mcause=%d mepc=%X mtval=%X ra=%X\n", cause,
        RVTrapRecoverEpc(), RVTrapRecoverTval(), RVTrapRecoverRa());
      UartPutS(buf);
      // Land in the debugger view: registers + the decoded fault, then back to this prompt,
      // where _A0 / Dr / U(_PC-16) / AsmStep already work. Stock TempleOS Dbg(), not a modal UI.
      if (dbg_view_ready)
        Dbg;
      RVTrapRecoverDisarm();
      continue;
    }
    r = ExePutS(line);
    RVTrapRecoverDisarm();
    StrPrint(buf, "ans=%d\n", r);
    UartPutS(buf);
    ok++;
  }
  if (!ok) {
    UartPutS("A2 ExePutS loop: no lines\n");
    return 2;
  }
  UartPutS("A2 ExePutS loop: OK\n");
  return 0;
}
