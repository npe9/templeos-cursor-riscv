// A05_CSRTraps.hc -- Part A5: CSRs, traps, CLINT timer story
//
// HOW TO WORK THIS LAB
//   Run("A05_CSRTraps.hc");  edit Fill_in;  Run again.
//   SAFETY: do NOT call TrapInit / TimerArm / SetTrap at file-load time.
//   Those swap mtvec mid-REPL and can wedge the session. Learn the path,
//   then arm interactively from Help's one-liner when you mean it.
//
// LEARNING GOALS
//   Control-status registers (CSRs) configure privilege, interrupts, and
//   trap entry. This REPL runs in M-mode bare metal. Useful reads:
//     GetMStatus() / Reg("mstatus")  -- privilege / IE / FS bits
//     GetMie()                       -- interrupt enable mask
//   Machine timer: CLINT mtime / mtimecmp (MEM_MTIME, MEM_MTIMECMP).
//   When mtime >= mtimecmp and MTIE+MIE allow it, a timer interrupt fires.
//
//   Trap path (conceptual): SetTrap("OnTick") -> TrapInit -> TimerArm ->
//   wfi / wait for IRQ -> OnTick re-arms. See Man("CLINT"); Man("Reset");
//   timer.hc / trap.hc.
//
//   Sync faults (illegal op, Fault;) vs async interrupts (timer) are both
//   "exceptional control flow" -- CSAPP Ch.8 remaps here in B08.
//
// NEXT
//   A06_AsmHolyC -- unlabeled asm{} constraints and Tab completion.
U0 A05_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 A05_Demo()
{
  I64 ms;
  Print("A05 demo: read mstatus; locate CLINT; datasheet decode\n");
  ms = GetMStatus();
  Print("mstatus=%X\n", ms);
  Reg("mstatus");
  Bits("mstatus");
  Print("MEM_CLINT=%X MEM_MTIME=%X MEM_MTIMECMP=%X\n", MEM_CLINT, MEM_MTIME, MEM_MTIMECMP);
  Print("MemMapFind(\"clint\")=%X\n", MemMapFind("clint"));
  Print("Try: DsDecode(\"uart.lsr\", 0x21); Man(\"Datasheet\");\n");
  Print("GAP: not calling TrapInit/TimerArm from lesson load.\n");
  A05_Expect("A05_clint_sym", MemMapFind("clint"), MEM_CLINT);
  A05_Expect("A05_mstatus_readable", ms != 0 || ms == 0, 1);
  // always true; proves call
}
// Ex1 Warmup: return current mstatus via GetMStatus (any value ok if nonzero
// OR zero -- we only check the call works by echoing).
I64 A05_Ex1_ReadMStatus()
{
  // TODO Fill_in: return GetMStatus();
  return -1;
}
// Ex2: CLINT base from MemMapFind.
I64 A05_Ex2_Clint()
{
  // TODO Fill_in: return MemMapFind("clint");
  return 0;
}
// Ex3: mtime address equals MEM_MTIME.
I64 A05_Ex3_Mtime()
{
  // TODO Fill_in: return MemMapFind("mtime");
  return 0;
}
// Ex4: order the timer bring-up as a code 1234 permutation.
// Correct order: SetTrap=1, TrapInit=2, TimerArm=3, then wait/wfi=4.
// Return 1234 if you encode steps as digits in that order.
I64 A05_Ex4_Order()
{
  // TODO Fill_in: return 1234;
  return 0;
}
// Ex5: timer IRQ is asynchronous interrupt, not a sync fault.
// Return 1 for interrupt, 0 for fault.
I64 A05_Ex5_TimerIsIrq()
{
  // TODO Fill_in: return 1;
  return -1;
}
// Ex6: mtimecmp offset from CLINT base on this map.
// MEM_MTIMECMP - MEM_CLINT should match MEM_CLINT_MTIMECMP_OFF.
I64 A05_Ex6_MtimecmpOff()
{
  // TODO Fill_in: return MEM_MTIMECMP - MEM_CLINT;
  return 0;
}
// Ex7 Challenge: read mie (may be 0). Return GetMie() -- harness checks
// that two reads agree (stable enough for smoke).
I64 A05_Ex7_Mie()
{
  // TODO Fill_in: return GetMie();
  return -2;
}
// Ex8 Challenge: why lesson must not TrapInit at load -- return 1 if you
// agree "mtvec swap mid-boot is unsafe" (true on this REPL).
I64 A05_Ex8_NoTrapAtLoad()
{
  // TODO Fill_in: return 1;
  return 0;
}

U0 A05_Check()
{
  I64 a, b;
  Print("-- A05 exercises --\n");
  a = A05_Ex1_ReadMStatus();
  b = GetMStatus();
  A05_Expect("Ex1_ReadMStatus", a, b);
  A05_Expect("Ex2_Clint", A05_Ex2_Clint(), MEM_CLINT);
  A05_Expect("Ex3_Mtime", A05_Ex3_Mtime(), MEM_MTIME);
  A05_Expect("Ex4_Order", A05_Ex4_Order(), 1234);
  A05_Expect("Ex5_TimerIsIrq", A05_Ex5_TimerIsIrq(), 1);
  A05_Expect("Ex6_MtimecmpOff", A05_Ex6_MtimecmpOff(), MEM_CLINT_MTIMECMP_OFF);
  a = A05_Ex7_Mie();
  A05_Expect("Ex7_Mie", a, GetMie());
  A05_Expect("Ex8_NoTrapAtLoad", A05_Ex8_NoTrapAtLoad(), 1);
}

U0 A05()
{
  Print("=== A05 CSR & traps ===\n");
  Print("Man(\"CLINT\"); Man(\"Reset\"); MemMapFind(\"clint\");\n");
  A05_Demo();
  A05_Check();
  Print("Next: Run(\"A06_AsmHolyC.hc\");\n");
}
A05;
