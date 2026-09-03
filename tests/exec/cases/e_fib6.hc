I64 Fib(I64 n);
I64 main()
{
  return Fib(6);
}

I64 Fib(I64 n)
{
  if (n <= 1)
    return 1;
  return Fib(n - 1) + Fib(n - 2);
}
