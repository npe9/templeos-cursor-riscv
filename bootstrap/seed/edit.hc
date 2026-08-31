// edit.hc -- HolyC full-screen editor (redefines Edit). TermKeyGet; Tab=complete/2sp.
// ^O save, ^G activate, ^] src (session push; ^X pops), ^K Man under cursor, ^X exit.
// Declares `editor`; RVEditorSelected sets default. EditC = C escape hatch.
I64 EvTop, EvCx, EvCy, EvDoLoad;
U8 EvMsg[96], EvName[64];
I64 EvK, EvLen, EvDirty, EvTr, EvJ, EvPl;
#define EVSESS_MAX 4
U8 EvSessPath[EVSESS_MAX][64];
I64 EvSessCy[EVSESS_MAX], EvSessCx[EVSESS_MAX], EvSessTop[EVSESS_MAX], EvSessDirty[EVSESS_MAX];
I64 EvSessDepth;
U0 EvRender(U8 *name, U8 *msg)
{
  I64 r, li, j, tr, tc, sr;
  tr = TermRows() - 2;
  tc = TermCols();
  sr = TermRows();
  if (tr < 1)
    tr = 1;
  TermGoto(1, 1);
  for (r = 0; r < tr; r++) {
    TermGoto(r + 1, 1);
    TermClearEol();
    li = EvTop + r;
    if (li < EdN) {
      j = 0;
      while (EdLn[li][j] && j < tc) {
        PutCh(EdLn[li][j]);
        j++;
      }
    } else
      PutCh('~');
  }
  TermGoto(sr - 1, 1);
  PutCh(27);
  PutCh('[');
  PutCh('7');
  PutCh('m');
  TermClearEol();
  PutCh(' ');
  UartStr(name);
  UartStr(" ln ");
  "%d", EvCy + 1;
  PutCh('/');
  "%d", EdN;
  UartStr(" col ");
  "%d", EvCx + 1;
  UartStr(" ^O save ^G go ^] src ^K man ^X exit");
  PutCh(27);
  PutCh('[');
  PutCh('0');
  PutCh('m');
  TermGoto(sr, 1);
  TermClearEol();
  if (msg[0])
    UartStr(msg);
  TermGoto(EvCy - EvTop + 1, EvCx + 1);
}

U0 EvSave(U8 *name)
{
  I64 off, k, m, n, t, v;
  U8 dig[16];
  off = 0;
  for (k = 0; k < EdN; k++) {
    m = 0;
    while (EdLn[k][m] && off < 16383) {
      EdOut[off] = EdLn[k][m];
      off++;
      m++;
    }
    if (off < 16383) {
      EdOut[off] = '\n';
      off++;
    }
  }
  EdOut[off] = 0;
  n = FmtSave(name, EdOut, off);
  if (n < 0)
    n = 0;
  UartStr("wrote ");
  if (name)
    UartStr(name);
  UartStr(" (");
  if (!n)
    PutCh('0');
  else {
    t = 0;
    v = n;
    while (v) {
      dig[t] = '0' + v % 10;
      t++;
      v = v / 10;
    }
    while (t) {
      t--;
      PutCh(dig[t]);
    }
  }
  UartStr(" bytes)\n");
  EvMsg[0] = 0;
}

U0 EvLoad(U8 *name)
{
  U8 *data;
  I64 dn, i, j, p;
  p = 0;
  while (name[p] && p < 63) {
    EvName[p] = name[p];
    p++;
  }
  EvName[p] = 0;
  EdN = 0;
  data = FileRead(name);
  dn = FileLen(name);
  if (dn < 0)
    dn = 0;
  if (data) {
    i = 0;
    while (i < dn && EdN < 256) {
      j = 0;
      while (i < dn && data[i] != '\n' && j < 127) {
        EdLn[EdN][j] = data[i];
        j++;
        i++;
      }
      EdLn[EdN][j] = 0;
      while (i < dn && data[i] != '\n')
        i++;
      if (i < dn && data[i] == '\n')
        i++;
      EdN++;
    }
  }
  if (EdN == 0) {
    EdLn[0][0] = 0;
    EdN = 1;
  }
  EvTop = 0;
  EvCx = 0;
  EvCy = 0;
}

U0 EvSessPush()
{
  I64 d, k, m, off;
  U8 spill[8];
  d = EvSessDepth;
  k = 0;
  while (EvName[k] && k < 63) {
    EvSessPath[d][k] = EvName[k];
    k++;
  }
  EvSessPath[d][k] = 0;
  EvSessCy[d] = EvCy;
  EvSessCx[d] = EvCx;
  EvSessTop[d] = EvTop;
  EvSessDirty[d] = EvDirty;
  spill[0] = '.';
  spill[1] = 'e';
  spill[2] = 's';
  spill[3] = '0' + d;
  spill[4] = 0;
  off = 0;
  for (k = 0; k < EdN; k++) {
    m = 0;
    while (EdLn[k][m] && off < 16383) {
      EdOut[off] = EdLn[k][m];
      off++;
      m++;
    }
    if (off < 16383) {
      EdOut[off] = '\n';
      off++;
    }
  }
  EdOut[off] = 0;
  FileWrite(spill, EdOut, off);
  EvSessDepth = d + 1;
}

