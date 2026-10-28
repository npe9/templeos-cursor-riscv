// UART 16550 -- HolyC driver (@ MEM_UART from MemMapSelected.hc / Kconfig).
// RX ring is still shared with the C IRQ/readline bootstrap (pointers published
// at MEM_HOST_SLOTS+0x20..038) until the ring moves fully into HolyC BSS. Drain/get are
// HolyC MMIO — no C funptr slots (was MEM_HOST_SLOTS+0x88 / MEM_HOST_SLOTS+0xB0).
// Software XON/XOFF (Ctrl-Q/Ctrl-S): state at MEM_HOST_SLOTS+0xF0 (fc) / MEM_HOST_SLOTS+0xF8
// (tx paused), shared with C uart_hw_drain so IRQ and Put stay in sync.
// Layout: keep LSR wait ending on a lone `;` so smoke `Na` inserts before THR
// store (see run_repl_smoke.sh livedrv — currently line 150 after --fmt).
// MEM_UART comes from MemMapSelected.hc (boot first; syncconfig regenerates it).
#define UART_LSR_OFF 5
#define UART_LSR_DR 0x01
#define UART_LSR_THRE 0x20
#define UART_CH_CTRLC 3
#define UART_XON 0x11
#define UART_XOFF 0x13
#define UART_FC_ADDR MEM_HOST_SLOTS+0xF0
#define UART_TX_PAUSED_ADDR MEM_HOST_SLOTS+0xF8
// Default on at load (C HostSlotsInstall seeds 0 until this Run; then on).
// CI PTY smokes must clear host IXON or boot floods freeze Put — see FLOW_CONTROL.md.
*(I64 *)UART_FC_ADDR = 1;
*(I64 *)UART_TX_PAUSED_ADDR = 0;
// Framed multi-channel UART (frame.hc). Default off — raw REPL / Print.
I64 g_uart_mux;
// Optional PutCh post-hook (console.hc VtCapture). FrameSend uses UartPut — bypasses.
U0 (*g_uart_putc_hook)(I64 ch);
// UartFcGet -- UartFcGet()
// NAME
//   UartFcGet - 1 if software XON/XOFF flow control is enabled
I64 UartFcGet()
{
  return *(I64 *)UART_FC_ADDR;
}
// UartXonXoff -- UartXonXoff(1)
// NAME
//   UartXonXoff - enable (1) or disable (0) software XON/XOFF on UART TX
// SYNOPSIS
//   U0 UartXonXoff(I64 on);
// DESCRIPTION
//   When on, host Ctrl-S (XOFF) pauses UartPut until Ctrl-Q (XON). XON/XOFF
//   are consumed in the drain path (not delivered to readline). Off for binary
//   protocols (ZMODEM / trzsz). Independent of UartRtsCts (HW stub).
// EXAMPLES
//   UartXonXoff(1);  DumpFile("boot.hc");
//   UartXonXoff(0);  // before ZmodemSend
U0 UartXonXoff(I64 on)
{
  *(I64 *)UART_FC_ADDR = on != 0;
  if (!on)
    *(I64 *)UART_TX_PAUSED_ADDR = 0;
}
// Soft intent flag only — QEMU virt + stdio/PTY do not wire RTS/CTS (MCR/MSR
// exist; chardev TIOCM unsupported). UartPut never waits on MSR.CTS.
I64 UartHwFc = 0;
// UartRtsCtsGet -- UartRtsCtsGet()
// NAME
//   UartRtsCtsGet - 1 if RTS/CTS hardware FC was requested (no-op on virt)
I64 UartRtsCtsGet()
{
  return UartHwFc;
}
// UartRtsCts -- UartRtsCts(1)
// NAME
//   UartRtsCts - request RTS/CTS hardware flow control (stub on virt)
// SYNOPSIS
//   U0 UartRtsCts(I64 on);
// DESCRIPTION
//   Records HW FC intent. On QEMU virt (stdio/PTY) this is a soft no-op:
//   guest MCR/MSR are readable but host chardev ignores modem lines, so
//   UartPut does not gate on CTS. Does not disable or alter UartXonXoff.
//   Real boards with wired RTS/CTS need a future driver path.
// EXAMPLES
//   UartRtsCts(1);  // no-op on virt; flag only
//   UartRtsCts(0);
U0 UartRtsCts(I64 on)
{
  UartHwFc = on != 0;
}

U0 UartFcNote(I64 ch)
{
  if (!*(I64 *)UART_FC_ADDR)
    return;
  if (ch == UART_XOFF)
    *(I64 *)UART_TX_PAUSED_ADDR = 1;
  else if (ch == UART_XON)
    *(I64 *)UART_TX_PAUSED_ADDR = 0;
}

