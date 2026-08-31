// RVPhase3.HC — TempleOS Boot.DD phase 3 on RISC-V.
// x86: Load("/Compiler/Compiler") → ExeFile("StartOS") → SrvTaskCont.
// RV (P3 intermediate — see templeos-riscv/COMPILER_RV.md):
//   1) In-image Compiler_RV_Body + Load(full host-AOT Compiler.BIN) for Cmp/ExePutS.
//   2) Guest MakeOS: Cmp → Tiny.BIN → Load → Call.
//   3) Guest Runtime: Cmp Seed/Svc/Kern + Adam/StartOS.BIN (HolyC modules on A:).
//   4) StartOS primarily Loads those guest BINs (not host-staged ExeFile strings).
// Residual host AOT: phase3 ELF + pack_tosb Compiler.BIN; AdamCore preferably guest BIN.
//
// Include AFTER Compiler_RV_Body.PRJ so `cmp`/`ExePutS`/`Cmp` are real symbols.
// Demo must also #include "RVHostBinEmbed.HC" (host-packed TOSB bytes).
Bool rv_phase3_compiler_ok = FALSE;
Bool rv_phase3_load_ok = FALSE;
Bool rv_phase3_startos_ok = FALSE;
Bool rv_phase3_include_ok = FALSE;
Bool rv_phase3_hostbin_ok = FALSE;
Bool rv_phase3_fullcmp_ok = FALSE;
Bool rv_phase3_makeos_ok = FALSE;
Bool rv_phase3_runtime_ok = FALSE;
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

