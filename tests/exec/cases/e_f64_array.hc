// F64 array elements carry their type (a[i] stays F64, not raw bits) — for `a[i]*2.0`, `ToI64(a[i])`.
F64 g100(){ return 100.0; }
I64 main(){
  F64 a[4]; a[0]=3.5; a[1]=2.5; a[2]=g100();
  F64 x=7.5; a[3]=x;
  return (ToI64(a[0]*2.0)==7)*1 + (ToI64(a[1]*2.0)==5)*2 + (ToI64(a[2])==100)*4 +
         (ToI64(a[3])==7)*8 + ((a[0]+a[1])==6.0)*16 + (a[2]>99.0)*32;   // 0x3f
}
