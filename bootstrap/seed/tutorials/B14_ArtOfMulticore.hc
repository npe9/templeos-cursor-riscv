// B14_ArtOfMulticore.hc -- The Art of Multiprocessor Programming (Herlihy & Shavit)
// Prereq: B12 + B13. Remap: shared-memory principles on this RV64 HolyC port
// (single-hart REPL demos; real multi-hart = RVSmp / A-extension AMOs).
//
// HOW TO WORK THIS LAB
//   Run("B14_ArtOfMulticore.hc");  Src/Vi Fill_in;  Run again until PASS.
//
// BOOK MAP (2e chapter themes → this lab)
//   Ch.2 Mutual exclusion     → TAS spin mtx (try / unlock)
//   Ch.5 Sync primitives       → CAS (compare-and-swap) power
//   Ch.6 Universality         → CAS implements n-consensus (yes)
//   Ch.7 Spin locks           → TAS busy-wait (contention)
//   Ch.10 Queues / ABA        → ABA risk flag
//   Ch.18 Barriers (2e)       → sense-reversing arrive count
//   Hardware                  → RISC-V amoadd / amoswap; CLINT MSIP (RVSmp)
//
// NOTE
//   HolyC reserves `lock` -- use `mtx` / `lk`. CAS here is a HolyC helper
//   (single-hart). On multi-hart use RVAmoAddI64 / amoswap.d (Kernel/Drv/RVSmp.HC).
//
// NEXT
//   Part C: Run("C01_Background.hc");  Dig-down: make kernel-smp-smoke
I64 AMP_cell;
I64 AMP_mtx;
U0 B14_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}
// TAS: test-and-set. Returns old *mtx (0 = you acquired).
I64 AMP_TAS(I64 *mtx)
{
  I64 old;
  old = *mtx;
  *mtx = 1;
  return old;
}
// CAS: if *addr == expect, store desire; return 1 on success.
I64 AMP_CAS(I64 *addr, I64 expect, I64 desire)
{
  if (*addr != expect)
    return 0;
  *addr = desire;
  return 1;
}
// Lock-free fetch-and-add via CAS loop (Herlihy: CAS is universal).
I64 AMP_FAA(I64 *addr, I64 inc)
{
  I64 old;
  while (1) {
    old = *addr;
    if (AMP_CAS(addr, old, old + inc))
      return old;
  }
  return 0;
}

U0 B14_Demo()
{
  I64 old;
  Print("B14: Art of Multiprocessor Programming → RV64 HolyC\n");
  Print("  TAS mtx + CAS FAA (single-hart model of shared memory)\n");
  Print("  GAP: true races need -smp + RVSmpWake / RVAmoAddI64\n");
  AMP_mtx = 0;
  B14_Expect("B14_TAS_acq", AMP_TAS(&AMP_mtx), 0);
  B14_Expect("B14_TAS_busy", AMP_TAS(&AMP_mtx), 1);
  AMP_mtx = 0;
  AMP_cell = 10;
  old = AMP_FAA(&AMP_cell, 5);
  B14_Expect("B14_FAA_old", old, 10);
  B14_Expect("B14_FAA_new", AMP_cell, 15);
}
// ---- Exercises (Fill_in) ---------------------------------------------------
// Ex1 Warmup: TAS acquire from unlocked (0) returns 0.
I64 B14_Ex1_TasAcq()
{
  I64 mtx;
  // TODO Fill_in: mtx = 0; return AMP_TAS(&mtx);
  return -1;
}
// Ex2: after TAS, unlock by storing 0; then TAS again returns 0.
I64 B14_Ex2_TasUnlock()
{
  I64 mtx;
  // TODO Fill_in:
  //   mtx = 0; AMP_TAS(&mtx); mtx = 0; return AMP_TAS(&mtx);
  return -1;
}
// Ex3: CAS success 7→9.
I64 B14_Ex3_CasOk()
{
  I64 x;
  // TODO Fill_in: x = 7; return AMP_CAS(&x, 7, 9);
  return -1;
}
// Ex4: CAS fail when expect wrong; cell unchanged (return cell).
I64 B14_Ex4_CasFail()
{
  I64 x;
  // TODO Fill_in: x = 7; AMP_CAS(&x, 8, 9); return x;
  return -1;
}
// Ex5: FAA add 3 to 0 → return new value (old+3).
I64 B14_Ex5_FaaNew()
{
  I64 x;
  // TODO Fill_in: x = 0; AMP_FAA(&x, 3); return x;
  return -1;
}
// Ex6: Consensus power — CAS can solve consensus for any n. Return 1.
I64 B14_Ex6_CasUniversal()
{
  // TODO Fill_in: return 1;
  return -1;
}
// Ex7: Lock-free means some thread always makes progress (even if others
// stall). Wait-free means every thread finishes in bounded steps.
// Return 2 for "lock-free weaker than wait-free" teaching code.
I64 B14_Ex7_ProgressLevels()
{
  // TODO Fill_in: return 2;
  return -1;
}
// Ex8: ABA — reuse of a popped node can fool CAS. Affirm risk: return 1.
I64 B14_Ex8_AbaRisk()
{
  // TODO Fill_in: return 1;
  return -1;
}
// Ex9: Barrier arrive — sense flip when last of n arrives.
// count starts at 0; each arrive ++count; if count==n, return 1 else 0.
I64 B14_Ex9_BarrierLast(I64 *count, I64 n)
{
  // TODO Fill_in:
  //   *count = *count + 1;
  //   if (*count == n) return 1;
  //   return 0;
  return -1;
}
// Ex10 Challenge: multi-hart IPI / wake uses CLINT (same as B13 / RVSmpMsip).
I64 B14_Ex10_Clint()
{
  // TODO Fill_in: return MemMapFind("clint");
  return 0;
}

U0 B14_Check()
{
  I64 c;
  Print("-- B14 exercises --\n");
  B14_Expect("Ex1_TasAcq", B14_Ex1_TasAcq(), 0);
  B14_Expect("Ex2_TasUnlock", B14_Ex2_TasUnlock(), 0);
  B14_Expect("Ex3_CasOk", B14_Ex3_CasOk(), 1);
  B14_Expect("Ex4_CasFail", B14_Ex4_CasFail(), 7);
  B14_Expect("Ex5_FaaNew", B14_Ex5_FaaNew(), 3);
  B14_Expect("Ex6_CasUniversal", B14_Ex6_CasUniversal(), 1);
  B14_Expect("Ex7_ProgressLevels", B14_Ex7_ProgressLevels(), 2);
  B14_Expect("Ex8_AbaRisk", B14_Ex8_AbaRisk(), 1);
  c = 0;
  B14_Expect("Ex9_Barrier_notlast", B14_Ex9_BarrierLast(&c, 3), 0);
  B14_Expect("Ex9_Barrier_mid", B14_Ex9_BarrierLast(&c, 3), 0);
  B14_Expect("Ex9_Barrier_last", B14_Ex9_BarrierLast(&c, 3), 1);
  B14_Expect("Ex10_Clint", B14_Ex10_Clint(), MEM_CLINT);
}

U0 B14()
{
  Print("=== B14 Art of Multiprocessor Programming ===\n");
  B14_Demo();
  B14_Check();
  Print("Next: Run(\"C01_Background.hc\");  or Tutorial;\n");
  Print("Hardware: RVAmoAddI64 / RVSmpWake  Kernel/Drv/RVSmp.HC\n");
}
B14;
