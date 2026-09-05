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

U0 RVExePubAddArg(CHashFun *tmpf, U8 *aname, CHashClass *cls, I64 flags = 0)
{
  CMemberLst *tmpm;
  if (!tmpf || !aname || !cls)
    return;
  tmpm = MemberLstNew(REG_ALLOC);
  tmpm->str = StrNew(aname);
  tmpm->member_class = cls;
  tmpm->flags = flags;
  tmpm->size = 8;
  RVExePubMemberLink(tmpf, tmpm);
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
  return n;
}

I64 RVExePubsWire()
{
  // Monolithic Body: symbols are in-image. Split-AOT Kernel should call
  // RVExePubsWireAddrs with Kernel &Print/&Regs/… instead.
  I64 addrs[10];
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
U0 RVCmpWireAsmHash()
{
  if (cmp.asm_hash)
    cmp.asm_hash->next = NULL;
  if (Fs && Fs->hash_table && cmp.asm_hash && Fs->hash_table != cmp.asm_hash)
    Fs->hash_table->next = cmp.asm_hash;
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
