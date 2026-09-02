// vim.hc -- modal vim-lite. Src("Vi"). `$`=ASCII36. Tab=complete/2sp. Enter split via VSuf+VMove.
// gd / ^] / Enter-on-symbol: same-file seeks in place; else SrcFile session push (depth 4); :q pops.
// After jump, target line is vertically centered. Files >256 lines: windowed load around the def.
// K / gM: Man(ident at or after cursor), pause for a key, redraw.
// Resolve: SrcmapFileOf -> SrcmapGet spill -> memfs / Name.hc -> DocFileFor.
U8 VLn[256][128], VOut[16384], VTmp[128], VMove[128], VSuf[128], VUndoLn[256][128];
U8 VYank[2048], VPat[64], VFile[64];
I64 VN, VCy, VCx, VTop, VMode, VDirty, VQuit, VPush, VDoSeek;
// VBase: 0-based file line of VLn[0]; VTot: total lines in file (status Ln abs/tot).
// VWinN: file lines covered at last load (for windowed :w splice).
I64 VBase, VTot, VWinN;
I64 VUndoN, VUndoCy, VUndoCx, VUndoTop, VUndoDirty, VUndoOk, VInsSnap;
I64 VCount, VOpCnt, VPend, VPendOp, VFindCh, VFindFwd, VFindTill, VMy, VMx;
I64 VYankLen, VYankLine, VSearchDir, VDotKind, VDotCnt, VDotCh, VDotMot, VVis;
#define VSESS_MAX 4
U8 VSessPath[VSESS_MAX][64];
I64 VSessCy[VSESS_MAX], VSessCx[VSESS_MAX], VSessTop[VSESS_MAX], VSessDirty[VSESS_MAX];
I64 VSessDepth;
#define VDOT_X 1
#define VDOT_XB 2
#define VDOT_DD 3
#define VDOT_D 4
#define VDOT_R 5
#define VDOT_P 6
#define VDOT_PP 7
#define VDOT_J 8
#define VDOT_DM 9
#define VDOT_CM 10
#define VDOT_YY 11
#define VDOT_CC 12
I64 VLen(I64 i)
{
  I64 n = 0;
  // Cap at 127 so a missing NUL cannot run into the next row.
  while (n < 127 && VLn[i][n])
    n++;
  return n;
}

U0 VEsc(U8 *s)
{
  PutCh(27);
  "%s", s;
}

U0 VGoto(I64 r, I64 c)
{
  TermGoto(r, c);
}

I64 VGet()
{
  I64 c;
  if (VPush) {
    c = VPush;
    VPush = 0;
    return c;
  }
  return TermKeyGet();
}

U0 VSetL(I64 i, U8 *s)
{
  I64 j = 0;
  while (s[j] && j < 127) {
    VLn[i][j] = s[j];
    j++;
  }
  VLn[i][j] = 0;
}
// Insert empty line at pos. Returns 0 if buffer full (caller must not truncate/overwrite).
I64 VInsL(I64 pos)
{
  I64 k, j;
  if (VN >= 256)
    return 0;
  if (pos < 0)
    pos = 0;
  if (pos > VN)
    pos = VN;
  k = VN;
  while (k > pos) {
    // Full-row move via VMove — avoids &VLn[i][0] pointer alias miscompile.
    j = 0;
    while (j < 128) {
      VMove[j] = VLn[k - 1][j];
      j++;
    }
    j = 0;
    while (j < 128) {
      VLn[k][j] = VMove[j];
      j++;
    }
    k = k - 1;
  }
  j = 0;
  while (j < 128) {
    VLn[pos][j] = 0;
    j++;
  }
  VN = VN + 1;
  if (VTot < VBase + VN)
    VTot = VBase + VN;
  return 1;
}

U0 VDelL(I64 pos)
{
  I64 k, j, last;
  if (VN <= 1) {
    VN = 1;
    VLn[0][0] = 0;
    return;
  }
  if (pos < 0 || pos >= VN)
    return;
  last = VN - 1;
  k = pos;
  while (k < last) {
    j = 0;
    while (j < 128) {
      VMove[j] = VLn[k + 1][j];
      j++;
    }
    j = 0;
    while (j < 128) {
      VLn[k][j] = VMove[j];
      j++;
    }
    k = k + 1;
  }
  VN = VN - 1;
  VLn[VN][0] = 0;
  if (VTot > VBase + VN)
    VTot = VTot - 1;
}

U0 VInsChar(I64 ch)
{
  I64 n, k;
  n = VLen(VCy);
  if (n >= 126)
    return;
  for (k = n + 1; k > VCx; k--)
    VLn[VCy][k] = VLn[VCy][k - 1];
  VLn[VCy][VCx] = ch;
  VCx++;
  VDirty = 1;
}

I64 VIsSpace(I64 ch)
{
  return ch == ' ' || ch == '\t' || !ch;
}

I64 VIsWord(I64 ch)
{
  if (ch >= 'a' && ch <= 'z')
    return 1;
  if (ch >= 'A' && ch <= 'Z')
    return 1;
  if (ch >= '0' && ch <= '9')
    return 1;
  if (ch == '_')
    return 1;
  return 0;
}

I64 VCnt()
{
  if (VCount > 0)
    return VCount;
  return 1;
}

U0 VClrCnt()
{
  VCount = 0;
  VOpCnt = 0;
}

U0 VSnap()
{
  I64 k, j;
  for (k = 0; k < VN; k++) {
    j = 0;
    while (VLn[k][j] && j < 127) {
      VUndoLn[k][j] = VLn[k][j];
      j++;
    }
    VUndoLn[k][j] = 0;
  }
  VUndoN = VN;
  VUndoCy = VCy;
  VUndoCx = VCx;
  VUndoTop = VTop;
  VUndoDirty = VDirty;
  VUndoOk = 1;
}

U0 VUndo()
{
  I64 k, j, tn, tcy, tcx, ttop, tdirty, mx;
  if (!VUndoOk)
    return;
  tn = VN;
  tcy = VCy;
  tcx = VCx;
  ttop = VTop;
  tdirty = VDirty;
  mx = VN;
  if (VUndoN > mx)
    mx = VUndoN;
  for (k = 0; k < mx; k++) {
    j = 0;
    VTmp[0] = 0;
    if (k < VN) {
      while (VLn[k][j] && j < 127) {
        VTmp[j] = VLn[k][j];
        j++;
      }
      VTmp[j] = 0;
    }
    j = 0;
    if (k < VUndoN) {
      while (VUndoLn[k][j] && j < 127) {
        VLn[k][j] = VUndoLn[k][j];
        j++;
      }
    }
    VLn[k][j] = 0;
    j = 0;
    while (VTmp[j] && j < 127) {
      VUndoLn[k][j] = VTmp[j];
      j++;
    }
    VUndoLn[k][j] = 0;
  }
  VN = VUndoN;
  VCy = VUndoCy;
  VCx = VUndoCx;
  VTop = VUndoTop;
  VDirty = VUndoDirty;
  VUndoN = tn;
  VUndoCy = tcy;
  VUndoCx = tcx;
  VUndoTop = ttop;
  VUndoDirty = tdirty;
  if (VN < 1) {
    VN = 1;
    VLn[0][0] = 0;
  }
  if (VCy >= VN)
    VCy = VN - 1;
  if (VCy < 0)
    VCy = 0;
  j = VLen(VCy);
  if (VCx > j)
    VCx = j;
}

U0 VEnterIns()
{
  if (!VInsSnap) {
    VSnap();
    VInsSnap = 1;
  }
  VMode = 1;
  VVis = 0;
}

U0 VClamp()
{
  I64 n;
  if (VCy < 0)
    VCy = 0;
  if (VCy >= VN)
    VCy = VN - 1;
  n = VLen(VCy);
  if (VMode == 1) {
    if (VCx > n)
      VCx = n;
  } else {
    if (n > 0 && VCx >= n)
      VCx = n - 1;
    if (!n)
      VCx = 0;
    if (VCx < 0)
      VCx = 0;
  }
}

