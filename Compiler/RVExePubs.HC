// RVExePubs.HC — register AOT Kernel funs into Fs hash for guest ExePutS JIT.
// In-image Kernel+Compiler_RV has Print/Regs/... as code, but CInit only fills
// asm_hash types. Without HTT_FUN entries, ExePutS("Print...") is Undefined
// identifier → LexExcept (and historically PutChars→null put_key → mepc=0).
//
// Win split-AOT: this file compiles in the Compiler unit (no Kernel). Declare
// Kernel entry points as extern so --link resolves them from the Kernel blob.
extern U0 Print(U8 *fmt,...);
extern U0 PutChars(U64 ch);
extern U0 Regs();
extern I64 Reg(U8 *name);
extern U0 RVWinSoftDir();
extern U0 RVWinSoftLs();
extern U0 RVWinSoftPwd();
extern I64 RVWinSoftCd(U8 *dirname);
extern U0 RVWinSoftHelp();
extern U0 RVWinSoftMan(U8 *name);
extern U0 RVWinSoftCat(U8 *name);
extern U0 RVWinSoftFind(U8 *needle);
extern U0 RVWinSoftEd(U8 *name);
extern U0 RVWinSoftTasks();
extern U0 AsmList();
extern U0 AsmDoc(U8 *mn);
extern U0 MemMap();
extern U0 Mstatus();
extern U0 Mcause();
extern U0 Csr(U8 *name);
extern U0 Uptime();
// Soft tip Soft #include stock DocInit_RV: Kernel doldoc abs addr (Compiler unit).
//
// ONLY when the kernel is absent. Kernel/RVDoc.HC defines the real `doldoc`; declaring it
// extern on top of that definition turns the global into an unresolved import for the WHOLE
// unit, so every reference — including DocInit's own, compiled earlier — materializes as
// address 0 (`addi a0,zero,0; ld a0,0(a0)`) and takes a load fault the first time any document
// is created. That is what kept DolDoc dead in the REPL image. RV_DOC_ED_KEY_MAX comes from
// Kernel/RVDoc.HC, so its absence means this is a standalone Compiler_RV build.
#ifndef RV_DOC_ED_KEY_MAX
extern U8 doldoc;
#endif
U0 RVExePubMemberLink(CHashFun *tmpf, CMemberLst *tmpm)
{
  CMemberLst *last;
  if (!tmpf || !tmpm)
    return;
  last = tmpf->last_in_member_lst;
  if (!tmpf->member_lst_and_root) {
    tmpf->member_lst_and_root = tmpm;
    tmpf->last_in_member_lst = tmpm;
    return;
  }
  last->next = tmpm;
  tmpf->last_in_member_lst = tmpm;
}

CHashFun *RVExePubFunNew(U8 *name, I64 addr, CHashClass *ret, I64 arg_cnt)
{
  CHashFun *tmpf;
  if (!name || !addr || !Fs || !Fs->hash_table)
    return NULL;
  if (HashFind(name, Fs->hash_table, HTT_FUN))
    return NULL;
  tmpf = PrsFunNew();
  tmpf->str = StrNew(name);
  tmpf->exe_addr = addr;
  tmpf->return_class = ret;
  tmpf->arg_cnt = arg_cnt;
  tmpf->member_cnt = arg_cnt;
  LBtr(&tmpf->flags, Cf_EXTERN);
  tmpf->type |= HTF_PUBLIC;
  HashAdd(tmpf, Fs->hash_table);
  return tmpf;
}

U0 RVExePubAddArg(CHashFun *tmpf, U8 *aname, CHashClass *cls, I64 flags = 0, I64 dft_val = 0)
{
  // flags may carry MLF_DFT_AVAILABLE: PrsExp then fills a missing arg with dft_val
  // (stock default-arg mechanism), e.g. FileMgr(FM_PICK_FILE) → mem_task=NULL.
  CMemberLst *tmpm;
  if (!tmpf || !aname || !cls)
    return;
  tmpm = MemberLstNew(REG_ALLOC);
  tmpm->str = StrNew(aname);
  tmpm->member_class = cls;
  tmpm->flags = flags;
  tmpm->dft_val = dft_val;
  tmpm->size = 8;
  RVExePubMemberLink(tmpf, tmpm);
}
/* Stock PopUp("…FileMgr(1,Fs->parent_task)") and Soft DocInit
 * `HashFind(Fs->hash_table,…)` need `_intern IC_FS CTask *Fs()`.
 * Soft AOT chains glbl→asm_hash only (not Fs), so plant into the given
 * table — WireAsmHash plants asm_hash; WireAddrs plants Fs->hash_table. */
CHashClass *RVExePubCTaskLiteIn(CHashTable *table)
{
  CHashClass *tmpc, *i64t;
  CMemberLst *tmpm_pt, *tmpm_ht;
  if (!table)
    return NULL;
  tmpc = HashFind("CTask", table, HTT_CLASS);
  if (tmpc) {
    // Soft DocInit needs hash_table; ExePutS needs parent_task.
    // Require hash_table — parent_task-only lite early-return was Soft AOT
    // Invalid lval / Invalid member on Fs->hash_table (tip-order plant wipe).
    if (MemberFind("hash_table", tmpc))
      return tmpc;
    tmpm_pt = MemberFind("parent_task", tmpc);
    if (tmpm_pt && cmp.internal_types) {
      // Incomplete lite (parent_task only): graft hash_table as BST right child.
      i64t = cmp.internal_types[RT_I64];
      tmpm_ht = MemberLstNew(REG_NONE);
      tmpm_ht->str = StrNew("hash_table");
      tmpm_ht->offset = offset(CTask.hash_table);
      tmpm_ht->size = sizeof(CHashTable *);
      tmpm_ht->member_class = i64t;
      tmpm_ht->left = NULL;
      tmpm_ht->right = NULL;
      tmpm_ht->next = NULL;
      tmpm_pt->right = tmpm_ht;
      if (!tmpm_pt->next)
        tmpm_pt->next = tmpm_ht;
      tmpc->last_in_member_lst = tmpm_ht;
      tmpc->member_cnt++;
      return tmpc;
    }
  }
  if (!cmp.internal_types)
    return NULL;
  i64t = cmp.internal_types[RT_I64];
  tmpc = PrsClassNew;
  tmpc->str = StrNew("CTask");
  tmpc->size = sizeof(CTask);
  tmpc->raw_type = RT_I64;
  // parent_task: CTask* (one star on the same slab) for PopUp/FileMgr.
  tmpm_pt = MemberLstNew(REG_NONE);
  tmpm_pt->str = StrNew("parent_task");
  tmpm_pt->offset = offset(CTask.parent_task);
  tmpm_pt->size = sizeof(CTask *);
  tmpm_pt->member_class = tmpc + 1;
  tmpm_pt->left = NULL;
  tmpm_pt->right = NULL;
  tmpm_pt->next = NULL;
  // hash_table: I64-sized ptr at stock offset (Soft HashFind table arg).
  tmpm_ht = MemberLstNew(REG_NONE);
  tmpm_ht->str = StrNew("hash_table");
  tmpm_ht->offset = offset(CTask.hash_table);
  tmpm_ht->size = sizeof(CHashTable *);
  tmpm_ht->member_class = i64t;
  tmpm_ht->left = NULL;
  tmpm_ht->right = NULL;
  tmpm_ht->next = NULL;
  // MemberFind BST: StrCmp(node,needle)>0 → right. Looking up hash_table
  // from parent_task root goes right (parent_task > hash_table).
  tmpm_pt->right = tmpm_ht;
  tmpm_pt->next = tmpm_ht;
  tmpc->member_lst_and_root = tmpm_pt;
  tmpc->last_in_member_lst = tmpm_ht;
  tmpc->member_cnt = 2;
  HashAdd(tmpc, table);
  return tmpc;
}

