// ed.hc -- the classic line editor, reimplemented in HolyC (redefines the C Ed).
// Src("Ed") brings this up. Addresses: . $ N  N,M  , %   Commands: a i d p n w q =
// (. alone ends an a/i input block). Edits in-memory files via FileRead/FileLen/FileWrite.
U8 EdLn[256][128];
I64 EdN, EdCur;
U8 EdOut[16384];
U8 EdCmd[128];
U8 EdTmp[128];
// safe mid-line / Tab helpers
I64 EdP, EdA1, EdA2, EdH1, EdH2, EdAt, EdLo, EdHi, EdK, EdOff, EdM;
U8 EdCh;
// current ed command char (not EdC — that is the C-editor repair hatch)
// EdLineLen -- EdLineLen(i)
// NAME
//   EdLineLen - length of ed line i.
// SYNOPSIS
//   EdLineLen(i)
// DESCRIPTION
//   length of ed line i.
// INPUTS
//   i - argument
// OUTPUTS
//   length of ed line i.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 EdLineLen(I64 i)
{
  I64 n = 0;
  while (EdLn[i][n])
    n++;
  return n;
}
// EdSetLine -- EdSetLine(i,s)
// NAME
//   EdSetLine - set ed line i from s.
// SYNOPSIS
//   EdSetLine(i,s)
// DESCRIPTION
//   set ed line i from s.
// INPUTS
//   i - argument
//   s - argument
// OUTPUTS
//   set ed line i from s.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 EdSetLine(I64 i, U8 *s)
{
  I64 j = 0;
  while (s[j] && j < 127) {
    EdLn[i][j] = s[j];
    j++;
  }
  EdLn[i][j] = 0;
}
// Read one console line into buf (backspace-aware); returns length.
// EdReadLine -- EdReadLine(buf,max)
// NAME
//   EdReadLine - read one console line into buf (backspace-aware).
// SYNOPSIS
//   EdReadLine(buf,max)
// DESCRIPTION
//   read one console line into buf (backspace-aware).
// INPUTS
//   buf - argument
//   max - argument
// OUTPUTS
//   read one console line into buf (backspace-aware).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 EdReadLine(U8 *buf, I64 max)
{
  I64 i = 0, c, old, j;
  /* Soft RX via hc_repl HcUartGet (UartGet ring + MMIO drain). */
  while (1) {
    c = HcUartGet();
    if (c == '\r' || c == '\n') {
      PutCh('\r');
      PutCh('\n');
      break;
    }
    if ((c == 127 || c == 8) && i > 0) {
      i--;
      PutCh(8);
      PutCh(' ');
      PutCh(8);
      continue;
    }
    if (c == 9 || c == '\t') {
      // Mid-token → CI complete; else Tab → 2-space indent
      buf[i] = 0;
      old = i;
      CompCx = i;
      if (CompTab(buf, max, 1)) {
        i = CompCx;
        while (old > 0) {
          PutCh(8);
          PutCh(' ');
          PutCh(8);
          old--;
        }
        j = 0;
        while (buf[j]) {
          PutCh(buf[j]);
          j++;
        }
        continue;
      }
      if (i + 2 < max) {
        buf[i] = ' ';
        i++;
        PutCh(' ');
        buf[i] = ' ';
        i++;
        PutCh(' ');
      }
      continue;
    }
    if (i < max - 1 && c >= 32 && c < 127) {
      buf[i] = c;
      i++;
      PutCh(c);
    }
  }
  buf[i] = 0;
  return i;
}
// EdInsertAt -- EdInsertAt(pos,text)
// NAME
//   EdInsertAt - insert a line at pos.
// SYNOPSIS
//   EdInsertAt(pos,text)
// DESCRIPTION
//   insert a line at pos.
// INPUTS
//   pos - argument
//   text - argument
// OUTPUTS
//   insert a line at pos.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 EdInsertAt(I64 pos, U8 *text)
{
  I64 k;
  if (EdN >= 256) {
    "ed: buffer full\n";
    return;
  }
  for (k = EdN; k > pos; k--)
    EdSetLine(k, &EdLn[k - 1][0]);
  EdSetLine(pos, text);
  EdN++;
}
// EdDeleteRange -- EdDeleteRange(a,b)
// NAME
//   EdDeleteRange - delete lines a..b inclusive (1-based).
// SYNOPSIS
//   EdDeleteRange(a,b)
// DESCRIPTION
//   delete lines a..b inclusive (1-based).
// INPUTS
//   a - argument
//   b - argument
// OUTPUTS
//   delete lines a..b inclusive (1-based).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 EdDeleteRange(I64 a, I64 b)
{
  I64 k, cnt;
  if (a < 1)
    a = 1;
  if (b > EdN)
    b = EdN;
  if (a > b)
    return;
  cnt = b - a + 1;
  for (k = a - 1; k + cnt < EdN; k++)
    EdSetLine(k, &EdLn[k + cnt][0]);
  EdN -= cnt;
}
// EdInputBlock -- EdInputBlock(at)
// NAME
//   EdInputBlock - read lines until . into the buffer at at.
// SYNOPSIS
//   EdInputBlock(at)
// DESCRIPTION
//   read lines until . into the buffer at at.
// INPUTS
//   at - argument
// OUTPUTS
//   read lines until . into the buffer at at.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 EdInputBlock(I64 at)
{
  U8 line[128];
  I64 len;
  while (1) {
    len = EdReadLine(line, 128);
    if (len == 1 && line[0] == '.')
      break;
    EdInsertAt(at, line);
    at++;
  }
  EdCur = at;
}
// EdParseAddr -- EdParseAddr(s,pp,have)
// NAME
//   EdParseAddr - parse an ed address (. $ N).
// SYNOPSIS
//   EdParseAddr(s,pp,have)
// DESCRIPTION
//   parse an ed address (. $ N).
// INPUTS
//   s - argument
//   pp - argument
//   have - argument
// OUTPUTS
//   parse an ed address (. $ N).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 EdParseAddr(U8 *s, I64 *pp, I64 *have)
{
  I64 p = *pp, v = -1;
  *have = 0;
  while (s[p] == ' ')
    p++;
  if (s[p] == '.') {
    v = EdCur;
    *have = 1;
    p++;
  } else if (s[p] == '$') {
    v = EdN;
    *have = 1;
    p++;
  } else if (s[p] >= '0' && s[p] <= '9') {
    v = 0;
    while (s[p] >= '0' && s[p] <= '9') {
      v = v * 10 + s[p] - '0';
      p++;
    }
    *have = 1;
  }
  *pp = p;
  return v;
}
// Ed -- Ed(name)
// NAME
//   Ed - classic line editor
// SYNOPSIS
//   U0 Ed(U8 *name);
// DESCRIPTION
//   Opens a simple line-oriented editor on a memfs file (a/i/d/p/n/w/q). Good for
//   scripted smoke and tiny edits. Prefer Vi or EditHoly for full-screen work;
//   EdC is the C escape hatch if HolyC Ed breaks.
// EXAMPLES
//   // Ed("boot.hc");   // interactive — use q to quit
//   Man("EdC");
//   Dir;
// SEE ALSO
//   EdC  EdHoly  Vi  Edit  Src  Cat
// BUGS
//   repl-holyc: always EdHoly (soft RX). Legacy host slot 0x870010B8 is cleared.
U0 Ed(U8 *name)
{
  EdHoly(name);
}

