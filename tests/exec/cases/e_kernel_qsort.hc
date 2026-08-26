// Runs the real TempleOS kernel's QSort (Kernel/QSort.HC) with a function-pointer comparator to
// sort 6 ints ascending — exercises kernel recursion, pointer arithmetic, and indirect calls.
// (The comparator must not be named `cmp`: the kernel has a global `cmp` of that name.)
#include "/Kernel/Kernel_RV.PRJ"
I64 QSortIntCmp(I64 *a, I64 *b) { return *a - *b; }
I64 main()
{
  I64 v[6];
  v[0]=5; v[1]=2; v[2]=8; v[3]=1; v[4]=9; v[5]=3;
  QSort(v, 6, sizeof(I64), &QSortIntCmp);
  return (v[0]==1)*1 + (v[1]==2)*2 + (v[2]==3)*4 + (v[3]==5)*8 + (v[4]==8)*16 + (v[5]==9)*32;
}
