// complete.hc -- case-insensitive Tab completion for editors (Vi / EditHoly / Ed).
// CompTab(line,max,list_ok): uses CompCx as cursor in/out. If a partial ident/path
// sits before CompCx, fill from HTT_FUN (via FunCollect) or memfs (case-insensitive).
// Returns 1 if Tab was handled; 0 if caller should insert 2-space indent.
#define COMP_MAX 32
#define COMP_NAME 48
U8 CompNames[COMP_MAX][COMP_NAME];
I64 CompN;
I64 CompCx;
U8 CompPfx[128];
I64 CompIsIdent(I64 c)
{
  if (c >= 'a' && c <= 'z')
    return 1;
  if (c >= 'A' && c <= 'Z')
    return 1;
  if (c >= '0' && c <= '9')
    return 1;
  if (c == '_')
    return 1;
  return 0;
}

I64 CompIsPath(I64 c)
{
  if (CompIsIdent(c))
    return 1;
  if (c == '.' || c == '/' || c == '-' || c == '+')
    return 1;
  return 0;
}

I64 CompChEq(I64 a, I64 b)
{
  if (a >= 'A' && a <= 'Z')
    a += 32;
  if (b >= 'A' && b <= 'Z')
    b += 32;
  return a == b;
}

I64 CompPrefixEq(U8 *s, U8 *p, I64 plen)
{
  I64 i = 0;
  if (!s)
    return 0;
  while (i < plen) {
    if (!s[i] || !CompChEq(s[i], p[i]))
      return 0;
    i++;
  }
  return 1;
}

I64 CompCommonPfx(I64 n)
{
  I64 i, j;
  U8 c;
  if (n <= 0)
    return 0;
  i = 0;
  while (1) {
    c = CompNames[0][i];
    if (!c)
      return i;
    for (j = 1; j < n; j++)
      if (!CompNames[j][i] || !CompChEq(CompNames[j][i], c))
        return i;
    i++;
  }
}

I64 CompStrOk(U8 *s)
{
  I64 k = 0;
  if (!s)
    return 0;
  while (k < COMP_NAME) {
    if (!s[k])
      return k > 0;
    if (!CompIsIdent(s[k]) && s[k] != '.')
      return 0;
    k++;
  }
  return 0;
}

U0 CompAdd(U8 *s, U8 *pfx, I64 plen)
{
  I64 i, k, same;
  if (!CompStrOk(s) || CompN >= COMP_MAX)
    return;
  if (!CompPrefixEq(s, pfx, plen))
    return;
  for (i = 0; i < CompN; i++) {
    same = 1;
    k = 0;
    while (k < COMP_NAME) {
      if (CompNames[i][k] != s[k]) {
        same = 0;
        break;
      }
      if (!s[k])
        break;
      k++;
    }
    if (same)
      return;
  }
  k = 0;
  while (k < COMP_NAME - 1 && s[k]) {
    CompNames[CompN][k] = s[k];
    k++;
  }
  CompNames[CompN][k] = 0;
  CompN++;
}

I64 CompCollectSyms(U8 *pfx, I64 plen)
{
  I64 body, mask, b, e, ty, nwalk;
  U8 *nm;
  CompN = 0;
  body = SymHashBody();
  mask = SymHashMask();
  if (!body || mask < 0)
    return 0;
  nwalk = 0;
  for (b = 0; b <= mask && CompN < COMP_MAX; b++) {
    e = *(I64 *)(body + b * 8);
    while (e && CompN < COMP_MAX) {
      nwalk++;
      if (nwalk > 2048)
        return CompN;
      ty = *(I64 *)(e + 16);
      if (ty & 0x100) {
        nm = *(I64 *)(e + 8);
        CompAdd(nm, pfx, plen);
      }
      e = *(I64 *)e;
    }
  }
  return CompN;
}

I64 CompCollectFiles(U8 *pfx, I64 plen)
{
  I64 i, cl, k;
  U8 *cwd, *nm, *rest;
  CompN = 0;
  cwd = FsCwd();
  if (!cwd)
    return 0;
  cl = 0;
  while (cl < 63 && cwd[cl])
    cl++;
  for (i = 0; i < MEMFS_MAX && CompN < COMP_MAX; i++) {
    if (!FsSlotUsed(i))
      continue;
    nm = FsName(i);
    if (!nm)
      continue;
    k = 0;
    while (k < cl && nm[k] == cwd[k])
      k++;
    if (k != cl)
      continue;
    rest = nm + cl;
    if (rest[0] == '.')
      continue;
    CompAdd(rest, pfx, plen);
    if (cl)
      CompAdd(nm, pfx, plen);
  }
  return CompN;
}

I64 CompApply(U8 *line, I64 max, I64 list_ok)
{
  I64 end, start, pathish, nm, fill, old, delta, i, need;
  U8 *best;
  end = CompCx;
  start = end;
  pathish = 0;
  if (end > 0 && (line[end - 1] == '"' || line[end - 1] == '\''))
    return 1;
  while (start > 0 && CompIsPath(line[start - 1]))
    start--;
  if (start == end)
    return 0;
  for (i = start; i < end; i++)
    if (line[i] == '.' || line[i] == '/')
      pathish = 1;
  if (start > 0 && line[start - 1] == '"')
    pathish = 1;
  old = end - start;
  if (old >= 127)
    return 1;
  for (i = 0; i < old; i++)
    CompPfx[i] = line[start + i];
  CompPfx[i] = 0;
  if (pathish)
    nm = CompCollectFiles(CompPfx, old);
  else {
    nm = CompCollectSyms(CompPfx, old);
    if (!nm)
      nm = CompCollectFiles(CompPfx, old);
  }
  if (!nm)
    return 1;
  best = &CompNames[0][0];
  if (nm == 1) {
    fill = 0;
    while (best[fill])
      fill++;
  } else
    fill = CompCommonPfx(nm);
  delta = fill - old;
  if (CompCx - old + fill >= max)
    return 1;
  need = 0;
  if (delta)
    need = 1;
  else {
    for (i = 0; i < fill; i++)
      if (line[start + i] != best[i])
        need = 1;
  }
  if (need) {
    if (delta > 0) {
      i = 0;
      while (line[end + i] && end + i < max - 1)
        i++;
      while (i >= 0) {
        if (end + delta + i < max)
          line[end + delta + i] = line[end + i];
        i--;
      }
    } else if (delta < 0) {
      i = 0;
      while (1) {
        line[end + delta + i] = line[end + i];
        if (!line[end + i])
          break;
        i++;
      }
    }
    for (i = 0; i < fill; i++)
      line[start + i] = best[i];
    CompCx = start + fill;
  }
  if (list_ok && nm > 1 && fill <= old) {
    PutCh('\n');
    for (i = 0; i < nm; i++) {
      UartStr("  ");
      UartStr(&CompNames[i][0]);
      PutCh('\n');
    }
  }
  return 1;
}

I64 CompTab(U8 *line, I64 max, I64 list_ok)
{
  return CompApply(line, max, list_ok);
}
