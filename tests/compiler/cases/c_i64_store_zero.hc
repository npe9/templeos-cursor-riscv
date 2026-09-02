// *(I64*)addr = 0 must clear the full word (store-width + Tier-1 sd zero).
// Stack &x is not a U32 bit31 VA — do not use this case for slli;srli zext checks
// (see c_abs_store_clean.hc / c_abs_store_bit31.hc).
I64 main()
{
  I64 x;
  x = 0x1122334455667788;
  *(I64 *)(&x) = 0;
  return x;
}
