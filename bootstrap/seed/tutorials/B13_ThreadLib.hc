// B13_ThreadLib.hc -- Write a (cooperative) threading library
// Prereq: B12_Concurrent. Builds the data structures / API of a tiny thread
// package on this HolyC REPL, then maps the same ideas onto real multi-hart
// (Kernel/Drv/RVSmp.HC) and preemptive (timer trap) ports.
//
// HOW TO WORK THIS LAB
//   Run("B13_ThreadLib.hc");  Src/Vi Fill_in;  Run again until PASS.
//
// WHAT YOU ARE BUILDING
//   A *user-level cooperative* library (green threads):
//     TCB  = id + state + entry fn + arg + return
//     ready queue  = round-robin work list
//     Spawn / Yield / Join / Run  = create, give up CPU, wait, drain queue
//     mtx (mutex)  = protect shared data  (HolyC reserves `lock` -- use mtx)
//   This is the same *shape* as pthreads / TempleOS tasks, without needing a
//   second hart or a full context-switch asm trampoline in the REPL.
//
// REALITY CHECK (honest GAPs)
//   - True preemption needs timer IRQ + save/restore of GPRs (see B08 / A05).
//   - True parallelism needs another hart: RVSmpWake / RVAmoAddI64 / MSIP.
//   - Stackful swapcontext (sp/ra save) is sketched; Run here calls fn()
//     directly (stackless / run-to-completion). Still the right *library* API.
//
// NEXT
//   B14_ArtOfMulticore -- Herlihy & Shavit (TAS/CAS/ABA/barriers); then Part C.
#define TL_MAX   8
#define TL_READY 0
#define TL_RUN   1
#define TL_DONE  2
#define TL_WAIT  3
I64 TL_state[8];
I64 TL_arg[8];
I64 TL_ret[8];
I64 TL_fn[8];
// code ptr as I64 (host parser has no I64 (*f[N])(I64) yet)
I64 TL_n;
I64 TL_cur;
I64 TL_q[8];
I64 TL_qh;
I64 TL_qt;
I64 TL_qc;
I64 TL_shared;
I64 TL_mtx;
U0 B13_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}
// ---- Library core (study these; demos call them) ---------------------------
U0 TL_Init()
{
  I64 i;
  TL_n = 0;
  TL_cur = -1;
  TL_qh = 0;
  TL_qt = 0;
  TL_qc = 0;
  TL_shared = 0;
  TL_mtx = 0;
  for (i = 0; i < TL_MAX; i++) {
    TL_state[i] = TL_DONE;
    TL_fn[i] = 0;
    TL_arg[i] = 0;
    TL_ret[i] = 0;
    TL_q[i] = -1;
  }
}

I64 TL_QPut(I64 id)
{
  if (TL_qc >= TL_MAX)
    return -1;
  TL_q[TL_qt] = id;
  TL_qt = (TL_qt + 1) % TL_MAX;
  TL_qc++;
  return 0;
}

I64 TL_QGet()
{
  I64 id;
  if (TL_qc <= 0)
    return -1;
  id = TL_q[TL_qh];
  TL_qh = (TL_qh + 1) % TL_MAX;
  TL_qc--;
  return id;
}

I64 TL_Spawn(I64 (*fn)(I64), I64 arg)
{
  I64 id;
  if (TL_n >= TL_MAX || !fn)
    return -1;
  id = TL_n;
  TL_n++;
  TL_fn[id] = fn;
  TL_arg[id] = arg;
  TL_ret[id] = 0;
  TL_state[id] = TL_READY;
  if (TL_QPut(id) < 0)
    return -1;
  return id;
}
// Run-to-completion scheduler: drain ready queue by calling each fn.
// A stackful Yield would save sp/ra and TL_QPut(TL_cur) instead of returning.
U0 TL_Run()
{
  I64 id;
  I64 (*f)(I64);
  while (TL_qc > 0) {
    id = TL_QGet();
    if (id < 0)
      break;
    TL_cur = id;
    TL_state[id] = TL_RUN;
    f = TL_fn[id];
    TL_ret[id] = f(TL_arg[id]);
    TL_state[id] = TL_DONE;
    TL_cur = -1;
  }
}

I64 TL_TryMtx(I64 *mtx)
{
  if (*mtx == 0) {
    *mtx = 1;
    return 1;
  }
  return 0;
}

U0 TL_UnlockMtx(I64 *mtx)
{
  *mtx = 0;
}
// Demo workers -- already complete.
I64 B13_WorkerA(I64 n)
{
  I64 i;
  for (i = 0; i < n; i++) {
    while (!TL_TryMtx(&TL_mtx))
      ;
    TL_shared++;
    TL_UnlockMtx(&TL_mtx);
  }
  return TL_shared;
}

I64 B13_WorkerB(I64 n)
{
  return B13_WorkerA(n);
}

