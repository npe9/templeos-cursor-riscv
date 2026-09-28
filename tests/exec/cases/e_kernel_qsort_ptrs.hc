// QSort over an array of POINTERS, with its width taken from sizeof(<class> *) — the shape that
// made Sort() trap.
//
// Adam/Opt/Utils/StrUtils.HC sorts doc entries with
//   QSort(a, cnt/entry_lines, entry_lines*sizeof(CDocEntry *), &DEPtrCompare)
// and sizeof(CDocEntry *) answered 208 (the class size) instead of 8, so QSort took its width!=8
// branch, MemCpy'd a "pivot" from far past the array, and DEPtrCompare dereferenced garbage
// (mcause=5, mtval=0x10). The tier-1 demo agent found it; e_sizeof_class_ptr.hc pins the sizeof
// itself, and this pins the consequence: three pointers to a 208-byte class, sorted by a
// comparator that dereferences them exactly as DEPtrCompare does. Expect 0xf.
#include "/Kernel/Kernel_RV.PRJ"
class CEnt { U8 pad[200]; U8 *tag; };
I64 EntCompare(CEnt **e1, CEnt **e2)
{
  return StrCmp((*e1)->tag, (*e2)->tag);
}
I64 main()
{
  CEnt a, b, c;
  CEnt *arr[3];
  I64 r = 0;
  a.tag = "c";
  b.tag = "a";
  c.tag = "b";
  arr[0] = &a;
  arr[1] = &b;
  arr[2] = &c;
  QSort(arr, 3, sizeof(CEnt *), &EntCompare);
  if (arr[0] == &b) r |= 1;
  if (arr[1] == &c) r |= 2;
  if (arr[2] == &a) r |= 4;
  if (sizeof(CEnt *) == 8) r |= 8;
  return r;
}
