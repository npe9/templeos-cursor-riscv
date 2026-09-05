// Stock Demo/Games/MassSpring.HC on AMathODE_RV + D3* (not a hand-rolled clone).
// Smoke: Init / PlaceMass / PlaceSpring / MassFind / ODEsUpdate / ODEPause / RK5 / DrawIt.
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#include "/Demo/Games/MassSpring.HC"
I64 MassSpringCountMasses()
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

I64 MassSpringCountSprings()
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

Bool MassSpringSeedChain(I64 ox = 20, I64 oy = 30)
{
  //Minimal three-mass chain for ODEsUpdate/RK5 oracle (not TempleOS gravity toys).
  MyMass *m0, *m1, *m2;
  MySpring *s0, *s1;
  Init;
  if (!ode)
    return FALSE;
  PlaceMass(ox, oy);
  PlaceMass(ox + 48, oy + 6);
  PlaceMass(ox + 96, oy + 4);
  m0 = ode->next_mass(MyMass *);
  if (!m0 || m0 == &ode->next_mass)
    return FALSE;
  m1 = m0->next(MyMass *);
  m2 = m1->next(MyMass *);
  if (!m1 || !m2 || m1 == &ode->next_mass || m2 == &ode->next_mass)
    return FALSE;
  if (m2->next != &ode->next_mass)
    return FALSE;
  m0->radius = 5;
  m1->radius = 7;
  m2->radius = 6;
  m0->flags |= MSF_FIXED;
  PlaceSpring(m0, m1);
  PlaceSpring(m1, m2);
  s0 = ode->next_spring(MySpring *);
  s1 = s0->next(MySpring *);
  if (!s0 || !s1)
    return FALSE;
  //Stock PlaceSpring rest_len=100; shorten for a compact smoke frame.
  s0->rest_len = 40;
  s1->rest_len = 40;
  ODERenum(ode);
  ODEState2Internal(ode);
  ODEInternal2State(ode);
  return TRUE;
}

Bool MassSpringTickRK5(I64 steps = 1)
{
  I64 s, i;
  if (!ode || steps < 1)
    return FALSE;
  if (ode->flags & ODEF_PAUSED)
    return FALSE;
  for (s = 0; s < steps; s++) {
    ODECallDerivative(ode, ode->t, ode->state_internal, ode->DstateDt);
    for (i = 0; i < ode->n_internal; i++)
      ode->state_scale[i] = Abs(ode->state_internal[i]) + Abs(ode->DstateDt[i] * ode->h) + ode->tolerance_internal;
    ODERK5OneStep(ode);
    ODEInternal2State(ode);
  }
  return TRUE;
}

I64 main()
{
  I64 i, x, y, ticks, n, springs;
  Bool was;
  MyMass *m1, *found;
  CD3 a, b, c;
  F64 dot, t0;
  CTask *adam;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  CRVDC *dc;
  adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  adam->task_signature = TASK_SIGNATURE_VAL;
  adam->addr = adam;
  gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVKernelInit();
  D3Equ(&a, 1.0, 2.0, 3.0);
  D3Equ(&b, 4.0, 5.0, 6.0);
  dot = D3Dot(&a, &b);
  D3Add(&c, &a, &b);
  if (ToI64(dot) != 32 || ToI64(c.x) != 5) {
    Print("D3 smoke FAIL dot=%d cx=%d\n", ToI64(dot), ToI64(c.x));
    return 1;
  }
  if (!MassSpringSeedChain(20, 30)) {
    Print("MassSpring init FAIL\n");
    return 1;
  }
  if (ode != adam->next_ode) {
    Print("MassSpring next_ode queue FAIL\n");
    return 1;
  }
  n = MassSpringCountMasses;
  springs = MassSpringCountSprings;
  if (n != 3 || springs != 2) {
    Print("MassSpring shape FAIL n_mass=%d n_spring=%d\n", n, springs);
    return 1;
  }
  found = MassFind(ode, 20, 30, 0)(MyMass *);
  if (!found || !(found->flags & MSF_FIXED)) {
    Print("MassSpring MassFind FAIL\n");
    return 1;
  }
  t0 = ode->t;
  winmgr.fps = WINMGR_FPS;
  winmgr.last_ode_time = 0.01;
  Busy(50000);
  ODEsUpdate(adam);
  Busy(50000);
  ODEsUpdate(adam);
  Busy(50000);
  ODEsUpdate(adam);
  if (ode->t <= t0) {
    Print("MassSpring ODEsUpdate FAIL t0=%d t=%d\n", ToI64(t0 * 1000), ToI64(ode->t * 1000));
    return 1;
  }
  Print("MassSpring ODEsUpdate t_ms=%d→%d\n", ToI64(t0 * 1000), ToI64(ode->t * 1000));
  was = ODEPause(ode, ON);
  if (MassSpringTickRK5(5)) {
    Print("MassSpring pause FAIL still stepped\n");
    return 1;
  }
  ODEPause(ode, OFF);
  ticks = 0;
  for (i = 0; i < 30; i++) {
    if (!MassSpringTickRK5(1)) {
      Print("MassSpring RK5 FAIL\n");
      return 1;
    }
    ticks++;
  }
  m1 = MassFindNum(ode, 1)(MyMass *);
  if (!m1) {
    Print("MassSpring MassFindNum FAIL\n");
    return 1;
  }
  x = ToI64(m1->x);
  y = ToI64(m1->y);
  // Prove stock DrawIt paints via GrLine/GrCircle (CDC→CRVDC).
  if (!RVGrInit(320, 240)) {
    Print("MassSpring Gr init FAIL\n");
    return 1;
  }
  DCFill(NULL, WHITE);
  DrawIt(Fs, rv_gr.dc(CDC *));
  RVGrRefresh();
  Print("MassSpring smoke ticks=%d m1=%d,%d paused0=%d was=%d ready=1 n=%d queued=1 t=%d\n", ticks, x, y, !(ode->flags & ODEF_PAUSED), was, n, ToI64(ode->t * 1000));
  if (ticks != 30 || x < 8 || y < 8) {
    Print("MassSpring smoke FAIL\n");
    return 1;
  }
  no_warn dc;
  CleanUp;
  return 0;
}
