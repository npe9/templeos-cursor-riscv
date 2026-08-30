// A pointer cast on a deref lvalue sets the access WIDTH regardless of the pointer's own type:
// `*(U32 *)b = v` stores 4 bytes even though b is U8 *. The bug: the deref-type chain consulted
// the variable's pointee first, so the store width came from U8 (1 byte) and the cast was ignored
// -- poking instruction words through a U8 * buffer wrote only the low byte.
U8 gbuf[16];
U8 *gp;
I64 main(){
  I64 i; U8 b[16]; U8 *p;
  for (i=0;i<16;i++) b[i]=0xEE;
  p = b;
  *(U32 *)p = 0x00050663;                     // 4-byte store through a cast U8* local
  gp = gbuf; for (i=0;i<16;i++) gbuf[i]=0xDD;
  *(U32 *)gp = 0x00100513;                    // same through a global U8*
  *(U16 *)(p+8) = 0x8067;                     // 2-byte store at an offset
  return (b[0]==0x63)*1 + (b[1]==0x06)*2 + (b[3]==0x00)*4 + (b[4]==0xEE)*8    // 4 bytes, not 1 or 8
       + (gbuf[0]==0x13)*16 + (gbuf[2]==0x10)*32 + (gbuf[4]==0xDD)*64
       + (b[8]==0x67)*128 + (b[9]==0x80)*256 + (b[10]==0xEE)*512
       + (*(U32 *)p==0x00050663)*1024;        // 4-byte load back through the cast
}
