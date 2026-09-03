// RVWinSerial.HC — UART TTY beside FB/WinMgr (BOARD_FB dual-console).
// VirtioInput owns the graphical Term; serial stays a live dig-down console.
// Soft RX (RVUartSoftOn) + polled drain in RVWinMgrRun. Crash mon via
// RVCrashMonInit (host trap → UART crash>). Prefer serial-always-TTY over VT mux.
#define RV_WIN_SERIAL_LINE_MAX 160
I64 rv_win_serial_ready;
I64 rv_win_serial_cmds;
I64 rv_win_serial_len;
U8 rv_win_serial_line[RV_WIN_SERIAL_LINE_MAX];
I64 (*RVWinSerialEval)(U8 *line);
asm {
	RVWinCsrrMstatus::
	csrr	a0, 0x300
	ret
	RVWinCsrrMie::
	csrr	a0, 0x304
	ret
	RVWinCsrrMip::
	csrr	a0, 0x344
	ret
	RVWinCsrrMepc::
	csrr	a0, 0x341
	ret
	RVWinCsrrMcause::
	csrr	a0, 0x342
	ret
	RVWinCsrrMtval::
	csrr	a0, 0x343
	ret
	RVWinSerialFaultAsm::
	.word	0
	ret
}

I64 RVWinSerialCmdEq(U8 *line, U8 *cmd)
{
  I64 i;
  if (!line || !cmd)
    return 0;
  i = 0;
  while (cmd[i] && line[i] == cmd[i])
    i++;
  if (cmd[i])
    return 0;
  return !line[i] || line[i] == ' ' || line[i] == '\t' || line[i] == ';';
}

U8 *RVWinSerialSkip(U8 *p)
{
  if (!p)
    return p;
  while (*p == ' ' || *p == '\t')
    p++;
  return p;
}

U8 *RVWinSerialSkipTok(U8 *p)
{
  p = RVWinSerialSkip(p);
  while (*p && *p != ' ' && *p != '\t')
    p++;
  return RVWinSerialSkip(p);
}

I64 RVWinSerialInRam(I64 a)
{
  return a >= 0x80000000 && a < 0x88000000;
}

U0 RVWinSerialHelp()
{
  Print("RVWinSerial — UART TTY while WinMgr/FB runs (docs/CONSOLE.md, BOARD_FB.md)\n");
  Print("  help / ?     this sheet\n");
  Print("  regs         CSR dig-down (mstatus/mie/mip/mepc/mcause/mtval)\n");
  Print("  bt           stack walk from SP (code ptrs in DRAM)\n");
  Print("  md ADDR [N]  hex dump DRAM (default 64 bytes)\n");
  Print("  mw ADDR VAL  store I64 in DRAM\n");
  Print("  fault        deliberate illegal insn → UART crash>\n");
  Print("  crash        enter UART crash> monitor now\n");
  Print("  q / quit     quit WinMgr (same as ESC on virtio-kbd)\n");
  Print("Virtio-kbd/tablet stay on the graphical Term; type here on -serial.\n");
  Print("Full HolyC ExePutS REPL: repl-holyc / A2 kernel_repl_exepubs (not this ELF).\n");
}

U0 RVWinSerialRegs()
{
  Print("regs mstatus=0x%X mie=0x%X mip=0x%X\n", RVWinCsrrMstatus(), RVWinCsrrMie(), RVWinCsrrMip());
  Print("     mepc=0x%X mcause=0x%X mtval=0x%X sp=0x%X\n", RVWinCsrrMepc(), RVWinCsrrMcause(), RVWinCsrrMtval(), GetRSP());
  Print("(Fault snap: UART crash> after RVCrashMonInit + fault.)\n");
}

U0 RVWinSerialBt(I64 max = 16)
{
  I64 sp, i, a, n;
  if (max <= 0)
    max = 16;
  if (max > 32)
    max = 32;
  sp = GetRSP();
  Print("bt sp=0x%X\n", sp);
  n = 0;
  for (i = 0; i < 64 && n < max; i++) {
    a = *(I64 *)(sp + i * 8);
    if (!RVWinSerialInRam(a))
      continue;
    if (a & 1)
      continue;
    // RV compressed can be any even; prefer 0x80xxxxxx kernel/blob range
    Print("  #%d 0x%X\n", n, a);
    n++;
  }
  if (!n)
    Print("  (empty)\n");
}

