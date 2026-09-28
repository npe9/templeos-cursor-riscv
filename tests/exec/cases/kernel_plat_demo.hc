// Platform Kconfig smoke: HolyC Drv UART + CLINT (+ PLIC/MemMap/SiFive when present).
// Addresses/driver select come from Kernel/RVAutoConf.HH (make -C templeos-riscv defconfig*).
//
// Keep matrix green:
//   - HAS_PLIC: Enable only if UART_IRQ>0 (icicle=90); shakti IRQ=0 skips.
//     RVPlicHw no-ops threshold/claim on shakti (QEMU 128KiB PLIC aperture).
//   - SiFive: Enable via RVSifivePlic* (sifive_u / sifive_e).
//   - HAS_APLIC (xiangshan): RVPlicAplic path; owned by that board.
//   - Never call RVMemMap() here — harness Print is virt UART @ 0x10000000.
#include "/Kernel/RVAutoConf.HH"
#include "/Kernel/Drv/RVSifivePlat.HC"
#include "/Kernel/Drv/RVUart.HC"
#include "/Kernel/Drv/RVTimer.HC"
#include "/Kernel/Drv/RVPlic.HC"
#include "/Kernel/Drv/RVMemMap.HC"
// mip, read raw: MTIP (bit 7) is set by the CLINT whenever mtime >= mtimecmp[THIS hart], with no
// interrupt enable involved, so it can be polled with MIE off. That makes it the one observable
// that tells a comparator armed on our hart from one armed on a parked hart's.
asm {
_RVPLAT_MIP::
	csrr	a0,mip
	ret
}
_extern _RVPLAT_MIP I64 RVPlatMip();
asm {
_RVPLAT_HARTID::
	csrr	a0,mhartid
	ret
}
_extern _RVPLAT_HARTID I64 RVPlatHartId();
// one hex digit per nibble, enough for a hart id and a comparator readback in a failure line
U0 RVPlatPutHex(I64 v)
{
  U8 b[20], *hx = "0123456789abcdef";   // indexing the literal directly miscompiles (audit note)
  I64 i;
  b[0] = '0'; b[1] = 'x';
  for (i = 0; i < 16; i++)
    b[2 + i] = hx[(v >> (60 - 4 * i)) & 15];
  b[18] = 0;
  RVUartPutS(b);
}
I64 main()
{
  I64 t, t1, id, i, s, deadline;
  U8 *drv;
  U32 *u;
  RVUartInit();
  RVUartPutS("plat-smoke: machine=");
  RVUartPutS(CONFIG_PLATFORM_NAME);
  RVUartPutS("\n");
  RVUartPutS("plat-smoke: uart_ok\n");
  t = RVClintMtime();
  RVUartPutS("plat-smoke: clint_ok\n");
#ifdef CONFIG_HAS_CLINT
  s = 0;
  i = 0;
  while (i < 200000) {
    s += i;
    i++;
  }
  t1 = RVClintMtime();
  RVClintArmTicks(CONFIG_TIMEBASE_FREQ);
  if (t1 > t && s) {
    RVUartPutS("plat-smoke: clint_adv_ok\n");
    t = t1;
  } else {
    RVUartPutS("plat-smoke: clint_adv_fail\n");
    return 1;
  }
  // timer_irq: the comparator we arm has to be THIS hart's. On the FU740 and on QEMU's sifive_u
  // this image runs on hart 1; a hart-0 offset (0x4000) arms a parked hart and MTIP never rises here,
  // which is how preemption, sleep and the break interrupt were silently dead on the board.
  // Both directions are needed: QEMU resets every mtimecmp to 0, so MTIP is already pending on
  // every hart at boot and "set after arming" would pass through the wrong comparator. Disarming
  // through the configured offset must CLEAR our MTIP; arming must SET it.
  // MTIP is polled with a 200 ms bound each way: silicon updates it at once, QEMU from a host-side
  // timer callback that lags an mtime read by well over a millisecond on a loaded machine.
  RVClintSetMtimecmp(-1);
  deadline = RVClintMtime + CONFIG_TIMEBASE_FREQ / 5;
  while ((RVPlatMip & 0x80) && RVClintMtime < deadline)
    ;
  if (RVPlatMip & 0x80) {
    RVUartPutS("plat-smoke: timer_irq_fail (MTIP still set with mtimecmp=-1: not this hart's comparator) hart=");
    RVPlatPutHex(RVPlatHartId);
    RVUartPutS(" cmp=");
    RVPlatPutHex(*(I64 *)(CONFIG_CLINT_BASE + CONFIG_CLINT_MTIMECMP_OFF));
    RVUartPutS(" mip=");
    RVPlatPutHex(RVPlatMip);
    RVUartPutS("\n");
    return 1;
  }
  RVClintSetMtimecmp(RVClintMtime + CONFIG_TIMEBASE_FREQ / 500);   // 2 ms out
  deadline = RVClintMtime + CONFIG_TIMEBASE_FREQ / 5;
  while (!(RVPlatMip & 0x80) && RVClintMtime < deadline)
    ;
  if (RVPlatMip & 0x80) {
    RVUartPutS("plat-smoke: timer_irq_ok\n");
  } else {
    RVUartPutS("plat-smoke: timer_irq_fail (MTIP never set: mtimecmp is not this hart's)\n");
    return 1;
  }
  RVClintSetMtimecmp(-1);
#else
  RVUartPutS("plat-smoke: clint_stub_ok\n");
#endif
  if (RVSifivePresent) {
    RVSifiveUartPutS("plat-smoke: sifive_api\n");
    t = RVSifiveClintMtime();
    RVSifiveUartPutS("plat-smoke: sifive_clint_ok\n");
    if (RVSifiveCanReset)
      RVSifiveUartPutS("plat-smoke: sifive_can_reset\n");
    else
      RVSifiveUartPutS("plat-smoke: sifive_no_hw_reset\n");
    RVSifivePlicSetThreshold(0);
    RVSifivePlicEnable(CONFIG_UART_IRQ, 1);
    id = RVSifivePlicClaim();
    RVSifivePlicComplete(id);
    RVSifiveUartPutS("plat-smoke: sifive_plic_ok\n");
#ifdef CONFIG_UART_SIFIVE
#ifdef CONFIG_HAS_PLIC
    // The pending source below is the SiFive UART's tx-watermark: on JH7110 boards RVSifivePresent
    // is true but the console is a 16550, so the step is compiled only where the UART is SiFive.
    // plic_meip: the context we program has to be THIS hart's (FU740: hart 1 M-mode is context 1;
    // fu740-c000.dtsi interrupts-extended). The observable is mip.MEIP (bit 11): the PLIC raises the
    // external-interrupt line of the context's own hart, so with every source enabled in the
    // configured context, threshold 0, and one source pending (the UART's tx-watermark with txcnt=1
    // on a drained FIFO), MEIP rises here iff the context is ours -- through a parked hart's context
    // it rises there and stays clear here. No IRQ number is involved: QEMU's sifive_u is an FU540
    // (UART0 = 4) standing in for the FU740 (UART0 = 39), and a test keyed on the number would fail
    // on the model with the right context and pass on the board with the wrong one.
    u = CONFIG_UART_BASE;
    u[2] = 1 | (1 << 16);                       // txen, txcnt=1
    deadline = RVSifiveClintMtime + CONFIG_TIMEBASE_FREQ / 50;
    while (!(u[5] & 1) && RVSifiveClintMtime < deadline)
      ;
    u[4] = 1;                                   // ie.txwm: the UART source is now pending at the PLIC
    RVSifivePlicSetThreshold(0);
    for (i = 1; i < 64; i++)
      RVSifivePlicEnable(i, 1);
    deadline = RVSifiveClintMtime + CONFIG_TIMEBASE_FREQ / 100;
    while (!(RVPlatMip & 0x800) && RVSifiveClintMtime < deadline)
      ;
    t = RVPlatMip & 0x800;
    id = RVSifivePlicClaim();
    RVSifivePlicComplete(id);
    u[4] = 0;
    u[2] = 1;
    // RVSifivePlicEnable coerces priority<=0 to 1, so it cannot disable: clear the enable words.
    u = CONFIG_PLIC_BASE + CONFIG_PLIC_ENABLE_OFF;
    u[0] = 0;
    u[1] = 0;
    if (t) {
      RVSifiveUartPutS("plat-smoke: plic_meip_ok\n");
    } else {
      RVSifiveUartPutS("plat-smoke: plic_meip_fail (MEIP never rose here: PLIC context is not this hart's)\n");
      return 1;
    }
#endif
#endif
    t = RVSifiveTestBase() | RVSifiveAonBase() | RVSifiveGpioBase() | RVSifiveUart1Base() | RVSifivePrciBase() | RVSifiveEthBase();
  }
#ifdef CONFIG_HAS_PLIC
  RVPlicSetThreshold(0);
  // Enable only when UART_IRQ>0 (icicle=90). Shakti IRQ=0 skips; threshold/claim
  // are no-ops in RVPlicHw on shakti (QEMU 128KiB PLIC aperture).
  if (CONFIG_UART_IRQ > 0)
    RVPlicEnable(CONFIG_UART_IRQ, 1);
  id = RVPlicClaim();
  RVPlicComplete(id);
  RVUartPutS("plat-smoke: plic_ok\n");
#else
#ifdef CONFIG_HAS_APLIC
  RVPlicSetThreshold(0);
  if (CONFIG_UART_IRQ)
    RVPlicEnable(CONFIG_UART_IRQ, 1);
  id = RVPlicClaim();
  RVPlicComplete(id);
  RVUartPutS("plat-smoke: aplic_ok\n");
#else
  RVPlicSetThreshold(0);
  id = RVPlicClaim();
  RVPlicComplete(id);
  RVUartPutS("plat-smoke: plic_stub_ok\n");
#endif
#endif
  // RVMemMap() uses implicit Print — hangs in this harness. Probe strings.
  drv = RVMemMapDrvUart();
  if (drv)
    RVUartPutS("plat-smoke: memmap_ok\n");
  RVUartPutS("plat-smoke: PASS\n");
  return t & 0;
}
