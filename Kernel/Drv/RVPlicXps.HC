// Xilinx XPS Interrupt Controller (xlnx.xps-intc) — QEMU amd-microblaze-v @ XPS_INTC_BASE.
// Same RVPlic* API as RVPlicHw. IRQs are 0-based board bits (timer=0, UARTLite=1).
// Dig-down: Man("PLIC"); RVPlicEnable; RVPlicClaim; RVPlicComplete;
#ifndef RV_DRV_PLIC_XPS_HC
#define RV_DRV_PLIC_XPS_HC
#ifndef CONFIG_XPS_INTC_BASE
#define CONFIG_XPS_INTC_BASE 0x41200000
#endif
#define XPS_INTC_ISR 0x00
#define XPS_INTC_IPR 0x04
#define XPS_INTC_IER 0x08
#define XPS_INTC_IAR 0x0C
#define XPS_INTC_SIE 0x10
#define XPS_INTC_CIE 0x14
#define XPS_INTC_IVR 0x18
#define XPS_INTC_MER 0x1C
#define XPS_INTC_MER_ME  1
#define XPS_INTC_MER_HIE 2
I64 xps_intc_ready;
U0 RVXpsIntcEnsure()
{
  U8 *b = CONFIG_XPS_INTC_BASE;
  if (xps_intc_ready)
    return;
  OutU32(b + XPS_INTC_MER, XPS_INTC_MER_ME | XPS_INTC_MER_HIE);
  xps_intc_ready = 1;
}

U0 RVPlicEnable(I64 irq, I64 priority)
{
  U8 *b = CONFIG_XPS_INTC_BASE;
  priority = priority;
  if (irq < 0 || irq > 31)
    return;
  RVXpsIntcEnsure;
  OutU32(b + XPS_INTC_SIE, 1 << irq);
}

U0 RVPlicSetThreshold(I64 thr)
{
  // XPS INTC has no priority threshold — no-op (keep API).
  thr = 0;
  RVXpsIntcEnsure;
}

I64 RVPlicClaim()
{
  U8 *b = CONFIG_XPS_INTC_BASE;
  I64 ivr;
  RVXpsIntcEnsure;
  ivr = InU32(b + XPS_INTC_IVR);
  if (ivr < 0 || ivr > 31)
    return 0;
  // Note: XPS IRQ 0 (timer) returns 0 — same as PLIC "none". Callers that need
  // timer IRQ0 should check IPR bit0 when Claim returns 0.
  return ivr;
}

U0 RVPlicComplete(I64 irq)
{
  U8 *b = CONFIG_XPS_INTC_BASE;
  if (irq < 0 || irq > 31)
    return;
  RVXpsIntcEnsure;
  OutU32(b + XPS_INTC_IAR, 1 << irq);
}
#endif
