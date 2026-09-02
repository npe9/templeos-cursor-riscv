// Const if(1)/if(0): host Tier-2 folds IMM+BR; dead else/then dropped.
I64 main()
{
  I64 x;
  x = 0;
  if (1)
    x = 7;
  else
    x = 9;
  if (0)
    x = 1;
  else
    x = x + 3;
  return x;
  // 10
}