CHashClass *RVExePubCTaskLite()
{
  if (!Fs || !Fs->hash_table)
    return NULL;
  return RVExePubCTaskLiteIn(Fs->hash_table);
}
/* A planted array member needs `dim.next`, not just `dim.total_cnt`:
 * PrsUnaryModifier keys CCF_ARRAY off `tmpm->dim.next` and takes the subscript
 * stride from `dim.next->total_cnt * elem_size`. With `dim.next` NULL the guest
 * Cmp saw a plain scalar and `doldoc.dft_de_flags[DOCT_TEXT] = ...` died on
 * "Not array or ptr". Shape follows PrsVarArgs' argv plant: head total_cnt is
 * the element count, the single dim node carries cnt + inner total_cnt 1. */
U0 RVExePubMemberDim(CMemberLst *m, I64 cnt)
{
  CArrayDim *tmpad;
  if (!m || cnt < 1)
    return;
  tmpad = CAlloc(sizeof(CArrayDim));
  tmpad->next = NULL;
  tmpad->cnt = cnt;
  tmpad->total_cnt = 1;
  m->dim.cnt = cnt;
  m->dim.total_cnt = cnt;
  m->dim.next = tmpad;
}
/* MemberAdd without a CCmpCtrl. Hand-linking only `next`/`right` left every
 * member past the second unreachable from MemberFind's BST ("Invalid member at
 * dft_type_flags"), so keep MemberAdd's exact insert: StrCmp(node,new)<=0 goes
 * left, else right, plus the flat next lst that Prs/sizeof walk. */
U0 RVExePubMemberPlant(CHashClass *tmpc, CMemberLst *m)
{
  CMemberLst **slot, *node;
  if (!tmpc || !m)
    return;
  m->left = NULL;
  m->right = NULL;
  m->next = NULL;
  slot = &tmpc->member_lst_and_root;
  while (node = *slot) {
    if (StrCmp(node->str, m->str) <= 0)
      slot = &node->left;
    else
      slot = &node->right;
  }
  *slot = m;
  if (tmpc->last_in_member_lst)
    tmpc->last_in_member_lst->next = m;
  tmpc->last_in_member_lst = m;
  tmpc->member_cnt++;
}
/* Soft tip: plant Kernel doldoc into Soft asm_hash so Soft #include of unmodified
 * stock DocInit_RV.HC Soft Cmps bare `doldoc` without Soft-local shadow. Layout
 * matches Kernel/RVDoc.HC CDolDocGlbls (DOCT_TYPES_NUM=43). */
#define RV_SOFT_DOCT_TYPES_NUM 43
CHashClass *RVExePubCDolDocGlblsLiteIn(CHashTable *table)
{
  CHashClass *tmpc, *i64t, *i32t;
  CMemberLst *m;
  I64 off;
  if (!table || !cmp.internal_types)
    return NULL;
  tmpc = HashFind("CDolDocGlbls", table, HTT_CLASS);
  if (tmpc && MemberFind("dft_de_flags", tmpc) && MemberFind("hash", tmpc))
    return tmpc;
  i64t = cmp.internal_types[RT_I64];
  i32t = cmp.internal_types[RT_I32];
  if (!tmpc) {
    tmpc = PrsClassNew;
    tmpc->str = StrNew("CDolDocGlbls");
    tmpc->raw_type = RT_I64;
    HashAdd(tmpc, table);
  }
  off = 0;
  tmpc->member_lst_and_root = NULL;
  tmpc->last_in_member_lst = NULL;
  tmpc->member_cnt = 0;
  // hash
  m = MemberLstNew(REG_NONE);
  m->str = StrNew("hash");
  m->offset = off;
  m->size = 8;
  m->member_class = i64t;
  RVExePubMemberPlant(tmpc, m);
  off += 8;
  // dft_de_flags[43]
  m = MemberLstNew(REG_NONE);
  m->str = StrNew("dft_de_flags");
  m->offset = off;
  m->size = 8 * RV_SOFT_DOCT_TYPES_NUM;
  m->member_class = i64t;
  RVExePubMemberDim(m, RV_SOFT_DOCT_TYPES_NUM);
  RVExePubMemberPlant(tmpc, m);
  off += 8 * RV_SOFT_DOCT_TYPES_NUM;
  // four I64[1] bitsets
  m = MemberLstNew(REG_NONE);
  m->str = StrNew("type_flags_nontag_invis");
  m->offset = off;
  m->size = 8;
  m->member_class = i64t;
  RVExePubMemberDim(m, 1);
  RVExePubMemberPlant(tmpc, m);
  off += 8;
  m = MemberLstNew(REG_NONE);
  m->str = StrNew("type_flags_form");
  m->offset = off;
  m->size = 8;
  m->member_class = i64t;
  RVExePubMemberDim(m, 1);
  RVExePubMemberPlant(tmpc, m);
  off += 8;
  m = MemberLstNew(REG_NONE);
  m->str = StrNew("type_flags_data");
  m->offset = off;
  m->size = 8;
  m->member_class = i64t;
  RVExePubMemberDim(m, 1);
  RVExePubMemberPlant(tmpc, m);
  off += 8;
  m = MemberLstNew(REG_NONE);
  m->str = StrNew("type_flags_chk_dup");
  m->offset = off;
  m->size = 8;
  m->member_class = i64t;
  RVExePubMemberDim(m, 1);
  RVExePubMemberPlant(tmpc, m);
  off += 8;
  // clean_scan_codes[4]
  m = MemberLstNew(REG_NONE);
  m->str = StrNew("clean_scan_codes");
  m->offset = off;
  m->size = 32;
  m->member_class = i64t;
  RVExePubMemberDim(m, 4);
  RVExePubMemberPlant(tmpc, m);
  off += 32;
  // dft_type_flags[43] I32
  m = MemberLstNew(REG_NONE);
  m->str = StrNew("dft_type_flags");
  m->offset = off;
  m->size = 4 * RV_SOFT_DOCT_TYPES_NUM;
  m->member_class = i32t;
  RVExePubMemberDim(m, RV_SOFT_DOCT_TYPES_NUM);
  RVExePubMemberPlant(tmpc, m);
  tmpc->size = off + 4 * RV_SOFT_DOCT_TYPES_NUM;
  return tmpc;
}

