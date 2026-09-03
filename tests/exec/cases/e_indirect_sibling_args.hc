// SetCallArgCnt must stamp the arg count on the just-emitted call IC, not the last call in the
// whole IC list. The corruptible pattern is ANY earlier call followed by an indirect call of a
// different arity: the indirect path's pre-emit stamp would land the new count on the earlier
// call's already-emitted IC, so that call marshals the wrong number of arguments.
//   (a) a direct call followed by an indirect call (the common case);
//   (b) two indirect member-fp calls of different arity in one if/else (the kernel's PutS:
//       `(*tmpk->put_s)(st)` (1 arg) vs `(*tmpk->put_key)(ch,0)` (2 args)).
I64 add3(I64 a, I64 b, I64 c)
{
  return a + b + c;
}

I64 one(I64 x)
{
  return x;
}
I64 (*g_fp)(I64) = &one;
class FP
{
  Bool (*put_key)(I64 ch, I64 sc);
  Bool (*put_s)(U8 *st);
};
U8 *cap_s;
I64 cap_k;
Bool PS(U8 *st)
{
  cap_s = st;
  return TRUE;
}

Bool PK(I64 ch, I64 sc)
{
  cap_k = ch;
  return TRUE;
}

I64 dispatch(FP *p, U8 *st, Bool use_s)
{
  if (use_s) {
    if ((*p->put_s)(st))
      return 1;
  } else {
    I64 ch = *st;
    if ((*p->put_key)(ch, 0))
      return 2;
  }
  return 0;
}

I64 main()
{
  // (a) direct call then indirect call of different arity
  I64 r = add3(1, 2, 3);
  // 3-arg direct call, IC emitted first
  I64 s = (*g_fp)(7);
  // 1-arg indirect call must not restamp add3
  // (b) sibling member-fp calls of different arity
  FP f;
  f.put_s = &PS;
  f.put_key = &PK;
  U8 *msg = "Z";
  dispatch(&f, msg, TRUE);
  dispatch(&f, "Q", FALSE);
  return (r == 6) * 1 + (s == 7) * 2 + (cap_s == msg) * 4 + (cap_k == 'Q') * 8 + (dispatch(&f, msg, TRUE) == 1) * 16;
  // 0x1f
}