U0 B13_Demo()
{
  I64 a, b;
  Print("B13: cooperative thread library (TCB + ready Q + mtx)\n");
  Print("  API: TL_Init / TL_Spawn / TL_Run / TL_TryMtx\n");
  Print("  GAP: stackful Yield + preemption + RVSmp multi-hart parallelism\n");
  TL_Init();
  a = TL_Spawn(&B13_WorkerA, 3);
  b = TL_Spawn(&B13_WorkerB, 4);
  TL_Run();
  B13_Expect("B13_spawn_ids", (a == 0) && (b == 1), 1);
  B13_Expect("B13_shared_7", TL_shared, 7);
  B13_Expect("B13_done_A", TL_state[0], TL_DONE);
}
// ---- Exercises (Fill_in) ---------------------------------------------------
// Ex1 Warmup: READY state constant.
I64 B13_Ex1_ReadyConst()
{
  // TODO Fill_in: return TL_READY;
  return -1;
}
// Ex2: after Init, queue count is 0.
I64 B13_Ex2_InitEmpty()
{
  // TODO Fill_in: TL_Init(); return TL_qc;
  return -1;
}
// Ex3: enqueue one id then dequeue it (use TL_QPut/TL_QGet).
I64 B13_Ex3_QueueRoundTrip(I64 id)
{
  // TODO Fill_in:
  //   TL_Init(); TL_QPut(id); return TL_QGet();
  return -1;
}
// Ex4: Spawn a no-op; return its id (should be 0 on fresh Init).
I64 B13_Nop(I64 x)
{
  return x;
}

I64 B13_Ex4_SpawnId()
{
  // TODO Fill_in:
  //   TL_Init(); return TL_Spawn(&B13_Nop, 42);
  return -1;
}
// Ex5: mutex -- acquire from 0 then fail second acquire.
I64 B13_Ex5_MtxBusy()
{
  I64 mtx;
  // TODO Fill_in:
  //   mtx = 0;
  //   if (!TL_TryMtx(&mtx)) return -1;
  //   if (TL_TryMtx(&mtx)) return -1;
  //   return 1;
  return -1;
}
// Ex6: unlock then re-acquire succeeds.
I64 B13_Ex6_MtxUnlock()
{
  I64 mtx;
  // TODO Fill_in:
  //   mtx = 0; TL_TryMtx(&mtx); TL_UnlockMtx(&mtx);
  //   return TL_TryMtx(&mtx);
  return -1;
}
// Ex7 Challenge: how many integer GPRs does a full RV64 context save
// (excluding x0 which is hardwired zero)? Teaching answer: 31.
I64 B13_Ex7_GprSaveCount()
{
  // TODO Fill_in: return 31;
  return -1;
}
// Ex8 Challenge: real second hart mailbox poke uses CLINT MSIP.
// Return MemMapFind("clint") -- same as B12 / RVSmpMsip base.
I64 B13_Ex8_SmpClint()
{
  // TODO Fill_in: return MemMapFind("clint");
  return 0;
}
// Ex9 Challenge: Join intuition -- return 1 iff state is DONE.
I64 B13_Ex9_JoinOk(I64 state)
{
  // TODO Fill_in: if (state == TL_DONE) return 1; return 0;
  return -1;
}
// Ex10 Challenge: Yield policy -- re-queue running id, return next from Q.
// Given cur already removed from Q; put cur back READY and return TL_QGet().
I64 B13_Ex10_YieldNext(I64 cur)
{
  // TODO Fill_in:
  //   TL_state[cur] = TL_READY;
  //   TL_QPut(cur);
  //   return TL_QGet();
  return -1;
}

U0 B13_Check()
{
  I64 n;
  Print("-- B13 exercises --\n");
  B13_Expect("Ex1_ReadyConst", B13_Ex1_ReadyConst(), TL_READY);
  B13_Expect("Ex2_InitEmpty", B13_Ex2_InitEmpty(), 0);
  B13_Expect("Ex3_QueueRoundTrip", B13_Ex3_QueueRoundTrip(3), 3);
  B13_Expect("Ex4_SpawnId", B13_Ex4_SpawnId(), 0);
  B13_Expect("Ex5_MtxBusy", B13_Ex5_MtxBusy(), 1);
  B13_Expect("Ex6_MtxUnlock", B13_Ex6_MtxUnlock(), 1);
  B13_Expect("Ex7_GprSaveCount", B13_Ex7_GprSaveCount(), 31);
  B13_Expect("Ex8_SmpClint", B13_Ex8_SmpClint(), MEM_CLINT);
  B13_Expect("Ex9_JoinOk", B13_Ex9_JoinOk(TL_DONE), 1);
  B13_Expect("Ex9_JoinBusy", B13_Ex9_JoinOk(TL_RUN), 0);
  TL_Init();
  TL_QPut(1);
  TL_QPut(2);
  TL_state[1] = TL_RUN;
  n = B13_Ex10_YieldNext(1);
  B13_Expect("Ex10_YieldNext", n, 2);
}

U0 B13()
{
  Print("=== B13 Write a threading library ===\n");
  B13_Demo();
  B13_Check();
  Print("Next: Run(\"B14_ArtOfMulticore.hc\");  then Part C / Tutorial;\n");
  Print("Dig-down: Kernel/Drv/RVSmp.HC  Man(\"CLINT\");  make kernel-smp-smoke\n");
}
B13;
