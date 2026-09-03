// Xiangshan / AIA APLIC (MSI→IMSIC). RVPlic* API; Claim via mtopei.
// MMIO uses I64 base+offset (avoid U32* = CONFIG_*+off hang). IMSIC file
// programmed with fixed miselect/mireg asm (multi-arg CSR helpers corrupt
// the plat blob). Nested S-domain / guest files still out of scope.
#ifndef RV_DRV_PLIC_APLIC_HC
#define RV_DRV_PLIC_APLIC_HC
#ifndef CONFIG_APLIC_BASE
#define CONFIG_APLIC_BASE 0x31100000
#endif
#ifndef CONFIG_IMSIC_BASE
#define CONFIG_IMSIC_BASE 0x3A800000
#endif
#define APLIC_DOMAINCFG               0x0000
#define APLIC_DOMAINCFG_DM            (1 << 2)
#define APLIC_DOMAINCFG_IE            (1 << 8)
#define APLIC_SOURCECFG_BASE          0x0004
#define APLIC_SOURCECFG_SM_LEVEL_HIGH 0x6
#define APLIC_SETIENUM                0x1EDC
#define APLIC_TARGET_BASE             0x3004
#define APLIC_TARGET_EIID_MASK        0x7FF
#define APLIC_TARGET_HART_SHIFT       18
asm {
	RVImsicDeliveryOn::
	li	a0,0x70
	csrw	0x350,a0
	li	a0,1
	csrw	0x351,a0
	ret
}

asm {
	RVImsicThreshold0::
	li	a0,0x72
	csrw	0x350,a0
	csrw	0x351,zero
	ret
}

U0 RVImsicInit()
{
  RVImsicDeliveryOn;
  RVImsicThreshold0;
}

U0 RVPlicEnableHart(I64 irq, I64 priority, I64 hart)
{
  I64 base = CONFIG_APLIC_BASE;
  U32 *domain;
  U32 *src;
  U32 *tgt;
  U32 *setie;
  U32 tgt_val;
  if (irq <= 0)
    return;
  if (priority <= 0)
    priority = 1;
  if (hart < 0)
    hart = 0;
  RVImsicInit;
  domain = base + APLIC_DOMAINCFG;
  *domain = *domain | APLIC_DOMAINCFG_DM | APLIC_DOMAINCFG_IE;
  src = base + APLIC_SOURCECFG_BASE + (irq - 1) * 4;
  *src = APLIC_SOURCECFG_SM_LEVEL_HIGH;
  tgt_val = ((hart & 0x3FFF) << APLIC_TARGET_HART_SHIFT) | (irq & APLIC_TARGET_EIID_MASK);
  tgt = base + APLIC_TARGET_BASE + (irq - 1) * 4;
  *tgt = tgt_val;
  setie = base + APLIC_SETIENUM;
  *setie = irq;
  priority = priority;
}

U0 RVPlicEnable(I64 irq, I64 priority)
{
  RVPlicEnableHart(irq, priority, 0);
}

U0 RVPlicSetThreshold(I64 thr)
{
  RVImsicInit;
  // Nonzero eithreshold needs a parameterized miselect write — still open.
  thr = 0;
}

asm {
	RVPlicClaim::
	csrrw	a0,0x35C,zero
	srli	a0,a0,16
	andi	a0,a0,0x7FF
	ret
}

U0 RVPlicComplete(I64 irq)
{
  irq = 0;
}
#endif
