// Thin-only stubs: gate full Display.HC + KDbg.HC (RawPutChar/StkRep/Fault*).
// SoftCall/STAY path never needs VGA raw text or the debugger surface.
#ifndef K_THIN_DBG_DISPLAY_STUBS_HC
#define K_THIN_DBG_DISPLAY_STUBS_HC
U0 RawPutChar(I64 ch)
{
  no_warn ch;
}

U0 VGAFlush()
{
}

U0 WinDerivedValsUpdate(CTask *task)
{
  if (!task)
    task = Fs;
  if (!task)
    return;
  task->win_width = task->win_right - task->win_left + 1;
  task->win_height = task->win_bottom - task->win_top + 1;
}

U8 *Caller(I64 num = 1)
{
  no_warn num;
  return NULL;
}

I64 UnusedStk(CTask *task = NULL)
{
  no_warn task;
  return 0x1000000;
}

Bool BptS(U8 *addr, CTask *task = NULL, Bool live = TRUE)
{
  no_warn addr;
  no_warn task;
  no_warn live;
  return FALSE;
}

Bool BptR(U8 *addr, CTask *task = NULL, Bool live = TRUE, Bool rem = TRUE)
{
  no_warn addr;
  no_warn task;
  no_warn live;
  no_warn rem;
  return FALSE;
}

U0 Dbg(U8 *msg = NULL, I64 msg_num = 0)
{
  no_warn msg;
  no_warn msg_num;
}

U0 G(U8 *ip = INVALID_PTR, CTask *task = NULL)
{
  no_warn ip;
  no_warn task;
}

U0 G2(U8 *ip = INVALID_PTR, CTask *task = NULL)
{
  no_warn ip;
  no_warn task;
}

U0 Panic(U8 *msg = NULL, I64 msg_num = 0, Bool panic = TRUE)
{
  U8 *uart = CONFIG_UART_BASE;
  U8 *p;
  no_warn msg_num;
  no_warn panic;
  if (msg) {
    p = msg;
    while (*p)
      *uart = *p++;
  }
  while (TRUE)
    HLT;
}
#endif