U0 VWordW()
{
  I64 n = VLen(VCy), ch;
  if (VCx >= n) {
    if (VCy < VN - 1) {
      VCy++;
      VCx = 0;
      n = VLen(VCy);
      while (VCx < n && VIsSpace(VLn[VCy][VCx]))
        VCx++;
    }
    return;
  }
  ch = VLn[VCy][VCx];
  if (VIsWord(ch))
    while (VCx < n && VIsWord(VLn[VCy][VCx]))
      VCx++;
  else if (!VIsSpace(ch))
    while (VCx < n && !VIsWord(VLn[VCy][VCx]) && !VIsSpace(VLn[VCy][VCx]))
      VCx++;
  while (VCx < n && VIsSpace(VLn[VCy][VCx]))
    VCx++;
  if (VCx >= n && VCy < VN - 1) {
    VCy++;
    VCx = 0;
    n = VLen(VCy);
    while (VCx < n && VIsSpace(VLn[VCy][VCx]))
      VCx++;
  }
}

U0 VWordB()
{
  I64 n, ch;
  if (VCx <= 0) {
    if (VCy > 0) {
      VCy--;
      n = VLen(VCy);
      VCx = n;
      while (VCx > 0 && VIsSpace(VLn[VCy][VCx - 1]))
        VCx--;
      if (VCx > 0) {
        ch = VLn[VCy][VCx - 1];
        if (VIsWord(ch))
          while (VCx > 0 && VIsWord(VLn[VCy][VCx - 1]))
            VCx--;
        else
          while (VCx > 0 && !VIsWord(VLn[VCy][VCx - 1]) && !VIsSpace(VLn[VCy][VCx - 1]))
            VCx--;
      }
    }
    return;
  }
  while (VCx > 0 && VIsSpace(VLn[VCy][VCx - 1]))
    VCx--;
  if (VCx > 0) {
    ch = VLn[VCy][VCx - 1];
    if (VIsWord(ch))
      while (VCx > 0 && VIsWord(VLn[VCy][VCx - 1]))
        VCx--;
    else
      while (VCx > 0 && !VIsWord(VLn[VCy][VCx - 1]) && !VIsSpace(VLn[VCy][VCx - 1]))
        VCx--;
  }
}

U0 VWordE()
{
  I64 n = VLen(VCy), ch;
  if (n <= 0)
    return;
  if (VCx >= n)
    VCx = n - 1;
  if (VCx < n - 1)
    VCx++;
  else if (VCy < VN - 1) {
    VCy++;
    VCx = 0;
    n = VLen(VCy);
    while (VCx < n && VIsSpace(VLn[VCy][VCx]))
      VCx++;
    if (VCx >= n)
      return;
  } else
    return;
  n = VLen(VCy);
  while (VCx < n && VIsSpace(VLn[VCy][VCx]))
    VCx++;
  if (VCx >= n)
    return;
  ch = VLn[VCy][VCx];
  if (VIsWord(ch))
    while (VCx + 1 < n && VIsWord(VLn[VCy][VCx + 1]))
      VCx++;
  else
    while (VCx + 1 < n && !VIsWord(VLn[VCy][VCx + 1]) && !VIsSpace(VLn[VCy][VCx + 1]))
      VCx++;
}

U0 VWordWW()
{
  I64 n = VLen(VCy);
  if (VCx >= n) {
    if (VCy < VN - 1) {
      VCy++;
      VCx = 0;
      n = VLen(VCy);
      while (VCx < n && VIsSpace(VLn[VCy][VCx]))
        VCx++;
    }
    return;
  }
  while (VCx < n && !VIsSpace(VLn[VCy][VCx]))
    VCx++;
  while (VCx < n && VIsSpace(VLn[VCy][VCx]))
    VCx++;
  if (VCx >= n && VCy < VN - 1) {
    VCy++;
    VCx = 0;
    n = VLen(VCy);
    while (VCx < n && VIsSpace(VLn[VCy][VCx]))
      VCx++;
  }
}

U0 VWordBB()
{
  I64 n;
  if (VCx <= 0) {
    if (VCy > 0) {
      VCy--;
      n = VLen(VCy);
      VCx = n;
      while (VCx > 0 && VIsSpace(VLn[VCy][VCx - 1]))
        VCx--;
      while (VCx > 0 && !VIsSpace(VLn[VCy][VCx - 1]))
        VCx--;
    }
    return;
  }
  while (VCx > 0 && VIsSpace(VLn[VCy][VCx - 1]))
    VCx--;
  while (VCx > 0 && !VIsSpace(VLn[VCy][VCx - 1]))
    VCx--;
}

U0 VWordEE()
{
  I64 n = VLen(VCy);
  if (n <= 0)
    return;
  if (VCx >= n)
    VCx = n - 1;
  if (VCx < n - 1)
    VCx++;
  else if (VCy < VN - 1) {
    VCy++;
    VCx = 0;
    n = VLen(VCy);
    while (VCx < n && VIsSpace(VLn[VCy][VCx]))
      VCx++;
    if (VCx >= n)
      return;
  } else
    return;
  n = VLen(VCy);
  while (VCx < n && VIsSpace(VLn[VCy][VCx]))
    VCx++;
  while (VCx + 1 < n && !VIsSpace(VLn[VCy][VCx + 1]))
    VCx++;
}

U0 VGoEOL()
{
  I64 n = VLen(VCy);
  if (n > 0)
    VCx = n - 1;
  else
    VCx = 0;
}

U0 VGoSoftBOL()
{
  I64 n = VLen(VCy);
  VCx = 0;
  while (VCx < n && VIsSpace(VLn[VCy][VCx]))
    VCx++;
  if (VCx >= n && n > 0)
    VCx = n - 1;
}

U0 VJoin()
{
  I64 a, j, k, need_sp;
  if (VCy >= VN - 1)
    return;
  VSnap();
  a = VLen(VCy);
  j = 0;
  while (VLn[VCy + 1][j] == ' ' || VLn[VCy + 1][j] == '\t')
    j++;
  need_sp = 0;
  if (a > 0 && VLn[VCy][a - 1] != ' ' && VLn[VCy][a - 1] != '\t' && VLn[VCy + 1][j])
    need_sp = 1;
  if (need_sp && a < 127) {
    VLn[VCy][a] = ' ';
    a++;
    VLn[VCy][a] = 0;
  }
  k = a;
  if (need_sp && k > 0)
    k--;
  while (VLn[VCy + 1][j] && a < 127) {
    VLn[VCy][a] = VLn[VCy + 1][j];
    a++;
    j++;
  }
  VLn[VCy][a] = 0;
  VDelL(VCy + 1);
  if (k >= a && a > 0)
    k = a - 1;
  if (k < 0)
    k = 0;
  VCx = k;
  VDirty = 1;
  VDotKind = VDOT_J;
  VDotCnt = 1;
}

U0 VDelEOL()
{
  I64 n = VLen(VCy);
  if (VCx >= n)
    return;
  VSnap();
  VLn[VCy][VCx] = 0;
  if (VCx > 0)
    VCx--;
  VDirty = 1;
  VDotKind = VDOT_D;
  VDotCnt = 1;
}

U0 VFindOnLine(I64 ch, I64 fwd, I64 till)
{
  I64 n = VLen(VCy), i;
  if (fwd) {
    i = VCx + 1;
    while (i < n) {
      if (VLn[VCy][i] == ch) {
        if (till) {
          if (i > 0)
            VCx = i - 1;
          else
            VCx = i;
        } else
          VCx = i;
        return;
      }
      i++;
    }
  } else {
    i = VCx - 1;
    while (i >= 0) {
      if (VLn[VCy][i] == ch) {
        if (till)
          VCx = i + 1;
        else
          VCx = i;
        return;
      }
      i--;
    }
  }
}

