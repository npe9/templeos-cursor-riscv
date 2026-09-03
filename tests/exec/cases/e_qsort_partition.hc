// A quicksort (partition + recursion + function-pointer comparator) sorts 6 ints; exercises
// pointer arithmetic scaling, ++/-- scaling, and indirect calls.
I64 SwapI64b(I64 *a, I64 *b)
{
  I64 t = *a;
  *a = *b;
  *b = t;
  return 0;
}

I64 cmp(I64 *a, I64 *b)
{
  return *a - *b;
}

U0 qs2a(I64 **base_ignored, I64 num, I64 (*fp)(I64 *, I64 *), I64 *base)
{
  I64 i;
  I64 *left, *right, pivot;
  left = base;
  right = base + num - 1;
  pivot = base[num / 2];
  do {
    while ((*fp)(left, &pivot) < 0)
      left++;
    while ((*fp)(right, &pivot) > 0)
      right--;
    if (left <= right) {
      SwapI64b(left, right);
      left++;
      right--;
    }
  } while (left <= right);
  i = right + 1 - base;
  if (1 < i < num)
    qs2a(base_ignored, i, fp, base);
  i = base + num - left;
  if (1 < i < num)
    qs2a(base_ignored, i, fp, left);
}

I64 main()
{
  I64 v[6];
  v[0] = 5;
  v[1] = 2;
  v[2] = 8;
  v[3] = 1;
  v[4] = 9;
  v[5] = 3;
  qs2a(0, 6, &cmp, v);
  return (v[0] == 1) * 1 + (v[1] == 2) * 2 + (v[2] == 3) * 4 + (v[3] == 5) * 8 + (v[4] == 8) * 16 + (v[5] == 9) * 32;
}
