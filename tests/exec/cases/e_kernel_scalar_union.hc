// In the kernel, the fixed-width integer types are scalar-typed UNIONS (`U16i union U16 {…}`,
// `U32i union U32`, …), so a `U16`/`U32` field or array records raw_type=I64 with a sub-word size.
// Element/member access must use the SIZE for the load/store width, or `tbl[i]` reads 8 bytes
// (pulling in neighbors) and `s.field=x` on a 4-byte tail field overruns the struct.
#include "/Kernel/Kernel_RV.PRJ"
I64 main(){
  // U16 union array (kernel date table): each element is 2 bytes
  I64 arr = (mon_start_days1[7]==212) & (mon_start_days1[1]==31) & (mon_start_days2[11]==335);
  // U32 union array (kernel char bitmap): 4-byte elements
  I64 u32 = (char_bmp_dec_numeric[1]==0x03FF0000);
  // CDate is `I64 class { U32 time; I32 date; }` — U32/I32 union members, r/w round-trip
  CDateStruct ds; MemSet(&ds,0,sizeof(CDateStruct));
  ds.year=2026; ds.mon=8; ds.day_of_mon=26; ds.hour=12; ds.min=30;
  CDate d=Struct2Date(&ds);
  CDateStruct o; MemSet(&o,0,sizeof(CDateStruct)); Date2Struct(&o,d);
  I64 rt = (o.year==2026) & (o.mon==8) & (o.day_of_mon==26) & (o.hour==12) & (o.min==30);
  return arr*1 + u32*2 + rt*4;   // 7
}
