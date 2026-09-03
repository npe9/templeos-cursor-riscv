U32 dot_prod(U32 *a, U32 *b, U32 n)
{
  U32 sum = 0;
  for (U32 i = 0; i < n; i++)
    sum += a[i] * b[i];
  return sum;
}

I64 main()
{
  U32 a[4], b[4], i;
  for (i = 0; i < 4; i++) {
    a[i] = i + 1;
    b[i] = 10 - i;
  }
  return dot_prod(a, b, 4);
}
