// HolyC virtio-mmio balloon smoke: inflate + deflate one page.
#include "/Kernel/Kernel_RV.PRJ"
#define MEM_UART 0x10000000
U0 Sh(U8 *s)
{
  U8 *u = MEM_UART;
  while (*s)
    *u = *s++;
}

I64 main()
{
  Sh("virtio-balloon demo: legacy virtio-mmio\n");
  if (VirtioBalloonSelfTest()) {
    Sh("virtio-balloon: fail\n");
    return 1;
  }
  Sh("virtio-balloon: ok\n");
  return 0;
}
