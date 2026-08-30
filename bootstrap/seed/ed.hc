// ed.hc -- the classic line editor, reimplemented in HolyC (redefines the C Ed).
// Src("Ed") brings this up. Addresses: . $ N  N,M  , %   Commands: a i d p n w q =
// ('.' alone ends an a/i input block). Edits in-memory files via FileRead/FileLen/FileWrite.
U8  EdLn[256][128];
I64 EdN, EdCur;
U8  EdOut[16384];

I64 EdLineLen(I64 i) { I64 n = 0; while (EdLn[i][n]) n++; return n; }
U0 EdSetLine(I64 i, U8 *s) { I64 j = 0; while (s[j] && j < 127) { EdLn[i][j] = s[j]; j++; } EdLn[i][j] = 0; }

// Read one console line into buf (backspace-aware); returns length.
I64 EdReadLine(U8 *buf, I64 max) {
  I64 i = 0, c;
  while (1) {
    c = GetCh();
    if (c == 0) continue;
    if (c == '\r' || c == '\n') { PutCh('\r'); PutCh('\n'); break; }
    if ((c == 127 || c == 8) && i > 0) { i--; PutCh(8); PutCh(' '); PutCh(8); continue; }
    if (i < max - 1 && c >= 32 && c < 127) { buf[i] = c; i++; PutCh(c); }
  }
  buf[i] = 0;
  return i;
}

U0 EdInsertAt(I64 pos, U8 *text) {
  I64 k;
  if (EdN >= 256) { "ed: buffer full\n"; return; }
  for (k = EdN; k > pos; k--) EdSetLine(k, &EdLn[k - 1][0]);
  EdSetLine(pos, text);
  EdN++;
}
U0 EdDeleteRange(I64 a, I64 b) {
  I64 k, cnt;
  if (a < 1) a = 1;
  if (b > EdN) b = EdN;
  if (a > b) return;
  cnt = b - a + 1;
  for (k = a - 1; k + cnt < EdN; k++) EdSetLine(k, &EdLn[k + cnt][0]);
  EdN -= cnt;
}
U0 EdInputBlock(I64 at) {
  U8 line[128];
  I64 len;
  while (1) {
    len = EdReadLine(line, 128);
    if (len == 1 && line[0] == '.') break;
    EdInsertAt(at, line);
    at++;
  }
  EdCur = at;
}
I64 EdParseAddr(U8 *s, I64 *pp, I64 *have) {
  I64 p = *pp, v = -1;
  *have = 0;
  while (s[p] == ' ') p++;
  if (s[p] == '.') { v = EdCur; *have = 1; p++; }
  else if (s[p] == '$') { v = EdN; *have = 1; p++; }
  else if (s[p] >= '0' && s[p] <= '9') { v = 0; while (s[p] >= '0' && s[p] <= '9') { v = v * 10 + s[p] - '0'; p++; } *have = 1; }
  *pp = p;
  return v;
}
U0 Ed(U8 *name) {
  U8 *data;
  I64 dn, i, j;
  U8 cmd[128];
  EdN = 0;
  data = FileRead(name);
  dn = FileLen(name);
  if (dn < 0) dn = 0;
  if (data) {
    i = 0;
    while (i < dn && EdN < 256) {
      j = 0;
      while (i < dn && data[i] != '\n' && j < 127) { EdLn[EdN][j] = data[i]; j++; i++; }
      EdLn[EdN][j] = 0;
      while (i < dn && data[i] != '\n') i++;
      if (i < dn && data[i] == '\n') i++;
      EdN++;
    }
  }
  EdCur = EdN;
  "ed %s: %d lines. cmds: a i d p n w q =  ('.' ends input)\n", name, EdN;
  while (1) {
    I64 p, a1, a2, h1, h2, at, lo, hi, k, off, m;
    U8 c;
    EdReadLine(cmd, 128);
    p = 0; while (cmd[p] == ' ') p++;
    a1 = -1; a2 = -1; h1 = 0; h2 = 0;
    if (cmd[p] == ',' || cmd[p] == '%') { a1 = 1; a2 = EdN; h1 = 1; h2 = 1; p++; }
    else {
      a1 = EdParseAddr(cmd, &p, &h1);
      if (cmd[p] == ',') { p++; a2 = EdParseAddr(cmd, &p, &h2); }
    }
    c = cmd[p];
    if (c == 'a') { at = h1 ? a1 : EdCur; if (at < 0) at = 0; if (at > EdN) at = EdN; EdInputBlock(at); }
    else if (c == 'i') { at = (h1 ? a1 : EdCur) - 1; if (at < 0) at = 0; if (at > EdN) at = EdN; EdInputBlock(at); }
    else if (c == 'd') { lo = h1 ? a1 : EdCur; hi = h2 ? a2 : lo; EdDeleteRange(lo, hi); if (EdCur > EdN) EdCur = EdN; }
    else if (c == 'p' || c == 'n') {
      lo = h1 ? a1 : EdCur; hi = h2 ? a2 : lo;
      if (lo < 1) lo = 1; if (hi > EdN) hi = EdN;
      for (k = lo; k <= hi; k++) { if (c == 'n') { "%d", k; PutCh('\t'); } "%s", &EdLn[k - 1][0]; PutCh('\n'); }
      if (hi >= 1) EdCur = hi;
    }
    else if (c == 'w') {
      off = 0;
      for (k = 0; k < EdN; k++) {
        m = 0;
        while (EdLn[k][m] && off < 16383) { EdOut[off] = EdLn[k][m]; off++; m++; }
        if (off < 16383) { EdOut[off] = '\n'; off++; }
      }
      EdOut[off] = 0;
      FileWrite(name, EdOut, off);
      "wrote %s (%d bytes)\n", name, off;
    }
    else if (c == 'q') { "\n"; return; }
    else if (c == '=') { "%d\n", h1 ? a1 : EdCur; }
    else if (c == 0) {
      if (h1) { if (a1 >= 1 && a1 <= EdN) { EdCur = a1; "%s", &EdLn[a1 - 1][0]; PutCh('\n'); } }
      else if (EdCur < EdN) { EdCur++; "%s", &EdLn[EdCur - 1][0]; PutCh('\n'); }
    }
    else "?\n";
  }
}
