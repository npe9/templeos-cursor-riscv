// `arr[i++]` on a glbl array with a glbl index: the post-increment write-back
// must land, and the load must use the pre-bump index.  This is the shape that
// soft-failed in the guest lexer (`g_toks[g_tok_i++]` read element 0 forever
// with `g_tok_i` left at 0).  Full form matrix: tests/exec/cases/e_arr_postinc_forms.hc.
I64 g_toks[4];
I64 g_tok_i;
I64 main()
{
  I64 r = 0;
  I64 t;
  I64 *p;
  g_toks[0] = 0x11;
  g_toks[1] = 0x22;
  g_toks[2] = 0x33;
  g_tok_i = 0;
  t = g_toks[g_tok_i++];
  r += (t == 0x11) * 1;
  r += (g_tok_i == 1) * 2;
  t = g_toks[g_tok_i++];
  r += (t == 0x22) * 4;
  r += (g_tok_i == 2) * 8;
  p = g_toks;
  t = *p++;
  r += (t == 0x11 && *p == 0x22) * 16;
  return r;
  // 0x1F
}
