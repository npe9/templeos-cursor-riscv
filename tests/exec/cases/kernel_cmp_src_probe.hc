// SoftCall CmpSrcSoft companion: host-AOT multi-fun compound slice (G9).
// SoftCall Load("A:/MakeOS/SoftCmpSrc.BIN") + HashFind SoftCmpSrcProbe → 42.
// Past SoftCall-lite CmpBrSoft; SoftCall Load of shrunk multi-fun BIN (≤2KiB)
// — SoftCall-lite multi-fun Lex hung ExePutSSoft (host AOT entry thunk).
I64 SoftCmpSrcF()
{
  return 40;
}

I64 SoftCmpSrcG()
{
  return 2;
}

public I64 SoftCmpSrcProbe()
{
  return SoftCmpSrcF() + SoftCmpSrcG();
}
