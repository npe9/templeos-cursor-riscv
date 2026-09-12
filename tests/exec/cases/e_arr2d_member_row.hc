// Partial subscript of a 2-D array MEMBER must yield the row address, not a load.
// Regression: RVWinMgr's `StrPrint(rv_winmgr.wallpaper_tasks[n], ...)` where the member
// is `U8 wallpaper_tasks[4][96]` passed 0, so StrPrint(NULL,...) made StrPrintJoin MAlloc
// a buffer nobody freed — ~109 bytes leaked per Print, draining the 64 MB arena in ~90 s
// until MAlloc returned NULL and SPutChar's unchecked MemCpy(NULL,..) faulted.
class Rows
{
  I64 pad0;
  U8  rows[4][96];
  I64 pad1;
};

Rows g_r;
U8 g_flat[4][96];

I64 main()
{
  I64 r = 0, n;
  U8 *p;

  // Member of a class: row address, spaced by the row size.
  p = g_r.rows[0];
  r += (p == &g_r.rows[0][0]) * 1;
  p = g_r.rows[2];
  r += (p - g_r.rows[0] == 192) * 2;
  r += (p != NULL) * 4;

  // Plain global 2-D array: same rule.
  p = g_flat[3];
  r += (p - g_flat[0] == 288) * 8;

  // The row address must be writable and readable back.
  g_r.rows[2][0] = 'A';
  g_r.rows[2][1] = 0;
  p = g_r.rows[2];
  r += (*p == 'A') * 16;

  // A variable index, the shape the wallpaper code actually uses.
  n = 1;
  p = g_r.rows[n];
  r += (p - g_r.rows[0] == 96) * 32;

  return r;
  // 0x3F
}
