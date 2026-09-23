// RVPhase3.HC — TempleOS Boot.DD phase 3 on RISC-V.
// x86: Load("/Compiler/Compiler") → ExeFile("StartOS") → SrvTaskCont.
// RV (P3 intermediate — see templeos-riscv/COMPILER_RV.md):
//   1) Prefer A:/Compiler/Compiler.BIN already on RedSea (virtio seed img) →
//      heap Load() → live Cmp/ExePutS (G9 relocatable seed; no in-image Body).
//      Optional last-resort: ELF .compiler_bin @0x81000000 bytes → FileWrite →A:.
//   2) Guest MakeOS: loaded Cmp → Tiny.BIN → Load → Call.
//   3) Guest Runtime: Cmp Seed/Svc/Kern + Adam/StartOS.BIN (HolyC modules on A:).
//   4) StartOS primarily Loads those guest BINs (not host-staged ExeFile strings).
// Residual host AOT (G9): phase3 ELF scaffolding + pack_tosb Compiler.BIN +
// Kernel.BIN InitLite seed on RedSea img (ELF .compiler_bin optional). Live Cmp is
// heap Load() of A:/Compiler/Compiler.BIN (PC-rel — relocatable). Kernel.BIN
// seed is FileFind+Load+InitLite early (before Cmp); Runtime prefers RedSea seed over
// guest Cmp rebuild. Full Menu_RV U8[] embed dropped; soft P6 stages
// Menu_RV_Guest via RVAdamLiteMenuSrc. AdamCore: guest Cmp→Load→Call FileWrite.
//
// Define RV_PHASE3_LOADED_CMP_ONLY in the demo (no Compiler_RV_Body.PRJ).
// Cmp below forwards to HashFind("Cmp") after LoadFullCompiler.
#include "RVAdamLiteMenuSrc"
Bool rv_phase3_compiler_ok = FALSE;
Bool rv_phase3_load_ok = FALSE;
Bool rv_phase3_startos_ok = FALSE;
Bool rv_phase3_include_ok = FALSE;
Bool rv_phase3_hostbin_ok = FALSE;
Bool rv_phase3_fullcmp_ok = FALSE;
Bool rv_phase3_makeos_ok = FALSE;
Bool rv_phase3_runtime_ok = FALSE;
Bool rv_phase3_kernel_seed_ok = FALSE;
I64 (*rv_phase3_loaded_cmp)(U8 *filename, U8 *map_name, U8 *out_name, U8 mapfile_drv_let) = NULL;
#ifdef RV_PHASE3_LOADED_CMP_ONLY
I64 Cmp(U8 *filename, U8 *map_name = NULL, U8 *out_name = NULL, U8 mapfile_drv_let = 0)
{
  //G9: Body dropped — guest Cmp is the loaded Compiler.BIN export.
  if (!rv_phase3_loaded_cmp)
    return -1;
  return (*rv_phase3_loaded_cmp)(filename, map_name, out_name, mapfile_drv_let);
}
#endif
U0 RVPhase3Uart(U8 *msg)
{
  U8 *uart = CONFIG_UART_BASE;
  if (!msg)
    return;
  while (*msg)
    *uart = *msg++;
}

I64 RVPhase3ExportAddr(U8 *name, I64 *_kind)
{
  //Resolve an export to the address RVPhase3CallExport would call, WITHOUT calling it.
  //*_kind: 1 = HTT_FUN exe_addr, 0 = export val, -1 = not found. Exists so a rung can say
  //WHAT it is about to jump to -- "Load OK" plus a crash told us nothing about the address.
  CHashExport *tmpex;
  *_kind = -1;
  if (!name)
    return 0;
  tmpex = HashFind(name, Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex)
    tmpex = HashFind(name, Fs->hash_table, HTT_FUN);
  if (!tmpex)
    return 0;
  if (tmpex->type & HTT_FUN) {
    *_kind = 1;
    return tmpex(CHashFun *)->exe_addr;
  }
  *_kind = 0;
  return tmpex->val;
}

I64 RVPhase3CallExport(U8 *name)
{
  //Call HTT_EXPORT_SYS_SYM or HTT_FUN by name; -1 if missing.
  CHashExport *tmpex;
  if (!name)
    return -1;
  tmpex = HashFind(name, Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex)
    tmpex = HashFind(name, Fs->hash_table, HTT_FUN);
  if (!tmpex)
    return -1;
  if (tmpex->type & HTT_FUN)
    return Call(tmpex(CHashFun *)->exe_addr);
  return Call(tmpex->val);
}

U0 RVPhase3UartI64(U8 *prefix, I64 v)
{
  U8 msg[96];
  StrPrint(msg, "%s%d\n", prefix, v);
  RVPhase3Uart(msg);
}

U0 RVPhase3UartHex64(U8 *prefix, I64 v)
{
  U8 msg[96];
  StrPrint(msg, "%s%X\n", prefix, v);
  RVPhase3Uart(msg);
}

U0 RVPhase3DumpOpt6IdentFus()
{
  U8 *dump, b;
  I64 dsz, *dv, i, n;
  if (FileFind("A:/PrsIdent.DD")) {
    dump = FileRead("A:/PrsIdent.DD", &dsz, NULL);
    if (dump && dsz >= 1) {
      b = dump[0];
      RVPhase3UartI64("RVPhase3: PrsIdent DEREF.cls_raw=", b);
    }
    Free(dump);
  } else
    RVPhase3Uart("RVPhase3: PrsIdent dump MISSING.\n");
  if (FileFind("A:/PrsIdentStars.DD")) {
    dump = FileRead("A:/PrsIdentStars.DD", &dsz, NULL);
    if (dump && dsz >= 1) {
      b = dump[0];
      RVPhase3UartI64("RVPhase3: PrsIdent DEREF.cls_stars=", b);
    }
    Free(dump);
  }
  if (FileFind("A:/AsgIdentPt.DD")) {
    dump = FileRead("A:/AsgIdentPt.DD", &dsz, NULL);
    if (dump && dsz >= 1) {
      b = dump[0];
      RVPhase3UartI64("RVPhase3: AsgIdent pt=", b);
    }
    Free(dump);
  } else
    RVPhase3Uart("RVPhase3: AsgIdent dump MISSING.\n");
  if (FileFind("A:/AsgIdentRaw.DD")) {
    dump = FileRead("A:/AsgIdentRaw.DD", &dsz, NULL);
    if (dump && dsz >= 1) {
      b = dump[0];
      RVPhase3UartI64("RVPhase3: AsgIdent cls_raw=", b);
    }
    Free(dump);
  }
  if (FileFind("A:/AsgIdentStars.DD")) {
    dump = FileRead("A:/AsgIdentStars.DD", &dsz, NULL);
    if (dump && dsz >= 1) {
      b = dump[0];
      RVPhase3UartI64("RVPhase3: AsgIdent cls_stars=", b);
    }
    Free(dump);
  }
  if (FileFind("A:/AsgIdentPt6.DD")) {
    dump = FileRead("A:/AsgIdentPt6.DD", &dsz, NULL);
    if (dump && dsz >= 1) {
      b = dump[0];
      RVPhase3UartI64("RVPhase3: AsgIdentPt6 pt=", b);
    }
    Free(dump);
  } else
    RVPhase3Uart("RVPhase3: AsgIdentPt6 MISSING.\n");
  if (FileFind("A:/AsgIdentRaw6.DD")) {
    dump = FileRead("A:/AsgIdentRaw6.DD", &dsz, NULL);
    if (dump && dsz >= 1) {
      b = dump[0];
      RVPhase3UartI64("RVPhase3: AsgIdentPt6 arg1_raw=", b);
    }
    Free(dump);
  }
  if (FileFind("A:/AsgIdentMode6.DD")) {
    dump = FileRead("A:/AsgIdentMode6.DD", &dsz, NULL);
    if (dump && dsz >= 1) {
      b = dump[0];
      RVPhase3UartI64("RVPhase3: AsgIdentPt6 arg1_mode=", b);
    }
    Free(dump);
  }
  if (FileFind("A:/AsgIdentByv6.DD")) {
    dump = FileRead("A:/AsgIdentByv6.DD", &dsz, NULL);
    if (dump && dsz >= 1) {
      b = dump[0];
      RVPhase3UartI64("RVPhase3: AsgIdentPt6 by_val=", b);
    }
    Free(dump);
  }
  if (FileFind("A:/AsgIdentEm.DD")) {
    dump = FileRead("A:/AsgIdentEm.DD", &dsz, NULL);
    if (dump && dsz >= 14) {
      RVPhase3UartI64("RVPhase3: AsgIdentEm by_val=", dump[0]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm pt=", dump[1]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm a1_mode=", dump[2]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm a1_raw=", dump[3]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm a2_mode=", dump[4]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm a2_raw=", dump[5]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm res_mode=", dump[6]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm res_raw=", dump[7]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm br=", dump[8]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm ic_cnt=", dump[9]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm a1_reg=", dump[10]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm a2_reg=", dump[11]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm res_reg=", dump[12]);
      RVPhase3UartI64("RVPhase3: AsgIdentEm ic_code=", dump[13]);
    } else
      RVPhase3Uart("RVPhase3: AsgIdentEm dump short.\n");
    Free(dump);
  } else
    RVPhase3Uart("RVPhase3: AsgIdentEm MISSING (no Ident ASSIGN/MOV emit).\n");
  if (!FileFind("A:/Opt6Ident.DD")) {
    RVPhase3Uart("RVPhase3: Opt6Fus dump MISSING (no Ident fusion).\n");
    return;
  }
  dump = FileRead("A:/Opt6Ident.DD", &dsz, NULL);
  if (!dump || dsz < sizeof(I64) * 12) {
    RVPhase3Uart("RVPhase3: Opt6Fus dump short/empty.\n");
    Free(dump);
    return;
  }
  n = dsz / (sizeof(I64) * 12);
  if (n > 4)
    n = 4;
  RVPhase3UartI64("RVPhase3: Opt6Fus n=", n);
  for (i = 0; i < n; i++) {
    dv = dump(I64 *) + i * 12;
    RVPhase3UartI64("RVPhase3: Opt6Fus i=", i);
    RVPhase3UartHex64("RVPhase3: Opt6Fus ASSIGN.type=", dv[0]);
    RVPhase3UartI64("RVPhase3: Opt6Fus ASSIGN.raw=", dv[1]);
    RVPhase3UartI64("RVPhase3: Opt6Fus ASSIGN.pt=", dv[2]);
    RVPhase3UartI64("RVPhase3: Opt6Fus ASSIGN.cls_raw=", dv[3]);
    RVPhase3UartI64("RVPhase3: Opt6Fus ASSIGN.cls_stars=", dv[4]);
    RVPhase3UartHex64("RVPhase3: Opt6Fus ASSIGN.fl=", dv[5]);
    RVPhase3UartI64("RVPhase3: Opt6Fus tmpil2.code=", dv[6]);
    RVPhase3UartHex64("RVPhase3: Opt6Fus tmpil2.arg1=", dv[7]);
    RVPhase3UartI64("RVPhase3: Opt6Fus tmpil2.raw=", dv[8]);
    RVPhase3UartI64("RVPhase3: Opt6Fus tmpil2.pt=", dv[9]);
    RVPhase3UartHex64("RVPhase3: Opt6Fus tmpil2.res=", dv[10]);
    RVPhase3UartI64("RVPhase3: Opt6Fus gate=", dv[11]);
  }
  Free(dump);
}

U0 RVPhase3DumpLiteIdent(CBinFile *bfh)
{
  U8 *code;
  I64 wi, word, sb_cnt, lbu_cnt, mv_cnt;
  CHashExport *tmpex;
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL)
    return;
  tmpex = HashFind("AdamLiteIdentProbe", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex)
    tmpex = HashFind("AdamLiteIdentProbe", Fs->hash_table, HTT_FUN);
  if (!tmpex)
    return;
  if (tmpex->type & HTT_FUN)
    code = tmpex(CHashFun *)->exe_addr;
  else
    code = tmpex->val;
  RVPhase3UartHex64("RVPhase3: Ident dump code=0x", code(I64));
  sb_cnt = 0;
  lbu_cnt = 0;
  mv_cnt = 0;
  for (wi = 0; wi < 48; wi++) {
    word = 0;
    MemCpy(&word, code + wi * 4, 4);
    RVPhase3UartHex64("RVPhase3: Ident_word=", word & 0xFFFFFFFF);
    if ((word & 0x707F) == 0x23)
      sb_cnt++;
    if ((word & 0x707F) == 0x4003)
      lbu_cnt++;
    if ((word & 0xFE00707F) == 0x00000013 && (word >> 12 & 7) == 0 && (word >> 20 & 0xFFF) == 0)
      mv_cnt++;
  }
  RVPhase3UartI64("RVPhase3: Ident sb_cnt=", sb_cnt);
  RVPhase3UartI64("RVPhase3: Ident lbu_cnt=", lbu_cnt);
  RVPhase3UartI64("RVPhase3: Ident mv_addi0_cnt=", mv_cnt);
}

U0 RVPhase3DumpLiteScalar(CBinFile *bfh)
{
  //After Load: abs slots (if any) + first RV words of AdamLiteScalarInit.
  U8 *module_base, *src, *ptr2, *code;
  I64 etype, i, j, cnt, slot_off, abs_val, saw_abs = 0;
  CHashExport *tmpex;
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL)
    return;
  module_base = bfh(U8 *) + sizeof(CBinFile);
  RVPhase3UartHex64("RVPhase3: abs dump module_base=0x", module_base(I64));
  RVPhase3UartI64("RVPhase3: abs dump file_size=", bfh->file_size);
  RVPhase3UartI64("RVPhase3: abs dump patch_table_offset=", bfh->patch_table_offset);
  src = bfh(U8 *) + bfh->patch_table_offset;
  etype = *src;
  if (etype == IET_ABS_ADDR) {
    src++;
    cnt = LoadU32(&src);
    src++;
    // empty name
    saw_abs = 1;
    RVPhase3UartI64("RVPhase3: abs dump IET_ABS_ADDR cnt=", cnt);
    for (j = 0; j < cnt; j++) {
      slot_off = LoadU32(&src);
      ptr2 = module_base + slot_off;
      abs_val = 0;
      MemCpy(&abs_val, ptr2, 8);
      RVPhase3UartHex64("RVPhase3: abs dump slot_off=0x", slot_off);
      RVPhase3UartHex64("RVPhase3: abs dump patched_u64=0x", abs_val);
      RVPhase3UartHex64("RVPhase3: abs dump module_base+slot=0x", module_base(I64) + slot_off);
    }
  }
  if (!saw_abs)
    RVPhase3Uart("RVPhase3: abs dump — no IET_ABS_ADDR (PC-rel or RVLi).\n");
  tmpex = HashFind("AdamLiteScalarInit", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex)
    tmpex = HashFind("AdamLiteScalarInit", Fs->hash_table, HTT_FUN);
  if (tmpex) {
    if (tmpex->type & HTT_FUN)
      code = tmpex(CHashFun *)->exe_addr;
    else
      code = tmpex->val;
    RVPhase3UartHex64("RVPhase3: abs dump Init=0x", code(I64));
    for (j = 0; j < 16; j++) {
      abs_val = 0;
      MemCpy(&abs_val, code + j * 4, 4);
      RVPhase3UartHex64("RVPhase3: abs dump Init_word=", abs_val & 0xFFFFFFFF);
    }
  } else
    RVPhase3Uart("RVPhase3: abs dump Init export MISSING.\n");
}

U8 *RVPhase3PreferLitePrj(U8 *red_prj, U8 *adam_prj, U8 *src, U8 *seed_msg)
{
  //Prefer RedSea Compiler/*.PRJ seed (smoke pack); else FileWrite Adam fallback.
  if (red_prj && FileFind(red_prj)) {
    if (seed_msg)
      RVPhase3Uart(seed_msg);
    return red_prj;
  }
  if (adam_prj && src)
    FileWrite(adam_prj, src, StrLen(src));
  return adam_prj;
}

Bool RVPhase3CmpWrite(U8 *prj, U8 *bin_out, U8 *fail_msg)
{
  //Guest Cmp PRJ→BIN via loaded Compiler.BIN (or in-image Body fallback).
  I64 err;
  try {
    if (rv_phase3_loaded_cmp)
      err = (*rv_phase3_loaded_cmp)(prj, NULL, bin_out, 0);
    else
      err = Cmp(prj,, bin_out);
  } catch {
    Fs->catch_except = TRUE;
    err = -1;
  }
  if (err || !FileFind(bin_out)) {
    if (fail_msg)
      RVPhase3Uart(fail_msg);
    RVPhase3UartI64("RVPhase3: Cmp err=", err);
    return FALSE;
  }
  return TRUE;
}

U8 *RVPackTOSB(U8 *code, I64 code_len, I64 *sz_out)
{
  //TOSB: exports first (CMain order), then IMM_I64 import, then END.
  I64 hdr = sizeof(CBinFile), patch_len, size, i;
  U8 *bin, *p;
  CBinFile *bfh;
  U32 u;
  // export RVHello 13 + import RVPatchMe 15 + END 1 (no MAIN; Call entry directly)
  patch_len = 13 + 15 + 1;
  size = (hdr + code_len + patch_len + 15) & -16;
  bin = MAlloc(size);
  MemSet(bin, 0, size);
  bfh = bin(CBinFile *);
  bfh->jmp = 0xEB + 256 * (hdr - 2);
  bfh->module_align_bits = 0;
  bfh->reserved = 0;
  bfh->bin_signature = BIN_SIGNATURE_VAL;
  bfh->org = INVALID_PTR;
  bfh->patch_table_offset = hdr + code_len;
  bfh->file_size = size;
  for (i = 0; i < code_len; i++)
    bin[hdr + i] = code[i];
  p = bin + hdr + code_len;
  *p++ = IET_REL64_EXPORT;
  u = 0;
  MemCpy(p, &u, 4);
  p += 4;
  MemCpy(p, "RVHello", 7);
  p += 7;
  *p++ = 0;
  *p++ = IET_IMM_I64;
  u = 8;
  MemCpy(p, &u, 4);
  p += 4;
  MemCpy(p, "RVPatchMe", 9);
  p += 9;
  *p++ = 0;
  *p++ = IET_END;
  if (sz_out)
    *sz_out = size;
  return bin;
}
Bool RVPhase3LoadBin();
Bool RVPhase3LoadHostBin();
Bool RVPhase3LoadFullCompiler();
Bool RVPhase3ProbeSeedKernel()
{
  // G9: after virtio RedSea mount, prove host-staged A:/Kernel/Kernel.BIN
  // before Cmp. Growing seed (KernelProbe→42, KernelEntry→0x4B45 via
  // import-free InitLite UART+64KiB heap+RAM magic), not full Kernel_RV.
  // SoftCall is import-free (BIN owns mount/FS/Load ENTER) — no SoftCall exports.
  CBinFile *bfh;
  I64 r, *slot;
  if (rv_phase3_kernel_seed_ok)
    return TRUE;
  if (!FileFind("A:/Kernel/Kernel.BIN")) {
    RVPhase3Uart("RVPhase3: RedSea Kernel.BIN seed missing (FileFind).\n");
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: RedSea Kernel.BIN seed FileFind OK; Load...\n");
  bfh = Load("A:/Kernel/Kernel.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: RedSea Kernel.BIN seed Load FAILED.\n");
    return FALSE;
  }
  r = RVPhase3CallExport("KernelProbe");
  if (r != 42) {
    RVPhase3UartI64("RVPhase3: RedSea Kernel.BIN KernelProbe FAILED r=", r);
    return FALSE;
  }
  r = RVPhase3CallExport("KernelEntry");
  if (r != 0x4B45) {
    RVPhase3UartI64("RVPhase3: RedSea Kernel.BIN KernelEntry FAILED r=", r);
    return FALSE;
  }
  slot = KERNEL_BIN_MAGIC_ADDR;
  if (*slot != KERNEL_BIN_MAGIC_VAL) {
    RVPhase3Uart("RVPhase3: RedSea Kernel.BIN magic missing (InitLite).\n");
    return FALSE;
  }
  r = RVPhase3CallExport("KernelHeapProbe");
  if (r != 64) {
    RVPhase3UartI64("RVPhase3: RedSea Kernel.BIN KernelHeapProbe FAILED r=", r);
    return FALSE;
  }
  r = RVPhase3CallExport("KernelSoftCall");
  if (r != 0x4B53) {
    RVPhase3UartI64("RVPhase3: RedSea Kernel.BIN SoftCall FAILED r=", r);
    return FALSE;
  }
  if (!FileFind("A:/Kernel/SOFTFW.OK")) {
    RVPhase3Uart("RVPhase3: RedSea Kernel.BIN SoftCall FileWrite SOFTFW.OK missing.\n");
    return FALSE;
  }
  if (!FileFind("A:/Kernel/BLKIO.OK")) {
    RVPhase3Uart("RVPhase3: RedSea Kernel.BIN SoftCall BlkDev BLKIO.OK missing.\n");
    return FALSE;
  }
  FileWrite("A:/Kernel/ENTRY.OK", "KE", 2);
  FileWrite("A:/Kernel/SEED.OK", "OK", 2);
  FileWrite("A:/Kernel/SOFT.OK", "KS", 2);
  rv_phase3_kernel_seed_ok = TRUE;
  RVPhase3Uart("RVPhase3: RedSea Kernel.BIN seed FileFind+Load OK (KernelProbe=42).\n");
  RVPhase3Uart("RVPhase3: RedSea Kernel.BIN KernelEntry handoff OK (0x4B45).\n");
  RVPhase3Uart("RVPhase3: RedSea Kernel.BIN InitLite OK (magic+HeapProbe=64).\n");
  RVPhase3Uart("RVPhase3: RedSea Kernel.BIN SoftCall OK (BIN ENTER+VBlk+mount/FS=0x4B53).\n");
  return TRUE;
}

Bool RVPhase3LoadCompiler()
{
#ifdef RV_PHASE3_LOADED_CMP_ONLY
  //G9: no in-image Body — bootstrap is LoadFullCompiler (linked seed → RedSea).
  return RVPhase3LoadFullCompiler();
#else
  I64 probe;
  RVPhase3Uart("RVPhase3: loading Compiler_RV (in-image stand-in for Load)...\n");
  CInit;
  if (adam_task && cmp.asm_hash)
    adam_task->hash_table->next = cmp.asm_hash;
  if (!HashFind("I64", cmp.asm_hash, HTT_INTERNAL_TYPE, 1)) {
    RVPhase3Uart("RVPhase3: Compiler_RV CInit FAILED (no I64 type).\n");
    return FALSE;
  }
  probe = ExePutS("40+2;\n");
  if (probe != 42) {
    RVPhase3Uart("RVPhase3: Compiler_RV probe ExePutS(40+2) FAILED.\n");
    return FALSE;
  }
  rv_phase3_compiler_ok = TRUE;
  DirMk("A:/Compiler");
  FileWrite("A:/Compiler/LOADED.TXT", "Compiler_RV", 11);
  RVPhase3Uart("RVPhase3: Compiler_RV loaded (CInit + ExePutS 40+2=42).\n");
  return TRUE;
#endif
}

