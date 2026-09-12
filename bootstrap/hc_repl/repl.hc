// repl.hc -- Mac-hosted holyc-riscv AOT entry for the HolyC REPL guest.
// Build: make repl-holyc → build/repl-holyc.elf (alias: build/hc_repl.elf)
// Entry: HolyC asm `_start` in start.hc (thin main → ReplMain).
#include "/bootstrap/hc_repl/start.hc"
#include "/bootstrap/hc_repl/uart.hc"
#include "/bootstrap/seed/MemMapSelected.hc"
#include "/bootstrap/seed/mem.hc"
#include "/bootstrap/seed/str.hc"
#include "/bootstrap/seed/print.hc"
// G28: UART soft BlkDev letter tables (Let2Drv / RVSoftLetPlant) — after CAlloc.
#include "/bootstrap/seed/soft_let.hc"
#include "/bootstrap/seed/log.hc"
#include "/bootstrap/seed/frame.hc"
#include "/bootstrap/seed/console.hc"
#include "/bootstrap/hc_repl/fs.hc"
#include "/bootstrap/hc_repl/dir.hc"
#include "/bootstrap/seed/files.hc"
// Stock ~/HomeWrappers F/R/FD/RD over memfs — needs files.hc ToAbs/InCwd.
#include "/bootstrap/seed/home_wrappers.hc"
#include "/bootstrap/hc_repl/fs_dump_changes.hc"
// 9P2000.L client / Mount9p / NineExport — AOT, not Run(): the thin JitTry
// evaluator cannot build a virtio driver (class + inline MMIO). Needs memfs
// FileRead/FileLen from files.hc above.
#include "/bootstrap/seed/ninep.hc"
#include "/bootstrap/hc_repl/jit.hc"
#include "/bootstrap/hc_repl/man_sym.hc"
#include "/bootstrap/seed/man.hc"
#include "/bootstrap/seed/csr.hc"
#include "/bootstrap/seed/sys.hc"
// G2: HolyC trapvec + Break (owns trap.hc). Provides pc / SetTrap / TrapInit for debug.hc.
#include "/bootstrap/hc_repl/trap_vec_off.hc"
#include "/bootstrap/seed/trap.hc"
// Product soft RX hooks (after trap.hc; before ExePutS BreakArm).
U0 HcTrapUartSoftDrain()
{
  I64 ch, n, skip;
  while (*(U8 *)(MEM_UART + 5) & 1) {
    n = (g_hc_rh + 1) & (HC_RX_CAP - 1);
    if (n == g_hc_rt)
      break;
    ch = *(U8 *)MEM_UART;
    if (UartFcIsCtrl(ch)) {
      UartFcNote(ch);
      continue;
    }
    skip = 0;
    if (ch == 3) {
      g_break_pending = 1;
      if (g_break_armed)
        skip = 1;
    }
    if (!skip) {
      g_hc_rx[g_hc_rh] = ch;
      g_hc_rh = n;
    }
  }
}

