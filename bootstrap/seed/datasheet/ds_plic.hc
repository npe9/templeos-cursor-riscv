// ds_plic.hc -- SiFive/virt-style PLIC context-0 register sheets.
// Offsets match MEM_PLIC_* in csr.hc / RVPlicHw.
U0 DsSheetPlicEnable()
{
  DsBegin("plic.enable", "plic", DS_KIND_MMIO, MEM_PLIC + MEM_PLIC_ENABLE_OFF, 4);
  DsField("IRQ0_31", 0, 31, 0, "M-mode ctx0 enable bits (IRQ n = bit n)");
  DsEnd;
}

U0 DsSheetPlicPending()
{
  DsBegin("plic.pending", "plic", DS_KIND_MMIO, MEM_PLIC + MEM_PLIC_PENDING_OFF, 4);
  DsField("IRQ0_31", 0, 31, 0, "Pending bits (read-only)");
  DsEnd;
}

U0 DsSheetPlicThreshold()
{
  DsBegin("plic.threshold", "plic", DS_KIND_MMIO, MEM_PLIC + MEM_PLIC_THRESHOLD_OFF, 4);
  DsField("THRESHOLD", 0, 2, 0, "Priority threshold (0 = accept prio>0)");
  DsEnd;
}

U0 DsSheetPlicClaim()
{
  DsBegin("plic.claim", "plic", DS_KIND_MMIO, MEM_PLIC + MEM_PLIC_CLAIM_OFF, 4);
  DsField("IRQ", 0, 31, 0, "Claim/complete: read=claim, write=complete");
  DsEnd;
}

U0 DsPlicInit()
{
  DsSheetPlicEnable;
  DsSheetPlicPending;
  DsSheetPlicThreshold;
  DsSheetPlicClaim;
}
DsPlicInit;