U0 VMatchPct()
{
  I64 n, i, depth, open, close, fwd, ch;
  n = VLen(VCy);
  if (!n)
    return;
  if (VCx >= n)
    VCx = n - 1;
  ch = VLn[VCy][VCx];
  open = 0;
  close = 0;
  fwd = 1;
  if (ch == '(') {
    open = '(';
    close = ')';
  } else if (ch == '[') {
    open = '[';
    close = ']';
  } else if (ch == '{') {
    open = '{';
    close = '}';
  } else if (ch == ')') {
    open = '(';
    close = ')';
    fwd = 0;
  } else if (ch == ']') {
    open = '[';
    close = ']';
    fwd = 0;
  } else if (ch == '}') {
    open = '{';
    close = '}';
    fwd = 0;
  } else {
    i = VCx;
    while (i < n) {
      ch = VLn[VCy][i];
      if (ch == '(' || ch == '[' || ch == '{') {
        VCx = i;
        VMatchPct();
        return;
      }
      i++;
    }
    return;
  }
  depth = 0;
  if (fwd) {
    i = VCx;
    while (i < n) {
      if (VLn[VCy][i] == open)
        depth++;
      else if (VLn[VCy][i] == close) {
        depth--;
        if (!depth) {
          VCx = i;
          return;
        }
      }
      i++;
    }
  } else {
    i = VCx;
    while (i >= 0) {
      if (VLn[VCy][i] == close)
        depth++;
      else if (VLn[VCy][i] == open) {
        depth--;
        if (!depth) {
          VCx = i;
          return;
        }
      }
      i--;
    }
  }
}

U0 VYankClear()
{
  VYankLen = 0;
  VYank[0] = 0;
}

U0 VYankPutC(I64 ch)
{
  if (VYankLen < 2047) {
    VYank[VYankLen] = ch;
    VYankLen++;
    VYank[VYankLen] = 0;
  }
}

U0 VYankLineRange(I64 a, I64 b)
{
  I64 i, j, t;
  if (a > b) {
    t = a;
    a = b;
    b = t;
  }
  if (a < 0)
    a = 0;
  if (b >= VN)
    b = VN - 1;
  VYankClear();
  VYankLine = 1;
  for (i = a; i <= b; i++) {
    j = 0;
    while (VLn[i][j] && VYankLen < 2047) {
      VYankPutC(VLn[i][j]);
      j++;
    }
    VYankPutC('\n');
  }
}

U0 VYankCharRange(I64 y1, I64 x1, I64 y2, I64 x2)
{
  I64 y, x, n, t;
  if (y1 > y2 || (y1 == y2 && x1 > x2)) {
    t = y1;
    y1 = y2;
    y2 = t;
    t = x1;
    x1 = x2;
    x2 = t;
  }
  VYankClear();
  VYankLine = 0;
  if (y1 == y2) {
    n = VLen(y1);
    if (x2 >= n)
      x2 = n - 1;
    if (x1 < 0)
      x1 = 0;
    for (x = x1; x <= x2 && x < n; x++)
      VYankPutC(VLn[y1][x]);
    return;
  }
  n = VLen(y1);
  for (x = x1; x < n; x++)
    VYankPutC(VLn[y1][x]);
  VYankPutC('\n');
  for (y = y1 + 1; y < y2; y++) {
    x = 0;
    while (VLn[y][x]) {
      VYankPutC(VLn[y][x]);
      x++;
    }
    VYankPutC('\n');
  }
  n = VLen(y2);
  if (x2 >= n)
    x2 = n - 1;
  for (x = 0; x <= x2 && x < n; x++)
    VYankPutC(VLn[y2][x]);
}

U0 VDelCharRange(I64 y1, I64 x1, I64 y2, I64 x2)
{
  I64 y, x, n, t, k;
  if (y1 > y2 || (y1 == y2 && x1 > x2)) {
    t = y1;
    y1 = y2;
    y2 = t;
    t = x1;
    x1 = x2;
    x2 = t;
  }
  if (y1 == y2) {
    n = VLen(y1);
    if (x1 >= n)
      return;
    if (x2 >= n)
      x2 = n - 1;
    k = x2 - x1 + 1;
    for (x = x1; x + k <= n; x++)
      VLn[y1][x] = VLn[y1][x + k];
    VCy = y1;
    VCx = x1;
    VClamp();
    VDirty = 1;
    return;
  }
  x = 0;
  while (x < x1 && VLn[y1][x] && x < 127) {
    VTmp[x] = VLn[y1][x];
    x++;
  }
  k = x2 + 1;
  while (VLn[y2][k] && x < 127) {
    VTmp[x] = VLn[y2][k];
    x++;
    k++;
  }
  VTmp[x] = 0;
  VSetL(y1, VTmp);
  for (y = y2; y > y1; y--)
    VDelL(y);
  VCy = y1;
  VCx = x1;
  VClamp();
  VDirty = 1;
}

U0 VDelLineRange(I64 a, I64 b)
{
  I64 i, t, cnt;
  if (a > b) {
    t = a;
    a = b;
    b = t;
  }
  if (a < 0)
    a = 0;
  if (b >= VN)
    b = VN - 1;
  cnt = b - a + 1;
  for (i = 0; i < cnt; i++)
    VDelL(a);
  if (VN < 1) {
    VN = 1;
    VLn[0][0] = 0;
  }
  VCy = a;
  if (VCy >= VN)
    VCy = VN - 1;
  VCx = 0;
  VDirty = 1;
}

U0 VPut(I64 before)
{
  I64 i, j, k, n, line;
  if (!VYankLen)
    return;
  VSnap();
  if (VYankLine) {
    line = VCy;
    if (!before)
      line++;
    if (line > VN)
      line = VN;
    i = 0;
    while (i < VYankLen) {
      j = 0;
      while (i < VYankLen && VYank[i] != '\n' && j < 127) {
        VTmp[j] = VYank[i];
        j++;
        i++;
      }
      VTmp[j] = 0;
      if (i < VYankLen && VYank[i] == '\n')
        i++;
      if (j || i <= VYankLen) {
        VInsL(line);
        VSetL(line, VTmp);
        line++;
      }
    }
    if (!before)
      VCy++;
    if (VCy >= VN)
      VCy = VN - 1;
    VCx = 0;
    VDirty = 1;
    return;
  }
  if (!before) {
    n = VLen(VCy);
    if (n > 0 && VCx < n)
      VCx++;
  }
  i = 0;
  while (i < VYankLen) {
    if (VYank[i] == '\n') {
      j = 0;
      k = VCx;
      n = VLen(VCy);
      while (k < n && j < 127) {
        VTmp[j] = VLn[VCy][k];
        j++;
        k++;
      }
      VTmp[j] = 0;
      if (!VInsL(VCy + 1))
        return;
      VLn[VCy][VCx] = 0;
      VSetL(VCy + 1, VTmp);
      VCy++;
      VCx = 0;
      i++;
    } else {
      VInsChar(VYank[i]);
      i++;
    }
  }
  if (VCx > 0)
    VCx--;
  VDirty = 1;
}
// Count newlines in file (1-based last line even without trailing NL).
I64 VCountLines(U8 *data, I64 dn)
{
  I64 i, n;
  if (!data || dn <= 0)
    return 0;
  n = 1;
  i = 0;
  while (i < dn) {
    if (data[i] == '\n') {
      if (i + 1 < dn)
        n++;
    }
    i++;
  }
  return n;
}
// Load up to 256 lines starting at 0-based file line `base`.
U0 VLoadAt(U8 *name, I64 base)
{
  U8 *data;
  I64 dn, i, j, ln;
  VN = 0;
  VBase = 0;
  VTot = 0;
  VWinN = 0;
  if (base < 0)
    base = 0;
  data = FileRead(name);
  dn = FileLen(name);
  if (dn < 0)
    dn = 0;
  if (data) {
    VTot = VCountLines(data, dn);
    i = 0;
    ln = 0;
    while (i < dn && ln < base) {
      while (i < dn && data[i] != '\n')
        i++;
      if (i < dn && data[i] == '\n')
        i++;
      ln++;
    }
    VBase = ln;
    while (i < dn && VN < 256) {
      j = 0;
      while (i < dn && data[i] != '\n' && j < 127) {
        VLn[VN][j] = data[i];
        j++;
        i++;
      }
      VLn[VN][j] = 0;
      while (i < dn && data[i] != '\n')
        i++;
      if (i < dn && data[i] == '\n')
        i++;
      VN++;
    }
  }
  if (VN < 1) {
    VN = 1;
    VLn[0][0] = 0;
  }
  VWinN = VN;
  if (VTot < VBase + VN)
    VTot = VBase + VN;
}

