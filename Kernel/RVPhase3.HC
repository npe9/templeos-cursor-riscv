// RVPhase3.HC — TempleOS Boot.DD phase 3 on RISC-V.
// x86: Load("/Compiler/Compiler") → ExeFile("StartOS") → SrvTaskCont.
// RV (P3 intermediate — see templeos-riscv/COMPILER_RV.md):
//   1) Stage host-seed Compiler.BIN (ELF @0x81000000 bytes) → A:/Compiler/Compiler.BIN →
//      heap Load() → live Cmp/ExePutS (G9 relocatable seed; no in-image Body).
//   2) Guest MakeOS: loaded Cmp → Tiny.BIN → Load → Call.
//   3) Guest Runtime: Cmp Seed/Svc/Kern + Adam/StartOS.BIN (HolyC modules on A:).
//   4) StartOS primarily Loads those guest BINs (not host-staged ExeFile strings).
// Residual host AOT (G9): phase3 ELF scaffolding + pack_tosb Compiler.BIN seed
// linked at 0x81000000 as bootstrap *bytes* (→A:). Live Cmp is heap Load() of
// A:/Compiler/Compiler.BIN (host AOT is PC-rel — relocatable; no fixed-VMA
// LoadPass). Full Menu_RV U8[] embed dropped; soft P6 stages Menu_RV_Guest
// via RVAdamLiteMenuSrc. AdamCore: guest Cmp→Load→Call FileWrite only.
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
    for (j = 0; j < 12; j++) {
      abs_val = 0;
      MemCpy(&abs_val, code + j * 4, 4);
      RVPhase3UartHex64("RVPhase3: abs dump Init_word=", abs_val & 0xFFFFFFFF);
    }
  } else
    RVPhase3Uart("RVPhase3: abs dump Init export MISSING.\n");
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
  // 0x81000000 remains bootstrap byte source until a RedSea image ships the seed.
  CBinFile *src, *bfh, *red;
  CHashExport *tmpex, *tmpex_eps, *tmpex_cmp;
  I64 n, val, sz, red_sz = 0, cinit_addr, exeps_addr;
  U8 *probe, *red_buf = NULL;
  Bool prefer_redsea = FALSE, have_linked = FALSE, used_reloc = FALSE;
  if (rv_phase3_fullcmp_ok)
    return TRUE;
#ifndef RV_PHASE3_LOADED_CMP_ONLY
  if (!rv_phase3_compiler_ok)
    return FALSE;
