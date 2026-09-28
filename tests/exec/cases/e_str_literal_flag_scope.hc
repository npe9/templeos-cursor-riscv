// The string-literal pointer flag must not outlive its own primary.
//
// `str_lit_just_loaded` tells ParsePostfix to keep a literal's U8 * typing (so `"abc"[i]` reads a
// byte). A flag like that is exactly the hazard the auto-deref comments in ParsePostfix already
// document for `var_just_loaded`: if it survived into the NEXT operand, `arr[1]` in the same
// expression would be typed U8/1 and read one byte of an I64. It is cleared at the top of every
// ParsePrimary, and this case is the proof: literals and named bases mixed in single expressions,
// a literal used as a plain value, and two literals in one expression. Expect 0x3f.
I64 main() {
  I64 r = 0, arr[4], x;
  U8 *p = "abcdef";
  arr[1] = 0x1111222233334444;
  if ("xy"[0] == 'x' && arr[1] == 0x1111222233334444) r |= 1;   // stale flag => arr[1] typed U8/1
  if (p[1] == 'b' && arr[1] == 0x1111222233334444)    r |= 2;
  x = "abc";                                                    // literal as a plain value
  if (arr[1] == 0x1111222233334444)                   r |= 4;   // still intact after that
  if (*"Q" == 'Q')                                    r |= 8;   // deref of a literal
  if ("ab"[1] == 'b' && "cd"[1] == 'd')               r |= 16;  // two literals in one expression
  if (x && arr[1] == 0x1111222233334444)              r |= 32;
  return r;
}