CHashClass *RVExePubCDateStructLiteIn(CHashTable *table)
{
  // Lite CDateStruct so Date2Struct(&ds,dt) output is usable (ds.hour/min/sec/...).
  // Value type: size must be right so `CDateStruct ds;` reserves the stack slot.
  CHashClass *tmpc, *u8t, *i32t;
  CMemberLst *m;
  I64 i;
  U8 *names[6];
  I64 offs[6];
  if (!table || !cmp.internal_types)
    return NULL;
  tmpc = HashFind("CDateStruct", table, HTT_CLASS);
  if (tmpc && MemberFind("hour", tmpc) && MemberFind("year", tmpc))
    return tmpc;
  u8t = cmp.internal_types[RT_U8];
  i32t = cmp.internal_types[RT_I32];
  if (!tmpc) {
    tmpc = PrsClassNew;
    tmpc->str = StrNew("CDateStruct");
    tmpc->size = sizeof(CDateStruct);
    tmpc->raw_type = RT_I64;
  }
  names[0] = "sec";         offs[0] = offset(CDateStruct.sec);
  names[1] = "min";         offs[1] = offset(CDateStruct.min);
  names[2] = "hour";        offs[2] = offset(CDateStruct.hour);
  names[3] = "day_of_week"; offs[3] = offset(CDateStruct.day_of_week);
  names[4] = "day_of_mon";  offs[4] = offset(CDateStruct.day_of_mon);
  names[5] = "mon";         offs[5] = offset(CDateStruct.mon);
  for (i = 0; i < 6; i++) {
    if (MemberFind(names[i], tmpc))
      continue;
    m = MemberLstNew(REG_NONE);
    m->str = StrNew(names[i]);
    m->offset = offs[i];
    m->size = 1;
    m->member_class = u8t;
    RVExePubMemberPlant(tmpc, m);
  }
  if (!MemberFind("year", tmpc)) {
    m = MemberLstNew(REG_NONE);
    m->str = StrNew("year");
    m->offset = offset(CDateStruct.year);
    m->size = 4;
    m->member_class = i32t;
    RVExePubMemberPlant(tmpc, m);
  }
  if (!HashFind("CDateStruct", table, HTT_CLASS))
    HashAdd(tmpc, table);
  return tmpc;
}

CHashClass *RVExePubCDirEntryLiteIn(CHashTable *table)
{
  // Lite CDirEntry so FilesFind()'s result is usable: `while (de) { ...de->full_name;
  // de=de->next; }`. Offsets/sizes come from the real struct via offset()/sizeof so they
  // track KernelA.HH. Members inserted with RVExePubMemberPlant (matches MemberFind's BST).
  CHashClass *tmpc, *i64t, *u8t, *u8p, *u16t;
  CMemberLst *m;
  if (!table || !cmp.internal_types)
    return NULL;
  tmpc = HashFind("CDirEntry", table, HTT_CLASS);
  if (tmpc && MemberFind("full_name", tmpc) && MemberFind("next", tmpc))
    return tmpc;
  i64t = cmp.internal_types[RT_I64];
  u8t = cmp.internal_types[RT_U8];
  u16t = cmp.internal_types[RT_U16];
  u8p = u8t + 1;
  if (!tmpc) {
    tmpc = PrsClassNew;
    tmpc->str = StrNew("CDirEntry");
    tmpc->size = sizeof(CDirEntry);
    tmpc->raw_type = RT_I64;
  }
  if (!MemberFind("next", tmpc)) {
    m = MemberLstNew(REG_NONE);
    m->str = StrNew("next");
    m->offset = offset(CDirEntry.next);
    m->size = sizeof(CDirEntry *);
    m->member_class = tmpc + 1;   // CDirEntry* — the class's own one-star slab
    RVExePubMemberPlant(tmpc, m);
  }
  if (!MemberFind("full_name", tmpc)) {
    m = MemberLstNew(REG_NONE);
    m->str = StrNew("full_name");
    m->offset = offset(CDirEntry.full_name);
    m->size = sizeof(U8 *);
    m->member_class = u8p;
    RVExePubMemberPlant(tmpc, m);
  }
  if (!MemberFind("name", tmpc)) {
    m = MemberLstNew(REG_NONE);
    m->str = StrNew("name");
    m->offset = offset(CDirEntry.name);
    m->size = CDIR_FILENAME_LEN;
    m->member_class = u8t;
    RVExePubMemberDim(m, CDIR_FILENAME_LEN);
    RVExePubMemberPlant(tmpc, m);
  }
  if (!MemberFind("size", tmpc)) {
    m = MemberLstNew(REG_NONE);
    m->str = StrNew("size");
    m->offset = offset(CDirEntry.size);
    m->size = sizeof(I64);
    m->member_class = i64t;
    RVExePubMemberPlant(tmpc, m);
  }
  if (!MemberFind("attr", tmpc)) {
    m = MemberLstNew(REG_NONE);
    m->str = StrNew("attr");
    m->offset = offset(CDirEntry.attr);
    m->size = sizeof(U16);
    m->member_class = u16t;
    RVExePubMemberPlant(tmpc, m);
  }
  if (!HashFind("CDirEntry", table, HTT_CLASS))
    HashAdd(tmpc, table);
  return tmpc;
}

I64 RVExePubInternDolDocIn(CHashTable *table)
{
  CHashClass *tmpc;
  CHashGlblVar *tmpg;
  if (!table)
    return 0;
  tmpc = RVExePubCDolDocGlblsLiteIn(table);
  if (!tmpc)
    return 0;
  if (HashFind("doldoc", table, HTT_GLBL_VAR))
    return 1;
  tmpg = CAlloc(sizeof(CHashGlblVar));
  tmpg->str = StrNew("doldoc");
  tmpg->type = HTT_GLBL_VAR;
  tmpg->flags = GVF_ALIAS;
  tmpg->var_class = tmpc;
  tmpg->size = tmpc->size;
  tmpg->data_addr = &doldoc;
  HashAdd(tmpg, table);
  return 1;
}

I64 RVExePubInternFsGsIn(CHashTable *table)
{
  CHashFun *tmpf;
  CHashClass *ct, *ctp;
  I64 n = 0;
  if (!table)
    return 0;
  ct = RVExePubCTaskLiteIn(table);
  if (!ct)
    return 0;
  ctp = ct + 1;
  if (!HashFind("Fs", table, HTT_FUN)) {
    tmpf = PrsFunNew;
    tmpf->str = StrNew("Fs");
    tmpf->exe_addr = IC_FS;
    tmpf->return_class = ctp;
    tmpf->arg_cnt = 0;
    tmpf->member_cnt = 0;
    Bts(&tmpf->flags, Ff_INTERNAL);
    LBtr(&tmpf->flags, Cf_EXTERN);
    tmpf->type |= HTF_PUBLIC;
    HashAdd(tmpf, table);
    n++;
  }
  if (!HashFind("Gs", table, HTT_FUN)) {
    tmpf = PrsFunNew;
    tmpf->str = StrNew("Gs");
    tmpf->exe_addr = IC_GS;
    tmpf->return_class = ctp;
    // CCPU * in stock; CTask* enough for member parse
    tmpf->arg_cnt = 0;
    tmpf->member_cnt = 0;
    Bts(&tmpf->flags, Ff_INTERNAL);
    LBtr(&tmpf->flags, Cf_EXTERN);
    tmpf->type |= HTF_PUBLIC;
    HashAdd(tmpf, table);
    n++;
  }
  return n;
}

/* Stock KernelB.HH `_intern` functions: PrsExp emits tmpf->exe_addr as the IC
 * (Ff_INTERNAL), so the REPL/Soft hash needs them as CHashFun entries. Only
 * the ICs OptPass_RV implements are planted; x86-only ones (In/Out, Carry,
 * RFlags, InvlPg) stay out. Kernel HTT_EXPORT_SYS_SYM entries of the same
 * name (Bt/Bts/StrLen…) are address constants, not callable — these win. */
CHashFun *RVExePubInternNew(CHashTable *table, U8 *name, I64 ic, CHashClass *ret, I64 arg_cnt)
{
  CHashFun *tmpf;
  if (HashFind(name, table, HTT_FUN))
    return NULL;
  tmpf = PrsFunNew;
  tmpf->str = StrNew(name);
  tmpf->exe_addr = ic;
  tmpf->return_class = ret;
  tmpf->arg_cnt = arg_cnt;
  tmpf->member_cnt = arg_cnt;
  Bts(&tmpf->flags, Ff_INTERNAL);
  LBtr(&tmpf->flags, Cf_EXTERN);
  tmpf->type |= HTF_PUBLIC;
  HashAdd(tmpf, table);
  return tmpf;
}

