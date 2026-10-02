// A SMALL CLASS PASSED BY VALUE ARRIVES INTACT, AND IS A COPY.
//
// The cFS translation needs this: NASA's CFE_SB_SubscribeEx, CFE_SB_SubscribeFull and
// CFE_SB_SendSubscriptionReport all take a `CFE_SB_Qos_t Quality` BY VALUE, and
// CFE_SB_Qos_t is two bytes (Priority, Reliability). Translating those signatures 1:1 means
// the compiler has to pass a class in a register and leave the caller's copy alone.
//
// Three shapes, because the register-pair boundary is where this would break:
//   - a 2-byte class, the Qos case itself;
//   - an 8-byte class, the largest that fits one register;
//   - mutation inside the callee, which must NOT be visible to the caller. If a by-value
//     parameter were quietly passed by reference, every function here that scribbles on its
//     argument would corrupt the caller, and the differential transcript would diverge somewhere
//     far away from the cause.
class Small
{
  U8 a;
  U8 b;
};

class Eight
{
  I32 lo;
  I32 hi;
};

I64 main();

I64 TakeSmall(Small s)
{
  s.a = 99;
  // must not reach the caller
  return s.b;
}

I64 TakeEight(Eight e)
{
  return e.hi - e.lo;
}

I64 main()
{
  Small s;
  Eight e;
  I64 r = 0;
  s.a = 3;
  s.b = 7;
  e.lo = 11;
  e.hi = 40;
  r = r * 100 + TakeSmall(s);
  // 7 -- the second byte survived the call
  r = r * 100 + s.a;
  // 3, NOT 99 -- the callee mutated its own copy
  r = r * 100 + TakeEight(e);
  // 29
  return r;
}
