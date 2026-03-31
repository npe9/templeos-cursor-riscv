/* Separate TU so -O2 IPA cannot const-propagate GUEST_VMA into a tail jr (breaks guest ra). */
#include <stdint.h>

long templeos_invoke_guest(uintptr_t guest_vma) {
  typedef long (*guest_fn_t)(void);
  guest_fn_t g = (guest_fn_t)guest_vma;
  long ret;
  __asm__ volatile(
      "mv t0, %[fn]\n\t"
      "jalr ra, 0(t0)\n\t"
      "mv %[o], a0"
      : [o] "=r"(ret)
      : [fn] "r"(g)
      : "ra", "t0", "a0", "memory");
  return ret;
}
