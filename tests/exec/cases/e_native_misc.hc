// Verifies native RISC-V ToUpper/AbsI64/MaxI64/ClampI64/SqrI64/SwapI64/StrICmp in KUtilsRV.HC.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 x=7,y=9,r=0;
  r += (ToUpper('a')=='A')*1;
  r += (ToUpper('Z')=='Z')*2;         // non-lowercase unchanged
  r += (AbsI64(-5)==5)*4;
  r += (MaxI64(7,9)==9)*8;
  r += (ClampI64(20,0,10)==10)*16;    // above hi
  r += (ClampI64(-3,0,10)==0)*32;     // below lo
  r += (SqrI64(6)==36)*64;
  SwapI64(&x,&y);
  r += (x==9 && y==7)*128;
  r += (StrICmp("Hello","hello")==0)*256;
  r += (StrICmp("abc","abd")<0)*512;
  return r;                           // all = 0x3FF
}
