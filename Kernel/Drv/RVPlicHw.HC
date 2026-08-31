// PLIC (when CONFIG_HAS_PLIC). Selected via RVPlicSelected.HH.
U0 RVPlicEnable(I64 irq, I64 priority)
{
  U32 *prio = CONFIG_PLIC_BASE + irq * 4;
  U32 *en = CONFIG_PLIC_BASE + CONFIG_PLIC_ENABLE_OFF;
  if (priority <= 0)
    priority = 1;
  *prio = priority;
  *en = *en | (1 << irq);
}

U0 RVPlicSetThreshold(I64 thr)
{
  U32 *t = CONFIG_PLIC_BASE + CONFIG_PLIC_THRESHOLD_OFF;
  *t = thr;
}

I64 RVPlicClaim()
{
  U32 *c = CONFIG_PLIC_BASE + CONFIG_PLIC_CLAIM_OFF;
  return *c;
}

U0 RVPlicComplete(I64 irq)
{
  U32 *c = CONFIG_PLIC_BASE + CONFIG_PLIC_CLAIM_OFF;
  *c = irq;
}