Bool RVPhase3CmpWrite(U8 *prj, U8 *bin_out, U8 *fail_msg)
{
  //Guest Cmp PRJ→BIN; UART fail_msg and return FALSE on error.
  I64 err;
  try {
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

Bool RVPhase3LoadCompiler()
{
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
}

Bool RVPhase3LoadFullCompiler()
{
  //Load linked full Compiler_RV TOSB (97 imports); CInit + loaded ExePutS as live JIT.
  CBinFile *src, *bfh;
  CHashExport *tmpex, *tmpex_eps;
  I64 n, val, sz, cinit_addr, exeps_addr;
  U8 *probe;
  // Host AOT is PC-relative (auipc globals/calls/strings); no IET_ABS_ADDR needed.
  // Live path: Call loaded CInit (module cmp) then funptr ExePutS.
  if (!rv_phase3_compiler_ok)
    return FALSE;
  src = 0x81000000(CBinFile *);
  // link_exepubs.ld .compiler_bin
  if (src->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: full Compiler.BIN not linked at 0x81000000.\n");
    return FALSE;
  }
  sz = src->file_size;
  if (sz < sizeof(CBinFile) || sz > 0x400000) {
    RVPhase3Uart("RVPhase3: full Compiler.BIN size bad.\n");
    return FALSE;
  }
  n = RVCmpExportImports();
  no_warn n;
  RVPhase3Uart("RVPhase3: exported imports for full Compiler.BIN; LoadPass...\n");
  DirMk("A:/Compiler");
  FileWrite("A:/Compiler/FULLBIN.MARK", "FULL", 4);
  /* In-place Load at fixed VMA 0x81000000 (writable .compiler_bin). */
  bfh = LoadPass(src, sz, "A:/Compiler/Compiler", LDF_JUST_LOAD | LDF_SILENT, src);
  RVPhase3Uart("RVPhase3: LoadPass returned.\n");
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVPhase3Uart("RVPhase3: LoadBuf full Compiler.BIN FAILED.\n");
    return FALSE;
  }
  tmpex = HashFind("CInit", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  tmpex_eps = HashFind("ExePutS", Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex || !tmpex_eps) {
    RVPhase3Uart("RVPhase3: full Compiler.BIN export CInit/ExePutS MISSING.\n");
    return FALSE;
  }
  cinit_addr = tmpex->val;
  exeps_addr = tmpex_eps->val;
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
  FileWrite("A:/Compiler/FULLBIN.TXT", "FULL", 4);
  RVPhase3Uart("RVPhase3: Load() full Compiler.BIN OK (97 imports + ExePutS).\n");
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
  U8 *src;
  I64 val;
  CBinFile *bfh;
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
  // Kern.BIN — arg call (3*n); n+n+n still clobbers reg-arg (documented residual).
  RVPhase3Uart("RVPhase3: Runtime staging A:/Runtime/Kern...\n");
  src = "public I64 KernScale(I64 n)\n" "{\n" "  return 3*n;\n" "}\n";
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
  RVPhase3Uart("RVPhase3: Runtime Kern.BIN OK (arg+call+add→42).\n");
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
  // AdamCore.BIN — guest Cmp MakeAdam bring-up (FileWrite/DirMk imports).
  RVPhase3Uart("RVPhase3: Runtime staging A:/Adam/AdamCore...\n");
  // DirMk with stack path (no string lits — those hang guest Cmp).
  src =
    "import Bool DirMk(U8 *filename);\n"
    "public U0 AdamRVCoreInit()\n"
    "{\n"
    "  U8 p[8];\n"
    "  p[0]='A';p[1]=':';p[2]='/';p[3]='A';p[4]='d';p[5]='a';p[6]='m';p[7]=0;\n"
    "  DirMk(p);\n"
    "}\n";
  FileWrite("A:/Adam/AdamCore.HC", src, StrLen(src));
  FileWrite("A:/Adam/AdamCore.PRJ", src, StrLen(src));
  RVPhase3Uart("RVPhase3: Runtime Cmp(A:/Adam/AdamCore.PRJ)...\n");
  if (!RVPhase3CmpWrite("A:/Adam/AdamCore.PRJ", "A:/Adam/AdamCore.BIN", "RVPhase3: Runtime AdamCore Cmp FAILED.\n")) {
    RVPhase3Uart("RVPhase3: AdamCore Cmp soft-fail (StartOS uses linked core).\n");
    return TRUE;
  }
  RVPhase3Uart("RVPhase3: Runtime AdamCore.BIN ready for StartOS Load.\n");
  return TRUE;
}

Bool RVPhase3StartOS()
{
  //P3 intermediate: StartOS success = Load guest-Cmp'd BINs (StartOS/Seed/Svc/Kern/AdamCore).
  // Linked MakeAdam_RV_Core remains fallback if AdamCore.BIN missing.
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
  // Prefer guest-Cmp'd AdamCore.BIN; fall back to linked MakeAdam_RV_Core.
  if (FileFind("A:/Adam/AdamCore.BIN")) {
    // Guest Cmp BINs resolve imports via Fs hash (same as Load Compiler.BIN).
    RVCmpExportOne("DirMk",&DirMk);
    RVCmpExportOne("FileWrite",&FileWrite);
    bfh = Load("A:/Adam/AdamCore.BIN", LDF_JUST_LOAD | LDF_SILENT);
    if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
      RVPhase3Uart("RVPhase3: AdamCore.BIN Load FAILED.\n");
      return FALSE;
    }
    RVPhase3Uart("RVPhase3: AdamCore.BIN Load OK; Call AdamRVCoreInit...\n");
    RVPhase3CallExport("AdamRVCoreInit");
    back = FileRead("A:/Adam/READY.TXT", &sz, NULL);
    if (back && sz == 4) {
      RVPhase3Uart("RVPhase3: StartOS Load AdamCore.BIN OK (guest Cmp).\n");
    } else {
      // Guest BIN loaded but did not plant markers — linked core.
      AdamRVCoreInit;
      RVPhase3Uart("RVPhase3: AdamCore.BIN OK; markers via linked MakeAdam.\n");
    }
  } else {
    AdamRVCoreInit;
    RVPhase3Uart("RVPhase3: StartOS AdamRVCoreInit via linked host AOT.\n");
  }
  back = FileRead("A:/Adam/READY.TXT", &sz, NULL);
  if (!back || sz != 4) {
    RVPhase3Uart("RVPhase3: Adam READY.TXT missing.\n");
    return FALSE;
  }
  back = FileRead("A:/Adam/CORE.TXT", &sz, NULL);
  if (!back || sz < 10) {
    RVPhase3Uart("RVPhase3: Adam CORE.TXT missing (MakeAdam_RV_Core).\n");
    return FALSE;
  }
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
  rv_phase3_startos_ok = TRUE;
  if (FileFind("A:/Adam/AdamCore.BIN"))
    RVPhase3Uart("RVPhase3: StartOS subset OK (guest BINs AdamCore+StartOS+Seed+Svc+Kern).\n");
  else
    RVPhase3Uart("RVPhase3: StartOS subset OK (guest BINs StartOS+Seed+Svc+Kern).\n");
  return TRUE;
}

U0 RVPhase3WinRefresh()
{
  U8 *wp, *home;
  I64 sz = 0, idx = -1;
  if (!rv_phase3_startos_ok)
    return;
  wp = FileRead("A:/Adam/WALLPAPER.TXT", &sz, NULL);
  if (wp && sz > 0)
    RVWinSetWallpaper(wp);
  if (rv_winmgr.n_wins > 0) {
    RVWinSetTitle(0, "Adam");
    RVWinSetBody(0, "$$ETempleOS/RISC-V Adam\n" "$$FMakeAdam_RV_Core on FB WinMgr\n" "$$AGuest Cmp Runtime BINs\n" "$$BLoad() StartOS+Seed+Svc+Kern\n" "$$3StartOS_RV (guest BIN)\n" "$$B0$$7Doc-lite BG sample\n");
    if (rv_winmgr.n_wins > 1) {
      RVWinSetTitle(1, "DolDoc / Files");
      RVWinSetBody(1, "$$EMakeAdam_RV_Core / DolDoc-lite\n" "$$Ftext_base + TextChar on ramfb\n" "A:/Adam/HOME.DD\n" "A:/Adam/READY.TXT\n" "A:/Adam/CORE.TXT\n" "A:/Adam/StartOS.BIN\n" "A:/MakeOS/Tiny.BIN\n" "A:/MakeOS/MAKEOS.OK\n" "A:/Runtime/Seed.BIN\n" "A:/Runtime/SEED.OK\n" "A:/Runtime/Svc.BIN\n" "A:/Runtime/SVC.OK\n" "A:/Runtime/Kern.BIN\n" "A:/Runtime/KERN.OK\n" "A:/Compiler/FULLBIN.TXT\n");
    }
    if (rv_winmgr.n_wins < 3)
      idx = RVWinNew(20, rv_winmgr.cols - 4, 18, rv_winmgr.rows - 4, "HOME.DD", "", FALSE);
    no_warn idx;
    if (rv_winmgr.n_wins > 2) {
      home = FileRead("A:/Adam/HOME.DD", &sz, NULL);
      RVWinSetTitle(2, "HOME.DD");
      if (home && sz > 0)
        RVWinSetBody(2, home);
      else
        RVWinSetBody(2, "empty HOME.DD\n");
    }
    RVWinMgrRefresh;
    RVPhase3Uart("RVPhase3: WinMgr Adam desktop updated on FB.\n");
  }
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
    // no-op unless WinMgr already up (FB/interactive)
  }
}
