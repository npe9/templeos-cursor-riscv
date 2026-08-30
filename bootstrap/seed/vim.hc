// vim.hc -- a modal vim-lite over ANSI serial, in HolyC. Vi("file.hc") edits an in-memory file
// full-screen: NORMAL (hjkl 0 $ gg G x dd o O i a A I :), INSERT (ESC out), COMMAND
// (:w :q :q! :wq :x :<n> :!holyc). Arrows work (ESC [ A/B/C/D). 20-line viewport + status bar.
// Edit the editor: Src("Vi"). Same fixed-slot file model as ed.hc: 256 lines x 128 cols.
U8  VLn[256][128];
U8  VOut[16384];
I64 VN, VCy, VCx, VTop, VMode, VDirty, VQuit, VPush;
U8  VFile[64];

I64 VLen(I64 i) { I64 n = 0; while (VLn[i][n]) n++; return n; }
U0  VEsc(U8 *s) { PutCh(27); "%s", s; }
U0  VGoto(I64 r, I64 c) { PutCh(27); "[%d;%dH", r, c; }
// Blocking key read with pushback (GetCh itself returns 0 when idle).
I64 VGet() {
  I64 c;
  if (VPush) { c = VPush; VPush = 0; return c; }
  while (1) { c = GetCh(); if (c) return c; }
}
// One keystroke, arrows folded to hjkl. Bare ESC vs ESC-sequence: poll briefly for a following
// byte; '[' means a sequence, anything else is pushed back and the ESC stands alone.
I64 VKey() {
  I64 c, c2, c3, i;
  c = VGet();
  if (c != 27) return c;
  c2 = 0;
  for (i = 0; i < 30000; i++) { c2 = GetCh(); if (c2) break; }
  if (!c2) return 27;
  if (c2 != '[') { VPush = c2; return 27; }
  c3 = VGet();
  if (c3 == 'A') return 'k';
  if (c3 == 'B') return 'j';
  if (c3 == 'C') return 'l';
  if (c3 == 'D') return 'h';
  return 27;
}
U0 VSetL(I64 i, U8 *s) { I64 j = 0; while (s[j] && j < 127) { VLn[i][j] = s[j]; j++; } VLn[i][j] = 0; }
U0 VInsL(I64 pos) {   // open an empty line at pos (shift down)
  I64 k;
  if (VN >= 256) return;
  for (k = VN; k > pos; k--) VSetL(k, &VLn[k - 1][0]);
  VLn[pos][0] = 0;
  VN++;
}
U0 VDelL(I64 pos) {   // delete line pos (shift up); keep at least one line
  I64 k;
  for (k = pos; k < VN - 1; k++) VSetL(k, &VLn[k + 1][0]);
  VN--;
  if (VN < 1) { VN = 1; VLn[0][0] = 0; }
}
U0 VLoad(U8 *name) {
  U8 *data; I64 dn, i, j;
  VN = 0;
  data = FileRead(name);
  dn = FileLen(name);
  if (dn < 0) dn = 0;
  if (data) {
    i = 0;
    while (i < dn && VN < 256) {
      j = 0;
      while (i < dn && data[i] != '\n' && j < 127) { VLn[VN][j] = data[i]; j++; i++; }
      VLn[VN][j] = 0;
      while (i < dn && data[i] != '\n') i++;
      if (i < dn && data[i] == '\n') i++;
      VN++;
    }
  }
  if (VN < 1) { VN = 1; VLn[0][0] = 0; }
}
U0 VSave() {
  I64 k, m, off = 0;
  for (k = 0; k < VN; k++) {
    m = 0;
    while (VLn[k][m] && off < 16383) { VOut[off] = VLn[k][m]; off++; m++; }
    if (off < 16383) { VOut[off] = '\n'; off++; }
  }
  VOut[off] = 0;
  FileWrite(VFile, VOut, off);
  VDirty = 0;
}
U0 VDraw() {
  I64 r, i;
  if (VCy < VTop) VTop = VCy;
  if (VCy >= VTop + 20) VTop = VCy - 19;
  for (r = 0; r < 20; r++) {
    VGoto(r + 1, 1); VEsc("[K");
    i = VTop + r;
    if (i < VN) { "%s", &VLn[i][0]; } else PutCh('~');
  }
  VGoto(21, 1); VEsc("[7m");
  if (VMode) { "-- INSERT --"; } else { "-- NORMAL --"; }
  "  %s%s  Ln %d/%d Col %d ", VFile, VDirty ? "*" : "", VCy + 1, VN, VCx + 1;
  VEsc("[0m"); VEsc("[K");
  VGoto(VCy - VTop + 1, VCx + 1);
}
U0 VCmd() {   // ':' command line
  U8 cmd[64]; I64 i = 0, c, n;
  VGoto(21, 1); VEsc("[K"); PutCh(':');
  while (1) {
    c = VGet();
    if (c == '\r' || c == '\n') break;
    if ((c == 127 || c == 8) && i > 0) { i--; PutCh(8); PutCh(' '); PutCh(8); continue; }
    if (c == 27) return;
    if (i < 62 && c >= 32 && c < 127) { cmd[i] = c; i++; PutCh(c); }
  }
  cmd[i] = 0;
  if (cmd[0] == 'w' && cmd[1] == 0) VSave();
  else if (cmd[0] == 'w' && cmd[1] == 'q' && cmd[2] == 0) { VSave(); VQuit = 1; }
  else if (cmd[0] == 'x' && cmd[1] == 0) { VSave(); VQuit = 1; }
  else if (cmd[0] == 'q' && cmd[1] == 0) { if (!VDirty) VQuit = 1; }
  else if (cmd[0] == 'q' && cmd[1] == '!' && cmd[2] == 0) VQuit = 1;
  else if (cmd[0] == '!') { VGoto(22, 1); VEsc("[K"); Exec(&cmd[1]); "-- press a key --"; VGet(); }
  else if (cmd[0] >= '0' && cmd[0] <= '9') {
    n = 0; i = 0;
    while (cmd[i] >= '0' && cmd[i] <= '9') { n = n * 10 + cmd[i] - '0'; i++; }
    if (n >= 1 && n <= VN) { VCy = n - 1; VCx = 0; }
  }
}
U0 VInsert(I64 c) {   // INSERT-mode key
  I64 n, k;
  if (c == 27) { VMode = 0; n = VLen(VCy); if (VCx > n) VCx = n; if (VCx > 0) VCx--; return; }
  if (c == '\r' || c == '\n') {          // split the line at the cursor
    VInsL(VCy + 1);
    VSetL(VCy + 1, &VLn[VCy][VCx]);
    VLn[VCy][VCx] = 0;
    VCy++; VCx = 0; VDirty = 1; return;
  }
  if (c == 127 || c == 8) {
    if (VCx > 0) { n = VLen(VCy); for (k = VCx - 1; k < n; k++) VLn[VCy][k] = VLn[VCy][k + 1]; VCx--; VDirty = 1; }
    return;
  }
  if (c >= 32 && c < 127) {
    n = VLen(VCy);
    if (n < 126) { for (k = n + 1; k > VCx; k--) VLn[VCy][k] = VLn[VCy][k - 1]; VLn[VCy][VCx] = c; VCx++; VDirty = 1; }
  }
}
U0 Vi(U8 *name) {
  I64 c, n, pend = 0;
  I64 j = 0;
  while (name[j] && j < 63) { VFile[j] = name[j]; j++; } VFile[j] = 0;
  VLoad(name);
  VCy = 0; VCx = 0; VTop = 0; VMode = 0; VDirty = 0; VQuit = 0; VPush = 0;
  while (!VQuit) {
    VDraw();
    c = VKey();
    if (VMode) { VInsert(c); continue; }
    n = VLen(VCy);
    if (pend == 'd') { if (c == 'd') { VDelL(VCy); if (VCy >= VN) VCy = VN - 1; VCx = 0; VDirty = 1; } pend = 0; continue; }
    if (pend == 'g') { if (c == 'g') { VCy = 0; VCx = 0; } pend = 0; continue; }
    if (c == 'h') { if (VCx > 0) VCx--; }
    else if (c == 'l') { if (VCx < n - 1) VCx++; }
    else if (c == 'j') { if (VCy < VN - 1) { VCy++; n = VLen(VCy); if (VCx >= n && n > 0) VCx = n - 1; if (!n) VCx = 0; } }
    else if (c == 'k') { if (VCy > 0) { VCy--; n = VLen(VCy); if (VCx >= n && n > 0) VCx = n - 1; if (!n) VCx = 0; } }
    else if (c == '0') VCx = 0;
    else if (c == '$') { if (n > 0) VCx = n - 1; else VCx = 0; }
    else if (c == 'G') { VCy = VN - 1; VCx = 0; }
    else if (c == 'g') pend = 'g';
    else if (c == 'd') pend = 'd';
    else if (c == 'x') { if (n > 0) { I64 k; for (k = VCx; k < n; k++) VLn[VCy][k] = VLn[VCy][k + 1]; if (VCx >= n - 1 && VCx > 0) VCx--; VDirty = 1; } }
    else if (c == 'o') { VInsL(VCy + 1); VCy++; VCx = 0; VMode = 1; VDirty = 1; }
    else if (c == 'O') { VInsL(VCy); VCx = 0; VMode = 1; VDirty = 1; }
    else if (c == 'i') VMode = 1;
    else if (c == 'a') { if (n > 0 && VCx < n) VCx++; VMode = 1; }
    else if (c == 'A') { VCx = n; VMode = 1; }
    else if (c == 'I') { VCx = 0; VMode = 1; }
    else if (c == ':') VCmd();
  }
  VEsc("[2J"); VGoto(1, 1);
}
U0 Vim(U8 *name) { Vi(name); }

// Default editor: SetEd("Vi") or SetEd("Ed"); E("file") opens with whichever is set.
U8 EdDflt = 'E';
U0 SetEd(U8 *name) { EdDflt = name[0]; "default editor: %s\n", name; }
U0 E(U8 *f) { if (EdDflt == 'V' || EdDflt == 'v') Vi(f); else Ed(f); }
