import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
import U8 *StrCpy(U8 *dst, U8 *src);
class CRVProdMenuEntry
{
  I64 next;
  I64 sub;
  U8 name[32];
  I64 msg_code;
  I64 arg1;
  I64 arg2;
};

public I64 RVMenuCMenuEntSelfTest()
{
  CRVProdMenuEntry *e;
  I64 n;
  n = sizeof(CRVProdMenuEntry);
  if (n < 56)
    return 2;
  e = CAlloc(n);
  if (!e)
    return 3;
  StrCpy(e->name, "Tile");
  e->arg1 = 8;
  if (e->name[0] != 'T') {
    Free(e);
    return 4;
  }
  if (e->arg1 != 8) {
    Free(e);
    return 5;
  }
  Free(e);
  return 8;
}
