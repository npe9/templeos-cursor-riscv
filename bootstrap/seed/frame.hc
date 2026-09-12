// frame.hc -- framed multi-channel UART (CONSOLE.md / G22).
// Default off (g_uart_mux=0 in uart.hc): raw REPL unchanged.
// Boot after log.hc (installs g_log_mux_hook; needs g_uart_mux + g_log_mux_ch).
// Wire: SYNC=0x7E | stuffed(CH | LEN16le | PAYLOAD | CRC8)
// Escape: 0x7D, (b^0x20) for 0x7E/0x7D. CRC8 poly 0x07 init 0.
// CH: 0=console 1=FS 2=dbg 3=log 4=RPC. Host: tools/uart_mux.py
#define FRAME_SYNC 0x7E
#define FRAME_ESC 0x7D
#define FRAME_MAX 64
#define FRAME_CH_CONSOLE 0
#define FRAME_CH_FS 1
#define FRAME_CH_DBG 2
#define FRAME_CH_LOG 3
#define FRAME_CH_RPC 4
// Scratch for FrameSend (avoid large stack frames in the JIT).
U8 g_frame_scratch[3 + FRAME_MAX];
I64 FrameCrc8(U8 *buf, I64 len)
{
  I64 crc, i, bit;
  crc = 0;
  if (!buf || len < 1)
    return 0;
  for (i = 0; i < len; i++) {
    crc = crc ^ buf[i];
    for (bit = 0; bit < 8; bit++) {
      if (crc & 0x80)
        crc = ((crc << 1) ^ 0x07) & 0xFF;
      else
        crc = (crc << 1) & 0xFF;
    }
  }
  return crc & 0xFF;
}

U0 FrameEscPut(I64 b)
{
  b = b & 0xFF;
  if (b == FRAME_SYNC || b == FRAME_ESC) {
    UartPut(FRAME_ESC);
    UartPut(b ^ 0x20);
  } else
    UartPut(b);
}
// FrameSend -- always emits a frame (even if mux off). Caps at FRAME_MAX.
U0 FrameSend(I64 ch, U8 *buf, I64 len)
{
  I64 i, n, crc;
  if (len < 0)
    len = 0;
  if (len > FRAME_MAX)
    len = FRAME_MAX;
  if (!buf && len)
    return;
  g_frame_scratch[0] = ch & 0xFF;
  g_frame_scratch[1] = len & 0xFF;
  g_frame_scratch[2] = (len >> 8) & 0xFF;
  for (i = 0; i < len; i++)
    g_frame_scratch[3 + i] = buf[i];
  n = 3 + len;
  crc = FrameCrc8(g_frame_scratch, n);
  UartPut(FRAME_SYNC);
  for (i = 0; i < n; i++)
    FrameEscPut(g_frame_scratch[i]);
  FrameEscPut(crc);
}

U0 FramePutStr(I64 ch, U8 *s)
{
  I64 n;
  if (!s)
    return;
  n = 0;
  while (s[n])
    n++;
  while (n > FRAME_MAX) {
    FrameSend(ch, s, FRAME_MAX);
    s = s + FRAME_MAX;
    n = n - FRAME_MAX;
  }
  if (n)
    FrameSend(ch, s, n);
}
// UartMuxOn -- enable mux; LogMuxEmit (below) ships dmesg to ch3.
U0 FrameLogMuxEmit(I64 level, U8 *sub, U8 *msg);
// forward — defined below, installed here
U0 UartMuxOn()
{
  g_uart_mux = 1;
  g_log_mux_ch = FRAME_CH_LOG;
  g_log_mux_hook = &FrameLogMuxEmit;
}

U0 UartMuxOff()
{
  g_uart_mux = 0;
  g_log_mux_ch = 0;
}

I64 UartMuxGet()
{
  return g_uart_mux;
}

U0 FrameFsSend(U8 *buf, I64 len)
{
  FrameSend(FRAME_CH_FS, buf, len);
}

U0 FrameDbgSend(U8 *buf, I64 len)
{
  FrameSend(FRAME_CH_DBG, buf, len);
}

U0 FrameLogSend(U8 *buf, I64 len)
{
  FrameSend(FRAME_CH_LOG, buf, len);
}

U0 FrameRpcSend(U8 *buf, I64 len)
{
  FrameSend(FRAME_CH_RPC, buf, len);
}
// Framed ch3 log emitter. Installed into log.hc's g_log_mux_hook by UartMuxOn — a
// second `U0 LogMuxEmit` here would just be dead code (single translation unit).
U0 FrameLogMuxEmit(I64 level, U8 *sub, U8 *msg)
{
  U8 line[96];
  I64 i, n, c;
  if (!g_uart_mux && !g_log_mux_ch)
    return;
  if (!sub)
    sub = "";
  if (!msg)
    msg = "";
  if (level == LOG_WARN)
    line[0] = 'W';
  else if (level == LOG_ERR)
    line[0] = 'E';
  else
    line[0] = 'I';
  line[1] = '\t';
  n = 2;
  i = 0;
  while (sub[i] && n < 40) {
    c = sub[i++];
    if (c == '\t' || c == '\n' || c == '\r')
      c = ' ';
    line[n++] = c;
  }
  if (n < 94)
    line[n++] = '\t';
  i = 0;
  while (msg[i] && n < 95) {
    c = msg[i++];
    if (c == '\n' || c == '\r')
      c = ' ';
    line[n++] = c;
  }
  FrameSend(FRAME_CH_LOG, line, n);
}
