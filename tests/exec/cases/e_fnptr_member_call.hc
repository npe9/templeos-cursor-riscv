// Calling a function pointer held in a CLASS MEMBER: `x.fn(a)` and `p->fn(a)`.
//
// Before this, a fnptr member could not be called in place, and the two halves of the failure
// were not equally visible:
//
//     m.fn(5);          -> "Expected ';' or ','"      a parse error, so it could not ship
//     r = m.fn(5);      -> "Expected ';' or ','"
//     if (m.fn(5)) ..   -> parse error
//     return m.fn(5);   -> COMPILED, and yielded the POINTER VALUE
//
// The last one is the one that matters. Measured at 0x8080007c -- the callee's address inside
// the blob -- where 6 was correct, with no diagnostic at all. So this file's first field is the
// return form: the other seven prove a parse got unblocked, but only that one had a WRONG
// ANSWER to begin with, and it is what proves the fix did something rather than nothing.
//
// Why it needed a compiler change rather than a workaround. The NASA cFS translation is full of
// this idiom -- cFE's fs module alone calls Meta->OnEvent in four places and Meta->GetData in
// one, and es/tbl/evs use the same callback-table shape -- so Kernel/Cfs/osal worked around it
// by copying the member to a local typed variable first and calling that, at four sites, and
// said so in a comment in osapi_common.HC. A workaround repeated across every remaining module
// is a deviation from NASA's source multiplied out, in exactly the dimension the translation
// exists to preserve.
//
// Each form contributes one two-digit field, most significant first:
//
//   06  return m.fn(5)        the silent miscompile
//   11  m.fn(5);             statement, counted by the callee's side effect
//   06  r = m.fn(5)          assignment
//   01  if (m.fn(5) == 6)    condition
//   06  p->fn(5)             through a pointer
//   60  g2(a.fn(5))          argument position
//   77  pb->in->fn(7, 77)    chained, two arguments
//   31  gg.h[1].fn(3)        array of a one-member wrapper class -- the OSAL idiom, because
//                            HolyC has no array-of-function-pointers syntax
//   34  a.get(&a, &v)        an out-parameter written through the call
class Slot
{
  I64 (*fn)(I64 x);
};

class Node
{
  I64 pad;
  I64 (*fn)(I64 x, I64 y);
};

class Outer
{
  I64 pad;
  Node *in;
};

class Getter
{
  I64 (*get)(I64 *out);
};

class Bank
{
  Slot h[4];
};
I64 Inc(I64 x);
I64 Times10(I64 y);
I64 Pair100(I64 x, I64 y);
I64 PutOut(I64 *out);
I64 RetForm();
I64 g_calls;
Bank g_bank;
I64 main()
{
  Slot a;
  Slot *p;
  Node n;
  Outer o;
  Outer *po;
  Getter gt;
  I64 r = 0;
  I64 v = 0;
  a.fn = &Inc;
  p = &a;
  // 1. the return form -- compiled to the pointer value before the fix
  r = r * 100 + RetForm();
  // 2. statement form: the call must HAPPEN, so count it in the callee
  g_calls = 10;
  a.fn(5);
  r = r * 100 + g_calls;
  // 3. assignment form
  v = a.fn(5);
  r = r * 100 + v;
  // 4. condition form
  if (a.fn(5) == 6)
    r = r * 100 + 1;
  else
    r = r * 100 + 99;
  // 5. through a pointer
  r = r * 100 + p->fn(5);
  // 6. argument position -- a call inside another call's argument list
  r = r * 100 + Times10(a.fn(5));
  // 7. chained member access, two arguments
  n.fn = &Pair100;
  o.in = &n;
  po = &o;
  r = r * 100 + po->in->fn(7, 77) % 100;
  // 8. array of a one-member wrapper class: `I64 (*h[4])(I64)` does not parse at any scope, so
  //    OSAL's event-handler table is an array of a class holding the single pointer.
  g_bank.h[1].fn = &Inc;
  r = r * 100 + g_bank.h[1].fn(30);
  // 9. an out-parameter written through the call, which a load-of-the-pointer cannot fake
  gt.get = &PutOut;
  v = 0;
  gt.get(&v);
  r = r * 100 + v % 100;
  return r;
}

I64 Inc(I64 x)
{
  g_calls++;
  return x + 1;
}

I64 Times10(I64 y)
{
  return y * 10;
}

I64 Pair100(I64 x, I64 y)
{
  return x * 100 + y;
}

I64 PutOut(I64 *out)
{
  *out = 1234;
  return 0;
}
// The return form gets its own function so the value under test is the CALL's result and not
// something an outer expression could have supplied.
I64 RetForm()
{
  Slot m;
  m.fn = &Inc;
  return m.fn(5);
}
