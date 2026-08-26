// The kernel's %X formatting (StrPrint.HC `tmp_buf[k]= m&15 +'0'`) relies on HolyC precedence.
#include "/Kernel/Kernel_RV.PRJ"
I64 main(){ U8 b[32]; StrPrint(b,"%08X",0xDEAD);
  return (b[0]=='0')*1+(b[4]=='D')*2+(b[5]=='E')*4+(b[6]=='A')*8+(b[7]=='D')*16+(StrLen(b)==8)*32; }
