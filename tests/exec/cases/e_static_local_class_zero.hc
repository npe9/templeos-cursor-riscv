// A `static` LOCAL OF CLASS TYPE STARTS ZEROED AND PERSISTS ACROSS CALLS.
//
// NASA's CFE_TIME_ToneVerify (cfe_time_tone.c) writes
//
//     static CFE_TIME_SysTime_t PrevTime1 = { 0, 0 };
//     static CFE_TIME_SysTime_t PrevTime2 = { 0, 0 };
//
// and the whole of its duplicate-tone detection is a comparison against them. HolyC has no
// aggregate initialiser, so the translation writes the bare declaration and RELIES on a static
// local of class type being zero on the first call -- which is C's rule, but this compiler's
// statics are its own code path (docs/HOLYC_STRUCT_LIMITS.md #12 rewrote it), and "a spacecraft
// clock happens to work" is not a thing to find out later.
//
// Two properties, and the sequence below separates them: the FIRST call must read zeros, and
// every later call must read what the previous call left. A static that were re-zeroed on entry
// would pass the first property and fail the second; one that lived on the stack would fail both.
#define XUART 0x10000000
U0 S(U8 *s)
{
  U8 *u = XUART;
  while (*s)
    *u = *s++;
}

class P
{
  I64 a;
  I64 b;
};
// Returns what the PREVIOUS call stored, then stores this call's values. The first call must
// return 0, which is the only thing that can tell a zeroed static from an uninitialised one.
I64 Step(I64 v)
{
  static P Prev;
  I64 was = Prev.a * 10 + Prev.b;
  Prev.a = v;
  Prev.b = v + 1;
  return was;
}

I64 main()
{
  I64 r = 0;
  r = r * 1000 + Step(3);
  // 0 -- zero on the first call
  r = r * 1000 + Step(7);
  // 34 -- what Step(3) left
  r = r * 1000 + Step(0);
  // 78
  r = r * 1000 + Step(5);
  // 1 -- a zero STORED is not the same as never stored, so Step(0) must be readable back
  return r;
}
