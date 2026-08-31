// Call through a memory slot that holds a code address (host-ABI style once-indirect).
I64 Add(I64 a, I64 b)
{
  return a + b;
}
I64 slot;
I64 main()
{
  I64 (*fp)(I64, I64);
  slot = &Add;
  fp = *(I64 *)(&slot);
  return fp(30, 19);
  // 49
}
