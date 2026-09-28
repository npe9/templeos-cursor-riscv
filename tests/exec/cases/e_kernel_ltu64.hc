// LtU64: unsigned order, the asm stepper's bltu/bgeu. -1 is the largest unsigned value.
#include "/Kernel/Kernel_RV.PRJ"
I64 main() {
  I64 r = 0;
  if (LtU64(1, 2))                    r |= 1;
  if (!LtU64(2, 1))                   r |= 2;
  if (!LtU64(-1, 1))                  r |= 4;   // 0xffff... is not below 1 unsigned
  if (LtU64(1, -1))                   r |= 8;
  if (!LtU64(5, 5))                   r |= 16;
  if (LtU64(0x7fffffffffffffff, 0x8000000000000000)) r |= 32;   // signed order would say the opposite
  return r;
}
