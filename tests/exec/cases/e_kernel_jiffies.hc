// RVJiffies reads the board's own mtime and advances.
//
// Tier 2 of the platform seam. This was HolyRVJiffies in bootstrap/holy_rt.h, reading mtime at a
// hardcoded 0x02000000+0xBFF8; it is now HolyC in Kernel/KUtilsRV.HC reading
// CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF, which Kconfig generates per board.
//
// Unlike the libm and strmem cases this one CAN fail on a broken implementation, because the
// assertions are about behaviour over time rather than a value the C also computes correctly:
// uninitialised must read 0, an initialised clock must be non-zero and must MOVE, and it must
// never move backwards. A stub returning 0, or a wrong base address reading a dead MMIO window,
// fails all three.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 before, mid, after, i, back = 0;
  RVKernelInit();
  // Before init the divisor is 0 and the contract is to return 0, not to divide by zero.
  before = RVJiffies();
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);   // 1 ms jiffy
  mid = RVJiffies();
  // Spin until the clock ticks. mtime on QEMU virt is 10 MHz, so a 1 ms jiffy needs 10k ticks;
  // bound the loop so a dead clock fails the case instead of hanging it.
  for (i = 0; i < 80000000 && RVJiffies() == mid; i++)
    ;
  after = RVJiffies();
  // Monotonic: sample repeatedly and catch any backwards step.
  for (i = 0; i < 2000; i++) {
    I64 a = RVJiffies(), b = RVJiffies();
    if (b < a)
      back = 1;
  }
  return (before == 0) * 1 + (mid != 0) * 2 + (after > mid) * 4 + (!back) * 8;
  // 0xf
}
