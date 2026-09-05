// HolyC `lock` stmt: amoswap.d.aq spin + amoswap.d.rl release on HOLYC_STMT_LOCK_ADDR.
I64 main()
{
  I64 x;
  *(I64 *)0x87001F00 = 0;  // start unlocked (HolyLock word)
  x = 0;
  lock x = 42;
  return x;
}
