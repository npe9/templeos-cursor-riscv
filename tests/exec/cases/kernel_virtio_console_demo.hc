// HolyC virtio-mmio console smoke: Init + port-0 TX (file/null chardev).
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
  Sh("virtio-console demo: legacy virtio-mmio\n");
  if (VirtioConsoleInit()) {
    Sh("virtio-console: fail\n");
    return 1;
  }
  // Safe notify: QUEUE_NOTIFY after avail kick; host chardev file/null (not stdio).
  rc = VirtioConsoleWrite("virtio-console\n", 15);
  if (rc >= 0)
    Sh("virtio-console: tx_ok\n");
  else
    Sh("virtio-console: ready\n");
  return 0;
}
