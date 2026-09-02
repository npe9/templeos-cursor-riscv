// PjPutHex-style indexed store: must stay sb …,0(t0) — never sb a0,0(a0).
// Pattern gate in run_compiler_stress.sh (not an exec oracle).
U0 F()
{
  U8 b[16];
  I64 n;
  I64 A;
  I64 d;
  n = 0;
  A = 10;
  d = 5;
  b[n++] = A + d - 10;
}

I64 main()
{
  return 0;
}
