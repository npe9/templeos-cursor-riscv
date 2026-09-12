// SoftCall PrsSrcSoft companion: host-AOT Prs-shaped glbl+multi-fun slice (G9).
// SoftCall Load("A:/MakeOS/SoftPrsSrc.BIN") + HashFind SoftPrsSrcProbe -> 42.
// Past SoftCall Load SoftCmpSrc; SoftCall Load of larger Prs fold BIN (<=2KiB)
// - SoftCall-lite Lex digit/while over SoftCall Load 2KiB; SoftCall-lite PrsCmpSrc
// hung ExePutSSoft (host AOT entry thunk).
I64 soft_prs_x;
I64 SoftPrsAdd(I64 a, I64 b)
{
  return a + b;
}

I64 SoftPrsMul(I64 a, I64 b)
{
  return a *b;
}

I64 SoftPrsFold()
{
  I64 x;
  soft_prs_x = SoftPrsAdd(40, 2);
  if (soft_prs_x != 42)
    return -1;
  x = SoftPrsMul(6, 7);
  if (x != 42)
    return -2;
  soft_prs_x = SoftPrsAdd(SoftPrsMul(5, 8), 2);
  if (soft_prs_x != 42)
    return -3;
  return soft_prs_x;
}

public I64 SoftPrsSrcProbe()
{
  return SoftPrsFold();
}