U0 RVWinSerialMd(I64 addr, I64 n = 64)
{
  I64 i, b;
  if (!RVWinSerialInRam(addr) || n <= 0) {
    Print("md: bad addr/len (DRAM 0x80000000..0x88000000)\n");
    return;
  }
  if (n > 0x1000)
    n = 0x1000;
  for (i = 0; i < n; i++) {
    if ((i & 15) == 0)
      Print("%08X:", addr + i);
    b = *(U8 *)(addr + i);
    Print(" %02X", b);
    if ((i & 15) == 15)
      Print("\n");
  }
  if (n & 15)
    Print("\n");
}

U0 RVWinSerialMw(I64 addr, I64 val)
{
  if (!RVWinSerialInRam(addr)) {
    Print("mw: bad addr (DRAM only)\n");
    return;
  }
  *(I64 *)addr = val;
  Print("mw *0x%X = 0x%X\n", addr, val);
}

U0 RVWinSerialFault()
{
  Print("RVWinSerial: deliberate fault → UART crash>\n");
  RVWinSerialFaultAsm();
}

U0 RVWinSerialPrompt()
{
  Print("> ");
}

Bool RVWinSerialDispatch(U8 *line)
{
  U8 *p, *q;
  I64 addr, n, val, r;
  if (!line)
    return FALSE;
  p = RVWinSerialSkip(line);
  if (!*p)
    return FALSE;
  rv_win_serial_cmds++;
  if (RVWinSerialCmdEq(p, "help") || RVWinSerialCmdEq(p, "?")) {
    RVWinSerialHelp;
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "regs")) {
    RVWinSerialRegs;
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "bt")) {
    RVWinSerialBt;
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "md")) {
    q = RVWinSerialSkipTok(p);
    addr = Str2I64(q);
    q = RVWinSerialSkipTok(q);
    n = 64;
    if (*q)
      n = Str2I64(q);
    RVWinSerialMd(addr, n);
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "mw")) {
    q = RVWinSerialSkipTok(p);
    addr = Str2I64(q);
    q = RVWinSerialSkipTok(q);
    val = Str2I64(q);
    RVWinSerialMw(addr, val);
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "fault")) {
    RVWinSerialFault;
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "crash")) {
    Print("RVWinSerial: entering crash> (host mon; 'go' returns)\n");
    RVCrashMon();
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "q") || RVWinSerialCmdEq(p, "quit")) {
    rv_winmgr.want_quit = TRUE;
    Print("RVWinSerial: quit WinMgr\n");
    return TRUE;
  }
  if (RVWinSerialEval) {
    r = RVWinSerialEval(p);
    Print("ans=%d\n", r);
    return FALSE;
  }
  Print("?\n");
  return FALSE;
}

U0 RVWinSerialPutEcho(I64 ch)
{
  U8 e[2];
  e[0] = ch;
  e[1] = 0;
  RVUartPutS(e);
}

U0 RVWinSerialPoll()
{
  I64 ch;
  if (!rv_win_serial_ready)
    return;
  while (TRUE) {
    ch = RVUartTryGet;
    if (ch < 0)
      break;
    if (ch == '\r' || ch == '\n') {
      RVUartPutS("\n");
      rv_win_serial_line[rv_win_serial_len] = 0;
      RVWinSerialDispatch(rv_win_serial_line);
      rv_win_serial_len = 0;
      if (!rv_winmgr.want_quit)
        RVWinSerialPrompt;
      continue;
    }
    if (ch == 3) {
      rv_win_serial_len = 0;
      RVUartPutS("^C\n");
      RVWinSerialPrompt;
      continue;
    }
    if (ch == 8 || ch == 127) {
      if (rv_win_serial_len > 0) {
        rv_win_serial_len--;
        RVUartPutS("\b \b");
      }
      continue;
    }
    if (ch >= 32 && ch < 127 && rv_win_serial_len < RV_WIN_SERIAL_LINE_MAX - 1) {
      rv_win_serial_line[rv_win_serial_len++] = ch;
      RVWinSerialPutEcho(ch);
    }
  }
}

Bool RVWinSerialInit()
{
  if (rv_win_serial_ready)
    return TRUE;
  RVUartSoftOn(1);
  RVTrapInit();
  RVCrashMonInit();
  rv_win_serial_ready = TRUE;
  rv_win_serial_len = 0;
  rv_win_serial_cmds = 0;
  Print("RVWinSerial ready soft=%d crash_mon=1 (help; regs; bt; fault; q)\n", RVUartSoftGet);
  RVWinSerialPrompt;
  return TRUE;
}