U0 VLoad(U8 *name)
{
  VLoadAt(name, 0);
}
// Seek to 0-based file line abs; reload the 256-line window when needed.
U0 VGotoAbs(I64 abs)
{
  I64 base;
  if (abs < 0)
    abs = 0;
  if (VTot > 0 && abs >= VTot)
    abs = VTot - 1;
  if (abs >= VBase && abs < VBase + VN) {
    VCy = abs - VBase;
    VClamp();
    return;
  }
  base = abs - 100;
  if (base < 0)
    base = 0;
  if (abs - base >= 256)
    base = abs - 200;
  if (base < 0)
    base = 0;
  if (VTot > 256 && VTot - base < 256) {
    base = VTot - 256;
    if (base < 0)
      base = 0;
  }
  VLoadAt(VFile, base);
  VCy = abs - VBase;
  if (VCy < 0)
    VCy = 0;
  if (VCy >= VN)
    VCy = VN - 1;
  VClamp();
}

U0 VSave()
{
  I64 k, m, off = 0, n, dn, i, ln, j;
  U8 *data, *out;
  // Windowed / truncated buffer: splice edited lines back into the full file.
  if (VBase > 0 || VTot > VWinN) {
    data = FileRead(VFile);
    dn = FileLen(VFile);
    if (dn < 0)
      dn = 0;
    out = MAlloc(65536);
    if (!out) {
      UartStr("Vi: save OOM\n");
      return;
    }
    off = 0;
    i = 0;
    ln = 0;
    if (data) {
      while (i < dn && ln < VBase && off < 65535) {
        out[off] = data[i];
        if (data[i] == '\n')
          ln++;
        off++;
        i++;
      }
    }
    for (k = 0; k < VN && off < 65534; k++) {
      m = 0;
      while (VLn[k][m] && off < 65534) {
        out[off] = VLn[k][m];
        off++;
        m++;
      }
      if (off < 65535) {
        out[off] = '\n';
        off++;
      }
    }
    if (data) {
      j = 0;
      while (i < dn && j < VWinN) {
        if (data[i] == '\n')
          j++;
        i++;
      }
      while (i < dn && off < 65535) {
        out[off] = data[i];
        off++;
        i++;
      }
    }
    out[off] = 0;
    off = FmtSave(VFile, out, off);
    Free(out);
  } else {
    for (k = 0; k < VN; k++) {
      m = 0;
      while (VLn[k][m] && off < 16383) {
        VOut[off] = VLn[k][m];
        off++;
        m++;
      }
      if (off < 16383) {
        VOut[off] = '\n';
        off++;
      }
    }
    VOut[off] = 0;
    off = FmtSave(VFile, VOut, off);
  }
  if (IsHcName(VFile)) {
    n = VBase + VCy;
    VLoadAt(VFile, VBase);
    if (VCy >= VN)
      VCy = VN - 1;
    // Keep absolute cursor line when possible.
    if (n >= VBase && n < VBase + VN)
      VCy = n - VBase;
    if (VCy < 0)
      VCy = 0;
    n = VLen(VCy);
    if (VCx > n)
      VCx = n;
  }
  VDirty = 0;
}

U0 VDraw()
{
  I64 r, i, j, tr, tc, sr;
  sr = TermRows();
  tc = TermCols();
  tr = sr - 1;
  if (tr < 1)
    tr = 1;
  if (VCy < VTop)
    VTop = VCy;
  if (VCy >= VTop + tr)
    VTop = VCy - tr + 1;
  for (r = 0; r < tr; r++) {
    TermGoto(r + 1, 1);
    TermClearEol();
    i = VTop + r;
    if (i < VN) {
      j = 0;
      while (VLn[i][j] && j < tc) {
        PutCh(VLn[i][j]);
        j++;
      }
    } else
      PutCh('~');
  }
  TermGoto(sr, 1);
  VEsc("[7m");
  if (VMode == 1) {
    "-- INSERT --";
  } else if (VVis == 1) {
    "-- VISUAL --";
  } else if (VVis == 2) {
    "-- VISUAL LINE --";
  } else {
    "-- NORMAL --";
  }
  " %s%s Ln %d/%d Col %d ", VFile, VDirty ? "*" : "", VBase + VCy + 1, VTot > 0 ? VTot : VN, VCx + 1;
  VEsc("[0m");
  TermClearEol();
  TermGoto(VCy - VTop + 1, VCx + 1);
}

U0 VDoSearch(I64 dir, I64 from_next)
{
  I64 y, x, n, i, plen, wrapped, guard;
  if (!VPat[0])
    return;
  plen = 0;
  while (VPat[plen])
    plen++;
  y = VCy;
  x = VCx;
  wrapped = 0;
  guard = 0;
  if (from_next) {
    if (dir > 0)
      x++;
    else
      x--;
  }
  while (guard < 100000) {
    guard++;
    n = VLen(y);
    if (dir > 0) {
      while (x + plen <= n) {
        i = 0;
        while (i < plen && VLn[y][x + i] == VPat[i])
          i++;
        if (i == plen) {
          VCy = y;
          VCx = x;
          return;
        }
        x++;
      }
      y++;
      x = 0;
      if (y >= VN) {
        if (wrapped)
          return;
        y = 0;
        wrapped = 1;
      }
    } else {
      if (x > n - 1)
        x = n - 1;
      while (x >= 0) {
        if (x + plen <= n) {
          i = 0;
          while (i < plen && VLn[y][x + i] == VPat[i])
            i++;
          if (i == plen) {
            VCy = y;
            VCx = x;
            return;
          }
        }
        x--;
      }
      y--;
      if (y < 0) {
        if (wrapped)
          return;
        y = VN - 1;
        wrapped = 1;
      }
      x = VLen(y);
    }
  }
}

U0 VSearchPrompt(I64 dir)
{
  U8 buf[64];
  I64 i = 0, c;
  VGoto(TermRows(), 1);
  VEsc("[K");
  if (dir > 0)
    PutCh('/');
  else
    PutCh('?');
  while (1) {
    c = VGet();
    if (c == '\r' || c == '\n')
      break;
    if (c == 27)
      return;
    if ((c == 127 || c == 8) && i > 0) {
      i--;
      PutCh(8);
      PutCh(' ');
      PutCh(8);
      continue;
    }
    if (i < 62 && c >= 32 && c < 127) {
      buf[i] = c;
      i++;
      PutCh(c);
    }
  }
  buf[i] = 0;
  if (i > 0) {
    i = 0;
    while (buf[i] && i < 63) {
      VPat[i] = buf[i];
      i++;
    }
    VPat[i] = 0;
  }
  VSearchDir = dir;
  VDoSearch(dir, 0);
}

U0 VStar()
{
  I64 n, a, b, i;
  n = VLen(VCy);
  if (!n || VCx >= n)
    return;
  if (!VIsWord(VLn[VCy][VCx]))
    return;
  a = VCx;
  while (a > 0 && VIsWord(VLn[VCy][a - 1]))
    a--;
  b = VCx;
  while (b + 1 < n && VIsWord(VLn[VCy][b + 1]))
    b++;
  i = 0;
  while (a <= b && i < 63) {
    VPat[i] = VLn[VCy][a];
    i++;
    a++;
  }
  VPat[i] = 0;
  VSearchDir = 1;
  VDoSearch(1, 0);
}

U0 VMotion(I64 mot, I64 cnt)
{
  I64 i, n;
  for (i = 0; i < cnt; i++) {
    if (mot == 'h') {
      if (VCx > 0)
        VCx--;
    } else if (mot == 'l') {
      n = VLen(VCy);
      if (VCx < n - 1)
        VCx++;
    } else if (mot == 'j') {
      if (VCy < VN - 1) {
        VCy++;
        VClamp();
      } else if (VBase + VN < VTot)
        VGotoAbs(VBase + VCy + 1);
    } else if (mot == 'k') {
      if (VCy > 0) {
        VCy--;
        VClamp();
      } else if (VBase > 0)
        VGotoAbs(VBase + VCy - 1);
    } else if (mot == 'w')
      VWordW();
    else if (mot == 'b')
      VWordB();
    else if (mot == 'e')
      VWordE();
    else if (mot == 'W')
      VWordWW();
    else if (mot == 'B')
      VWordBB();
    else if (mot == 'E')
      VWordEE();
    else if (mot == '0')
      VCx = 0;
    else if (mot == '^')
      VGoSoftBOL();
    else if (mot == 36)
      VGoEOL();
    else if (mot == 'G') {
      VGotoAbs(VTot > 0 ? VTot - 1 : VN - 1);
      VCx = 0;
    } else if (mot == '%')
      VMatchPct();
    else
      break;
  }
}