U0 EdHoly(U8 *name)
{
  U8 *data;
  I64 dn, i, j;
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
  EdCur = EdN;
  "ed %s: %d lines. cmds: a i d p n w q = !  (! runs HolyC; '.' ends input)\n", name, EdN;
  while (1) {
    EdReadLine(EdCmd, 128);
    EdP = 0;
    while (EdCmd[EdP] == ' ')
      EdP++;
    EdA1 = -1;
    EdA2 = -1;
    EdH1 = 0;
    EdH2 = 0;
    if (EdCmd[EdP] == ',' || EdCmd[EdP] == '%') {
      EdA1 = 1;
      EdA2 = EdN;
      EdH1 = 1;
      EdH2 = 1;
      EdP++;
    } else {
      EdA1 = EdParseAddr(EdCmd, &EdP, &EdH1);
      if (EdCmd[EdP] == ',') {
        EdP++;
        EdA2 = EdParseAddr(EdCmd, &EdP, &EdH2);
      }
    }
    EdCh = EdCmd[EdP];
    if (EdCh == 'a') {
      EdAt = EdH1 ? EdA1 : EdCur;
      if (EdAt < 0)
        EdAt = 0;
      if (EdAt > EdN)
        EdAt = EdN;
      EdInputBlock(EdAt);
    } else if (EdCh == 'i') {
      EdAt = (EdH1 ? EdA1 : EdCur) - 1;
      if (EdAt < 0)
        EdAt = 0;
      if (EdAt > EdN)
        EdAt = EdN;
      EdInputBlock(EdAt);
    } else if (EdCh == 'd') {
      EdLo = EdH1 ? EdA1 : EdCur;
      EdHi = EdH2 ? EdA2 : EdLo;
      EdDeleteRange(EdLo, EdHi);
      if (EdCur > EdN)
        EdCur = EdN;
    } else if (EdCh == 'p' || EdCh == 'n') {
      EdLo = EdH1 ? EdA1 : EdCur;
      EdHi = EdH2 ? EdA2 : EdLo;
      if (EdLo < 1)
        EdLo = 1;
      if (EdHi > EdN)
        EdHi = EdN;
      for (EdK = EdLo; EdK <= EdHi; EdK++) {
        if (EdCh == 'n') {
          "%d", EdK;
          PutCh('\t');
        }
        "%s", &EdLn[EdK - 1][0];
        PutCh('\n');
      }
      if (EdHi >= 1)
        EdCur = EdHi;
    } else if (EdCh == 'w') {
      EdOff = 0;
      for (EdK = 0; EdK < EdN; EdK++) {
        EdM = 0;
        while (EdLn[EdK][EdM] && EdOff < 16383) {
          EdOut[EdOff] = EdLn[EdK][EdM];
          EdOff++;
          EdM++;
        }
        if (EdOff < 16383) {
          EdOut[EdOff] = '\n';
          EdOff++;
        }
      }
      EdOut[EdOff] = 0;
      EdOff = FmtSave(name, EdOut, EdOff);
      if (IsHcName(name)) {
        data = FileRead(name);
        dn = FileLen(name);
        if (dn < 0)
          dn = 0;
        EdN = 0;
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
        if (EdCur > EdN)
          EdCur = EdN;
      }
      "wrote %s (%d bytes)\n", name, EdOff;
    } else if (EdCh == 'q') {
      "\n";
      return;
    } else if (EdCh == '!') {
      Exec(&EdCmd[EdP + 1]);
    } else if (EdCh == '=') {
      "%d\n", EdH1 ? EdA1 : EdCur;
    } else if (EdCh == 0) {
      if (EdH1) {
        if (EdA1 >= 1 && EdA1 <= EdN) {
          EdCur = EdA1;
          "%s", &EdLn[EdA1 - 1][0];
          PutCh('\n');
        }
      } else if (EdCur < EdN) {
        EdCur++;
        "%s", &EdLn[EdCur - 1][0];
        PutCh('\n');
      }
    } else
      "?\n";
  }
}
// EdC -- EdC("file")
// NAME
//   EdC - C line editor escape hatch
// SYNOPSIS
//   U0 EdC(U8 *file);
// DESCRIPTION
//   Always-available C line editor if HolyC Ed/EdHoly breaks. Same host slot as
//   Ed. Prefer Ed after boot; use EdC when recovering a broken editor.
// EXAMPLES
//   // EdC("boot.hc");  // interactive
//   Man("Ed");
//   SrcFile("EdC");
// SEE ALSO
//   Ed  EdHoly  Vi  Edit  Src
// BUGS
//   Once-indirect to C; not live-editable beyond this trampoline.
U0 EdC(U8 *name)
{
  I64 (*ed)(U8 *name);
  ed = *(I64 *)0x870010B8;
  if (ed)
    ed(name);
}
