import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
import U8 *StrCpy(U8 *dst, U8 *src);
class CRVKernMenuEntry
{
  I64 next;
  I64 sub;
  U8 name[32];
  I64 msg_code;
  I64 arg1;
  I64 arg2;
  Bool checked, dir, pad[6];
};

class CRVKernMenu
{
  I64 next;
  I64 sub;
  I64 task;
  I64 flags;
  U8 attr, pad[7];
};

public I64 RVMenuCMenuProdSelfTest()
{
  CRVKernMenuEntry *e;
  CRVKernMenu *m;
  I64 ne;
  I64 nm;
  ne = sizeof(CRVKernMenuEntry);
  nm = sizeof(CRVKernMenu);
  if (ne != 80)
    return 2;
  if (nm != 40)
    return 3;
  e = CAlloc(ne);
  if (!e)
    return 4;
  m = CAlloc(nm);
  if (!m) {
    Free(e);
    return 5;
  }
  StrCpy(e->name, "Tile");
  e->arg1 = 8;
  e->checked = 1;
  e->pad[0] = 1;
  m->flags = 8;
  m->attr = 7;
  if (e->name[0] != 'T') {
    Free(m);
    Free(e);
    return 6;
  }
  if (e->arg1 != 8) {
    Free(m);
    Free(e);
    return 7;
  }
  if (!e->checked) {
    Free(m);
    Free(e);
    return 9;
  }
  if (m->flags != 8) {
    Free(m);
    Free(e);
    return 10;
  }
  Free(m);
  Free(e);
  return 8;
}
