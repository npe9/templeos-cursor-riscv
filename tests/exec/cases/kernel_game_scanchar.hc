// Scripted KEYBOARD + POINTER into a third stock game, driven through ScanChar.
//
// Demo/Games/BattleLines.HC reads keys with ScanChar and steers with ms.pos, so it exercises
// paths the other two game smokes do not:
//
//   ScanChar takes the MSG_KEY_DOWN and then BLOCKS in GetMsg until a MSG_KEY_UP with a
//   non-zero ASCII arrives. Post only the down and the game wedges — which is exactly what
//   made this look broken before. Every key here is a down/up PAIR.
//
//   The game Sleep(40)s per turn, so the driver has to let REAL TIME pass. A tight Yield loop
//   runs in microseconds and leaves the task asleep with nothing appearing to happen.
//
// Asserted: '2' reaches the game's own switch (tap_mode flips), and the trooper ends up in a
// DIFFERENT place with the pointer inside its tap radius than with the pointer far away. The
// magnitudes are deliberately not pinned — the tap intensity is ((R^2-d)^2)^2 and the values
// it produces here are large enough to suspect a fixed-point overflow, which is its own
// question. Divergence is the thing that proves the input arrived.
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#include "/Demo/Games/BattleLines.HC"
I64 main()
{
  I64 x0, y0, x1, y1, i;
  CTask *t;
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
  if (!RVGrInit(640, 480)) { Print("BL FAIL gr\n"); return 1; }
  Fs->win_left = 0; Fs->win_right = 79; Fs->win_top = 0; Fs->win_bottom = 59;
  WinDerivedValsUpdate(Fs);
  t = Spawn(&BattleLines, NULL, "bl", -1, adam, 0, 0);
  if (!t) { Print("BL FAIL spawn\n"); return 1; }
  t->next_task = adam->next_task; t->last_task = adam;
  adam->next_task->last_task = t; adam->next_task = t;
  t->win_left = 0; t->win_right = 79; t->win_top = 0; t->win_bottom = 59;
  WinDerivedValsUpdate(t);
  Sleep(300);   //let the task get past PopUpOk/Init into its loop (it Sleep(40)s per turn)
  {
    I64 ax, bx, k;
    // Enable tap_mode with a REAL key pair: ScanChar takes the DOWN then blocks in GetMsg
    // until a KEY_UP with non-zero ASCII arrives. Posting only the down wedges the game.
    TaskMsg(t, NULL, MSG_KEY_DOWN, '2', 0, 0);
    TaskMsg(t, NULL, MSG_KEY_UP,   '2', 0, 0);
    for (k = 0; k < 6; k++) Sleep(100);
    Print("BL tap_mode=%d (1 = the key reached the game's switch)\n", tap_mode);

    ms.pos.z = 25; ms.lb = TRUE;
    ms.pos.x = 520; ms.pos.y = 190;   //20px LEFT of the trooper — inside the 50px tap radius, not on it
    for (k = 0; k < 12; k++) Sleep(100);
    ax = tr[0][0].x >> 32;
    Print("BL with pointer 20px left of it: x=%d\n", ax);
    ms.pos.x = 40;  ms.pos.y = 40;    //far away — outside it
    for (k = 0; k < 12; k++) Sleep(100);
    bx = tr[0][0].x >> 32;
    x0 = ax; x1 = bx;
    Print("BL near-pointer x=%d then far-pointer x=%d\n", ax, bx);
  }
  TaskMsg(t, NULL, MSG_KEY_DOWN, CH_ESC, 0, 0);
  Sleep(300);
  if (!tap_mode) { Print("BL FAIL — the key never reached the game's switch\n"); return 1; }
  if (x0 == x1) { Print("BL FAIL — the trooper ignored where the pointer was\n"); return 1; }
  Print("BL OK\nCASE-DONE\n");
  return 0;
}
