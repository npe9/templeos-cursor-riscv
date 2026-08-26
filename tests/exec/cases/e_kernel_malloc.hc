// Runs the real TempleOS kernel heap: MAlloc, MSize, Free (Mem/MAllocFree.HC via the runtime).
#include "/Kernel/Kernel_RV.PRJ"
I64 main(){
  U8 *p=MAlloc(100,NULL), *q=MAlloc(200,NULL);
  I64 s1=MSize(p), s2=MSize(q);
  p[0]=42; p[99]=7;
  Free(p);
  return (s1>=100)*1 + (s2>=200)*2 + (p[0]==42)*4;   // 7
}