U0 VApplyOp(I64 op, I64 y1, I64 x1, I64 y2, I64 x2, I64 linewise)
{
  if (op == 'y') {
    if (linewise)
      VYankLineRange(y1, y2);
    else
      VYankCharRange(y1, x1, y2, x2);
    return;
  }
  VSnap();
  if (linewise) {
    VYankLineRange(y1, y2);
    VDelLineRange(y1, y2);
    if (op == 'c') {
      VInsL(VCy);
      VCx = 0;
      VInsSnap = 1;
      VMode = 1;
      VDirty = 1;
    }
    return;
  }
  VYankCharRange(y1, x1, y2, x2);
  VDelCharRange(y1, x1, y2, x2);
  if (op == 'c') {
    VInsSnap = 1;
    VMode = 1;
  }
}

U0 VDoOpMotion(I64 op, I64 mot, I64 cnt)
{
  I64 y1, x1, y2, x2, linewise, tot;
  tot = cnt;
  if (VOpCnt > 1)
    tot = VOpCnt *cnt;
  y1 = VCy;
  x1 = VCx;
  linewise = 0;
  if (mot == 'j' || mot == 'k' || mot == 'G')
    linewise = 1;
  VMotion(mot, tot);
  y2 = VCy;
  x2 = VCx;
  if (linewise)
    VApplyOp(op, y1, 0, y2, 0, 1);
  else {
    if ((mot == 'w' || mot == 'W') && (y2 > y1 || (y2 == y1 && x2 > x1))) {
      if (x2 > 0)
        x2--;
    }
    VApplyOp(op, y1, x1, y2, x2, 0);
  }
  if (op == 'd') {
    VDotKind = VDOT_DM;
    VDotMot = mot;
    VDotCnt = tot;
  }
  if (op == 'c') {
    VDotKind = VDOT_CM;
    VDotMot = mot;
    VDotCnt = tot;
  }
}

U0 VDotReplay()
{
  I64 c, k, n, t;
  c = VDotCnt;
  if (c < 1)
    c = 1;
  if (VDotKind == VDOT_X) {
    VSnap();
    while (c > 0) {
      n = VLen(VCy);
      if (n > 0 && VCx < n) {
        for (t = VCx; t < n; t++)
          VLn[VCy][t] = VLn[VCy][t + 1];
        n = VLen(VCy);
        if (VCx >= n && VCx > 0)
          VCx--;
        VDirty = 1;
      }
      c--;
    }
  } else if (VDotKind == VDOT_XB) {
    VSnap();
    while (c > 0 && VCx > 0) {
      n = VLen(VCy);
      for (t = VCx - 1; t < n; t++)
        VLn[VCy][t] = VLn[VCy][t + 1];
      VCx--;
      VDirty = 1;
      c--;
    }
  } else if (VDotKind == VDOT_DD) {
    VSnap();
    while (c > 0 && VN > 0) {
      VDelL(VCy);
      c--;
    }
    if (VN < 1) {
      VN = 1;
      VLn[0][0] = 0;
    }
    if (VCy >= VN)
      VCy = VN - 1;
    VCx = 0;
    VDirty = 1;
  } else if (VDotKind == VDOT_D)
    VDelEOL();
  else if (VDotKind == VDOT_R) {
    if (VLen(VCy) > 0 && VCx < VLen(VCy)) {
      VSnap();
      VLn[VCy][VCx] = VDotCh;
      VDirty = 1;
    }
  } else if (VDotKind == VDOT_P) {
    while (c > 0) {
      VPut(0);
      c--;
    }
  } else if (VDotKind == VDOT_PP) {
    while (c > 0) {
      VPut(1);
      c--;
    }
  } else if (VDotKind == VDOT_J) {
    while (c > 0) {
      VJoin();
      c--;
    }
  } else if (VDotKind == VDOT_DM)
    VDoOpMotion('d', VDotMot, c);
  else if (VDotKind == VDOT_CM)
    VDoOpMotion('c', VDotMot, c);
  else if (VDotKind == VDOT_YY)
    VYankLineRange(VCy, VCy + c - 1);
  else if (VDotKind == VDOT_CC) {
    VSnap();
    VYankLineRange(VCy, VCy + c - 1);
    VDelLineRange(VCy, VCy + c - 1);
    VInsL(VCy);
    VCx = 0;
    VInsSnap = 1;
    VMode = 1;
    VDirty = 1;
  }
}

U0 VSessPush()
{
  I64 d, k, m, off;
  U8 spill[8];
  d = VSessDepth;
  k = 0;
  while (VFile[k] && k < 63) {
    VSessPath[d][k] = VFile[k];
    k++;
  }
  VSessPath[d][k] = 0;
  VSessCy[d] = VCy;
  VSessCx[d] = VCx;
  VSessTop[d] = VTop;
  VSessDirty[d] = VDirty;
  spill[0] = '.';
  spill[1] = 'v';
  spill[2] = 's';
  spill[3] = '0' + d;
  spill[4] = 0;
  off = 0;
  for (k = 0; k < VN; k++) {
    m = 0;
    while (VLn[k][m] && off < 16383) {
      VOut[off] = VLn[k][m];
      off++;
      m++;
    }
    if (off < 16383) {
      VOut[off] = '\n';
      off++;
    }
  }
  VOut[off] = 0;
  FileWrite(spill, VOut, off);
  VSessDepth = d + 1;
}

U0 VSessPop()
{
  I64 d, k, n;
  U8 spill[8];
  if (VSessDepth <= 0)
    return;
  VSessDepth--;
  d = VSessDepth;
  spill[0] = '.';
  spill[1] = 'v';
  spill[2] = 's';
  spill[3] = '0' + d;
  spill[4] = 0;
  VLoad(spill);
  k = 0;
  while (VSessPath[d][k] && k < 63) {
    VFile[k] = VSessPath[d][k];
    k++;
  }
  VFile[k] = 0;
  VCy = VSessCy[d];
  VCx = VSessCx[d];
  VTop = VSessTop[d];
  VDirty = VSessDirty[d];
  VMode = 0;
  VPend = 0;
  VPendOp = 0;
  VVis = 0;
  VDoSeek = 0;
  VUndoOk = 0;
  if (VCy >= VN)
    VCy = VN - 1;
  if (VCy < 0)
    VCy = 0;
  n = VLen(VCy);
  if (VCx > n)
    VCx = n;
}

U0 VCenter()
{
  I64 tr;
  tr = TermRows() - 1;
  if (tr < 1)
    tr = 1;
  VTop = VCy - tr / 2;
  if (VTop < 0)
    VTop = 0;
}
// Absolute 0-based line of `name` def in file, or -1. Prefers DefAt; else IdentAt off //.
I64 VFindDefLine(U8 *fname, U8 *name)
{
  U8 *data, line[128];
  I64 dn, i, j, ln, col, id_ln, k;
  data = FileRead(fname);
  dn = FileLen(fname);
  if (!data || !name || !*name || dn < 0)
    return -1;
  i = 0;
  ln = 0;
  id_ln = -1;
  while (i < dn) {
    j = 0;
    while (i < dn && data[i] != '\n' && j < 127) {
      line[j] = data[i];
      j++;
      i++;
    }
    line[j] = 0;
    while (i < dn && data[i] != '\n')
      i++;
    if (i < dn && data[i] == '\n')
      i++;
    col = DefAt(line, name);
    if (col >= 0)
      return ln;
    if (id_ln < 0) {
      k = 0;
      while (line[k] == ' ' || line[k] == 9)
        k++;
      if (!(line[k] == '/' && line[k + 1] == '/')) {
        col = IdentAt(line, name);
        if (col >= 0)
          id_ln = ln;
      }
    }
    ln++;
  }
  return id_ln;
}

