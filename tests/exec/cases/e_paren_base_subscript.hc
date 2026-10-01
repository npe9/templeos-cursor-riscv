// Parenthesising an array base must not change what a subscript steps by.
//
//     U8 m[16];
//     (m)[1]        read EIGHT bytes from m+8, not one byte from m+1
//     (m)[1] = x    stored one byte AT m+8
//
// Both silent. The write is the dangerous half: on any U8 array shorter than 16 it is an
// out-of-bounds store with nothing to announce it, and it is reachable from ordinary C, because
// a function-like macro that indexes its argument produces exactly this shape --
//
//     #define OS_CPUSET_SET(cpu, p) (p)[(cpu) / 8] |= (1 << ((cpu) % 8))
//
// which is how this was found: OSAL's cpu-set macros, while translating cFE's task affinity
// module. With OS_MAX_CPUS == 1 the mask is one byte and the loop never reaches bit 8, so the
// configuration this port builds would not have shown it; a 16-core target would have.
//
// The cause: parenthesising the base threw away the container symbol, and with it the element
// size, so PtrElemInfo fell back to 8. The fix carries the element size across the parentheses
// in cc->expr_elem_size.
//
// NOT fixed, and deliberately not asserted here: the same shape where the element is a CLASS,
// `(&tbl[4])[2]` on a 16-byte record, still steps by 8 and lands one slot low. That is
// docs/HOLYC_STRUCT_LIMITS.md #4, which this file's mechanism explains but does not close.
U8 g_bytes[16];
U16 g_words[8];
I64 main()
{
  U8 m[32];
  I64 i;
  I64 r = 0;
  for (i = 0; i < 32; i++)
    m[i] = 0;
  for (i = 0; i < 16; i++)
    g_bytes[i] = i;
  for (i = 0; i < 8; i++)
    g_words[i] = i * 10;
  // READ through a parenthesised base: one byte, from the right place.
  r = r * 100 + (g_bytes)[1];
  // 1
  r = r * 100 + (g_bytes)[9];
  // 9
  // ...and the same for a two-byte element.
  r = r * 100 + (g_words)[2];
  // 20
  r = r * 100 + (g_words)[7];
  // 70
  // WRITE through a parenthesised base lands at the right index. Both of these used to land
  // eight times further along, inside the second half of this 32-byte local.
  (m)[1] = 0x22;
  (m)[3] |= 0x44;
  r = r * 100 + m[1];
  // 34
  r = r * 100 + m[3];
  // 68
  // ...and nothing was written at the index the broken scaling would have used.
  r = r * 10 + (m[8] == 0);
  // 1
  r = r * 10 + (m[24] == 0);
  // 1
  // A local pointer parenthesised the same way.
  
  {
    U8 *q = g_bytes;
    r = r * 100 + (q)[5];
    // 5
  }
  return r;
}
