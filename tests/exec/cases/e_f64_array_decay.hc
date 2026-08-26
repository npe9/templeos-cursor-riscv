// An F64-element array decays to its address (an integer), across ALL access forms: a bare global
// array, a class member array, a subscripted row of a 2-D array, and a dereffed F64**. None may be
// typed F64, or the address is mangled when passed as an argument / a following `+ int` gets
// pointer-scaled (the call result is the callee's return type, not the argument's).
class C { F64 v[2]; };
F64 gg[2];
I64 chk(I64 *p){ return p>0x1000; }
I64 main(){
  C s; F64 m[2][2]; F64 *q; F64 **pp=&q; q=gg;
  gg[0]=1.5; s.v[0]=2.5; m[0][0]=3.5;
  return chk(gg)*1 + chk(s.v)*2 + chk(m[0])*4 + chk(*pp)*8   // each address valid → 0xf
       + (chk(s.v)+15==16)*16                                // no pointer-scaling on `call + int`
       + (chk(s.v)*2+chk(m[0])*4==6)*32;                     // 0x3f
}