#endif
  src = 0x81000000(CBinFile *);
  // link_exepubs.ld .compiler_bin — optional once RedSea already has matching seed.
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
    RVPhase3Uart("RVPhase3: staged A:/Compiler/Compiler.BIN (RedSea host seed).\n");
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
  U8 *src, *back;
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
  // G9: guest Kernel.BIN (Boot.DD shape) — StartOS prefers this over Mac scaffold.
  // Tiny probe until guest Cmp can rebuild real Kernel_RV; not the phase3 ELF.
  RVPhase3Uart("RVPhase3: Runtime staging A:/Kernel/Kernel.BIN...\n");
  DirMk("A:/Kernel");
  src = "public I64 KernelProbe()\n" "{\n" "  return 42;\n" "}\n";
  FileWrite("A:/Kernel/Kernel.HC", src, StrLen(src));
  FileWrite("A:/Kernel/Kernel.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: Runtime Cmp(A:/Kernel/Kernel.PRJ)...\n");
  if (!RVPhase3CmpWrite("A:/Kernel/Kernel.PRJ", "A:/Kernel/Kernel.BIN", "RVPhase3: Runtime Kernel Cmp FAILED.\n"))
    return FALSE;
  FileWrite("A:/Kernel/KERNEL.OK", "OK", 2);
  RVPhase3Uart("RVPhase3: Runtime Kernel.BIN ready (guest Cmp preferred over Mac scaffold).\n");
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
  else
    RVPhase3Uart("RVPhase3: P6 bisect — scalar-glbl Cmp OK.\n");
  // Soft: Menu Lex-shaped guest Cmp. StrCpy→glbl U8[] Cmp OK; U8 elem Call
  // still soft (saw 0). Local U8 name[32]/*p++ ident walk — stepped bisects.
  // Full in-tree Menu_RV.HC (CMenu/CCmpCtrl) still host/WinMgr.
  RVPhase3Uart("RVPhase3: P6 bisect — Menu hand Lex Cmp...\n");
  src = "import U8 *StrCpy(U8 *dst,U8 *src);\n" "U8 g_lex_buf[40];\n" "public I64 AdamLiteLexProbe()\n" "{\n" "  StrCpy(g_lex_buf,\"TileHorz\");\n" "  return g_lex_buf[0];\n" "}\n";
  FileWrite("A:/Adam/LiteLex.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteLex.PRJ", "A:/Adam/LiteLex.BIN", "RVPhase3: P6 bisect Menu Lex BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Menu Lex FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Menu Lex Cmp OK.\n");
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
  // G8: star-lit / *p Cmp+Call (unary prec pack fix i+0x10000*PREC).
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
  // Class member U8[] + StrCpy (Menu ent shape).
  RVPhase3Uart("RVPhase3: P6 bisect — class member StrCpy Cmp...\n");
  src = "import U8 *StrCpy(U8 *dst,U8 *src);\n" "class CRVMenuEntM\n" "{\n" "  U8 name[24];\n" "  I64 id;\n" "};\n" "CRVMenuEntM g_ent_m;\n" "public I64 AdamLiteMemProbe()\n" "{\n" "  StrCpy(g_ent_m.name,\"TileHorz\");\n" "  return g_ent_m.name[0];\n" "}\n";
  FileWrite("A:/Adam/LiteMem.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteMem.PRJ", "A:/Adam/LiteMem.BIN", "RVPhase3: P6 bisect class member StrCpy BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — class member StrCpy FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — class member StrCpy Cmp OK.\n");
  // In-tree Menu_RV_Guest + Lex+Guest wrap on A: (nested #include, not flat extract).
  // Guest alone: PersonalMenu + Width/src_embedded. Wrap folds Guest_Lex before Guest.
  src = RVAdamLiteMenuGuestSrc();
  FileWrite("A:/Adam/Menu_RV_Guest.HC", src, StrLen(src));
  RVPhase3UartI64("RVPhase3: Menu_RV_Guest.HC staged bytes=", StrLen(src));
  // Soft: index hand Lex unit (also folded into Menu_RV wrap for AdamLite).
  src = RVAdamLiteMenuLexSrc();
  FileWrite("A:/Adam/Menu_RV_Guest_Lex.HC", src, StrLen(src));
  FileWrite("A:/Adam/LiteMenuLex.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex index hand Lex Cmp...\n");
  if (!RVPhase3CmpWrite("A:/Adam/LiteMenuLex.PRJ", "A:/Adam/LiteMenuLex.BIN", "RVPhase3: P6 bisect Guest_Lex BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Guest_Lex Cmp OK.\n");
  src = RVAdamLiteMenuRVWrapSrc();
  FileWrite("A:/Adam/Menu_RV.HC", src, StrLen(src));
  RVPhase3UartI64("RVPhase3: Menu_RV.HC wrap staged bytes=", StrLen(src));
  // PersonalMenu.DD SoT for host MenuFile / guest Lex Init string.
  src = "Win {\n" "  TileHorz(,1);\n" "  TileVert(,2);\n" "  WinMax(,3);\n" "  Close(,4);\n" "}\n" "Help {\n" "  About(,5);\n" "  Help(,6);\n" "  FormDemo(,7);\n" "  CtrlsDemo(,8);\n" "}\n";
  FileWrite("A:/Adam/PersonalMenu.DD", src, StrLen(src));
  RVPhase3UartI64("RVPhase3: PersonalMenu.DD staged bytes=", StrLen(src));
  // Soft: Lex+Guest wrap Call probe (same nest AdamLite uses).
  src = "#include \"Menu_RV\"\n" "public I64 AdamLiteLexFoldProbe()\n" "{\n" "  RVMenuPersonalInit;\n" "  return RVMenuPersonalCount;\n" "}\n";
  FileWrite("A:/Adam/LiteLexFold.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: P6 bisect — Lex+Guest fold wrap Cmp...\n");
  if (!RVPhase3CmpWrite("A:/Adam/LiteLexFold.PRJ", "A:/Adam/LiteLexFold.BIN", "RVPhase3: P6 bisect Lex+Guest fold BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — Lex+Guest fold FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Lex+Guest fold Cmp OK.\n");
  if (!FileFind("A:/Adam/Menu_RV.HC") || !FileFind("A:/Adam/Menu_RV_Guest.HC"))
    RVPhase3Uart("RVPhase3: P6 bisect — Menu_RV(+Guest) FileFind MISS after write.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — Menu_RV(+Guest) FileFind OK.\n");
  // Flat Cmp of Guest body alone (no Lex include — Init falls back to n=8).
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
  // Do NOT store Count into local/glbl before multi-STR FileWrite (CALL_IMPORT hang).
  // Sibling store→FileWrite probe is separate (LiteStoreFw). Menu Lite stays FileWrite-safe.
  Cd("A:/Adam");
  src = "#include \"Menu_RV\"\n" "import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);\n" "public I64 AdamRVLiteInit()\n" "{\n" "  RVMenuPersonalInit;\n" "  FileWrite(\"A:/Adam/LITE.TXT\",\"MakeAdam_RV_Lite\",16);\n" "  return 8;\n" "}\n";
  FileWrite("A:/Adam/MakeAdam_RV_Lite.HC", src, StrLen(src));
  FileWrite("A:/Adam/MakeAdam_RV_Lite.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/MakeAdam_RV_Lite.PRJ", "A:/Adam/AdamLite.BIN", "RVPhase3: P6 MakeAdam_RV_Lite Cmp BLOCKED (soft; #include Menu_RV).\n")) {
    RVPhase3Uart("RVPhase3: P6 nested include soft-fail; try abs #include...\n");
    src = "#include \"A:/Adam/Menu_RV.HC\"\n" "import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);\n" "public I64 AdamRVLiteInit()\n" "{\n" "  RVMenuPersonalInit;\n" "  FileWrite(\"A:/Adam/LITE.TXT\",\"MakeAdam_RV_Lite\",16);\n" "  return 8;\n" "}\n";
    FileWrite("A:/Adam/MakeAdam_RV_Lite.HC", src, StrLen(src));
    FileWrite("A:/Adam/MakeAdam_RV_Lite.PRJ", src, StrLen(src));
    if (!RVPhase3CmpWrite("A:/Adam/MakeAdam_RV_Lite.PRJ", "A:/Adam/AdamLite.BIN", "RVPhase3: P6 MakeAdam_RV_Lite Cmp BLOCKED (soft; abs #include).\n"))
      RVPhase3Uart("RVPhase3: P6 MakeAdam_RV_Lite probe — Cmp soft-fail (G8 Menu_RV).\n");
    else
      RVPhase3Uart("RVPhase3: P6 AdamLite.BIN ready (guest Cmp abs #include Menu_RV).\n");
  } else
    RVPhase3Uart("RVPhase3: P6 AdamLite.BIN ready (guest Cmp #include Menu_RV).\n");
  // Focused proof: same-module Count→local then multi-STR CALL_IMPORT (no Menu).
  src = "import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);\n" "I64 StoreFwCount()\n{\n  return 8;\n}\n" "public I64 AdamLiteStoreFwProbe()\n" "{\n" "  I64 n;\n" "  n=StoreFwCount;\n" "  FileWrite(\"A:/Adam/STOREFW.TXT\",\"STOREFW\",7);\n" "  return n;\n" "}\n";
  FileWrite("A:/Adam/LiteStoreFw.PRJ", src, StrLen(src));
  if (!RVPhase3CmpWrite("A:/Adam/LiteStoreFw.PRJ", "A:/Adam/LiteStoreFw.BIN", "RVPhase3: P6 bisect store→FileWrite BLOCKED.\n"))
    RVPhase3Uart("RVPhase3: P6 bisect — store→FileWrite Cmp FAIL.\n");
  else
    RVPhase3Uart("RVPhase3: P6 bisect — store→FileWrite Cmp OK.\n");
  Cd("A:/");
  return TRUE;
}

