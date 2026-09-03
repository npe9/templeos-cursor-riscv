// B08_ECF.hc -- CSAPP 3e Ch.8: Exceptional Control Flow
// Remap: traps / CLINT timer / Reset / Fault -- not Linux signals or fork/exec.
//
// HOW TO WORK THIS LAB
//   Run("B08_ECF.hc");  edit Fill_in;  Run again.
//   SAFETY: do not TrapInit at lesson load (see A05).
//
// BOOK THEMES
//   Exceptions, process control, signals. Bare metal: sync faults vs async
//   IRQs, soft Reset vs Halt, timer OnTick. No fork -- concurrency is B12.
//
// NEXT
//   B09_VM -- honest gap + physical MEM_* stand-in.
U0 B08_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 B08_Demo()
{
  Print("B08 ECF on bare metal:\n");
  Print("  async: CLINT timer IRQ (Man(\"CLINT\"))\n");
  Print("  sync:  Fault; / illegal op paths\n");
  Print("  soft:  Reset; HardReset; Halt;\n");
  Print("mstatus=%X mie=%X\n", GetMStatus(), GetMie());
  Print("Do not TrapInit at lesson load.\n");
  B08_Expect("B08_clint", MemMapFind("clint"), MEM_CLINT);
}
// Ex1 Warmup: timer tick is interrupt (1) not fault (0).
I64 B08_Ex1_TimerClass()
{
  // TODO Fill_in: return 1;
  return -1;
}
// Ex2: Fault; is sync exceptional flow -- return 0 for "interrupt"? No:
// return 0 meaning "not an IRQ" / sync.
I64 B08_Ex2_FaultIsSync()
{
  // TODO Fill_in: return 1;  // yes, sync
  return 0;
}
// Ex3: bring-up order code 1234 (SetTrap,TrapInit,TimerArm,wait).
I64 B08_Ex3_Order()
{
  // TODO Fill_in: return 1234;
  return 0;
}
// Ex4: CLINT base.
I64 B08_Ex4_Clint()
{
  // TODO Fill_in: return MemMapFind("clint");
  return 0;
}
// Ex5: Reset symbol linked.
I64 B08_Ex5_ResetLinked()
{
  // TODO Fill_in: if (FnAddr("Reset")) return 1; return 0;
  return 0;
}
// Ex6: GetMStatus readable (echo).
I64 B08_Ex6_MStatus()
{
  // TODO Fill_in: return GetMStatus();
  return -1;
}
// Ex7 Challenge: do not TrapInit at load -- affirm 1.
I64 B08_Ex7_Safe()
{
  // TODO Fill_in: return 1;
  return 0;
}
// Ex8 Challenge: mtimecmp - clint == OFF.
I64 B08_Ex8_Off()
{
  // TODO Fill_in: return MEM_MTIMECMP - MEM_CLINT;
  return 0;
}

U0 B08_Check()
{
  Print("-- B08 exercises --\n");
  B08_Expect("Ex1_TimerClass", B08_Ex1_TimerClass(), 1);
  B08_Expect("Ex2_FaultIsSync", B08_Ex2_FaultIsSync(), 1);
  B08_Expect("Ex3_Order", B08_Ex3_Order(), 1234);
  B08_Expect("Ex4_Clint", B08_Ex4_Clint(), MEM_CLINT);
  B08_Expect("Ex5_ResetLinked", B08_Ex5_ResetLinked(), 1);
  B08_Expect("Ex6_MStatus", B08_Ex6_MStatus(), GetMStatus());
  B08_Expect("Ex7_Safe", B08_Ex7_Safe(), 1);
  B08_Expect("Ex8_Off", B08_Ex8_Off(), MEM_CLINT_MTIMECMP_OFF);
}

U0 B08()
{
  Print("=== B08 CSAPP Ch.8 Exceptional control flow ===\n");
  B08_Demo();
  B08_Check();
  Print("Next: Run(\"B09_VM.hc\");\n");
}
B08;