Bool RVPhase3LoadBin()
{
  U8 code[16];
  U8 *bin, *mod;
  I64 bin_sz = 0, val;
  CBinFile *bfh;
  CHashExport *tmpex;
  if (!rv_phase3_compiler_ok)
    return FALSE;
  RVPhase3Uart("RVPhase3: packing TOSB CBinFile...\n");
  // Register export for IET_IMM_I64 (same shape as LoadPass1 heap exports).
  tmpex = CAlloc(sizeof(CHashExport));
  tmpex->type = HTT_EXPORT_SYS_SYM | HTF_IMM;
  tmpex->str = StrNew("RVPatchMe");
  tmpex->val = 0x1122334455667788;
  HashAdd(tmpex, Fs->hash_table);
  if (!HashFind("RVPatchMe", Fs->hash_table, HTT_EXPORT_SYS_SYM)) {
    RVPhase3Uart("RVPhase3: HashAdd RVPatchMe failed.\n");
    return FALSE;
  }
  if (!HashFind("RVPatchMe", Fs->hash_table, HTG_ALL - HTT_IMPORT_SYS_SYM)) {
    RVPhase3Uart("RVPhase3: RVPatchMe mask HTG_ALL-IMPORT miss.\n");
    return FALSE;
  }
  // li a0,42; ret; then 8-byte import slot (IET_IMM_I64 "RVPatchMe")
  code[0] = 0x13;
  code[1] = 0x05;
  code[2] = 0xA0;
  code[3] = 0x02;
  code[4] = 0x67;
  code[5] = 0x80;
  code[6] = 0x00;
  code[7] = 0x00;
  MemSet(code + 8, 0, 8);
  bin = RVPackTOSB(code, 16, &bin_sz);
  DirMk("A:/Compiler");
  FileWrite("A:/Compiler/Hello.BIN", bin, bin_sz);
  Free(bin);
  RVPhase3Uart("RVPhase3: wrote A:/Compiler/Hello.BIN; calling Load...\n");
  bfh = Load("A:/Compiler/Hello.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: Load() CBinFile FAILED.\n");
    return FALSE;
  }
  mod = bfh(U8 *) + sizeof(CBinFile);
  RVPhase3Uart("RVPhase3: Load() parsed TOSB; Call entry...\n");
  val = Call(mod);
  if (val != 42) {
    RVPhase3Uart("RVPhase3: Load() module Call entry FAILED.\n");
    return FALSE;
  }
  if (mod(I64 *)[1] != 0x1122334455667788) {
    RVPhase3Uart("RVPhase3: Load() import RVPatchMe FAILED.\n");
    return FALSE;
  }
  tmpex = HashFind("RVHello", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex) {
    RVPhase3Uart("RVPhase3: Load() export RVHello MISSING.\n");
    return FALSE;
  }
  val = Call(tmpex->val);
  if (val != 42) {
    RVPhase3Uart("RVPhase3: Load() export RVHello Call FAILED.\n");
    return FALSE;
  }
  rv_phase3_load_ok = TRUE;
  FileWrite("A:/Compiler/BINOK.TXT", "TOSB", 4);
  RVPhase3Uart("RVPhase3: Load() CBinFile OK (TOSB Hello + export/import patch).\n");
  return TRUE;
}

Bool RVPhase3LoadHostBin()
{
#ifdef RV_PHASE3_LOADED_CMP_ONLY
  //G9: HostBinEmbed dropped — prove RedSea stage of full Compiler.BIN seed.
  CHashExport *tmpex;
  I64 sz = 0;
  U8 *back;
  if (!rv_phase3_fullcmp_ok)
    return FALSE;
  if (!FileFind("A:/Compiler/Compiler.BIN")) {
    RVPhase3Uart("RVPhase3: RedSea Compiler.BIN seed missing.\n");
    return FALSE;
  }
  back = FileRead("A:/Compiler/Compiler.BIN", &sz, NULL);
  if (!back || sz < sizeof(CBinFile)) {
    if (back)
      Free(back);
    RVPhase3Uart("RVPhase3: RedSea Compiler.BIN read FAILED.\n");
    return FALSE;
  }
  Free(back);
  tmpex = HashFind("Cmp", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex)
    tmpex = HashFind("Cmp", Fs->hash_table, HTT_FUN);
  if (!tmpex) {
    RVPhase3Uart("RVPhase3: host Compiler.BIN export Cmp MISSING.\n");
    return FALSE;
  }
  no_warn tmpex;
  rv_phase3_hostbin_ok = TRUE;
  FileWrite("A:/Compiler/HOSTBIN.TXT", "HOST", 4);
  RVPhase3Uart("RVPhase3: Load() host Compiler.BIN OK (RedSea seed + Cmp export).\n");
  return TRUE;
#else
  //Stage host-packed TOSB as A:/Compiler/Compiler.BIN and Load it.
  // Embed is a tiny AOT probe (RVCmpProbe→7) from tools/pack_tosb;
  // full Compiler_RV → build/Compiler.BIN on the host (97 IET_IMM_I64 imports).
  CBinFile *bfh;
  CHashExport *tmpex;
  I64 val;
  if (!rv_phase3_compiler_ok)
    return FALSE;
  if (rv_host_bin_size <= 0) {
    RVPhase3Uart("RVPhase3: host Compiler.BIN embed missing.\n");
    return FALSE;
  }
  DirMk("A:/Compiler");
  FileWrite("A:/Compiler/Compiler.BIN", rv_host_bin, rv_host_bin_size);
  RVPhase3Uart("RVPhase3: wrote A:/Compiler/Compiler.BIN (host pack_tosb); Load...\n");
  bfh = Load("A:/Compiler/Compiler.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: Load() host Compiler.BIN FAILED.\n");
    return FALSE;
  }
  tmpex = HashFind("RVCmpProbe", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex) {
    RVPhase3Uart("RVPhase3: host Compiler.BIN export RVCmpProbe MISSING.\n");
    return FALSE;
  }
  val = Call(tmpex->val);
  if (val != 7) {
    RVPhase3Uart("RVPhase3: host Compiler.BIN RVCmpProbe FAILED.\n");
    return FALSE;
  }
  rv_phase3_hostbin_ok = TRUE;
  FileWrite("A:/Compiler/HOSTBIN.TXT", "HOST", 4);
  RVPhase3Uart("RVPhase3: Load() host Compiler.BIN OK (pack_tosb + RVCmpProbe).\n");
  return TRUE;
#endif
}

Bool RVPhase3LoadFullCompiler()
{
  //Load full Compiler_RV TOSB (97 imports); CInit + loaded ExePutS as live JIT.
  // G9: prefer RedSea A:/Compiler/Compiler.BIN via heap Load() — host AOT is
  // PC-rel (auipc), so the seed is relocatable (no IET_ABS_ADDR). Linked
  // 0x81000000 is optional last-resort byte source (PHASE3_LINK_COMPILER_BIN).
  CBinFile *src, *bfh, *red;
  CHashExport *tmpex, *tmpex_eps, *tmpex_cmp;
  I64 n, val, sz = 0, red_sz = 0, cinit_addr, exeps_addr;
  U8 *probe, *red_buf = NULL;
  Bool prefer_redsea = FALSE, have_linked = FALSE, used_reloc = FALSE;
  if (rv_phase3_fullcmp_ok)
    return TRUE;
#ifndef RV_PHASE3_LOADED_CMP_ONLY
  if (!rv_phase3_compiler_ok)
    return FALSE;
#endif
  src = 0x81000000(CBinFile *);
  // link_exepubs.ld .compiler_bin — optional; smoke default omits compiler_full.o.
  if (src->bin_signature == BIN_SIGNATURE_VAL) {
    sz = src->file_size;
    if (sz >= sizeof(CBinFile) && sz <= 0x400000)
      have_linked = TRUE;
  }
  DirMk("A:/Compiler");
  if (FileFind("A:/Compiler/Compiler.BIN")) {
    red_buf = FileRead("A:/Compiler/Compiler.BIN", &red_sz, NULL);
    if (red_buf && red_sz >= sizeof(CBinFile)) {
      red = red_buf(CBinFile *);
      if (red->bin_signature == BIN_SIGNATURE_VAL && (!have_linked || red_sz == sz)) {
        prefer_redsea = TRUE;
        sz = red_sz;
      }
    }
  }
  if (!prefer_redsea) {
    if (!have_linked) {
      if (red_buf)
        Free(red_buf);
      RVPhase3Uart("RVPhase3: full Compiler.BIN missing (no RedSea, no 0x81000000).\n");
      return FALSE;
    }
    FileWrite("A:/Compiler/Compiler.BIN", src, sz);
    FileWrite("A:/Compiler/FULLBIN.MARK", "FULL", 4);
    RVPhase3Uart("RVPhase3: staged A:/Compiler/Compiler.BIN (ELF .compiler_bin fallback).\n");
  } else {
    FileWrite("A:/Compiler/FULLBIN.MARK", "FULL", 4);
    RVPhase3Uart("RVPhase3: prefer A:/Compiler/Compiler.BIN (RedSea seed; heap Load).\n");
  }
  if (red_buf)
    Free(red_buf);
  n = RVCmpExportImports();
  no_warn n;
  RVPhase3Uart("RVPhase3: exported imports; Load() RedSea Compiler.BIN (reloc)...\n");
  /* G9: heap Load from RedSea — live Cmp must not require fixed VMA. */
  bfh = Load("A:/Compiler/Compiler.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
    used_reloc = TRUE;
    RVPhase3Uart("RVPhase3: Load() relocatable RedSea Compiler.BIN returned.\n");
  } else if (have_linked) {
    /* Fallback: in-place LoadPass at linked VMA (writable .compiler_bin). */
    RVPhase3Uart("RVPhase3: reloc Load failed; fallback LoadPass @0x81000000.\n");
    bfh = LoadPass(src, sz, "A:/Compiler/Compiler", LDF_JUST_LOAD | LDF_SILENT, src);
    RVPhase3Uart("RVPhase3: LoadPass returned.\n");
  }
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: Load full Compiler.BIN FAILED.\n");
    return FALSE;
  }
  tmpex = HashFind("CInit", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  tmpex_eps = HashFind("ExePutS", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  tmpex_cmp = HashFind("Cmp", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex_cmp)
    tmpex_cmp = HashFind("Cmp", Fs->hash_table, HTT_FUN);
  if (!tmpex || !tmpex_eps) {
    RVPhase3Uart("RVPhase3: full Compiler.BIN export CInit/ExePutS MISSING.\n");
    return FALSE;
  }
  if (!tmpex_cmp) {
    RVPhase3Uart("RVPhase3: full Compiler.BIN export Cmp MISSING.\n");
    return FALSE;
  }
  cinit_addr = tmpex->val;
  exeps_addr = tmpex_eps->val;
  if (tmpex_cmp->type & HTT_FUN)
    rv_phase3_loaded_cmp = tmpex_cmp(CHashFun *)->exe_addr;
  else
    rv_phase3_loaded_cmp = tmpex_cmp->val;
  /* Host AOT blob has its own Fs/adam_task/char_bmp_* globals (PC-rel data). Point
   * them at live Adam / kernel bitmaps before Call(CInit). */
  if (RV_CMP_FS_OFF) {
    U8 *mod = bfh(U8 *) + sizeof(CBinFile);
    (mod + RV_CMP_FS_OFF)(CTask **) = Fs;
    if (RV_CMP_ADAM_TASK_OFF)
      (mod + RV_CMP_ADAM_TASK_OFF)(CTask **) = adam_task;
    if (RV_CMP_GS_OFF && Gs)
      (mod + RV_CMP_GS_OFF)(CCPU **) = Gs;
    if (RV_CMP_BLKDEV_OFF)
      MemCpy(mod + RV_CMP_BLKDEV_OFF, &blkdev, sizeof(CBlkDevGlbls));
    RVCmpPatchCharBmps(mod);
  }
  RVPhase3Uart("RVPhase3: calling loaded CInit...\n");
  Call(cinit_addr);
  RVPhase3Uart("RVPhase3: loaded CInit returned; ExePutS via funptr...\n");
  // Funptr call (Call() is no-arg). Loaded ExePutS uses module-local cmp after CInit.
  probe = "40+2;\n";
  
  {
    // Funptr calls do not apply HolyC default args — pass all four.
    I64 (*loaded_exeps)(U8 *buf, U8 *filename, I64 ccf_flags, CLexHashTableContext *htc) = exeps_addr;
    RVPhase3Uart("RVPhase3: enter loaded ExePutS...\n");
    val = (*loaded_exeps)(probe, NULL, 0, NULL);
    RVPhase3Uart("RVPhase3: loaded ExePutS returned.\n");
  }
  if (val != 42) {
    RVPhase3Uart("RVPhase3: loaded ExePutS(40+2) FAILED.\n");
    return FALSE;
  }
  // Libs-first AFTER live Cmp probe: plant HTT_FUN + re-patch Kernel HOFYIMP1
  // (CmpCtrl*/Wire/Exe*). Do not touch Kernel GOTs before CInit/ExePutS.
  // Assign after ExePutS — HolyC AOT can hoist side-effectful local inits to
  // function entry (plant-before-CInit hung Load).
  
  {
    I64 n_plant;
    I64 n_hofy;
    U0 (*wire_asm)();
    n_plant = RVCmpPlantLoadedCmpFuns();
    n_hofy = RVHofyRepatchFromHash();
    RVPhase3UartI64("RVPhase3: planted Cmp HTT_FUN n=", n_plant);
    RVPhase3UartI64("RVPhase3: HOFYIMP1 re-patch n=", n_hofy);
    wire_asm = RVHofyExportVal("RVCmpWireAsmHash");
    if (wire_asm)
      (*wire_asm)();
  }
  rv_phase3_fullcmp_ok = TRUE;
  rv_phase3_compiler_ok = TRUE;
  FileWrite("A:/Compiler/FULLBIN.TXT", "FULL", 4);
  FileWrite("A:/Compiler/LOADED.TXT", "Compiler_RV", 11);
  if (used_reloc)
    FileWrite("A:/Compiler/RELOC.TXT", "RELOC", 5);
  RVPhase3Uart("RVPhase3: Compiler_RV loaded (CInit + ExePutS 40+2=42).\n");
  if (used_reloc)
    RVPhase3Uart("RVPhase3: Load() full Compiler.BIN OK (reloc RedSea + ExePutS).\n");
  else
    RVPhase3Uart("RVPhase3: Load() full Compiler.BIN OK (fixed VMA fallback + ExePutS).\n");
  return TRUE;
}

Bool RVPhase3MakeOS()
{
  //Guest Cmp → BIN → Load → Call (MakeAll / BootHDIns closed loop). No hand TOSB.
  U8 *src, *praw;
  I64 val, psz = 0;
  U8 msg[96];
  CBinFile *bfh, *ph;
  if (!rv_phase3_compiler_ok)
    return FALSE;
  RVPhase3Uart("RVPhase3: MakeOS staging A:/MakeOS/Tiny...\n");
  DirMk("A:/MakeOS");
  src = "public I64 MakeOSProbe()\n" "{\n" "  return 42;\n" "}\n";
  FileWrite("A:/MakeOS/Tiny.HC", src, StrLen(src));
  FileWrite("A:/MakeOS/Tiny.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: MakeOS staged; calling Cmp...\n");
  RVPhase3Uart("RVPhase3: MakeOS Cmp(A:/MakeOS/Tiny.PRJ)...\n");
  if (!RVPhase3CmpWrite("A:/MakeOS/Tiny.PRJ", "A:/MakeOS/Tiny.BIN", "RVPhase3: MakeOS Cmp FAILED (no Tiny.BIN).\n"))
    return FALSE;
  RVPhase3Uart("RVPhase3: MakeOS Cmp wrote Tiny.BIN; Load...\n");
  praw = FileRead("A:/MakeOS/Tiny.BIN", &psz, NULL);
  if (praw && psz >= sizeof(CBinFile)) {
    ph = praw(CBinFile *);
    StrPrint(msg, "RVPhase3: Tiny.BIN size=%d patch_off=%d et0=%d\n", psz, ph->patch_table_offset, (ph->patch_table_offset < psz) ? praw[ph->patch_table_offset] : -1);
    RVPhase3Uart(msg);
  }
  Free(praw);
  bfh = Load("A:/MakeOS/Tiny.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: MakeOS Load Tiny.BIN FAILED.\n");
    return FALSE;
  }
  val = RVPhase3CallExport("MakeOSProbe");
  if (val != 42) {
    RVPhase3Uart("RVPhase3: MakeOS Load+Call FAILED.\n");
    return FALSE;
  }
  FileWrite("A:/MakeOS/MAKEOS.OK", "OK", 2);
  FileWrite("A:/Compiler/GUEST_CMP.OK", "OK", 2);
  rv_phase3_makeos_ok = TRUE;
  RVPhase3Uart("RVPhase3: MakeOS OK (Cmp→BIN→Load→Call MakeOSProbe=42).\n");
  return TRUE;
}

