// A string literal is a U8 * value: subscripts and pointer arithmetic on it read bytes.
//
// The postfix pass cleared the expression's pointer typing after every primary except a
// pointer-returning call, so "abc"[i] fell to the I64/8 default: index scaled by 8 and an 8-byte
// load (a hex-digit table printed 't'). Only the pointer-variable form worked (0x4); want 0xf.
I64 main() {
  I64 r = 0, i = 1;
  U8 *p = "abcdef";
  if ("abcdef"[1] == 'b') r |= 1;      // constant index into a literal
  if ("abcdef"[i] == 'b') r |= 2;      // variable index into a literal
  if (p[i] == 'b')        r |= 4;      // same through a pointer (control)
  if (*("abcdef" + 2) == 'c') r |= 8;  // pointer arithmetic on a literal
  return r;
}
