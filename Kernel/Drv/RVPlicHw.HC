// PLIC (when CONFIG_HAS_PLIC). Selected via RVPlicSelected.HH.
// Enable words are 32 IRQs wide — Icicle MMUART0 is source 90 (word 2).
// QEMU shakti_c maps only 128KiB (0x0C000000–0x0C01FFFF); SiFive context
// threshold/claim live at +0x200000 and are unmapped there — no-op those.
U0 RVPlicEnable(I64 irq, I64 priority)
{
  U32 *prio = CONFIG_PLIC_BASE + irq * 4;
  U32 *en = CONFIG_PLIC_BASE + CONFIG_PLIC_ENABLE_OFF + (irq / 32) * 4;
  if (priority <= 0)
    priority = 1;
  *prio = priority;
  *en = *en | (1 << (irq & 31));
}

U0 RVPlicSetThreshold(I64 thr)
{
#ifdef CONFIG_PLATFORM_SHAKTI_C
  return;
#else
  U32 *t = CONFIG_PLIC_BASE + CONFIG_PLIC_THRESHOLD_OFF;
  *t = thr;
#endif
}

I64 RVPlicClaim()
{
#ifdef CONFIG_PLATFORM_SHAKTI_C
  return 0;
#else
  U32 *c = CONFIG_PLIC_BASE + CONFIG_PLIC_CLAIM_OFF;
  return *c;
#endif
}

U0 RVPlicComplete(I64 irq)
{
#ifdef CONFIG_PLATFORM_SHAKTI_C
  return;
#else
  U32 *c = CONFIG_PLIC_BASE + CONFIG_PLIC_CLAIM_OFF;
  *c = irq;
#endif
}