U0 EvSessPop()
{
  I64 d, k;
  U8 spill[8];
  if (EvSessDepth <= 0)
    return;
  EvSessDepth--;
  d = EvSessDepth;
  spill[0] = '.';
  spill[1] = 'e';
  spill[2] = 's';
  spill[3] = '0' + d;
  spill[4] = 0;
  EvLoad(spill);
  k = 0;
  while (EvSessPath[d][k] && k < 63) {
    EvName[k] = EvSessPath[d][k];
    k++;
  }
  EvName[k] = 0;
  EvCy = EvSessCy[d];
  EvCx = EvSessCx[d];
  EvTop = EvSessTop[d];
  EvDirty = EvSessDirty[d];
  EvDoLoad = 0;
  if (EvCy >= EdN)
    EvCy = EdN - 1;
  if (EvCy < 0)
    EvCy = 0;
  if (EvCx > EdLineLen(EvCy))
    EvCx = EdLineLen(EvCy);
}

I64 EvTryQuit()
{
  if (EvSessDepth > 0) {
    EvSessPop();
    return 0;
  }
  return 1;
}

U0 EvJumpSeek(U8 *name)
{
  I64 i, col;
  for (i = 0; i < EdN; i++) {
    col = DefAt(&EdLn[i][0], name);
    if (col >= 0) {
      EvCy = i;
      EvCx = col;
      return;
    }
  }
  for (i = 0; i < EdN; i++) {
    col = IdentAt(&EdLn[i][0], name);
    if (col >= 0) {
      EvCy = i;
      EvCx = col;
      return;
    }
  }
}

U0 EvOpen(U8 *fn, I64 do_seek)
{
  I64 p;
  if (EvSessDepth >= EVSESS_MAX)
    return;
  EvSessPush();
  p = 0;
  while (fn[p] && p < 63) {
    EvName[p] = fn[p];
    p++;
  }
  EvName[p] = 0;
  EvLoad(fn);
  EvDirty = 0;
  EvDoLoad = 0;
  if (do_seek && JumpIdent[0])
    EvJumpSeek(JumpIdent);
}

U0 EvJumpName(U8 *fn)
{
  I64 p;
  p = 0;
  while (fn[p] && p < 63) {
    JumpFile[p] = fn[p];
    p++;
  }
  JumpFile[p] = 0;
}

U0 EvJump()
{
  U8 *fn;
  JumpIdent[0] = 0;
  EvDoLoad = 0;
  WordIdent(&EdLn[EvCy][0], EvCx, JumpIdent);
  if (!JumpIdent[0])
    return;
  fn = SrcFile(JumpIdent);
  if (!fn) {
    JumpIdent[0] = 0;
    return;
  }
  EvJumpName(fn);
  EvOpen(JumpFile, 1);
}

U0 EvActivate()
{
  U8 w[64];
  I64 k;
  WordAt(&EdLn[EvCy][0], EvCx, w);
  k = LinkKind(w, w);
  if (k == 1) {
    LinkCd(w);
    if (!StrCmp(EvName, ".dirlist")) {
      DirWrite();
      EvLoad(".dirlist");
    }
  } else if (k == 2) {
    JumpIdent[0] = 0;
    EvOpen(w, 0);
  } else if (w[0])
    EvJump();
}

U0 EvMan()
{
  WordIdent(&EdLn[EvCy][0], EvCx, JumpIdent);
  if (!JumpIdent[0])
    return;
  TermClear();
  Man(JumpIdent);
  UartStr("-- press a key --");
  TermKeyGet();
}

U0 Edit(U8 *name)
{
  I64 (*ed)(U8 *);
  ed = *(I64 *)0x870010E0;
  if (ed)
    ed(name);
}

