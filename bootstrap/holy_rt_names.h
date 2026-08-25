/* HolyC runtime exported to compiled code. One list, three users: the AOT compiler declares
 * these as externs (calls go through import slots), the REPL registers the C entry points,
 * and the exec harness resolves the blob's import directory by name.  X(name, argc) */
#ifndef HOLY_RT_NAMES_H
#define HOLY_RT_NAMES_H
#define HOLY_RT_NAMES(X) \
  X(Print, 1) X(PutS, 1) X(PutChars, 1) \
  X(MAlloc, 1) X(CAlloc, 1) X(Free, 1) \
  X(StrLen, 1) X(StrCpy, 2) X(StrCmp, 2) X(StrCat, 2) X(StrNew, 1) \
  X(MemCpy, 3) X(MemSet, 3) X(MemCmp, 3) X(MemSetI64, 3) \
  X(AbsI64, 1) X(MaxI64, 2) X(MinI64, 2) X(ToUpper, 1) X(ToLower, 1) \
  X(RandU16, 0) X(RandI64, 0) X(Seed, 1) X(YorN, 0) X(tS, 0) X(D, 2) \
  X(Pow, 2) X(Sqrt, 1) X(Exp, 1) X(Ln, 1) X(Log10, 1) X(Log2, 1) \
  X(Floor, 1) X(Ceil, 1) X(Round, 1) X(Trunc, 1) X(Sin, 1) X(Cos, 1) X(Tan, 1) X(ATan, 1) \
  X(Abs, 1) X(Sign, 1)

/* F64 typing of the runtime (arguments and results travel as raw 64-bit patterns): the
 * compiler converts call arguments per the mask and types the result. */
static int holy_rt_streq(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }
static int HolyRtRetF64(const char *n) {
  static const char *f64[] = { "tS", "Pow", "Sqrt", "Exp", "Ln", "Log10", "Log2", "Floor", "Ceil", "Round", "Trunc", "Sin", "Cos", "Tan", "ATan", "Abs", 0 };
  for (int i = 0; f64[i]; i++) if (holy_rt_streq(n, f64[i])) return 1;
  return 0;
}
static unsigned HolyRtF64Mask(const char *n) {
  if (holy_rt_streq(n, "Pow")) return 3;
  static const char *one[] = { "Sqrt", "Exp", "Ln", "Log10", "Log2", "Floor", "Ceil", "Round", "Trunc", "Sin", "Cos", "Tan", "ATan", "Abs", "Sign", 0 };
  for (int i = 0; one[i]; i++) if (holy_rt_streq(n, one[i])) return 1;
  return 0;
}
#endif