I64 RVExePubInternsIn(CHashTable *table)
{
  CHashFun *tmpf;
  CHashClass *u0, *i64t, *u64t, *f64t, *boolt, *u8t, *u8p, *i64p, *u64p, *u16p, *u32p;
  I64 n = 0, i;
  if (!table || !cmp.internal_types)
    return 0;
  u0 = cmp.internal_types[RT_U0];
  i64t = cmp.internal_types[RT_I64];
  u64t = cmp.internal_types[RT_U64];
  f64t = cmp.internal_types[RT_F64];
  boolt = cmp.internal_types[RT_I8];   // Bool is I8 (CInit internal_types_table)
  u8t = cmp.internal_types[RT_U8];
  u8p = u8t + 1;
  i64p = i64t + 1;
  u64p = u64t + 1;
  u16p = cmp.internal_types[RT_U16] + 1;
  u32p = cmp.internal_types[RT_U32] + 1;
  // (I64 *bit_field, I64 bit_num) -> Bool
  for (i = 0; i < 7; i++) {
    switch (i) {
      case 0 : tmpf = RVExePubInternNew(table, "Bt", IC_BT, boolt, 2); break;
      case 1 : tmpf = RVExePubInternNew(table, "Btc", IC_BTC, boolt, 2); break;
      case 2 : tmpf = RVExePubInternNew(table, "Btr", IC_BTR, boolt, 2); break;
      case 3 : tmpf = RVExePubInternNew(table, "Bts", IC_BTS, boolt, 2); break;
      case 4 : tmpf = RVExePubInternNew(table, "LBtc", IC_LBTC, boolt, 2); break;
      case 5 : tmpf = RVExePubInternNew(table, "LBtr", IC_LBTR, boolt, 2); break;
      default: tmpf = RVExePubInternNew(table, "LBts", IC_LBTS, boolt, 2); break;
    }
    if (tmpf) {
      RVExePubAddArg(tmpf, "bit_field", i64p);
      RVExePubAddArg(tmpf, "bit_num", i64t);
      n++;
    }
  }
  if (tmpf = RVExePubInternNew(table, "Bsf", IC_BSF, i64t, 1)) { RVExePubAddArg(tmpf, "val", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "Bsr", IC_BSR, i64t, 1)) { RVExePubAddArg(tmpf, "val", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "ToUpper", IC_TOUPPER, i64t, 1)) { RVExePubAddArg(tmpf, "ch", u8t); n++; }
  if (tmpf = RVExePubInternNew(table, "StrLen", IC_STRLEN, i64t, 1)) { RVExePubAddArg(tmpf, "st", u8p); n++; }
  if (tmpf = RVExePubInternNew(table, "QueInit", IC_QUE_INIT, u0, 1)) { RVExePubAddArg(tmpf, "head", u8p); n++; }
  if (tmpf = RVExePubInternNew(table, "QueIns", IC_QUE_INS, u0, 2)) { RVExePubAddArg(tmpf, "entry", u8p); RVExePubAddArg(tmpf, "pred", u8p); n++; }
  if (tmpf = RVExePubInternNew(table, "QueInsRev", IC_QUE_INS_REV, u0, 2)) { RVExePubAddArg(tmpf, "entry", u8p); RVExePubAddArg(tmpf, "succ", u8p); n++; }
  if (tmpf = RVExePubInternNew(table, "QueRem", IC_QUE_REM, u0, 1)) { RVExePubAddArg(tmpf, "entry", u8p); n++; }
  if (tmpf = RVExePubInternNew(table, "ATan", IC_ATAN, f64t, 1)) { RVExePubAddArg(tmpf, "d", f64t); n++; }
  if (tmpf = RVExePubInternNew(table, "Abs", IC_ABS, f64t, 1)) { RVExePubAddArg(tmpf, "d", f64t); n++; }
  if (tmpf = RVExePubInternNew(table, "AbsI64", IC_ABS_I64, i64t, 1)) { RVExePubAddArg(tmpf, "i", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "Cos", IC_COS, f64t, 1)) { RVExePubAddArg(tmpf, "d", f64t); n++; }
  if (tmpf = RVExePubInternNew(table, "MaxI64", IC_MAX_I64, i64t, 2)) { RVExePubAddArg(tmpf, "n1", i64t); RVExePubAddArg(tmpf, "n2", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "MaxU64", IC_MAX_U64, u64t, 2)) { RVExePubAddArg(tmpf, "n1", u64t); RVExePubAddArg(tmpf, "n2", u64t); n++; }
  if (tmpf = RVExePubInternNew(table, "MinI64", IC_MIN_I64, i64t, 2)) { RVExePubAddArg(tmpf, "n1", i64t); RVExePubAddArg(tmpf, "n2", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "MinU64", IC_MIN_U64, u64t, 2)) { RVExePubAddArg(tmpf, "n1", u64t); RVExePubAddArg(tmpf, "n2", u64t); n++; }
  if (tmpf = RVExePubInternNew(table, "ModU64", IC_MOD_U64, u64t, 2)) { RVExePubAddArg(tmpf, "q", u64p); RVExePubAddArg(tmpf, "d", u64t); n++; }
  if (tmpf = RVExePubInternNew(table, "SignI64", IC_SIGN_I64, i64t, 1)) { RVExePubAddArg(tmpf, "i", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "Sin", IC_SIN, f64t, 1)) { RVExePubAddArg(tmpf, "d", f64t); n++; }
  if (tmpf = RVExePubInternNew(table, "Sqr", IC_SQR, f64t, 1)) { RVExePubAddArg(tmpf, "d", f64t); n++; }
  if (tmpf = RVExePubInternNew(table, "SqrI64", IC_SQR_I64, i64t, 1)) { RVExePubAddArg(tmpf, "i", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "SqrU64", IC_SQR_U64, u64t, 1)) { RVExePubAddArg(tmpf, "i", u64t); n++; }
  if (tmpf = RVExePubInternNew(table, "Sqrt", IC_SQRT, f64t, 1)) { RVExePubAddArg(tmpf, "d", f64t); n++; }
  if (tmpf = RVExePubInternNew(table, "SwapI64", IC_SWAP_I64, u0, 2)) { RVExePubAddArg(tmpf, "n1", i64p); RVExePubAddArg(tmpf, "n2", i64p); n++; }
  if (tmpf = RVExePubInternNew(table, "SwapU16", IC_SWAP_U16, u0, 2)) { RVExePubAddArg(tmpf, "n1", u16p); RVExePubAddArg(tmpf, "n2", u16p); n++; }
  if (tmpf = RVExePubInternNew(table, "SwapU32", IC_SWAP_U32, u0, 2)) { RVExePubAddArg(tmpf, "n1", u32p); RVExePubAddArg(tmpf, "n2", u32p); n++; }
  if (tmpf = RVExePubInternNew(table, "SwapU8", IC_SWAP_U8, u0, 2)) { RVExePubAddArg(tmpf, "n1", u8p); RVExePubAddArg(tmpf, "n2", u8p); n++; }
  if (tmpf = RVExePubInternNew(table, "Tan", IC_TAN, f64t, 1)) { RVExePubAddArg(tmpf, "d", f64t); n++; }
  if (tmpf = RVExePubInternNew(table, "ToBool", IC_TO_BOOL, boolt, 1)) { RVExePubAddArg(tmpf, "i", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "ToF64", IC_TO_F64, f64t, 1)) { RVExePubAddArg(tmpf, "i", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "ToI64", IC_TO_I64, i64t, 1)) { RVExePubAddArg(tmpf, "d", f64t); n++; }
  if (tmpf = RVExePubInternNew(table, "GetRAX", IC_GET_RAX, i64t, 0)) n++;
  if (tmpf = RVExePubInternNew(table, "GetRBP", IC_GET_RBP, u8p, 0)) n++;
  if (tmpf = RVExePubInternNew(table, "GetRSP", IC_GET_RSP, u8p, 0)) n++;
  if (tmpf = RVExePubInternNew(table, "GetTSC", IC_RDTSC, i64t, 0)) n++;
  if (tmpf = RVExePubInternNew(table, "Pop", IC_POP, i64t, 0)) n++;
  if (tmpf = RVExePubInternNew(table, "Push", IC_PUSH, u0, 1)) { RVExePubAddArg(tmpf, "d", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "SetRAX", IC_SET_RAX, u0, 1)) { RVExePubAddArg(tmpf, "d", i64t); n++; }
  if (tmpf = RVExePubInternNew(table, "SetRBP", IC_SET_RBP, u0, 1)) { RVExePubAddArg(tmpf, "d", u8p); n++; }
  if (tmpf = RVExePubInternNew(table, "SetRSP", IC_SET_RSP, u0, 1)) { RVExePubAddArg(tmpf, "d", u8p); n++; }
  if (tmpf = RVExePubInternNew(table, "CLFlush", IC_CLFLUSH, u0, 1)) { RVExePubAddArg(tmpf, "a", u8p); n++; }
  return n;
}

