import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
class CRVProdMenu
{
  I64 next;
  I64 sub;
  I64 task;
  I64 flags;
  U8 attr, pad[7];
};

public I64 RVMenuCMenuU8PadSelfTest()
{
  CRVProdMenu *m;
  I64 n;
  n = sizeof(CRVProdMenu);
  if (n != 40)
    return 2;
  m = CAlloc(n);
  if (!m)
    return 3;
  m->flags = 8;
  m->attr = 7;
  if (m->flags != 8) {
    Free(m);
    return 4;
  }
  if (m->attr != 7) {
    Free(m);
    return 5;
  }
  Free(m);
  return 8;
}
