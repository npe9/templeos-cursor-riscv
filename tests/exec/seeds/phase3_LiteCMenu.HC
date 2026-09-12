import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
class CRVLiteMenu
{
  I64 next;
  I64 sub;
  I64 task;
  I64 flags;
};
public I64 RVMenuCMenuSelfTest()
{
  CRVLiteMenu s;
  CRVLiteMenu *m;
  I64 n;
  I64 f;
  s.flags=8;
  if (s.flags!=8)
    return 1;
  n=sizeof(CRVLiteMenu);
  if (n<32)
    return 2;
  m=0;
  m=CAlloc(n);
  if (!m)
    return 3;
  m->flags=8;
  if (m->flags!=8) {
    Free(m);
    return 4;
  }
  f=m->flags;
  Free(m);
  return f;
}
