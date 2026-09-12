U32 dot_prod(U32 *a, U32 *b, U32 n)
{
  U32 sum = 0;
  for (U32 i = 0; i < n; i++)
    sum += a[i] * b[i];
  return sum;
}