I64 RVExePubInternFsGs()
{
  if (!Fs || !Fs->hash_table)
    return 0;
  return RVExePubInternFsGsIn(Fs->hash_table);
}

I64 RVExePubsWireAddrs(I64 *addrs)
{
  // Call after CInit (+ asm_hash chain). addrs[0..9] = Print, PutChars, Regs, Reg,
  // Dir, Ls, Pwd, Cd, Help, Man code addresses (Kernel must pass these on split-AOT:
  // Compiler &Regs GOT is often unpatched when only used via address-of).
  CHashFun *tmpf;
  CHashClass *cls_u0, *u8p, *i64t, *u64t;
  CMemberLst *tmpm;
  I64 n = 0;
  if (!Fs || !Fs->hash_table || !cmp.internal_types || !addrs)
    return 0;
  cls_u0 = cmp.internal_types[RT_U0];
  i64t = cmp.internal_types[RT_I64];
  u64t = cmp.internal_types[RT_U64];
  u8p = cmp.internal_types[RT_U8] + 1;
  n += RVExePubInternFsGs;
  RVExePubCDirEntryLiteIn(Fs->hash_table);
  RVExePubCDateStructLiteIn(Fs->hash_table);
  n += RVExePubInternsIn(Fs->hash_table);
  // Compiler-unit debug entry points (local addresses): PassTrace dumps ICs per pass.
  if (!HashFind("PassTrace", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("PassTrace", &PassTrace, i64t, 1);
    if (tmpf) {
      RVExePubAddArg(tmpf, "i", i64t, MLF_DFT_AVAILABLE, 0b10001111101);
      n++;
    }
  }
  if (!HashFind("Print", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Print", addrs[0], cls_u0, 1);
    if (tmpf) {
      Bts(&tmpf->flags, Ff_DOT_DOT_DOT);
      RVExePubAddArg(tmpf, "fmt", u8p);
      RVExePubAddArg(tmpf, "argc", i64t, 16);
      // MLF_DOT_DOT_DOT (KernelA; aot Cmp unit may lack HH)
      RVExePubAddArg(tmpf, "argv", i64t, 16);
      n++;
    }
  }
  if (!HashFind("PutChars", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("PutChars", addrs[1], cls_u0, 1);
    if (tmpf) {
      RVExePubAddArg(tmpf, "ch", u64t);
      n++;
    }
  }
  if (!HashFind("Regs", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Regs", addrs[2], cls_u0, 0);
    if (tmpf)
      n++;
  }
  if (!HashFind("Reg", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Reg", addrs[3], i64t, 1);
    if (tmpf) {
      RVExePubAddArg(tmpf, "name", u8p);
      n++;
    }
  }
  if (!HashFind("Dir", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Dir", addrs[4], cls_u0, 0);
    if (tmpf)
      n++;
  }
  if (!HashFind("Ls", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Ls", addrs[5], cls_u0, 0);
    if (tmpf)
      n++;
  }
  if (!HashFind("Pwd", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Pwd", addrs[6], cls_u0, 0);
    if (tmpf)
      n++;
  }
  if (!HashFind("Cd", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Cd", addrs[7], i64t, 1);
    if (tmpf) {
      RVExePubAddArg(tmpf, "dirname", u8p, MLF_DFT_AVAILABLE);
      tmpm = tmpf->last_in_member_lst;
      if (tmpm)
        tmpm->dft_val = 0;
      n++;
    }
  }
  if (!HashFind("Help", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Help", addrs[8], cls_u0, 0);
    if (tmpf)
      n++;
  }
  if (!HashFind("Man", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Man", addrs[9], cls_u0, 1);
    if (tmpf) {
      RVExePubAddArg(tmpf, "name", u8p);
      n++;
    }
  }
  // Slots 10-13 (win harness): Adam FileMgr/FileNameForm and their zero/one-arg PopUp
  // runners, so servant ExePutS("Cd(…);FileMgr(FM_PICK_FILE,Fs->parent_task);") and
  // DocPopUp's FileNameForm(...) resolve. Read only when non-zero (short arrays).
  if (addrs[10] && !HashFind("FileMgr", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("FileMgr", addrs[10], u8p, 2);
    if (tmpf) {
      RVExePubAddArg(tmpf, "mode", i64t, MLF_DFT_AVAILABLE, 0);
      RVExePubAddArg(tmpf, "mem_task", u8p, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[11] && !HashFind("DocPopUpPickFileRun", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("DocPopUpPickFileRun", addrs[11], u8p, 1);
    if (tmpf) {
      RVExePubAddArg(tmpf, "dir", u8p, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[12] && !HashFind("FileNameForm", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("FileNameForm", addrs[12], u8p, 3);
    if (tmpf) {
      RVExePubAddArg(tmpf, "dft", u8p, MLF_DFT_AVAILABLE, 0);
      RVExePubAddArg(tmpf, "dof_flags", i64t, MLF_DFT_AVAILABLE, 0);
      RVExePubAddArg(tmpf, "mem_task", u8p, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[13] && !HashFind("DocPopUpFileNameRun", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("DocPopUpFileNameRun", addrs[13], u8p, 0);
    if (tmpf)
      n++;
  }
  // Slot 14, and read only when non-zero: callers that pass a shorter array (the
  // monolithic RVExePubsWire below used to pass 10) must not be read out of bounds.
  if (addrs[14] && !HashFind("Cat", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Cat", addrs[14], cls_u0, 1);
    if (tmpf) {
      RVExePubAddArg(tmpf, "name", u8p);
      n++;
    }
  }
  // Slot 15: FilesFind — query runtime. Returns CDirEntry* (planted as i64t, caller
  // casts) so stock file-utility programs (Templates/Util1.HC) resolve.
  if (addrs[15] && !HashFind("FilesFind", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("FilesFind", addrs[15], i64t, 2);
    if (tmpf) {
      RVExePubAddArg(tmpf, "mask", u8p);
      RVExePubAddArg(tmpf, "flags", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  // Slots 16-22: query/util runtime (no side effects, no blocking input). Pointer
  // returns/args are planted as i64t and the caller casts (no struct classes here).
  if (addrs[16] && !HashFind("DirTreeDel", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("DirTreeDel", addrs[16], cls_u0, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "de", i64t); n++; }
  }
  if (addrs[17] && !HashFind("StrFind", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("StrFind", addrs[17], i64t, 3);
    if (tmpf) {
      RVExePubAddArg(tmpf, "needle", u8p);
      RVExePubAddArg(tmpf, "haystack", u8p);
      RVExePubAddArg(tmpf, "flags", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[18] && !HashFind("ScanFlags", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("ScanFlags", addrs[18], cls_u0, 3);
    if (tmpf) {
      RVExePubAddArg(tmpf, "dst", i64t);
      RVExePubAddArg(tmpf, "lst", u8p);
      RVExePubAddArg(tmpf, "src", u8p);
      n++;
    }
  }
  if (addrs[19] && !HashFind("Define", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Define", addrs[19], i64t, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "dname", u8p); n++; }
  }
  if (addrs[20] && !HashFind("Now", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Now", addrs[20], i64t, 0);
    if (tmpf) n++;
  }
  if (addrs[21] && !HashFind("Str2Date", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Str2Date", addrs[21], i64t, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "st", u8p); n++; }
  }
  if (addrs[22] && !HashFind("Date2Struct", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Date2Struct", addrs[22], cls_u0, 2);
    if (tmpf) {
      RVExePubAddArg(tmpf, "ds", i64t);
      RVExePubAddArg(tmpf, "cdt", i64t);
      n++;
    }
  }
  // Slots 23-27: allocator + string foundations. Not compiler intrinsics and not
  // callable via the HTF_IMM RVCmpImports table — programs that MAlloc/StrNew need
  // these planted as real HTT_FUN calls. Pointer returns are i64t (caller casts).
  if (addrs[23] && !HashFind("MAlloc", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("MAlloc", addrs[23], i64t, 2);
    if (tmpf) {
      RVExePubAddArg(tmpf, "size", i64t);
      RVExePubAddArg(tmpf, "mem_task", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[24] && !HashFind("CAlloc", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("CAlloc", addrs[24], i64t, 2);
    if (tmpf) {
      RVExePubAddArg(tmpf, "size", i64t);
      RVExePubAddArg(tmpf, "mem_task", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[25] && !HashFind("Free", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Free", addrs[25], cls_u0, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "ptr", i64t); n++; }
  }
  if (addrs[26] && !HashFind("StrNew", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("StrNew", addrs[26], i64t, 2);
    if (tmpf) {
      RVExePubAddArg(tmpf, "buf", u8p);
      RVExePubAddArg(tmpf, "mem_task", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[27] && !HashFind("Str2I64", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Str2I64", addrs[27], i64t, 3);
    if (tmpf) {
      RVExePubAddArg(tmpf, "st", u8p);
      RVExePubAddArg(tmpf, "radix", i64t, MLF_DFT_AVAILABLE, 10);
      RVExePubAddArg(tmpf, "end", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  // Slots 28-30: the printf-family (varargs). Same shape as Print above: arg_cnt is the
  // FIXED args, Ff_DOT_DOT_DOT set, then the argc/argv varargs markers (MLF_DOT_DOT_DOT).
  if (addrs[28] && !HashFind("MStrPrint", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("MStrPrint", addrs[28], i64t, 1);
    if (tmpf) {
      Bts(&tmpf->flags, Ff_DOT_DOT_DOT);
      RVExePubAddArg(tmpf, "fmt", u8p);
      RVExePubAddArg(tmpf, "argc", i64t, 16);
      RVExePubAddArg(tmpf, "argv", i64t, 16);
      n++;
    }
  }
  if (addrs[29] && !HashFind("StrPrint", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("StrPrint", addrs[29], i64t, 2);
    if (tmpf) {
      Bts(&tmpf->flags, Ff_DOT_DOT_DOT);
      RVExePubAddArg(tmpf, "dst", u8p);
      RVExePubAddArg(tmpf, "fmt", u8p);
      RVExePubAddArg(tmpf, "argc", i64t, 16);
      RVExePubAddArg(tmpf, "argv", i64t, 16);
      n++;
    }
  }
  if (addrs[30] && !HashFind("DocPrint", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("DocPrint", addrs[30], i64t, 2);
    if (tmpf) {
      Bts(&tmpf->flags, Ff_DOT_DOT_DOT);
      RVExePubAddArg(tmpf, "doc", i64t, MLF_DFT_AVAILABLE, 0);
      RVExePubAddArg(tmpf, "fmt", u8p);
      RVExePubAddArg(tmpf, "argc", i64t, 16);
      RVExePubAddArg(tmpf, "argv", i64t, 16);
      n++;
    }
  }
  // Slots 31-35: mem + doc-object manipulation. MemCpy/MemSet are &RVMemCpy/&RVMemSet
  // (the RV implementations) planted under their stock names.
  if (addrs[31] && !HashFind("MemCpy", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("MemCpy", addrs[31], i64t, 3);
    if (tmpf) {
      RVExePubAddArg(tmpf, "dst", i64t);
      RVExePubAddArg(tmpf, "src", i64t);
      RVExePubAddArg(tmpf, "size", i64t);
      n++;
    }
  }
  if (addrs[32] && !HashFind("MemSet", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("MemSet", addrs[32], i64t, 3);
    if (tmpf) {
      RVExePubAddArg(tmpf, "dst", i64t);
      RVExePubAddArg(tmpf, "dat", i64t);
      RVExePubAddArg(tmpf, "size", i64t);
      n++;
    }
  }
  if (addrs[33] && !HashFind("DocNew", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("DocNew", addrs[33], i64t, 2);
    if (tmpf) {
      RVExePubAddArg(tmpf, "filename", u8p, MLF_DFT_AVAILABLE, 0);
      RVExePubAddArg(tmpf, "task", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[34] && !HashFind("DocDel", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("DocDel", addrs[34], cls_u0, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "doc", i64t); n++; }
  }
  if (addrs[35] && !HashFind("DocClear", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("DocClear", addrs[35], cls_u0, 2);
    if (tmpf) {
      RVExePubAddArg(tmpf, "doc", i64t, MLF_DFT_AVAILABLE, 0);
      RVExePubAddArg(tmpf, "clear_holds", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  // Slots 36-37: filesystem read/write, so REPL programs can load/save files.
  if (addrs[36] && !HashFind("FileRead", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("FileRead", addrs[36], i64t, 3);
    if (tmpf) {
      RVExePubAddArg(tmpf, "name", u8p);
      RVExePubAddArg(tmpf, "size", i64t, MLF_DFT_AVAILABLE, 0);
      RVExePubAddArg(tmpf, "attr", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[37] && !HashFind("FileWrite", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("FileWrite", addrs[37], i64t, 5);
    if (tmpf) {
      RVExePubAddArg(tmpf, "name", u8p);
      RVExePubAddArg(tmpf, "fbuf", u8p);
      RVExePubAddArg(tmpf, "size", i64t);
      RVExePubAddArg(tmpf, "cdt", i64t, MLF_DFT_AVAILABLE, 0);
      RVExePubAddArg(tmpf, "attr", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  // Slots 38-40: the VT console features as real HolyC functions — Find("needle");
  // Ed("file"); Tasks; — so they run through the compiler like Cat/Dir, not as
  // dispatch barewords.
  if (addrs[38] && !HashFind("Find", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Find", addrs[38], cls_u0, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "needle", u8p); n++; }
  }
  if (addrs[39] && !HashFind("Ed", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Ed", addrs[39], cls_u0, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "name", u8p); n++; }
  }
  if (addrs[40] && !HashFind("Tasks", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Tasks", addrs[40], cls_u0, 0);
    if (tmpf) n++;
  }
  // Slots 41-45: RISC-V exploration (Kernel/RVExplore.HC). AsmList/AsmDoc document what
  // the asm{} assembler accepts; MemMap prints the platform map; Mstatus/Mcause read+
  // decode the trap CSRs.
  if (addrs[41] && !HashFind("AsmList", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("AsmList", addrs[41], cls_u0, 0);
    if (tmpf) n++;
  }
  if (addrs[42] && !HashFind("AsmDoc", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("AsmDoc", addrs[42], cls_u0, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "mn", u8p); n++; }
  }
  if (addrs[43] && !HashFind("MemMap", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("MemMap", addrs[43], cls_u0, 0);
    if (tmpf) n++;
  }
  if (addrs[44] && !HashFind("Mstatus", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Mstatus", addrs[44], cls_u0, 0);
    if (tmpf) n++;
  }
  if (addrs[45] && !HashFind("Mcause", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Mcause", addrs[45], cls_u0, 0);
    if (tmpf) n++;
  }
  if (addrs[46] && !HashFind("Csr", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Csr", addrs[46], cls_u0, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "name", u8p); n++; }
  }
  if (addrs[47] && !HashFind("Uptime", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Uptime", addrs[47], cls_u0, 0);
    if (tmpf) n++;
  }
  return n;
}

/* TempleOS-style debugger register labels. Stock TempleOS lets you read AND assign registers
 * as var-like labels (`U(_RIP-16);`, `_RAX = 5;` — Doc/DbgOverview.DD). The same trick works
 * here with no compiler change: plant each register as an ordinary I64 GLOBAL whose storage IS
 * its slot in the fault freeze, exactly as RVExePubInternDolDocIn aliases `doldoc`.
 *
 * Addresses must match bootstrap/seed/trap.hc (TRAP_SNAP_X / MEM_TRAP_SNAP) and
 * bootstrap/holy_rt.h (HOLY_TRAP_SNAP_X / HOLY_TRAP_SNAP) — both images publish both views.
 * Writes land in the freeze; making them take effect on resume is the trap-return copy-back. */
#define RV_DBG_SNAP    0x87000100
#define RV_DBG_SNAP_X  0x87000400

I64 RVExePubRegAlias(U8 *name, I64 addr, CHashClass *i64t)
{
  CHashGlblVar *tmpg;
  if (!name || !addr || !i64t || !Fs || !Fs->hash_table)
    return 0;
  if (HashFind(name, Fs->hash_table, HTT_GLBL_VAR))
    return 0;
  tmpg = CAlloc(sizeof(CHashGlblVar));
  tmpg->str = StrNew(name);
  tmpg->type = HTT_GLBL_VAR;
  tmpg->flags = GVF_ALIAS;
  // fixed address: never freed with the entry
  tmpg->var_class = i64t;
  tmpg->size = 8;
  tmpg->data_addr = addr;
  HashAdd(tmpg, Fs->hash_table);
  return 1;
}

/* _X0.._X31 by register number, every ABI name at the same address, and the CSR slots.
 * `Dr;` prints them; `_A0` / `_PC` read them; assignment writes the freeze. */
I64 RVExePubsWireDbgRegs()
{
  CHashClass *i64t;
  U8 nm[16], *p;
  I64 n = 0, i, k;
  if (!Fs || !Fs->hash_table || !cmp.internal_types)
    return 0;
  i64t = cmp.internal_types[RT_I64];
  if (!i64t)
    return 0;
  i = 0;
  while (i < 32) {
    StrPrint(nm, "_X%d", i);
    n += RVExePubRegAlias(nm, RV_DBG_SNAP_X + i * 8, i64t);
    i++;
  }
  p = "zero ra sp gp tp t0 t1 t2 fp s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6";
  i = 0;
  while (i < 32) {
    k = 0;
    nm[k++] = '_';
    while (*p && *p != ' ') {
      if (k < 14)
        nm[k++] = ToUpper(*p);
      p++;
    }
    nm[k] = 0;
    if (*p == ' ')
      p++;
    n += RVExePubRegAlias(nm, RV_DBG_SNAP_X + i * 8, i64t);
    i++;
  }
  n += RVExePubRegAlias("_S0", RV_DBG_SNAP_X + 8 * 8, i64t);
  // s0 == fp == x8
  n += RVExePubRegAlias("_MCAUSE", RV_DBG_SNAP + 18 * 8, i64t);
  n += RVExePubRegAlias("_MEPC", RV_DBG_SNAP + 19 * 8, i64t);
  n += RVExePubRegAlias("_PC", RV_DBG_SNAP + 19 * 8, i64t);
  n += RVExePubRegAlias("_RIP", RV_DBG_SNAP + 19 * 8, i64t);
  // stock spelling
  n += RVExePubRegAlias("_MTVAL", RV_DBG_SNAP + 20 * 8, i64t);
  n += RVExePubRegAlias("_MSTATUS", RV_DBG_SNAP + 21 * 8, i64t);
  return n;
}

/* Debugger surface for the REPL: Kernel passes &Disasm,&DisasmAt,&U,&UA,&RVDisFnAddr,&RVUf
 * (8-slot array; zero = not provided). Separate from WireAddrs so short arrays stay safe. */
I64 RVExePubsWireDbg(I64 *addrs)
{
  CHashFun *tmpf;
  CHashClass *cls_u0, *u8p, *i64t;
  I64 n = 0;
  if (!Fs || !Fs->hash_table || !cmp.internal_types || !addrs)
    return 0;
  cls_u0 = cmp.internal_types[RT_U0];
  i64t = cmp.internal_types[RT_I64];
  u8p = cmp.internal_types[RT_U8] + 1;
  if (addrs[0] && !HashFind("Disasm", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Disasm", addrs[0], cls_u0, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "name", u8p); n++; }
  }
  if (addrs[1] && !HashFind("DisasmAt", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("DisasmAt", addrs[1], cls_u0, 3);
    if (tmpf) {
      RVExePubAddArg(tmpf, "addr", i64t);
      RVExePubAddArg(tmpf, "max", i64t, MLF_DFT_AVAILABLE, 2000);
      RVExePubAddArg(tmpf, "end", i64t, MLF_DFT_AVAILABLE, 0);
      n++;
    }
  }
  if (addrs[2] && !HashFind("U", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("U", addrs[2], cls_u0, 2);
    if (tmpf) { RVExePubAddArg(tmpf, "addr", i64t); RVExePubAddArg(tmpf, "n", i64t, MLF_DFT_AVAILABLE, 28); n++; }
  }
  if (addrs[3] && !HashFind("UA", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("UA", addrs[3], cls_u0, 2);
    if (tmpf) { RVExePubAddArg(tmpf, "addr", i64t); RVExePubAddArg(tmpf, "n", i64t, MLF_DFT_AVAILABLE, 28); n++; }
  }
  if (addrs[4] && !HashFind("FnAddr", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("FnAddr", addrs[4], i64t, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "name", u8p); n++; }
  }
  if (addrs[5] && !HashFind("Uf", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Uf", addrs[5], cls_u0, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "name", u8p); n++; }
  }
  if (addrs[6] && !HashFind("Bp", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("Bp", addrs[6], i64t, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "addr", i64t, MLF_DFT_AVAILABLE, 0); n++; }
  }
  if (addrs[7] && !HashFind("BpClr", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("BpClr", addrs[7], i64t, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "addr", i64t, MLF_DFT_AVAILABLE, 0); n++; }
  }
  n += RVExePubsWireDbgRegs();
  // _X0.._X31 / _A0 / _PC …: no addrs needed, the freeze is at a fixed address
  // asm REPL (RVAsmRepl.HC, linked ahead of this file): step one line with the same array
  // as its register file, so the debugger and the JIT share one context.
  if (!HashFind("AsmStep", Fs->hash_table, HTT_FUN)) {
    tmpf = RVExePubFunNew("AsmStep", &AsmStep, i64t, 1);
    if (tmpf) { RVExePubAddArg(tmpf, "text", u8p); n++; }
  }
  if (!HashFind("AsmRegs", Fs->hash_table, HTT_FUN)) {
    if (RVExePubFunNew("AsmRegs", &AsmRegs, cls_u0, 0)) n++;
  }
  if (!HashFind("AsmClr", Fs->hash_table, HTT_FUN)) {
    if (RVExePubFunNew("AsmClr", &AsmClr, cls_u0, 0)) n++;
  }
  // Dr: the stock register dump over the same freeze (RVDbgCore.HC)
  if (!HashFind("Dr", Fs->hash_table, HTT_FUN)) {
    if (RVExePubFunNew("Dr", &Dr, cls_u0, 0)) n++;
  }
  return n;
}

I64 RVExePubsWire()
{
  // Monolithic Body: symbols are in-image. Split-AOT Kernel should call
  // RVExePubsWireAddrs with Kernel &Print/&Regs/… instead.
  I64 addrs[64];
  I64 zi;
  for (zi = 0; zi < 64; zi++)
    addrs[zi] = 0;
  addrs[0] = &Print;
  addrs[1] = &PutChars;
  addrs[2] = &Regs;
  addrs[3] = &Reg;
  addrs[4] = &RVWinSoftDir;
  addrs[5] = &RVWinSoftLs;
  addrs[6] = &RVWinSoftPwd;
  addrs[7] = &RVWinSoftCd;
  addrs[8] = &RVWinSoftHelp;
  addrs[9] = &RVWinSoftMan;
  addrs[14] = &RVWinSoftCat;
  addrs[38] = &RVWinSoftFind;
  addrs[39] = &RVWinSoftEd;
  addrs[40] = &RVWinSoftTasks;
  addrs[41] = &AsmList;
  addrs[42] = &AsmDoc;
  addrs[43] = &MemMap;
  addrs[44] = &Mstatus;
  addrs[45] = &Mcause;
  addrs[46] = &Csr;
  addrs[47] = &Uptime;
  return RVExePubsWireAddrs(addrs);
}
// Split-AOT: Compiler unit has its own Fs/Gs storage. Kernel sets the live
// task pointers — sync before CInit/ExePutS so guest Cmp uses Adam's Fs.
U0 RVAotLibSync(I64 fs, I64 gs)
{
  Fs = fs;
  Gs = gs;
}
// Host AOT Compiler unit keeps its own BSS char_bmp_* (all zero). Lex then
// splits I64→"I"+6 and 40+2→4 then 0+2. Same bug as Load's RVCmpPatchCharBmps;
// Kernel passes live StrA bitmap pointers (I64[17] pack).
U0 RVCmpWireCharBmps(I64 *src)
{
  I64 n = 16 * sizeof(U32);
  if (!src)
    return;
  if (src[0])
    MemCpy(char_bmp_alpha, src[0], n);
  if (src[1])
    MemCpy(char_bmp_alpha_numeric, src[1], n);
  if (src[2])
    MemCpy(char_bmp_alpha_numeric_no_at, src[2], n);
  if (src[3])
    MemCpy(char_bmp_word, src[3], n);
  if (src[4])
    MemCpy(char_bmp_dec_numeric, src[4], n);
  if (src[5])
    MemCpy(char_bmp_hex_numeric, src[5], n);
  if (src[6])
    MemCpy(char_bmp_white_space, src[6], n);
  if (src[7])
    MemCpy(char_bmp_non_eol_white_space, src[7], n);
  if (src[8])
    MemCpy(char_bmp_zero_cr_nl_cursor, src[8], n);
  if (src[9])
    MemCpy(char_bmp_zero_tab_cr_nl_cursor, src[9], n);
  if (src[10])
    MemCpy(char_bmp_zero_tab_cr_nl_cursor_dollar, src[10], n);
  if (src[11])
    MemCpy(char_bmp_macro, src[11], n);
  if (src[12])
    MemCpy(char_bmp_printable, src[12], n);
  if (src[13])
    MemCpy(char_bmp_displayable, src[13], n);
  if (src[14])
    MemCpy(char_bmp_safe_dollar, src[14], n);
  if (src[15])
    MemCpy(char_bmp_filename, src[15], n);
  if (src[16])
    MemCpy(char_bmp_non_eol, src[16], n);
}
// Chain cmp.asm_hash under Fs (same as in-image Body path after CInit).
// Never overwrite an existing next (servant→parent): walk to the end and
// attach asm_hash there. Severing parent loses ExePubs (FileMgr HTT_FUN).
U0 RVCmpWireAsmHash()
{
  CHashTable *ht;
  if (cmp.asm_hash)
    cmp.asm_hash->next = NULL;
  // Soft AOT: CmpCtrlNew sets glbl→asm_hash (not Fs). Plant _intern Fs/Gs +
  // CTask.hash_table here so Soft DocInit `Fs->hash_table` Soft Cmps.
  // Soft tip Soft #include stock DocInit_RV: plant Kernel doldoc abs into asm_hash.
  if (cmp.asm_hash) {
    RVExePubInternFsGsIn(cmp.asm_hash);
    RVExePubInternDolDocIn(cmp.asm_hash);
    RVExePubCDirEntryLiteIn(cmp.asm_hash);
    RVExePubCDateStructLiteIn(cmp.asm_hash);
    RVExePubInternsIn(cmp.asm_hash);
  }
  if (!Fs || !Fs->hash_table || !cmp.asm_hash)
    return;
  if (Fs->hash_table == cmp.asm_hash)
    return;
  ht = Fs->hash_table;
  while (ht->next) {
    if (ht->next == cmp.asm_hash)
      return;
    ht = ht->next;
  }
  ht->next = cmp.asm_hash;
}

I64 RVCmpCtrlAddrsGet(I64 *out)
{
  //Split-AOT: Kernel &CmpCtrlNew is an unpatched GOT — calling it → illegal insn
  // (insn≈0x8098 truncated ptr). This runs in the Compiler unit so &CmpCtrlNew/&Lex
  // are real code addresses. Kernel passes out[4] then RVMenuWireCmpCtrlAddrs.
  if (!out)
    return 0;
  out[0] = &CmpCtrlNew;
  out[1] = &Lex;
  out[2] = &LexExpressionI64;
  out[3] = &CmpCtrlDel;
  return 4;
}
// Split-AOT ExePutS entry: Compiler Fs is a separate data slot from Kernel Fs.
// Yield only updates Kernel's slot (holy_fs_slot). Re-sync + re-wire before JIT.
I64 RVExePutSSynced(U8 *buf, I64 fs, I64 gs)
{
  RVAotLibSync(fs, gs);
  RVCmpWireAsmHash;
  return ExePutS(buf);
}
