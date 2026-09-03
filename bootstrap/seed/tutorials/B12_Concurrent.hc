// B12_Concurrent.hc -- CSAPP 3e Ch.12: Concurrent Programming
// Remap: timer ticks + early multi-hart (RVSmp) -- not pthreads / processes.
//
// HOW TO WORK THIS LAB
//   Run("B12_Concurrent.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Processes, threads, synchronization, deadlock. On this port: OnTick /
//   tick_count after a deliberate TrapInit path; Kernel/Drv/RVSmp.HC and
//   kernel_smp demos on the host smoke side. GAP: no pthreads in REPL.
//
// NOTE
//   HolyC reserves the identifier `lock` -- use `lk` / `mtx` in code.
//
// NEXT
//   B13_ThreadLib -- build a cooperative thread package; then Part C.
U0 B12_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}
// Shared counter for race-intuition exercises (single-hart safe here).
I64 B12_counter;
U0 B12_Demo()
{
  Print("B12: concurrency = traps + multi-hart (early)\n");
  Print("  tick_count / OnTick after TrapInit path (do not arm at load)\n");
  Print("  Kernel/Drv/RVSmp.HC + kernel_smp host smokes\n");
  Print("GAP: no pthreads / shared-memory apps in REPL yet.\n");
  B12_counter = 0;
  B12_Expect("B12_counter_init", B12_counter, 0);
}
// Ex1 Warmup: atomic-looking increment on single hart.
I64 B12_Ex1_Inc()
{
  // TODO Fill_in: B12_counter = 0; B12_counter++; return B12_counter;
  return -1;
}
// Ex2: add n times.
I64 B12_Ex2_AddN(I64 n)
{
  I64 i;
  // TODO Fill_in: B12_counter=0; for (i=0;i<n;i++) B12_counter++; return B12_counter;
  return -1;
}
// Ex3: mutex intuition -- flag 0/1. Return 1 if acquired from 0.
I64 B12_Ex3_TryLock(I64 *lk)
{
  // TODO Fill_in:
  //   if (*lk == 0) { *lk = 1; return 1; }
  //   return 0;
  return -1;
}
// Ex4: unlock.
I64 B12_Ex4_Unlock(I64 *lk)
{
  // TODO Fill_in: *lk = 0; return *lk;
  return -1;
}
// Ex5: affirm no pthreads.
I64 B12_Ex5_NoPthreads()
{
  // TODO Fill_in: return 1;
  return -1;
}
// Ex6: timer path still CLINT.
I64 B12_Ex6_Clint()
{
  // TODO Fill_in: return MemMapFind("clint");
  return -1;
}
// Ex7 Challenge: deadlock toy -- two locks taken opposite orders.
// Return 1 if orders (A then B) vs (B then A) can deadlock (yes).
I64 B12_Ex7_DeadlockRisk()
{
  // TODO Fill_in: return 1;
  return -1;
}
// Ex8 Challenge: producer sum 1..n into shared (single hart).
I64 B12_Ex8_Prod(I64 n)
{
  I64 i, s;
  // TODO Fill_in: s=0; for (i=1;i<=n;i++) s+=i; return s;
  s = -1;
  return s;
}

U0 B12_Check()
{
  I64 lk;
  Print("-- B12 exercises --\n");
  B12_Expect("Ex1_Inc", B12_Ex1_Inc(), 1);
  B12_Expect("Ex2_AddN", B12_Ex2_AddN(5), 5);
  lk = 0;
  B12_Expect("Ex3_TryLock", B12_Ex3_TryLock(&lk), 1);
  B12_Expect("Ex3_TryLock_busy", B12_Ex3_TryLock(&lk), 0);
  B12_Expect("Ex4_Unlock", B12_Ex4_Unlock(&lk), 0);
  B12_Expect("Ex5_NoPthreads", B12_Ex5_NoPthreads(), 1);
  B12_Expect("Ex6_Clint", B12_Ex6_Clint(), MEM_CLINT);
  B12_Expect("Ex7_DeadlockRisk", B12_Ex7_DeadlockRisk(), 1);
  B12_Expect("Ex8_Prod", B12_Ex8_Prod(10), 55);
}

U0 B12()
{
  Print("=== B12 CSAPP Ch.12 Concurrent programming ===\n");
  B12_Demo();
  B12_Check();
  Print("Part B Ch.12 done. Thread lib lab: Run(\"B13_ThreadLib.hc\");\n");
}
B12;
