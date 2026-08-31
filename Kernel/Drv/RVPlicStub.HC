// PLIC stubs (no hardware). Selected via RVPlicSelected.HH.
U0 RVPlicEnable(I64 irq, I64 priority)
{
  irq = priority;
}

U0 RVPlicSetThreshold(I64 thr)
{
  thr = 0;
}

I64 RVPlicClaim()
{
  return 0;
}

U0 RVPlicComplete(I64 irq)
{
  irq = 0;
}
