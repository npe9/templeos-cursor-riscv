// Guards `arr[i++]` and its siblings: every inc/dec form must keep the index
// write-back AND yield the pre-bump value.  A lost write-back looked like a
// LiteLexPlant `r=3` soft-fail (`g_toks[g_tok_i++]` read element 0 forever).
// Covers the five lowering sites: post-inc/dec, pre-inc/dec, `*p++` read,
// `*p++ = v`, and the plain deref that feeds an indexed load.
I64 g_toks[4];
I64 g_tok_i;
class CBuf
{
  I64 v[4];
  I64 i;
};

I64 main()
{
  I64 r = 0;
  I64 t;
  I64 s;
  I64 a[4];
  I64 *p;
  U8 b[4];
  CBuf c;
  // 1) glbl array indexed by a glbl post-increment (the LiteLexPlant shape)
  g_toks[0] = 44;
  g_toks[1] = 77;
  g_toks[2] = 99;
  g_tok_i = 0;
  t = g_toks[g_tok_i++];
  r += (t == 44 && g_tok_i == 1) * 1;
  t = g_toks[g_tok_i++];
  r += (t == 77 && g_tok_i == 2) * 2;
  // 2) scalar glbl post-inc / post-dec
  g_tok_i = 5;
  t = g_tok_i++;
  r += (t == 5 && g_tok_i == 6) * 4;
  t = g_tok_i--;
  r += (t == 6 && g_tok_i == 5) * 8;
  // 3) pre-inc / pre-dec
  r += (++g_tok_i == 6) * 16;
  r += (--g_tok_i == 5 && g_tok_i == 5) * 32;
  // 4) `*p++` read (deref post-inc)
  a[0] = 1;
  a[1] = 2;
  a[2] = 3;
  a[3] = 4;
  p = a;
  s = *p++;
  s += *p++;
  r += (s == 3 && *p == 3) * 64;
  // 5) `*p++ = v` (assign post-inc)
  p = a;
  *p++ = 7;
  *p++ = 9;
  r += (a[0] == 7 && a[1] == 9 && *p == 3) * 128;
  // 6) U8 array indexed by a local post-increment (narrow store-thru path)
  b[0] = 0x11;
  b[1] = 0x22;
  t = 0;
  s = b[t++];
  r += (s == 0x11 && t == 1) * 256;
  s = b[t++];
  r += (s == 0x22 && t == 2) * 512;
  // 7) class member array indexed by a member post-increment
  c.v[0] = 21;
  c.v[1] = 31;
  c.i = 0;
  t = c.v[c.i++];
  r += (t == 21 && c.i == 1) * 1024;
  t = c.v[c.i++];
  r += (t == 31 && c.i == 2) * 2048;
  return r;
  // 0xFFF
}
