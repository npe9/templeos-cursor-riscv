// edit.hc -- the basic full-screen terminal editor, reimplemented in HolyC (redefines Edit).
// Nano-style, ANSI: type inserts, arrow keys move, Enter splits, Backspace deletes/joins,
// Delete = ESC[3~, ^O saves, ^X exits. Reuses ed.hc's EdLn/EdN and helpers. Src("Edit") brings
// this up; EditC is the C escape hatch. Control output goes via PutCh (raw bytes), so ANSI
// escapes are exact.
I64 EvTop, EvCx, EvCy;
U8  EvMsg[96];

U0 EvGoto(I64 row, I64 col) {          // ESC [ row ; col H  (1-based)
  PutCh(27); PutCh('[');
  "%d", row; PutCh(';'); "%d", col; PutCh('H');
}
U0 EvClrLine() { PutCh(27); PutCh('['); PutCh('2'); PutCh('K'); }

U0 EvRender(U8 *name, U8 *msg) {
  I64 r, li, j;
  PutCh(27); PutCh('['); PutCh('H');
  for (r = 0; r < 22; r++) {
    EvGoto(r + 1, 1); EvClrLine();
    li = EvTop + r;
    if (li < EdN) { j = 0; while (EdLn[li][j] && j < 80) { PutCh(EdLn[li][j]); j++; } }
    else PutCh('~');
  }
  EvGoto(23, 1);
  PutCh(27); PutCh('['); PutCh('7'); PutCh('m');          // reverse video status bar
  EvClrLine();
  PutCh(' '); UartStr(name);
  UartStr("  ln "); "%d", EvCy + 1; PutCh('/'); "%d", EdN;
  UartStr("  col "); "%d", EvCx + 1;
  UartStr("   ^O save  ^X exit");
  PutCh(27); PutCh('['); PutCh('0'); PutCh('m');
  EvGoto(24, 1); EvClrLine();
  if (msg[0]) UartStr(msg);
  EvGoto(EvCy - EvTop + 1, EvCx + 1);                     // place the cursor
}
// Save the buffer and build EvMsg = "wrote <name> (<off> bytes)" for the status line.
U0 EvSave(U8 *name) {
  I64 off = 0, k, m, i, t, v;
  U8 *p;
  U8 tmp[16];
  for (k = 0; k < EdN; k++) {
    m = 0;
    while (EdLn[k][m] && off < 16383) { EdOut[off] = EdLn[k][m]; off++; m++; }
    if (off < 16383) { EdOut[off] = '\n'; off++; }
  }
  EdOut[off] = 0;
  FileWrite(name, EdOut, off);
  i = 0; p = "wrote ";
  while (*p) { EvMsg[i] = *p; i++; p++; }
  p = name;
  while (*p) { EvMsg[i] = *p; i++; p++; }
  EvMsg[i] = ' '; i++; EvMsg[i] = '('; i++;
  if (off == 0) { EvMsg[i] = '0'; i++; }
  else { t = 0; v = off; while (v) { tmp[t] = '0' + v % 10; t++; v /= 10; } while (t) { t--; EvMsg[i] = tmp[t]; i++; } }
  p = " bytes)";
  while (*p) { EvMsg[i] = *p; i++; p++; }
  EvMsg[i] = 0;
}
U0 Edit(U8 *name) {
  U8 *data, *msg;
  I64 dn, i, j, c, b1, b2, len, pl, dirty;
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
  if (EdN == 0) { EdLn[0][0] = 0; EdN = 1; }
  EvTop = 0; EvCx = 0; EvCy = 0; dirty = 0;
  msg = "";
  PutCh(27); PutCh('['); PutCh('2'); PutCh('J');
  EvRender(name, msg);
  while (1) {
    c = GetCh();
    msg = "";
    if (c == 24) {                                        // ^X exit
      if (dirty) { msg = "modified -- ^O to save, or ^X again to discard"; dirty = 0; EvRender(name, msg); continue; }
      break;
    }
    else if (c == 15) { EvSave(name); msg = EvMsg; dirty = 0; }      // ^O save
    else if (c == 27) {                                   // ESC [ A/B/C/D , ESC [ 3 ~
      b1 = GetCh();
      if (b1 == '[') {
        b2 = GetCh();
        len = EdLineLen(EvCy);
        if (b2 == 'A') { if (EvCy > 0) { EvCy--; if (EvCx > EdLineLen(EvCy)) EvCx = EdLineLen(EvCy); } }
        else if (b2 == 'B') { if (EvCy < EdN - 1) { EvCy++; if (EvCx > EdLineLen(EvCy)) EvCx = EdLineLen(EvCy); } }
        else if (b2 == 'C') { if (EvCx < len) EvCx++; else if (EvCy < EdN - 1) { EvCy++; EvCx = 0; } }
        else if (b2 == 'D') { if (EvCx > 0) EvCx--; else if (EvCy > 0) { EvCy--; EvCx = EdLineLen(EvCy); } }
        else if (b2 == '3') { GetCh(); if (EvCx < len) { for (j = EvCx; EdLn[EvCy][j]; j++) EdLn[EvCy][j] = EdLn[EvCy][j + 1]; dirty = 1; } }
      }
    }
    else if (c == '\r' || c == '\n') {                    // split line at cursor
      if (EdN < 256) { EdInsertAt(EvCy + 1, &EdLn[EvCy][EvCx]); EdLn[EvCy][EvCx] = 0; EvCy++; EvCx = 0; dirty = 1; }
    }
    else if (c == 127 || c == 8) {                        // backspace
      if (EvCx > 0) { for (j = EvCx - 1; EdLn[EvCy][j]; j++) EdLn[EvCy][j] = EdLn[EvCy][j + 1]; EvCx--; dirty = 1; }
      else if (EvCy > 0) {                                // join with previous line
        pl = EdLineLen(EvCy - 1); j = 0;
        while (EdLn[EvCy][j] && pl + j < 127) { EdLn[EvCy - 1][pl + j] = EdLn[EvCy][j]; j++; }
        EdLn[EvCy - 1][pl + j] = 0;
        EdDeleteRange(EvCy + 1, EvCy + 1);
        EvCy--; EvCx = pl; dirty = 1;
      }
    }
    else if (c >= 32 && c < 127) {                        // printable: insert at cursor
      len = EdLineLen(EvCy);
      if (len < 127) { for (j = len; j >= EvCx; j--) EdLn[EvCy][j + 1] = EdLn[EvCy][j]; EdLn[EvCy][EvCx] = c; EvCx++; dirty = 1; }
    }
    if (EvCy < EvTop) EvTop = EvCy;                       // vertical scroll
    if (EvCy >= EvTop + 22) EvTop = EvCy - 22 + 1;
    EvRender(name, msg);
  }
  PutCh(27); PutCh('['); PutCh('2'); PutCh('J'); PutCh(27); PutCh('['); PutCh('H');
}
