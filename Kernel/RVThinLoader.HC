// RVThinLoader — G9 thin boot path: export-only LoadBufLite → HashAdd exports →
// HashFind("KernelEntry") → Call (SoftCall-shaped Jump). SoftCall owns first
// mount + FS/Load ENTER in BIN then HLT — loader does not regain control.
//
// RV_THIN_EMBED_BIN: Kernel.BIN linked at KERNEL_EMBED_ADDR (.kernel_bin) —
// no RVThinVirtioBlk / RVRedSeaRaw chicken-egg. SoftCall re-Inits virtio for
// LoadProbe/FS. Else: libs-first MMIO+raw+arena fetch (legacy chicken-egg).
// Demo: kernel_thin_loader_demo.hc
#ifndef RV_THIN_LOADER_HC
#define RV_THIN_LOADER_HC
#ifndef KERNEL_BIN_MAGIC_ADDR
#define KERNEL_BIN_MAGIC_ADDR 0x8700E000
#endif
#ifndef KERNEL_BIN_MAGIC_VAL
#define KERNEL_BIN_MAGIC_VAL 0x4B494E49
#endif
#ifndef KERNEL_BIN_STAY_ADDR
#define KERNEL_BIN_STAY_ADDR 0x8700E008
#endif
#ifndef KERNEL_BIN_STAY_VAL
#define KERNEL_BIN_STAY_VAL 0x53544159
#endif
// LoadBuf plants &KernelEntry here; SoftCall JumpSoft checks HashFind match.
#ifndef KERNEL_BIN_ENTRY_ADDR
#define KERNEL_BIN_ENTRY_ADDR 0x8700E010
#endif
#ifndef KERNEL_EMBED_ADDR
#define KERNEL_EMBED_ADDR 0x81000000
#endif
Bool rv_thin_loader_ok = FALSE;
U0 RVThinUart(U8 *msg)
{
  U8 *uart = CONFIG_UART_BASE;
  if (!msg)
    return;
  while (*msg)
    *uart = *msg++;
}

U0 RVThinUartI64(U8 *prefix, I64 v)
{
  U8 msg[96];
  StrPrint(msg, "%s%d\n", prefix, v);
  RVThinUart(msg);
}

U32 RVThinLoadU32(U8 **_src)
{
  U32 v;
  MemCpy(&v, *_src, 4);
  *_src += 4;
  return v;
}
// Export-only LoadBuf for import-free Kernel.BIN (no KLoad.HC in thin PRJ).
// Accepts IET_REL32/IMM32/REL64/IMM64_EXPORT + IET_END only — SoftCall seed
// packs REL64_EXPORT for KernelProbe/Entry/InitLite/… with zero imports/abs.
// HashAdds each export into Fs->hash_table; plants Jump-hint for SoftCall.
// Embed path: in-place (no MAlloc copy) — export-only does not patch body.
CBinFile *RVThinLoadBuf(CBinFile *src, I64 size)
{
  CBinFile *bfh;
  U8 *module_base, *pt, *st_ptr;
  I64 etype, i, entry;
  I64 *eslot;
  CHashExport *tmpex;
  CHashTable *table;
  if (!src || size < sizeof(CBinFile) || src->bin_signature != BIN_SIGNATURE_VAL)
    return NULL;
  if (src->patch_table_offset <= 0 || src->patch_table_offset >= size)
    return NULL;
  table = Fs->hash_table;
  if (!table || !table->body)
    return NULL;
#ifdef RV_THIN_EMBED_BIN
  bfh = src;
#else
  bfh = MAlloc(size);
  if (!bfh)
    return NULL;
  MemCpy(bfh, src, size);
#endif
  module_base = bfh(U8 *) + sizeof(CBinFile);
  pt = bfh(U8 *) + bfh->patch_table_offset;
  entry = 0;
  while (TRUE) {
    etype = *pt++;
    if (etype == IET_END)
      break;
    i = RVThinLoadU32(&pt);
    st_ptr = pt;
    pt += StrLen(st_ptr) + 1;
    if (etype == IET_REL32_EXPORT || etype == IET_IMM32_EXPORT || etype == IET_REL64_EXPORT || etype == IET_IMM64_EXPORT) {
      if (!*st_ptr)
        goto thin_load_fail;
      tmpex = CAlloc(sizeof(CHashExport));
      if (!tmpex)
        goto thin_load_fail;
      tmpex->str = StrNew(st_ptr);
      if (!tmpex->str)
        goto thin_load_fail;
      tmpex->type = HTT_EXPORT_SYS_SYM | HTF_IMM;
      if (etype == IET_IMM32_EXPORT || etype == IET_IMM64_EXPORT)
        tmpex->val = i;
      else
        tmpex->val = i + module_base;
      HashAdd(tmpex, table);
      if (!StrCmp(st_ptr, "KernelEntry"))
        entry = tmpex->val;
    } else {
      // Imports / ABS / heaps / MAIN need full KLoad — refuse (seed must stay import-free).
      goto thin_load_fail;
    }
  }
  if (!entry)
    goto thin_load_fail;
  eslot = KERNEL_BIN_ENTRY_ADDR;
  *eslot = entry;
  return bfh;
  thin_load_fail:
#ifndef RV_THIN_EMBED_BIN
  Free(bfh);
#endif
  return NULL;
}

