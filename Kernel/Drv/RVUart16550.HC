// NS16550A UART (QEMU virt / DW8250-class). Selected via RVUartSelected.HH.
// CONFIG_UART_REG_SHIFT: 0 = byte regs (virt), 2 = word-spaced (JH7110 /
// Xiangshan / Icicle). Word-spaced maps often ignore byte MMIO — use U32
// in/out when shift >= 2 so THRE waits see real LSR.
// Software XON/XOFF (RVUartXonXoff): host Ctrl-S pauses PutS until Ctrl-Q.
// RTS/CTS: RVUartRtsCts soft stub — no-op on QEMU virt (stdio/PTY ignore
// modem lines). Soft RX ring (RVUartSoftOn): FC poll + WinMgr serial TTY keep
// keys; without the ring, non-FC RX during PutS FC poll is dropped.
#ifndef CONFIG_UART_REG_SHIFT
#define CONFIG_UART_REG_SHIFT 0
#endif
#define RV_UART_XON  0x11
#define RV_UART_XOFF 0x13
#define RV_UART_SOFT_CAP 256
I64 RVUartFc = 1;
I64 RVUartTxPaused = 0;
I64 RVUartHwFc = 0;
I64 RVUartSoft = 0;
U8 RVUartSoftRx[RV_UART_SOFT_CAP];
I64 RVUartSoftHead = 0;
I64 RVUartSoftTail = 0;
U8 *RVUartReg(I64 idx)
{
  return CONFIG_UART_BASE + (idx << CONFIG_UART_REG_SHIFT);
}

U32 RVUartIn(I64 idx)
{
  if (CONFIG_UART_REG_SHIFT >= 2)
    return *(U32 *)(CONFIG_UART_BASE + (idx << CONFIG_UART_REG_SHIFT));
  return *(U8 *)(CONFIG_UART_BASE + idx);
}

U0 RVUartOut(I64 idx, U32 v)
{
  if (CONFIG_UART_REG_SHIFT >= 2)
    *(U32 *)(CONFIG_UART_BASE + (idx << CONFIG_UART_REG_SHIFT)) = v;
  else
    *(U8 *)(CONFIG_UART_BASE + idx) = v;
}

U0 RVUartInit()
{
}

U0 RVUartXonXoff(I64 on)
{
  RVUartFc = on != 0;
  if (!on)
    RVUartTxPaused = 0;
}

I64 RVUartRtsCtsGet()
{
  return RVUartHwFc;
}
// Soft stub: records HW FC intent. Does not wait on MSR.CTS in PutS (virt
// chardev has no usable RTS/CTS). Independent of RVUartXonXoff.
U0 RVUartRtsCts(I64 on)
{
  RVUartHwFc = on != 0;
}

U0 RVUartSoftOn(I64 on = 1)
{
  RVUartSoft = on != 0;
  if (!on) {
    RVUartSoftHead = 0;
    RVUartSoftTail = 0;
  }
}

I64 RVUartSoftGet()
{
  return RVUartSoft;
}

U0 RVUartSoftEnqueue(I64 ch)
{
  I64 nh;
  nh = (RVUartSoftHead + 1) & (RV_UART_SOFT_CAP - 1);
  if (nh == RVUartSoftTail)
    return;
  RVUartSoftRx[RVUartSoftHead] = ch;
  RVUartSoftHead = nh;
}

U0 RVUartRxDrain()
{
  I64 ch;
  while (RVUartIn(5) & 1) {
    ch = RVUartIn(0) & 0xFF;
    if (RVUartFc) {
      if (ch == RV_UART_XOFF) {
        RVUartTxPaused = 1;
        continue;
      }
      if (ch == RV_UART_XON) {
        RVUartTxPaused = 0;
        continue;
      }
    }
    if (RVUartSoft)
      RVUartSoftEnqueue(ch);
  }
}

U0 RVUartFcPoll()
{
  I64 ch;
  if (!RVUartFc && !RVUartSoft)
    return;
  while (RVUartIn(5) & 1) {
    ch = RVUartIn(0) & 0xFF;
    if (RVUartFc) {
      if (ch == RV_UART_XOFF) {
        RVUartTxPaused = 1;
        continue;
      }
      if (ch == RV_UART_XON) {
        RVUartTxPaused = 0;
        continue;
      }
    }
    if (RVUartSoft)
      RVUartSoftEnqueue(ch);
  }
}

Bool RVUartPutS(U8 *st)
{
  while (*st) {
    RVUartFcPoll;
    while (RVUartFc && RVUartTxPaused)
      RVUartFcPoll;
    while (!(RVUartIn(5) & 0x20))
      ;
    // THRE
    RVUartOut(0, *st++);
  }
  return TRUE;
}

Bool RVUartDataReady()
{
  if (RVUartSoft && RVUartSoftHead != RVUartSoftTail)
    return TRUE;
  return (RVUartIn(5) & 1) != 0;
}

I64 RVUartTryGet()
{
  I64 ch, nt;
  if (RVUartSoft) {
    RVUartRxDrain;
    if (RVUartSoftHead == RVUartSoftTail)
      return -1;
    ch = RVUartSoftRx[RVUartSoftTail];
    nt = (RVUartSoftTail + 1) & (RV_UART_SOFT_CAP - 1);
    RVUartSoftTail = nt;
    return ch & 0xFF;
  }
  if (!(RVUartIn(5) & 1))
    return -1;
  ch = RVUartIn(0) & 0xFF;
  if (RVUartFc) {
    if (ch == RV_UART_XOFF) {
      RVUartTxPaused = 1;
      return -1;
    }
    if (ch == RV_UART_XON) {
      RVUartTxPaused = 0;
      return -1;
    }
  }
  return ch;
}

I64 RVUartGetC()
{
  I64 ch;
  while (1) {
    ch = RVUartTryGet;
    if (ch >= 0)
      return ch;
  }
  return 0;
}

I64 RVUartGetLine(U8 *buf, I64 max)
{
  I64 n = 0, ch;
  while (n < max - 1) {
    ch = RVUartGetC;
    if (ch == '\r' || ch == '\n') {
      RVUartPutS("\n");
      break;
    }
    if (ch == 8 || ch == 127) {
      if (n > 0) {
        n--;
        RVUartPutS("\b \b");
      }
      continue;
    }
    buf[n++] = ch;
    U8 e[2];
    e[0] = ch;
    e[1] = 0;
    RVUartPutS(e);
  }
  buf[n] = 0;
  return n;
}
