import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
class CRVBoolScalars
{
  I64 next;
  Bool checked;
  Bool dir;
};

public I64 RVMenuCMenuBoolSelfTest()
{
  CRVBoolScalars *e;
  I64 n;
  n = sizeof(CRVBoolScalars);
  if (n < 10)
    return 2;
  e = CAlloc(n);
  if (!e)
    return 3;
  e->checked = 1;
  e->dir = 0;
  if (!e->checked) {
    Free(e);
    return 4;
  }
  if (e->dir) {
    Free(e);
    return 5;
  }
  Free(e);
  return 8;
}
