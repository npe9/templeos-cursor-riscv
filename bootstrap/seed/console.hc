// console.hc -- soft VT multiplexing over UART (CONSOLE.md #4 / G25).
// Default: VT0 = REPL; soft switch via Vt(n) / VtAttach / VtNext / VtPrev.
// Opt-in: VtCapture(1) dual-writes Print/UartStr into current VT scrollback
//   (PutCh hook; FrameSend still raw UartPut). VtKeys(1) enables Ctrl-A prefix.
// When UartMuxOn: FrameSend(ch0, "V\tN") for host tools/uart_mux.py --vt-split.
// Flat arrays. Serial REPL stays primary (not FB WinMgr). No panes.
#define VT_N 4
#define VT_LINE_MAX 48
#define VT_SCROLL_N 6
#define VT_TITLE_MAX 12
#define VT_CH_PREFIX 1
I64 g_vt_cur;
I64 g_vt_inited;
I64 g_vt_head[VT_N];
I64 g_vt_count[VT_N];
U8 g_vt_title[VT_N *VT_TITLE_MAX];
U8 g_vt_buf[VT_N *VT_SCROLL_N *VT_LINE_MAX];
I64 g_vt_capture;
I64 g_vt_cap_busy;
I64 g_vt_cap_len;
U8 g_vt_cap_line[VT_LINE_MAX];
I64 g_vt_keys;
U0 VtPutN(U8 *s, I64 max)
{
  I64 i;
  if (!s || max < 1)
    return;
  i = 0;
  while (s[i] && i < max) {
    PutCh(s[i]);
    i++;
  }
}

U8 *VtTitlePtr(I64 n)
{
  return &g_vt_title[n *VT_TITLE_MAX];
}

U8 *VtBufLine(I64 n, I64 slot)
{
  return &g_vt_buf[(n *VT_SCROLL_N + slot) * VT_LINE_MAX];
}

U0 VtTitleSet(I64 n, U8 *s)
{
  I64 i;
  U8 *dst;
  if (n < 0 || n >= VT_N)
    return;
  dst = VtTitlePtr(n);
  if (!s)
    s = "";
  i = 0;
  while (s[i] && i < VT_TITLE_MAX - 1) {
    dst[i] = s[i];
    i++;
  }
  dst[i] = 0;
}

U0 VtInit()
{
  I64 i;
  if (g_vt_inited)
    return;
  for (i = 0; i < VT_N; i++) {
    g_vt_head[i] = 0;
    g_vt_count[i] = 0;
    VtTitlePtr(i)[0] = 0;
  }
  VtTitleSet(0, "repl");
  VtTitleSet(1, "vt1");
  VtTitleSet(2, "vt2");
  VtTitleSet(3, "vt3");
  g_vt_cur = 0;
  g_vt_capture = 0;
  g_vt_cap_busy = 0;
  g_vt_cap_len = 0;
  g_vt_keys = 0;
  g_vt_inited = 1;
}

I64 VtCur()
{
  if (!g_vt_inited)
    VtInit;
  return g_vt_cur;
}

I64 VtCount()
{
  return VT_N;
}

U8 *VtLineAt(I64 n, I64 idx)
{
  I64 start, slot;
  if (n < 0 || n >= VT_N)
    return NULL;
  if (idx < 0 || idx >= g_vt_count[n])
    return NULL;
  start = g_vt_head[n] - g_vt_count[n];
  if (start < 0)
    start = start + VT_SCROLL_N;
  slot = (start + idx) % VT_SCROLL_N;
  return VtBufLine(n, slot);
}

U0 VtPushLine(I64 n, U8 *s)
{
  I64 i, c;
  U8 *dst;
  if (n < 0 || n >= VT_N)
    return;
  if (!s)
    s = "";
  dst = VtBufLine(n, g_vt_head[n]);
  i = 0;
  while (s[i] && i < VT_LINE_MAX - 1) {
    c = s[i];
    if (c == '\n' || c == '\r')
      break;
    dst[i] = c;
    i++;
  }
  dst[i] = 0;
  g_vt_head[n] = (g_vt_head[n] + 1) % VT_SCROLL_N;
  if (g_vt_count[n] < VT_SCROLL_N)
    g_vt_count[n]++;
}
// Notify host framed demux (ch0 payload "V\tN"). No-op when mux off.
U0 VtMuxNotify(I64 n)
{
  U8 msg[4];
  if (!g_uart_mux)
    return;
  if (n < 0 || n >= VT_N)
    return;
  msg[0] = 'V';
  msg[1] = '\t';
  msg[2] = '0' + n;
  FrameSend(FRAME_CH_CONSOLE, msg, 3);
}

U0 VtBanner(I64 n)
{
  U8 *t;
  if (n < 0 || n >= VT_N)
    return;
  t = VtTitlePtr(n);
  g_vt_cap_busy = 1;
  UartStr("\r\n--- VT ");
  PutCh('0' + n);
  UartStr(" (");
  if (t[0])
    VtPutN(t, VT_TITLE_MAX - 1);
  else
    UartStr("?");
  UartStr(") ---\r\n");
  g_vt_cap_busy = 0;
}