I64 UartFcIsCtrl(I64 ch)
{
  if (!*(I64 *)UART_FC_ADDR)
    return 0;
  if (ch == UART_XON || ch == UART_XOFF)
    return 1;
  return 0;
}
// UartRxDrain -- UartRxDrain()
// NAME
//   UartRxDrain - pull 16550 RX FIFO into the shared ring (MIE masked)
// SYNOPSIS
//   U0 UartRxDrain();
// DESCRIPTION
//   Same race fix as the old C uart_hw_drain: PUSHFD/CLI … POPFD so nested
//   IRQs cannot enqueue a duplicate byte during the LSR→RBR loop. Enqueues
//   into the published ring (IRQ path may still drain too). With UartFc on,
//   XON/XOFF update the shared pause flag and are not enqueued.
//   Uses HolyC CLI/STI-family intrinsics (not asm{} :: exports) so boot does
//   not depend on secondary-label exe_addr / IC_CALL_INDIRECT2.
// SEE ALSO
//   UartPut  UartXonXoff  UartTryGetByte  TermKeyGet
U0 UartRxDrain()
{
  I64 ch, n, rx, rhp, rtp, cap, rh, rt;
  PUSHFD;
  CLI;
  rx = *(I64 *)MEM_HOST_SLOTS + 0x20;
  rhp = *(I64 *)MEM_HOST_SLOTS + 0x28;
  rtp = *(I64 *)MEM_HOST_SLOTS + 0x30;
  cap = *(I64 *)MEM_HOST_SLOTS + 0x38;
  if (rx && rhp && rtp && cap >= 2) {
    while (*(U8 *)(MEM_UART + UART_LSR_OFF) & UART_LSR_DR) {
      ch = *(U8 *)MEM_UART;
      if (UartFcIsCtrl(ch)) {
        UartFcNote(ch);
      } else {
        rh = *(I64 *)rhp;
        rt = *(I64 *)rtp;
        n = (rh + 1) & (cap - 1);
        if (n == rt)
          break;
        *(U8 *)(rx + rh) = ch;
        *(I64 *)rhp = n;
      }
    }
  } else {
    while (*(U8 *)(MEM_UART + UART_LSR_OFF) & UART_LSR_DR) {
      ch = *(U8 *)MEM_UART;
      if (UartFcIsCtrl(ch))
        UartFcNote(ch);
    }
  }
  POPFD;
}

U0 UartPut(I64 ch)
{
  UartRxDrain();
  while (*(I64 *)UART_FC_ADDR && *(I64 *)UART_TX_PAUSED_ADDR)
    UartRxDrain();
  // livedrv smoke inserts uppercase before THR poke (see run_repl_smoke.sh)
  while (!(*(U8 *)(MEM_UART + UART_LSR_OFF) & UART_LSR_THRE))
    ;
  *(U8 *)MEM_UART = ch;
}

U0 PutCh(I64 ch)
{
  UartPut(ch);
  if (g_uart_putc_hook)
    (*g_uart_putc_hook)(ch);
}

U0 UartStr(U8 *s)
{
  if (!s)
    return;
  while (*s)
    PutCh (*s++);
}

U0 PutS(U8 *s)
{
  UartStr(s);
}
// HcUartGet -- blocking byte from shared ring, else 16550 MMIO (repl-holyc)
I64 HcUartGet()
{
  I64 ch, rx, rhp, rtp, cap, rh, rt;
  while (1) {
    UartRxDrain();
    rx = *(I64 *)MEM_HOST_SLOTS + 0x20;
    rhp = *(I64 *)MEM_HOST_SLOTS + 0x28;
    rtp = *(I64 *)MEM_HOST_SLOTS + 0x30;
    cap = *(I64 *)MEM_HOST_SLOTS + 0x38;
    if (!rx || !rhp || !rtp || cap < 2) {
      while (!(*(U8 *)(MEM_UART + UART_LSR_OFF) & UART_LSR_DR))
        ;
      ch = *(U8 *)MEM_UART;
      if (UartFcIsCtrl(ch)) {
        UartFcNote(ch);
        continue;
      }
      return ch;
    }
    rh = *(I64 *)rhp;
    rt = *(I64 *)rtp;
    if (rh == rt)
      continue;
    ch = *(U8 *)(rx + rt);
    *(I64 *)rtp = (rt + 1) & (cap - 1);
    if (UartFcIsCtrl(ch)) {
      UartFcNote(ch);
      continue;
    }
    return ch;
  }
  return 0;
}
// HcTermKeyGet -- repair hatch to C TermKeyGet (slot 0xD0); TermKeyGetC uses this.
I64 HcTermKeyGet()
{
  I64 (*get)();
  get = *(I64 *)MEM_HOST_SLOTS + 0xD0;
  if (!get)
    return 0;
  return get();
}
