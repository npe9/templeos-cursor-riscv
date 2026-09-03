// HolyC virtio-mmio SCSI smoke: Init + INQUIRY + READ(10) LBA0.
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
  Sh("virtio-scsi demo: legacy virtio-mmio\n");
  if (VirtioScsiInit()) {
    Sh("virtio-scsi: fail\n");
    return 1;
  }
  VirtioScsiEvtPrime();
  if (!VirtioScsiSelfTest()) {
    Sh("virtio-scsi: ok\n");
    return 0;
  }
  Sh("virtio-scsi: ready\n");
  return 0;
}
