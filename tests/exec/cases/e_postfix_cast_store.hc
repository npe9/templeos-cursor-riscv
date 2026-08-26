// A postfix cast on a deref lvalue sets the access WIDTH: `b[i](I64)` is *(I64*)&b[i] — an 8-byte
// store/load, not b[i]'s declared U8. The kernel's StrPrint %c relies on this: `tmp_buf[0](I64)=ch`
// must overwrite all 8 bytes so a prior specifier's digits don't trail the character.
I64 main(){
  U8 b[16]; I64 i;
  for (i=0;i<16;i++) b[i]=0xFF;              // poison
  b[0](I64)=0x0000000000000041;              // 8-byte store: b[0]=0x41, b[1..7]=0
  U8 c[16]; for (i=0;i<16;i++) c[i]=0xEE;
  c[4](I64)=0x1122334455667788;              // 8-byte store at a nonzero index
  return (b[0]==0x41)*1 + (b[1]==0)*2 + (b[7]==0)*4
       + (c[4]==0x88)*8 + (c[11]==0x11)*16 + (c[12]==0xEE)*32   // c[12] untouched
       + (b[0](I64)==0x41)*64;               // 8-byte load reads the wide value back
}
