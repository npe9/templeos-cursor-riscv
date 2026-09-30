// Compound assignment to a NARROW struct field must not disturb the field next to it.
//
// The host compiler used to emit every `x op= y` as a 64-BIT read-modify-write, whatever the
// destination's width, because the compound paths in ParseAssignment passed RT_I64 while the
// plain `=` path had long computed the real width. On a 4-byte field that reads and writes 8
// bytes, so the NEXT field is part of the arithmetic.
//
// It hid well. `a += 5` looks correct, because a small addend does not carry out of bit 31.
// It is wrong exactly when the operation crosses that boundary:
//
//     a *= 2   multiplies the neighbour too      (10,20 -> a=20, b=40)
//     a -= 3   with a == 0 BORROWS from it       (0,7   -> a=-3, b=6)
//
// Found by the NASA cFS OSAL timer translation. OS_TimeBase_CallbackThread does
//     timecb->wait_time -= tick_time;
// on an int32 whose neighbour is interval_time, so a ONE-SHOT timer -- the one with
// interval_time == 0 -- had its interval borrowed down to -1 and then fired on every
// subsequent tick instead of once. The differential gate caught it as t2 firing 3 times where
// NASA's own C fired it once; the cause was two fields down, not in the translation.
//
// Each step below leaves the NEIGHBOUR's value in the accumulator, so a 64-bit
// read-modify-write changes the answer.
class Pair
{
  I32 a;
  I32 b;
};

Pair g;

I64 main()
{
  I64 r = 0;
  U32 three = 3;

  // multiply: b must stay 20, not become 40
  g.a = 10;
  g.b = 20;
  g.a *= 2;
  r = r * 100 + g.b;

  // subtract with a borrow out of bit 31: b must stay 7, not become 6
  g.a = 0;
  g.b = 7;
  g.a -= 3;
  r = r * 100 + g.b;

  // the same borrow with an unsigned operand, which is how the OSAL case was written
  g.a = 0;
  g.b = 9;
  g.a -= three;
  r = r * 100 + g.b;

  // and the field itself must still hold the right value
  r = r * 100 + (-g.a);
  return r;
}
