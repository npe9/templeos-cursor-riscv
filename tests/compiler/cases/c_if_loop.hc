// if + while accumulator (control-flow codegen).
I64 main()
{
  I64 i;
  I64 s;
  s = 0;
  i = 0;
  while (i < 10) {
    if (i & 1)
      s += i;
    else
      s += 1;
    i++;
  }
  // evens: five × +1 = 5; odds: 1+3+5+7+9 = 25; total 30.
  return s;
}
