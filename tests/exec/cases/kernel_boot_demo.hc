// Bring up the portable RISC-V kernel environment with RVKernelInit() (Kernel/KBootRV.HC), then use
// the kernel's OWN Print — including %f float formatting (needs the pow10 table) and reads of the
// kernel's bit tables — routed to the UART through the native keydev console. Proves the boot-init
// wires a working environment end to end.
#include "/Kernel/Kernel_RV.PRJ"
I64 main(){
  RVKernelInit();
  Print("RISC-V TempleOS init OK\n");
  Print("floats: pi=%5.4f  sqrt2=%5.4f  1e3=%3.1f\n", 3.14159265, 1.41421356, 1000.0);
  Print("bits: rev(0x01)=0x%02X  popcount(0xFF)=%d\n", rev_bits_table[1], set_bits_table[255]);
  return 0;
}
