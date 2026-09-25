// Scripted input into a STOCK TempleOS game, end to end.
//
// Demo/Games/Halogen.HC's own `while (TRUE) { ScanMsg … }` runs here — not a reimplementation.
// Three cursor-rights move the car, ESC leaves the loop, and a KEY_UP satisfies the trailing
// GetMsg the game does on the way out. If the message path, GetKey's sources, Sleep, Snd or the
// game's own Init/UpdateRoad/DrawIt break, car_x stops moving or this never returns.
// Not a reimplementation — Halogen's own `while (TRUE) { ScanMsg … }` runs to completion.
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#include "/Demo/Games/Halogen.HC"
I64 main()
{
  I64 before, after, i;
  CTask *adam = 0x86900000; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  MemSet(adam, 0, sizeof(CTask)); Fs = adam; adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400; heap_end = 0x86000000;
  bp = 0x86800000; BlkPoolInit(bp, 0x2000); sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah; adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0); adam->task_signature = TASK_SIGNATURE_VAL; adam->addr = adam;
  gs = 0x86A00000; MemSet(gs, 0, sizeof(CCPU)); gs->seth_task = adam; adam->gs = gs; Gs = gs;
  RVYieldInit(&Fs);
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
  RVKernelInit();
  if (!RVGrInit(640, 480)) { Print("L4 FAIL gr\n"); return 1; }
  Fs->win_left = 0; Fs->win_right = 79; Fs->win_top = 0; Fs->win_bottom = 59;
  WinDerivedValsUpdate(Fs);

  // Script: three cursor-rights, then ESC to leave the loop, then the KEY_UP that
  // Halogen's trailing GetMsg(,,1<<MSG_KEY_UP) waits on.
  for (i = 0; i < 3; i++)
    TaskMsg(Fs, NULL, MSG_KEY_DOWN, 0, SC_CURSOR_RIGHT, 0);
  TaskMsg(Fs, NULL, MSG_KEY_DOWN, CH_ESC, 0, 0);
  TaskMsg(Fs, NULL, MSG_KEY_UP, 0, 0, 0);

  before = car_x;
  Print("L4 Halogen car_x before=%d — entering the stock game loop\n", before);
  Halogen;
  after = car_x;
  Print("L4 Halogen car_x after=%d delta=%d returned=1\nCASE-DONE\n", after, after - before);
  if (after == before) { Print("L4 FAIL — input did not move the car\n"); return 1; }
  Print("L4 OK\n");
  return 0;
}
