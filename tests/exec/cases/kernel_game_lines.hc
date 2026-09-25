// A ScanChar demo that runs until ANY key: Demo/Graphics/Lines.HC, driven as a task.
//
// Three things this had to get right, each of which looked like a kernel bug first:
//
//  1. Lines.HC ended with a bare `Main;`, so INCLUDING it ran the game at load with no
//     graphics up — a load fault before main() executed a single statement. 141 Demo files
//     had the same unguarded autorun; they now carry #ifndef RV_NO_DEMO_AUTORUN.
//  2. It draws BLACK for its first 1000 iterations (`dc->color=c++&15` starts at 0), at
//     Sleep(1) each, so a short run sees an unchanged frame and reads as "drew nothing".
//  3. TaskValidate() still passes after the task function returns, so liveness is the wrong
//     assertion. The observable is the FRAME: it changes while the demo runs, and after the
//     key it stops changing — back at exactly the pre-run hash, because the demo's epilogue
//     does DCFill(dc); DCDel(dc). That proves the key reached ScanChar AND the cleanup ran.
//
// ScanChar takes the key DOWN and then blocks for a KEY_UP with non-zero ASCII, so both are
// posted. Slow by nature (~40s): the 1000 black iterations are the demo's own.
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#include "/Demo/Graphics/Lines.HC"
I64 main()
{
  I64 i, h0, h1;
  Bool alive_before, alive_after;
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
  if (!RVGrInit(640, 480)) { Print("LN FAIL gr\n"); return 1; }
  DCFill(NULL, BLACK);
  h0 = RVFbHash() & 0xFFFFFFFF;
  Print("LN &Main=%X  &main=%X  (equal would mean they collide)\n", &Main, &main);
  t = Spawn(&Main, NULL, "lines", -1, adam, 0, 0);
  Print("LN spawned t=%X rip=%X\n", t, t->rip);
  if (!t) { Print("LN FAIL spawn\n"); return 1; }
  t->next_task = adam->next_task; t->last_task = adam;
  adam->next_task->last_task = t; adam->next_task = t;
  t->win_left = 0; t->win_right = 79; t->win_top = 0; t->win_bottom = 59;
  WinDerivedValsUpdate(t);
  for (i = 0; i < 100; i++) Sleep(200);    //~20s: Lines needs 1000 iterations to leave BLACK
  h1 = RVFbHash() & 0xFFFFFFFF;
  alive_before = TaskValidate(t);
  // Any key stops it — and ScanChar needs the RELEASE as well as the press.
  TaskMsg(t, NULL, MSG_KEY_DOWN, 'q', 0, 0);
  TaskMsg(t, NULL, MSG_KEY_UP,   'q', 0, 0);
  for (i = 0; i < 50; i++) Sleep(100);   //give ScanChar time to notice
  {
    I64 h2, h3;
    h2 = RVFbHash() & 0xFFFFFFFF;
    for (i = 0; i < 20; i++) Sleep(100);
    h3 = RVFbHash() & 0xFFFFFFFF;
    alive_after = (h2 != h3);   //still drawing?
    Print("LN drew=%d (0x%08X->0x%08X) still_drawing_after_key=%d (0x%08X vs 0x%08X)\n",
          h0 != h1, h0, h1, alive_after, h2, h3);
    if (h0 == h1) { Print("LN FAIL — nothing was drawn\n"); return 1; }
  }
  if (alive_after) { Print("LN FAIL — it kept drawing after the key\n"); return 1; }
  Print("LN OK\nCASE-DONE\n");
  return 0;
}