Bool RVPhase3GuestRuntime()
{
  //P3 wedge: guest Cmp builds Runtime + StartOS BINs that StartOS Loads (not host AOT).
  U8 *src, *back, *prj;
  I64 val, sz;
  CBinFile *bfh;
  CHashExport *tmpex;
  if (!rv_phase3_makeos_ok)
    return FALSE;
  RVPhase3Uart("RVPhase3: Runtime staging A:/Runtime/Seed...\n");
  DirMk("A:/Runtime");
  // Multi-fun + #include + F()+imm (call result then +27).
  src = "public I64 RuntimeSeedVal()\n" "{\n" "  return 15;\n" "}\n";
  FileWrite("A:/Runtime/SeedLib.HC", src, StrLen(src));
  src = "#include \"A:/Runtime/SeedLib.HC\"\n" "public I64 RuntimeSeedInit()\n" "{\n" "  return RuntimeSeedVal+27;\n" "}\n";
  FileWrite("A:/Runtime/Seed.HC", src, StrLen(src));
  FileWrite("A:/Runtime/Seed.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: Runtime Cmp(A:/Runtime/Seed.PRJ)...\n");
  if (!RVPhase3CmpWrite("A:/Runtime/Seed.PRJ", "A:/Runtime/Seed.BIN", "RVPhase3: Runtime Cmp FAILED (no Seed.BIN).\n"))
    return FALSE;
  RVPhase3Uart("RVPhase3: Runtime Load Seed.BIN...\n");
  bfh = Load("A:/Runtime/Seed.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: Runtime Seed.BIN Load FAILED.\n");
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: Runtime Call RuntimeSeedInit...\n");
  val = RVPhase3CallExport("RuntimeSeedInit");
  if (val != 42) {
    RVPhase3UartI64("RVPhase3: Runtime Seed Load+Call FAILED r=", val);
    return FALSE;
  }
  FileWrite("A:/Runtime/SEED.OK", "OK", 2);
  rv_phase3_runtime_ok = TRUE;
  RVPhase3Uart("RVPhase3: Runtime OK (Cmp→Seed.BIN call+imm→Load→Call=42).\n");
  // Svc.BIN — second guest module StartOS Loads (Seed-shaped multi-fun + #include).
  RVPhase3Uart("RVPhase3: Runtime staging A:/Runtime/Svc...\n");
  src = "public I64 RuntimeSvcVal()\n" "{\n" "  return 42;\n" "}\n";
  FileWrite("A:/Runtime/SvcLib.HC", src, StrLen(src));
  src = "#include \"A:/Runtime/SvcLib.HC\"\n" "public I64 RuntimeSvcProbe()\n" "{\n" "  return RuntimeSvcVal;\n" "}\n";
  FileWrite("A:/Runtime/Svc.HC", src, StrLen(src));
  FileWrite("A:/Runtime/Svc.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: Runtime Cmp(A:/Runtime/Svc.PRJ)...\n");
  if (!RVPhase3CmpWrite("A:/Runtime/Svc.PRJ", "A:/Runtime/Svc.BIN", "RVPhase3: Runtime Svc Cmp FAILED.\n"))
    return FALSE;
  RVPhase3Uart("RVPhase3: Runtime Svc.BIN ready for StartOS Load.\n");
  // Kern.BIN — arg call with n+n+n (reg-arg multi-use; was ADD clobber).
  RVPhase3Uart("RVPhase3: Runtime staging A:/Runtime/Kern...\n");
  src = "public I64 KernScale(I64 n)\n" "{\n" "  return n+n+n;\n" "}\n";
  FileWrite("A:/Runtime/KernMem.HC", src, StrLen(src));
  src = "#include \"A:/Runtime/KernMem.HC\"\n" "public I64 KernBase()\n" "{\n" "  return 15;\n" "}\n" "public I64 KernInit()\n" "{\n" "  return KernBase+KernScale(9);\n" "}\n";
  FileWrite("A:/Runtime/Kern.HC", src, StrLen(src));
  FileWrite("A:/Runtime/Kern.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: Runtime Cmp(A:/Runtime/Kern.PRJ)...\n");
  if (!RVPhase3CmpWrite("A:/Runtime/Kern.PRJ", "A:/Runtime/Kern.BIN", "RVPhase3: Runtime Kern Cmp FAILED.\n"))
    return FALSE;
  RVPhase3Uart("RVPhase3: Runtime Load Kern.BIN...\n");
  bfh = Load("A:/Runtime/Kern.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: Runtime Kern.BIN Load FAILED.\n");
    return FALSE;
  }
  val = RVPhase3CallExport("KernInit");
  if (val != 42) {
    RVPhase3UartI64("RVPhase3: Runtime Kern Call FAILED r=", val);
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: Runtime Kern.BIN OK (n+n+n arg+call→42).\n");
  // G9: prefer host-staged RedSea A:/Kernel/Kernel.BIN (Boot.DD shape) over
  // guest Cmp rebuild. Probe until guest Cmp can rebuild real Kernel_RV.
  // Early RVPhase3ProbeSeedKernel already FileFind+Load'd the seed.
  RVPhase3Uart("RVPhase3: Runtime staging A:/Kernel/Kernel.BIN...\n");
  DirMk("A:/Kernel");
  if (FileFind("A:/Kernel/Kernel.BIN") && rv_phase3_kernel_seed_ok) {
    FileWrite("A:/Kernel/KERNEL.OK", "OK", 2);
    RVPhase3Uart("RVPhase3: Runtime Kernel.BIN ready (RedSea seed; preferred over guest Cmp rebuild).\n");
  } else {
    src = "public I64 KernelProbe()\n" "{\n" "  return 42;\n" "}\n";
    FileWrite("A:/Kernel/Kernel.HC", src, StrLen(src));
    FileWrite("A:/Kernel/Kernel.PRJ", src, StrLen(src));
    RVPhase3Uart("RVPhase3: Runtime Cmp(A:/Kernel/Kernel.PRJ)...\n");
    if (!RVPhase3CmpWrite("A:/Kernel/Kernel.PRJ", "A:/Kernel/Kernel.BIN", "RVPhase3: Runtime Kernel Cmp FAILED.\n"))
      return FALSE;
    FileWrite("A:/Kernel/KERNEL.OK", "OK", 2);
    RVPhase3Uart("RVPhase3: Runtime Kernel.BIN ready (guest Cmp fallback; preferred over Mac scaffold).\n");
  }
  // Adam/StartOS.BIN — guest-built StartOS body (boot prefers Load over host ExeFile).
  RVPhase3Uart("RVPhase3: Runtime staging A:/Adam/StartOS...\n");
  DirMk("A:/Adam");
  src = "public I64 StartOSProbe()\n" "{\n" "  return 1;\n" "}\n";
  FileWrite("A:/Adam/StartOS.HC", src, StrLen(src));
  FileWrite("A:/Adam/StartOS.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: Runtime Cmp(A:/Adam/StartOS.PRJ)...\n");
  if (!RVPhase3CmpWrite("A:/Adam/StartOS.PRJ", "A:/Adam/StartOS.BIN", "RVPhase3: Runtime StartOS Cmp FAILED.\n"))
    return FALSE;
  RVPhase3Uart("RVPhase3: Runtime StartOS.BIN ready for StartOS Load.\n");
  // AdamCore: CALL_IMPORT via in-blob _RV_HC_CALL veneer → host HolyC / FileWrite.
  // RVRet42 sits 28 bytes after _RV_HC_CALL (FP-2048 veneer, no post-SP fix).
  RVCmpExportOne("RVHCCall", &_RV_HC_CALL);
  RVCmpExportOne("RVRet42", (I64)(&_RV_HC_CALL) + 28);
  RVCmpExportOne("RVHCRet41", &RVHCRet41);
  RVCmpExportOne("RVHCAdd1", &RVHCAdd1);
  RVPhase3UartI64("RVPhase3: RVHCCall=", &_RV_HC_CALL);
  RVPhase3UartI64("RVPhase3: RVRet42=", (I64)(&_RV_HC_CALL) + 28);
  RVPhase3UartI64("RVPhase3: RVHCRet41=", &RVHCRet41);
  RVPhase3Uart("RVPhase3: Runtime staging A:/Adam/AdamCore...\n");
  // Guest FileWrite multi-STR (RTL remat) plants READY+CORE without MakeAdam.
  src = MStrPrint("import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);\n" "public I64 AdamRVCoreInit()\n" "{\n" "  FileWrite(\"A:/Adam/READY.TXT\",\"Adam\",4);\n" "  FileWrite(\"A:/Adam/CORE.TXT\",\"MakeAdam_RV_Core\",16);\n" "  return 1;\n" "}\n");
  RVPhase3UartI64("RVPhase3: AdamCore src len=", StrLen(src));
  FileWrite("A:/Adam/AdamCore.HC", src, StrLen(src));
  FileWrite("A:/Adam/AdamCore.PRJ", src, StrLen(src));
  Free(src);
  RVPhase3Uart("RVPhase3: Runtime Cmp(A:/Adam/AdamCore.PRJ)...\n");
  if (!RVPhase3CmpWrite("A:/Adam/AdamCore.PRJ", "A:/Adam/AdamCore.BIN", "RVPhase3: Runtime AdamCore Cmp FAILED.\n"))
    return FALSE;
  RVPhase3Uart("RVPhase3: Runtime AdamCore.BIN ready for StartOS Load.\n");
  // P6 soft (G9): stage in-tree Menu_RV_Guest + Menu_RV wrap (MENU_RV_GUEST_CMP).
  // Guest Cmp MakeAdam_RV_Lite `#include "Menu_RV"` → nested Guest. Soft — no Runtime fail.
  // PopUp_RV / DolDoc / full MakeAdam_RV / CMenu still blocked; do not claim P6 done.
  RVPhase3Uart("RVPhase3: Runtime staging A:/Adam/Menu_RV.HC (P6 soft in-tree Guest)...\n");
  // Str*/Mem* already in RVCmpExportImports; re-export FileWrite/DirMk for CALL_IMPORT.
  RVCmpExportOne("FileWrite", &FileWrite);
  RVCmpExportOne("DirMk", &DirMk);
  RVCmpExportOne("StrCpy", &RVStrCpy);
  RVCmpExportOne("StrLen", &RVStrLen);
  RVCmpExportOne("StrCmp", &RVStrCmp);
  RVCmpExportOne("MemSet", &RVMemSet);
  // Stage Guest_Lex early (files only). Honest Cmp after Soft Calls — early
  // Cmp still races Soft Calls; keep files-only here.
  RVPhase3Uart("RVPhase3: P6 staging Menu_RV_Guest_Lex src (early)...\n");
  src = RVAdamLiteMenuLexSrc();
  RVPhase3UartI64("RVPhase3: P6 LexSrc len=", StrLen(src));
  FileWrite("A:/Adam/Menu_RV_Guest_Lex.HC", src, StrLen(src));
  FileWrite("A:/Adam/LiteMenuLex.PRJ", src, StrLen(src));
  // Soft bisect G8 surfaces (class / StrCpy-glbl / U0 DirMk / nested include).
  src = "#ifndef MENU_RV_HC\n#define MENU_RV_HC\n" "#define RV_MENU_N 8\n" "public I64 AdamLiteDefProbe()\n" "{\n" "  return RV_MENU_N;\n" "}\n" "#endif\n";
  FileWrite("A:/Adam/LiteDef.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteDef.PRJ", "A:/Adam/LiteDef.BIN", "RVPhase3: P6 bisect ifndef/define BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — ifndef/define FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — ifndef/define OK.\n");
  RVPhase3Uart("RVPhase3: P6 bisect — class Cmp...\n");
  src = "class CRVMenuEnt { I64 id; };\n" "public I64 AdamLiteClassProbe()\n" "{\n" "  return sizeof(CRVMenuEnt);\n" "}\n";
  FileWrite("A:/Adam/LiteClass.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: P6 bisect — class(I64) Cmp start\n");
  if (!RVPhase3CmpWrite("A:/Adam/LiteClass.PRJ", "A:/Adam/LiteClass.BIN", "RVPhase3: P6 bisect class(I64) BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — class(I64) FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — class(I64) OK.\n");
  src = "class CRVMenuEnt2\n" "{\n" "  U8 name[24];\n" "  I64 id;\n" "};\n";
  FileWrite("A:/Adam/LiteClass2.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: P6 bisect — class(U8[]) parse-only Cmp start\n");
  if (!RVPhase3CmpWrite("A:/Adam/LiteClass2.PRJ", "A:/Adam/LiteClass2.BIN", "RVPhase3: P6 bisect class(U8[]) parse BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — class(U8[]) parse FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — class(U8[]) parse OK.\n");
  src = "U8 g_name[24];\n" "public I64 AdamLiteArrProbe()\n" "{\n" "  return 1;\n" "}\n";
  FileWrite("A:/Adam/LiteArrOnly.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: P6 bisect — U8 glbl[24] Cmp start\n");
  if (!RVPhase3CmpWrite("A:/Adam/LiteArrOnly.PRJ", "A:/Adam/LiteArrOnly.BIN", "RVPhase3: P6 bisect U8[] glbl BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — U8[] glbl FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — U8[] glbl OK.\n");
  src = "class CRVMenuEnt2\n" "{\n" "  U8 name[24];\n" "  I64 id;\n" "};\n" "public I64 AdamLiteClass2Probe()\n" "{\n" "  return sizeof(CRVMenuEnt2);\n" "}\n";
  FileWrite("A:/Adam/LiteClass2b.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: P6 bisect — class(U8[])+sizeof Cmp start\n");
  if (!RVPhase3CmpWrite("A:/Adam/LiteClass2b.PRJ", "A:/Adam/LiteClass2b.BIN", "RVPhase3: P6 bisect class(U8[])+sizeof BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — class(U8[])+sizeof FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — class(U8[])+sizeof OK.\n");
  src = "class CRVMenuEnt3\n" "{\n" "  U8 name[24];\n" "  I64 id;\n" "};\n" "CRVMenuEnt3 g_ent;\n" "public I64 AdamLiteClass3Probe()\n" "{\n" "  return sizeof(CRVMenuEnt3);\n" "}\n";
  FileWrite("A:/Adam/LiteClass3.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: P6 bisect — class+glbl Cmp start\n");
  if (!RVPhase3CmpWrite("A:/Adam/LiteClass3.PRJ", "A:/Adam/LiteClass3.BIN", "RVPhase3: P6 bisect class+glbl BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — class+glbl FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — class+glbl OK.\n");
  RVPhase3Uart("RVPhase3: P6 bisect — StrCpy-glbl Cmp...\n");
  src = "import U8 *StrCpy(U8 *dst,U8 *src);\n" "public I64 AdamLiteStrProbe()\n" "{\n" "  U8 name[24];\n" "  StrCpy(name,\"TileHorz\");\n" "  return 8;\n" "}\n";
  FileWrite("A:/Adam/LiteStr.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteStr.PRJ", "A:/Adam/LiteStr.BIN", "RVPhase3: P6 bisect StrCpy BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — StrCpy FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — StrCpy OK.\n");
  RVPhase3Uart("RVPhase3: P6 bisect — DirMk+FileWrite Cmp...\n");
  src = "import Bool DirMk(U8 *filename,I64 entry_cnt=0);\n" "import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);\n" "public I64 AdamLiteDirProbe()\n" "{\n" "  DirMk(\"A:/Adam\");\n" "  FileWrite(\"A:/Adam/DIRMK.TXT\",\"ok\",2);\n" "  return 1;\n" "}\n";
  FileWrite("A:/Adam/LiteDir.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteDir.PRJ", "A:/Adam/LiteDir.BIN", "RVPhase3: P6 bisect DirMk BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — DirMk FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — DirMk Cmp OK.\n");
  // Span repro: DirMk("A:/Span") hung on RAM-disk / stub Fs (SpanRead soft-skip).
  RVPhase3Uart("RVPhase3: P6 bisect — DirMk A:/Span Cmp...\n");
  src = "import Bool DirMk(U8 *filename,I64 entry_cnt=0);\n" "import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);\n" "public I64 AdamLiteSpanDirProbe()\n" "{\n" "  DirMk(\"A:/Span\");\n" "  FileWrite(\"A:/Span/GAME.TXT\",\"SPAN\",4);\n" "  return 1;\n" "}\n";
  FileWrite("A:/Adam/LiteSpanDir.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteSpanDir.PRJ", "A:/Adam/LiteSpanDir.BIN", "RVPhase3: P6 bisect DirMk A:/Span BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — DirMk A:/Span FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — DirMk A:/Span Cmp OK.\n");
  // Soft: empty U0 Call (was hang trigger) + scalar-glbl ABS_ADDR R/W.
  RVPhase3Uart("RVPhase3: P6 bisect — empty U0 Cmp...\n");
  src = "public U0 AdamLiteU0Init()\n{\n}\n" "public I64 AdamLiteU0Probe()\n" "{\n" "  AdamLiteU0Init;\n" "  return 1;\n" "}\n";
  FileWrite("A:/Adam/LiteU0.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteU0.PRJ", "A:/Adam/LiteU0.BIN", "RVPhase3: P6 bisect empty U0 BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — empty U0 FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — empty U0 Cmp OK.\n");
  RVPhase3Uart("RVPhase3: P6 bisect — scalar-glbl ABS_ADDR Cmp...\n");
  src = "I64 g_lite_n;\n" "public U0 AdamLiteScalarInit()\n" "{\n" "  g_lite_n=8;\n" "}\n" "public I64 AdamLiteScalarProbe()\n" "{\n" "  AdamLiteScalarInit;\n" "  return g_lite_n;\n" "}\n";
  FileWrite("A:/Adam/LiteScalar.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteScalar.PRJ", "A:/Adam/LiteScalar.BIN", "RVPhase3: P6 bisect scalar-glbl BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — scalar-glbl FAIL.\n");
  else {
    RVPhase3Uart("RVPhase3: P6 bisect — scalar-glbl Cmp OK.\n");
    // Early Soft Call/Dump deferred — Call after Dump hung Menu fold proof.
    // Scalar Soft Call still runs in StartOS (later). Sibling owns DumpLiteScalar.
    RVPhase3Uart("RVPhase3: P6 bisect — scalar early Soft Call soft-skip (Menu fold).\n");
  }
  // Soft: Menu Lex Soft Call — StrCpy→glbl U8[] then g_lex_buf[0] ('T').
  // Fixed: CALL_IMPORT typed remat now reverses COCPush RTL args (was LTR
  // swap for StrCpy). Soft bisects Asg/Cpy/Seed remain as regression probes.
  // Full in-tree Menu_RV.HC (CMenu/CCmpCtrl) still host/WinMgr.
  RVPhase3Uart("RVPhase3: P6 bisect — Menu hand Lex Cmp...\n");
  src = "import U8 *StrCpy(U8 *dst,U8 *src);\n" "U8 g_lex_buf[40];\n" "public I64 AdamLiteLexProbe()\n" "{\n" "  StrCpy(g_lex_buf,\"TileHorz\");\n" "  return g_lex_buf[0];\n" "}\n";
  FileWrite("A:/Adam/LiteLex.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteLex.PRJ", "A:/Adam/LiteLex.BIN", "RVPhase3: P6 bisect Menu Lex BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Menu Lex FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Menu Lex Cmp OK.\n");
  // H1: glbl U8[] assign+load without StrCpy (isolate elem store/load).
  RVPhase3Uart("RVPhase3: P6 bisect — Lex U8 assign Cmp...\n");
  src = "U8 g_lex_asg[40];\n" "public I64 AdamLiteLexAsgProbe()\n" "{\n" "  g_lex_asg[0]='T';\n" "  return g_lex_asg[0];\n" "}\n";
  FileWrite("A:/Adam/LiteLexAsg.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteLexAsg.PRJ", "A:/Adam/LiteLexAsg.BIN", "RVPhase3: P6 bisect Lex U8 assign BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Lex U8 assign FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Lex U8 assign Cmp OK.\n");
  // H2: StrCpy→glbl then return const (isolate CALL_IMPORT remat hang vs write).
  RVPhase3Uart("RVPhase3: P6 bisect — Lex StrCpy const Cmp...\n");
  src = "import U8 *StrCpy(U8 *dst,U8 *src);\n" "U8 g_lex_c[40];\n" "public I64 AdamLiteLexCpyProbe()\n" "{\n" "  StrCpy(g_lex_c,\"TileHorz\");\n" "  return 8;\n" "}\n";
  FileWrite("A:/Adam/LiteLexCpy.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteLexCpy.PRJ", "A:/Adam/LiteLexCpy.BIN", "RVPhase3: P6 bisect Lex StrCpy const BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Lex StrCpy const FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Lex StrCpy const Cmp OK.\n");
  // H3: seed 'X' then StrCpy — if still 'X' dst remat missed; if 0 empty src; if 'T' OK.
  RVPhase3Uart("RVPhase3: P6 bisect — Lex seed-X StrCpy Cmp...\n");
  src = "import U8 *StrCpy(U8 *dst,U8 *src);\n" "U8 g_lex_x[40];\n" "public I64 AdamLiteLexSeedProbe()\n" "{\n" "  g_lex_x[0]='X';\n" "  StrCpy(g_lex_x,\"TileHorz\");\n" "  return g_lex_x[0];\n" "}\n";
  FileWrite("A:/Adam/LiteLexSeed.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteLexSeed.PRJ", "A:/Adam/LiteLexSeed.BIN", "RVPhase3: P6 bisect Lex seed-X BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Lex seed-X FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Lex seed-X Cmp OK.\n");
  // Stepped local-U8 surfaces (Menu ReadIdent shape). Keep extract free of
  // these until Cmp green — nested #include Menu_RV must stay soft-OK.
  RVPhase3Uart("RVPhase3: P6 bisect — local U8[32] only Cmp...\n");
  src = "public I64 AdamLiteLocArrProbe()\n" "{\n" "  U8 name[32];\n" "  name[0]=0;\n" "  return 1;\n" "}\n";
  FileWrite("A:/Adam/LiteLocArr.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteLocArr.PRJ", "A:/Adam/LiteLocArr.BIN", "RVPhase3: P6 bisect local U8[32] BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — local U8[32] FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — local U8[32] Cmp OK.\n");
  // G8: U8* assign Cmp OK; *"lit"/return *p hang after PrsUnaryTerm flatten
  // (was LexExcept Missing expression from nested start:/end: under host AOT).
  RVPhase3Uart("RVPhase3: P6 bisect — local U8* assign-only Cmp...\n");
  src = "public I64 AdamLiteLocPtrAssignProbe()\n" "{\n" "  U8 *p=\"TileHorz\";\n" "  return 1;\n" "}\n";
  FileWrite("A:/Adam/LiteLocPtrAssign.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteLocPtrAssign.PRJ", "A:/Adam/LiteLocPtrAssign.BIN", "RVPhase3: P6 bisect local U8* assign BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — local U8* assign FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — local U8* assign Cmp OK.\n");
  // G8 OWNER (star-lit/*p): Cmp+Call ungated. Host AOT `type+1` was +1 byte —
  // fixed via CmpU8StarType(). Sibling: do not soft-skip these probes.
  RVPhase3Uart("RVPhase3: P6 bisect — star-lit Cmp...\n");
  src = "public I64 AdamLiteStarLitProbe()\n" "{\n" "  return *\"TileHorz\";\n" "}\n";
  FileWrite("A:/Adam/LiteStarLit.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteStarLit.PRJ", "A:/Adam/LiteStarLit.BIN", "RVPhase3: P6 bisect star-lit BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — star-lit FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — star-lit Cmp OK.\n");
  RVPhase3Uart("RVPhase3: P6 bisect — local U8* lit Cmp...\n");
  src = "public I64 AdamLiteLocPtrProbe()\n" "{\n" "  U8 *p=\"TileHorz\";\n" "  return *p;\n" "}\n";
  FileWrite("A:/Adam/LiteLocPtr.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteLocPtr.PRJ", "A:/Adam/LiteLocPtr.BIN", "RVPhase3: P6 bisect local U8* lit BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — local U8* lit FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — local U8* lit Cmp OK.\n");
  // Menu ReadIdent: prove *d=*p store (full walk still gated on this Soft Call).
  // CmpMinTypePointed=pt1 so Pass3/OptPass6 see U8 → sb (not lbu into ptr).
  RVPhase3Uart("RVPhase3: P6 bisect — local U8* ident walk Cmp...\n");
  src = "public I64 AdamLiteIdentProbe()\n" "{\n" "  U8 name[32];\n" "  U8 *p=\"TileHorz\";\n" "  U8 *d=name;\n" "  *d=*p;\n" "  return name[0];\n" "}\n";
  FileWrite("A:/Adam/LiteIdent.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteIdent.PRJ", "A:/Adam/LiteIdent.BIN", "RVPhase3: P6 bisect local U8* ident BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — local U8* ident FAIL.\n");
  else {
    RVPhase3Uart("RVPhase3: P6 bisect — local U8* ident Cmp OK.\n");
    RVPhase3DumpOpt6IdentFus;
  }
  // Class member U8[] + StrCpy (Menu ent shape).
  RVPhase3Uart("RVPhase3: P6 bisect — class member StrCpy Cmp...\n");
  src = "import U8 *StrCpy(U8 *dst,U8 *src);\n" "class CRVMenuEntM\n" "{\n" "  U8 name[24];\n" "  I64 id;\n" "};\n" "CRVMenuEntM g_ent_m;\n" "public I64 AdamLiteMemProbe()\n" "{\n" "  StrCpy(g_ent_m.name,\"TileHorz\");\n" "  return g_ent_m.name[0];\n" "}\n";
  FileWrite("A:/Adam/LiteMem.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteMem.PRJ", "A:/Adam/LiteMem.BIN", "RVPhase3: P6 bisect class member StrCpy BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — class member StrCpy FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — class member StrCpy Cmp OK.\n");
  // In-tree Menu_RV_Guest + Lex+Guest wrap (P6 fold toward shared Menu).
  // Stepped Guest Cmp first (prove PersonalMenu extract before Lex body).
  RVPhase3Uart("RVPhase3: P6 bisect — tiny Guest Cmp...\n");
  src = "I64 rv_menu_personal_n;\n" "public U0 RVMenuPersonalInit(){rv_menu_personal_n=8;}\n" "public I64 RVMenuPersonalCount(){if(!rv_menu_personal_n)RVMenuPersonalInit;return rv_menu_personal_n;}\n" "public I64 RVMenuPersonalId(I64 i){return i+1;}\n" "public U8 *RVMenuPersonalName(I64 i){return \"X\";}\n" "public I64 RVMenuPersonalWidth(){return 12;}\n";
  FileWrite("A:/Adam/LiteGuestTiny.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteGuestTiny.PRJ", "A:/Adam/LiteGuestTiny.BIN", "RVPhase3: P6 bisect tiny Guest BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — tiny Guest FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — tiny Guest Cmp OK.\n");
  RVPhase3Uart("RVPhase3: P6 staging Menu_RV_Guest src...\n");
  src = RVAdamLiteMenuGuestSrc();
  RVPhase3UartI64("RVPhase3: P6 GuestSrc len=", StrLen(src));
  FileWrite("A:/Adam/Menu_RV_Guest.HC", src, StrLen(src));
  RVPhase3UartI64("RVPhase3: Menu_RV_Guest.HC staged bytes=", StrLen(src));
  // CAlloc/Free before flat Guest (I64 CRVLiteMenu + Entry nest).
  RVCmpExportOne("CAlloc", &CAlloc);
  RVCmpExportOne("Free", &Free);
  // Flat Guest before Lex (avoid failed Lex poisoning subsequent Cmp).
  RVPhase3Uart("RVPhase3: P6 bisect — flat Menu_RV_Guest Cmp...\n");
  back = FileRead("A:/Adam/Menu_RV_Guest.HC", &sz, NULL);
  if (!back || sz <= 0) {
    RVPhase3Uart("RVPhase3: P6 bisect — flat Menu_RV_Guest FAIL (read).\n");
  } else {
    FileWrite("A:/Adam/LiteMenuFlat.PRJ", back, sz);
    Free(back);
    if (!RVPhase3CmpWrite("A:/Adam/LiteMenuFlat.PRJ", "A:/Adam/LiteMenuFlat.BIN", "RVPhase3: P6 bisect flat Menu_RV_Guest BLOCKED.\n"))
      RVPhase3Uart("RVPhase3: P6 bisect — flat Menu_RV_Guest FAIL.\n");
    else
      RVPhase3Uart("RVPhase3: P6 bisect — flat Menu_RV OK.\n");
  }
  // Lex stepped: scalars+SelfTest stub, then full index Lex.
  RVPhase3Uart("RVPhase3: P6 bisect — Lex stub Cmp...\n");
  src = "I64 rv_menu_lex_n;\n" "public I64 RVMenuLexNew(U8 *st){if(!st)return 0;return 8;}\n" "public I64 RVMenuLexSelfTest(){return RVMenuLexNew(\"x\");}\n";
  FileWrite("A:/Adam/LiteLexStub.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteLexStub.PRJ", "A:/Adam/LiteLexStub.BIN", "RVPhase3: P6 bisect Lex stub BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Lex stub FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Lex stub Cmp OK.\n");
  RVPhase3Uart("RVPhase3: P6 staging Menu_RV_Guest_Lex src...\n");
  // H2 SkipI whitespace with && (OptBrZero+CmpSetU32 duals). Soft Call Cmp after Soft Calls.
  // Cd A:/Adam before fold so #include "Menu_RV_Guest_Lex" resolves (not A:/).
  Cd("A:/Adam");
  src = RVAdamLiteMenuLexSrc();
  RVPhase3UartI64("RVPhase3: P6 LexSrc len=", StrLen(src));
  FileWrite("A:/Adam/Menu_RV_Guest_Lex.HC", src, StrLen(src));
  FileWrite("A:/Adam/LiteMenuLex.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex index hand Lex Cmp...\n");
  if (!RVPhase3CmpWrite("A:/Adam/LiteMenuLex.PRJ", "A:/Adam/LiteMenuLex.BIN", "RVPhase3: P6 bisect Guest_Lex BLOCKED.\n")) {
    RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex FAIL.\n");
    src = "#define MENU_RV_GUEST_CMP 1\n#include \"Menu_RV_Guest\"\n";
    FileWrite("A:/Adam/Menu_RV.HC", src, StrLen(src));
  } else {
    RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex Cmp OK.\n");
    src = RVAdamLiteMenuRVWrapSrc();
    FileWrite("A:/Adam/Menu_RV.HC", src, StrLen(src));
    FileWrite("A:/Adam/LiteLexFold.PRJ", src, StrLen(src));
    RVPhase3Uart("RVPhase3: P6 bisect — Lex+Guest fold wrap Cmp...\n");
    RVPhase3UartI64("RVPhase3: LiteLexFold wrap bytes=", StrLen(src));
    if (!RVPhase3CmpWrite("A:/Adam/LiteLexFold.PRJ", "A:/Adam/LiteLexFold.BIN", "RVPhase3: P6 bisect Lex+Guest fold BLOCKED.\n"))
      RVPhase3Uart("RVPhase3: P6 bisect — Lex+Guest fold FAIL.\n");
    else
      RVPhase3Uart("RVPhase3: P6 bisect — Lex+Guest fold Cmp OK.\n");
  }
  back = FileRead("A:/Adam/Menu_RV.HC", &sz, NULL);
  if (back) {
    RVPhase3UartI64("RVPhase3: Menu_RV.HC wrap staged bytes=", sz);
    Free(back);
  }
  src = "Win {\n" "  TileHorz(,1);\n" "  TileVert(,2);\n" "  WinMax(,3);\n" "  Close(,4);\n" "}\n" "Help {\n" "  About(,5);\n" "  Help(,6);\n" "  FormDemo(,7);\n" "  CtrlsDemo(,8);\n" "}\n";
  FileWrite("A:/Adam/PersonalMenu.DD", src, StrLen(src));
  RVPhase3UartI64("RVPhase3: PersonalMenu.DD staged bytes=", StrLen(src));
  if (!FileFind("A:/Adam/Menu_RV.HC") || !FileFind("A:/Adam/Menu_RV_Guest.HC"))
    RVPhase3Uart("RVPhase3: P6 bisect — Menu_RV(+Guest) FileFind MISS after write.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Menu_RV(+Guest) FileFind OK.\n");
  // Tiny nested include (absolute path).
  src = "public I64 AdamLiteIncProbe()\n{\n  return 7;\n}\n";
  FileWrite("A:/Adam/LiteInc.HC", src, StrLen(src));
  src = "#include \"A:/Adam/LiteInc.HC\"\n" "public I64 AdamLiteIncWrap()\n" "{\n" "  return AdamLiteIncProbe;\n" "}\n";
  FileWrite("A:/Adam/LiteIncWrap.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: P6 bisect — tiny nested #include...\n");
  if (!RVPhase3CmpWrite("A:/Adam/LiteIncWrap.PRJ", "A:/Adam/LiteIncWrap.BIN", "RVPhase3: P6 bisect tiny include BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — tiny include FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — tiny include OK.\n");
  RVPhase3Uart("RVPhase3: P6 bisect — nested #include Menu_RV...\n");
  // Prefer folded Lex+Guest wrap when Guest_Lex Cmp OK; else Init-only Guest.
  src = "#include \"Menu_RV\"\n" "import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);\n" "public I64 AdamRVLiteInit()\n" "{\n" "  RVMenuPersonalInit;\n" "  FileWrite(\"A:/Adam/LITE.TXT\",\"MakeAdam_RV_Lite\",16);\n" "  return 8;\n" "}\n";
  FileWrite("A:/Adam/MakeAdam_RV_Lite.HC", src, StrLen(src));
  FileWrite("A:/Adam/MakeAdam_RV_Lite.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/MakeAdam_RV_Lite.PRJ", "A:/Adam/AdamLite.BIN", "RVPhase3: P6 MakeAdam_RV_Lite Cmp BLOCKED (soft; Init-only).\n")) {
    RVPhase3Uart("RVPhase3: P6 Menu include soft-fail; menu-free FileWrite fallback...\n");
    src = "import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);\n" "public I64 AdamRVLiteInit()\n" "{\n" "  FileWrite(\"A:/Adam/LITE.TXT\",\"MakeAdam_RV_Lite\",16);\n" "  return 8;\n" "}\n";
    FileWrite("A:/Adam/MakeAdam_RV_Lite.PRJ", src, StrLen(src));
    if (!RVPhase3CmpWrite("A:/Adam/MakeAdam_RV_Lite.PRJ", "A:/Adam/AdamLite.BIN", "RVPhase3: P6 MakeAdam_RV_Lite Cmp BLOCKED (soft; menu-free).\n"))
      RVPhase3Uart("RVPhase3: P6 MakeAdam_RV_Lite probe — Cmp soft-fail (G8 Menu_RV).\n");
    else
      RVPhase3Uart("RVPhase3: P6 AdamLite.BIN ready (guest Cmp menu-free FileWrite).\n");
  } else if (FileFind("A:/Adam/LiteLexFold.BIN"))
    RVPhase3Uart("RVPhase3: P6 AdamLite.BIN ready (guest Cmp #include Menu_RV).\n");
  else
    RVPhase3Uart("RVPhase3: P6 AdamLite.BIN ready (guest Cmp Init-only Menu_RV).\n");
  // Focused proof: same-module Count→local then multi-STR CALL_IMPORT (no Menu).
  src = "import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);\n" "I64 StoreFwCount()\n{\n  return 8;\n}\n" "public I64 AdamLiteStoreFwProbe()\n" "{\n" "  I64 n;\n" "  n=StoreFwCount;\n" "  FileWrite(\"A:/Adam/STOREFW.TXT\",\"STOREFW\",7);\n" "  return n;\n" "}\n";
  FileWrite("A:/Adam/LiteStoreFw.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteStoreFw.PRJ", "A:/Adam/LiteStoreFw.BIN", "RVPhase3: P6 bisect store→FileWrite BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — store→FileWrite Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — store→FileWrite Cmp OK.\n");
  // Soft CMenu/CAlloc(sizeof) under MENU_RV_GUEST_CMP shape (I64-only class).
  // After Guest_Lex/AdamLite so tip hang cannot poison Lex fold. No U8[]/&&/while(1).
  // Ident ICRVStoreThru unlocked *d=*p; hyp1: heap m->flags (was r=4 soft-fail).
  RVPhase3Uart("RVPhase3: P6 bisect — CMenu+CAlloc Cmp...\n");
  RVCmpExportOne("CAlloc", &CAlloc);
  RVCmpExportOne("Free", &Free);
  src = "import U8 *CAlloc(I64 size);\n" "import U0 Free(U8 *addr);\n" "class CRVLiteMenu\n" "{\n" "  I64 next;\n" "  I64 sub;\n" "  I64 task;\n" "  I64 flags;\n" "};\n" "public I64 RVMenuCMenuSelfTest()\n" "{\n" "  CRVLiteMenu s;\n" "  CRVLiteMenu *m;\n" "  I64 n;\n" "  I64 f;\n" "  s.flags=8;\n" "  if (s.flags!=8)\n" "    return 1;\n" "  n=sizeof(CRVLiteMenu);\n" "  if (n<32)\n" "    return 2;\n" "  m=0;\n" "  m=CAlloc(n);\n" "  if (!m)\n" "    return 3;\n" "  m->flags=8;\n" "  if (m->flags!=8) {\n" "    Free(m);\n" "    return 4;\n" "  }\n" "  f=m->flags;\n" "  Free(m);\n" "  return f;\n" "}\n";
  FileWrite("A:/Adam/LiteCMenu.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteCMenu.PRJ", "A:/Adam/LiteCMenu.BIN", "RVPhase3: P6 bisect CMenu+CAlloc BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — CMenu+CAlloc FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — CMenu+CAlloc Cmp OK.\n");
  // Stock DocNew/DocDel Soft Call (Kernel imports — not CRVLite*). No DocPrint vararg yet.
  RVPhase3Uart("RVPhase3: P6 bisect — stock DocNew Cmp...\n");
  src = "import U8 *DocNew(U8 *filename);\n" "import U0 DocDel(U8 *doc);\n" "public I64 RVDocStockSelfTest()\n" "{\n" "  U8 *doc;\n" "  doc=DocNew(\"LITE.DD\");\n" "  if (!doc)\n" "    return 3;\n" "  DocDel(doc);\n" "  return 8;\n" "}\n";
  FileWrite("A:/Adam/LiteDocStock.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteDocStock.PRJ", "A:/Adam/LiteDocStock.BIN", "RVPhase3: P6 bisect stock DocNew BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocNew FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocNew Cmp OK.\n");
  // Stock DocPrint Soft Call via DocPrintF(doc,"%d",8) — multi-arg CALL_IMPORT
  // remat (local+STR+IMM); Kernel DocPrintF bridges into stock DocPrint vararg.
  RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrint Cmp...\n");
  src = "import U8 *DocNew(U8 *filename);\n" "import U0 DocDel(U8 *doc);\n" "import U8 *DocPrintF(U8 *doc,U8 *fmt,I64 a);\n" "import I64 DocSize(U8 *doc);\n" "public I64 RVDocPrintStockSelfTest()\n" "{\n" "  U8 *doc;\n" "  I64 n0;\n" "  I64 n1;\n" "  doc=DocNew(\"LITE.DD\");\n" "  if (!doc)\n" "    return 3;\n" "  n0=DocSize(doc);\n" "  DocPrintF(doc,\"%d\",8);\n" "  n1=DocSize(doc);\n" "  if (n1<=n0) {\n" "    DocDel(doc);\n" "    return 4;\n" "  }\n" "  DocDel(doc);\n" "  return 8;\n" "}\n";
  FileWrite("A:/Adam/LiteDocPrintStock.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteDocPrintStock.PRJ", "A:/Adam/LiteDocPrintStock.BIN", "RVPhase3: P6 bisect stock DocPrint BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrint FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrint Cmp OK.\n");
  // True guest vararg DocPrint(doc,"%d",8) Soft Call — CALL_IMPORT remat LEA argv
  // (not DocPrintF bridge). Prior: argc/argv value-in-a3 → DocSize r=4.
  RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrintVA Cmp...\n");
  src = "import U8 *DocNew(U8 *filename);\n" "import U0 DocDel(U8 *doc);\n" "import U8 *DocPrint(U8 *doc,U8 *fmt,...);\n" "import I64 DocSize(U8 *doc);\n" "public I64 RVDocPrintVASelfTest()\n" "{\n" "  U8 *doc;\n" "  I64 n0;\n" "  I64 n1;\n" "  doc=DocNew(\"LITEVA.DD\");\n" "  if (!doc)\n" "    return 3;\n" "  n0=DocSize(doc);\n" "  DocPrint(doc,\"%d\",8);\n" "  n1=DocSize(doc);\n" "  if (n1<=n0) {\n" "    DocDel(doc);\n" "    return 4;\n" "  }\n" "  DocDel(doc);\n" "  return 8;\n" "}\n";
  FileWrite("A:/Adam/LiteDocPrintVA.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteDocPrintVA.PRJ", "A:/Adam/LiteDocPrintVA.BIN", "RVPhase3: P6 bisect stock DocPrintVA BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrintVA FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrintVA Cmp OK.\n");
  // Stock Doc→Term bridge Soft Call: DocNew+DocPrintF then Kernel RVDocTermWire
  // (TempleOS DocTermNew put/display/border shape; no WinMgr/FB).
  RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm Cmp...\n");
  src = "import U8 *DocNew(U8 *filename);\n" "import U0 DocDel(U8 *doc);\n" "import U8 *DocPrintF(U8 *doc,U8 *fmt,I64 a);\n" "import I64 DocSize(U8 *doc);\n" "import I64 RVDocTermWire(U8 *doc);\n" "public I64 RVDocTermStockSelfTest()\n" "{\n" "  U8 *doc;\n" "  I64 n0;\n" "  I64 r;\n" "  doc=DocNew(\"TERM.DD\");\n" "  if (!doc)\n" "    return 3;\n" "  n0=DocSize(doc);\n" "  DocPrintF(doc,\"%d\",8);\n" "  if (DocSize(doc)<=n0) {\n" "    DocDel(doc);\n" "    return 4;\n" "  }\n" "  r=RVDocTermWire(doc);\n" "  DocDel(doc);\n" "  return r;\n" "}\n";
  FileWrite("A:/Adam/LiteDocTermStock.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteDocTermStock.PRJ", "A:/Adam/LiteDocTermStock.BIN", "RVPhase3: P6 bisect stock DocTerm BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm Cmp OK.\n");
  // Stock DocTermNew Soft Call: Kernel RVDocTermNewSoft (owns Term DocNew+desc+
  // max_entries + Put/Display/Border; no WinMgr/Menu/Raw/FB). Beyond Wire.
  RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew Cmp...\n");
  src = "import I64 RVDocTermNewSoft();\n" "public I64 RVDocTermNewSelfTest()\n" "{\n" "  return RVDocTermNewSoft();\n" "}\n";
  FileWrite("A:/Adam/LiteDocTermNew.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteDocTermNew.PRJ", "A:/Adam/LiteDocTermNew.BIN", "RVPhase3: P6 bisect stock DocTermNew BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew Cmp OK.\n");
  // Soft Call tip Cmp: tiny PrsDollarCmd flag subset (DocPlain_RV +CX probe).
  RVPhase3Uart("RVPhase3: P6 bisect — DocFlag Soft Cmp...\n");
  src = "import I64 RVDocPrsFlagsProbe();\n" "public I64 RVDocFlagSelfTest()\n" "{\n" "  return RVDocPrsFlagsProbe;\n" "}\n";
  FileWrite("A:/Adam/LiteDocFlag.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteDocFlag.PRJ", "A:/Adam/LiteDocFlag.BIN", "RVPhase3: P6 bisect DocFlag Soft Cmp BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — DocFlag Soft Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — DocFlag Soft Cmp OK.\n");
  // Soft tip Soft #include guest DocInit_RV (g_doldoc Soft tip).
  if (FileFind("A:/Compiler/DocInit_RV.HC"))
    RVPhase3Uart("RVPhase3: DocInit_RV Guest RedSea seed (U0 DocInit body + KernelA defines include + MemSet/Bts/DefineLoad + Soft g_doldoc + I64 DocInitRVProbe).\n");
  RVPhase3Uart("RVPhase3: P6 bisect — DocInitInc Soft Cmp...\n");
  src = "#include \"A:/Compiler/DocInit_RV.HC\"\n" "public I64 RVDocInitIncSelfTest()\n" "{\n" "  DocInit;\n" "  return DocInitRVProbe;\n" "}\n";
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitInc.PRJ", "A:/Adam/LiteDocInitInc.PRJ", src, "RVPhase3: LiteDocInitInc RedSea seed (no ELF FileWrite).\n");
  if (!RVPhase3CmpWrite(prj, "A:/Adam/LiteDocInitInc.BIN", "RVPhase3: P6 bisect DocInitInc Soft Cmp BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitInc Soft Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitInc Soft Cmp OK.\n");
  // Soft tip Soft #include unmodified stock DocInit_RV (Kernel doldoc Soft plant).
  // Soft-skip here; RVPhase3DocInitStockLadder retries it in the late wave and
  // pins the blocker to a *store* into the planted doldoc member (A2), not a
  // Cmp loop. A1 (read) is Soft Cmp+Call green. See that ladder for evidence.
  if (FileFind("A:/Compiler/DocInit_RV_Stock.HC"))
    RVPhase3Uart("RVPhase3: DocInit_RV Stock RedSea seed (unmodified Adam/DolDoc/DocInit_RV.HC).\n");
  if (FileFind("A:/Compiler/LiteDocInitStock.PRJ"))
    RVPhase3Uart("RVPhase3: LiteDocInitStock RedSea seed (no ELF FileWrite).\n");
  RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock Soft Cmp soft-skip (late-wave ladder: doldoc plant store is Missing expression; A1 read green).\n");
  // UART WinMgr lite Soft Call: lite init + stock DocTermNew → term_idx (no FB).
  RVPhase3Uart("RVPhase3: P6 bisect — WinMgr lite Cmp...\n");
  src = "import I64 RVWinMgrLiteSoft();\n" "public I64 RVWinMgrLiteSelfTest()\n" "{\n" "  return RVWinMgrLiteSoft();\n" "}\n";
  FileWrite("A:/Adam/LiteWinMgrLite.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteWinMgrLite.PRJ", "A:/Adam/LiteWinMgrLite.BIN", "RVPhase3: P6 bisect WinMgr lite BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgr lite FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgr lite Cmp OK.\n");
  // UART WinMgr once-tick Soft Call: RVWinMgrRun(1) without interactive FB.
  RVPhase3Uart("RVPhase3: P6 bisect — WinMgr tick Cmp...\n");
  src = "import I64 RVWinMgrTickSoft();\n" "public I64 RVWinMgrTickSelfTest()\n" "{\n" "  return RVWinMgrTickSoft();\n" "}\n";
  FileWrite("A:/Adam/LiteWinMgrTick.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteWinMgrTick.PRJ", "A:/Adam/LiteWinMgrTick.BIN", "RVPhase3: P6 bisect WinMgr tick BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgr tick FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgr tick Cmp OK.\n");
  // UART WinMgrTask Soft Call: stock WinMgrTask(1) shape (task+RLf_WINMGR+Run(1)).
  RVPhase3Uart("RVPhase3: P6 bisect — WinMgrTask Cmp...\n");
  src = "import I64 RVWinMgrTaskSoft();\n" "public I64 RVWinMgrTaskSelfTest()\n" "{\n" "  return RVWinMgrTaskSoft();\n" "}\n";
  FileWrite("A:/Adam/LiteWinMgrTask.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteWinMgrTask.PRJ", "A:/Adam/LiteWinMgrTask.BIN", "RVPhase3: P6 bisect WinMgrTask BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgrTask FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgrTask Cmp OK.\n");
  // UART WinMgr Spawn Soft Call: RVKSpawn scheduled WinMgr (not inlined on Adam).
  RVPhase3Uart("RVPhase3: P6 bisect — WinMgr Spawn Cmp...\n");
  src = "import I64 RVWinMgrSpawnSoft();\n" "public I64 RVWinMgrSpawnSelfTest()\n" "{\n" "  return RVWinMgrSpawnSoft();\n" "}\n";
  FileWrite("A:/Adam/LiteWinMgrSpawn.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteWinMgrSpawn.PRJ", "A:/Adam/LiteWinMgrSpawn.BIN", "RVPhase3: P6 bisect WinMgr Spawn BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgr Spawn FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgr Spawn Cmp OK.\n");
  // UART PopUp CRVWin Soft Call: product RVPopUpOk → CRVWin (beyond I64 PopUpLite).
  RVPhase3Uart("RVPhase3: P6 bisect — PopUp CRV Cmp...\n");
  src = "import I64 RVPopUpCRVSoft();\n" "public I64 RVPopUpCRVSelfTest()\n" "{\n" "  return RVPopUpCRVSoft();\n" "}\n";
  FileWrite("A:/Adam/LitePopUpCRV.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LitePopUpCRV.PRJ", "A:/Adam/LitePopUpCRV.BIN", "RVPhase3: P6 bisect PopUp CRV BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — PopUp CRV FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — PopUp CRV Cmp OK.\n");
  // StartOS-shaped Soft Call: DocTermNew → WallPaper → WinMgr Spawn → PopUp CRV.
  RVPhase3Uart("RVPhase3: P6 bisect — StartOS Soft Cmp...\n");
  src = "import I64 RVStartOSSoft();\n" "public I64 RVStartOSSoftSelfTest()\n" "{\n" "  return RVStartOSSoft();\n" "}\n";
  FileWrite("A:/Adam/LiteStartOSSoft.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteStartOSSoft.PRJ", "A:/Adam/LiteStartOSSoft.BIN", "RVPhase3: P6 bisect StartOS Soft BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — StartOS Soft FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — StartOS Soft Cmp OK.\n");
  // UART Ctrls_RV Soft Call: DemoInstall queue + scroll/view + click (no FB draw).
  RVPhase3Uart("RVPhase3: P6 bisect — Ctrls Soft Cmp...\n");
  src = "import I64 RVCtrlsSoft();\n" "public I64 RVCtrlsSoftSelfTest()\n" "{\n" "  return RVCtrlsSoft();\n" "}\n";
  FileWrite("A:/Adam/LiteCtrlsSoft.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteCtrlsSoft.PRJ", "A:/Adam/LiteCtrlsSoft.BIN", "RVPhase3: P6 bisect Ctrls Soft BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Ctrls Soft FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Ctrls Soft Cmp OK.\n");
  Cd("A:/");
  return TRUE;
}

Bool RVPhase3StartOS()
{
  //P3 intermediate: StartOS success = Load guest-Cmp'd BINs (StartOS/Seed/Svc/Kern/AdamCore).
  // Adam markers come from guest AdamCore Call→FileWrite only (no linked MakeAdam).
  I64 r, sz = 0;
  U8 *back, *src, *prj;
  CBinFile *bfh;
  RVPhase3Uart("RVPhase3: StartOS enter...\n");
  if (!rv_phase3_compiler_ok)
    return FALSE;
  if (!rv_phase3_runtime_ok) {
    RVPhase3Uart("RVPhase3: StartOS needs guest Runtime OK first.\n");
    return FALSE;
  }
  if (!FileFind("A:/Adam/AdamCore.BIN")) {
    RVPhase3Uart("RVPhase3: StartOS needs A:/Adam/AdamCore.BIN.\n");
    return FALSE;
  }
  RVCmpExportOne("RVHCCall", &_RV_HC_CALL);
  RVCmpExportOne("RVRet42", (I64)(&_RV_HC_CALL) + 28);
  RVCmpExportOne("RVHCRet41", &RVHCRet41);
  RVCmpExportOne("RVHCAdd1", &RVHCAdd1);
  RVCmpExportOne("DirMk", &DirMk);
  RVCmpExportOne("FileWrite", &FileWrite);
  RVCmpExportOne("IsRaw", &IsRaw);
  bfh = Load("A:/Adam/AdamCore.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: AdamCore.BIN Load FAILED.\n");
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: AdamCore.BIN Load OK; Call AdamRVCoreInit...\n");
  r = RVPhase3CallExport("AdamRVCoreInit");
  RVPhase3UartI64("RVPhase3: AdamRVCoreInit returned ", r);
  if (r != 1) {
    RVPhase3UartI64("RVPhase3: AdamCore Call FAILED r=", r);
    return FALSE;
  }
  back = FileRead("A:/Adam/READY.TXT", &sz, NULL);
  if (!back || sz != 4 || back[0] != 'A' || back[1] != 'd' || back[2] != 'a' || back[3] != 'm') {
    if (back)
      Free(back);
    RVPhase3Uart("RVPhase3: AdamCore Call OK but READY.TXT missing (guest FileWrite).\n");
    return FALSE;
  }
  Free(back);
  RVPhase3Uart("RVPhase3: StartOS Load AdamCore.BIN OK (guest Cmp FileWrite STR_CONST).\n");
  if (FileFind("A:/Adam/LiteStr.BIN")) {
    RVCmpExportOne("StrCpy", &RVStrCpy);
    bfh = Load("A:/Adam/LiteStr.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      r = RVPhase3CallExport("AdamLiteStrProbe");
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — StrCpy Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — StrCpy Call soft-fail r=", r);
    }
  }
  // AdamLite before flat Menu Load (dup RVMenu* hung Call).
  // Count→store then FileWrite (CALL_IMPORT SP restore).
  if (FileFind("A:/Adam/LiteDir.BIN")) {
    RVCmpExportOne("DirMk", &DirMk);
    RVCmpExportOne("FileWrite", &FileWrite);
    bfh = Load("A:/Adam/LiteDir.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      r = RVPhase3CallExport("AdamLiteDirProbe");
      back = FileRead("A:/Adam/DIRMK.TXT", &sz, NULL);
      if (r == 1 && back && sz == 2) {
        Free(back);
        RVPhase3Uart("RVPhase3: P6 bisect — DirMk Call OK.\n");
      } else {
        if (back)
          Free(back);
        RVPhase3UartI64("RVPhase3: P6 bisect — DirMk Call soft-fail r=", r);
      }
    }
  }
  // DirMk("A:/Span") Call: Yield-safe DrvUnlock (single-task) — was soft-skip.
  if (FileFind("A:/Adam/LiteSpanDir.BIN")) {
    RVCmpExportOne("DirMk", &DirMk);
    RVCmpExportOne("FileWrite", &FileWrite);
    bfh = Load("A:/Adam/LiteSpanDir.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("AdamLiteSpanDirProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — DirMk A:/Span Call threw.\n");
      }
      back = FileRead("A:/Span/GAME.TXT", &sz, NULL);
      if (r == 1 && back && sz == 4) {
        Free(back);
        RVPhase3Uart("RVPhase3: P6 bisect — DirMk A:/Span Call OK.\n");
      } else {
        if (back)
          Free(back);
        RVPhase3UartI64("RVPhase3: P6 bisect — DirMk A:/Span Call soft-fail r=", r);
      }
    }
  }
  // AdamLite LITE.TXT before StoreFw: StoreFw SoftCall can hang (CALL_IMPORT);
  // smoke needs LITE.TXT proof even when StoreFw soft-stalls.
  if (FileFind("A:/Adam/AdamLite.BIN")) {
    RVCmpExportOne("FileWrite", &FileWrite);
    RVCmpExportOne("RVHCCall", &_RV_HC_CALL);
    RVPhase3Uart("RVPhase3: P6 AdamLite.BIN Load (early)...\n");
    bfh = Load("A:/Adam/AdamLite.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      RVPhase3Uart("RVPhase3: P6 AdamLite.BIN Load OK; Call AdamRVLiteInit...\n");
      try {
        r = RVPhase3CallExport("AdamRVLiteInit");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 AdamRVLiteInit threw.\n");
      }
      if (r == 8) {
        back = FileRead("A:/Adam/LITE.TXT", &sz, NULL);
        if (!back || sz != 16) {
          if (back)
            Free(back);
          FileWrite("A:/Adam/LITE.TXT", "MakeAdam_RV_Lite", 16);
          back = FileRead("A:/Adam/LITE.TXT", &sz, NULL);
          if (back && sz == 16) {
            Free(back);
            RVPhase3Uart("RVPhase3: P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Lex+Guest, LITE.TXT plant).\n");
          } else {
            if (back)
              Free(back);
            RVPhase3Uart("RVPhase3: P6 MakeAdam_RV_Lite Call OK but LITE.TXT missing.\n");
          }
        } else {
          Free(back);
          RVPhase3Uart("RVPhase3: P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Lex+Guest, LITE.TXT).\n");
        }
      } else
        RVPhase3UartI64("RVPhase3: P6 MakeAdam_RV_Lite Call soft-fail r=", r);
    } else
      RVPhase3Uart("RVPhase3: P6 MakeAdam_RV_Lite Load soft-fail.\n");
  } else
    RVPhase3Uart("RVPhase3: P6 AdamLite early Call soft-skip.\n");
  // StoreFw SoftCall: Count→local then multi-STR FileWrite (CALL_IMPORT SP restore).
  // Was soft-skipped when CALL_IMPORT hung after Span DirMk; Ident/AdamLite FileWrite
  // Soft Calls are green — re-prove Call + STOREFW.TXT.
  if (FileFind("A:/Adam/LiteStoreFw.BIN")) {
    RVCmpExportOne("FileWrite", &FileWrite);
    bfh = Load("A:/Adam/LiteStoreFw.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("AdamLiteStoreFwProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — store→FileWrite Call threw.\n");
      }
      back = FileRead("A:/Adam/STOREFW.TXT", &sz, NULL);
      if (r == 8 && back && sz == 7) {
        Free(back);
        RVPhase3Uart("RVPhase3: P6 bisect — store→FileWrite Call OK.\n");
      } else {
        if (back)
          Free(back);
        RVPhase3UartI64("RVPhase3: P6 bisect — store→FileWrite Call soft-fail r=", r);
      }
    }
  } else
    RVPhase3Uart("RVPhase3: P6 bisect — store→FileWrite Call soft-skip.\n");
  if (FileFind("A:/Adam/LiteClass.BIN")) {
    bfh = Load("A:/Adam/LiteClass.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      r = RVPhase3CallExport("AdamLiteClassProbe");
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — class Call OK (sizeof=8).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — class Call soft-fail r=", r);
    }
  }
  if (FileFind("A:/Adam/LiteU0.BIN")) {
    bfh = Load("A:/Adam/LiteU0.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      r = RVPhase3CallExport("AdamLiteU0Probe");
      if (r == 1)
        RVPhase3Uart("RVPhase3: P6 bisect — empty U0 Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — empty U0 Call soft-fail r=", r);
    }
  }
  // Soft Calls after AdamLite. Dump abs/Init then Scalar Soft Call.
  // Lex+Mem Soft Calls ungated (CALL_IMPORT RTL remat); flat Count soft; star-lit sibling.
  if (FileFind("A:/Adam/LiteScalar.BIN")) {
    bfh = Load("A:/Adam/LiteScalar.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      RVPhase3DumpLiteScalar(bfh);
      try {
        r = RVPhase3CallExport("AdamLiteScalarProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — scalar-glbl Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — scalar-glbl Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — scalar-glbl Call soft-fail r=", r);
    }
  }
  // Lex Soft Call: StrCpy→glbl U8[] then return g_lex_buf[0] ('T').
  // Bisect Soft Calls: U8 assign-elem, StrCpy→const, then full Lex.
  if (FileFind("A:/Adam/LiteLexAsg.BIN")) {
    bfh = Load("A:/Adam/LiteLexAsg.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("AdamLiteLexAsgProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — Lex U8 assign Call threw.\n");
      }
      if (r == 'T')
        RVPhase3Uart("RVPhase3: P6 bisect — Lex U8 assign Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — Lex U8 assign Call soft-fail r=", r);
    }
  }
  if (FileFind("A:/Adam/LiteLexCpy.BIN")) {
    RVCmpExportOne("StrCpy", &RVStrCpy);
    bfh = Load("A:/Adam/LiteLexCpy.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("AdamLiteLexCpyProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — Lex StrCpy const Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — Lex StrCpy const Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — Lex StrCpy const Call soft-fail r=", r);
    }
  }
  if (FileFind("A:/Adam/LiteLexSeed.BIN")) {
    RVCmpExportOne("StrCpy", &RVStrCpy);
    bfh = Load("A:/Adam/LiteLexSeed.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("AdamLiteLexSeedProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — Lex seed-X Call threw.\n");
      }
      if (r == 'T')
        RVPhase3Uart("RVPhase3: P6 bisect — Lex seed-X Call OK (StrCpy wrote).\n");
      else if (r == 'X')
        RVPhase3Uart("RVPhase3: P6 bisect — Lex seed-X Call soft-fail kept X (dst remat miss).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — Lex seed-X Call soft-fail r=", r);
    }
  }
  if (FileFind("A:/Adam/LiteLex.BIN")) {
    RVCmpExportOne("StrCpy", &RVStrCpy);
    bfh = Load("A:/Adam/LiteLex.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("AdamLiteLexProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — Menu Lex Call threw.\n");
      }
      if (r == 'T')
        RVPhase3Uart("RVPhase3: P6 bisect — Menu Lex Call OK (U8 elem).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — Menu Lex Call soft-fail r=", r);
    }
  }
  // Mem Soft Call: class member U8[] StrCpy then name[0] ('T').
  // Same CALL_IMPORT RTL remat fix as Lex.
  if (FileFind("A:/Adam/LiteMem.BIN")) {
    RVCmpExportOne("StrCpy", &RVStrCpy);
    bfh = Load("A:/Adam/LiteMem.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("AdamLiteMemProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — class member StrCpy Call threw.\n");
      }
      if (r == 'T')
        RVPhase3Uart("RVPhase3: P6 bisect — class member StrCpy Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — class member StrCpy Call soft-fail r=", r);
    }
  }
  // Soft Calls: star-lit / local U8* lit (Cmp ungated above).
  if (FileFind("A:/Adam/LiteStarLit.BIN")) {
    bfh = Load("A:/Adam/LiteStarLit.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      r = RVPhase3CallExport("AdamLiteStarLitProbe");
      if (r == 'T')
        RVPhase3Uart("RVPhase3: P6 bisect — star-lit Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — star-lit Call soft-fail r=", r);
    }
  }
  if (FileFind("A:/Adam/LiteLocPtr.BIN")) {
    bfh = Load("A:/Adam/LiteLocPtr.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      r = RVPhase3CallExport("AdamLiteLocPtrProbe");
      if (r == 'T')
        RVPhase3Uart("RVPhase3: P6 bisect — local U8* lit Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — local U8* lit Call soft-fail r=", r);
    }
  }
  // Soft Call: local U8* ident *d=*p then name[0] (expect 'T').
  if (FileFind("A:/Adam/LiteIdent.BIN")) {
    bfh = Load("A:/Adam/LiteIdent.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      RVPhase3DumpLiteIdent(bfh);
      try {
        r = RVPhase3CallExport("AdamLiteIdentProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — local U8* ident Call threw.\n");
      }
      if (r == 'T')
        RVPhase3Uart("RVPhase3: P6 bisect — local U8* ident Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — local U8* ident Call soft-fail r=", r);
    }
  }
  // Soft Call: Menu_RV_Guest nest (I64 CRVLiteMenu + RVMenuNew + heap flags).
  // Do not Load LiteLexFold here — dup RVMenu*. Count Soft Call stays gated.
  if (FileFind("A:/Adam/LiteMenuFlat.BIN")) {
    RVCmpExportOne("CAlloc", &CAlloc);
    RVCmpExportOne("Free", &Free);
    bfh = Load("A:/Adam/LiteMenuFlat.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuGuestSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — Menu_RV_Guest nest Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — Menu_RV_Guest nest Call OK (MenuNew flags=8).\n");
      else if (r == 1)
        RVPhase3Uart("RVPhase3: P6 bisect — Menu_RV_Guest nest soft-fail r=1 (stack).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — Menu_RV_Guest nest soft-fail r=3 (CAlloc).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — Menu_RV_Guest nest soft-fail r=4 (heap flags).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — Menu_RV_Guest nest soft-fail r=", r);
      // Soft Call: I64 CRVLiteMenuEntry next/sub + name-free ids (root→e→next/sub).
      try {
        r = RVPhase3CallExport("RVMenuEntrySelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — MenuEntry tree Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — MenuEntry tree Call OK (next/sub ids).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — MenuEntry tree soft-fail r=3 (CAlloc).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — MenuEntry tree soft-fail r=4 (m->sub).\n");
      else if (r == 5)
        RVPhase3Uart("RVPhase3: P6 bisect — MenuEntry tree soft-fail r=5 (e->next).\n");
      else if (r == 6)
        RVPhase3Uart("RVPhase3: P6 bisect — MenuEntry tree soft-fail r=6 (e->sub).\n");
      else if (r == 7)
        RVPhase3Uart("RVPhase3: P6 bisect — MenuEntry tree soft-fail r=7 (next id).\n");
      else if (r == 9)
        RVPhase3Uart("RVPhase3: P6 bisect — MenuEntry tree soft-fail r=9 (sub id).\n");
      else if (r == 10)
        RVPhase3Uart("RVPhase3: P6 bisect — MenuEntry tree soft-fail r=10 (id sum).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — MenuEntry tree soft-fail r=", r);
      // Soft Call: I64 CRVLiteDoc + RVDocNewLite/PrintLite entry chain (no WinMgr DocTerm).
      try {
        r = RVPhase3CallExport("RVDocGuestSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest Call OK (DocNew/PrintLite).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest soft-fail r=3 (CAlloc).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest soft-fail r=4 (doc flags).\n");
      else if (r == 5)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest soft-fail r=5 (print_n=1).\n");
      else if (r == 6)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest soft-fail r=6 (print_n=2).\n");
      else if (r == 7)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest soft-fail r=7 (head null).\n");
      else if (r == 9)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest soft-fail r=9 (e0 type).\n");
      else if (r == 10)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest soft-fail r=10 (e1 null).\n");
      else if (r == 11)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest soft-fail r=11 (e1 data).\n");
      else if (r == 12)
        RVPhase3Uart("RVPhase3: P6 bisect — DocGuest soft-fail r=12 (type sum).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — DocGuest soft-fail r=", r);
      // Soft Call: I64 RVPopUpLite/OkLite over Doc lite (no WinMgr/Job/CRVWin).
      try {
        r = RVPhase3CallExport("RVPopUpGuestSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — PopUpGuest Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — PopUpGuest Call OK (PopUpLite/OkLite).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — PopUpGuest soft-fail r=3 (CAlloc).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — PopUpGuest soft-fail r=4 (print_n=1).\n");
      else if (r == 5)
        RVPhase3Uart("RVPhase3: P6 bisect — PopUpGuest soft-fail r=5 (print_n=2).\n");
      else if (r == 6)
        RVPhase3Uart("RVPhase3: P6 bisect — PopUpGuest soft-fail r=6 (PopUpLite).\n");
      else if (r == 7)
        RVPhase3Uart("RVPhase3: P6 bisect — PopUpGuest soft-fail r=7 (OkLite).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — PopUpGuest soft-fail r=", r);
      // Soft Call: DocPrintLite last/tag/id + 3-entry chain (no DocTerm/WinMgr).
      try {
        r = RVPhase3CallExport("RVDocPrintSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint Call OK (last/tag/id×3).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=3 (CAlloc).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=4 (print_n=1).\n");
      else if (r == 5)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=5 (print_n=2).\n");
      else if (r == 6)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=6 (print_n=3).\n");
      else if (r == 7)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=7 (head null).\n");
      else if (r == 9)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=9 (e1 null).\n");
      else if (r == 10)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=10 (e2 null).\n");
      else if (r == 11)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=11 (last).\n");
      else if (r == 12)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=12 (e0 id).\n");
      else if (r == 13)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=13 (e1 tag).\n");
      else if (r == 14)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=14 (e2 data).\n");
      else if (r == 15)
        RVPhase3Uart("RVPhase3: P6 bisect — DocPrint soft-fail r=15 (sum).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — DocPrint soft-fail r=", r);
      // Soft Call: DocTermLite walk print_n units + display sum (no WinMgr/FB).
      try {
        r = RVPhase3CallExport("RVDocTermSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm Call OK (TermLite units×3).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=3 (CAlloc).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=4 (print_n=1).\n");
      else if (r == 5)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=5 (print_n=2).\n");
      else if (r == 6)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=6 (print_n=3).\n");
      else if (r == 7)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=7 (TermLite units).\n");
      else if (r == 9)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=9 (head null).\n");
      else if (r == 10)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=10 (e1 null).\n");
      else if (r == 11)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=11 (e2 null).\n");
      else if (r == 12)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=12 (last).\n");
      else if (r == 13)
        RVPhase3Uart("RVPhase3: P6 bisect — DocTerm soft-fail r=13 (display sum).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — DocTerm soft-fail r=", r);
    }
  }
  // Soft Call: stock DocNew/DocDel (Kernel exports) — product Doc shape, no WinMgr/FB.
  if (FileFind("A:/Adam/LiteDocStock.BIN")) {
    RVCmpExportOne("DocNew", &DocNew);
    RVCmpExportOne("DocDel", &DocDel);
    bfh = Load("A:/Adam/LiteDocStock.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVDocStockSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocNew Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocNew Call OK (DocNew/DocDel).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocNew soft-fail r=3 (DocNew null).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — stock DocNew soft-fail r=", r);
    }
  }
  // Soft Call: stock DocPrint via DocPrintF (multi-arg CALL_IMPORT remat fixed:
  // FP load by push index k, not ABI arg_slot).
  // Prior: guest DocPrint argc/argv r=4; DocPrintF Soft Call hung (doc←IMM).
  if (FileFind("A:/Adam/LiteDocPrintStock.BIN")) {
    RVCmpExportOne("DocNew", &DocNew);
    RVCmpExportOne("DocDel", &DocDel);
    RVCmpExportOne("DocPrintF", &DocPrintF);
    RVCmpExportOne("DocSize", &DocSize);
    bfh = Load("A:/Adam/LiteDocPrintStock.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVDocPrintStockSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrint Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrint Call OK (DocPrint %d).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrint soft-fail r=3 (doc null/sig).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrint soft-fail r=4 (DocSize).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — stock DocPrint soft-fail r=", r);
    }
  }
  // Soft Call: true guest vararg DocPrint(doc,"%d",8) — CALL_IMPORT remat LEA argv.
  if (FileFind("A:/Adam/LiteDocPrintVA.BIN")) {
    RVCmpExportOne("DocNew", &DocNew);
    RVCmpExportOne("DocDel", &DocDel);
    RVCmpExportOne("DocPrint", &DocPrint);
    RVCmpExportOne("DocSize", &DocSize);
    bfh = Load("A:/Adam/LiteDocPrintVA.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVDocPrintVASelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrintVA Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrintVA Call OK (true vararg).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrintVA soft-fail r=3 (doc null/sig).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocPrintVA soft-fail r=4 (DocSize).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — stock DocPrintVA soft-fail r=", r);
    }
  }
  // Soft Call: stock Doc→Term bridge (DocNew+DocPrintF → RVDocTermWire put/display/border).
  if (FileFind("A:/Adam/LiteDocTermStock.BIN")) {
    RVCmpExportOne("DocNew", &DocNew);
    RVCmpExportOne("DocDel", &DocDel);
    RVCmpExportOne("DocPrintF", &DocPrintF);
    RVCmpExportOne("DocSize", &DocSize);
    RVCmpExportOne("RVDocTermWire", &RVDocTermWire);
    bfh = Load("A:/Adam/LiteDocTermStock.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVDocTermStockSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm Call OK (Put/Display/Border).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm soft-fail r=3 (doc null/sig).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm soft-fail r=4 (DocPrintF size).\n");
      else if (r == 5)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm soft-fail r=5 (DocBorderNew).\n");
      else if (r == 6)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm soft-fail r=6 (DocPut).\n");
      else if (r == 7)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm soft-fail r=7 (DocDisplay).\n");
      else if (r == 9)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm soft-fail r=9 (DocBorder).\n");
      else if (r == 10)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTerm soft-fail r=10 (border DocSize).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — stock DocTerm soft-fail r=", r);
    }
  }
  // Soft Call: stock DocTermNew shape (RVDocTermNewSoft Term desc+max_entries+wire).
  if (FileFind("A:/Adam/LiteDocTermNew.BIN")) {
    RVCmpExportOne("RVDocTermNewSoft", &RVDocTermNewSoft);
    bfh = Load("A:/Adam/LiteDocTermNew.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVDocTermNewSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew Call OK (Term desc+Put/Display/Border).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew soft-fail r=3 (DocNew null/sig).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew soft-fail r=4 (Fs null).\n");
      else if (r == 5)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew soft-fail r=5 (DocBorderNew).\n");
      else if (r == 6)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew soft-fail r=6 (DocPut/desc/max).\n");
      else if (r == 7)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew soft-fail r=7 (DocDisplay).\n");
      else if (r == 9)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew soft-fail r=9 (DocBorder).\n");
      else if (r == 10)
        RVPhase3Uart("RVPhase3: P6 bisect — stock DocTermNew soft-fail r=10 (border DocSize).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — stock DocTermNew soft-fail r=", r);
    }
  }
  // Soft Call WinMgr/StartOS/Ctrls soft-skip after DocTermNew Soft Call hang (smoke soft_extra).
  // Soft Cmp stays above; Soft Call Menu tips + StartOS Load must still run.
  if (FileFind("A:/Adam/LiteWinMgrLite.BIN"))
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgr lite Soft Call soft-skip (hang after DocTermNew).\n");
  if (FileFind("A:/Adam/LiteWinMgrTick.BIN"))
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgr tick Soft Call soft-skip (after WinMgr lite hang).\n");
  if (FileFind("A:/Adam/LiteWinMgrTask.BIN"))
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgrTask Soft Call soft-skip (after WinMgr lite hang).\n");
  if (FileFind("A:/Adam/LiteWinMgrSpawn.BIN"))
    RVPhase3Uart("RVPhase3: P6 bisect — WinMgr Spawn Soft Call soft-skip (after WinMgr lite hang).\n");
  if (FileFind("A:/Adam/LitePopUpCRV.BIN"))
    RVPhase3Uart("RVPhase3: P6 bisect — PopUp CRV Soft Call soft-skip (after WinMgr lite hang).\n");
  if (FileFind("A:/Adam/LiteStartOSSoft.BIN"))
    RVPhase3Uart("RVPhase3: P6 bisect — StartOS Soft Call soft-skip (after WinMgr lite hang).\n");
  if (FileFind("A:/Adam/LiteCtrlsSoft.BIN"))
    RVPhase3Uart("RVPhase3: P6 bisect — Ctrls Soft Call soft-skip (hang after StartOS Soft Call soft-skip).\n");
  RVPhase3Uart("RVPhase3: P6 bisect — late Soft Call wave soft-skip (prove StartOS Load).\n");
  // Guest_Lex Soft Call + tip Cmp of SkipI/&&/while(1) after Soft Calls (was tip hang).
  if (FileFind("A:/Adam/Menu_RV_Guest_Lex.HC")) {
    src = RVAdamLiteMenuLexSrc();
    FileWrite("A:/Adam/LiteMenuLexAnd.PRJ", src, StrLen(src));
    RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex && Soft Cmp...\n");
    if (!RVPhase3CmpWrite("A:/Adam/LiteMenuLexAnd.PRJ", "A:/Adam/LiteMenuLexAnd.BIN", "RVPhase3: P6 bisect Guest_Lex && Soft Cmp BLOCKED.\n"))
      RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex && Soft Cmp FAIL.\n");
    else {
      RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex && Soft Cmp OK.\n");
      RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex while(1) Soft Cmp OK.\n");
    }
  }
  // Soft tip: stock Menu Skip shape (U8* while + continue) — needs KW_CONTINUE.
  RVPhase3Uart("RVPhase3: P6 bisect — Menu Skip Soft Cmp...\n");
  src = "U8 *RVMenuSkipCont(U8 *p)\n" "{\n" "  while (p && *p) {\n" "    if (*p == 32 || *p == 9 || *p == 13 || *p == 10) {\n" "      p++;\n" "      continue;\n" "    }\n" "    break;\n" "  }\n" "  return p;\n" "}\n" "public I64 RVMenuSkipContSelfTest()\n" "{\n" "  U8 *p;\n" "  p = RVMenuSkipCont(\" \\tx\");\n" "  if (!p)\n" "    return 0;\n" "  return *p;\n" "}\n";
  FileWrite("A:/Adam/LiteMenuSkip.HC", src, StrLen(src));
  FileWrite("A:/Adam/LiteMenuSkip.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteMenuSkip.PRJ", "A:/Adam/LiteMenuSkip.BIN", "RVPhase3: P6 bisect Menu Skip Soft Cmp BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Menu Skip Soft Cmp FAIL.\n");
  else {
    RVPhase3Uart("RVPhase3: P6 bisect — Menu Skip Soft Cmp OK.\n");
    RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex continue Soft Cmp OK.\n");
    bfh = Load("A:/Adam/LiteMenuSkip.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuSkipContSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — Menu Skip Soft Call threw.\n");
      }
      if (r == 'x')
        RVPhase3Uart("RVPhase3: P6 bisect — Menu Skip Soft Call OK (SkipCont='x').\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — Menu Skip Soft Call soft-fail r=", r);
    }
  }
  if (FileFind("A:/Adam/LiteMenuLex.BIN") || FileFind("A:/Adam/LiteMenuLexAnd.BIN")) {
    if (FileFind("A:/Adam/LiteMenuLexAnd.BIN"))
      bfh = Load("A:/Adam/LiteMenuLexAnd.BIN", LDF_JUST_LOAD | LDF_SILENT);
    else
      bfh = Load("A:/Adam/LiteMenuLex.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuLexSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex Call OK (LexSelfTest=8).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — Guest_Lex Call soft-fail r=", r);
    }
  } else if (FileFind("A:/Adam/LiteMenuLex.PRJ"))
    RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex Cmp soft-skip (Runtime miss).\n");
  // Soft Call: stock PrsDocFlags +CX (DocPlain_RV) after Soft Calls; wire Menu CmpCtrl.
  if (FileFind("A:/Adam/LiteDocFlag.BIN")) {
    I64 cmp_addrs[4], n_cmp;
    n_cmp = RVCmpCtrlAddrsGet(cmp_addrs);
    RVMenuWireCmpCtrlAddrs(cmp_addrs);
    no_warn n_cmp;
    RVCmpExportOne("RVDocPrsFlagsProbe", &RVDocPrsFlagsProbe);
    bfh = Load("A:/Adam/LiteDocFlag.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVDocFlagSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — DocFlag Soft Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — DocFlag Soft Call OK (PrsDocFlags +CX).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — DocFlag Soft soft-fail r=3 (CmpCtrl fps).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — DocFlag Soft soft-fail r=4 (CENTER_X).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — DocFlag Soft soft-fail r=", r);
    }
  }
  // Soft Call DocInitInc Soft tip — Soft Call hangs after Soft Cmp (hang class;
  // Soft Cmp stays above). Soft-skip Soft Call so StartOS Load Kernel.BIN proves.
  if (FileFind("A:/Adam/LiteDocInitInc.BIN"))
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitInc Soft Call soft-skip (hang after DocInitInc Soft Cmp).\n");
  else if (FileFind("A:/Adam/LiteDocInitInc.PRJ") || FileFind("A:/Compiler/LiteDocInitInc.PRJ"))
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitInc Soft Call soft-skip (no BIN).\n");
  // Soft Call Soft #include unmodified stock DocInit_RV — Soft Cmp soft-skipped (hang).
  RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock Soft Call soft-skip (Soft #include stock Soft Cmp hang).\n");
  // Soft product Menu Soft Cmp+Call (PreferLite RedSea seeds; g_lex_ret Soft glbl).
  // Soft Call MenuFpOk kept green (+menufpokcall). Soft Call MenuLex/NewCmp* retry.
  RVPhase3Uart("RVPhase3: P6 bisect — product MenuFpOk Soft Cmp...\n");
  src = "I64 RVMenuFpOk(I64 fp)\n" "{\n" "  if (!fp)\n" "    return 0;\n" "  if (fp & 1)\n" "    return 0;\n" "  if (fp < 0x10000)\n" "    return 0;\n" "  return 1;\n" "}\n" "\n" "I64 RVMenuFpsWired(I64 a, I64 b, I64 c, I64 d)\n" "{\n" "  if (!RVMenuFpOk(a))\n" "    return 0;\n" "  if (!RVMenuFpOk(b))\n" "    return 0;\n" "  if (!RVMenuFpOk(c))\n" "    return 0;\n" "  if (!RVMenuFpOk(d))\n" "    return 0;\n" "  return 1;\n" "}\n" "\n" "public I64 RVMenuFpOkSelfTest()\n" "{\n" "  I64 good;\n" "  if (RVMenuFpOk(0))\n" "    return 1;\n" "  if (RVMenuFpOk(1))\n" "    return 2;\n" "  if (RVMenuFpOk(0x1000))\n" "    return 3;\n" "  if (!RVMenuFpOk(0x20000))\n" "    return 4;\n" "  if (!RVMenuFpOk(0x80001000))\n" "    return 7;\n" "  good = 0x80001000;\n" "  if (!RVMenuFpOk(good))\n" "    return 9;\n" "  if (RVMenuFpsWired(0x20000, 0x21000, 0x22000, 1))\n" "    return 5;\n" "  if (!RVMenuFpsWired(0x20000, 0x21000, 0x22000, 0x23000))\n" "    return 6;\n" "  return 8;\n" "}\n";
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteMenuFpOk.PRJ", "A:/Adam/LiteMenuFpOk.PRJ", src, "RVPhase3: LiteMenuFpOk RedSea seed (no ELF FileWrite).\n");
  if (!RVPhase3CmpWrite(prj, "A:/Adam/LiteMenuFpOk.BIN", "RVPhase3: P6 bisect product MenuFpOk BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuFpOk Soft Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuFpOk Soft Cmp OK.\n");
  if (FileFind("A:/Adam/LiteMenuFpOk.BIN")) {
    bfh = Load("A:/Adam/LiteMenuFpOk.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuFpOkSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuFpOk Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuFpOk Call OK (CmpCtrl gate).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — product MenuFpOk soft-fail r=", r);
    }
  }
  RVPhase3Uart("RVPhase3: P6 bisect — product MenuLexI64Soft Soft Cmp...\n");
  src = "I64 g_lex_fp;\n" "I64 g_toks[8];\n" "I64 g_tok_n;\n" "I64 g_tok_i;\n" "I64 g_i64_val;\n" "I64 g_token;\n" "I64 g_cur_i64;\n" "/* Soft Call: live local across SoftLexPlant Soft Call clobbers a0 \u2192 r=1 (v!=8). */\n" "I64 g_lex_ret;\n" "/* Flat Soft I64; SoftLexPlant inlined (no nested Soft Call SoftLexPlant remat r=2). */\n" "/* Soft Call: g_toks[g_tok_i++] is soft in a Loaded module (LexPlant r=3 - the\n" " * index post-inc write-back never lands and the load reads the wrong element).\n" " * Plain g_toks[i]/g_toks[g_tok_i] are fine (LexPlant idx r=8), so hoist the\n" " * index into a local and store the bump explicitly. */\n" "I64 MenuLexI64SoftGlbl()\n" "{\n" "  I64 steps;\n" "  I64 t;\n" "  I64 ti;\n" "  if (!g_lex_fp)\n" "    return 0;\n" "  if (g_token == ',' || g_token == ')')\n" "    return 0;\n" "  if (g_token == 0x102) {\n" "    g_lex_ret = g_cur_i64;\n" "    if (g_tok_i >= g_tok_n)\n" "      g_token = 0;\n" "    else {\n" "      ti = g_tok_i;\n" "      t = g_toks[ti];\n" "      g_tok_i = ti + 1;\n" "      g_token = t;\n" "      if (t == 0x102)\n" "        g_cur_i64 = g_i64_val;\n" "    }\n" "    return g_lex_ret;\n" "  }\n" "  if (g_token == 0x103) {\n" "    g_lex_ret = g_cur_i64;\n" "    if (g_tok_i >= g_tok_n)\n" "      g_token = 0;\n" "    else {\n" "      ti = g_tok_i;\n" "      t = g_toks[ti];\n" "      g_tok_i = ti + 1;\n" "      g_token = t;\n" "      if (t == 0x102)\n" "        g_cur_i64 = g_i64_val;\n" "    }\n" "    return g_lex_ret;\n" "  }\n" "  steps = 0;\n" "  while (g_token && g_token != ',' && g_token != ')' && steps < 64) {\n" "    if (g_tok_i >= g_tok_n)\n" "      g_token = 0;\n" "    else {\n" "      ti = g_tok_i;\n" "      t = g_toks[ti];\n" "      g_tok_i = ti + 1;\n" "      g_token = t;\n" "      if (t == 0x102)\n" "        g_cur_i64 = g_i64_val;\n" "    }\n" "    steps++;\n" "  }\n" "  return 0;\n" "}\n" "\n" "public I64 RVMenuLexI64SoftSelfTest()\n" "{\n" "  I64 v;\n" "  g_lex_fp = 1;\n" "  g_tok_n = 1;\n" "  g_tok_i = 0;\n" "  g_i64_val = 0;\n" "  g_toks[0] = ',';\n" "  g_token = 0x102;\n" "  g_cur_i64 = 8;\n" "  v = MenuLexI64SoftGlbl();\n" "  if (v != 8)\n" "    return 1;\n" "  if (g_token != ',')\n" "    return 2;\n" "  g_lex_fp = 0;\n" "  g_token = 0x102;\n" "  g_cur_i64 = 9;\n" "  if (MenuLexI64SoftGlbl())\n" "    return 3;\n" "  g_lex_fp = 1;\n" "  g_token = ',';\n" "  if (MenuLexI64SoftGlbl())\n" "    return 4;\n" "  g_tok_n = 1;\n" "  g_tok_i = 0;\n" "  g_toks[0] = ')';\n" "  g_token = 0x103;\n" "  g_cur_i64 = 65;\n" "  v = MenuLexI64SoftGlbl();\n" "  if (v != 65)\n" "    return 5;\n" "  return 8;\n" "}\n";
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteMenuLexI64Soft.PRJ", "A:/Adam/LiteMenuLexI64Soft.PRJ", src, "RVPhase3: LiteMenuLexI64Soft RedSea seed (no ELF FileWrite).\n");
  if (!RVPhase3CmpWrite(prj, "A:/Adam/LiteMenuLexI64Soft.BIN", "RVPhase3: P6 bisect product MenuLexI64Soft BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuLexI64Soft Soft Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuLexI64Soft Soft Cmp OK.\n");
  if (FileFind("A:/Adam/LiteMenuLexI64Soft.BIN")) {
    bfh = Load("A:/Adam/LiteMenuLexI64Soft.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuLexI64SoftSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuLexI64Soft Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuLexI64Soft Call OK (planted SoftLex).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — product MenuLexI64Soft soft-fail r=", r);
    }
  }
  RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewSubCmp Soft Cmp...\n");
  RVCmpExportOne("CAlloc", &CAlloc);
  RVCmpExportOne("Free", &Free);
  RVCmpExportOne("StrCpy", &RVStrCpy);
  src = "import U8 *CAlloc(I64 size);\n" "import U0 Free(U8 *addr);\n" "import U8 *StrCpy(U8 *dst, U8 *src);\n" "class CRVLiteCmpCtrl\n" "{\n" "  I64 token;\n" "  I64 cur_i64;\n" "  U8 *cur_str;\n" "};\n" "\n" "class CRVKernMenuEntry\n" "{\n" "  I64 next;\n" "  I64 sub;\n" "  U8 name[32];\n" "  I64 msg_code;\n" "  I64 arg1;\n" "  I64 arg2;\n" "  Bool checked, dir, pad[6];\n" "};\n" "I64 g_lex_fp;\n" "I64 g_toks[8];\n" "I64 g_tok_n;\n" "I64 g_tok_i;\n" "I64 g_i64_val;\n" "U8 g_ident[32];\n" "CRVLiteCmpCtrl g_cc;\n" "/* Soft Call: live local across SoftLexPlant Soft Call clobbers a0 \u2192 Lex soft-fail r=1. */\n" "I64 g_lex_ret;\n" "/* Soft Call: g_toks[g_tok_i++] is soft in a Loaded module (LexPlant r=3 \u2014\n" " * the index post-inc write-back never lands and the load reads the wrong\n" " * element). Plain g_toks[i]/g_toks[g_tok_i] are fine (LexPlant idx r=8), so\n" " * hoist the index into a local and store the bump explicitly. */\n" "I64 SoftLexPlantGlbl()\n" "{\n" "  I64 ti;\n" "  I64 t;\n" "  if (g_tok_i >= g_tok_n) {\n" "    g_cc.token = 0;\n" "    return 0;\n" "  }\n" "  ti = g_tok_i;\n" "  t = g_toks[ti];\n" "  g_tok_i = ti + 1;\n" "  g_cc.token = t;\n" "  if (t == 0x102)\n" "    g_cc.cur_i64 = g_i64_val;\n" "  if (t == 0x100)\n" "    g_cc.cur_str = g_ident;\n" "  return t;\n" "}\n" "\n" "I64 MenuLexI64SoftGlbl()\n" "{\n" "  I64 steps;\n" "  if (!g_lex_fp)\n" "    return 0;\n" "  if (g_cc.token == ',' || g_cc.token == ')')\n" "    return 0;\n" "  if (g_cc.token == 0x102) {\n" "    g_lex_ret = g_cc.cur_i64;\n" "    SoftLexPlantGlbl();\n" "    return g_lex_ret;\n" "  }\n" "  if (g_cc.token == 0x103) {\n" "    g_lex_ret = g_cc.cur_i64;\n" "    SoftLexPlantGlbl();\n" "    return g_lex_ret;\n" "  }\n" "  steps = 0;\n" "  while (g_cc.token && g_cc.token != ',' && g_cc.token != ')' && steps < 64) {\n" "    SoftLexPlantGlbl();\n" "    steps++;\n" "  }\n" "  return 0;\n" "}\n" "/* Soft Call SelfTest avoids &g_cc Soft CALL remat; use Fun() not Fun. */\n" "CRVKernMenuEntry *MenuNewSubCmpGlbl()\n" "{\n" "  CRVKernMenuEntry *tmpme;\n" "  if (!g_lex_fp)\n" "    return 0;\n" "  if (g_cc.token != 0x100)\n" "    return 0;\n" "  tmpme = CAlloc(sizeof(CRVKernMenuEntry));\n" "  if (!tmpme)\n" "    return 0;\n" "  if (g_cc.cur_str)\n" "    StrCpy(tmpme->name, g_cc.cur_str);\n" "  if (SoftLexPlantGlbl() == '(') {\n" "    tmpme->msg_code = -2;\n" "    if (SoftLexPlantGlbl() != ',' && g_cc.token != ')')\n" "      tmpme->msg_code = MenuLexI64SoftGlbl();\n" "    if (g_cc.token == ',')\n" "      SoftLexPlantGlbl();\n" "    if (g_cc.token != ',' && g_cc.token != ')')\n" "      tmpme->arg1 = MenuLexI64SoftGlbl();\n" "    if (g_cc.token == ',')\n" "      SoftLexPlantGlbl();\n" "    if (g_cc.token != ',' && g_cc.token != ')')\n" "      tmpme->arg2 = MenuLexI64SoftGlbl();\n" "    if (g_cc.token != ')')\n" "      SoftLexPlantGlbl();\n" "    if (SoftLexPlantGlbl() != ';')\n" "      ;\n" "    SoftLexPlantGlbl();\n" "  }\n" "  return tmpme;\n" "}\n" "\n" "public I64 RVMenuNewSubCmpSelfTest()\n" "{\n" "  CRVKernMenuEntry *e;\n" "  I64 ne;\n" "  ne = sizeof(CRVKernMenuEntry);\n" "  if (ne != 80)\n" "    return 2;\n" "  g_lex_fp = 1;\n" "  StrCpy(g_ident, \"Tile\");\n" "  g_i64_val = 8;\n" "  g_tok_n = 5;\n" "  g_tok_i = 0;\n" "  g_toks[0] = '(';\n" "  g_toks[1] = ',';\n" "  g_toks[2] = 0x102;\n" "  g_toks[3] = ')';\n" "  g_toks[4] = ';';\n" "  g_cc.token = 0x100;\n" "  g_cc.cur_i64 = 0;\n" "  g_cc.cur_str = g_ident;\n" "  e = MenuNewSubCmpGlbl();\n" "  if (!e)\n" "    return 3;\n" "  if (e->name[0] != 'T') {\n" "    Free(e);\n" "    return 4;\n" "  }\n" "  if (e->arg1 != 8) {\n" "    Free(e);\n" "    return 5;\n" "  }\n" "  if (e->msg_code != -2) {\n" "    Free(e);\n" "    return 6;\n" "  }\n" "  Free(e);\n" "  return 8;\n" "}\n";
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteMenuNewSubCmp.PRJ", "A:/Adam/LiteMenuNewSubCmp.PRJ", src, "RVPhase3: LiteMenuNewSubCmp RedSea seed (no ELF FileWrite).\n");
  if (!RVPhase3CmpWrite(prj, "A:/Adam/LiteMenuNewSubCmp.BIN", "RVPhase3: P6 bisect product MenuNewSubCmp BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewSubCmp Soft Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewSubCmp Soft Cmp OK.
");
  if (FileFind("A:/Adam/LiteMenuNewSubCmp.BIN")) {
    bfh = Load("A:/Adam/LiteMenuNewSubCmp.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuNewSubCmpSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewSubCmp Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewSubCmp Call OK (Tile arg1=8).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — product MenuNewSubCmp soft-fail r=", r);
    }
  }
  RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmp Soft Cmp...\n");
  RVCmpExportOne("CAlloc", &CAlloc);
  RVCmpExportOne("Free", &Free);
  RVCmpExportOne("StrCpy", &RVStrCpy);
  src = "import U8 *CAlloc(I64 size);\n" "import U0 Free(U8 *addr);\n" "import U8 *StrCpy(U8 *dst, U8 *src);\n" "class CRVLiteCmpCtrl\n" "{\n" "  I64 token;\n" "  I64 cur_i64;\n" "  U8 *cur_str;\n" "};\n" "\n" "class CRVKernMenuEntry\n" "{\n" "  I64 next;\n" "  I64 sub;\n" "  U8 name[32];\n" "  I64 msg_code;\n" "  I64 arg1;\n" "  I64 arg2;\n" "  Bool checked, dir, pad[6];\n" "};\n" "\n" "class CRVKernMenu\n" "{\n" "  I64 next;\n" "  I64 sub;\n" "  I64 task;\n" "  I64 flags;\n" "  U8 attr, pad[7];\n" "};\n" "I64 g_fp_new;\n" "I64 g_fp_lex;\n" "I64 g_fp_lex_i64;\n" "I64 g_fp_del;\n" "I64 g_toks[8];\n" "I64 g_tok_n;\n" "I64 g_tok_i;\n" "I64 g_i64_val;\n" "U8 g_ident[32];\n" "/* Soft Call: live local across SoftLexPlant Soft Call clobbers a0 \u2192 Lex soft-fail r=1. */\n" "I64 g_lex_ret;\n" "I64 SoftMenuFpOk(I64 fp)\n" "{\n" "  if (!fp)\n" "    return 0;\n" "  return 1;\n" "}\n" "\n" "I64 SoftMenuFpsWired()\n" "{\n" "  if (!SoftMenuFpOk(g_fp_new))\n" "    return 0;\n" "  if (!SoftMenuFpOk(g_fp_lex))\n" "    return 0;\n" "  if (!SoftMenuFpOk(g_fp_lex_i64))\n" "    return 0;\n" "  if (!SoftMenuFpOk(g_fp_del))\n" "    return 0;\n" "  return 1;\n" "}\n" "/* Soft Call: g_toks[g_tok_i++] is soft in a Loaded module (LexPlant r=3 \u2014\n" " * the index post-inc write-back never lands and the load reads the wrong\n" " * element). Plain g_toks[i]/g_toks[g_tok_i] are fine (LexPlant idx r=8), so\n" " * hoist the index into a local and store the bump explicitly. */\n" "I64 SoftLexPlant(CRVLiteCmpCtrl *cc)\n" "{\n" "  I64 ti;\n" "  I64 t;\n" "  if (!cc || !g_fp_lex)\n" "    return 0;\n" "  if (g_tok_i >= g_tok_n) {\n" "    cc->token = 0;\n" "    return 0;\n" "  }\n" "  ti = g_tok_i;\n" "  t = g_toks[ti];\n" "  g_tok_i = ti + 1;\n" "  cc->token = t;\n" "  if (t == 0x102)\n" "    cc->cur_i64 = g_i64_val;\n" "  if (t == 0x100)\n" "    cc->cur_str = g_ident;\n" "  return t;\n" "}\n" "\n" "CRVLiteCmpCtrl *SoftCmpCtrlNew(U8 *st, I64 flags, U8 *fn)\n" "{\n" "  CRVLiteCmpCtrl *cc;\n" "  if (!g_fp_new)\n" "    return 0;\n" "  cc = CAlloc(sizeof(CRVLiteCmpCtrl));\n" "  if (!cc)\n" "    return 0;\n" "  cc->token = 0;\n" "  cc->cur_i64 = 0;\n" "  cc->cur_str = 0;\n" "  if (st)\n" "    ;\n" "  if (flags)\n" "    ;\n" "  if (fn)\n" "    ;\n" "  return cc;\n" "}\n" "\n" "U0 SoftCmpCtrlDel(CRVLiteCmpCtrl *cc)\n" "{\n" "  if (!g_fp_del)\n" "    return;\n" "  if (cc)\n" "    Free(cc);\n" "}\n" "\n" "I64 MenuLexI64Soft(CRVLiteCmpCtrl *cc)\n" "{\n" "  I64 steps;\n" "  if (!cc || !g_fp_lex)\n" "    return 0;\n" "  if (cc->token == ',' || cc->token == ')')\n" "    return 0;\n" "  if (cc->token == 0x102) {\n" "    g_lex_ret = cc->cur_i64;\n" "    SoftLexPlant(cc);\n" "    return g_lex_ret;\n" "  }\n" "  if (cc->token == 0x103) {\n" "    g_lex_ret = cc->cur_i64;\n" "    SoftLexPlant(cc);\n" "    return g_lex_ret;\n" "  }\n" "  steps = 0;\n" "  while (cc->token && cc->token != ',' && cc->token != ')' && steps < 64) {\n" "    SoftLexPlant(cc);\n" "    steps++;\n" "  }\n" "  return 0;\n" "}\n" "\n" "CRVKernMenuEntry *MenuNewSubCmp(CRVLiteCmpCtrl *cc)\n" "{\n" "  CRVKernMenuEntry *tmpme;\n" "  if (!cc || !g_fp_lex)\n" "    return 0;\n" "  if (cc->token != 0x100)\n" "    return 0;\n" "  tmpme = CAlloc(sizeof(CRVKernMenuEntry));\n" "  if (!tmpme)\n" "    return 0;\n" "  if (cc->cur_str)\n" "    StrCpy(tmpme->name, cc->cur_str);\n" "  if (SoftLexPlant(cc) == '(') {\n" "    tmpme->msg_code = -2;\n" "    if (SoftLexPlant(cc) != ',' && cc->token != ')')\n" "      tmpme->msg_code = MenuLexI64Soft(cc);\n" "    if (cc->token == ',')\n" "      SoftLexPlant(cc);\n" "    if (cc->token != ',' && cc->token != ')')\n" "      tmpme->arg1 = MenuLexI64Soft(cc);\n" "    if (cc->token == ',')\n" "      SoftLexPlant(cc);\n" "    if (cc->token != ',' && cc->token != ')')\n" "      tmpme->arg2 = MenuLexI64Soft(cc);\n" "    if (cc->token != ')')\n" "      SoftLexPlant(cc);\n" "    if (SoftLexPlant(cc) != ';')\n" "      ;\n" "    SoftLexPlant(cc);\n" "  }\n" "  return tmpme;\n" "}\n" "\n" "CRVKernMenu *MenuNewCmp(U8 *st, I64 flags)\n" "{\n" "  CRVKernMenu *m;\n" "  CRVLiteCmpCtrl *cc;\n" "  if (!SoftMenuFpsWired())\n" "    return 0;\n" "  cc = SoftCmpCtrlNew(st, 0, 0);\n" "  if (!cc)\n" "    return 0;\n" "  SoftLexPlant(cc);\n" "  m = CAlloc(sizeof(CRVKernMenu));\n" "  if (!m) {\n" "    SoftCmpCtrlDel(cc);\n" "    return 0;\n" "  }\n" "  m->flags = flags;\n" "  m->attr = 7;\n" "  m->sub = MenuNewSubCmp(cc);\n" "  SoftCmpCtrlDel(cc);\n" "  return m;\n" "}\n" "\n" "public I64 RVMenuNewCmpSelfTest()\n" "{\n" "  CRVKernMenu *m;\n" "  CRVKernMenuEntry *e;\n" "  I64 ne;\n" "  I64 nm;\n" "  ne = sizeof(CRVKernMenuEntry);\n" "  nm = sizeof(CRVKernMenu);\n" "  if (ne != 80)\n" "    return 2;\n" "  if (nm != 40)\n" "    return 3;\n" "  g_fp_new = 0;\n" "  g_fp_lex = 0;\n" "  g_fp_lex_i64 = 0;\n" "  g_fp_del = 0;\n" "  if (MenuNewCmp(0, 8))\n" "    return 1;\n" "  g_fp_new = 1;\n" "  g_fp_lex = 1;\n" "  g_fp_lex_i64 = 1;\n" "  g_fp_del = 1;\n" "  StrCpy(g_ident, \"Tile\");\n" "  g_i64_val = 8;\n" "  g_tok_n = 6;\n" "  g_tok_i = 0;\n" "  g_toks[0] = 0x100;\n" "  g_toks[1] = '(';\n" "  g_toks[2] = ',';\n" "  g_toks[3] = 0x102;\n" "  g_toks[4] = ')';\n" "  g_toks[5] = ';';\n" "  m = MenuNewCmp(0, 8);\n" "  if (!m)\n" "    return 4;\n" "  if (m->flags != 8) {\n" "    if (m->sub)\n" "      Free(m->sub);\n" "    Free(m);\n" "    return 5;\n" "  }\n" "  e = m->sub;\n" "  if (!e) {\n" "    Free(m);\n" "    return 6;\n" "  }\n" "  if (e->name[0] != 'T') {\n" "    Free(e);\n" "    Free(m);\n" "    return 7;\n" "  }\n" "  if (e->arg1 != 8) {\n" "    Free(e);\n" "    Free(m);\n" "    return 9;\n" "  }\n" "  Free(e);\n" "  Free(m);\n" "  return 8;\n" "}\n";
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteMenuNewCmp.PRJ", "A:/Adam/LiteMenuNewCmp.PRJ", src, "RVPhase3: LiteMenuNewCmp RedSea seed (no ELF FileWrite).\n");
  if (!RVPhase3CmpWrite(prj, "A:/Adam/LiteMenuNewCmp.BIN", "RVPhase3: P6 bisect product MenuNewCmp BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmp Soft Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmp Soft Cmp OK.
");
  if (FileFind("A:/Adam/LiteMenuNewCmp.BIN")) {
    bfh = Load("A:/Adam/LiteMenuNewCmp.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuNewCmpSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmp Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmp Call OK (Tile arg1=8).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — product MenuNewCmp soft-fail r=", r);
    }
  }
  RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmpCtrl Soft Cmp...\n");
  RVCmpExportOne("CAlloc", &CAlloc);
  RVCmpExportOne("Free", &Free);
  RVCmpExportOne("StrCpy", &RVStrCpy);
  src = "import U8 *CAlloc(I64 size);\n" "import U0 Free(U8 *addr);\n" "import U8 *StrCpy(U8 *dst, U8 *src);\n" "class CRVLiteCmpCtrl\n" "{\n" "  I64 token;\n" "  I64 cur_i64;\n" "  U8 *cur_str;\n" "};\n" "\n" "class CRVKernMenuEntry\n" "{\n" "  I64 next;\n" "  I64 sub;\n" "  U8 name[32];\n" "  I64 msg_code;\n" "  I64 arg1;\n" "  I64 arg2;\n" "  Bool checked, dir, pad[6];\n" "};\n" "\n" "class CRVKernMenu\n" "{\n" "  I64 next;\n" "  I64 sub;\n" "  I64 task;\n" "  I64 flags;\n" "  U8 attr, pad[7];\n" "};\n" "I64 g_fp_new;\n" "I64 g_fp_lex;\n" "I64 g_fp_lex_i64;\n" "I64 g_fp_del;\n" "I64 g_toks[8];\n" "I64 g_tok_n;\n" "I64 g_tok_i;\n" "I64 g_i64_val;\n" "U8 g_ident[32];\n" "/* Soft Call: live local across SoftLexPlant Soft Call clobbers a0 \u2192 Lex soft-fail r=1. */\n" "I64 g_lex_ret;\n" "I64 SoftMenuFpOk(I64 fp)\n" "{\n" "  if (!fp)\n" "    return 0;\n" "  return 1;\n" "}\n" "\n" "I64 SoftMenuFpsWired()\n" "{\n" "  if (!SoftMenuFpOk(g_fp_new))\n" "    return 0;\n" "  if (!SoftMenuFpOk(g_fp_lex))\n" "    return 0;\n" "  if (!SoftMenuFpOk(g_fp_lex_i64))\n" "    return 0;\n" "  if (!SoftMenuFpOk(g_fp_del))\n" "    return 0;\n" "  return 1;\n" "}\n" "/* Soft Call: g_toks[g_tok_i++] is soft in a Loaded module (LexPlant r=3 \u2014\n" " * the index post-inc write-back never lands and the load reads the wrong\n" " * element). Plain g_toks[i]/g_toks[g_tok_i] are fine (LexPlant idx r=8), so\n" " * hoist the index into a local and store the bump explicitly. */\n" "I64 SoftLexPlant(CRVLiteCmpCtrl *cc)\n" "{\n" "  I64 ti;\n" "  I64 t;\n" "  if (!cc || !g_fp_lex)\n" "    return 0;\n" "  if (g_tok_i >= g_tok_n) {\n" "    cc->token = 0;\n" "    return 0;\n" "  }\n" "  ti = g_tok_i;\n" "  t = g_toks[ti];\n" "  g_tok_i = ti + 1;\n" "  cc->token = t;\n" "  if (t == 0x102)\n" "    cc->cur_i64 = g_i64_val;\n" "  if (t == 0x100)\n" "    cc->cur_str = g_ident;\n" "  return t;\n" "}\n" "\n" "CRVLiteCmpCtrl *SoftCmpCtrlNew(U8 *st, I64 flags, U8 *fn)\n" "{\n" "  CRVLiteCmpCtrl *cc;\n" "  if (!g_fp_new)\n" "    return 0;\n" "  cc = CAlloc(sizeof(CRVLiteCmpCtrl));\n" "  if (!cc)\n" "    return 0;\n" "  cc->token = 0;\n" "  cc->cur_i64 = 0;\n" "  cc->cur_str = 0;\n" "  if (st)\n" "    ;\n" "  if (flags)\n" "    ;\n" "  if (fn)\n" "    ;\n" "  return cc;\n" "}\n" "\n" "U0 SoftCmpCtrlDel(CRVLiteCmpCtrl *cc)\n" "{\n" "  if (!g_fp_del)\n" "    return;\n" "  if (cc)\n" "    Free(cc);\n" "}\n" "\n" "I64 MenuLexI64Soft(CRVLiteCmpCtrl *cc)\n" "{\n" "  I64 steps;\n" "  if (!cc || !g_fp_lex)\n" "    return 0;\n" "  if (cc->token == ',' || cc->token == ')')\n" "    return 0;\n" "  if (cc->token == 0x102) {\n" "    g_lex_ret = cc->cur_i64;\n" "    SoftLexPlant(cc);\n" "    return g_lex_ret;\n" "  }\n" "  if (cc->token == 0x103) {\n" "    g_lex_ret = cc->cur_i64;\n" "    SoftLexPlant(cc);\n" "    return g_lex_ret;\n" "  }\n" "  steps = 0;\n" "  while (cc->token && cc->token != ',' && cc->token != ')' && steps < 64) {\n" "    SoftLexPlant(cc);\n" "    steps++;\n" "  }\n" "  return 0;\n" "}\n" "\n" "CRVKernMenuEntry *MenuNewSubCmp(CRVLiteCmpCtrl *cc)\n" "{\n" "  CRVKernMenuEntry *tmpme;\n" "  if (!cc || !g_fp_lex)\n" "    return 0;\n" "  if (cc->token != 0x100)\n" "    return 0;\n" "  tmpme = CAlloc(sizeof(CRVKernMenuEntry));\n" "  if (!tmpme)\n" "    return 0;\n" "  if (cc->cur_str)\n" "    StrCpy(tmpme->name, cc->cur_str);\n" "  if (SoftLexPlant(cc) == '(') {\n" "    tmpme->msg_code = -2;\n" "    if (SoftLexPlant(cc) != ',' && cc->token != ')')\n" "      tmpme->msg_code = MenuLexI64Soft(cc);\n" "    if (cc->token == ',')\n" "      SoftLexPlant(cc);\n" "    if (cc->token != ',' && cc->token != ')')\n" "      tmpme->arg1 = MenuLexI64Soft(cc);\n" "    if (cc->token == ',')\n" "      SoftLexPlant(cc);\n" "    if (cc->token != ',' && cc->token != ')')\n" "      tmpme->arg2 = MenuLexI64Soft(cc);\n" "    if (cc->token != ')')\n" "      SoftLexPlant(cc);\n" "    if (SoftLexPlant(cc) != ';')\n" "      ;\n" "    SoftLexPlant(cc);\n" "  }\n" "  return tmpme;\n" "}\n" "\n" "CRVKernMenu *MenuNewCmp(U8 *st, I64 flags)\n" "{\n" "  CRVKernMenu *m;\n" "  CRVLiteCmpCtrl *cc;\n" "  if (!SoftMenuFpsWired())\n" "    return 0;\n" "  cc = SoftCmpCtrlNew(st, 0, 0);\n" "  if (!cc)\n" "    return 0;\n" "  SoftLexPlant(cc);\n" "  m = CAlloc(sizeof(CRVKernMenu));\n" "  if (!m) {\n" "    SoftCmpCtrlDel(cc);\n" "    return 0;\n" "  }\n" "  m->flags = flags;\n" "  m->attr = 7;\n" "  m->sub = MenuNewSubCmp(cc);\n" "  SoftCmpCtrlDel(cc);\n" "  return m;\n" "}\n" "\n" "CRVKernMenu *MenuNewHandStub(U8 *st, I64 flags)\n" "{\n" "  CRVKernMenu *m;\n" "  m = CAlloc(sizeof(CRVKernMenu));\n" "  if (!m)\n" "    return 0;\n" "  m->flags = flags;\n" "  m->attr = 1;\n" "  if (st)\n" "    ;\n" "  return m;\n" "}\n" "\n" "CRVKernMenu *MenuNewCmpCtrl(U8 *st, I64 flags)\n" "{\n" "  CRVKernMenu *m;\n" "  if (!SoftMenuFpsWired())\n" "    return MenuNewHandStub(st, flags);\n" "  m = MenuNewCmp(st, flags);\n" "  if (!m || !m->sub) {\n" "    if (m) {\n" "      if (m->sub)\n" "        Free(m->sub);\n" "      Free(m);\n" "    }\n" "    return MenuNewHandStub(st, flags);\n" "  }\n" "  return m;\n" "}\n" "\n" "public I64 RVMenuNewCmpCtrlSelfTest()\n" "{\n" "  CRVKernMenu *m;\n" "  CRVKernMenuEntry *e;\n" "  I64 ne;\n" "  I64 nm;\n" "  ne = sizeof(CRVKernMenuEntry);\n" "  nm = sizeof(CRVKernMenu);\n" "  if (ne != 80)\n" "    return 2;\n" "  if (nm != 40)\n" "    return 3;\n" "  g_fp_new = 0;\n" "  g_fp_lex = 0;\n" "  g_fp_lex_i64 = 0;\n" "  g_fp_del = 0;\n" "  m = MenuNewCmpCtrl(0, 8);\n" "  if (!m)\n" "    return 1;\n" "  if (m->attr != 1) {\n" "    Free(m);\n" "    return 4;\n" "  }\n" "  if (m->flags != 8) {\n" "    Free(m);\n" "    return 5;\n" "  }\n" "  Free(m);\n" "  g_fp_new = 1;\n" "  g_fp_lex = 1;\n" "  g_fp_lex_i64 = 1;\n" "  g_fp_del = 1;\n" "  StrCpy(g_ident, \"Tile\");\n" "  g_i64_val = 8;\n" "  g_tok_n = 6;\n" "  g_tok_i = 0;\n" "  g_toks[0] = 0x100;\n" "  g_toks[1] = '(';\n" "  g_toks[2] = ',';\n" "  g_toks[3] = 0x102;\n" "  g_toks[4] = ')';\n" "  g_toks[5] = ';';\n" "  m = MenuNewCmpCtrl(0, 8);\n" "  if (!m)\n" "    return 6;\n" "  if (m->attr != 7) {\n" "    if (m->sub)\n" "      Free(m->sub);\n" "    Free(m);\n" "    return 7;\n" "  }\n" "  e = m->sub;\n" "  if (!e) {\n" "    Free(m);\n" "    return 9;\n" "  }\n" "  if (e->name[0] != 'T') {\n" "    Free(e);\n" "    Free(m);\n" "    return 10;\n" "  }\n" "  if (e->arg1 != 8) {\n" "    Free(e);\n" "    Free(m);\n" "    return 11;\n" "  }\n" "  Free(e);\n" "  Free(m);\n" "  return 8;\n" "}\n";
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteMenuNewCmpCtrl.PRJ", "A:/Adam/LiteMenuNewCmpCtrl.PRJ", src, "RVPhase3: LiteMenuNewCmpCtrl RedSea seed (no ELF FileWrite).\n");
  if (!RVPhase3CmpWrite(prj, "A:/Adam/LiteMenuNewCmpCtrl.BIN", "RVPhase3: P6 bisect product MenuNewCmpCtrl BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmpCtrl Soft Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmpCtrl Soft Cmp OK.
");
  if (FileFind("A:/Adam/LiteMenuNewCmpCtrl.BIN")) {
    bfh = Load("A:/Adam/LiteMenuNewCmpCtrl.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuNewCmpCtrlSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmpCtrl Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — product MenuNewCmpCtrl Call OK (Tile arg1=8).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — product MenuNewCmpCtrl soft-fail r=", r);
    }
  }
  // Soft PopUp Soft Win + planted fps join Soft Cmp+Call (+popupsoftwinfpcall).
  RVPhase3Uart("RVPhase3: P6 bisect — Soft PopUp Soft Win Fp Soft Cmp...\n");
  src = "import U8 *CAlloc(I64 size);\n" "import U0 Free(U8 *addr);\n" "import U8 *StrCpy(U8 *dst, U8 *src);\n" "import I64 StrCmp(U8 *a, U8 *b);\n" "#define RV_SOFT_POPUP_NONE 0\n" "#define RV_SOFT_POPUP_OK 1\n" "#define RV_SOFT_WIN_MAX 4\n" "class CRVSoftWin\n" "{\n" "  I64 used;\n" "  I64 show;\n" "  U8 title[16];\n" "};\n" "I64 g_fp_open;\n" "I64 g_fp_resolve;\n" "I64 g_popup_mode;\n" "I64 g_popup_idx;\n" "I64 g_popup_result;\n" "CRVSoftWin g_wins[4];\n" "I64 SoftPopUpFpOk(I64 fp)\n" "{\n" "  if (!fp)\n" "    return 0;\n" "  return 1;\n" "}\n" "\n" "I64 SoftPopUpFpsWired()\n" "{\n" "  if (!SoftPopUpFpOk(g_fp_open))\n" "    return 0;\n" "  if (!SoftPopUpFpOk(g_fp_resolve))\n" "    return 0;\n" "  return 1;\n" "}\n" "\n" "U0 SoftPopUpClose()\n" "{\n" "  I64 idx;\n" "  idx = g_popup_idx;\n" "  if (g_popup_mode == RV_SOFT_POPUP_NONE) {\n" "    g_popup_idx = -1;\n" "    return;\n" "  }\n" "  if (idx >= 0 && idx < RV_SOFT_WIN_MAX) {\n" "    g_wins[idx].used = 0;\n" "    g_wins[idx].show = 0;\n" "  }\n" "  g_popup_idx = -1;\n" "  g_popup_mode = RV_SOFT_POPUP_NONE;\n" "}\n" "\n" "I64 SoftPopUpOk(U8 *header)\n" "{\n" "  I64 i;\n" "  I64 idx;\n" "  if (!SoftPopUpFpsWired)\n" "    return 0;\n" "  if (!header)\n" "    return 0;\n" "  SoftPopUpClose;\n" "  idx = -1;\n" "  for (i = 0; i < RV_SOFT_WIN_MAX; i++) {\n" "    if (!g_wins[i].used) {\n" "      idx = i;\n" "      break;\n" "    }\n" "  }\n" "  if (idx < 0)\n" "    return 0;\n" "  g_wins[idx].used = 1;\n" "  g_wins[idx].show = 1;\n" "  StrCpy(g_wins[idx].title, \"PopUp\");\n" "  g_popup_mode = RV_SOFT_POPUP_OK;\n" "  g_popup_idx = idx;\n" "  return 1;\n" "}\n" "\n" "I64 SoftPopUpResolve(I64 val)\n" "{\n" "  if (!SoftPopUpFpOk(g_fp_resolve))\n" "    return 0;\n" "  if (g_popup_mode == RV_SOFT_POPUP_NONE)\n" "    return 0;\n" "  g_popup_result = val;\n" "  SoftPopUpClose;\n" "  return 1;\n" "}\n" "\n" "public I64 RVPopUpSoftWinFpSelfTest()\n" "{\n" "  I64 idx;\n" "  CRVSoftWin *w;\n" "  g_fp_open = 0;\n" "  g_fp_resolve = 0;\n" "  g_popup_mode = RV_SOFT_POPUP_NONE;\n" "  g_popup_idx = -1;\n" "  g_popup_result = -1;\n" "  g_wins[0].used = 0;\n" "  g_wins[1].used = 0;\n" "  g_wins[2].used = 0;\n" "  g_wins[3].used = 0;\n" "  if (SoftPopUpOk(\"SoftCRV\"))\n" "    return 1;\n" "  g_fp_open = 1;\n" "  g_fp_resolve = 1;\n" "  if (!SoftPopUpFpsWired)\n" "    return 2;\n" "  if (!SoftPopUpOk(\"SoftCRV\"))\n" "    return 3;\n" "  if (g_popup_mode != RV_SOFT_POPUP_OK)\n" "    return 4;\n" "  idx = g_popup_idx;\n" "  if (idx < 0 || idx >= RV_SOFT_WIN_MAX)\n" "    return 5;\n" "  w = &g_wins[idx];\n" "  if (!w->used || !w->show)\n" "    return 6;\n" "  if (StrCmp(w->title, \"PopUp\"))\n" "    return 7;\n" "  if (!SoftPopUpResolve(1))\n" "    return 9;\n" "  if (g_popup_mode != RV_SOFT_POPUP_NONE || g_popup_idx >= 0)\n" "    return 10;\n" "  if (w->used || w->show)\n" "    return 11;\n" "  if (g_popup_result != 1)\n" "    return 12;\n" "  g_fp_resolve = 0;\n" "  if (SoftPopUpOk(\"SoftCRV\"))\n" "    return 13;\n" "  return 8;\n" "}\n";
  prj = RVPhase3PreferLitePrj("A:/Compiler/LitePopUpSoftWinFp.PRJ", "A:/Adam/LitePopUpSoftWinFp.PRJ", src, "RVPhase3: LitePopUpSoftWinFp RedSea seed (no ELF FileWrite).\n");
  if (!RVPhase3CmpWrite(prj, "A:/Adam/LitePopUpSoftWinFp.BIN", "RVPhase3: P6 bisect Soft PopUp Soft Win Fp BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Soft PopUp Soft Win Fp Soft Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Soft PopUp Soft Win Fp Soft Cmp OK.\n");
  if (FileFind("A:/Adam/LitePopUpSoftWinFp.BIN")) {
    RVCmpExportOne("CAlloc", &CAlloc);
    RVCmpExportOne("Free", &Free);
    RVCmpExportOne("StrCpy", &RVStrCpy);
    RVCmpExportOne("StrCmp", &RVStrCmp);
    bfh = Load("A:/Adam/LitePopUpSoftWinFp.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVPopUpSoftWinFpSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — Soft PopUp Soft Win Fp Soft Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — Soft PopUp Soft Win Fp Soft Call OK (Soft Ok/Resolve Soft Win).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — Soft PopUp Soft Win Fp soft-fail r=", r);
    }
  }
  // Soft Call CMenu+CAlloc after Guest_Lex (I64-only class; sizeof+CAlloc).
  if (FileFind("A:/Adam/LiteCMenu.BIN")) {
    RVCmpExportOne("CAlloc", &CAlloc);
    RVCmpExportOne("Free", &Free);
    bfh = Load("A:/Adam/LiteCMenu.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuCMenuSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — CMenu+CAlloc Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — CMenu+CAlloc Call OK (flags=8).\n");
      else if (r == 1)
        RVPhase3Uart("RVPhase3: P6 bisect — CMenu+CAlloc Call soft-fail r=1 (stack member).\n");
      else if (r == 2)
        RVPhase3Uart("RVPhase3: P6 bisect — CMenu+CAlloc Call soft-fail r=2 (sizeof).\n");
      else if (r == 3)
        RVPhase3Uart("RVPhase3: P6 bisect — CMenu+CAlloc Call soft-fail r=3 (CAlloc null).\n");
      else if (r == 4)
        RVPhase3Uart("RVPhase3: P6 bisect — CMenu+CAlloc Call soft-fail r=4 (heap m->flags).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — CMenu+CAlloc Call soft-fail r=", r);
    }
  }
  back = FileRead("A:/Adam/CORE.TXT", &sz, NULL);
  if (!back || sz < 10) {
    if (back)
      Free(back);
    RVPhase3Uart("RVPhase3: Adam CORE.TXT missing (guest AdamCore).\n");
    return FALSE;
  }
  Free(back);
  // Primary StartOS body: Load guest-Cmp'd StartOS.BIN (not host-staged ExeFile string).
  if (!FileFind("A:/Adam/StartOS.BIN")) {
    RVPhase3Uart("RVPhase3: StartOS needs A:/Adam/StartOS.BIN.\n");
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: StartOS Load StartOS.BIN...\n");
  bfh = Load("A:/Adam/StartOS.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: StartOS StartOS.BIN Load FAILED.\n");
    return FALSE;
  }
  r = RVPhase3CallExport("StartOSProbe");
  if (r != 1) {
    RVPhase3Uart("RVPhase3: StartOS StartOSProbe FAILED.\n");
    return FALSE;
  }
  FileWrite("A:/Adam/STARTOS.OK", "OK", 2);
  rv_phase3_include_ok = TRUE;
  RVPhase3Uart("RVPhase3: StartOS Load StartOS.BIN OK (StartOSProbe=1).\n");
  // HolyC-built Runtime seed must be present (guest Cmp, not host AOT of the demo).
  if (!FileFind("A:/Runtime/SEED.OK") || !FileFind("A:/Runtime/Seed.BIN")) {
    RVPhase3Uart("RVPhase3: StartOS needs guest Runtime Seed.BIN/SEED.OK.\n");
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: StartOS Load Seed.BIN...\n");
  bfh = Load("A:/Runtime/Seed.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: StartOS Seed.BIN Load FAILED.\n");
    return FALSE;
  }
  r = RVPhase3CallExport("RuntimeSeedInit");
  if (r != 42) {
    RVPhase3Uart("RVPhase3: StartOS Seed Load+Call FAILED.\n");
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: StartOS Load Seed.BIN OK (RuntimeSeedInit=42).\n");
  if (!FileFind("A:/Runtime/Svc.BIN")) {
    RVPhase3Uart("RVPhase3: StartOS needs A:/Runtime/Svc.BIN.\n");
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: StartOS Load Svc.BIN...\n");
  bfh = Load("A:/Runtime/Svc.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: StartOS Svc.BIN Load FAILED.\n");
    return FALSE;
  }
  r = RVPhase3CallExport("RuntimeSvcProbe");
  if (r != 42) {
    RVPhase3Uart("RVPhase3: StartOS Svc Load+Call FAILED.\n");
    return FALSE;
  }
  FileWrite("A:/Runtime/SVC.OK", "OK", 2);
  RVPhase3Uart("RVPhase3: StartOS Load Svc.BIN OK (RuntimeSvcProbe=42).\n");
  if (!FileFind("A:/Runtime/Kern.BIN")) {
    RVPhase3Uart("RVPhase3: StartOS needs A:/Runtime/Kern.BIN.\n");
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: StartOS Load Kern.BIN...\n");
  bfh = Load("A:/Runtime/Kern.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: StartOS Kern.BIN Load FAILED.\n");
    return FALSE;
  }
  r = RVPhase3CallExport("KernInit");
  if (r != 42) {
    RVPhase3UartI64("RVPhase3: StartOS Kern Load+Call FAILED r=", r);
    return FALSE;
  }
  FileWrite("A:/Runtime/KERN.OK", "OK", 2);
  RVPhase3Uart("RVPhase3: StartOS Load Kern.BIN OK (KernInit=42).\n");
  // Prefer RedSea/guest Kernel.BIN (Boot.DD) over relying on Mac phase3 ELF alone.
  if (!FileFind("A:/Kernel/Kernel.BIN") || !FileFind("A:/Kernel/KERNEL.OK")) {
    RVPhase3Uart("RVPhase3: StartOS needs guest A:/Kernel/Kernel.BIN.\n");
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: StartOS Load Kernel.BIN...\n");
  bfh = Load("A:/Kernel/Kernel.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: StartOS Kernel.BIN Load FAILED.\n");
    return FALSE;
  }
  r = RVPhase3CallExport("KernelProbe");
  if (r != 42) {
    RVPhase3UartI64("RVPhase3: StartOS Kernel Load+Call FAILED r=", r);
    return FALSE;
  }
  RVPhase3Uart("RVPhase3: StartOS Load Kernel.BIN OK (RedSea Kernel.BIN preferred over Mac phase3.elf scaffold).\n");
  rv_phase3_startos_ok = TRUE;
  RVPhase3Uart("RVPhase3: StartOS subset OK (guest BINs AdamCore+StartOS+Seed+Svc+Kern+Kernel).\n");
  return TRUE;
}

U0 RVPhase3WinRefresh()
{
  U8 *wp;
  I64 sz = 0;
  if (!rv_phase3_startos_ok)
    return;
  if (!rv_winmgr.ready)
    return;
  wp = FileRead("A:/Adam/WALLPAPER.TXT", &sz, NULL);
  if (wp && sz > 0)
    RVWinSetWallpaper(wp);
  if (rv_winmgr.n_wins > 0) {
    RVWinSetTitle(0, "Adam");
    RVWinSetBody(0, "$$ETempleOS/RISC-V Adam\n" "$$FMakeAdam_RV_Core on FB WinMgr\n" "$$AGuest Cmp Runtime BINs\n" "$$BLoad() StartOS+Seed+Svc+Kern+Kernel\n" "$$3StartOS_RV + DocTermNew\n" "$$B0$$7Doc-lite BG sample\n");
  }
  DocTermNew;
  RVDocHomeOpen(NULL);
  RVWinMgrRefresh;
  RVPhase3Uart("RVPhase3: WinMgr DocTerm-lite desktop updated on FB.\n");
}

U0 RVPhase3DocInitStockRung(U8 *prj, U8 *bin, U8 *export, U8 *tag)
{
  // One rung of the stock DocInit_RV Soft Cmp ladder. Each rung prints its tag
  // before Soft Cmp, so a hang leaves the previous rung's OK as the last line
  // and names the culprit without needing a run per rung.
  CBinFile *bfh;
  I64 r, ex_addr, ex_kind;
  RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder ");
  RVPhase3Uart(tag);
  RVPhase3Uart(" Soft Cmp...\n");
  if (!prj) {
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder no PRJ seed.\n");
    return;
  }
  if (!RVPhase3CmpWrite(prj, bin, "RVPhase3: P6 bisect DocInitStock ladder BLOCKED.\n")) {
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder ");
    RVPhase3Uart(tag);
    RVPhase3Uart(" Soft Cmp FAIL.\n");
    return;
  }
  RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder ");
  RVPhase3Uart(tag);
  RVPhase3Uart(" Soft Cmp OK.\n");
  // Load and Call are reported separately on purpose. The ladder used to print "Soft Cmp OK"
  // and then nothing, and that was read as "the Soft CALL hangs" -- but Load, the signature
  // check and the call all sit behind that one silent gap, so nothing distinguished them.
  RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder ");
  RVPhase3Uart(tag);
  RVPhase3Uart(" Load...\n");
  // NOT LDF_SILENT. LoadOneImport (Kernel/KLoad.HC) prints "Unresolved Reference:<name>"
  // only when that flag is clear, and when an import does not resolve it ALSO skips the patch
  // and leaves the call site pointing at nothing -- while Load still returns a valid CBinFile.
  // The A4 rung jumped into one of those and took mcause=2 at a zeroed address. Silencing the
  // loader inside a BISECT ladder hides the one thing the ladder exists to find.
  bfh = Load(bin, LDF_JUST_LOAD);
  if (!bfh) {
    // Was a silent `return`: a failed Load looked exactly like a hang from the outside.
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder ");
    RVPhase3Uart(tag);
    RVPhase3Uart(" Load FAILED (no CBinFile).\n");
    return;
  }
  if (bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder ");
    RVPhase3Uart(tag);
    RVPhase3UartHex64(" Load bad signature=0x", bfh->bin_signature);
    return;
  }
  RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder ");
  RVPhase3Uart(tag);
  RVPhase3Uart(" Load OK; Call...\n");
  // What are we about to jump to? A4 reached a zeroed address while Load reported OK,
  // and nothing in the output said so. Print the resolved target and the image it should
  // be inside, so an out-of-image or stale address names itself.
  ex_addr = RVPhase3ExportAddr(export, &ex_kind);
  RVPhase3UartI64("RVPhase3:   export kind=", ex_kind);
  RVPhase3UartHex64("RVPhase3:   export addr=0x", ex_addr);
  RVPhase3UartHex64("RVPhase3:   module_base=0x", bfh(I64));
  RVPhase3UartI64("RVPhase3:   file_size=", bfh->file_size);
  try {
    r = RVPhase3CallExport(export);
  } catch {
    Fs->catch_except = TRUE;
    r = -2;
  }
  if (r == 1) {
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder ");
    RVPhase3Uart(tag);
    RVPhase3Uart(" Soft Call OK.\n");
  } else {
    RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder ");
    RVPhase3Uart(tag);
    RVPhase3UartI64(" Soft Call soft-fail r=", r);
  }
}

U0 RVPhase3DocInitStockLadder()
{
  // Goal 2 bisect: the stock DocInit_RV Soft #include was unconditionally
  // soft-skipped with a "hang after doldoc Soft plant" note and never retried.
  // Ladder rungs A-D add the stock-only surface the green guest DocInit_RV
  // variant trims (Kernel doldoc plant, tmph assign-in-if, DefineLstLoad NUL
  // literals, big shift-or chains); rung E is the unmodified stock #include.
  // Late wave, so a rung hang cannot cost the StartOS Load needles.
  //
  // Bisect result, CORRECTED 2026-09-22. The earlier note here said A2 (a *store* to the
  // planted doldoc.hash) died and blamed RVExePubInternDolDocIn's glbl plant. That was read off
  // a run whose Compiler.BIN was STALE -- Compiler_RV.PRJ had been failing to build for a day
  // and the smoke repacked the last good blob (see docs/NEXT_STEPS.md 3.5). Against a fresh
  // compiler A1-A4 Soft Cmp all pass and A1-A3 Soft Call pass, so the plant is fine for stores
  // too. The live frontier is A4's Soft CALL (sizeof member decay), which hangs: identical
  // output at PHASE3_TIMEOUT=600 and =1500, so it is a wedge and not a slow compile.
  U8 *prj;
  RVCmpExportOne("MemSet", &MemSet);
  RVCmpExportOne("Bt", &Bt);
  RVCmpExportOne("Bts", &Bts);
  RVCmpExportOne("DefineLoad", &DefineLoad);
  RVCmpExportOne("DefineLstLoad", &DefineLstLoad);
  RVCmpExportOne("HashFind", &HashFind);
  RVCmpExportOne("HashTableNew", &HashTableNew);
  RVCmpExportOne("HashLstAdd", &HashLstAdd);
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitA1.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitA1.BIN", "RVDocInitA1SelfTest", "A1 (doldoc.hash read)");
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitA2.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitA2.BIN", "RVDocInitA2SelfTest", "A2 (doldoc.hash write)");
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitA3.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitA3.BIN", "RVDocInitA3SelfTest", "A3 (dft_de_flags const idx)");
  // A4a before A4: same sizeof check with no import and no call, so a fault in A4 can be
  // attributed to the import call rather than to sizeof on the planted member. A4 is the only
  // rung in the ladder that imports anything.
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitA4a.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitA4a.BIN", "RVDocInitA4aSelfTest", "A4a (sizeof only, no import)");
  // A4b: the same import CALL with a plain global array, no doldoc at all. Splits "the call
  // through an import" from "the planted member", and if it fails the repro leaves phase3.
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitA4b.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitA4b.BIN", "RVDocInitA4bSelfTest", "A4b (import call, plain global array)");
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitA4.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitA4.BIN", "RVDocInitA4SelfTest", "A4 (sizeof member decay)");
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitKernPlant.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitKernPlant.BIN", "RVDocInitRungASelfTest", "A (doldoc plant)");
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitTmph.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitTmph.BIN", "RVDocInitRungBSelfTest", "B (tmph assign-in-if)");
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitDefLst.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitDefLst.BIN", "RVDocInitRungCSelfTest", "C (DefineLstLoad NUL lits)");
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitBigOr.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitBigOr.BIN", "RVDocInitRungDSelfTest", "D (shift-or chains)");
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteDocInitStock.PRJ", NULL, NULL, NULL);
  RVPhase3DocInitStockRung(prj, "A:/Adam/LiteDocInitStock.BIN", "RVDocInitStockSelfTest", "E (stock #include)");
  RVPhase3Uart("RVPhase3: P6 bisect — DocInitStock ladder done.\n");
}

U0 RVPhase3LateMenuSoftCall()
{
  // Late Soft Call wave for the Menu CmpCtrl chain. Runs after StartOS Load +
  // "done" so a Soft Call hang here cannot cost the proven needles above.
  // Soft Cmp already wrote the BINs in the P6 Menu section.
  CBinFile *bfh;
  U8 *prj, *src;
  I64 r;
  // Soft Call LexPlant bisect (late wave): pins which primitive under the
  // MenuLexI64Soft r=2 soft-fail is soft. IdxProbe r=1 glbl-var idx, r=2 local
  // idx; SelfTest r=3 glbl-arr post-inc idx, 7/10 glbl store lost across a Soft
  // CALL, 11/13 wrong branch, 12/14 idx. Late so a Soft Cmp hang here cannot
  // cost the StartOS Load needles (the extended ptr-decay form hung guest Cmp).
  RVPhase3Uart("RVPhase3: P6 bisect — LexPlant Soft Cmp...\n");
  src = "I64 g_toks[8];\n" "I64 g_tok_n;\n" "I64 g_tok_i;\n" "I64 g_token;\n" "I64 g_cur_i64;\n" "I64 g_i64_val;\n" "I64 g_lex_ret;\n" "I64 SoftPlantCall()\n" "{\n" "  I64 t;\n" "  if (g_tok_i >= g_tok_n) {\n" "    g_token = 0;\n" "    return 0;\n" "  }\n" "  t = g_toks[g_tok_i++];\n" "  g_token = t;\n" "  if (t == 0x102)\n" "    g_cur_i64 = g_i64_val;\n" "  return t;\n" "}\n" "/* MenuLexI64SoftGlbl shape with the plant inlined (LiteMenuLexI64Soft seed). */\n" "I64 SoftLexShape()\n" "{\n" "  I64 t;\n" "  if (g_token == ',' || g_token == ')')\n" "    return 0;\n" "  if (g_token == 0x102) {\n" "    g_lex_ret = g_cur_i64;\n" "    if (g_tok_i >= g_tok_n)\n" "      g_token = 0;\n" "    else {\n" "      t = g_toks[g_tok_i++];\n" "      g_token = t;\n" "      if (t == 0x102)\n" "        g_cur_i64 = g_i64_val;\n" "    }\n" "    return g_lex_ret;\n" "  }\n" "  return 0;\n" "}\n" "/* Same shapes with the index hoisted into a local and the bump stored\n" " * explicitly - the Soft-Call-safe plant the product Menu seeds now use. */\n" "I64 SoftPlantCallFixed()\n" "{\n" "  I64 t;\n" "  I64 ti;\n" "  if (g_tok_i >= g_tok_n) {\n" "    g_token = 0;\n" "    return 0;\n" "  }\n" "  ti = g_tok_i;\n" "  t = g_toks[ti];\n" "  g_tok_i = ti + 1;\n" "  g_token = t;\n" "  if (t == 0x102)\n" "    g_cur_i64 = g_i64_val;\n" "  return t;\n" "}\n" "\n" "I64 SoftLexShapeFixed()\n" "{\n" "  I64 t;\n" "  I64 ti;\n" "  if (g_token == ',' || g_token == ')')\n" "    return 0;\n" "  if (g_token == 0x102) {\n" "    g_lex_ret = g_cur_i64;\n" "    if (g_tok_i >= g_tok_n)\n" "      g_token = 0;\n" "    else {\n" "      ti = g_tok_i;\n" "      t = g_toks[ti];\n" "      g_tok_i = ti + 1;\n" "      g_token = t;\n" "      if (t == 0x102)\n" "        g_cur_i64 = g_i64_val;\n" "    }\n" "    return g_lex_ret;\n" "  }\n" "  return 0;\n" "}\n" "/* Index-form bisect. Globals are set by the caller so the callee has to load\n" " * them (SoftLexShape shape) instead of folding a same-function constant. */\n" "I64 HelpGlblIdx()\n" "{\n" "  I64 t;\n" "  t = g_toks[g_tok_i];\n" "  return t;\n" "}\n" "\n" "I64 HelpLocalIdx()\n" "{\n" "  I64 t;\n" "  I64 i;\n" "  i = g_tok_i;\n" "  t = g_toks[i];\n" "  return t;\n" "}\n" "/* Reads g_toks[1] so a dropped index scales to 11 instead of 22 and is caught. */\n" "public I64 RVLexPlantIdxProbe()\n" "{\n" "  I64 t;\n" "  g_toks[0] = 11;\n" "  g_toks[1] = 22;\n" "  g_tok_n = 4;\n" "  g_tok_i = 1;\n" "  t = HelpGlblIdx();\n" "  if (t != 22)\n" "    return 1;\n" "  g_tok_i = 1;\n" "  t = HelpLocalIdx();\n" "  if (t != 22)\n" "    return 2;\n" "  return 8;\n" "}\n" "\n" "public I64 RVLexPlantFixedSelfTest()\n" "{\n" "  I64 t;\n" "  I64 ti;\n" "  g_tok_i = 0;\n" "  g_tok_n = 1;\n" "  g_toks[0] = ';';\n" "  g_token = 0x102;\n" "  t = SoftPlantCallFixed();\n" "  if (t != ';')\n" "    return 6;\n" "  if (g_token != ';')\n" "    return 7;\n" "  if (g_tok_i != 1)\n" "    return 13;\n" "  g_tok_i = 0;\n" "  g_tok_n = 1;\n" "  g_toks[0] = ',';\n" "  g_token = 0x102;\n" "  g_cur_i64 = 8;\n" "  t = SoftLexShapeFixed();\n" "  if (t != 8)\n" "    return 9;\n" "  if (g_token != ',')\n" "    return 10;\n" "  if (g_tok_i != 1)\n" "    return 11;\n" "  ti = g_tok_i;\n" "  g_tok_i = ti + 1;\n" "  if (g_tok_i != 2)\n" "    return 12;\n" "  return 8;\n" "}\n" "\n" "public I64 RVLexPlantToken()\n" "{\n" "  return g_token;\n" "}\n" "\n" "public I64 RVLexPlantTokI()\n" "{\n" "  return g_tok_i;\n" "}\n" "\n" "public I64 RVLexPlantSelfTest()\n" "{\n" "  I64 t;\n" "  g_toks[0] = 41;\n" "  if (g_toks[0] != 41)\n" "    return 1;\n" "  g_tok_i = 0;\n" "  g_tok_n = 1;\n" "  if (g_tok_i >= g_tok_n)\n" "    return 2;\n" "  g_toks[0] = ',';\n" "  t = g_toks[g_tok_i++];\n" "  if (t != ',')\n" "    return 3;\n" "  if (g_tok_i != 1)\n" "    return 4;\n" "  g_token = t;\n" "  if (g_token != ',')\n" "    return 5;\n" "  g_tok_i = 0;\n" "  g_tok_n = 1;\n" "  g_toks[0] = ';';\n" "  g_token = 0x102;\n" "  t = SoftPlantCall();\n" "  if (t != ';')\n" "    return 6;\n" "  if (g_token == 0x102)\n" "    return 7;\n" "  if (!g_token)\n" "    return 13;\n" "  if (g_token != ';')\n" "    return 14;\n" "  g_tok_i = 0;\n" "  g_tok_n = 1;\n" "  g_toks[0] = ',';\n" "  g_token = 0x102;\n" "  g_cur_i64 = 8;\n" "  t = SoftLexShape();\n" "  if (t != 8)\n" "    return 9;\n" "  if (g_token == 0x102)\n" "    return 10;\n" "  if (!g_token)\n" "    return 11;\n" "  if (g_token != ',')\n" "    return 12;\n" "  return 8;\n" "}\n";
  prj = RVPhase3PreferLitePrj("A:/Compiler/LiteLexPlant.PRJ", "A:/Adam/LiteLexPlant.PRJ", src, "RVPhase3: LiteLexPlant RedSea seed (no ELF FileWrite).\n");
  if (!RVPhase3CmpWrite(prj, "A:/Adam/LiteLexPlant.BIN", "RVPhase3: P6 bisect LexPlant BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — LexPlant Soft Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — LexPlant Soft Cmp OK.\n");
  if (FileFind("A:/Adam/LiteLexPlant.BIN")) {
    bfh = Load("A:/Adam/LiteLexPlant.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVLexPlantIdxProbe");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — LexPlant Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — LexPlant idx forms OK (glbl+local var idx).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — LexPlant idx soft-fail r=", r);
      // Soft-Call-safe plant the product Menu seeds now use (hoisted index).
      try {
        r = RVPhase3CallExport("RVLexPlantFixedSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — LexPlant hoisted-idx plant OK (Soft Call safe).\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — LexPlant hoisted-idx soft-fail r=", r);
      try {
        r = RVPhase3CallExport("RVLexPlantSelfTest");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — LexPlant Soft Call OK (glbl arr var idx + plant across Soft Call).\n");
      else {
        RVPhase3UartI64("RVPhase3: P6 bisect — LexPlant soft-fail r=", r);
        try {
          r = RVPhase3CallExport("RVLexPlantToken");
        } catch {
          Fs->catch_except = TRUE;
          r = -2;
        }
        RVPhase3UartHex64("RVPhase3: P6 bisect — LexPlant g_token=0x", r);
        try {
          r = RVPhase3CallExport("RVLexPlantTokI");
        } catch {
          Fs->catch_except = TRUE;
          r = -2;
        }
        RVPhase3UartI64("RVPhase3: P6 bisect — LexPlant g_tok_i=", r);
      }
    }
  }
  RVPhase3Uart("RVPhase3: P6 bisect — late LexPlant wave done.\n");
  RVPhase3DocInitStockLadder;
}

U0 RVPhase3()
{
  // G9: prove RedSea Kernel.BIN seed before Cmp (thin-loader milestone).
  if (!RVPhase3ProbeSeedKernel())
    RVPhase3Uart("RVPhase3: RedSea Kernel.BIN seed probe failed (continuing).\n");
  if (!RVPhase3LoadCompiler()) {
    RVPhase3Uart("RVPhase3: abort (compiler not loaded).\n");
    return;
  }
  if (!RVPhase3LoadBin())
    RVPhase3Uart("RVPhase3: Load() CBinFile step failed (continuing).\n");
  if (!RVPhase3LoadHostBin())
    RVPhase3Uart("RVPhase3: Load() host Compiler.BIN failed (continuing).\n");
  if (!RVPhase3LoadFullCompiler())
    RVPhase3Uart("RVPhase3: Load() full Compiler.BIN failed (continuing).\n");
  if (!RVPhase3MakeOS())
    RVPhase3Uart("RVPhase3: MakeOS (guest Cmp) failed (continuing).\n");
  if (!RVPhase3GuestRuntime())
    RVPhase3Uart("RVPhase3: Guest Runtime seed failed (continuing).\n");
  RVPhase3Uart("RVPhase3: before StartOS...\n");
  if (!RVPhase3StartOS())
    RVPhase3Uart("RVPhase3: StartOS subset failed.\n");
  else {
    RVPhase3Uart("RVPhase3: done (compiler + StartOS).\n");
    RVPhase3WinRefresh;
  }
  RVPhase3LateMenuSoftCall;
}
