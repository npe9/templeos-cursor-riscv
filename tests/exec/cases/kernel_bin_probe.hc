// Host-packed RedSea Kernel.BIN seed (G9) — growing toward Kernel_RV TOSB.
// Not full Kernel_RV (traps/virtio/Load still live in Mac thin-loader ELF).
// Smoke: holyc-riscv → pack_tosb → mk_redsea_seed_img.py → A:/Kernel/Kernel.BIN
//
// KernelProbe     — phase3 seed FileFind+Load needle (→42).
// KernelHeapProbe — second init: host MAlloc/Free imports (heap surface).
// KernelInitLite  — third init: UART banner + FileWrite A:/Kernel/ENTRY.OK (→0x4B49 'KI').
// KernelEntry     — thin-loader handoff (→0x4B45 'KE'); runs Probe+InitLite then returns
//                   so Mac scaffold can still observe success (non-returning jump = later).
#ifndef CONFIG_UART_BASE
#define CONFIG_UART_BASE 0x10000000
#endif
public I64 KernelProbe()
{
  return 42;
}

U0 KernelUart(U8 *msg)
{
  U8 *uart = CONFIG_UART_BASE;
  if (!msg)
    return;
  while (*msg)
    *uart = *msg++;
}

public I64 KernelHeapProbe()
{
  U8 *p;
  p = MAlloc(64);
  if (!p)
    return -1;
  Free(p);
  return 64;
}

public I64 KernelInitLite()
{
  I64 n, h;
  KernelUart("Kernel.BIN: KernelInitLite (heap+FileWrite)...\n");
  h = KernelHeapProbe();
  if (h != 64)
    return -3;
  n = FileWrite("A:/Kernel/ENTRY.OK", "KE", 2);
  if (n < 2)
    return -1;
  return 0x4B49;
}

public I64 KernelEntry()
{
  I64 r;
  r = KernelProbe();
  if (r != 42)
    return -1;
  r = KernelInitLite();
  if (r != 0x4B49)
    return -2;
  KernelUart("Kernel.BIN: KernelEntry handoff OK (InitLite).\n");
  return 0x4B45;
}
