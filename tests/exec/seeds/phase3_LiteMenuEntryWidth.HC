import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
import U8 *StrCpy(U8 *dst, U8 *src);
import I64 StrLen(U8 *st);
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

I64 MenuEntryWidth(CRVKernMenuEntry *tmpme)
{
  I64 res;
  I64 len;
  CRVKernMenuEntry *tmpse;
  if (!tmpme)
    return 1;
  res = StrLen(tmpme->name);
  tmpse = tmpme->sub;
  while (tmpse) {
    len = StrLen(tmpse->name);
    if (len > res)
      res = len;
    tmpse = tmpse->next;
  }
  return res + 1;
}

public I64 RVMenuEntryWidthSelfTest()
{
  CRVKernMenuEntry *e;
  CRVKernMenuEntry *s;
  I64 w;
  e = CAlloc(sizeof(CRVKernMenuEntry));
  if (!e)
    return 3;
  s = CAlloc(sizeof(CRVKernMenuEntry));
  if (!s) {
    Free(e);
    return 3;
  }
  StrCpy(e->name, "Tile");
  StrCpy(s->name, "TileHorz");
  e->sub = s;
  w = MenuEntryWidth(e);
  Free(s);
  Free(e);
  if (w != 9)
    return 2;
  return 8;
}
