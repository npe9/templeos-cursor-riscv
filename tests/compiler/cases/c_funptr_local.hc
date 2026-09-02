// Call via local function pointer (soft funptr / IC_CALL_INDIRECT stress).
I64 Add(I64 a, I64 b)
{
  return a + b;
}

I64 main()
{
  I64 (*fp)(I64, I64);
  fp = &Add;
  return (*fp)(40, 2);
}
