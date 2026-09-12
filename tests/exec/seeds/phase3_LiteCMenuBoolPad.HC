import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
class CRVBoolPad
{
  I64 next;
  Bool checked, dir, pad[6];
};

public I64 RVMenuCMenuBoolPadSelfTest()
{
  CRVBoolPad *e;
  I64 n;
  n = sizeof(CRVBoolPad);
  if (n != 16)
    return 2;
  e = CAlloc(n);
  if (!e)
    return 3;
  e->checked = 1;
  e->dir = 0;
  e->pad[0] = 1;
  e->pad[5] = 1;
  if (!e->checked) {
    Free(e);
    return 4;
  }
  if (e->dir) {
    Free(e);
    return 5;
  }
  if (!e->pad[0]) {
    Free(e);
    return 6;
  }
  if (!e->pad[5]) {
    Free(e);
    return 7;
  }
  Free(e);
  return 8;
}