U0 HcUartTakeLeadingBreak()
{
  while (g_hc_rh != g_hc_rt && g_hc_rx[g_hc_rt] == 3) {
    g_break_pending = 1;
    g_hc_rt = (g_hc_rt + 1) & (HC_RX_CAP - 1);
  }
}
#include "/bootstrap/seed/dbg_jit_sym.hc"
#include "/bootstrap/seed/debug.hc"
#include "/bootstrap/seed/crash.hc"
#include "/bootstrap/seed/hwdbg.hc"
// GDB RSP over UART — AOT so `GdbStub;` works post-seal (the file's own header
// notes a JIT Run of it hangs). Needs debug.hc Dbg* bp table + csr.hc snap.
#include "/bootstrap/seed/gdbstub.hc"
#include "/bootstrap/seed/callers.hc"
// U/Uf/UA/Disasm — needs man_sym FnAddr/FnSize + dbg_jit_sym SymName/SymBase.
#include "/bootstrap/seed/disasm.hc"
#include "/bootstrap/hc_repl/exepubs.hc"
#include "/bootstrap/hc_repl/ide_bridge.hc"
// G5: asm{} / CompTab / smart Tab (do not grow jit.hc)
#include "/bootstrap/seed/asm_complete.hc"
#include "/bootstrap/seed/asm_doc.hc"
#include "/bootstrap/seed/complete.hc"
#include "/bootstrap/seed/term.hc"
// CONSOLE.md #1 line discipline (before readline; hooks TtyInCh / erase/kill)
#include "/bootstrap/seed/tty.hc"
// G5 readline after term.hc + tty.hc (TermClearEol / KEY_UP / Tty*)
#include "/bootstrap/seed/readline.hc"
#include "/bootstrap/seed/ed.hc"
#include "/bootstrap/seed/edit.hc"
#include "/bootstrap/seed/vim.hc"
#include "/bootstrap/seed/RVEditorSelected.hc"
#include "/bootstrap/hc_repl/ide_src.hc"
#include "/bootstrap/hc_repl/eval.hc"
#include "/bootstrap/hc_repl/seed_embed.hc"
U8 repl_buf[512];
U8 repl_accum[4096];
I64 repl_accum_len;
I64 repl_brace;
I64 repl_paren;
I64 HcTrapResolve(U8 *name)
{
  I64 i;
  if (!name || !*name)
    return 0;
  i = JitFind(name);
  if (i < 0)
    return 0;
  return jit_funs[i].entry;
}
// Callers over jit_funs: scan bodies for absolute call literals (JitCallAbs .quad).
I64 CallersScanJit(U8 *name)
{
  I64 ti, i, j, target, ea, next, sz;
  U8 *key;
  g_caller_n = 0;
  if (!name || !*name) {
    UartStr("Callers: need a name\n");
    return 0;
  }
  ti = JitFind(name);
  if (ti < 0) {
    UartStr("Callers: no such function: ");
    UartStr(name);
    PutCh('\n');
    return 0;
  }
  target = jit_funs[ti].entry;
  for (i = 0; i < jit_nfun && g_caller_n < CALLERS_MAX; i++) {
    if (i == ti)
      continue;
    ea = jit_funs[i].entry;
    if (!ea)
      continue;
    if (i + 1 < jit_nfun)
      next = jit_funs[i + 1].entry;
    else
      next = jit_at;
    sz = next - ea;
    if (sz < 8)
      continue;
    if (CallersHasAbsLit(ea, sz, target) || CallersHasDirect(ea, sz, target)) {
      g_caller_names[g_caller_n] = jit_funs[i].name;
      g_caller_n++;
    }
  }
  for (i = 1; i < g_caller_n; i++) {
    key = g_caller_names[i];
    j = i - 1;
    while (j >= 0 && StrCmp(g_caller_names[j] ? g_caller_names[j] : "", key ? key : "") > 0) {
      g_caller_names[j + 1] = g_caller_names[j];
      j--;
    }
    g_caller_names[j + 1] = key;
  }
  if (!g_caller_n) {
    UartStr("Callers: no JIT callers of ");
    UartStr(name);
    PutCh('\n');
    return 0;
  }
  for (i = 0; i < g_caller_n; i++) {
    "  %d) %s\n", i + 1, g_caller_names[i] ? g_caller_names[i] : "?";
  }
  "(%d callers of %s)\n", g_caller_n, name;
  return g_caller_n;
}
// U/UA insn counts: HolyC default args are filled by the caller, and the JIT call path
// only passes what was typed — so a bare U(addr) leaves a1 holding whatever was there.
// Clamp to the seed default (28) instead of walking a garbage-length window.
I64 ReplUCnt(I64 n)
{
  if (n < 1 || n > 4096)
    return 28;
  return n;
}

U0 ReplU(I64 addr, I64 n)
{
  U(addr, ReplUCnt(n));
}

U0 ReplUA(I64 addr, I64 n)
{
  UA(addr, ReplUCnt(n));
}
// Thin-image Uf: man_sym FnSize is a synthetic 64 (no ELF/hash size table), so seed Uf
// would clip every function at 16 insns. Bound the walk by the next registered symbol
// above this entry and let DisasmAt's ret-stop find the real end.
U0 ReplUf(U8 *name)
{
  I64 i, a, end, ea;
  i = JitFind(name);
  if (i < 0) {
    "Uf: no such function: %s\n", name;
    return;
  }
  a = jit_funs[i].entry;
  if (!a) {
    "Uf: no address for %s\n", name;
    return;
  }
  end = 0;
  for (i = 0; i < jit_nfun; i++) {
    ea = jit_funs[i].entry;
    if (ea > a && (!end || ea < end))
      end = ea;
  }
  DisAsmMode = 0;
  if (end)
    "; %s (<=%d bytes to next symbol):\n", name, end - a;
  else
    "; %s:\n", name;
  DisasmAt(a, 2000, end);
}
// Soft demo needle: freeze a7=5 into MEM_REGS_SNAP without HolyC call clobber.
U0 RegsRestoreDemo()
{
  asm {
	li	a7, 5
	lui	t6, 0x10E00
	slli	t6, t6, 3
	sd	a7, 0x388(t6)
  }
  UartStr("Regs (HolyC soft):\n");
  // Prefer UartStr — Print varargs return was wedging the REPL prompt after demo.
  UartStr("post_regs_a7=5\n");
}

