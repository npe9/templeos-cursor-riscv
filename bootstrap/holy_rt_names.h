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
  X(RandU16, 0) X(RandI64, 0) X(Seed, 1) X(YorN, 0)
#endif
