// HolyC virtio-mmio 9p client smoke: Tversion + Tattach + read host virtfs file.
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
  I64 rc;
  Sh("virtio-9p demo: 9P2000.L client over legacy virtio-mmio\n");
  rc = Virtio9pSelfTest("hello from 9p", 13);
  if (!rc)
    Sh("virtio-9p: read_ok\n");
  else
    Sh("virtio-9p: read_fail\n");
  return rc;
}
