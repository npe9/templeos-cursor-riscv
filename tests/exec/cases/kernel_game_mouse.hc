// Scripted MOUSE input into a STOCK TempleOS game, end to end.
//
// Demo/Games/MassSpring.HC's own `GetMsg` loop runs here. Its mouse verbs are the interesting
// part: MSG_MS_L_DOWN places a mass at (arg1,arg2), and an MSG_MS_R_DOWN / MSG_MS_R_UP pair
// over two different masses springs them together. So the script builds a two-mass, one-spring
// model purely by clicking, then ESCs out — and the counts prove the game acted on each event
// rather than merely surviving them.
//
// Companion to kernel-game-input-smoke, which drives Halogen with the keyboard.
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#include "/Demo/Games/MassSpring.HC"

I64 MSCountMasses()
{
  I64 n = 0, guard = 0;
  CMass *tmpm;
  if (!ode)
    return 0;
  tmpm = ode->next_mass;
  while (tmpm != &ode->next_mass) {
    n++;
    tmpm = tmpm->next;
    if (!tmpm || ++guard > 4096)
      break;
  }
  return n;
}

I64 MSCountSprings()
{
  I64 n = 0, guard = 0;
  CSpring *tmps;
  if (!ode)
    return 0;
  tmps = ode->next_spring;
  while (tmps != &ode->next_spring) {
    n++;
    tmps = tmps->next;
    if (!tmps || ++guard > 4096)
      break;
  }
  return n;
}

I64 main()
{
  I64 masses, springs;
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
  if (!RVGrInit(640, 480)) { Print("MOUSE FAIL gr\n"); return 1; }
  Fs->win_left = 0; Fs->win_right = 79; Fs->win_top = 0; Fs->win_bottom = 59;
  WinDerivedValsUpdate(Fs);

  // Run the game as a TASK, which is how TempleOS runs one, and sample while it is still
  // alive: MassSpringDemo's own epilogue calls CleanUp, which QueDels every mass and spring,
  // so counting after it returns always reads 0.
  {
    CTask *t;
    I64 i;
    t = Spawn(&MassSpringDemo, NULL, "ms", -1, adam, 0, 0);
    if (!t) { Print("MOUSE FAIL spawn\n"); return 1; }
    t->next_task = adam->next_task;
    t->last_task = adam;
    adam->next_task->last_task = t;
    adam->next_task = t;
    Print("MOUSE spawned task=%d — letting it reach GetMsg\n", t->task_num);
    for (i = 0; i < 400; i++) Yield;

    // Left-click two masses, then right-press on the first and right-release on the second,
    // which is how the game is told to spring them together.
    TaskMsg(t, NULL, MSG_MS_L_DOWN, 100, 100, 0);
    TaskMsg(t, NULL, MSG_MS_L_DOWN, 200, 140, 0);
    TaskMsg(t, NULL, MSG_MS_R_DOWN, 100, 100, 0);
    TaskMsg(t, NULL, MSG_MS_R_UP,   200, 140, 0);
    for (i = 0; i < 2000; i++) Yield;

    masses = MSCountMasses;
    springs = MSCountSprings;
    Print("MOUSE masses=%d springs=%d (sampled while the game is running)\n", masses, springs);

    TaskMsg(t, NULL, MSG_KEY_DOWN, CH_ESC, 0, 0);
    TaskMsg(t, NULL, MSG_KEY_UP, 0, 0, 0);
    for (i = 0; i < 2000; i++) Yield;
  }
  if (masses != 2 || springs != 1) {
    Print("MOUSE FAIL — clicks did not build the model (want masses=2 springs=1)\n");
    return 1;
  }
  Print("MOUSE OK\nCASE-DONE\n");
  return 0;
}