U0 RVThinLoader()
{
  CBinFile *bfh;
  U8 *raw;
  I64 r, sz, *stay, *eslot;
  CHashExport *tmpex;
  rv_thin_loader_ok = FALSE;
#ifdef RV_THIN_EMBED_BIN
  RVThinUart("RVThinLoader: thin embed+LoadBuf; Kernel.BIN @0x81000000...\n");
  raw = KERNEL_EMBED_ADDR;
  if (!raw || raw(CBinFile *)->bin_signature != BIN_SIGNATURE_VAL) {
    RVThinUart("RVThinLoader: embed Kernel.BIN missing/bad TOSB.\n");
    return;
  }
  sz = raw(CBinFile *)->file_size;
  if (sz < sizeof(CBinFile)) {
    RVThinUart("RVThinLoader: embed Kernel.BIN size bad.\n");
    return;
  }
  RVThinUartI64("RVThinLoader: embed OK sz=", sz);
  RVThinUart("RVThinLoader: embed OK; LoadBuf...\n");
  bfh = RVThinLoadBuf(raw(CBinFile *), sz);
#else
  RVThinUart("RVThinLoader: thin MMIO+raw+arena; read Kernel/Kernel.BIN...\n");
  raw = RVRedSeaRawFileRead("Kernel", "Kernel.BIN", &sz);
  if (!raw || sz < sizeof(CBinFile)) {
    RVThinUart("RVThinLoader: raw Kernel.BIN missing.\n");
    return;
  }
  // SoftCall is import-free — export-only LoadBufLite (no full KLoad in thin).
  RVThinUartI64("RVThinLoader: raw OK arena sz=", sz);
  RVThinUart("RVThinLoader: raw OK; LoadBuf...\n");
  bfh = RVThinLoadBuf(raw(CBinFile *), sz);
  Free(raw);
#endif
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVThinUart("RVThinLoader: LoadBuf FAILED.\n");
    return;
  }
  // Plant STAY so KernelEntry SoftCall then HLT (phase3 Call leaves slot 0).
  stay = KERNEL_BIN_STAY_ADDR;
  *stay = KERNEL_BIN_STAY_VAL;
  eslot = KERNEL_BIN_ENTRY_ADDR;
  if (!eslot || !*eslot) {
    RVThinUart("RVThinLoader: Jump-hint missing after LoadBuf.\n");
    return;
  }
  tmpex = HashFind("KernelEntry", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex || !tmpex->val) {
    RVThinUart("RVThinLoader: HashFind KernelEntry FAILED.\n");
    return;
  }
  // SoftCall JumpSoft also requires HashFind == Jump-hint.
  if (tmpex->val != *eslot) {
    RVThinUart("RVThinLoader: HashFind/Jump-hint mismatch.\n");
    return;
  }
  rv_thin_loader_ok = TRUE;
  RVThinUart("RVThinLoader: LoadBuf OK; Jump KernelEntry via HashFind (non-return)...\n");
  // Call via HashFind (SoftCall-shaped). Stay path never returns (SoftCall+HLT).
  r = Call(tmpex->val);
  // Unreachable when Stay holds.
  RVThinUartI64("RVThinLoader: Jump returned (FAIL) r=", r);
  rv_thin_loader_ok = FALSE;
}
#endif
