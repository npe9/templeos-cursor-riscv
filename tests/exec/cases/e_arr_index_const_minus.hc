// A CLASS-MEMBER ARRAY INDEXED BY A CONSTANT EXPRESSION must address the element the
// expression names. `g.inner[8 - 1]` did not: it resolved to base + 8*12 - 12*12, which is
// 48 bytes BEFORE the array rather than 84 bytes into it.
//
// The cause was pointer-arithmetic scaling leaking into the index. ParseAdd asks PtrElemInfo
// about its left operand, an integer literal sets none of the pointer-tracking state, and the
// subscript path had not cleared what the BASE left there -- so `8` looked like a pointer to a
// 12-byte element, the `1` was scaled by 12, and the subscript scaled the result by 12 again.
//
// Found on cFS's CFE_TBL_Global, where `Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1]` landed
// 117,320 bytes before the object: a wild store into whatever global preceded it. A bare
// literal index and a VARIABLE index were both always right, which is why the three forms are
// all measured here side by side -- only the constant expression was wrong.
class E12
{
  U8 b[12];
};

class Big
{
  I64 head;
  E12 inner[8];
  I64 tail;
};
Big g_big;
E12 g_arr[8];
class Holder
{
  U16 *p;
};
Holder g_h;
U16 g_words[8];
I64 main()
{
  I64 r = 0, n;
  // top-level array, for contrast: all four index forms are right
  r += ((U8 *) & g_arr[7] - (U8 *) & g_arr[0] == 84) * 1;
  r += ((U8 *) & g_arr[8 - 1] - (U8 *) & g_arr[0] == 84) * 2;
  // the same four on an array that is a CLASS MEMBER
  r += ((U8 *) & g_big.inner[7] - (U8 *) & g_big == 92) * 4;
  r += ((U8 *) & g_big.inner[8 - 1] - (U8 *) & g_big == 92) * 8;
  n = 7;
  r += ((U8 *) & g_big.inner[n] - (U8 *) & g_big == 92) * 16;
  n = 8;
  r += ((U8 *) & g_big.inner[n - 1] - (U8 *) & g_big == 92) * 32;
  // index 0 and 1, to see where it starts going wrong
  r += ((U8 *) & g_big.inner[0] - (U8 *) & g_big == 8) * 64;
  r += ((U8 *) & g_big.inner[1] - (U8 *) & g_big == 20) * 128;
  // and a store through the member-array form
  g_big.inner[8 - 1].b[0] = 'A';
  r += (g_big.inner[7].b[0] == 'A') * 256;
  // THE OTHER DIRECTION AND THE OTHER ARM: `CONST + variable` through a POINTER member, which
  // is DskDrv.HC's `bd->dev_id_record[10 + i]` on a `U16 *`. PtrElemInfo reaches a pointer
  // member through `m->pointed_to_type`, a different branch from the array member above, and
  // the scale came out 2 -- so the ATA identify record was read at words 10, 12, 14 instead of
  // 10, 11, 12 and both DrvSerialNum and DrvModelNum returned half a string.
  g_words[3] = 0x1234;
  g_words[4] = 0x5678;
  g_h.p = g_words;
  n = 1;
  r += (g_h.p[2 + n] == 0x1234) * 512;
  r += (g_h.p[1 + 2] == 0x1234) * 1024;
  g_h.p[3 + n] = 0xBEEF;
  r += (g_words[4] == 0xBEEF) * 2048;
  return r;
  // 0xFFF
}