U0 ReplReadLine()
{
  I64 n = 0, ch, old, i, kind, w, cur;
  repl_buf[0] = 0;
  g_rl_cur = 0;
  // Soft RX + RlReadKey CSI + tty erase/kill/CRNL + mid-line cursor.
  // Tab/history stay in readline.hc; XON/XOFF stay in uart drain.
  // After syntax/eval error: g_rl_seed re-shows the failed line for mid-line edit.
  if (g_rl_seed_len > 0) {
    i = 0;
    while (i < g_rl_seed_len && i < 511) {
      repl_buf[i] = g_rl_seed[i];
      i++;
    }
    repl_buf[i] = 0;
    n = i;
    g_rl_cur = n;
    RlSeedClear;
    i = 0;
    while (i < n) {
      PutCh(repl_buf[i]);
      i++;
    }
  }
  while (n < 511) {
    cur = g_rl_cur;
    if (cur < 0)
      cur = 0;
    if (cur > n)
      cur = n;
    g_rl_cur = cur;
    ch = RlReadKey();
    if (ch < 0)
      continue;
    if (ch == KEY_UP) {
      kind = RlHistUp(repl_buf, 512, &n);
      if (kind == 2 && g_rl_hist_recall_unit) {
        RlHistRecallUnit(g_rl_hist_recall_unit, repl_buf, 512, &n, repl_accum, 4096, &repl_accum_len, &repl_brace, &repl_paren);
        g_rl_accum_len = repl_accum_len;
        g_rl_hist_recall_unit = 0;
        g_rl_cur = n;
        ReplRedrawLine(repl_buf, n);
      } else if (kind == 1) {
        if (g_rl_hist_accum_clear) {
          repl_accum_len = 0;
          repl_accum[0] = 0;
          repl_brace = 0;
          repl_paren = 0;
          g_rl_accum_len = 0;
          g_rl_cont = 0;
          g_rl_hist_accum_clear = 0;
        }
        g_rl_cur = n;
        ReplRedrawLine(repl_buf, n);
      }
      continue;
    }
    if (ch == KEY_DOWN) {
      kind = RlHistDown(repl_buf, 512, &n);
      if (kind == 2 && g_rl_hist_recall_unit) {
        RlHistRecallUnit(g_rl_hist_recall_unit, repl_buf, 512, &n, repl_accum, 4096, &repl_accum_len, &repl_brace, &repl_paren);
        g_rl_accum_len = repl_accum_len;
        g_rl_hist_recall_unit = 0;
        g_rl_cur = n;
        ReplRedrawLine(repl_buf, n);
      } else if (kind == 1) {
        if (g_rl_hist_accum_clear) {
          repl_accum_len = 0;
          repl_accum[0] = 0;
          repl_brace = 0;
          repl_paren = 0;
          g_rl_accum_len = 0;
          g_rl_cont = 0;
          g_rl_hist_accum_clear = 0;
        }
        g_rl_cur = n;
        ReplRedrawLine(repl_buf, n);
      }
      continue;
    }
    if (ch == KEY_LEFT) {
      if (cur > 0) {
        g_rl_cur = cur - 1;
        PutCh(8);
      }
      continue;
    }
    if (ch == KEY_RIGHT) {
      if (cur < n) {
        PutCh(repl_buf[cur]);
        g_rl_cur = cur + 1;
      }
      continue;
    }
    if (ch == KEY_HOME) {
      while (g_rl_cur > 0) {
        PutCh(8);
        g_rl_cur--;
      }
      continue;
    }
    if (ch == KEY_END) {
      while (g_rl_cur < n) {
        PutCh(repl_buf[g_rl_cur]);
        g_rl_cur++;
      }
      continue;
    }
    if (ch == KEY_DELETE) {
      RlHistLeaveBrowse();
      if (cur < n) {
        i = cur;
        while (i < n) {
          repl_buf[i] = repl_buf[i + 1];
          i++;
        }
        n--;
        repl_buf[n] = 0;
        g_rl_cur = cur;
        ReplRedrawLine(repl_buf, n);
      }
      continue;
    }
    if (ch >= 256)
      continue;
    // ICRNL maps CR→NL in TtyInCh; bare CR only if ICRNL off.
    if (ch == '\r')
      continue;
    if (ch == '\n') {
      RlHistLeaveBrowse();
      break;
    }
    if (ch == 3) {
      UartStr("^C\n");
      n = 0;
      repl_buf[0] = 0;
      repl_accum_len = 0;
      repl_brace = 0;
      repl_paren = 0;
      g_rl_accum_len = 0;
      g_rl_cur = 0;
      RlSeedForget;
      RlHistLeaveBrowse();
      TtyEofClear;
      break;
    }
    if (TtyIsEof(ch)) {
      RlHistLeaveBrowse();
      // Empty ^D → session EOF (TtyEofHit); non-empty submits the line.
      if (n == 0 && !repl_accum_len)
        TtyEofRaise;
      break;
    }
    if (TtyIsKill(ch)) {
      RlHistLeaveBrowse();
      n = 0;
      repl_buf[0] = 0;
      g_rl_cur = 0;
      ReplRedrawLine(repl_buf, 0);
      continue;
    }
    if (TtyIsWerase(ch)) {
      RlHistLeaveBrowse();
      // Word-erase left of cursor.
      w = TtyWeraseLen(repl_buf, cur);
      if (w > 0) {
        i = cur - w;
        while (i + w < n) {
          repl_buf[i] = repl_buf[i + w];
          i++;
        }
        n = n - w;
        repl_buf[n] = 0;
        g_rl_cur = cur - w;
        if (g_rl_cur == n)
          TtyEchoKill(w);
        else
          ReplRedrawLine(repl_buf, n);
      }
      continue;
    }
    if (TtyIsErase(ch)) {
      RlHistLeaveBrowse();
      if (cur > 0) {
        i = cur - 1;
        while (i < n - 1) {
          repl_buf[i] = repl_buf[i + 1];
          i++;
        }
        n--;
        repl_buf[n] = 0;
        g_rl_cur = cur - 1;
        if (g_rl_cur == n)
          TtyEchoErase;
        else
          ReplRedrawLine(repl_buf, n);
      }
      continue;
    }
    if (ch == '\t') {
      RlHistLeaveBrowse();
      // Tab at g_rl_cur (mid-line ok); CompCx follows completed token.
      old = n;
      kind = ReplSmartTab(repl_buf, 512, &n, 1);
      if (kind < 0)
        continue;
      if (kind == 0) {
        if (cur >= old)
          UartStr("  ");
        else
          ReplRedrawLine(repl_buf, n);
      } else if (kind == 1) {
        if (cur >= old && g_rl_cur == n && n > old) {
          i = old;
          while (i < n) {
            PutCh(repl_buf[i]);
            i++;
          }
        } else {
          ReplRedrawLine(repl_buf, n);
        }
      }
      continue;
    }
    if (ch >= 32 && ch < 127) {
      RlHistLeaveBrowse();
      if (n >= 511)
        continue;
      if (cur == n) {
        repl_buf[n] = ch;
        n++;
        repl_buf[n] = 0;
        g_rl_cur = n;
        TtyEchoCh(ch);
      } else {
        i = n;
        while (i > cur) {
          repl_buf[i] = repl_buf[i - 1];
          i--;
        }
        repl_buf[cur] = ch;
        n++;
        repl_buf[n] = 0;
        g_rl_cur = cur + 1;
        ReplRedrawLine(repl_buf, n);
      }
    }
  }
  repl_buf[n] = 0;
  g_rl_cur = n;
  if (n)
    TtyOutNl;
}