U0 VJumpSeek(U8 *name)
{
  I64 i, col, j, abs;
  if (!name || !*name)
    return;
  i = 0;
  while (i < VN) {
    col = DefAt(&VLn[i][0], name);
    if (col >= 0) {
      VCy = i;
      VCx = col;
      VCenter();
      return;
    }
    i++;
  }
  i = 0;
  while (i < VN) {
    j = 0;
    while (VLn[i][j] == ' ' || VLn[i][j] == 9)
      j++;
    if (VLn[i][j] == '/' && VLn[i][j + 1] == '/') {
      i++;
      continue;
    }
    col = IdentAt(&VLn[i][0], name);
    if (col >= 0) {
      VCy = i;
      VCx = col;
      VCenter();
      return;
    }
    i++;
  }
  abs = VFindDefLine(VFile, name);
  if (abs < 0)
    return;
  VGotoAbs(abs);
  VCx = 0;
  col = DefAt(&VLn[VCy][0], name);
  if (col < 0)
    col = IdentAt(&VLn[VCy][0], name);
  if (col >= 0)
    VCx = col;
  VCenter();
}

U0 VOpen(U8 *fn, I64 do_seek)
{
  I64 p;
  if (VSessDepth >= VSESS_MAX)
    return;
  VSessPush();
  p = 0;
  while (fn[p] && p < 63) {
    VFile[p] = fn[p];
    p++;
  }
  VFile[p] = 0;
  VLoad(VFile);
  VCy = 0;
  VCx = 0;
  VTop = 0;
  VDirty = 0;
  VMode = 0;
  VPend = 0;
  VPendOp = 0;
  VVis = 0;
  VUndoOk = 0;
  if (do_seek && JumpIdent[0])
    VJumpSeek(JumpIdent);
}

U0 VTryQuit()
{
  if (VSessDepth > 0) {
    VSessPop();
    return;
  }
  VQuit = 1;
}

U0 VCmd()
{
  U8 cmd[64];
  I64 i = 0, c, n, a1, a2, have1, p;
  VGoto(TermRows(), 1);
  VEsc("[K");
  PutCh(':');
  while (1) {
    c = VGet();
    if (c == '\r' || c == '\n')
      break;
    if ((c == 127 || c == 8) && i > 0) {
      i--;
      PutCh(8);
      PutCh(' ');
      PutCh(8);
      continue;
    }
    if (c == 27)
      return;
    if (i < 62 && c >= 32 && c < 127) {
      cmd[i] = c;
      i++;
      PutCh(c);
    }
  }
  cmd[i] = 0;
  if (cmd[0] == 'w' && cmd[1] == 0) {
    VSave();
    return;
  }
  if (cmd[0] == 'w' && cmd[1] == 'q' && cmd[2] == 0) {
    VSave();
    VTryQuit();
    return;
  }
  if (cmd[0] == 'x' && cmd[1] == 0) {
    VSave();
    VTryQuit();
    return;
  }
  if (cmd[0] == 'q' && cmd[1] == 0) {
    if (!VDirty)
      VTryQuit();
    return;
  }
  if (cmd[0] == 'q' && cmd[1] == '!' && cmd[2] == 0) {
    VTryQuit();
    return;
  }
  if (cmd[0] == '!') {
    VGoto(TermRows(), 1);
    VEsc("[K");
    Exec(&cmd[1]);
    "-- press a key --";
    VGet();
    return;
  }
  if (cmd[0] == 'e' && (cmd[1] == ' ' || cmd[1] == 0)) {
    p = 1;
    while (cmd[p] == ' ')
      p++;
    if (!cmd[p])
      return;
    i = 0;
    while (cmd[p] && i < 63) {
      VFile[i] = cmd[p];
      i++;
      p++;
    }
    VFile[i] = 0;
    VLoad(VFile);
    VCy = 0;
    VCx = 0;
    VTop = 0;
    VDirty = 0;
    VUndoOk = 0;
    return;
  }
  p = 0;
  have1 = 0;
  a1 = 1;
  a2 = VN;
  if (cmd[0] == '%') {
    have1 = 1;
    a1 = 1;
    a2 = VN;
    p = 1;
  } else if (cmd[0] >= '0' && cmd[0] <= '9') {
    n = 0;
    while (cmd[p] >= '0' && cmd[p] <= '9') {
      n = n * 10 + cmd[p] - '0';
      p++;
    }
    a1 = n;
    have1 = 1;
    a2 = n;
    if (cmd[p] == ',') {
      p++;
      if (cmd[p] == 36) {
        a2 = VN;
        p++;
      } else if (cmd[p] >= '0' && cmd[p] <= '9') {
        n = 0;
        while (cmd[p] >= '0' && cmd[p] <= '9') {
          n = n * 10 + cmd[p] - '0';
          p++;
        }
        a2 = n;
      }
    }
  } else if (cmd[0] == 36) {
    if (VTot > 0)
      VGotoAbs(VTot - 1);
    else
      VGotoAbs(VN - 1);
    VCx = 0;
    return;
  }
  if (have1 && cmd[p] == 0) {
    if (a1 >= 1) {
      VGotoAbs(a1 - 1);
      VCx = 0;
    }
    return;
  }
  if (have1 && cmd[p] == 'd') {
    VSnap();
    VDelLineRange(a1 - 1, a2 - 1);
    return;
  }
  if (have1 && cmd[p] == 'y') {
    VYankLineRange(a1 - 1, a2 - 1);
    return;
  }
  if (!have1 && cmd[0] >= '0' && cmd[0] <= '9') {
    n = 0;
    i = 0;
    while (cmd[i] >= '0' && cmd[i] <= '9') {
      n = n * 10 + cmd[i] - '0';
      i++;
    }
    if (n >= 1 && n <= VN) {
      VCy = n - 1;
      VCx = 0;
    }
  }
}
// Ident at cursor, else first ident after focus (rest of line, then later lines).
U0 VJumpIdentFill()
{
  I64 y;
  JumpIdent[0] = 0;
  WordIdent(&VLn[VCy][0], VCx, JumpIdent);
  if (JumpIdent[0])
    return;
  y = VCy + 1;
  while (y < VN) {
    WordIdent(&VLn[y][0], 0, JumpIdent);
    if (JumpIdent[0])
      return;
    y++;
  }
}

U0 VJump()
{
  U8 *fn;
  I64 p, sr;
  VJumpIdentFill();
  if (!JumpIdent[0]) {
    sr = TermRows();
    TermGoto(sr, 1);
    TermClearEol();
    UartStr("no ident");
    return;
  }
  fn = SrcFile(JumpIdent);
  if (!fn) {
    JumpIdent[0] = 0;
    return;
  }
  p = 0;
  while (fn[p] && p < 63) {
    JumpFile[p] = fn[p];
    p++;
  }
  JumpFile[p] = 0;
  if (!StrICmp(VFile, JumpFile)) {
    VJumpSeek(JumpIdent);
    return;
  }
  VOpen(JumpFile, 1);
}

U0 VMan()
{
  VJumpIdentFill();
  TermClear();
  if (!JumpIdent[0])
    Man(0);
  else
    Man(JumpIdent);
  UartStr("-- press a key --");
  VGet();
}

