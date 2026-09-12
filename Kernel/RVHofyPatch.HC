// RVHofyPatch.HC — re-patch host-AOT HOFYIMP1 slots from Fs hash after Load(Compiler.BIN).
// Kernel includes CompilerB.HH with OPTf_EXTERNS_TO_IMPORTS, so CmpCtrlNew/ExePrint/
// RVCmpWireAsmHash/… are HOFYIMP1 GOTs. oracle_out_plat fills them with a stub at boot;
// Load plants IET_REL64_EXPORT into Fs — this walks the blob trailer and writes real addrs
// (same resolution SysSymImportsResolve does for TempleOS patch-table imports).
#ifndef RV_HOFY_PATCH_HC
#define RV_HOFY_PATCH_HC
#define RV_HOFY_MAGIC	0x31504D4959464F48 // "HOFYIMP1" LE
#ifndef RV_BLOB_BASE
#define RV_BLOB_BASE	0x80800000
#endif
#ifndef RV_BLOB_SCAN_MAX
#define RV_BLOB_SCAN_MAX	0x200000
#endif
Bool RVHofyIsCmpSeedName(U8 *name)
{
  //Kernel HOFYIMP1 names that Load(Compiler.BIN) exports (not Call/Yield/…).
  if (!name || !name[0])
    return FALSE;
  if (!StrCmp(name, "CmpCtrlNew") || !StrCmp(name, "CmpCtrlDel") || !StrCmp(name, "Lex") || !StrCmp(name, "LexStmt2Bin") || !StrCmp(name, "ExePrint") || !StrCmp(name, "ExeFile") || !StrCmp(name, "ClassMemberLstDel") || !StrCmp(name, "RVCmpWireAsmHash") || !StrCmp(name, "RVAotLibSync") || !StrCmp(name, "RVCmpCtrlAddrsGet") || !StrCmp(name, "RVExePutSSynced") || !StrCmp(name, "Ui") || !StrCmp(name, "U") || !StrCmp(name, "CInit") || !StrCmp(name, "ExePutS") || !StrCmp(name, "Cmp"))
    return TRUE;
  return FALSE;
}

I64 RVHofyExportVal(U8 *name)
{
  CHashExport *tmpex;
  if (!name || !Fs || !Fs->hash_table)
    return 0;
  tmpex = HashFind(name, Fs->hash_table, HTG_ALL - HTT_IMPORT_SYS_SYM);
  if (!tmpex)
    return 0;
  if (tmpex->type & HTT_FUN)
    return tmpex(CHashFun *)->exe_addr;
  if (tmpex->type & HTT_GLBL_VAR)
    return tmpex(CHashGlblVar *)->data_addr;
  return tmpex->val;
}

I64 RVHofyRepatchFromHash(U8 *base = NULL, I64 scan_max = 0)
{
  //Find HOFYIMP1 at end of host-AOT blob; patch Compiler-seed slots only.
  // Do NOT rewrite Call/Yield/… — oracle/host harness owns those Kernel GOTs.
  U8 *ent, *name;
  I64 i, k, n = 0;
  U64 magic, count, slot, val;
  if (!base)
    base = RV_BLOB_BASE;
  if (scan_max <= 0)
    scan_max = RV_BLOB_SCAN_MAX;
  for (i = scan_max & ~7; i >= 16; i -= 8) {
    magic = 0;
    MemCpy(&magic, base + i - 8, 8);
    if (magic != RV_HOFY_MAGIC)
      continue;
    count = 0;
    MemCpy(&count, base + i - 16, 8);
    if (!count || count > 4096)
      continue;
    if (i < 16 + count * 32)
      continue;
    ent = base + i - 16 - count * 32;
    for (k = 0; k < count; k++) {
      slot = 0;
      MemCpy(&slot, ent, 8);
      name = ent + 8;
      if (name[0] && slot + 8 <= scan_max && RVHofyIsCmpSeedName(name)) {
        val = RVHofyExportVal(name);
        if (val) {
          MemCpy(base + slot, &val, 8);
          n++;
        }
      }
      ent += 32;
    }
    return n;
  }
  return 0;
}

I64 RVCmpPlantLoadedFun(U8 *name)
{
  //Plant HTT_FUN beside Load's HTT_EXPORT_SYS_SYM so ExePutS/HashFind(HTT_FUN) hit.
  CHashExport *tmpex;
  CHashFun *tmpf;
  I64 addr;
  if (!name || !Fs || !Fs->hash_table)
    return 0;
  if (HashFind(name, Fs->hash_table, HTT_FUN))
    return 0;
  tmpex = HashFind(name, Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex)
    return 0;
  addr = tmpex->val;
  if (!addr)
    return 0;
  tmpf = CAlloc(sizeof(CHashFun));
  tmpf->type = HTT_FUN | HTF_PUBLIC;
  tmpf->str = StrNew(name);
  tmpf->exe_addr = addr;
  LBtr(&tmpf->flags, Cf_EXTERN);
  HashAdd(tmpf, Fs->hash_table);
  return 1;
}

I64 RVCmpPlantLoadedCmpFuns()
{
  //Libs-first: CmpCtrl* / Wire / Lex / Exe* after reloc Compiler.BIN Load.
  I64 n = 0;
  n += RVCmpPlantLoadedFun("CmpCtrlNew");
  n += RVCmpPlantLoadedFun("CmpCtrlDel");
  n += RVCmpPlantLoadedFun("Lex");
  n += RVCmpPlantLoadedFun("LexStmt2Bin");
  n += RVCmpPlantLoadedFun("ExePrint");
  n += RVCmpPlantLoadedFun("ExeFile");
  n += RVCmpPlantLoadedFun("ClassMemberLstDel");
  n += RVCmpPlantLoadedFun("RVCmpWireAsmHash");
  n += RVCmpPlantLoadedFun("RVAotLibSync");
  n += RVCmpPlantLoadedFun("RVCmpCtrlAddrsGet");
  return n;
}
#endif