U0 ReplAccumReset()
{
  repl_accum_len = 0;
  repl_accum[0] = 0;
  repl_brace = 0;
  repl_paren = 0;
  // Avoid AOT U8* global stores here (g_rl_prompt class). Bind once in ReplMain.
  g_rl_accum_len = 0;
}

I64 ReplShouldParse(U8 *buf, I64 n, I64 brace, I64 paren)
{
  I64 i;
  if (brace || paren)
    return 0;
  if (n <= 0)
    return 0;
  if (buf[n - 1] == ';' || buf[n - 1] == '}')
    return 1;
  // #define / #undef — no trailing ';' (session DefRegister).
  i = 0;
  while (i < n && (buf[i] == ' ' || buf[i] == '\t'))
    i++;
  if (i < n && buf[i] == '#')
    return 1;
  return 0;
}
U0 ReplEvalLine(U8 *line);
U0 ReplLoop()
{
  I64 n, i;
  ReplAccumReset();
  TtyEofClear;
  while (1) {
    // Avoid g_rl_prompt = "> " — AOT U8* string-literal assigns can be bad and hang UartStr.
    if (repl_accum_len) {
      g_rl_cont = 1;
      UartStr("... ");
    } else {
      g_rl_cont = 0;
      UartStr("> ");
    }
    ReplReadLine();
    n = 0;
    while (repl_buf[n])
      n++;
    // Empty ^D: leave REPL (session EOF). Piped smokes usually timeout instead.
    if (TtyEofHit() && !n && !repl_accum_len) {
      UartStr("tty eof\n");
      break;
    }
    if (!n && !repl_accum_len)
      continue;
    // Physical-line join: keep '\n' so history stores compile units (legacy parity).
    if (repl_accum_len > 0 && repl_accum_len < 4095) {
      repl_accum[repl_accum_len] = '\n';
      repl_accum_len++;
    }
    i = 0;
    while (i < n && repl_accum_len < 4095) {
      if (repl_buf[i] == '{')
        repl_brace++;
      else if (repl_buf[i] == '}') {
        if (repl_brace > 0)
          repl_brace--;
      } else if (repl_buf[i] == '(')
        repl_paren++;
      else if (repl_buf[i] == ')') {
        if (repl_paren > 0)
          repl_paren--;
      }
      repl_accum[repl_accum_len] = repl_buf[i];
      repl_accum_len++;
      i++;
    }
    repl_accum[repl_accum_len] = 0;
    g_rl_accum_len = repl_accum_len;
    if (!ReplShouldParse(repl_buf, n, repl_brace, repl_paren))
      continue;
    // Fault / Break / Ctrl-C longjmp back here (TrapFaultRecover / TrapBreakRaise).
    g_repl_jb_ok = 1;
    if (ReplDoSetJmpHc()) {
      ReplAccumReset();
      continue;
    }
    g_repl_eval_err = 0;
    ReplEvalLine(repl_accum);
    RlHistPushUnit(repl_accum, repl_accum_len);
    // Extended cmdline: keep failed line for Left/Right/Home/End fix-up. Skip the
    // re-seed when the line we handed out only got appended to — that is a pipe,
    // not a cursor, and re-seeding it cascades one error over the whole session.
    if (g_repl_eval_err && !RlSeedWasAppended(repl_accum, repl_accum_len))
      RlSeedLine(repl_accum, repl_accum_len);
    else
      RlSeedForget;
    ReplAccumReset();
  }
}

