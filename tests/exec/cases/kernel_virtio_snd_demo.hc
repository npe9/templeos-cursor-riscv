// HolyC virtio-sound smoke: VirtioSndInit + PCM TX period (audiodev none OK).
#include "/Kernel/Kernel_RV.PRJ"
#define MEM_UART 0x10000000
U0 Sh(U8 *s)
{
  U8 *u = MEM_UART;
  while (*s)
    *u = *s++;
}

U0 Hex(I64 v)
{
  U8 b[20];
  I64 i;
  U8 *p = b + 18;
  *p = 0;
  p--;
  if (!v) {
    Sh("0");
    return;
  }
  while (v) {
    i = v & 15;
    v >>= 4;
    if (i < 10)
      *p = '0' + i;
    else
      *p = 'a' + i - 10;
    p--;
  }
  Sh(p + 1);
}

U0 Dec(I64 v)
{
  U8 b[24];
  I64 i, n = 0;
  U8 *p;
  if (v < 0) {
    Sh("-");
    v = -v;
  }
  if (!v) {
    Sh("0");
    return;
  }
  p = b + 23;
  *p = 0;
  while (v) {
    i = v % 10;
    v = v / 10;
    p--;
    *p = '0' + i;
    n++;
  }
  Sh(p);
}

I64 main()
{
  I64 rc, t0, elapsed;
  CTask adam;
  Sh("virtio-snd demo: legacy virtio-mmio\n");
  if (!VirtioSndFind) {
    Sh("virtio-snd: no device\n");
    return 1;
  }
  Sh("virtio-snd: found base=");
  Hex(VirtioSndFind);
  Sh("\n");
  rc = VirtioSndSelfTest;
  if (rc) {
    Sh("virtio-snd: fail rc=");
    Hex(rc);
    Sh(" ctrl=");
    Hex(virtio_snd_ctrl_ok);
    Sh(" tx_ok=");
    Hex(virtio_snd_tx_ok);
    Sh(" tx_fail=");
    Hex(virtio_snd_tx_fail);
    Sh(" started=");
    Hex(virtio_snd_started);
    Sh("\n");
    return 1;
  }
  Sh("virtio-snd: tx_ok=");
  Hex(virtio_snd_tx_ok);
  Sh(" ctrl=");
  Hex(virtio_snd_ctrl_ok);
  Sh("\n");
  //Wall-clock Play needle: quarter @ tempo 2.5 ≈ 400 ms (Yield-default restored after).
  MemSet(&adam, 0, sizeof(CTask));
  adam.addr = &adam;
  adam.next_task = &adam;
  adam.last_task = &adam;
  Fs = &adam;
  RVSndRealTiming(TRUE);
  MusicSettingsRst;
  t0 = RVJiffies();
  Play("5qC");
  elapsed = RVJiffies() - t0;
  RVSndRealTiming(FALSE);
  if (elapsed < 250 || elapsed > 800) {
    Sh("virtio-snd: timing FAIL ms=");
    Dec(elapsed);
    Sh("\n");
    return 1;
  }
  Sh("virtio-snd: timing_ms=");
  Dec(elapsed);
  Sh("\n");
  Sh("virtio-snd: ok\n");
  return 0;
}
