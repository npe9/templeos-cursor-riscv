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
  U8 tag[64];
  U8 buf[64];
  I64 rc, n;
  Sh("9p dbg\n");
  rc = NinePTransportBindMmio();
  Sh("bind rc\n");
  if (rc) return rc;
  rc = NinePClientInit(&ninep_client, NINEP_TP_MMIO);
  Sh("cinit rc\n");
  rc = NinePClientVersion(&ninep_client);
  Sh("ver rc\n");
  if (rc) return rc + 10;
  rc = NinePTransportMountTag(tag, 64);
  Sh("tag: ");
  UartStr(tag);
  Sh("\n");
  rc = NinePClientAttach(&ninep_client, tag, "holyc");
  Sh("attach rc\n");
  if (rc) return rc + 20;
  n = NinePClientReadPath(&ninep_client, "test.txt", buf, 64);
  Sh("read n\n");
  if (n > 0) {
    buf[n] = 0;
    UartStr(buf);
    Sh("\n");
  }
  return 0;
}