I64 ReplMain()
{
  UartRxInit();
  SoftDbgHostSlotsClear();
  FsInit();
  // G28: plant A: soft letter so Let2Drv matches Kernel RVSoftLetPlant (no cur_dv).
  RVSoftLetPlant('A');
  // G28: plant P: as 9P/virtfs share letter (Kernel RVSoftLet9pPlant).
  RVSoftLet9pPlant('P');
  MemfsSeed();
  FsEpochSeal(FS_EPOCH_BOOT);
  JitInit();
  // RegSnapAddrFix(); // inline la@boot wedges AOT; eval RegEntry snaps per call
  TrapResolveHook = &HcTrapResolve;
  JitAdd("DumpB64", &DumpB64, 2, 1);
  JitAdd("DumpMem", &DumpMem, 3, 1);
  JitAdd("DumpFile", &DumpFile, 1, 1);
  JitAdd("DumpChanges", &DumpChanges, 1, 1);
  JitAdd("FileWrite", &FileWrite, 3, 1);
  JitAdd("Del", &Del, 1, 1);
  JitAdd("Rename", &Rename, 2, 1);
  JitAdd("Move", &Move, 2, 1);
  JitAdd("FsChanges", &FsChanges, 3, 1);
  JitAdd("FsLog", &FsLog, 1, 1);
  JitAdd("FsEpoch", &FsEpoch, 0, 0);
  JitAdd("FsCheckpoint", &FsCheckpoint, 1, 1);
  JitAdd("FsDiff", &FsDiff, 2, 1);
  JitAdd("FsReplay", &FsReplay, 1, 0);
  JitAdd("FsRecover", &FsRecover, 0, 0);
  // UART flow control (docs/UART.md, docs/FLOW_CONTROL.md) — these are the
  // documented prompt-callable surface, so they have to be in the table.
  JitAdd("UartPut", &UartPut, 1, 1);
  JitAdd("UartXonXoff", &UartXonXoff, 1, 1);
  JitAdd("UartFcGet", &UartFcGet, 0, 0);
  JitAdd("UartRtsCts", &UartRtsCts, 1, 1);
  JitAdd("UartRtsCtsGet", &UartRtsCtsGet, 0, 0);
  JitAdd("Man", &Man, 1, 1);
  JitAdd("Sections", &Sections, 0, 1);
  JitAdd("Help", &Help, 0, 1);
  JitAdd("Funs", &Funs, 1, 1);
  JitAdd("FunsList", &FunsList, 0, 1);
  JitAdd("FunsSec", &FunsSec, 1, 1);
  JitAdd("FunsS", &FunsS, 0, 1);
  JitAdd("FunSec", &FunSec, 1, 0);
  JitAdd("FunSecName", &FunSecName, 1, 0);
  JitAdd("FunCount", &FunCount, 0, 0);
  JitAdd("FunName", &FunName, 1, 0);
  JitAdd("SrcFile", &SrcFile, 1, 0);
  JitAdd("SrcText", &SrcText, 1, 0);
  JitAdd("SymFile", &SymFile, 1, 0);
  JitAdd("FnAddr", &FnAddr, 1, 0);
  JitAdd("FnSize", &FnSize, 1, 0);
  JitAdd("Print", &Print, 1, 1);
  JitAdd("Dir", &Dir, 0, 1);
  JitAdd("Cat", &Cat, 1, 1);
  // G28 UART soft letter (seed/soft_let.hc)
  JitAdd("Let2Drv", &Let2Drv, 2, 0);
  JitAdd("Let2Let", &Let2Let, 1, 0);
  JitAdd("RVSoftLetPlant", &RVSoftLetPlant, 1, 0);
  JitAdd("RVSoftLet9pPlant", &RVSoftLet9pPlant, 1, 0);
  JitAdd("SoftLetRep", &SoftLetRep, 0, 1);
  JitAdd("RVBlkDevTablesInit", &RVBlkDevTablesInit, 0, 1);
  // dmesg ring (seed/log.hc) — ≠ Print, ≠ FsLog; ts prefers MEM_RTC / LogNow
  JitAdd("Log", &Log, 3, 1);
  JitAdd("LogInfo", &LogInfo, 2, 1);
  JitAdd("LogWarn", &LogWarn, 2, 1);
  JitAdd("LogErr", &LogErr, 2, 1);
  JitAdd("LogClear", &LogClear, 0, 1);
  JitAdd("LogInit", &LogInit, 0, 1);
  JitAdd("LogCount", &LogCount, 0, 0);
  JitAdd("LogNow", &LogNow, 0, 0);
  JitAdd("DMesg", &DMesg, 1, 1);
  JitAdd("SysInit", &SysInit, 0, 1);
  JitAdd("Sys", &Sys, 0, 1);
  // Interruptible busy eval (seed/sys.hc). The thin JitTry has no toplevel
  // while/for and growing it into one is out of bounds, so the Ctrl-C smoke
  // spins here instead of at the prompt.
  JitAdd("Spin", &Spin, 1, 0);
  JitAdd("SysHelp", &SysHelp, 0, 1);
  JitAdd("Uptime", &Uptime, 0, 1);
  JitAdd("UptimeTicks", &UptimeTicks, 0, 0);
  JitAdd("UptimeSecs", &UptimeSecs, 0, 0);
  JitAdd("MemRep", &MemRep, 0, 1);
  JitAdd("IrqRep", &IrqRep, 0, 1);
  JitAdd("DevRep", &DevRep, 0, 1);
  JitAdd("Cnts", &Cnts, 0, 1);
  JitAdd("TtyInit", &TtyInit, 0, 1);
  JitAdd("Tty", &Tty, 0, 1);
  JitAdd("TtyHelp", &TtyHelp, 0, 1);
  JitAdd("TtyCanon", &TtyCanon, 0, 1);
  JitAdd("TtyRaw", &TtyRaw, 0, 1);
  JitAdd("TtyModeGet", &TtyModeGet, 0, 0);
  JitAdd("TtyIsCanon", &TtyIsCanon, 0, 0);
  JitAdd("TtyIsRaw", &TtyIsRaw, 0, 0);
  JitAdd("TtyEcho", &TtyEcho, 1, 1);
  JitAdd("TtyEchoGet", &TtyEchoGet, 0, 0);
  JitAdd("TtyIcrnl", &TtyIcrnl, 1, 1);
  JitAdd("TtyIcrnlGet", &TtyIcrnlGet, 0, 0);
  JitAdd("TtyMapIn", &TtyMapIn, 1, 0);
  JitAdd("TtyIsErase", &TtyIsErase, 1, 0);
  JitAdd("TtyIsKill", &TtyIsKill, 1, 0);
  JitAdd("TtyIsWerase", &TtyIsWerase, 1, 0);
  JitAdd("TtyIsEof", &TtyIsEof, 1, 0);
  JitAdd("TtyOnlcr", &TtyOnlcr, 1, 1);
  JitAdd("TtyOnlcrGet", &TtyOnlcrGet, 0, 0);
  JitAdd("TtyEofHit", &TtyEofHit, 0, 0);
  JitAdd("TtyEofClear", &TtyEofClear, 0, 1);
  JitAdd("TtyEofRaise", &TtyEofRaise, 0, 1);
  // frame.hc (G22 framed multi-channel UART). #include'd into this image since it
  // was written, but never published to the JIT — so UartMuxOn read as
  // "unknown fun" and the framed half of the console stack was unreachable from
  // the prompt. tools/uart_mux.py's --vt-split/--vt-panes want these.
  JitAdd("UartMuxOn", &UartMuxOn, 0, 1);
  JitAdd("UartMuxOff", &UartMuxOff, 0, 1);
  JitAdd("UartMuxGet", &UartMuxGet, 0, 0);
  JitAdd("FramePutStr", &FramePutStr, 2, 1);
  JitAdd("VtInit", &VtInit, 0, 1);
  JitAdd("Vt", &Vt, 1, 1);
  JitAdd("VtAttach", &VtAttach, 1, 1);
  JitAdd("VtNext", &VtNext, 0, 1);
  JitAdd("VtPrev", &VtPrev, 0, 1);
  JitAdd("VtCur", &VtCur, 0, 0);
  JitAdd("VtCount", &VtCount, 0, 0);
  JitAdd("VtList", &VtList, 0, 1);
  JitAdd("VtPutStr", &VtPutStr, 1, 1);
  JitAdd("VtTitle", &VtTitle, 1, 1);
  JitAdd("VtClear", &VtClear, 0, 1);
  JitAdd("VtDetach", &VtDetach, 0, 1);
  JitAdd("VtCapture", &VtCapture, 1, 1);
  JitAdd("VtCaptureGet", &VtCaptureGet, 0, 0);
  JitAdd("VtKeys", &VtKeys, 1, 1);
  JitAdd("VtKeysGet", &VtKeysGet, 0, 0);
  JitAdd("VtPane", &VtPane, 2, 1);
  JitAdd("VtPaneOff", &VtPaneOff, 0, 1);
  JitAdd("VtPaneA", &VtPaneA, 0, 0);
  JitAdd("VtPaneB", &VtPaneB, 0, 0);
  JitAdd("VtHelp", &VtHelp, 0, 1);
  // CONSOLE #11 — Term* (seed/term.hc); smoke TermSize/TermNameAnsi/TermRep
  JitAdd("TermInit", &TermInit, 0, 1);
  JitAdd("TermSize", &TermSize, 2, 1);
  JitAdd("TermSetSize", &TermSetSize, 2, 1);
  JitAdd("TermRows", &TermRows, 0, 0);
  JitAdd("TermCols", &TermCols, 0, 0);
  JitAdd("TermFlags", &TermFlags, 0, 0);
  JitAdd("TermName", &TermName, 0, 0);
  JitAdd("TermNameAnsi", &TermNameAnsi, 0, 1);
  JitAdd("TermNameXterm", &TermNameXterm, 0, 1);
  JitAdd("TermRep", &TermRep, 0, 1);
  JitAdd("TermHelp", &TermHelp, 0, 1);
  JitAdd("TermProbe", &TermProbe, 0, 0);
  JitAdd("TermQuery", &TermQuery, 0, 0);
  // REPL_FUNS.md DolDoc→ANSI rows: real SGR behind $$FG/$$BG/$$IV/$$UL/$$BK/$$FD/$$BD.
  JitAdd("TermColor", &TermColor, 1, 1);
  JitAdd("TermColorGet", &TermColorGet, 0, 0);
  JitAdd("TermColorOk", &TermColorOk, 0, 0);
  JitAdd("TermSgr", &TermSgr, 1, 1);
  JitAdd("TermSgrColor", &TermSgrColor, 1, 0);
  JitAdd("TermFg", &TermFg, 1, 1);
  JitAdd("TermBg", &TermBg, 1, 1);
  JitAdd("TermFgDft", &TermFgDft, 0, 1);
  JitAdd("TermBgDft", &TermBgDft, 0, 1);
  JitAdd("TermInverse", &TermInverse, 1, 1);
  JitAdd("TermUnderline", &TermUnderline, 1, 1);
  JitAdd("TermBlink", &TermBlink, 1, 1);
  JitAdd("TermBold", &TermBold, 1, 1);
  JitAdd("TermAttrOff", &TermAttrOff, 0, 1);
  JitAdd("TermColorDemo", &TermColorDemo, 0, 1);
  JitAdd("SrcFileRep", &SrcFileRep, 1, 1);
  JitAdd("FnSizeRep", &FnSizeRep, 1, 1);
  g_callers_hc = &CallersScanJit;
  JitAdd("Regs", &Regs, 0, 1);
  JitAdd("Reg", &Reg, 1, 0);
  JitAdd("CsrExplain", &CsrExplain, 1, 0);
  JitAdd("CsrDecodeVal", &CsrDecodeVal, 2, 1);
  JitAdd("CsrDecodeMstatus", &CsrDecodeMstatus, 1, 1);
  JitAdd("CsrDecodeMcause", &CsrDecodeMcause, 1, 1);
  JitAdd("McauseCauseName", &McauseCauseName, 1, 0);
  JitAdd("McausePrint", &McausePrint, 1, 1);
  JitAdd("Dr", &Dr, 0, 1);
  JitAdd("MemMap", &MemMap, 0, 1);
  JitAdd("MemMapDrv", &MemMapDrv, 0, 1);
  JitAdd("MemMapFind", &MemMapFind, 1, 0);
  JitAdd("RegHelp", &RegHelp, 0, 1);
  JitAdd("Bt", &Bt, 0, 1);
  JitAdd("StkRep", &StkRep, 0, 1);
  JitAdd("Callers", &Callers, 1, 1);
  JitAdd("WhoCalls", &WhoCalls, 1, 1);
  JitAdd("CallerCnt", &CallerCnt, 0, 0);
  JitAdd("DbgHelp", &DbgHelp, 0, 1);
  JitAdd("TrapDump", &TrapDump, 0, 1);
  JitAdd("CrashDump", &CrashDump, 0, 1);
  JitAdd("CrashMon", &CrashMon, 0, 1);
  JitAdd("CrashHelp", &CrashHelp, 0, 1);
  JitAdd("CrashOnTrap", &CrashOnTrap, 3, 0);
  JitAdd("ZapTrap", &ZapTrap, 3, 0);
  JitAdd("Md", &Md, 2, 1);
  JitAdd("Mw", &Mw, 2, 1);
  // seed/disasm.hc: U/Uf/UA — see ReplUCnt for the n=28 default.
  JitAdd("U", &ReplU, 2, 1);
  JitAdd("Uf", &ReplUf, 1, 1);
  JitAdd("Disasm", &ReplUf, 1, 1);
  JitAdd("DisasmAt", &DisasmAt, 3, 1);
  JitAdd("UA", &ReplUA, 2, 1);
  JitAdd("UAsm", &ReplUA, 2, 1);
  // seed/home_wrappers.hc: stock ~/HomeWrappers command line.
  JitAdd("F", &F, 1, 0);
  JitAdd("FD", &FD, 1, 0);
  JitAdd("R", &R, 2, 0);
  JitAdd("RD", &RD, 2, 0);
  // seed/ninep.hc / seed/gdbstub.hc are AOT-#included above, but jit_funs only has
  // JIT_FUN_MAX(256) - ~224 boot slots left for the session's own definitions, so
  // publish just the documented entry points (NINEP.md / DEBUGGER.md) here. The rest
  // of Ninep*/Gdb* stays callable from AOT code and readable via Src/Cat.
  JitAdd("Mount9p", &Mount9p, 2, 0);
  JitAdd("NineExport", &NineExport, 1, 0);
  JitAdd("NinepSmoke", &NinepSmoke, 0, 0);
  JitAdd("GdbStub", &GdbStub, 0, 1);
  JitAdd("GdbHelp", &GdbHelp, 0, 1);
  JitAdd("RegsRestoreDemo", &RegsRestoreDemo, 0, 1);
  JitAdd("Ed", &Ed, 1, 1);
  JitAdd("EdHoly", &EdHoly, 1, 1);
  JitAdd("Vi", &Vi, 1, 1);
  JitAdd("Edit", &Edit, 1, 1);
  JitAdd("EditHoly", &EditHoly, 1, 1);
  JitAdd("Run", &Run, 1, 1);
  JitAdd("Src", &Src, 1, 1);
  editor = &Vi;
  JitAdd("CompCollectSyms", &CompCollectSyms, 2, 0);
  JitAdd("CompCollectFiles", &CompCollectFiles, 2, 0);
  JitAdd("CompCollectAsm", &CompCollectAsm, 3, 0);
  JitAdd("CompMidDemo", &CompMidDemo, 0, 1);
  JitAdd("CompAsmDemo", &CompAsmDemo, 0, 1);
  JitAdd("AsmDoc", &AsmDoc, 1, 1);
  JitAdd("AsmList", &AsmList, 0, 1);
  JitAdd("AsmDocHelp", &AsmDocHelp, 0, 1);
  JitAdd("RlMidDemo", &RlMidDemo, 0, 1);
  JitAdd("TrapInit", &TrapInit, 0, 1);
  JitAdd("TrapInitOnce", &TrapInitOnce, 0, 1);
  JitAdd("SetTrap", &SetTrap, 1, 1);
  JitAdd("SetTrapFn", &SetTrapFn, 1, 1);
  JitAdd("Fault", &Fault, 0, 1);
  JitAdd("Break", &Break, 0, 1);
  JitAdd("Ecall", &Ecall, 0, 1);
  JitAdd("TimerArm", &TimerArm, 1, 1);
  JitAdd("BreakArm", &BreakArm, 0, 1);
  JitAdd("BreakDisarm", &BreakDisarm, 0, 1);
  JitAdd("OnTrap", &OnTrap, 3, 0);
  // SiFive test finisher @ MEM_TEST (QEMU virt): Quit/Exit/PowerOff=PASS,
  // Fail=FAIL, HardReset=RESET; soft Reset=Boot re-entry; Halt=wfi park.
  JitAdd("TestFinisher", &TestFinisher, 1, 1);
  JitAdd("Quit", &Quit, 0, 1);
  JitAdd("Exit", &Exit, 0, 1);
  JitAdd("PowerOff", &PowerOff, 0, 1);
  JitAdd("Fail", &Fail, 0, 1);
  JitAdd("Reset", &Reset, 0, 1);
  JitAdd("HardReset", &HardReset, 0, 1);
  JitAdd("Halt", &Halt, 0, 1);
  TrapUartSoftDrain = &HcTrapUartSoftDrain;
  // G2: TrapInitOnce on Fault/Break/SetTrap/BreakArm — not at boot (mtvec wedge).
  // CONSOLE #9: bind CrashOnTrap by fn ptr (no mtvec); TrapInit keeps it if g_trap_fn set.
  SetTrapFn(&CrashOnTrap);
  TrapVecAddrFix();
  // This is an interactive session, so say so: ExePutS gates BreakArm on this
  // flag, and only TrapInit used to set it — which boot never reaches. Without
  // it Ctrl-C could not interrupt a running eval at all. Still no mtvec swap
  // here: the first ExePutS → BreakArm → TrapInitOnce installs it at eval time.
  g_break_interactive = 1;
  UartRxBootstrap();
  pc = g_trap_vec;
  g_exepubs_n = 0;
  LogInit;
  SysInit;
  TtyInit;
  TermInit;
  VtInit;
  LogInfo("boot", "repl-holyc ready");
  LogWarn("boot", "uart mux ch3 pending");
  LogInfo("smoke", "dmesg-ring");
  LogWarn("smoke", "warn-needle");
  LogErr("smoke", "err-needle");
  UartStr("\n");
  UartStr("A2: ExePutS owns compile loop\n");
  UartStr("A2: bridge→Jit (Cmp=make repl-cmp / build/repl-cmp.elf)\n");
  UartStr("G2: HolyC TrapDispatch + Ctrl-C Break\n");
  UartStr("G5: Tab=complete/indent  Up/Down=history\n");
  // Slot budget in the boot banner: the next lane to AOT-#include a seed sees
  // the headroom before it runs out, not after (JitAdd also shouts on overrun).
  "JIT: %d/%d fun slots used (%d free)\n", jit_nfun, JIT_FUN_MAX, JIT_FUN_MAX - jit_nfun;
  UartStr("Crash: Fault → dump → crash> (go|regs|md|mw|bt|reboot)\n");
  Help();
  // Boot /proc-ish dump (smoke needles; also useful UART inventory)
  Sys;
  Tty;
  VtList;
  UartStr("Try: Dir;  Fault;  MemMap;  Regs;  Sys;  Tty;  VtList;  Man(\"CrashMon\");  DMesg;\n\n");
  // G3: pull piped regression stdin into soft ring once boot paint is done.
  UartRxBootstrap();
  RlHistSeed();
  g_rl_accum_len = 0;
  ReplLoop();
  return 0;
}