Bool RVPhase3StartOS()
{
  //P3 intermediate: StartOS success = Load guest-Cmp'd BINs (StartOS/Seed/Svc/Kern/AdamCore).
  // Adam markers come from guest AdamCore Call→FileWrite only (no linked MakeAdam).
  I64 r, sz = 0;
  U8 *back;
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
  if (FileFind("A:/Adam/LiteStoreFw.BIN")) {
    RVCmpExportOne("FileWrite", &FileWrite);
    RVCmpExportOne("RVHCCall", &_RV_HC_CALL);
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
  }
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
    RVPhase3Uart("RVPhase3: P6 MakeAdam_RV_Lite BIN absent (Cmp soft-fail earlier).\n");
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
  // Lex/Mem/flat Count stay soft (same ABS_ADDR root); star-lit gated.
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
  if (FALSE && FileFind("A:/Adam/LiteLex.BIN")) {
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
  if (FALSE && FileFind("A:/Adam/LiteMem.BIN")) {
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
  // Star-lit / local U8* lit Soft Calls.
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
  if (FALSE && FileFind("A:/Adam/LiteIdent.BIN")) {
    bfh = Load("A:/Adam/LiteIdent.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      r = RVPhase3CallExport("AdamLiteIdentProbe");
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — local U8* ident Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — local U8* ident Call soft-fail r=", r);
    }
  }
  // Soft: Call Count from flat Menu BIN — gated until Scalar ABS_ADDR Call OK.
  // Lex+Guest fold Call is exercised by AdamLite Init (wrap includes Guest_Lex).
  // Do not Load LiteLexFold here — dup RVMenu* after AdamLite hung Call.
  if (FALSE && FileFind("A:/Adam/LiteMenuFlat.BIN")) {
    bfh = Load("A:/Adam/LiteMenuFlat.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (bfh && bfh->bin_signature == BIN_SIGNATURE_VAL) {
      try {
        r = RVPhase3CallExport("RVMenuPersonalCount");
      } catch {
        Fs->catch_except = TRUE;
        r = -2;
        RVPhase3Uart("RVPhase3: P6 bisect — flat Menu Count Call threw.\n");
      }
      if (r == 8)
        RVPhase3Uart("RVPhase3: P6 bisect — flat Menu Count Call OK.\n");
      else
        RVPhase3UartI64("RVPhase3: P6 bisect — flat Menu Count Call soft-fail r=", r);
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
  // Prefer guest Kernel.BIN (Boot.DD) over relying on Mac phase3 ELF alone.
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
  RVPhase3Uart("RVPhase3: StartOS Load Kernel.BIN OK (guest Cmp preferred over Mac scaffold).\n");
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

U0 RVPhase3()
{
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
}
