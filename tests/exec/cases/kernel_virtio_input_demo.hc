// HolyC virtio-mmio input smoke: VirtioInputInit + empty poll.
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
  I64 n;
  Sh("virtio-input demo: legacy virtio-mmio\n");
  if (VirtioInputInit()) {
    Sh("no virtio-input device\n");
    return 0;
  }
  Sh("device up\n");
  n = VirtioInputPoll(8);
  Sh("virtio-input: ready\n");
  return n;
}
