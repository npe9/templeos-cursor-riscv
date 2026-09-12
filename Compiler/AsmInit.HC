U0 AsmPrsInsFlags(CCmpCtrl *cc, CInst *tmpins)
{
  I64 i;
  while (TRUE) {
    switch (cc->token) {
      case TK_IDENT :
      if ((i = LstMatch(cc->cur_str, "NO\0CB\0CW\0CD\0CP\0IB\0IW\0ID\0")) >= 0) {
        tmpins->opcode_modifier = i;
        break;
      } else
        return;
      case TK_I64 :
      if (cc->cur_i64 == 16)
        tmpins->flags |= IEF_OP_SIZE16;
      else if (cc->cur_i64 == 32)
        tmpins->flags |= IEF_OP_SIZE32;
      else
        return;
      break;
      case '+' :
      tmpins->flags |= IEF_PLUS_OPCODE;
      case '/' :
      if (Lex(cc) == TK_I64 && cc->cur_i64 < 8)
        tmpins->slash_val = cc->cur_i64;
      else if (cc->token == TK_IDENT) {
        if (!StrCmp(cc->cur_str, "R"))
          tmpins->slash_val = SV_R_REG;
        else if (!StrCmp(cc->cur_str, "I"))
          tmpins->slash_val = SV_I_REG;
        else
          return;
      } else
        return;
      break;
      case '!' :
      tmpins->flags |= IEF_DONT_SWITCH_MODES;
      break;
      case '&' :
      tmpins->flags |= IEF_DFT;
      break;
      case '%' :
      tmpins->flags |= IEF_NOT_IN_64_BIT;
      break;
      case '=' :
      tmpins->flags |= IEF_48_REX;
      break;
      case '`' :
      tmpins->flags |= IEF_REX_ONLY_R8_R15;
      break;
      case '^' :
      tmpins->flags |= IEF_REX_XOR_LIKE;
      break;
      case '*' :
      tmpins->flags |= IEF_STI_LIKE;
      break;
      case '$$' :
      tmpins->flags |= IEF_ENDING_ZERO;
      break;
      default:
      return;
    }
    Lex(cc);
  }
}

U0 AsmHashAddInternalType(U8 *name, I64 rt, I64 sz)
{
  // Register a plain type name (I64, …) when OpCodes/KernelA unions are absent.
  CHashClass *c;
  I64 j;
  if (!cmp.asm_hash)
    return;
  if (HashFind(name, cmp.asm_hash, HTT_INTERNAL_TYPE, 1))
    return;
  c = PrsClassNew;
  c->type = HTT_INTERNAL_TYPE;
  c->raw_type = rt;
  Bts(&c->flags, Cf_INTERNAL_TYPE);
  c->size = sz;
  c->str = AStrNew(name);
  HashAdd(c, cmp.asm_hash);
  if (!cmp.internal_types[rt])
    cmp.internal_types[rt] = c;
  for (j = 1; j <= PTR_STARS_NUM; j++) {
    c[j].type = HTT_CLASS;
    c[j].raw_type = RT_PTR;
    c[j].size = sizeof(U8 *);
    c[j].ptr_stars_cnt = j;
  }
}

U0 AsmHashLoad()
{
  //See $LK,"::/Compiler/OpCodes.DD"$.
  I64 i, j;
  CInternalType *tmpit;
  CHashClass *tmpc;
  cmp.size_arg_mask[0] = 0x3FF0FFFFFE;
  cmp.size_arg_mask[1] = 0x1110111112;
  cmp.size_arg_mask[2] = 0x2220222224;
  cmp.size_arg_mask[4] = 0x0440444448;
  cmp.size_arg_mask[8] = 0x0880888880;
  cmp.asm_hash = HashTableNew(1024);
  // RV: A2/ExePutS RAM disk has no OpCodes.DD. FileRead("A:/Compiler/...") PrintErr-spams
  // via Name2DirClus and is unnecessary — soft-load HolyC keywords (same ids as OpCodes.DD).
  // When a board image ships OpCodes on A:, restore FileRead("A:/Compiler/OpCodes.DD") here.
  {
    // No OpCodes.DD yet: soft-load HolyC keywords (same order/ids as OpCodes.DD).
    U8 *kw = "include\0define\0union\0catch\0class\0try\0if\0else\0for\0while\0" "extern\0_extern\0return\0sizeof\0_intern\0do\0asm\0goto\0exe\0break\0" "switch\0start\0end\0case\0default\0public\0offset\0import\0_import\0" "ifdef\0ifndef\0ifaot\0ifjit\0endif\0assert\0reg\0noreg\0lastclass\0" "no_warn\0help_index\0help_file\0static\0lock\0defined\0interrupt\0" "haserrcode\0argpop\0noargpop\0continue\0";
    I64 ki = 0;
    while (*kw) {
      CHashGeneric *tmph = CAlloc(sizeof(CHashGeneric));
      tmph->type = HTT_KEYWORD;
      tmph->str = AStrNew(kw);
      tmph->user_data0 = ki++;
      HashAdd(tmph, cmp.asm_hash);
      while (*kw++)
        ;
    }
  }
  for (i = 0; i < INTERNAL_TYPES_NUM; i++) {
    tmpit = &internal_types_table[i];
    tmpc = PrsClassNew;
    tmpc->type = HTT_INTERNAL_TYPE;
    tmpc->raw_type = tmpit->type;
    Bts(&tmpc->flags, Cf_INTERNAL_TYPE);
    tmpc->size = tmpit->size;
    tmpc->str = AStrNew(tmpit->name);
    HashAdd(tmpc, cmp.asm_hash);
    cmp.internal_types[tmpc->raw_type] = tmpc;
    // RV: re-assert * / ** / … slots. Corrupt ptr_stars_cnt on
    // internal_types[RT_U8]+1 (saw stars=5) hung CmpRawTypePointed via tmpc--.
    for (j = 1; j <= PTR_STARS_NUM; j++) {
      tmpc[j].type = HTT_CLASS;
      tmpc[j].raw_type = RT_PTR;
      tmpc[j].size = sizeof(U8 *);
      tmpc[j].ptr_stars_cnt = j;
    }
  }
  // Plain I64/U64/… (TempleOS KernelA unions over *i); needed before full Load.
  AsmHashAddInternalType("I16", RT_I16, 2);
  AsmHashAddInternalType("U16", RT_U16, 2);
  AsmHashAddInternalType("I32", RT_I32, 4);
  AsmHashAddInternalType("U32", RT_U32, 4);
  AsmHashAddInternalType("I64", RT_I64, 8);
  AsmHashAddInternalType("U64", RT_U64, 8);
#ifdef CMP_RV_ASM
  AsmRVRegsAdd;
#endif
  // Terminal table. Do not set adam_task->hash_table->next = cmp.asm_hash here:
  // when hash_table aliases asm_hash (or next is already asm_hash), that assignment
  // creates a self-loop and HashFind spins forever after CInit.
  cmp.asm_hash->next = NULL;
}