U0 VInsert(I64 c)
{
  I64 n, k, j, t, nrow, i;
  if (c == 27) {
    VMode = 0;
    VInsSnap = 0;
    n = VLen(VCy);
    if (VCx > n)
      VCx = n;
    if (VCx > 0)
      VCx--;
    return;
  }
  if (c == 29) {
    VJump();
    return;
  }
  if (c == '\r' || c == '\n') {
    // Split at cursor. Insert the new row BEFORE truncating — if the 256-line
    // buffer is full, VInsL fails and we must not clobber the following line
    // (old order: truncate + VSetL(next) overwrote KEEP_* rows below).
    if (VN >= 256)
      return;
    j = 0;
    t = VCx;
    if (t < 0)
      t = 0;
    if (t > 127)
      t = 127;
    while (t < 127 && VLn[VCy][t] && j < 127) {
      VSuf[j] = VLn[VCy][t];
      j++;
      t++;
    }
    VSuf[j] = 0;
    nrow = VCy + 1;
    if (!VInsL(nrow))
      return;
    VLn[VCy][VCx] = 0;
    j = 0;
    while (VSuf[j] && j < 127) {
      VLn[nrow][j] = VSuf[j];
      j++;
    }
    VLn[nrow][j] = 0;
    VCy = nrow;
    VCx = 0;
    VDirty = 1;
    return;
  }
  if (c == 127 || c == 8) {
    if (VCx > 0) {
      n = VLen(VCy);
      for (k = VCx - 1; k < n; k++)
        VLn[VCy][k] = VLn[VCy][k + 1];
      VCx--;
      VDirty = 1;
    }
    return;
  }
  if (c == 9 || c == '\t') {
    CompAsmReset();
    for (i = 0; i < VCy; i++) {
      CompAsmFeed(&VLn[i][0], VLen(i));
      CompAsmFeed("\n", 1);
    }
    CompAsmFeed(&VLn[VCy][0], VCx);
    CompCx = VCx;
    if (!CompTab(&VLn[VCy][0], 128, 0)) {
      VInsChar(' ');
      VInsChar(' ');
    } else {
      VCx = CompCx;
      VDirty = 1;
    }
    return;
  }
  if (c >= 32 && c < 127)
    VInsChar(c);
}

U0 VActivate()
{
  U8 w[64];
  I64 k;
  WordAt(&VLn[VCy][0], VCx, w);
  k = LinkKind(w, w);
  if (k == 1) {
    LinkCd(w);
    if (!StrCmp(VFile, ".dirlist")) {
      DirWrite();
      VLoad(".dirlist");
      VCy = 0;
      VCx = 0;
      VDirty = 0;
    }
  } else if (k == 2) {
    JumpIdent[0] = 0;
    VOpen(w, 0);
  } else if (w[0]) {
    VJumpIdentFill();
    if (JumpIdent[0])
      VJump();
  }
}

