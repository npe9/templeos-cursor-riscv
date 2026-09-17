// Kernel-image fault freeze: the C runtime's trap vector (holy_rt.h HolyTrapVector) must save
// EVERY GPR and publish the same two views as the seed image — legacy slots at 0x87000100 and
// the canonical x0..x31 array at 0x87000400 — or a debugger reading one image cannot read the
// other. Plants markers in s1/s2/s5/s11/gp/tp, faults, recovers, and reads them back.
#define TRAP_SNAP   0x87000100
#define TRAP_SNAP_X 0x87000400
#define MEM_UART    0x10000000

extern U0 RVTrapInit();
extern I64 RVTrapRecoverArm();
extern I64 RVTrapRecoverCause();

U0 TfPutS(U8 *s)
{
  U8 *uart = MEM_UART;
  while (*s)
    *uart = *s++;
}

U0 TfHex(I64 v)
{
  U8 *uart = MEM_UART;
  I64 i, d;
  i = 60;
  while (i >= 0) {
    d = (v >> i) & 15;
    *uart = d < 10 ? '0' + d : 'a' + d - 10;
    i -= 4;
  }
}

U0 TfField(U8 *name, I64 got, I64 want)
{
  TfPutS(name);
  TfPutS("=");
  TfHex(got);
  TfPutS(got == want ? " ok\n" : " BAD\n");
}

I64 TfX(I64 n)
{
  return *(I64 *)(TRAP_SNAP_X + n * 8);
}

I64 main()
{
  I64 bad;
  RVTrapInit();
  if (!RVTrapRecoverArm()) {
    // Plant, then fault on a load from address 4. Recovery resumes after the `if`.
    asm {
	li	s1, 0x51
	li	s2, 0x52
	li	s5, 0x55
	li	s11, 0x5B
	li	gp, 0x63
	li	tp, 0x64
	li	t0, 4
	ld	t1, 0(t0)
    }
  }
  TfPutS("trapframe: recovered cause=");
  TfHex(RVTrapRecoverCause());
  TfPutS("\n");
  TfField("s1", TfX(9), 0x51);
  TfField("s2", TfX(18), 0x52);
  TfField("s5", TfX(21), 0x55);
  TfField("s11", TfX(27), 0x5B);
  TfField("gp", TfX(3), 0x63);
  TfField("tp", TfX(4), 0x64);
  TfField("x0", TfX(0), 0);
  // Legacy view must still agree: slot 18 = mcause (5 = load access fault), 16 = sp = x2.
  TfField("mcause", *(I64 *)(TRAP_SNAP + 18 * 8), 5);
  TfField("spmatch", *(I64 *)(TRAP_SNAP + 16 * 8) == TfX(2), 1);
  TfField("mstatus_nz", *(I64 *)(TRAP_SNAP + 21 * 8) != 0, 1);
  bad = TfX(9) != 0x51 || TfX(18) != 0x52 || TfX(21) != 0x55 || TfX(27) != 0x5B ||
        TfX(3) != 0x63 || TfX(4) != 0x64 || TfX(0) != 0;
  if (bad)
    TfPutS("trapframe: FAIL\n");
  else
    TfPutS("trapframe: PASS\n");
  return 0;
}
