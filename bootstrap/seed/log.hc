// log.hc -- dmesg-style program/kernel log ring (≠ Print stdout, ≠ FsLog journal).
// Optional UART mux ch3: frame.hc redefines LogMuxEmit after UartMuxOn.
#define LOG_INFO 0
#define LOG_WARN 1
#define LOG_ERR 2
#define LOG_RING_N 64
#define LOG_MSG_MAX 96
#define LOG_SUB_MAX 16
class CLogRec
{
  I64 ts;
  I64 level;
  U8 sub[LOG_SUB_MAX];
  U8 msg[LOG_MSG_MAX];
};
CLogRec g_log_ring[LOG_RING_N];
I64 g_log_head;
I64 g_log_count;
I64 g_log_dropped;
I64 g_log_inited;
I64 g_log_seq;
// Optional ch3: stub until frame.hc loads and redefines LogMuxEmit.
// UartMuxOn sets g_log_mux_ch=FRAME_CH_LOG; mux off leaves this a no-op.
I64 g_log_mux_ch;
U0 LogMuxEmit(I64 level, U8 *sub, U8 *msg)
{
  // Stub — frame.hc redefines to FrameSend(ch3, …). Keep body cheap for boot.
  if (!g_uart_mux && !g_log_mux_ch)
    return;
  if (!sub || !msg)
    return;
  if (level < 0)
    return;
}
// LogNow -- LogNow()
// NAME
//   LogNow - timestamp for a log record
// SYNOPSIS
//   I64 LogNow();
// DESCRIPTION
//   Prefer Goldfish RTC wall ns when MEM_RTC is mapped (same latch as
//   Kernel/Drv/RVRtcGoldfish.HC / RVRtcReadNs). Else CLINT mtime cycle
//   counter. Else a monotonic sequence. Seed path does not #include Kernel.
// EXAMPLES
//   Print("%X\n", LogNow);
// SEE ALSO
//   Log  DMesg  RVRtcReadNs  MEM_RTC  MEM_MTIME
I64 LogNow()
{
  // Prefer Goldfish RTC when mapped; fall back to CLINT mtime / seq.
  // Do not touch RTC if base is zero (boards without Goldfish).
  U32 *rtc;
  I64 lo, hi, ns;
  if (MEM_RTC) {
    // Probe: only use if TIME_LOW looks live (non-zero after a read).
    // Faulting MMIO would trap — MEM_RTC is 0 on maps without Goldfish.
    rtc = MEM_RTC;
    lo = rtc[0](U32);
    hi = rtc[1](U32);
    ns = lo | (hi << 32);
    if (ns)
      return ns;
  }
  if (MEM_MTIME)
    return *(I64 *)MEM_MTIME;
  g_log_seq++;
  return g_log_seq;
}

U0 LogCpy(U8 *dst, U8 *src, I64 cap)
{
  I64 i;
  if (!dst || cap < 1)
    return;
  if (!src) {
    dst[0] = 0;
    return;
  }
  i = 0;
  while (src[i] && i < cap - 1) {
    dst[i] = src[i];
    i++;
  }
  dst[i] = 0;
}

U8 LogLevelCh(I64 level)
{
  if (level == LOG_WARN)
    return 'W';
  if (level == LOG_ERR)
    return 'E';
  return 'I';
}
// LogInit -- LogInit()
// NAME
//   LogInit - reset the dmesg ring (idempotent)
// SYNOPSIS
//   U0 LogInit();
U0 LogInit()
{
  g_log_head = 0;
  g_log_count = 0;
  g_log_dropped = 0;
  g_log_seq = 0;
  g_log_inited = 1;
  g_log_mux_ch = 0;
}
// Log -- Log(level,subsys,msg)
// NAME
//   Log - append one record to the dmesg ring (not UART stdout)
// SYNOPSIS
//   U0 Log(I64 level,U8 *subsys,U8 *msg);
// DESCRIPTION
//   Stores severity, subsystem, message, and LogNow() stamp. Silent until DMesg.
// EXAMPLES
//   Log(LOG_INFO,"boot","ring-ready");
//   DMesg;
U0 Log(I64 level, U8 *subsys, U8 *msg)
{
  CLogRec *r;
  if (!g_log_inited)
    LogInit;
  if (level < LOG_INFO)
    level = LOG_INFO;
  if (level > LOG_ERR)
    level = LOG_ERR;
  r = &g_log_ring[g_log_head];
  r->ts = LogNow();
  r->level = level;
  LogCpy(r->sub, subsys, LOG_SUB_MAX);
  LogCpy(r->msg, msg, LOG_MSG_MAX);
  g_log_head = (g_log_head + 1) & (LOG_RING_N - 1);
  if (g_log_count < LOG_RING_N)
    g_log_count++;
  else
    g_log_dropped++;
  LogMuxEmit(level, r->sub, r->msg);
}

U0 LogInfo(U8 *subsys, U8 *msg)
{
  Log(LOG_INFO, subsys, msg);
}

U0 LogWarn(U8 *subsys, U8 *msg)
{
  Log(LOG_WARN, subsys, msg);
}

U0 LogErr(U8 *subsys, U8 *msg)
{
  Log(LOG_ERR, subsys, msg);
}

U0 LogClear()
{
  LogInit;
}

I64 LogCount()
{
  if (!g_log_inited)
    return 0;
  return g_log_count;
}
// DMesg -- DMesg(n)
// NAME
//   DMesg - print the log ring to the UART console
// SYNOPSIS
//   U0 DMesg(I64 n=0);
U0 DMesg(I64 n = 0)
{
  I64 i, start, show, idx;
  CLogRec *r;
  if (!g_log_inited || !g_log_count) {
    UartStr("(dmesg empty)\n");
    return;
  }
  show = g_log_count;
  if (n > 0 && n < show)
    show = n;
  if (g_log_count < LOG_RING_N)
    start = 0;
  else
    start = g_log_head;
  start = (start + (g_log_count - show)) & (LOG_RING_N - 1);
  UartStr("--- dmesg ---\n");
  for (i = 0; i < show; i++) {
    idx = (start + i) & (LOG_RING_N - 1);
    r = &g_log_ring[idx];
    "[%X] %c %s  %s\n", r->ts, LogLevelCh(r->level), r->sub, r->msg;
  }
  if (g_log_dropped)
    "(dropped %d)\n", g_log_dropped;
}