U0 EditHoly(U8 *name)
{
  U8 *msg;
  EvSessDepth = 0;
  EvLoad(name);
  EvDirty = 0;
  EvDoLoad = 0;
  msg = "";
  TermProbe();
  TermClear();
  EvRender(EvName, msg);
  while (1) {
    EvK = TermKeyGet();
    EvTr = TermRows() - 2;
    if (EvTr < 1)
      EvTr = 1;
    EvLen = EdLineLen(EvCy);
    msg = "";
    if (EvK == 24) {
      if (EvDirty) {
        msg = "modified -- ^O to save, or ^X again to discard";
        EvDirty = 0;
        EvRender(EvName, msg);
        continue;
      }
      if (EvTryQuit())
        break;
    } else if (EvK == 15) {
      EvSave(EvName);
      msg = EvMsg;
      EvDirty = 0;
    } else if (EvK == 7)
      EvActivate();
    else if (EvK == 29)
      EvJump();
    else if (EvK == 11)
      EvMan();
    else if (EvK == KEY_UP) {
      if (EvCy > 0) {
        EvCy--;
        if (EvCx > EdLineLen(EvCy))
          EvCx = EdLineLen(EvCy);
      }
    } else if (EvK == KEY_DOWN) {
      if (EvCy < EdN - 1) {
        EvCy++;
        if (EvCx > EdLineLen(EvCy))
          EvCx = EdLineLen(EvCy);
      }
    } else if (EvK == KEY_RIGHT) {
      if (EvCx < EvLen)
        EvCx++;
      else if (EvCy < EdN - 1) {
        EvCy++;
        EvCx = 0;
      }
    } else if (EvK == KEY_LEFT) {
      if (EvCx > 0)
        EvCx--;
      else if (EvCy > 0) {
        EvCy--;
        EvCx = EdLineLen(EvCy);
      }
    } else if (EvK == KEY_HOME)
      EvCx = 0;
    else if (EvK == KEY_END)
      EvCx = EvLen;
    else if (EvK == KEY_PGUP) {
      EvCy -= EvTr;
      if (EvCy < 0)
        EvCy = 0;
      if (EvCx > EdLineLen(EvCy))
        EvCx = EdLineLen(EvCy);
    } else if (EvK == KEY_PGDN) {
      EvCy += EvTr;
      if (EvCy > EdN - 1)
        EvCy = EdN - 1;
      if (EvCx > EdLineLen(EvCy))
        EvCx = EdLineLen(EvCy);
    } else if (EvK == KEY_DELETE) {
      if (EvCx < EvLen) {
        for (EvJ = EvCx; EdLn[EvCy][EvJ]; EvJ++)
          EdLn[EvCy][EvJ] = EdLn[EvCy][EvJ + 1];
        EvDirty = 1;
      }
    } else if (EvK == '\r' || EvK == '\n') {
      if (!StrCmp(EvName, ".dirlist"))
        EvActivate();
      else if (EdN < 256) {
        EvJ = 0;
        EvPl = EvCx;
        while (EdLn[EvCy][EvPl] && EvJ < 127) {
          EdTmp[EvJ] = EdLn[EvCy][EvPl];
          EvJ++;
          EvPl++;
        }
        EdTmp[EvJ] = 0;
        EdLn[EvCy][EvCx] = 0;
        EdInsertAt(EvCy + 1, EdTmp);
        EvCy++;
        EvCx = 0;
        EvDirty = 1;
      }
    } else if (EvK == 127 || EvK == 8) {
      if (EvCx > 0) {
        for (EvJ = EvCx - 1; EdLn[EvCy][EvJ]; EvJ++)
          EdLn[EvCy][EvJ] = EdLn[EvCy][EvJ + 1];
        EvCx--;
        EvDirty = 1;
      } else if (EvCy > 0) {
        EvPl = EdLineLen(EvCy - 1);
        EvJ = 0;
        while (EdLn[EvCy][EvJ] && EvPl + EvJ < 127) {
          EdLn[EvCy - 1][EvPl + EvJ] = EdLn[EvCy][EvJ];
          EvJ++;
        }
        EdLn[EvCy - 1][EvPl + EvJ] = 0;
        EdDeleteRange(EvCy + 1, EvCy + 1);
        EvCy--;
        EvCx = EvPl;
        EvDirty = 1;
      }
    } else if (EvK == 9 || EvK == '\t') {
      if (!CompTab(&EdLn[EvCy][0], 128, &EvCx, 0)) {
        if (EvLen + 2 <= 127) {
          for (EvJ = 0; EvJ < 2; EvJ++) {
            EvLen = EdLineLen(EvCy);
            for (EvPl = EvLen; EvPl >= EvCx; EvPl--)
              EdLn[EvCy][EvPl + 1] = EdLn[EvCy][EvPl];
            EdLn[EvCy][EvCx] = ' ';
            EvCx++;
          }
          EvDirty = 1;
        }
      } else
        EvDirty = 1;
    } else if (EvK >= 32 && EvK < 127) {
      if (EvLen < 127) {
        for (EvJ = EvLen; EvJ >= EvCx; EvJ--)
          EdLn[EvCy][EvJ + 1] = EdLn[EvCy][EvJ];
        EdLn[EvCy][EvCx] = EvK;
        EvCx++;
        EvDirty = 1;
      }
    }
    if (EvCy < EvTop)
      EvTop = EvCy;
    if (EvCy >= EvTop + EvTr)
      EvTop = EvCy - EvTr + 1;
    EvRender(EvName, msg);
  }
  g_term_rx_own = 0;
  TermClear();
}

U0 EditC(U8 *name)
{
  I64 (*ed)(U8 *);
  ed = *(I64 *)0x870010E0;
  if (ed)
    ed(name);
}
U0 (*editor)(U8 *);
