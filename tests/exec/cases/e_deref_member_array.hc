// `*p->name` on a MEMBER array must load one element, not 8 bytes.
//
// The 2026-08-27 fix covered `*arr` for LOCAL arrays only. Through a member the deref fell to
// RT_I64, so RedSeaFilesFind's `*tmpde->name!='.'` read ".." as 0x2e2e, took the recurse branch
// for the parent entry, and every FilesFind(FUF_RECURSE) recursed into its own parent until the
// heap died (DirNameAbs mtval=0x70 / MAlloc+0x168 were the symptoms). Expect 0x3b; 0x3c before.
class CEnt { U8 name[8]; I64 tail; };
I64 main() {
  CEnt c;
  CEnt *p = &c;
  I64 r = 0;
  c.name[0] = '.'; c.name[1] = '.'; c.name[2] = 0; c.tail = 0x7777;
  if (*c.name == '.')  r |= 1;      // direct member array deref
  if (*p->name == '.') r |= 2;      // through a pointer
  if (*p->name != '.') r |= 4;      // the RedSeaFilesFind shape (must NOT set)
  c.name[1] = 0;
  if (*p->name == '.') r |= 8;      // "." reads as '.' either way
  *p->name = 'X';                   // deref STORE into a member array
  if (c.name[1] == 0 && c.tail == 0x7777) r |= 16;   // neighbours intact
  if (c.name[0] == 'X') r |= 32;
  return r;
}
