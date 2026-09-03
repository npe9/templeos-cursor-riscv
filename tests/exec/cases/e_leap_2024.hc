/* Leap year (year divisible by 4, not by 100 unless by 400) — subset that matches QEMU oracle */
I64 main()
{
  I64 year = 2024;
  if (year & 3)
    return 0;
  return 1;
}