U0 VVisDel(I64 op)
{
  I64 y1, x1, y2, x2;
  y1 = VMy;
  x1 = VMx;
  y2 = VCy;
  x2 = VCx;
  if (VVis == 2)
    VApplyOp(op, y1, 0, y2, 0, 1);
  else
    VApplyOp(op, y1, x1, y2, x2, 0);
  VVis = 0;
}
// Vi -- Vi(name)
// NAME
//   Vi - modal vim-lite full-screen editor
// SYNOPSIS
//   U0 Vi(U8 *name);
// DESCRIPTION
//   Opens a memfs file in a small vim-like editor. Normal/insert modes; :w :q;
//   gd/^] jump to definition; K or gM shows Man for the ident at or after the cursor.
//   Set `editor=&Vi;` to make Src/DirEd use Vi by default.
// EXAMPLES
//   // Vi("boot.hc");   // interactive — :q to quit
//   editor=&Vi;
//   Man("Src");
// SEE ALSO
//   Edit  EditHoly  Ed  Src  Man  Fmt
// BUGS
//   Subset of vim; 256-line buffer with windowed seek/save for larger files.
U0 Vi(U8 *name)
{
  I64 c, n, tr, cnt, k, t, j;
  j = 0;
  while (name[j] && j < 63) {
    VFile[j] = name[j];
    j++;
  }
  VFile[j] = 0;
  VSessDepth = 0;
  VLoad(name);
  VCy = 0;
  VCx = 0;
  VTop = 0;
  VMode = 0;
  VDirty = 0;
  VQuit = 0;
  VPush = 0;
  VDoSeek = 0;
  if (JumpIdent[0]) {
    VJumpSeek(JumpIdent);
    JumpIdent[0] = 0;
  }
  VUndoOk = 0;
  VInsSnap = 0;
  VCount = 0;
  VOpCnt = 0;
  VPend = 0;
  VPendOp = 0;
  VVis = 0;
  VYankLen = 0;
  VYankLine = 0;
  VPat[0] = 0;
  VSearchDir = 1;
  VFindCh = 0;
  VDotKind = 0;
  TermProbe();
  while (!VQuit) {
    VDraw();
    c = TermKeyGet();
    n = VLen(VCy);
    tr = TermRows() - 1;
    if (tr < 1)
      tr = 1;
    if (c == KEY_UP)
      c = 'k';
    else if (c == KEY_DOWN)
      c = 'j';
    else if (c == KEY_LEFT)
      c = 'h';
    else if (c == KEY_RIGHT)
      c = 'l';
    else if (c == KEY_HOME)
      c = '0';
    else if (c == KEY_END)
      c = 36;
    else if (c == KEY_PGUP) {
      I64 abs;
      abs = VBase + VCy - tr;
      if (abs < 0)
        abs = 0;
      VGotoAbs(abs);
      continue;
    } else if (c == KEY_PGDN) {
      I64 abs;
      abs = VBase + VCy + tr;
      if (VTot > 0 && abs >= VTot)
        abs = VTot - 1;
      VGotoAbs(abs);
      continue;
    } else if (c == KEY_DELETE)
      c = 'x';
    if (VMode == 1) {
      VInsert(c);
      continue;
    }
    if (VPend == 'f' || VPend == 't' || VPend == 'F' || VPend == 'T') {
      if (c >= 32 && c < 127) {
        cnt = VCnt();
        VClrCnt();
        VFindCh = c;
        VFindFwd = (VPend == 'f' || VPend == 't');
        VFindTill = (VPend == 't' || VPend == 'T');
        if (VPendOp) {
          VMy = VCy;
          VMx = VCx;
        }
        for (k = 0; k < cnt; k++)
          VFindOnLine(VFindCh, VFindFwd, VFindTill);
        if (VPendOp) {
          VApplyOp(VPendOp, VMy, VMx, VCy, VCx, 0);
          if (VPendOp == 'd') {
            VDotKind = VDOT_DM;
            VDotMot = 'f';
            VDotCnt = cnt;
            VDotCh = c;
          }
          if (VPendOp == 'c') {
            VDotKind = VDOT_CM;
            VDotMot = 'f';
            VDotCnt = cnt;
            VDotCh = c;
          }
          VPendOp = 0;
        }
      }
      VPend = 0;
      continue;
    }
    if (VPend == 'g') {
      if (c == 'g') {
        cnt = VCnt();
        VClrCnt();
        if (VPendOp) {
          VMy = VCy;
          VGotoAbs(0);
          VApplyOp(VPendOp, VMy, 0, 0, 0, 1);
          VPendOp = 0;
        } else {
          VGotoAbs(0);
          VCx = 0;
        }
      } else if (c == 'd')
        VJump();
      else if (c == 'M')
        VMan();
      VPend = 0;
      continue;
    }
    if (VPend == 'r') {
      if (c >= 32 && c < 127) {
        if (n > 0 && VCx < n) {
          VSnap();
          cnt = VCnt();
          if (cnt < 1)
            cnt = 1;
          for (k = 0; k < cnt && VCx + k < n; k++)
            VLn[VCy][VCx + k] = c;
          VDirty = 1;
          VDotKind = VDOT_R;
          VDotCh = c;
          VDotCnt = cnt;
        }
      }
      VPend = 0;
      VClrCnt();
      continue;
    }
    if (c >= '1' && c <= '9') {
      VCount = VCount * 10 + (c - '0');
      continue;
    }
    if (c == '0' && VCount > 0) {
      VCount = VCount * 10;
      continue;
    }
    cnt = VCnt();
    if (VVis) {
      if (c == 27 || c == 'v') {
        VVis = 0;
        VClrCnt();
        continue;
      }
      if (c == 'V') {
        if (VVis == 2)
          VVis = 0;
        else
          VVis = 2;
        VClrCnt();
        continue;
      }
      if (c == 'd' || c == 'x') {
        VVisDel('d');
        VClrCnt();
        continue;
      }
      if (c == 'c') {
        VVisDel('c');
        VClrCnt();
        continue;
      }
      if (c == 'y') {
        VVisDel('y');
        VClrCnt();
        continue;
      }
      if (c == 'h' || c == 'l' || c == 'j' || c == 'k' || c == 'w' || c == 'b' || c == 'e' || c == 'W' || c == 'B' || c == 'E' || c == '0' || c == '^' || c == 36 || c == 'G' || c == '%') {
        VMotion(c, cnt);
        VClrCnt();
        continue;
      }
      if (c == 'f' || c == 't' || c == 'F' || c == 'T') {
        VPend = c;
        continue;
      }
      if (c == ';' || c == ',') {
        if (VFindCh)
          for (k = 0; k < cnt; k++)
            VFindOnLine(VFindCh, c == ';' ? VFindFwd : !VFindFwd, VFindTill);
        VClrCnt();
        continue;
      }
      VClrCnt();
      continue;
    }
    if (VPendOp) {
      if (c == VPendOp) {
        if (c == 'd') {
          VSnap();
          VYankLineRange(VCy, VCy + cnt - 1);
          VDelLineRange(VCy, VCy + cnt - 1);
          VDotKind = VDOT_DD;
          VDotCnt = cnt;
        } else if (c == 'c') {
          VSnap();
          VYankLineRange(VCy, VCy + cnt - 1);
          VDelLineRange(VCy, VCy + cnt - 1);
          VInsL(VCy);
          VCx = 0;
          VInsSnap = 1;
          VMode = 1;
          VDirty = 1;
          VDotKind = VDOT_CC;
          VDotCnt = cnt;
        } else if (c == 'y') {
          VYankLineRange(VCy, VCy + cnt - 1);
          VDotKind = VDOT_YY;
          VDotCnt = cnt;
        }
        VPendOp = 0;
        VClrCnt();
        continue;
      }
      if (c == 'h' || c == 'l' || c == 'j' || c == 'k' || c == 'w' || c == 'b' || c == 'e' || c == 'W' || c == 'B' || c == 'E' || c == '0' || c == '^' || c == 36 || c == 'G' || c == '%') {
        VDoOpMotion(VPendOp, c, cnt);
        VPendOp = 0;
        VClrCnt();
        continue;
      }
      if (c == 'f' || c == 't' || c == 'F' || c == 'T') {
        VPend = c;
        continue;
      }
      VPendOp = 0;
    }
    if (c == 'd' || c == 'c' || c == 'y') {
      VOpCnt = VCnt();
      VCount = 0;
      VPendOp = c;
      continue;
    }
    if (c == 'h' || c == 'l' || c == 'j' || c == 'k' || c == 'w' || c == 'b' || c == 'e' || c == 'W' || c == 'B' || c == 'E') {
      VMotion(c, cnt);
      VClrCnt();
      continue;
    }
    if (c == '0') {
      VCx = 0;
      VClrCnt();
      continue;
    }
    if (c == '^') {
      VGoSoftBOL();
      VClrCnt();
      continue;
    }
    if (c == 36) {
      VGoEOL();
      VClrCnt();
      continue;
    }
    if (c == 'G') {
      if (VCount > 0)
        VGotoAbs(VCount - 1);
      else
        VGotoAbs(VTot > 0 ? VTot - 1 : VN - 1);
      VCx = 0;
      VClrCnt();
      continue;
    }
    if (c == 'g') {
      VPend = 'g';
      continue;
    }
    if (c == '%') {
      VMatchPct();
      VClrCnt();
      continue;
    }
    if (c == 'f' || c == 't' || c == 'F' || c == 'T') {
      VPend = c;
      continue;
    }
    if (c == ';' || c == ',') {
      if (VFindCh)
        for (k = 0; k < cnt; k++)
          VFindOnLine(VFindCh, c == ';' ? VFindFwd : !VFindFwd, VFindTill);
      VClrCnt();
      continue;
    }
    if (c == 'u') {
      VUndo();
      VClrCnt();
      continue;
    }
    if (c == '.') {
      VDotReplay();
      VClrCnt();
      continue;
    }
    if (c == 'r') {
      VPend = 'r';
      continue;
    }
    if (c == 'D') {
      for (k = 0; k < cnt; k++)
        VDelEOL();
      VClrCnt();
      continue;
    }
    if (c == 'C') {
      VSnap();
      VLn[VCy][VCx] = 0;
      VInsSnap = 1;
      VMode = 1;
      VDirty = 1;
      VDotKind = VDOT_CM;
      VDotMot = 36;
      VDotCnt = 1;
      VClrCnt();
      continue;
    }
    if (c == 'Y') {
      VYankLineRange(VCy, VCy + cnt - 1);
      VDotKind = VDOT_YY;
      VDotCnt = cnt;
      VClrCnt();
      continue;
    }
    if (c == 'J') {
      for (k = 0; k < cnt; k++)
        VJoin();
      VClrCnt();
      continue;
    }
    if (c == 'x') {
      VSnap();
      for (k = 0; k < cnt; k++) {
        n = VLen(VCy);
        if (n > 0 && VCx < n) {
          for (t = VCx; t < n; t++)
            VLn[VCy][t] = VLn[VCy][t + 1];
          n = VLen(VCy);
          if (VCx >= n && VCx > 0)
            VCx--;
          VDirty = 1;
        }
      }
      VDotKind = VDOT_X;
      VDotCnt = cnt;
      VClrCnt();
      continue;
    }
    if (c == 'X') {
      VSnap();
      for (k = 0; k < cnt; k++) {
        if (VCx > 0) {
          n = VLen(VCy);
          for (t = VCx - 1; t < n; t++)
            VLn[VCy][t] = VLn[VCy][t + 1];
          VCx--;
          VDirty = 1;
        }
      }
      VDotKind = VDOT_XB;
      VDotCnt = cnt;
      VClrCnt();
      continue;
    }
    if (c == 'p') {
      for (k = 0; k < cnt; k++)
        VPut(0);
      VDotKind = VDOT_P;
      VDotCnt = cnt;
      VClrCnt();
      continue;
    }
    if (c == 'P') {
      for (k = 0; k < cnt; k++)
        VPut(1);
      VDotKind = VDOT_PP;
      VDotCnt = cnt;
      VClrCnt();
      continue;
    }
    if (c == 'v') {
      VVis = 1;
      VMy = VCy;
      VMx = VCx;
      VClrCnt();
      continue;
    }
    if (c == 'V') {
      VVis = 2;
      VMy = VCy;
      VMx = VCx;
      VClrCnt();
      continue;
    }
    if (c == '/') {
      VSearchPrompt(1);
      VClrCnt();
      continue;
    }
    if (c == '?') {
      VSearchPrompt(-1);
      VClrCnt();
      continue;
    }
    if (c == 'n') {
      VDoSearch(VSearchDir, 1);
      VClrCnt();
      continue;
    }
    if (c == 'N') {
      VDoSearch(-VSearchDir, 1);
      VClrCnt();
      continue;
    }
    if (c == '*') {
      VStar();
      VClrCnt();
      continue;
    }
    if (c == 'o') {
      VSnap();
      if (!VInsL(VCy + 1)) {
        VClrCnt();
        continue;
      }
      VCy++;
      VCx = 0;
      VInsSnap = 1;
      VMode = 1;
      VDirty = 1;
      VClrCnt();
      continue;
    }
    if (c == 'O') {
      VSnap();
      if (!VInsL(VCy)) {
        VClrCnt();
        continue;
      }
      VCx = 0;
      VInsSnap = 1;
      VMode = 1;
      VDirty = 1;
      VClrCnt();
      continue;
    }
    if (c == 'i') {
      VEnterIns();
      VClrCnt();
      continue;
    }
    if (c == 'a') {
      // Append after cursor (EOL when already on last char). Same INSERT
      // Enter split path as i — must preserve rows below.
      if (n > 0 && VCx < n)
        VCx++;
      VEnterIns();
      VClrCnt();
      continue;
    }
    if (c == 'A') {
      VCx = n;
      VEnterIns();
      VClrCnt();
      continue;
    }
    if (c == 'I') {
      VGoSoftBOL();
      VEnterIns();
      VClrCnt();
      continue;
    }
    if (c == ':') {
      VCmd();
      VClrCnt();
      continue;
    }
    if (c == 'K') {
      VMan();
      VClrCnt();
      continue;
    }
    if (c == 29) {
      VJump();
      VClrCnt();
      continue;
    }
    if (c == '\r' || c == '\n') {
      VActivate();
      VClrCnt();
      continue;
    }
    VClrCnt();
  }
  g_term_rx_own = 0;
  TermClear();
}

U0 Vim(U8 *name)
{
  Vi(name);
}
