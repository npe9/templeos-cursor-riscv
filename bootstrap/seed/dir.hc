// dir.hc -- Dir() in HolyC, cwd-aware: lists the current directory (see Cd/Pwd), collapsing
// subdirectories to a single "name/" line and hiding dotfiles (.dir markers, .dirlist). Redefines
// the C built-in, so the listing is itself editable: Src("Dir") brings this up.
//
// DirWrite() dumps the same names into ".dirlist" so an editor can treat the listing as a DolDoc:
// put the cursor on a name and Enter (Vi NORMAL / Edit on this file / ^G) to Cd or open it.
//
// Keep per-function locals few: the JIT frame spills only a handful, so a long Dir() with 11
// locals lost `cl` across Print and hung in `while (k < cl && ...)`.
U8 DirFlat[1024];
// 16 names * 64; 1-D (multi-dim row decay is a separate codegen hazard)
U8 DirBuf[2048];
I64 DirLen;
I64 DirNs;
U8 JumpIdent[64];
// identifier for gd/^] -- global so VLoad/EvLoad cant clobber it
U8 JumpFile[64];
// originating filename, filled by SrcFile then loaded by the editor loop
// WordAt -- WordAt(line,col,out)
// NAME
//   WordAt - copy the whitespace-delimited word under col into out.
// SYNOPSIS
//   WordAt(line,col,out)
// DESCRIPTION
//   copy the whitespace-delimited word under col into out.
// INPUTS
//   line - argument
//   col - argument
//   out - argument
// OUTPUTS
//   copy the whitespace-delimited word under col into out.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 WordAt(U8 *line, I64 col, U8 *out)
{
  I64 i = col, j = 0;
  if (i < 0)
    i = 0;
  while (i > 0 && line[i] && line[i] != ' ' && line[i] != 0x09)
    i--;
  if (line[i] == ' ' || line[i] == 0x09)
    i++;
  while (line[i] == ' ' || line[i] == 0x09)
    i++;
  while (line[i] && line[i] != ' ' && line[i] != 0x09 && j < 63) {
    out[j] = line[i];
    j++;
    i++;
  }
  out[j] = 0;
}
// IdentChar -- IdentChar(c)
// NAME
//   IdentChar - nonzero if c is an identifier character.
// SYNOPSIS
//   IdentChar(c)
// DESCRIPTION
//   nonzero if c is an identifier character.
// INPUTS
//   c - argument
// OUTPUTS
//   nonzero if c is an identifier character.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 IdentChar(I64 c)
{
  if (c >= 'A' && c <= 'Z')
    return 1;
  if (c >= 'a' && c <= 'z')
    return 1;
  if (c >= '0' && c <= '9')
    return 1;
  if (c == '_')
    return 1;
  return 0;
}
// WordIdent -- WordIdent(line,col,out)
// NAME
//   WordIdent - copy the C identifier under col into out.
// SYNOPSIS
//   WordIdent(line,col,out)
// DESCRIPTION
//   copy the C identifier under col into out.
// INPUTS
//   line - argument
//   col - argument
//   out - argument
// OUTPUTS
//   copy the C identifier under col into out.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 WordIdent(U8 *line, I64 col, U8 *out)
{
  I64 i = col, j = 0;
  if (i < 0)
    i = 0;
  if (i > 127)
    i = 127;
  while (i > 0 && !IdentChar(line[i]))
    i--;
  while (i > 0 && IdentChar(line[i - 1]))
    i--;
  while (i < 128 && IdentChar(line[i]) && j < 63) {
    out[j] = line[i];
    j++;
    i++;
  }
  out[j] = 0;
}
// IdentAt -- IdentAt(line,name)
// NAME
//   IdentAt - column of name as a whole-word ident, or -1.
// SYNOPSIS
//   IdentAt(line,name)
// DESCRIPTION
//   column of name as a whole-word ident, or -1.
// INPUTS
//   line - argument
//   name - argument
// OUTPUTS
//   column of name as a whole-word ident, or -1.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 IdentAt(U8 *line, U8 *name)
{
  I64 i, j, start;
  start = 0;
  while (start < 128 && line[start]) {
    i = start;
    j = 0;
    while (i < 128 && name[j] && line[i] == name[j]) {
      i++;
      j++;
    }
    if (!name[j] && j > 0) {
      if (i >= 128 || !IdentChar(line[i])) {
        if (start == 0 || !IdentChar(line[start - 1]))
          return start;
      }
    }
    start++;
  }
  return -1;
}
// DefAt -- DefAt(line,name)
// NAME
//   DefAt - column of name if it looks like a function def, or -1.
// SYNOPSIS
//   DefAt(line,name)
// DESCRIPTION
//   column of name if it looks like a function def, or -1.
// INPUTS
//   line - argument
//   name - argument
// OUTPUTS
//   column of name if it looks like a function def, or -1.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 DefAt(U8 *line, U8 *name)
{
  I64 i, k;
  i = IdentAt(line, name);
  if (i < 0)
    return -1;
  k = i;
  while (k < 128 && IdentChar(line[k]))
    k++;
  while (k < 128 && (line[k] == ' ' || line[k] == 9))
    k++;
  if (k < 128 && line[k] == '(')
    return i;
  return -1;
}
// LinkKind -- LinkKind(name,out)
// NAME
//   LinkKind - classify name: 0 none, 1 dir, 2 file; fills out.
// SYNOPSIS
//   LinkKind(name,out)
// DESCRIPTION
//   classify name: 0 none, 1 dir, 2 file; fills out.
// INPUTS
//   name - argument
//   out - argument
// OUTPUTS
//   classify name: 0 none, 1 dir, 2 file; fills out.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 LinkKind(U8 *name, U8 *out)
{
  I64 n = 0;
  if (!name) {
    out[0] = 0;
    return 0;
  }
  while (name[n] && n < 63) {
    out[n] = name[n];
    n++;
  }
  out[n] = 0;
  if (n && out[n - 1] == 47) {
    n--;
    out[n] = 0;
  }
  if (!out[0])
    return 0;
  if (out[0] == '.' && !out[1])
    return 0;
  if (out[0] == '.' && out[1] == '.' && !out[2])
    return 1;
  if (IsDir(out))
    return 1;
  if (FileLen(out) >= 0)
    return 2;
  return 0;
}
// LinkCd -- LinkCd(name)
// NAME
//   LinkCd - Cd into name (DolDoc link helper).
// SYNOPSIS
//   LinkCd(name)
// DESCRIPTION
//   Cd into name (DolDoc link helper).
// INPUTS
//   name - argument
// OUTPUTS
//   Cd into name (DolDoc link helper).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 LinkCd(U8 *name)
{
  Cd(name);
}
// DirPut -- DirPut(s)
// NAME
//   DirPut - append s into DirBuf for DirWrite.
// SYNOPSIS
//   DirPut(s)
// DESCRIPTION
//   append s into DirBuf for DirWrite.
// INPUTS
//   s - argument
// OUTPUTS
//   append s into DirBuf for DirWrite.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DirPut(U8 *s)
{
  I64 i = 0;
  while (s[i] && DirLen < 2047) {
    DirBuf[DirLen] = s[i];
    DirLen++;
    i++;
  }
}
// DirSeen -- DirSeen(rest,L)
// NAME
//   DirSeen - nonzero if rest[0..L) was already noted.
// SYNOPSIS
//   DirSeen(rest,L)
// DESCRIPTION
//   nonzero if rest[0..L) was already noted.
// INPUTS
//   rest - argument
//   L - argument
// OUTPUTS
//   nonzero if rest[0..L) was already noted.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 DirSeen(U8 *rest, I64 L)
{
  I64 d, c2, off;
  for (d = 0; d < DirNs; d++) {
    off = d * 64;
    c2 = 0;
    while (c2 < L && DirFlat[off + c2] == rest[c2])
      c2++;
    if (c2 == L && !DirFlat[off + c2])
      return 1;
  }
  return 0;
}
// DirNote -- DirNote(rest,L)
// NAME
//   DirNote - record a subdirectory name for Dir listing.
// SYNOPSIS
//   DirNote(rest,L)
// DESCRIPTION
//   record a subdirectory name for Dir listing.
// INPUTS
//   rest - argument
//   L - argument
// OUTPUTS
//   record a subdirectory name for Dir listing.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DirNote(U8 *rest, I64 L)
{
  I64 c2, off;
  if (DirNs >= 16)
    return;
  off = DirNs * 64;
  for (c2 = 0; c2 < L; c2++)
    DirFlat[off + c2] = rest[c2];
  DirFlat[off + L] = 0;
  DirNs++;
}
// DirUnder -- DirUnder(nm)
// NAME
//   DirUnder - nonzero if nm is under the current cwd.
// SYNOPSIS
//   DirUnder(nm)
// DESCRIPTION
//   nonzero if nm is under the current cwd.
// INPUTS
//   nm - argument
// OUTPUTS
//   nonzero if nm is under the current cwd.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 DirUnder(U8 *nm)
{
  U8 *cwd;
  I64 cl, k;
  cwd = CwdStr();
  cl = 0;
  while (cwd[cl])
    cl++;
  k = 0;
  while (k < cl && nm[k] == cwd[k])
    k++;
  return k == cl;
}
// CwdLen -- CwdLen()
// NAME
//   CwdLen - strlen(CwdStr()).
// SYNOPSIS
//   CwdLen()
// DESCRIPTION
//   strlen(CwdStr()).
// INPUTS
//   none
// OUTPUTS
//   strlen(CwdStr()).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 CwdLen()
{
  U8 *c;
  I64 n;
  c = CwdStr();
  n = 0;
  while (c[n])
    n++;
  return n;
}
// SlashLen -- SlashLen(s)
// NAME
//   SlashLen - length of nm up to the first /.
// SYNOPSIS
//   SlashLen(s)
// DESCRIPTION
//   length of nm up to the first /.
// INPUTS
//   s - argument
// OUTPUTS
//   length of nm up to the first /.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 SlashLen(U8 *s)
{
  I64 n;
  n = 0;
  while (n < 64 && s[n] && s[n] != 47)
    n++;
  return n;
}
// DirOne -- DirOne(i)
// NAME
//   DirOne - print one FileName(i) entry for Dir().
// SYNOPSIS
//   DirOne(i)
// DESCRIPTION
//   print one FileName(i) entry for Dir().
// INPUTS
//   i - argument
// OUTPUTS
//   print one FileName(i) entry for Dir().
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DirOne(I64 i)
{
  U8 *nm, *rest;
  I64 L, c2;
  nm = FileName(i);
  if (!nm || !DirUnder(nm))
    return;
  rest = nm + CwdLen();
  L = SlashLen(rest);
  if (rest[L] == 47) {
    if (!DirSeen(rest, L)) {
      DirNote(rest, L);
      " ";
      for (c2 = 0; c2 < L; c2++)
        PutCh(rest[c2]);
      "/\n";
    }
    return;
  }
  if (rest[0] == '.')
    return;
  "  %s  %d bytes\n", rest, FileSize(i);
}
// DirWOne -- DirWOne(i)
// NAME
//   DirWOne - append one entry into DirBuf for DirWrite.
// SYNOPSIS
//   DirWOne(i)
// DESCRIPTION
//   append one entry into DirBuf for DirWrite.
// INPUTS
//   i - argument
// OUTPUTS
//   append one entry into DirBuf for DirWrite.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DirWOne(I64 i)
{
  U8 *nm, *rest;
  I64 L, c2;
  nm = FileName(i);
  if (!nm || !DirUnder(nm))
    return;
  rest = nm + CwdLen();
  if (rest[0] == '.')
    return;
  L = SlashLen(rest);
  if (rest[L] == 47) {
    if (!DirSeen(rest, L)) {
      DirNote(rest, L);
      for (c2 = 0; c2 < L && DirLen < 2047; c2++) {
        DirBuf[DirLen] = rest[c2];
        DirLen++;
      }
      DirPut("/\n");
    }
    return;
  }
  DirPut(rest);
  DirPut("\n");
}
// DirWrite -- DirWrite()
// NAME
//   DirWrite - write cwd listing into .dirlist for DirEd.
// SYNOPSIS
//   DirWrite()
// DESCRIPTION
//   write cwd listing into .dirlist for DirEd.
// INPUTS
//   none
// OUTPUTS
//   write cwd listing into .dirlist for DirEd.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DirWrite()
{
  I64 i, n;
  DirLen = 0;
  DirNs = 0;
  if (CwdLen())
    DirPut("../\n");
  n = FileCount();
  for (i = 0; i < n; i++)
    DirWOne(i);
  DirBuf[DirLen] = 0;
  FileWrite(".dirlist", DirBuf, DirLen);
}
// Dir -- Dir()
// NAME
//   Dir - cwd-aware directory listing
// SYNOPSIS
//   U0 Dir();
// DESCRIPTION
//   Lists the current working directory on the UART (TempleOS Dir, memfs port). Prints
//   "/cwd", optional "../", subdirectory names as "name/", and files with sizes. Hides
//   dotfiles (.dir markers, .dirlist). Redefines the C Dir builtin -- Src("Dir") edits
//   this HolyC. DirWrite dumps the same names into ".dirlist" for DirEd / Activate.
// INPUTS
//   none (uses CwdStr / FileCount / FileName)
// OUTPUTS
//   none (listing on UART)
// BUGS
//   Max 16 subdirectory names tracked (DirFlat). Not a recursive tree. Keep locals few
//   in helpers -- JIT frame spills are limited (long Dir bodies have hung across Print).
//   Stock TempleOS Dir has flags / DolDoc links; here links are Activate/DirEd convention.
U0 Dir()
{
  I64 i, n;
  " /%s\n", CwdStr();
  if (CwdLen()) {
    " ../\n";
  }
  DirNs = 0;
  n = FileCount();
  for (i = 0; i < n; i++)
    DirOne(i);
}
// Ls -- Ls()
// NAME
//   Ls - alias of Dir()
// SYNOPSIS
//   U0 Ls();
// DESCRIPTION
//   Same as Dir(); Unix-familiar name for the cwd listing.
// INPUTS
//   none
// OUTPUTS
//   none (UART listing)
// BUGS
//   Same limitations as Dir.
U0 Ls()
{
  Dir;
}