U0 VtReplay(I64 n)
{
  I64 i;
  U8 *ln;
  if (n < 0 || n >= VT_N)
    return;
  g_vt_cap_busy = 1;
  for (i = 0; i < g_vt_count[n]; i++) {
    ln = VtLineAt(n, i);
    if (ln) {
      VtPutN(ln, VT_LINE_MAX - 1);
      PutCh('\n');
    }
  }
  g_vt_cap_busy = 0;
}
// VtCaptureCh -- PutCh hook body (line-buffer into current VT).
U0 VtCaptureCh(I64 ch)
{
  if (!g_vt_capture || g_vt_cap_busy)
    return;
  if (!g_vt_inited)
    VtInit;
  ch = ch & 0xFF;
  if (ch == '\r')
    return;
  if (ch == '\n') {
    g_vt_cap_line[g_vt_cap_len] = 0;
    g_vt_cap_busy = 1;
    VtPushLine(g_vt_cur, g_vt_cap_line);
    g_vt_cap_busy = 0;
    g_vt_cap_len = 0;
    return;
  }
  if (g_vt_cap_len < VT_LINE_MAX - 1) {
    g_vt_cap_line[g_vt_cap_len] = ch;
    g_vt_cap_len++;
  }
}
// VtCapture -- VtCapture(1)
// NAME
//   VtCapture - opt-in dual-write Print/UartStr into current VT scrollback
U0 VtCapture(I64 on)
{
  if (!g_vt_inited)
    VtInit;
  g_vt_capture = on != 0;
  g_vt_cap_len = 0;
  if (g_vt_capture)
    g_uart_putc_hook = &VtCaptureCh;
  else
    g_uart_putc_hook = NULL;
}

I64 VtCaptureGet()
{
  return g_vt_capture;
}
// VtKeys -- VtKeys(1)
// NAME
//   VtKeys - enable Ctrl-A prefix in readline (0-3 / n / p / d)
U0 VtKeys(I64 on)
{
  if (!g_vt_inited)
    VtInit;
  g_vt_keys = on != 0;
}

I64 VtKeysGet()
{
  return g_vt_keys;
}
// Vt -- Vt(1)
U0 Vt(I64 n)
{
  if (!g_vt_inited)
    VtInit;
  if (n < 0 || n >= VT_N) {
    UartStr("Vt: bad id (0..");
    PutCh('0' + (VT_N - 1));
    UartStr(")\n");
    return;
  }
  g_vt_cur = n;
  VtMuxNotify(n);
  VtBanner(n);
  VtReplay(n);
}
// VtAttach -- tmux-ish alias of Vt.
U0 VtAttach(I64 n)
{
  Vt(n);
}
// VtDetach -- return to REPL VT0 (soft detach).
U0 VtDetach()
{
  Vt(0);
}

U0 VtNext()
{
  if (!g_vt_inited)
    VtInit;
  Vt ((g_vt_cur + 1) % VT_N);
}

U0 VtPrev()
{
  if (!g_vt_inited)
    VtInit;
  Vt ((g_vt_cur + VT_N - 1) % VT_N);
}

U0 VtTitle(U8 *s)
{
  if (!g_vt_inited)
    VtInit;
  VtTitleSet(g_vt_cur, s);
}

U0 VtPutStr(U8 *s)
{
  if (!g_vt_inited)
    VtInit;
  g_vt_cap_busy = 1;
  VtPushLine(g_vt_cur, s);
  if (s) {
    VtPutN(s, VT_LINE_MAX - 1);
    PutCh('\n');
  }
  g_vt_cap_busy = 0;
}

U0 VtClear()
{
  if (!g_vt_inited)
    VtInit;
  g_vt_head[g_vt_cur] = 0;
  g_vt_count[g_vt_cur] = 0;
  g_vt_cap_len = 0;
}

U0 VtList()
{
  I64 i;
  U8 *t;
  if (!g_vt_inited)
    VtInit;
  g_vt_cap_busy = 1;
  UartStr("=== VT (soft mux) ===\n");
  for (i = 0; i < VT_N; i++) {
    if (i == g_vt_cur)
      PutCh('*');
    else
      PutCh(' ');
    PutCh(' ');
    PutCh('0' + i);
    UartStr("  ");
    t = VtTitlePtr(i);
    if (t[0])
      VtPutN(t, VT_TITLE_MAX - 1);
    else
      UartStr("(untitled)");
    UartStr("  lines=");
    PutCh('0' + (g_vt_count[i] % 10));
    PutCh('\n');
  }
  UartStr("=== VT end ===\n");
  g_vt_cap_busy = 0;
}

U0 VtHelp()
{
  UartStr("VtHelp — soft VT mux (CONSOLE.md #4)\n");
  UartStr("  Vt(n); VtAttach(n); VtDetach; VtNext; VtPrev;\n");
  UartStr("  VtPutStr(\"line\"); VtTitle(\"name\"); VtClear; VtList;\n");
  UartStr("  VtCapture(1);  // Print/UartStr → current VT scrollback (opt-in)\n");
  UartStr("  VtKeys(1);     // Ctrl-A then 0-3 / n / p / d  (readline)\n");
  UartStr("  UartMuxOn; Vt(1);  // also framed V\\tN on ch0\n");
  UartStr("  No panes. Man(\"Vt\");  docs/CONSOLE.md\n");
}
VtInit;
