// hwdbg.hc -- Hardware trigger CSRs (Sdtrig / Debug 0.13 mcontrol) + host gdb twin.
// Additive to soft Watch/Step in debug.hc — do not rewrite those paths (dbg lane G1).
// Dig-down: docs/DEBUGGER.md § Hardware. Host attach: make hwdbg-smoke / BAREMETAL.md.
//
// On QEMU virt (rv64, debug=on): tselect/tdata*/tinfo are M-mode accessible.
// dcsr/dpc are Debug-mode only — HwStep documents host gdb stepi, not guest dcsr.step.
// Trigger action=0 raises breakpoint exception (cause 3) → DbgTrap / trapvec.
//
// mcontrol match bits (QEMU debug.h): load=1 store=2 exec=4 M=64
// type2 = 0x2000000000000000, type6 = 0x6000000000000000
I64 HwTrigArmed;
I64 HwTrigAddr;
I64 HwTrigBits;
asm {
	HcGetTSelect::
	csrr	a0, 0x7a0
	ret
	HcSetTSelect::
	csrw	0x7a0, a0
	ret
	HcGetTData1::
	csrr	a0, 0x7a1
	ret
	HcSetTData1::
	csrw	0x7a1, a0
	ret
	HcGetTData2::
	csrr	a0, 0x7a2
	ret
	HcSetTData2::
	csrw	0x7a2, a0
	ret
	HcGetTInfo::
	csrr	a0, 0x7a4
	ret
}

I64 GetTSelect()
{
  return HcGetTSelect();
}

U0 SetTSelect(I64 v)
{
  HcSetTSelect(v);
}

I64 GetTData1()
{
  return HcGetTData1();
}

U0 SetTData1(I64 v)
{
  HcSetTData1(v);
}

I64 GetTData2()
{
  return HcGetTData2();
}

U0 SetTData2(I64 v)
{
  HcSetTData2(v);
}

I64 GetTInfo()
{
  return HcGetTInfo();
}

I64 HwTrigPresent()
{
  I64 info;
  info = GetTInfo();
  // tinfo bit N set ⇒ type N supported. Need type 2 and/or 6.
  if (info & 0x44)
    return 1;
  return 0;
}

I64 HwTrigBuild(I64 bits)
{
  I64 info, body;
  body = bits & 0x47;
  // load|store|exec|M
  info = GetTInfo();
  if (info & 4)
    return 0x2000000000000000 | body;
  if (info & 0x40)
    return 0x6000000000000000 | body;
  return 0;
}
// HwTrigProbe -- HwTrigProbe()
// NAME
//   HwTrigProbe - probe Sdtrig / mcontrol CSRs (tselect tdata1 tinfo)
// SYNOPSIS
//   HwTrigProbe;
// DESCRIPTION
//   Reads trigger-module CSRs from M-mode. On QEMU virt expect tinfo with types
//   2 and/or 6 (often 0x44). Returns 1 if a usable match trigger exists.
// EXAMPLES
//   HwTrigProbe;  HwHelp;
// SEE ALSO
//   HwWatch  HwBreak  HwClr  Man("HwDbg")  docs/DEBUGGER.md
// BUGS
//   Boards without a Trigger Module may illegal-instruction on csrr.
I64 HwTrigProbe()
{
  I64 info, t1, sel;
  UartStr("HWDBG_PROBE_OK\n");
  sel = GetTSelect();
  t1 = GetTData1();
  info = GetTInfo();
  "HwTrigProbe: tselect=0x%X tdata1=0x%X tinfo=0x%X\n", sel, t1, info;
  if (info & 0x44) {
    UartStr("HwTrigProbe: match trigger present (type 2 and/or 6)\n");
    return 1;
  }
  UartStr("HwTrigProbe: no type-2/6 match trigger (use soft Watch/Step or host gdb)\n");
  return 0;
}

U0 HwTrigDisarm()
{
  SetTSelect(0);
  SetTData1(0);
  HwTrigArmed = 0;
  HwTrigAddr = 0;
  HwTrigBits = 0;
}

U0 HwTrigArm(I64 addr, I64 bits)
{
  I64 t1, rb;
  if (!addr) {
    UartStr("HwTrigArm: null address\n");
    return;
  }
  if (!HwTrigPresent()) {
    UartStr("HwTrigArm: no trigger module — soft Watch/Bp or make hwdbg-smoke\n");
    return;
  }
  t1 = HwTrigBuild(bits | 64);
  if (!t1) {
    UartStr("HwTrigArm: cannot build mcontrol value\n");
    return;
  }
  SetTSelect(0);
  SetTData1(0);
  SetTData2(addr);
  SetTData1(t1);
  rb = GetTData1();
  HwTrigArmed = 1;
  HwTrigAddr = addr;
  HwTrigBits = bits;
  // Same soft trap path as Bp — call TrapInit/SetTrap from the REPL if needed:
  //   SetTrap("DbgTrap"); TrapInit;
  "HwTrigArm: addr=0x%X bits=0x%X tdata1=0x%X (readback 0x%X)\n", addr, bits, t1, rb;
  if ((rb & 7) == 0)
    UartStr("HwTrigArm: WARNING - match bits cleared by WARL; trigger may be inert\n");
}

U0 HwWatch(I64 addr)
{
  HwTrigArm(addr, 2);
  if (HwTrigArmed)
    "HwWatch: armed store watch @ 0x%X (HW; soft twin is Watch)\n", addr;
}

U0 HwBreak(I64 addr)
{
  HwTrigArm(addr, 4);
  if (HwTrigArmed)
    "HwBreak: armed exec trigger @ 0x%X (HW; soft twin is Bp)\n", addr;
}

U0 HwClr()
{
  HwTrigDisarm();
  UartStr("HwClr: trigger 0 disabled\n");
}

U0 HwTrigs()
{
  if (!HwTrigArmed) {
    UartStr("HwTrigs: (none armed)\n");
    return;
  }
  "HwTrigs: addr=0x%X bits=0x%X tdata1=0x%X tdata2=0x%X\n", HwTrigAddr, HwTrigBits, GetTData1(), GetTData2();
}

U0 HwStep()
{
  UartStr("HwStep: dcsr.step not available from M-mode on virt\n");
  UartStr("  soft: Step; StepOver;   host: make hwdbg-smoke / gdb stepi\n");
}

U0 HwHelp()
{
  UartStr("HWDBG_HELP_OK\n");
  UartStr("HwHelp - hardware triggers + host gdb (docs/DEBUGGER.md)\n");
  UartStr("  HwTrigProbe;                 // tselect/tdata1/tinfo\n");
  UartStr("  HwWatch(&x); HwBreak(&F);    // mcontrol store / exec\n");
  UartStr("  HwTrigs; HwClr;              // list / disarm trigger 0\n");
  UartStr("  HwStep;                      // points at soft Step / host stepi\n");
  UartStr("  Host: make hwdbg-smoke       // QEMU -S -gdb + riscv64-*-gdb\n");
  UartStr("  Soft twins: Watch; Bp; Step; DbgHelp; Man(\"Debugger\");\n");
}
