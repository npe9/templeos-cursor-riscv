/* HolyC Parser - Generates Intermediate Code */

#include "holyc_compiler.h"
static bool EmitFnAddress(Compiler *cc, CHashFun *fn);
static void SkipRegQualifier(Compiler *cc);
static bool ParseAssignment(Compiler *cc);
static I64 PtrElemInfo(Compiler *cc, U8 *pointee, I64 *depth);
static bool ParseExp(Compiler *cc);
static bool ParseMul(Compiler *cc);
static bool ParseBitwiseAnd(Compiler *cc);
static bool ParseBitwiseXor(Compiler *cc);
static bool ParseBitwiseOr(Compiler *cc);
static bool ParseAdd(Compiler *cc);
static bool ParseComparison(Compiler *cc);
static bool ParseEquality(Compiler *cc);
static bool ParseLogicalAnd(Compiler *cc);
static I64 CEPostfixCast(Compiler *cc, I64 v);
#ifndef BARE_METAL
#include <stdio.h>
#include <stdlib.h>
#endif
#ifndef BARE_METAL
#define PF_TRACE(line) do { if (getenv("HOLYC_TRACE")) fprintf(stderr, "[trace] ParseFunction fail at parser.c:%d token=%d ('%s')\n", (line), cc->lex.token, cc->lex.token_str ? cc->lex.token_str : ""); } while (0)
#else
#define PF_TRACE(line) do {} while (0)
#endif


static U8 ParseType(Compiler *cc);

// Walk cls and its base_class chain (TempleOS MemberFind). Needed so
// `CHashClass *p; p->str` resolves to CHash.str, not silent offset 0.
/* A member the class does not have used to resolve SILENTLY to offset 0, i.e. the aggregate's
 * own address used as if it were the field — a wild read with no diagnostic. Demo/Games/Maze.HC
 * reads `gr.text_base`, and RV's `gr` is a CGrMsGlbls whose only member is fp_draw_ms, so the
 * game took a load fault with nothing to point at.
 *
 * HOLYC_STRICT_MEMBERS=0 downgrades this to a warning, for working through a tree that has
 * leaned on the old behaviour. Default is a hard error: silence here is how a port hides the
 * fields it has not implemented yet. */
static void HostUnknownMember(Compiler *cc, CHashClass *cls, const char *name, char op) {
  const char *env = getenv("HOLYC_STRICT_MEMBERS");
  bool strict = !(env && env[0] == '0');
  const char *cname = (cls && cls->str) ? cls->str : "<anon>";
  if (strict) {
    char msg[256];
    snprintf(msg, sizeof msg, "No member '%s' in class '%s' (%s)", name, cname,
             op == '.' ? "." : "->");
    Error(cc, msg);
  } else {
    fprintf(stderr, "WARN: no member '%s' in class '%s' (%s)\n", name, cname,
            op == '.' ? "." : "->");
  }
}

static CMemberLst *HostMemberFind(CHashClass *cls, const char *name) {
  for (; cls; cls = cls->base_class) {
    for (CMemberLst *m = cls->member_lst; m; m = m->next)
      if (m->str && name && strcmp(m->str, name) == 0) return m;
  }
  return NULL;
}

// ----------------------------------------------------------------------------------------------
// IC GENERATION
// ----------------------------------------------------------------------------------------------

CIntermediateCode *ICNew(Compiler *cc, U8 opcode) {
  (void)cc;
#ifdef BARE_METAL
  extern void *parse_calloc(size_t n, size_t sz);
  CIntermediateCode *ic = parse_calloc(1, sizeof(CIntermediateCode));
#else
  CIntermediateCode *ic = calloc(1, sizeof(CIntermediateCode));
#endif
  if (!ic) {
    // Allocation failed!
    return NULL;
  }
  
  ic->ic_code = opcode;
  ic->ic_cnt = 0;
  ic->last = NULL;
  ic->next = NULL;
  
  // TempleOS ICNew does NOT auto-link! The caller must link it.
  // This allows manual control over IC chain construction.
  
  return ic;
}


void ICSetArg1(CIntermediateCode *ic, CICType type, I64 reg, I64 disp) {
  ic->arg1.type = type;
  ic->arg1.reg = reg;
  ic->arg1.disp = disp;
}

void ICSetArg2(CIntermediateCode *ic, CICType type, I64 reg, I64 disp) {
  ic->arg2.type = type;
  ic->arg2.reg = reg;
  ic->arg2.disp = disp;
}

void ICSetRes(CIntermediateCode *ic, CICType type, I64 reg, I64 disp) {
  ic->res.type = type;
  ic->res.reg = reg;
  ic->res.disp = disp;
}

// ----------------------------------------------------------------------------------------------
// SYMBOL TABLE
// ----------------------------------------------------------------------------------------------

Symbol *SymbolLookup(Compiler *cc, const char *name) {
  SymTable *st = cc->symtab;
  
  while (st) {
    Symbol *sym = st->symbols;
    while (sym) {
      if (strcmp(sym->name, name) == 0) {
        return sym;
      }
      sym = sym->next;
    }
    st = st->parent;
  }
  
  return NULL;
}

Symbol *SymbolDefine(Compiler *cc, const char *name, SymbolType type) {
  Symbol *sym = calloc(1, sizeof(Symbol));
  sym->name = strdup(name);
  sym->type = type;
  
  // Add to current scope
  sym->next = cc->symtab->symbols;
  cc->symtab->symbols = sym;
  
  return sym;
}

void SymTablePush(Compiler *cc) {
  SymTable *st = calloc(1, sizeof(SymTable));
  st->parent = cc->symtab;
  cc->symtab = st;
}

void SymTablePopTo(Compiler *cc, SymTable *scope);

void SymTablePop(Compiler *cc) {
  if (cc->symtab) {
    SymTable *st = cc->symtab;
    cc->symtab = st->parent;
    
    // Free symbols
    Symbol *sym = st->symbols;
    while (sym) {
      Symbol *next = sym->next;
      free(sym->name);
      free(sym);
      sym = next;
    }
    free(st);
  }
}

// Pop until `scope` is current again (function scopes: parameters must not outlive the function).
void SymTablePopTo(Compiler *cc, SymTable *scope) {
  while (cc->symtab && cc->symtab != scope) SymTablePop(cc);
}

static bool ParseConstDim(Compiler *cc, I64 *out);
static I64 CountAggregateElements(Compiler *cc);

// `T (*name)(params)` and `T (*name[N])(params)` / `T (*name[])(params)`. `out_arr_cnt` comes
// back 0 for the scalar form and the element count for a table; -1 asks the caller to size the
// table from its initializer.
static bool ParseFunctionPointerDeclarator(Compiler *cc, char **out_name, int *out_param_count,
                                           I64 *out_arr_cnt) {
  if (out_arr_cnt) *out_arr_cnt = 0;
  if (cc->lex.token != '(') {
    Error(cc, "Expected '(' for function pointer declarator");
    return false;
  }

  LexNext(cc);  // consume '('

  int pointer_depth = 0;
  while (cc->lex.token == '*') {
    pointer_depth++;
    LexNext(cc);
  }

  if (pointer_depth < 1) {
    Error(cc, "Expected '*' in function pointer declarator");
    return false;
  }

  if (cc->lex.token != TK_IDENT) {
    Error(cc, "Expected function pointer name");
    return false;
  }

  char *name = strdup(cc->lex.token_str);
  LexNext(cc);

  // `(*name[N])(…)`: a dispatch table of function pointers. The extent binds to the declarator,
  // inside the parens, which is why the array brackets are read here and not by the caller.
  if (cc->lex.token == '[') {
    I64 cnt = 0;
    LexNext(cc);
    if (cc->lex.token == ']') {
      cnt = -1;                                   // `[]`: sized by the initializer
    } else if (!ParseConstDim(cc, &cnt)) {
      free(name);
      return false;
    } else if (cnt <= 0) {
      free(name);
      Error(cc, "Function pointer array needs a positive extent");
      return false;
    }
    if (!LexExpect(cc, ']')) {
      free(name);
      return false;
    }
    if (cc->lex.token == '[') {
      free(name);
      Error(cc, "Multi-dimensional function pointer arrays are not supported");
      return false;
    }
    if (out_arr_cnt) *out_arr_cnt = cnt;
  }

  if (!LexExpect(cc, ')')) {
    free(name);
    return false;
  }

  if (!LexExpect(cc, '(')) {
    free(name);
    return false;
  }

  CHashClass *saved_class = cc->last_type_class;
  U8 saved_pointed_to = cc->last_pointed_to_type;

  int param_count = 0;

  if (cc->lex.token == ')') {
    LexNext(cc);
  } else {
    while (true) {
      if (cc->lex.token == TK_ELLIPSIS) {
        // Varargs - count as zero for now and consume ')'
        LexNext(cc);
        if (!LexExpect(cc, ')')) {
          free(name);
          return false;
        }
        param_count = 0;
        break;
      }

      U8 param_type = ParseType(cc);
      (void)param_type;  // Suppress unused warning – we only count params for now

      while (cc->lex.token == '*') {
        LexNext(cc);
      }

      if (cc->lex.token == TK_IDENT) {
        LexNext(cc);
      }

      if (cc->lex.token == '[') {
        LexNext(cc);
        if (cc->lex.token == TK_I64) {
          LexNext(cc);
        }
        if (!LexExpect(cc, ']')) {
          free(name);
          return false;
        }
      }

      if (cc->lex.token == '=') {   // default argument (`U8 *(*fp)(I64 flags=0)`): skip it
        int depth = 0;
        LexNext(cc);
        while (cc->lex.token != TK_EOF &&
               !(depth == 0 && (cc->lex.token == ',' || cc->lex.token == ';' || cc->lex.token == ')'))) {
          if (cc->lex.token == '(' || cc->lex.token == '[') depth++;
          else if (cc->lex.token == ')' || cc->lex.token == ']') depth--;
          LexNext(cc);
        }
      }

      param_count++;

      if (cc->lex.token == ',' || cc->lex.token == ';') {   // TempleOS sources also use ';' here
        LexNext(cc);
        continue;
      }

      if (!LexExpect(cc, ')')) {
        free(name);
        return false;
      }
      break;
    }
  }

  cc->last_type_class = saved_class;
  cc->last_pointed_to_type = saved_pointed_to;

  *out_name = name;
  *out_param_count = param_count;
  return true;
}

static bool EmitLocalFunctionPointerInitialization(Compiler *cc, Symbol *sym) {
  ICAdd(cc, IC_LEA, sym->offset, RT_I64);
  ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);

  if (!ParseExpression(cc)) {
    return false;
  }

  CIntermediateCode *ic = ICNew(cc, IC_ASSIGN);
  ic->res.type.raw_type = RT_I64;
  ic->res.type.mode = MDF_STK;
  ic->arg1_type_pointed_to = RT_I64;

  if (cc->ic_tail) cc->ic_tail->next = ic;
  else cc->ic_head = ic;
  cc->ic_tail = ic;

  cc->last_var_symbol = NULL;
  return true;
}

static bool ParseLocalAggregateInit(Compiler *cc, Symbol *sym, U8 var_type, CHashClass *decl_class);

static bool ParseLocalFunctionPointerDeclList(Compiler *cc, U8 return_type) {
  do {
    char *name = NULL;
    int parameter_count = 0;
    I64 arr_cnt = 0;
    if (!ParseFunctionPointerDeclarator(cc, &name, &parameter_count, &arr_cnt)) {
      return false;
    }

    if (arr_cnt < 0) {   // `T (*f[])(…) = {…}`: extent from the initializer
      arr_cnt = 0;
      if (cc->lex.token == '=') {
        LexPush(cc);
        LexNext(cc);
        if (cc->lex.token == '{') arr_cnt = CountAggregateElements(cc);
        LexPopRestore(cc);
      }
      if (arr_cnt <= 0) {
        free(name);
        Error(cc, "Cannot size `[]` function pointer table without a `{…}` initializer");
        return false;
      }
    }

    Symbol *sym = SymbolDefine(cc, name, SYM_VAR);
    sym->data_type = RT_I64;
    sym->size = arr_cnt > 0 ? 8 * arr_cnt : 8;
    sym->is_function_pointer = true;
    sym->function_return_type = return_type;
    sym->func_ptr_param_count = parameter_count;
    sym->pointed_to_type = RT_I64;
    sym->element_size = 8;
    if (arr_cnt > 0) {   // a table: `f[k]` subscripts it, `(*f[k])(…)` calls through it
      sym->is_array = true;
      sym->array_size = arr_cnt;
      sym->ndims = 1;
      sym->dim_stride[0] = 8;
    }

    int aligned_size = (sym->size + 7) & ~7;
    sym->offset = HOLY_LOCAL_MARKER(cc->locals_size);
    cc->locals_size += aligned_size;

    if (cc->lex.token == '=') {
      LexNext(cc);
      if (sym->is_array) {
        if (!ParseLocalAggregateInit(cc, sym, RT_I64, NULL)) {
          free(name);
          return false;
        }
      } else if (!EmitLocalFunctionPointerInitialization(cc, sym)) {
        free(name);
        return false;
      }
    }

    free(name);

    if (cc->lex.token == ',') {
      LexNext(cc);
      if (cc->lex.token != '(') {
        Error(cc, "Expected '(*' after ',' in function pointer declaration");
        return false;
      }
      continue;
    }
    break;
  } while (true);

  if (cc->lex.token == ';') {
    LexNext(cc);
  }

  return true;
}

static CHashGlblVar *CreateGlobalFunctionPointerEntry(Compiler *cc, const char *name, U8 return_type,
                                                      int param_count, I64 arr_cnt) {
  CHashGlblVar *tmpg = calloc(1, sizeof(CHashGlblVar));
  tmpg->str = strdup(name);
  tmpg->type = HTT_GLBL_VAR;
  tmpg->use_cnt = 0;
  tmpg->size = arr_cnt > 0 ? 8 * arr_cnt : 8;
  tmpg->flags = GVF_FUN;
  tmpg->is_function_pointer = true;
  tmpg->function_return_type = return_type;
  tmpg->func_ptr_param_count = param_count;
  tmpg->raw_type = RT_I64;
  tmpg->pointed_to_type = 0;
  tmpg->element_size = 8;
  if (arr_cnt > 0) {   // `T (*f[N])(…)`: a table, so `f[k]` subscripts by 8 bytes
    tmpg->flags |= GVF_ARRAY;
    tmpg->dim.cnt = tmpg->dim.total_cnt = arr_cnt;
    tmpg->ndims = 1;
    tmpg->dim_stride[0] = 8;
  }
  tmpg->data_addr = calloc(1, tmpg->size);
  HashAdd((CHashEntry*)tmpg, cc->hash_table);
  return tmpg;
}

// One slot of a function pointer table / a scalar function pointer: `&Name`, `Name`, or 0.
// A function's address is only known once the unit is laid out, so `&Name` is a run-time store
// into the global's data (the entry chunk in AOT, right now in the REPL) rather than data bytes.
static bool InitGlobalFunctionPointerSlot(Compiler *cc, CHashGlblVar *g, I64 byte_off) {
  if (cc->lex.token == '&') LexNext(cc);
  if (cc->lex.token == TK_IDENT) {
    CHashEntry *fn_entry = HashFind(cc->lex.token_str, cc->hash_table, HTT_FUN);
    if (!fn_entry || !(fn_entry->type & HTT_FUN)) {
      Error(cc, "Expected function name in initialization");
      return false;
    }
    CHashFun *fn = (CHashFun *)fn_entry;
    LexNext(cc);
    ICAdd(cc, IC_IMM_I64, (I64)g->data_addr + byte_off, RT_I64);
    cc->ic_tail->ic_flags = ICF_GLBL_ADDR;
    if (!EmitFnAddress(cc, fn)) return false;
    CIntermediateCode *aic = ICNew(cc, IC_ASSIGN);
    aic->res.type.raw_type = RT_I64;
    aic->res.type.mode = MDF_STK;
    aic->arg1_type_pointed_to = RT_I64;
    if (cc->ic_tail) cc->ic_tail->next = aic; else cc->ic_head = aic;
    cc->ic_tail = aic;
    ICAdd(cc, IC_END_EXP, 0, RT_I64);
    return true;
  }
  if (cc->lex.token == TK_I64) {
    *(I64 *)((U8 *)g->data_addr + byte_off) = cc->lex.token_i64;
    LexNext(cc);
    return true;
  }
  Error(cc, "Unsupported initializer for function pointer");
  return false;
}

static bool InitializeGlobalFunctionPointer(Compiler *cc, CHashGlblVar *global_entry) {
  if (cc->lex.token != '=') {
    return true;
  }

  LexNext(cc);

  if (!(global_entry->flags & GVF_ARRAY))
    return InitGlobalFunctionPointerSlot(cc, global_entry, 0);

  // `T (*f[N])(…) = {&A, &B, …}` — HolyC also allows the brace-less `= &A, &B;` form here,
  // since a function pointer table's declarator cannot be confused with a declarator list.
  bool braced = (cc->lex.token == '{');
  if (braced) LexNext(cc);
  I64 total = global_entry->dim.total_cnt > 0 ? global_entry->dim.total_cnt : 1;
  I64 idx = 0;
  while (cc->lex.token != (braced ? '}' : ';') && cc->lex.token != TK_EOF) {
    if (idx >= total) { Error(cc, "Too many initializers"); return false; }
    if (!InitGlobalFunctionPointerSlot(cc, global_entry, idx * 8)) return false;
    idx++;
    if (cc->lex.token == ',') LexNext(cc); else break;
  }
  // Slots the list omitted stay 0 — `data_addr` is calloc'd.
  return braced ? LexExpect(cc, '}') : true;
}

static bool ParseGlobalFunctionPointerDeclList(Compiler *cc, U8 return_type) {
  do {
    char *name = NULL;
    int parameter_count = 0;
    I64 arr_cnt = 0;
    if (!ParseFunctionPointerDeclarator(cc, &name, &parameter_count, &arr_cnt)) {
      return false;
    }

    if (arr_cnt < 0) {   // `T (*f[])(…) = {…}`: extent from the initializer
      arr_cnt = 0;
      if (cc->lex.token == '=') {
        LexPush(cc);
        LexNext(cc);
        if (cc->lex.token == '{') arr_cnt = CountAggregateElements(cc);
        LexPopRestore(cc);
      }
      if (arr_cnt <= 0) {
        free(name);
        Error(cc, "Cannot size `[]` function pointer table without a `{…}` initializer");
        return false;
      }
    }

    CHashGlblVar *entry = CreateGlobalFunctionPointerEntry(cc, name, return_type, parameter_count, arr_cnt);
    if (cc->lex.token == '=') {
      if (!InitializeGlobalFunctionPointer(cc, entry)) {
        free(name);
        return false;
      }
    }

    free(name);

    if (cc->lex.token == ',') {
      LexNext(cc);
      if (cc->lex.token != '(') {
        Error(cc, "Expected '(*' after ',' in function pointer declaration");
        return false;
      }
      continue;
    }
    break;
  } while (true);

  if (cc->lex.token == ';') {
    LexNext(cc);
  } else {
    Error(cc, "Expected ';' after function pointer declaration");
    return false;
  }

  return true;
}

// ----------------------------------------------------------------------------------------------
// LABELS
// ----------------------------------------------------------------------------------------------

CLabel *LabelNew(Compiler *cc, const char *name) {
  CLabel *lb = calloc(1, sizeof(CLabel));
  lb->name = name ? strdup(name) : NULL;
  lb->addr = -1;
  lb->defined = false;
  
  // Add to list
  lb->next = cc->labels;
  cc->labels = lb;
  
  return lb;
}

// True if lb was created in the current compilation unit (cc->labels is reset per unit:
// once per AOT file, once per REPL statement). Labels from an earlier unit carry offsets
// into a different code buffer, so PC-relative jal to them is invalid.
Bool LabelInUnit(Compiler *cc, CLabel *lb) {
  for (CLabel *p = cc->labels; p; p = p->next)
    if (p == lb) return true;
  return false;
}

// A scalar-typed union (`U16i union U16`, `U32i union U32`, …) records its base type as RT_I64
// but keeps a sub-word size; trust the size for the element load/store width so `arr[i]`
// accesses `size` bytes, not 8. (The kernel declares its date tables and char bitmaps this way.)
static U8 ScalarTypeForSize(U8 t, I64 size) {
  if (t == RT_I64 && (size == 1 || size == 2 || size == 4))
    return size == 1 ? RT_U8 : size == 2 ? RT_U16 : RT_U32;
  return t;
}

static void EnsureLvalueAddressPushed(Compiler *cc);
static bool ParseConstDim(Compiler *cc, I64 *out);

// DEREF loads through a0 without popping the slot a pushing producer (IC_ADD / IC_PUSH_ARG /
// IC_IMM_I64) left on the eval stack; drop it first so [ ] . -> reads leave exactly one value.
static void DerefDroppingAddressSlot(Compiler *cc) {
  CIntermediateCode *t = cc->ic_tail;
  // Every binary producer pushes its result, not just IC_ADD: `(p - 128)->m` and `(b + i * n)->m`
  // left the computed address on the eval stack. Straight-line code still ran (the emitter's
  // depth counter tracked the leak, and IC_END_EXP popped it), but a branch that skipped the
  // leaked pushes reached the join with a different real depth — IC_END_EXP then popped past
  // the frame base and the next push overwrote the saved ra.
  if (t && (t->ic_code == IC_ADD || t->ic_code == IC_SUB || t->ic_code == IC_MUL ||
            t->ic_code == IC_DIV || t->ic_code == IC_MOD ||
            t->ic_code == IC_AND || t->ic_code == IC_OR  || t->ic_code == IC_XOR ||
            t->ic_code == IC_SHL || t->ic_code == IC_SHR || t->ic_code == IC_USHR ||
            t->ic_code == IC_PUSH_ARG || t->ic_code == IC_IMM_I64 || t->ic_code == IC_DEREF))
    ICAdd(cc, IC_EVAL_DROP, 8, RT_I64);   // IC_DEREF: `p->m` at offset 0 — the pointer value's slot
  ICAdd(cc, IC_DEREF, 0, RT_I64);
}

// Record the argument count on the call IC just emitted (the compiler reads ic_flags there; a
// single Compiler-wide counter would be clobbered by nested calls like Print("%d", Add(1, 2))).
static void SetCallArgCnt(Compiler *cc, I64 argc) {
  // Stamp only the just-emitted call IC (the tail). Walking back to the *last* call in the whole
  // list clobbered an earlier sibling call: `(*p->put_s)(st)` then `(*p->put_key)(ch,0)` in an
  // if/else made put_key's count (2) land on put_s's already-emitted CALL_INDIRECT, so put_s
  // loaded two args. A pre-emit SetCallArgCnt (tail is IC_DEREF, not a call) is now a safe no-op.
  CIntermediateCode *ic = cc->ic_tail;
  if (ic && (ic->ic_code == IC_CALL || ic->ic_code == IC_CALL_INDIRECT || ic->ic_code == IC_CALL_INDIRECT2))
    ic->ic_flags = argc;
}

// Emit the call itself for `fn` (arguments already on the eval stack): PC-relative jal within
// the unit, else through the function's exe_addr slot; runtime externs go through their import
// slot (a global: absolute in the REPL, data-section relative in AOT).
static bool EmitCallDispatch(Compiler *cc, CHashFun *fn) {
  if (fn->is_extern && fn->import_var) {
    ICAdd(cc, IC_CALL_INDIRECT2, (I64)fn->import_var->data_addr, RT_I64);
    cc->ic_tail->ic_class = fn->import_var;
    fn->import_var->use_cnt++;
    return true;
  }
  if (cc->current_function_entry_label && fn == cc->last_compiled_func) {
    ICAdd(cc, IC_CALL, (I64)cc->current_function_entry_label, RT_I64);
  } else if (fn->entry_label && LabelInUnit(cc, (CLabel *)fn->entry_label)) {
    ICAdd(cc, IC_CALL, (I64)fn->entry_label, RT_I64);
  } else {
    if (!fn->exe_addr) { Error(cc, "Function declared but not defined"); return false; }
    ICAdd(cc, IC_CALL_INDIRECT2, (I64)&fn->exe_addr, RT_I64);
  }
  return true;
}

// A function's address as a value (`&Fn`, function-pointer initializers): the code address —
// PC-relative to its label in this unit, its exe_addr from an earlier REPL unit, or loaded from
// the import slot for a runtime/extern function.
static bool EmitFnAddress(Compiler *cc, CHashFun *fn) {
  if (fn->is_extern && fn->import_var) {
    ICAdd(cc, IC_IMM_I64, (I64)fn->import_var->data_addr, RT_I64);
    cc->ic_tail->ic_flags = ICF_GLBL_ADDR;
    ICAdd(cc, IC_EVAL_DROP, 8, RT_I64);
    ICAdd(cc, IC_DEREF, 0, RT_I64);
    // This DEREF *is* the value (`&Fn` = the slot's contents). The unary-& path must not
    // retract it like a variable's auto-deref: that left the slot address, and a call
    // through the pointer jumped into the import table (guest &RVF64Sin, `fp=&StrLen`).
    cc->fn_addr_slot_deref = cc->ic_tail;
    fn->import_var->use_cnt++;   // address-only use still needs the slot in the import directory
    return true;
  }
  if (cc->current_function_entry_label && fn == cc->last_compiled_func) {
    ICAdd(cc, IC_FN_ADDR, (I64)cc->current_function_entry_label, RT_I64);
    return true;
  }
  if (fn->entry_label && LabelInUnit(cc, (CLabel *)fn->entry_label)) {
    ICAdd(cc, IC_FN_ADDR, (I64)fn->entry_label, RT_I64);
    return true;
  }
  if (fn->exe_addr) {
    // Immediate code address — must NOT end in IC_DEREF: EnsureLvalueAddressPushed after
    // `&Fn` retracts a trailing DEREF and would leave &exe_addr (the slot) instead.
    ICAdd(cc, IC_IMM_I64, fn->exe_addr, RT_I64);
    return true;
  }
  Error(cc, "Function declared but not defined");
  return false;
}

// Emit a call to a named function whose `argc` arguments are already on the eval stack.
static bool EmitCallByName(Compiler *cc, const char *name, I64 argc) {
  CHashEntry *e = cc->hash_table ? HashFind(name, cc->hash_table, HTT_FUN) : NULL;
  if (!e || !(e->type & HTT_FUN)) {
    Error(cc, "Unknown function (Print is not available in this build)");
    return false;
  }
  CHashFun *fn = (CHashFun *)e;
  if (!EmitCallDispatch(cc, fn)) return false;
  cc->last_call_arg_cnt = argc;
  SetCallArgCnt(cc, argc);
  return true;
}

CLabel *LabelFind(Compiler *cc, const char *name) {
  CLabel *lb = cc->labels;
  while (lb) {
    if (lb->name && strcmp(lb->name, name) == 0) {
      return lb;
    }
    lb = lb->next;
  }
  return NULL;
}

// ----------------------------------------------------------------------------------------------
// PARSER - EXPRESSIONS
// ----------------------------------------------------------------------------------------------

// Forward declarations for expression parsing
static bool ParsePrimary(Compiler *cc);
static bool ParsePostfix(Compiler *cc);
static I64 CEOr(Compiler *cc, I64 dollar, bool *ok);
static bool ParseUnary(Compiler *cc);
static bool ParseGlobalVariable(Compiler *cc, U8 var_type, char *var_name);
static bool ParseEnumDefinitionBody(Compiler *cc, const char *enum_name, bool register_type);
bool ParseEnum(Compiler *cc);
// A parameter default, at the '=' token. Either a constant (`=0x80`, `=1<<JOBf_X`) or source text
// kept verbatim, because HolyC evaluates a non-constant default at each CALL SITE in the caller's
// context (`=gr.dc`, `=&TOSLinkCvt1`). Shared by plain and function-pointer parameters.
static void ParseParamDefault(Compiler *cc, U8 param_type,
                              bool *out_has_default, I64 *out_default_val, char **out_default_src) {
  *out_has_default = false;
  *out_default_val = 0;
  *out_default_src = NULL;
  if (cc->lex.token != '=') return;
  const char *dflt_start = cc->lex.ptr;   // the default's source text begins after '='
  LexNext(cc);
  if (cc->lex.token == KW_LASTCLASS) {    // `lastclass` → 0
    *out_has_default = true;
    LexNext(cc);
    return;
  }
  bool okc = false;
  I64 v = 0;
  if (cc->lex.token == TK_I64 || cc->lex.token == '-' || cc->lex.token == '(' || cc->lex.token == '~' ||
      (cc->lex.token == TK_IDENT && cc->lex.hash_entry && (cc->lex.hash_entry->type & HTT_ENUM))) {
    LexPush(cc);   // a failed constant evaluation must not leave tokens consumed
    okc = true;
    v = CEOr(cc, 0, &okc);
    if (okc && cc->lex.token != ',' && cc->lex.token != ')' && cc->lex.token != ';') okc = false;
    if (okc) LexPopNoRestore(cc); else LexPopRestore(cc);
  }
  *out_has_default = true;
  if (okc && param_type != RT_F64) {
    *out_default_val = v;
    return;
  }
  int paren_depth = 0;
  while (cc->lex.token != TK_EOF &&
         !(paren_depth == 0 && (cc->lex.token == ',' || cc->lex.token == ')' || cc->lex.token == ';'))) {
    if (cc->lex.token == '(' || cc->lex.token == '[') paren_depth++;
    else if (cc->lex.token == ')' || cc->lex.token == ']') paren_depth--;
    LexNext(cc);
  }
  const char *dflt_end = cc->lex.ptr - 1;   // the one-char terminator was just lexed
  if (dflt_end > dflt_start) {
    size_t n = (size_t)(dflt_end - dflt_start);
    *out_default_src = malloc(n + 1);
    memcpy(*out_default_src, dflt_start, n);
    (*out_default_src)[n] = 0;
  }
}

static bool ParseFunctionPointerDeclarator(Compiler *cc, char **out_name, int *out_param_count,
                                           I64 *out_arr_cnt);
static bool ParseLocalFunctionPointerDeclList(Compiler *cc, U8 return_type);
static bool ParseGlobalFunctionPointerDeclList(Compiler *cc, U8 return_type);

static I64 PrimitiveTypeSize(U8 type) {
  switch (type) {
    case RT_I0: case RT_U0: return 0;
    case RT_I8: case RT_U8: return 1;
    case RT_I16: case RT_U16: return 2;
    case RT_I32: case RT_U32: return 4;
    case RT_I64: case RT_U64: case RT_F64: return 8;
    default: return 8;
  }
}

static bool IsTypeStartToken(Compiler *cc) {
  switch (cc->lex.token) {
    case KW_I0: case KW_U0:
    case KW_I8: case KW_U8:
    case KW_I16: case KW_U16:
    case KW_I32: case KW_U32:
    case KW_I64: case KW_U64:
    case KW_F64:
    case KW_CLASS:
    case KW_ENUM:
      return true;
    default:
      break;
  }

  if (cc->lex.token == TK_IDENT && cc->lex.hash_entry &&
      (cc->lex.hash_entry->type & (HTT_CLASS | HTT_INTERNAL_TYPE))) {
    return true;
  }

  return false;
}

static U8 ParseType(Compiler *cc) {
  U8 type = RT_I64;  // Default
  cc->last_type_class = NULL;
  
  // Check if current token is a type (from hash table or keyword)
  if (cc->lex.token == TK_IDENT && cc->lex.hash_entry) {
    // Check if it's a class/internal type in hash table
    if (cc->lex.hash_entry->type & (HTT_CLASS | HTT_INTERNAL_TYPE)) {
      CHashClass *cls = (CHashClass*)cc->lex.hash_entry;
      type = cls->raw_type;
      cc->last_type_class = (cls->type & HTT_CLASS) ? cls : NULL;
      LexNext(cc);
    } else {
      Error(cc, "Expected type");
      return RT_I64;
    }
  } else {
    // Old keyword-based type checking (shouldn't happen with hash table)
    switch (cc->lex.token) {
      case KW_I0: case KW_U0: type = RT_I0; LexNext(cc); break;
      case KW_I8: type = RT_I8; LexNext(cc); break;
      case KW_U8: type = RT_U8; LexNext(cc); break;
      case KW_I16: type = RT_I16; LexNext(cc); break;
      case KW_U16: type = RT_U16; LexNext(cc); break;
      case KW_I32: type = RT_I32; LexNext(cc); break;
      case KW_U32: type = RT_U32; LexNext(cc); break;
      case KW_I64: type = RT_I64; LexNext(cc); break;
      case KW_U64: type = RT_U64; LexNext(cc); break;
      case KW_F64: type = RT_F64; LexNext(cc); break;
      case KW_ENUM:
        {
          LexNext(cc);

          char *enum_name = NULL;
          bool have_name = false;
          if (cc->lex.token == TK_IDENT) {
            enum_name = strdup(cc->lex.token_str);
            have_name = true;
            LexNext(cc);
          }

          if (cc->lex.token == '{') {
            bool register_type = have_name;
            if (!ParseEnumDefinitionBody(cc, enum_name, register_type)) {
              if (enum_name) free(enum_name);
              return RT_I64;
            }

            if (have_name) {
              CHashEntry *enum_type = HashFind(enum_name, cc->hash_table, HTT_CLASS | HTT_INTERNAL_TYPE);
              if (enum_type && (enum_type->type & (HTT_CLASS | HTT_INTERNAL_TYPE))) {
                CHashClass *cls = (CHashClass*)enum_type;
                type = cls->raw_type;
              } else {
                type = RT_I64;
              }
            } else {
              type = RT_I64;
            }
          } else if (have_name) {
            CHashEntry *enum_type = HashFind(enum_name, cc->hash_table, HTT_CLASS | HTT_INTERNAL_TYPE);
            if (enum_type && (enum_type->type & (HTT_CLASS | HTT_INTERNAL_TYPE))) {
              CHashClass *cls = (CHashClass*)enum_type;
              type = cls->raw_type;
            } else {
              type = RT_I64;
            }
          } else {
            Error(cc, "Expected enum declarator");
            if (enum_name) free(enum_name);
            return RT_I64;
          }

          if (enum_name) free(enum_name);
        }
        break;
      default:
        Error(cc, "Expected type");
        return RT_I64;
    }
  }
  
  // Save base type before pointer stars
  U8 base_type = type;
  
  // Handle pointer stars
  int ptr_count = 0;
  while (cc->lex.token == '*') {
    ptr_count++;
    LexNext(cc);
  }
  
  // Store pointed-to type in compiler context for next variable declaration
  if (ptr_count > 0) {
    cc->last_pointed_to_type = base_type;
    cc->last_ptr_depth = (U8)ptr_count;
    type = RT_I64;  // Pointers are 64-bit addresses
    // last_type_class stays: a pointer-to-class variable needs its class for p->member.
  } else {
    cc->last_pointed_to_type = 0;  // Not a pointer
    cc->last_ptr_depth = 0;
  }
  
  return type;
}

// Apply a cast to the value on the eval stack (prefix `(T)x` and HolyC postfix `x(T)`).
static void ApplyCast(Compiler *cc, U8 cast_type, bool cast_ptr, CHashClass *cls) {
  // HolyC casts relabel; they never convert ("To typecast int or F64, use ToI64()/ToF64()",
  // Doc/HolyC.DD). So `0x7FF0000000000000(F64)` is inf and `i(F64)` reads i's bits as a double.
  // Sub-word integer casts narrow (mask / sign-extend), as x86 MOVZX/MOVSX would.
  // A postfix cast on a deref lvalue reinterprets the memory location's WIDTH: `b[i](I64)` is
  // `*(I64*)&b[i]` — 8 bytes, not b[i]'s declared U8. Retype the pending DEREF (captured before
  // any sub-word mask/shift below changes ic_tail) so a following store — and the load itself —
  // uses the cast's width, not the element's. Without this, `tmp_buf[0](I64)=ch` (StrPrint's %c)
  // stored a single byte and left the previous specifier's bytes trailing.
  CIntermediateCode *cast_deref = (!cast_ptr && cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) ? cc->ic_tail : NULL;
  if (cast_deref) cast_deref->arg1_type_pointed_to = cast_type;
  if (!cast_ptr && cc->ic_tail && cc->ic_tail->ic_code == IC_IMM_I64 && cast_type == RT_F64) cc->ic_tail->ic_code = IC_IMM_F64;
  if (!cast_ptr && cc->ic_tail && cc->ic_tail->ic_code == IC_IMM_F64 && cast_type != RT_F64) cc->ic_tail->ic_code = IC_IMM_I64;
  if (cast_ptr) {
    cc->last_expr_type = RT_I64;
  } else if (cast_type == RT_F64) {
    cc->last_expr_type = RT_F64;
  } else {
    cc->last_expr_type = (cast_type == RT_U8 || cast_type == RT_U16 || cast_type == RT_U32 || cast_type == RT_U64) ? RT_U64 : RT_I64;
    I64 bits = (cast_type == RT_I8 || cast_type == RT_U8) ? 8 :
               (cast_type == RT_I16 || cast_type == RT_U16) ? 16 :
               (cast_type == RT_I32 || cast_type == RT_U32) ? 32 : 0;
    if (bits) {
      bool is_unsigned = (cast_type == RT_U8 || cast_type == RT_U16 || cast_type == RT_U32);
      if (is_unsigned) {
        ICAdd(cc, IC_IMM_I64, (I64)((1ULL << bits) - 1), RT_I64);
        ICAdd(cc, IC_AND, 0, RT_I64);
      } else {
        ICAdd(cc, IC_IMM_I64, 64 - bits, RT_I64);
        ICAdd(cc, IC_SHL, 0, RT_I64);
        ICAdd(cc, IC_IMM_I64, 64 - bits, RT_I64);
        ICAdd(cc, IC_SHR, 0, RT_I64);   // arithmetic shift: sign-extends
      }
    }
  }
  cc->cast_elem_type = cast_ptr ? cast_type : 0;
  cc->cast_elem_class = cast_ptr ? cls : NULL;
  // The cast also overrides the expression's POINTER identity: `*(U32 *)(b+4)` must deref by the
  // cast width, but pointer arithmetic (b+4) leaves expr_ptr_depth/expr_pointee set to b's own
  // pointee (U8), and the deref-type chain consults those before the cast. A pointer cast makes
  // this a pointer-to-cast_type; a value cast makes it not a pointer at all.
  // Multi-star casts keep their depth: `*(U8 **)` loads an 8-byte U8*, not a U8. Collapsing to
  // depth 1 made host-slot / nested-pointer loads look like they needed an asm trampoline.
  cc->expr_ptr_depth = cast_ptr ? (cc->last_ptr_depth ? cc->last_ptr_depth : 1) : 0;
  cc->expr_pointee = cast_ptr ? cast_type : 0;
  if (cast_ptr && cls && (cls->type & HTT_CLASS) && !(cls->type & HTT_INTERNAL_TYPE)) cc->last_expr_class = cls;
}

// `I64 reg RSI *dst, reg R13 c, noreg x`: register-allocation hints in declarators (x86 register
// names) — skipped here.
static void SkipRegQualifier(Compiler *cc) {
  if (cc->lex.token != KW_REG && cc->lex.token != KW_NOREG) return;
  LexNext(cc);
  if (cc->lex.token == TK_IDENT && (!cc->lex.hash_entry || (cc->lex.hash_entry->type & HTT_REG))) {   // an x86 register name, if a declarator follows it
    LexPush(cc);
    LexNext(cc);
    bool decl_follows = (cc->lex.token == '*' || cc->lex.token == TK_IDENT);
    LexPopRestore(cc);
    if (decl_follows) LexNext(cc);
  }
}

static void RewriteForwardImportCalls(Compiler *cc, CHashFun *fn);   // defined below

// Declared (or merely called) but not defined here: calls go through an import slot the
// loader fills by name (`__imp_<name>`).
void MakeImportSlot(Compiler *cc, CHashFun *f) {
  // `_extern _LABEL type Name(...)`: the declaration is an ALIAS for an asm{} label, not a
  // reference to something outside the image. An exported `_LABEL::` is already a first-class
  // CHashFun with entry_label set and is_extern FALSE (see the `::` handling in the asm block
  // parser), so bind straight to it. Without this the name became __imp_<Name>, the loader
  // filled it with a stub returning 0, and every stock asm routine silently answered 0 —
  // Demo/Asm/DivByHand.HC compiled, linked, reported L1-OK and divided everything to zero.
  if (cc->pending_link_symbol && cc->hash_table) {
    CHashEntry *e = HashFind(cc->pending_link_symbol, cc->hash_table, HTT_FUN);
    if (e && (e->type & HTT_FUN)) {
      CHashFun *tgt = (CHashFun *)e;
      if (tgt != f && tgt->entry_label && tgt->entry_label_defined) {
        f->entry_label = tgt->entry_label;
        f->entry_label_defined = 1;
        f->is_extern = FALSE;
        RewriteForwardImportCalls(cc, f);
        free(cc->pending_link_symbol);
        cc->pending_link_symbol = NULL;
        return;
      }
    }
  }
  CHashGlblVar *slot = calloc(1, sizeof(CHashGlblVar));
  char nm[80]; int k = 0;
  const char *pre = "__imp_";
  while (*pre) nm[k++] = *pre++;
  for (const char *q = f->str; *q && k < 78; q++) nm[k++] = *q;
  nm[k] = 0;
  slot->str = strdup(nm);
  slot->type = HTT_GLBL_VAR;
  slot->size = 8; slot->element_size = 8; slot->raw_type = RT_I64;
  slot->data_addr = calloc(1, 8);
  HashAdd((CHashEntry *)slot, cc->hash_table);
  f->import_var = slot;
  f->is_extern = TRUE;
}

// When a body arrives for a function previously only `extern`/forward-called, rewrite any
// already-emitted IC_CALL_INDIRECT2 through its `__imp_*` slot into a direct IC_CALL to the
// entry label. Without this, host AOT can leave the slot at 0 (self-resolve miss) and the
// call hangs — seen specifically for OptPass4 under Compiler_RV_Body include order.
static void RewriteICImportCalls(CIntermediateCode *head, CHashFun *fn) {
  if (!head || !fn || !fn->import_var || !fn->entry_label) return;
  I64 slot_addr = (I64)fn->import_var->data_addr;
  for (CIntermediateCode *ic = head; ic; ic = ic->next) {
    if (ic->ic_code == IC_CALL_INDIRECT2 &&
	(ic->ic_data == slot_addr || ic->ic_class == (CHashClass *)fn->import_var)) {
      ic->ic_code = IC_CALL;
      ic->ic_data = (I64)fn->entry_label;
      ic->ic_class = NULL;
    }
  }
}

static void RewriteForwardImportCalls(Compiler *cc, CHashFun *fn) {
  if (!cc || !fn || !fn->import_var || !fn->entry_label) return;
  RewriteICImportCalls(cc->ic_head, fn);
  RewriteICImportCalls(cc->aot_main_head, fn);
  for (AOTFnICChunk *ch = cc->aot_fn_ic_head; ch; ch = ch->next)
    RewriteICImportCalls(ch->head, fn);
  fn->import_var->self_resolved = TRUE; // keep out of loader import directory
  if (fn->import_var->use_cnt > 0) fn->import_var->use_cnt = 0;
}

// Push parameter i's default: a constant, or its source expression read again here — in the
// caller's context, as HolyC does (`CDC *dc=gr.dc`). The current token is held back meanwhile.
static bool EmitDefaultArg(Compiler *cc, CHashFun *fn, I64 i) {
  bool want_f64 = fn->param_typed && i < 16 && ((fn->param_f64_mask >> i) & 1);
  if (i < 16 && fn->param_default_src[i]) {
    size_t n = strlen(fn->param_default_src[i]);
    char *text = malloc(n + 3);
    memcpy(text, fn->param_default_src[i], n);
    text[n] = '\n'; text[n + 1] = ')'; text[n + 2] = 0;   // ')' ends the expression, then the held token returns
    LexPushStringPending(cc, text);
    free(text);
    if (!ParseAssignment(cc)) {
      LexAbandonPendingString(cc); return false;
    }
    if (!LexExpect(cc, ')')) { Error(cc, "Bad default argument expression"); LexAbandonPendingString(cc); return false; }
    if (want_f64 && cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
    else if (!want_f64 && cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64);
    cc->last_var_symbol = NULL;
    cc->last_global_var = NULL;
    return true;
  }
  ICAdd(cc, IC_IMM_I64, i < 16 ? fn->param_default[i] : 0, RT_I64);
  if (want_f64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
  return true;
}

// `IsDbgMode`, `ProgressBarsRst;`: HolyC calls a function named without parentheses.
// A call's result carries the callee's return pointer-ness, so ParseUnary's deref can
// size `*Fn()` from the pointee (its expr_ptr_depth arm) instead of falling back to
// RT_I64 and loading 8 bytes out of a 4-byte slot.
static void SetCallResultPtr(Compiler *cc, CHashFun *func) {
  if (func && func->ptr_stars_cnt > 0 && func->ret_pointed_to) {
    cc->expr_ptr_depth = (U8)func->ptr_stars_cnt;
    cc->expr_pointee = func->ret_pointed_to;
    cc->call_ptr_just_loaded = true;
  } else {
    cc->expr_ptr_depth = 0;
  }
}

static bool EmitNoParenCall(Compiler *cc, CHashFun *func) {
  ICAdd(cc, IC_CALL_START, 0, RT_I64);
  int arg_count = 0;
  I64 fixed = func->is_varargs ? func->param_cnt - 2 : func->param_cnt;
  while (arg_count < fixed && arg_count < 16 && func->param_has_default[arg_count]) {
    if (!EmitDefaultArg(cc, func, arg_count)) return false;
    ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
    arg_count++;
  }
  if (arg_count < fixed) { Error(cc, "Too few arguments in call"); return false; }
  if (func->is_varargs) {
    ICAdd(cc, IC_IMM_I64, 0, RT_I64); ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
    ICAdd(cc, IC_IMM_I64, 0, RT_I64); ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
    arg_count += 2;
  }
  if (!EmitCallDispatch(cc, func)) return false;
  cc->call_ret_type = (U8)func->raw_type;
  cc->last_call_arg_cnt = arg_count;
  SetCallArgCnt(cc, arg_count);
  cc->last_var_symbol = NULL;
  cc->last_expr_type = (cc->call_ret_type == RT_F64) ? RT_F64 : (cc->call_ret_type == RT_I0 || cc->call_ret_type == RT_U0) ? RT_I0 : RT_I64;
  cc->last_global_var = NULL;
  cc->last_member = NULL;
  // The call result IS the callee's return type, not an argument's: carry a pointer
  // return through so `*Fn()` derefs at the pointee's width.
  SetCallResultPtr(cc, func);
  ICAdd(cc, IC_CALL_END, 0, RT_I64);
  return true;
}

static bool ParsePrimary(Compiler *cc) {
  cc->var_just_loaded = false;
  cc->global_just_loaded = false;
  cc->call_ptr_just_loaded = false; cc->str_lit_just_loaded = false;
  bool addr_of = cc->addr_of_ident;
  cc->addr_of_ident = false;
  // Default: no global variable context until we identify one
  cc->last_global_var = NULL;
  // sizeof operator
  if (cc->lex.token == KW_SIZEOF) {
    LexNext(cc);

    bool had_paren = false;
    if (cc->lex.token == '(') {
      LexNext(cc);
      had_paren = true;
    }

    I64 size = 0;
    bool computed = false;

    if (had_paren && IsTypeStartToken(cc)) {
      U8 type = ParseType(cc);
      CHashClass *type_class = cc->last_type_class;
      // ParseType leaves the class in last_type_class for `Class *` too (p->member needs it), so
      // the star count has to be honoured here or sizeof(CDocEntry *) answers sizeof(CDocEntry).
      bool is_ptr = cc->last_ptr_depth > 0;
      I64 msize = -1;
      while (cc->lex.token == '.' && type_class) {   // sizeof(Class.member)
        LexNext(cc);
        CMemberLst *m = type_class->member_lst;
        while (m && !(cc->lex.token_str && strcmp(m->str, cc->lex.token_str) == 0)) m = m->next;
        if (!m) {
          Error(cc, "sizeof: unknown member"); return false;
        }
        msize = m->size;
        type_class = m->member_class;
        LexNext(cc);
      }

      if (!LexExpect(cc, ')')) return false;

      if (msize >= 0) {
        size = msize;
      } else if (is_ptr) {
        size = 8;
      } else if (type_class && type_class->size > 0) {
        size = type_class->size;
      } else {
        size = PrimitiveTypeSize(type);
      }
      computed = true;
    } else if (cc->lex.token == TK_IDENT && (!had_paren || !IsTypeStartToken(cc))) {
      char *name = strdup(cc->lex.token_str);
      if (!name) return false;
      LexNext(cc);

      Symbol *sym = SymbolLookup(cc, name);
      CHashClass *szcls = NULL;   // for `sizeof(var.member)`
      if (sym) {
        if (sym->is_array && sym->array_size >= 0 && sym->element_size > 0) {
          size = sym->array_size * sym->element_size;
        } else if (sym->size > 0) {
          size = sym->size;
        } else {
          size = PrimitiveTypeSize(sym->data_type);
        }
        szcls = (CHashClass *)sym->extra;
        computed = true;
      } else {
        CHashEntry *global_entry = HashFind(name, cc->hash_table, HTT_GLBL_VAR);
        if (global_entry && (global_entry->type & HTT_GLBL_VAR)) {
          CHashGlblVar *gv = (CHashGlblVar*)global_entry;
          if (gv->size > 0) {
            size = gv->size;
          } else if (gv->var_class && gv->var_class->size > 0) {
            size = gv->var_class->size;
          } else {
            size = PrimitiveTypeSize(gv->raw_type);
          }
          szcls = gv->var_class;
          computed = true;
        } else {
          Error(cc, "Unknown identifier in sizeof");
          free(name);
          return false;
        }
      }
      while (cc->lex.token == '.' && szcls) {   // sizeof(doldoc.dft_de_flags)
        LexNext(cc);
        CMemberLst *m = szcls->member_lst;
        while (m && !(cc->lex.token_str && strcmp(m->str, cc->lex.token_str) == 0)) m = m->next;
        if (!m) { Error(cc, "sizeof: unknown member"); free(name); return false; }
        size = m->size;
        szcls = m->member_class;
        LexNext(cc);
      }

      free(name);

      if (had_paren) {
        if (!LexExpect(cc, ')')) return false;
      }
    } else if (had_paren) {
      Error(cc, "Unsupported operand to sizeof");
      return false;
    } else {
      Error(cc, "Expected '(' after sizeof");
      return false;
    }

    if (!computed) {
      Error(cc, "Failed to compute sizeof operand");
      return false;
    }

    ICAdd(cc, IC_IMM_I64, size, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_I64) {
    cc->last_expr_type = RT_I64;
    // Integer literal
    ICAdd(cc, IC_IMM_I64, cc->lex.token_i64, RT_I64);
    LexNext(cc);
    return true;
  }
  
  if (cc->lex.token == TK_F64) {
    // Float literal - store as I64 bit pattern
    I64 bits = *(I64*)&cc->lex.token_f64;
    ICAdd(cc, IC_IMM_F64, bits, RT_F64);
    cc->last_expr_type = RT_F64;
    LexNext(cc);
    return true;
  }
  
  if (cc->lex.token == TK_STR) {
    // String literal - add to string table
    I64 slen = cc->lex.token_str ? cc->lex.token_str_len : 0;
    char *str = malloc(slen + 1);
    memcpy(str, cc->lex.token_str ? cc->lex.token_str : "", slen);
    str[slen] = 0;
    
    // Add to string table (will be emitted at end of code)
    StringLiteral *sl = malloc(sizeof(StringLiteral));
    sl->str = str;
    sl->len = slen;
    sl->offset = 0;  // Will be set during code generation
    sl->next = cc->strings;
    cc->strings = sl;
    
    // Use special IC to mark string literal (offset will be patched)
    ICAdd(cc, IC_STR_CONST, (I64)sl, RT_I64);
    cc->last_expr_type = RT_I64;
    cc->last_var_symbol = NULL;    // a literal is a value: no auto-deref from a stale operand
    // ...but a value of type U8 *: `"abc"[i]` and `*("abc"+2)` index bytes. Without this the
    // subscript fell to its I64/8 default and read 8 bytes at 8*i (a hex-digit table printed 't').
    cc->expr_ptr_depth = 1;
    cc->expr_pointee = RT_U8;
    cc->str_lit_just_loaded = true;
    cc->last_global_var = NULL;
    cc->last_member = NULL;
    LexNext(cc);
    // Adjacent literals across a macro boundary (`ST_ERR_ST "%s"`) arrive as separate tokens.
    while (cc->lex.token == TK_STR) {
      I64 n2 = cc->lex.token_str ? cc->lex.token_str_len : 0;
      char *joined = malloc(sl->len + n2 + 1);
      memcpy(joined, sl->str, sl->len);
      memcpy(joined + sl->len, cc->lex.token_str ? cc->lex.token_str : "", n2);
      joined[sl->len + n2] = 0;
      free(sl->str);
      sl->str = joined;
      sl->len += n2;
      LexNext(cc);
    }
    return true;
  }
  
  if (cc->lex.token == TK_DOLLAR && !cc->in_class_body) {   // `$$`: the current code address
    LexNext(cc);
    ICAdd(cc, IC_PC, 0, RT_I64);
    cc->last_expr_type = RT_I64;
    cc->last_var_symbol = NULL;
    cc->last_global_var = NULL;
    return true;
  }

  // `ToI64(x)`, `ToF64(x)`, `ToBool(x)`: the conversions (casts only relabel in HolyC).
  if (cc->lex.token == TK_IDENT && cc->lex.token_str &&
      (!strcmp(cc->lex.token_str, "ToI64") || !strcmp(cc->lex.token_str, "ToF64") || !strcmp(cc->lex.token_str, "ToBool"))) {
    char which = cc->lex.token_str[2];   // 'I', 'F', 'B'
    LexPush(cc);
    LexNext(cc);
    if (cc->lex.token == '(') {
      LexPopNoRestore(cc);
      LexNext(cc);
      if (!ParseExpression(cc)) return false;
      if (!LexExpect(cc, ')')) return false;
      if (which == 'F') { if (cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64); cc->last_expr_type = RT_F64; }
      else if (which == 'I') { if (cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64); cc->last_expr_type = RT_I64; }
      else { if (cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64); ICAdd(cc, IC_NOT, 0, RT_I64); ICAdd(cc, IC_NOT, 0, RT_I64); cc->last_expr_type = RT_I64; }
      cc->last_var_symbol = NULL;
      cc->last_global_var = NULL;
      cc->last_member = NULL;
      return true;
    }
    LexPopRestore(cc);
  }

  // `offset(Class.member[.sub…])`: constant member offset.
  if (cc->lex.token == TK_IDENT && cc->lex.token_str && !cc->lex.hash_entry && !strcmp(cc->lex.token_str, "offset")) {
    LexPush(cc);
    LexNext(cc);
    if (cc->lex.token == '(') {
      LexPopNoRestore(cc);
      LexNext(cc);
      if (!(cc->lex.token == TK_IDENT && cc->lex.hash_entry && (cc->lex.hash_entry->type & HTT_CLASS))) {
        Error(cc, "offset: expected class name");
        return false;
      }
      CHashClass *ocls = (CHashClass *)cc->lex.hash_entry;
      LexNext(cc);
      I64 off = 0;
      while (cc->lex.token == '.') {
        LexNext(cc);
        if (!(cc->lex.token == TK_IDENT || (cc->lex.token >= 300 && cc->lex.token_str)) || !ocls) {
          Error(cc, "offset: expected member name");
          return false;
        }
        CMemberLst *om = ocls->member_lst;
        // Guard om->str: a member can legitimately have no name (HostMemberFind
        // guards it too), and strcmp(NULL, ...) would crash the compiler here.
        while (om && !(om->str && cc->lex.token_str && !strcmp(om->str, cc->lex.token_str)))
          om = om->next;
        if (!om) {
          char msg[160];
          snprintf(msg, sizeof msg, "offset: unknown member '%s' in class '%s'",
                   cc->lex.token_str ? cc->lex.token_str : "(null)",
                   ocls->str ? ocls->str : "(anon)");
          Error(cc, msg);
          return false;
        }
        off += om->offset;
        ocls = om->member_class;
        LexNext(cc);
      }
      if (!LexExpect(cc, ')')) return false;
      ICAdd(cc, IC_IMM_I64, off, RT_I64);
      cc->last_expr_type = RT_I64;
      cc->last_var_symbol = NULL;
      cc->last_global_var = NULL;
      return true;
    }
    LexPopRestore(cc);
  }

  if (cc->lex.token == TK_IDENT) {
    // Variable or function call
    char *name = strdup(cc->lex.token_str);
    if (!name) return false;  // malloc failed
    
    LexNext(cc);
    
    // `p(U8 *)[i]` / `n(U8)`: a variable followed by a HolyC postfix cast is not a call.
    bool postfix_cast = false;
    if (cc->lex.token == '(' && !(cc->hash_table && HashFind(name, cc->hash_table, HTT_FUN))) {
      LexPush(cc);
      LexNext(cc);
      if (IsTypeStartToken(cc)) {
        LexNext(cc);
        while (cc->lex.token == '*') LexNext(cc);
        postfix_cast = (cc->lex.token == ')');
      }
      LexPopRestore(cc);
    }
    
    if (cc->lex.token != '(' && !addr_of) {
      CHashEntry *fe = HashFind(name, cc->hash_table, HTT_FUN);
      Symbol *vs = SymbolLookup(cc, name);
      if (vs && vs->type == SYM_FUNCTION) vs = NULL;
      if (fe && (fe->type & HTT_FUN) && !vs && !HashFind(name, cc->hash_table, HTT_GLBL_VAR)) {
        // Only when the call can be made: a name whose parameters have no defaults is the
        // function's address (`fp=Add;`), as before.
        CHashFun *nf = (CHashFun *)fe;
        I64 fixed = nf->is_varargs ? nf->param_cnt - 2 : nf->param_cnt;
        bool callable = true;
        for (I64 pi = 0; pi < fixed && pi < 16; pi++) if (!nf->param_has_default[pi]) { callable = false; break; }
        if (callable) {
          bool r = EmitNoParenCall(cc, nf);
          free(name);
          return r;
        }
      }
    }
    
    if (cc->lex.token == '(' && !postfix_cast) {
      // Function call
      LexNext(cc); // Skip '('
      if (cc->aot_mode && !HashFind(name, cc->hash_table, HTT_FUN)) {
        // Called before any declaration: HolyC resolves it at load — an implicit import.
        // (The REPL has nothing to resolve it against later, so there it stays an error.)
        Symbol *vs = SymbolLookup(cc, name);
        if (vs && vs->type == SYM_FUNCTION) vs = NULL;
        if (!vs && !HashFind(name, cc->hash_table, HTT_GLBL_VAR)) {
          CHashFun *nf = calloc(1, sizeof(CHashFun));
          nf->str = strdup(name);
          nf->type = HTT_FUN;
          nf->raw_type = RT_I64;
          HashAdd((CHashEntry *)nf, cc->hash_table);
          MakeImportSlot(cc, nf);
        }
      }
      
      ICAdd(cc, IC_CALL_START, 0, RT_I64);
      
      // Parse arguments. An empty slot (`f(,2)`, `f(1,)`) takes that parameter's default.
      CHashFun *pre_fn = NULL;
      {
        CHashEntry *pe = cc->hash_table ? HashFind(name, cc->hash_table, HTT_FUN) : NULL;
        if (pe && (pe->type & HTT_FUN)) pre_fn = (CHashFun *)pe;
      }
      int arg_count = 0;
      int va_cnt = 0;            // extra arguments of a HolyC varargs callee (stored, not pushed)
      I64 va_base = -1;          // frame temp holding them (argv)
      I64 va_fixed = (pre_fn && pre_fn->is_varargs) ? pre_fn->param_cnt - 2 : -1;
      if (cc->lex.token != ')') {
        do {
          if (arg_count + va_cnt > 0) {
            if (!LexExpect(cc, ',')) {
              free(name);
              return false;
            }
          }
          if (cc->lex.token == ',' || cc->lex.token == ')') {
            if (!pre_fn || arg_count >= pre_fn->param_cnt || arg_count >= 16 || !pre_fn->param_has_default[arg_count]) {
              // Name the callee and say which of the two it is. `DocFind(doc,,needle,n)` on a
              // function the port does not have read as a plain "Omitted argument has no default
              // value", which looks like a lost default on a function that exists — nine demos
              // showed it and the real answer was usually a missing declaration.
              char umsg[192];
              if (!pre_fn || !pre_fn->param_typed)
                snprintf(umsg, sizeof umsg,
                         "Argument %d omitted, but '%s' has no declaration here to take a default from",
                         arg_count + 1, name);
              else
                snprintf(umsg, sizeof umsg, "Argument %d of '%s' omitted and has no default value",
                         arg_count + 1, name);
              Error(cc, umsg);
              free(name);
              return false;
            }
            if (!EmitDefaultArg(cc, pre_fn, arg_count)) { free(name); return false; }
          } else if (va_fixed >= 0 && arg_count >= va_fixed) {
            // Extra argument of a varargs function: store it in the caller's argv temp.
            if (va_base < 0) va_base = cc->locals_size;
            I64 marker = HOLY_LOCAL_MARKER(va_base + 8 * va_cnt);
            cc->locals_size += 8;
            ICAdd(cc, IC_LEA, marker, RT_I64);
            ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
            if (!ParseExpression(cc)) {
              free(name);
              return false;
            }
            CIntermediateCode *aic = ICNew(cc, IC_ASSIGN);
            aic->res.type.raw_type = RT_I64;
            aic->res.type.mode = MDF_STK;
            aic->arg1_type_pointed_to = RT_I64;
            if (cc->ic_tail) cc->ic_tail->next = aic; else cc->ic_head = aic;
            cc->ic_tail = aic;
            ICAdd(cc, IC_EVAL_DROP, 8, RT_I64);
            va_cnt++;
            continue;
          } else {
            if (!ParseExpression(cc)) {
              free(name);
              return false;
            }
            // Convert to the parameter's type (F64 <-> I64) when the callee's types are known.
            if (pre_fn && pre_fn->param_typed) {
              I64 typed_n = pre_fn->param_cnt ? (pre_fn->is_varargs ? pre_fn->param_cnt - 2 : pre_fn->param_cnt) : pre_fn->arg_cnt;
              if (arg_count < typed_n) {
                bool want_f64 = (pre_fn->param_f64_mask >> arg_count) & 1;
                if (want_f64 && cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
                else if (!want_f64 && cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64);
              }
            }
          }
          // Add IC_PUSH_RES after each argument (TempleOS ICF_PUSH_RES flag)
          ICAdd(cc, IC_PUSH_RES, 0, 0);
          arg_count++;
        } while (cc->lex.token == ',');
      }
      
      if (!LexExpect(cc, ')')) {
        free(name);
        return false;
      }
      if (va_fixed >= 0) {
        // Fill the fixed parameters' defaults, then pass argc and argv.
        while (arg_count < va_fixed && arg_count < 16 && pre_fn->param_has_default[arg_count]) {
          if (!EmitDefaultArg(cc, pre_fn, arg_count)) { free(name); return false; }
          ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
          arg_count++;
        }
        ICAdd(cc, IC_IMM_I64, va_cnt, RT_I64);
        ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
        if (va_cnt > 0) {
          ICAdd(cc, IC_LEA, HOLY_LOCAL_MARKER(va_base), RT_I64);
          ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
        } else {
          ICAdd(cc, IC_IMM_I64, 0, RT_I64);
        }
        ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
        arg_count += 2;
      }
      
      // Look up function in HASH TABLE (not symbol table - functions are in hash table)
      if (!cc->hash_table) {
        // No hash table - can't look up function
        free(name);
        return false;
      }
      
      CHashEntry *entry = HashFind(name, cc->hash_table, HTT_FUN);
      // Outlives the branch below so the call result can carry the callee's return
      // pointer-ness; stays NULL on the non-HTT_FUN paths, which clears it instead.
      CHashFun *called = NULL;
      if (entry && (entry->type & HTT_FUN)) {
        // Function found in hash table
        CHashFun *func = (CHashFun*)entry;
        called = func;
        if (func) {
          // Fill in trailing default arguments; too few without defaults is an error.
          while (arg_count < func->param_cnt && arg_count < 16 && func->param_has_default[arg_count]) {
            if (!EmitDefaultArg(cc, func, arg_count)) { free(name); return false; }
            ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
            arg_count++;
          }
          if (func->param_cnt && arg_count < func->param_cnt) {
            Error(cc, "Too few arguments in call");
            free(name);
            return false;
          }
          if (!EmitCallDispatch(cc, func)) {
            free(name);
            return false;
          }
          cc->call_ret_type = (U8)func->raw_type;
          // Store actual arg_cnt for compiler to use (not func->arg_cnt)
          cc->last_call_arg_cnt = arg_count;
          SetCallArgCnt(cc, arg_count);
          
          
        } else {
          free(name);
          return false;
        }
      } else {
        // Check for local function pointer variable
        Symbol *fp_sym = SymbolLookup(cc, name);
        if (fp_sym && fp_sym->is_function_pointer) {
          cc->last_var_symbol = fp_sym;
          cc->last_expr_class = fp_sym->extra ? (CHashClass*)fp_sym->extra : NULL;
          cc->flags &= ~(CCF_RAX | CCF_ARRAY);

          ICAdd(cc, IC_LEA, fp_sym->offset, RT_I64);
          ICAdd(cc, IC_DEREF, 0, RT_I64);  // Push code address held by the funptr
          cc->last_call_arg_cnt = arg_count;
          SetCallArgCnt(cc, arg_count);
          ICAdd(cc, IC_CALL_INDIRECT, 0, RT_I64);
          SetCallArgCnt(cc, arg_count);  // the count must land on this IC, not an earlier call
          cc->last_var_symbol = NULL;  // a call result is a value; args may have set this
          cc->last_expr_type = RT_I64;
          cc->last_global_var = NULL;
          ICAdd(cc, IC_CALL_END, 0, RT_I64);
          free(name);
          return true;
        }

        // Check for global function pointer variable
        CHashEntry *global_fp = HashFind(name, cc->hash_table, HTT_GLBL_VAR);
        if (global_fp && (global_fp->type & HTT_GLBL_VAR)) {
          CHashGlblVar *global = (CHashGlblVar*)global_fp;
          if (global->is_function_pointer) {
            cc->last_global_var = global;
            ICAdd(cc, IC_IMM_I64, (I64)global->data_addr, RT_I64);
            cc->ic_tail->ic_flags = ICF_GLBL_ADDR;
            ICAdd(cc, IC_EVAL_DROP, 8, RT_I64);   // keep only the pointer value above the args
            ICAdd(cc, IC_DEREF, 0, RT_I64);
            cc->last_call_arg_cnt = arg_count;
            SetCallArgCnt(cc, arg_count);
            ICAdd(cc, IC_CALL_INDIRECT, 0, RT_I64);
            SetCallArgCnt(cc, arg_count);  // the count must land on this IC, not an earlier call
            cc->last_var_symbol = NULL;  // a call result is a value; args may have set this
            cc->last_expr_type = RT_I64;
            cc->last_global_var = NULL;
            ICAdd(cc, IC_CALL_END, 0, RT_I64);
            free(name);
            return true;
          }
        }

        // Function not found - emit warning result
        Error(cc, "Unknown function or function pointer");
        ICAdd(cc, IC_IMM_I64, 0, RT_I64);
      }
      
      cc->last_var_symbol = NULL;  // a call result is a value; args may have set this
      
      cc->last_expr_type = (cc->call_ret_type == RT_F64) ? RT_F64 : (cc->call_ret_type == RT_I0 || cc->call_ret_type == RT_U0) ? RT_I0 : RT_I64;
      
      cc->last_global_var = NULL;
      cc->last_member = NULL;
      // Result is the callee's return type, not an argument's — including its
      // pointer-ness, so `*Fn()` derefs at the pointee's width.
      SetCallResultPtr(cc, called);

      ICAdd(cc, IC_CALL_END, 0, RT_I64);
      free(name);
      return true;
    } else {
      // Variable reference - check local symbol table first, then globals
      Symbol *sym = SymbolLookup(cc, name);
      if (sym && sym->type == SYM_FUNCTION) sym = NULL;  // functions are handled below, not as variables
      if (sym) {
        // Local variable - save symbol for array subscripting
        cc->last_var_symbol = sym;
        cc->last_member = NULL;
        cc->subscript_level = 0;
        cc->last_expr_type = (sym->data_type == RT_F64 && !sym->pointed_to_type && !sym->is_array) ? RT_F64 :
                             (sym->pointed_to_type || sym->data_type == RT_U8 || sym->data_type == RT_U16 ||
                              sym->data_type == RT_U32 || sym->data_type == RT_U64) ? RT_U64 : RT_I64;
        cc->last_global_var = NULL;
        cc->last_expr_class = sym->extra ? (CHashClass*)sym->extra : NULL;
        
        // Match original (PrsExp.HC:765-807)
        // Clear CCF_RAX flag (line 765)
        cc->flags &= ~(CCF_RAX | CCF_ARRAY);
        
        // ALL variables (including parameters) use same pattern
        // Generate address of variable: addi a0, s0, offset
        // Use IC_LEA (Load Effective Address) with offset
        ICAdd(cc, IC_LEA, sym->offset, RT_I64);
        cc->var_just_loaded = true;
        cc->global_just_loaded = false;
        if (sym->is_array) {
          // An array is its address: no auto-deref; push it so it is a proper eval-stack value
          // (call argument, assignment source). `[` sees the pushed base and adds no second push.
          cc->flags |= CCF_ARRAY;
          ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
        }
        // PE_DEREFERENCE will add IC_DEREF if !(CCF_RAX|CCF_ARRAY)
        
        free(name);
        return true;
      }
      
      // Check global hash table
      CHashEntry *entry = HashFind(name, cc->hash_table, HTT_GLBL_VAR);
      if (entry && (entry->type & HTT_GLBL_VAR)) {
        // Global variable
        CHashGlblVar *global = (CHashGlblVar*)entry;
        cc->last_global_var = global;
        cc->last_member = NULL;
        cc->last_var_symbol = NULL;  // stale local from an earlier statement would suppress the auto-deref
        cc->var_just_loaded = false;
        cc->global_just_loaded = true;
        cc->last_expr_type = (global->raw_type == RT_F64 && !global->pointed_to_type && !(global->flags & GVF_ARRAY)) ? RT_F64 :
                             (global->pointed_to_type || global->raw_type == RT_U8 || global->raw_type == RT_U16 ||
                              global->raw_type == RT_U32 || global->raw_type == RT_U64) ? RT_U64 : RT_I64;
        
        // Generate load from global (absolute address)
        CICType type = {0};
        type.mode = MDF_IMM;
        type.raw_type = RT_I64;
        
        // For now, push the address of the global
        // Full implementation would load the value
        CIntermediateCode *ic = ICNew(cc, IC_IMM_I64);
        ic->ic_data = (I64)global->data_addr;
        ic->ic_flags = ICF_GLBL_ADDR;
        cc->last_expr_class = global->var_class;
        cc->flags &= ~(CCF_RAX | CCF_ARRAY);
        if (global->flags & GVF_ARRAY) cc->flags |= CCF_ARRAY;   // array = its (already pushed) address
        
        // Link into IC chain
        if (cc->ic_tail) cc->ic_tail->next = ic;
        else cc->ic_head = ic;
        cc->ic_tail = ic;
        
        free(name);
        return true;
      }
      
      // Function name without '(': HolyC calls it with no arguments (`Dir;`), except under
      // `&`, where it is the function's code address (once-indirect; see EmitFnAddress).
      CHashEntry *func_entry = HashFind(name, cc->hash_table, HTT_FUN);
      if (func_entry && (func_entry->type & HTT_FUN)) {
        CHashFun *func = (CHashFun*)func_entry;
        if (cc->flags & CCF_RAX) {
          if (!EmitFnAddress(cc, func)) { free(name); return false; }
          cc->last_var_symbol = NULL;
          cc->last_global_var = NULL;
          free(name);
          return true;
        }
        ICAdd(cc, IC_CALL_START, 0, RT_I64);
        if (!EmitCallByName(cc, name, 0)) { free(name); return false; }
        ICAdd(cc, IC_CALL_END, 0, RT_I64);
        cc->last_var_symbol = NULL;
        cc->last_global_var = NULL;
        cc->last_expr_type = RT_I64;
        free(name);
        return true;
      }

      // Check enum constants
      CHashEntry *enum_entry = HashFind(name, cc->hash_table, HTT_ENUM);
      if (enum_entry && (enum_entry->type & HTT_ENUM)) {
        CHashEnumValue *enum_val = (CHashEnumValue*)enum_entry;
        ICAdd(cc, IC_IMM_I64, enum_val->value, RT_I64);
        free(name);
        return true;
      }
      
      { //Name it. "Undefined variable" with no identifier cannot be triaged, and a port needs
        //to enumerate exactly which symbols a body of stock code expects.
        char umsg[192];
        snprintf(umsg, sizeof umsg, "Undefined variable '%s'", name);
        Error(cc, umsg);
      }
      free(name);
      return false;
    }
  }
  
  // Parenthesized expression or C-style cast: (type) x, (type *) x
  if (cc->lex.token == '(') {
    LexPush(cc);
    LexNext(cc);  // Skip '('
    if (IsTypeStartToken(cc)) {
      U8 saved_pt = cc->last_pointed_to_type;
      CHashClass *saved_tc = cc->last_type_class;
      cc->last_pointed_to_type = 0;
      U8 cast_type = ParseType(cc);   // `U8 *` comes back as I64 with the pointee in last_pointed_to_type
      CHashClass *cast_cls = cc->last_type_class;
      bool cast_ptr = false;
      if (cc->last_pointed_to_type) { cast_ptr = true; cast_type = cc->last_pointed_to_type; }
      while (cc->lex.token == '*') { cast_ptr = true; LexNext(cc); }
      if (cc->lex.token == ')') {
        LexNext(cc);  // Skip ')'
        LexPopNoRestore(cc);
        if (!ParseUnary(cc)) {
          cc->last_pointed_to_type = saved_pt;
          cc->last_type_class = saved_tc;
          return false;
        }
        ApplyCast(cc, cast_type, cast_ptr, cast_cls);
        cc->last_pointed_to_type = saved_pt;
        cc->last_type_class = saved_tc;
        // A cast erases the operand's variable identity: `*(U32 *)b = v` must take its store
        // width from the CAST, and the deref-type chain checks var/global/member pointees first
        // -- a surviving last_global_var made it store by b's own pointee (1 byte for U8 *b).
        cc->last_var_symbol = NULL;
        cc->last_global_var = NULL;
        cc->last_member = NULL;
        return true;
      }
    }
    LexPopRestore(cc);
    // `(*fp)(args)`: call through a computed pointer. Look ahead for `( * … ) (`.
    bool ind_call = false;
    {
      LexPush(cc);
      LexNext(cc);
      if (cc->lex.token == '*') {
        int depth = 1;
        LexNext(cc);
        while (cc->lex.token != TK_EOF && depth > 0) {
          if (cc->lex.token == '(') depth++;
          else if (cc->lex.token == ')') depth--;
          LexNext(cc);
        }
        ind_call = (depth == 0 && cc->lex.token == '(');
        if (ind_call) {   // `(*p)(I64)` is a deref with a postfix cast, not a call
          LexNext(cc);
          if (IsTypeStartToken(cc)) ind_call = false;
        }
      }
      LexPopRestore(cc);
    }
    if (ind_call) {
      I64 marker = HOLY_LOCAL_MARKER(cc->locals_size);   // the pointer, kept in a frame temp
      cc->locals_size += 8;
      ICAdd(cc, IC_LEA, marker, RT_I64);
      ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
      LexNext(cc);  // '('
      LexNext(cc);  // '*': `(*fp)` names the function the pointer holds (no load through it)
      if (!ParseExpression(cc)) return false;
      if (!LexExpect(cc, ')')) return false;
      CIntermediateCode *aic = ICNew(cc, IC_ASSIGN);
      aic->res.type.raw_type = RT_I64;
      aic->res.type.mode = MDF_STK;
      aic->arg1_type_pointed_to = RT_I64;
      if (cc->ic_tail) cc->ic_tail->next = aic; else cc->ic_head = aic;
      cc->ic_tail = aic;
      ICAdd(cc, IC_EVAL_DROP, 8, RT_I64);
      LexNext(cc);  // '('
      ICAdd(cc, IC_CALL_START, 0, RT_I64);
      int argc = 0;
      if (cc->lex.token != ')') {
        do {
          if (argc > 0) LexNext(cc);   // ','
          if (!ParseExpression(cc)) return false;
          ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
          argc++;
        } while (cc->lex.token == ',');
      }
      if (!LexExpect(cc, ')')) return false;
      ICAdd(cc, IC_LEA, marker, RT_I64);
      ICAdd(cc, IC_DEREF, 0, RT_I64);
      cc->last_call_arg_cnt = argc;
      SetCallArgCnt(cc, argc);
      ICAdd(cc, IC_CALL_INDIRECT, 0, RT_I64);
      SetCallArgCnt(cc, argc);
      cc->last_var_symbol = NULL;
      cc->last_global_var = NULL;
      cc->last_expr_type = RT_I64;
      ICAdd(cc, IC_CALL_END, 0, RT_I64);
      return true;
    }
    LexNext(cc);  // Skip '('
    if (!ParseExpression(cc)) return false;
    cc->last_var_symbol = NULL;
    return LexExpect(cc, ')');
  }
  
  Error(cc, "Expected expression");
  return false;
}

static bool ParseUnary(Compiler *cc) {
  // Pre-increment: ++var
  if (cc->lex.token == TK_ADD_ADD) {
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    // Operand must stay an address: retract the auto-deref ParsePostfix appended.
    // The retracted DEREF carries the lvalue's width; IncDec needs it or a U8/U16/U32
    // lvalue gets an 8-byte read-modify-write (neighbour bytes in the result, and a
    // tail member overruns its class).
    U8 lty_pp = 0;
    if (cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) { lty_pp = cc->ic_tail->arg1_type_pointed_to; cc->ic_tail->ic_code = IC_NOP1; }
    // step != 0 means the lvalue is itself a pointer/array (8 bytes wide) — keep I64.
    { U8 pe; I64 pd; I64 step = PtrElemInfo(cc, &pe, &pd); ICAdd(cc, IC_PP_, step > 1 ? step : 0, RT_I64);
      if (!step && lty_pp && cc->ic_tail) cc->ic_tail->arg1_type_pointed_to = lty_pp; }  // pre-increment (scaled for pointers)
    return true;
  }
  
  // Pre-decrement: --var
  if (cc->lex.token == TK_SUB_SUB) {
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    // Operand must stay an address: retract the auto-deref ParsePostfix appended.
    U8 lty_mm = 0;
    if (cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) { lty_mm = cc->ic_tail->arg1_type_pointed_to; cc->ic_tail->ic_code = IC_NOP1; }
    { U8 pe; I64 pd; I64 step = PtrElemInfo(cc, &pe, &pd); ICAdd(cc, IC_MM_, step > 1 ? step : 0, RT_I64);
      if (!step && lty_mm && cc->ic_tail) cc->ic_tail->arg1_type_pointed_to = lty_mm; }  // pre-decrement
    return true;
  }
  
  if (cc->lex.token == '-') {
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    if (cc->last_expr_type == RT_F64) ICAdd(cc, IC_FNEG, 0, RT_F64);
    else ICAdd(cc, IC_UNARY_MINUS, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == '+') {
    // Unary plus: the value unchanged. C and HolyC both allow it, and stock TempleOS uses it
    // for column alignment in tables of signed constants — Demo/Games/Maze.HC's
    // `I64 dir_x[4]={ 0,+1, 0,-1}` failed to compile without this, in the initializer AND in
    // ordinary expressions (`a=+1`). No IC: `+x` is x.
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    return true;
  }

  if (cc->lex.token == '!') {
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    ICAdd(cc, IC_NOT, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == '~') {
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    ICAdd(cc, IC_COM, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == '&') {
    // Address-of operator
    LexNext(cc);
    cc->addr_of_ident = true;   // `&Fn` names the function; not a no-paren call
    I64 saved_flags = cc->flags;
    cc->flags |= CCF_RAX;
    if (!ParseUnary(cc)) {
      cc->flags = saved_flags;
      return false;
    }
    cc->flags = saved_flags;
    // ParsePrimary clears CCF_RAX, so the auto-deref still fired: retract it and make sure the
    // address is on the eval stack (that is the whole of `&`) — unless the operand was an
    // extern function, whose trailing DEREF loads the code address from its import slot.
    if (cc->ic_tail != cc->fn_addr_slot_deref)
      EnsureLvalueAddressPushed(cc);
    U8 addr_pointee = RT_I64;
    if (cc->last_var_symbol) addr_pointee = cc->last_var_symbol->pointed_to_type ? RT_I64 : cc->last_var_symbol->data_type;
    else if (cc->last_global_var) addr_pointee = cc->last_global_var->pointed_to_type ? RT_I64 : (U8)cc->last_global_var->raw_type;
    else if (cc->last_member) addr_pointee = cc->last_member->pointed_to_type ? RT_I64 : cc->last_member->raw_type;
    cc->last_expr_type = RT_I64;   // `&x` is a pointer (address), never F64 — else `I64 a=&x` converts it
    cc->expr_ptr_depth = 1;
    cc->expr_pointee = addr_pointee;
    cc->last_var_symbol = NULL;
    cc->last_global_var = NULL;
    cc->last_member = NULL;
    return true;
  }
  
  if (cc->lex.token == '*') {
    // Dereference operator - explicit dereference
    LexNext(cc);

    if (!ParseUnary(cc)) return false;

    U8 deref_type = RT_I64;
    U8 depth = 0, pointee = 0;
    if (cc->last_var_symbol && cc->last_var_symbol->pointed_to_type != 0) {
      pointee = cc->last_var_symbol->pointed_to_type; depth = cc->last_var_symbol->ptr_depth;
      if (depth <= 1) {
        CHashClass *pc = (CHashClass *)cc->last_var_symbol->extra;
        if (pc && pc->size > 0) pointee = ScalarTypeForSize(pointee, pc->size);
      }
    } else if (cc->last_var_symbol && cc->last_var_symbol->is_array) {
      // `*arr` on a plain array: the array decays to element*, so the deref loads/stores ONE
      // element, whose width is the element type — not RT_I64. Without this, deref_type stayed
      // RT_I64 and `*arr = v` emitted an 8-byte store that zeroed the next 7 bytes of the array
      // (e.g. DirNameAbs's `U8 drv[3]; *drv=Drv2Let;` lost the ':' it put in drv[1], hanging Load).
      pointee = cc->last_var_symbol->data_type; depth = 1;
      {
        I64 esz = cc->last_var_symbol->element_size > 0 ? cc->last_var_symbol->element_size : 8;
        pointee = ScalarTypeForSize(pointee, esz);
      }
    } else if (!cc->last_var_symbol && cc->last_global_var && cc->last_global_var->pointed_to_type) {
      pointee = cc->last_global_var->pointed_to_type; depth = cc->last_global_var->ptr_depth;
      if (depth <= 1) {
        CHashClass *pc = cc->last_global_var->var_class;
        if (pc && pc->size > 0) pointee = ScalarTypeForSize(pointee, pc->size);
      }
    } else if (!cc->last_var_symbol && !cc->last_global_var && cc->last_member && cc->last_member->is_array) {
      // `*p->arr` / `*s.arr`: a member array decays to element*, exactly like the local-array case
      // above. The member branch below only knew pointer members, so deref_type fell to RT_I64:
      // RedSeaFilesFind's `*tmpde->name!='.'` read 8 bytes of ".." (0x2e2e != '.'), sent ".." down
      // the recurse branch, and every FilesFind(FUF_RECURSE) recursed into its own parent until the
      // heap died. An array of pointers dereferences to a pointer (depth stays > 1 -> RT_I64).
      CMemberLst *mb = cc->last_member;
      if (mb->pointed_to_type) { pointee = mb->pointed_to_type; depth = (U8)(mb->ptr_depth + 1); }
      else {
        I64 esz = mb->elem_size > 0 ? mb->elem_size : PrimitiveTypeSize(mb->raw_type);
        pointee = ScalarTypeForSize(mb->raw_type, esz); depth = 1;
      }
    } else if (!cc->last_var_symbol && !cc->last_global_var && cc->last_member && cc->last_member->pointed_to_type) {
      pointee = cc->last_member->pointed_to_type; depth = cc->last_member->ptr_depth;
    } else if (cc->expr_ptr_depth) {   // `**pp`: the inner deref left a pointer
      pointee = cc->expr_pointee; depth = cc->expr_ptr_depth;
    } else if (cc->cast_elem_type) {   // `*(U32*)p`: a preceding pointer cast set the element width
      pointee = cc->cast_elem_type; depth = 1;
      cc->cast_elem_type = 0;          // consumed -- must not leak into a later deref in the expression
    }
    if (depth < 1) depth = 1;
    deref_type = (depth > 1 || !pointee) ? RT_I64 : pointee;   // through a `T **`, load the pointer
    /* Drop duplicate pointer slot (still in a0) before DEREF pushes *a0 — else DROP after would
     * pop the loaded value. */
    ICAdd(cc, IC_EVAL_DROP, 8, RT_I64);
    ICAdd(cc, IC_DEREF, 0, RT_I64);
    if (cc->ic_tail) cc->ic_tail->arg1_type_pointed_to = deref_type;
    cc->last_expr_type = (deref_type == RT_F64) ? RT_F64 :
      (deref_type == RT_U8 || deref_type == RT_U16 || deref_type == RT_U32 || deref_type == RT_U64) ? RT_U64 : RT_I64;
    cc->last_var_symbol = NULL;
    if (depth > 1) { cc->last_global_var = NULL; cc->last_member = NULL; }
    cc->expr_ptr_depth = (U8)(depth - 1);
    cc->expr_pointee = pointee;
    return true;
  }
  
  return ParsePostfix(cc);  // Changed from ParsePrimary
}

// Handle postfix operators: [], ., ->
static bool ParsePostfix(Compiler *cc) {
  // Parse primary expression first
  bool is_paren_expr = (cc->lex.token == '(');  // Track parenthesized expressions
  if (!ParsePrimary(cc)) return false;
  
  // Auto-dereference variables (match original PE_DEREFERENCE phase PrsExp.HC:97-118)
  // Only if ParsePrimary just loaded a local (var_just_loaded), not a stale last_var_symbol
  // left over from an earlier operand in `!p || !p[0]` — that used to skip auto-deref and
  // made U8* param `p[i]` index the stack slot (stack smash).
  // Skip auto-deref for parenthesized expressions
  if (cc->var_just_loaded && cc->last_var_symbol && !(cc->flags & (CCF_RAX | CCF_ARRAY)) && !is_paren_expr) {
    // Create IC_DEREF with typed load
    CIntermediateCode *ic = ICNew(cc, IC_DEREF);
    ic->res.type.raw_type = RT_I64;
    ic->res.type.mode = MDF_STK;
    
    // Auto-deref loads the VARIABLE itself, not what it points to
    // Always use data_type (RT_I64 for pointers, actual type for non-pointers)
    ic->arg1_type_pointed_to = cc->last_var_symbol->data_type;
    
    // Link into IC chain
    if (cc->ic_tail) cc->ic_tail->next = ic;
    else cc->ic_head = ic;
    cc->ic_tail = ic;
  } else if (cc->global_just_loaded && !cc->last_var_symbol && cc->last_global_var &&
             !(cc->flags & (CCF_RAX | CCF_ARRAY)) && !is_paren_expr) {
    // Auto-deref for global variables. IC_IMM_I64 pushed the address; drop that slot so the
    // value is the only thing left (a second global operand would otherwise pop the address).
    ICAdd(cc, IC_EVAL_DROP, 8, RT_I64);
    CIntermediateCode *ic = ICNew(cc, IC_DEREF);
    ic->res.type.raw_type = RT_I64;
    ic->res.type.mode = MDF_STK;
    ic->arg1_type_pointed_to = cc->last_global_var->raw_type;
    
    if (cc->ic_tail) cc->ic_tail->next = ic;
    else cc->ic_head = ic;
    cc->ic_tail = ic;
  }
  cc->var_just_loaded = false;
  cc->global_just_loaded = false;
  
  // Handle postfix operators (array subscript, member access)
  // Save a prefix pointer-cast's element width (e.g. `(U32*)p`) before resetting for the postfix loop:
  // if no postfix operator ([]/./-> or a postfix cast) consumes it, it must survive so an OUTER deref
  // `*(U32*)p` stores/loads by that width instead of defaulting to 8 bytes.
  U8 primary_ptr_cast = cc->cast_elem_type;
  cc->cast_elem_type = 0;
  // `(**ppb)[i]` keeps the depth the parens computed; a pointer-returning call keeps
  // its pointee so `*Fn()` can size the deref.
  if (!is_paren_expr && !cc->call_ptr_just_loaded && !cc->str_lit_just_loaded) cc->expr_ptr_depth = 0;   // a literal is a U8 * value too
  while (true) {
    if (cc->lex.token == '(') {
      // HolyC postfix cast: expr(type) / expr(type *), e.g. "0123456789ABCDEF"(U8 *)[i].
      LexPush(cc);
      LexNext(cc);
      bool is_cast = false;
      if (IsTypeStartToken(cc)) {
        U8 saved_pt = cc->last_pointed_to_type;
        CHashClass *saved_tc = cc->last_type_class;
        cc->last_pointed_to_type = 0;
        U8 cast_type = ParseType(cc);   // `U8 *`: I64 with the pointee in last_pointed_to_type
        CHashClass *cast_cls = cc->last_type_class;
        bool cast_ptr = false;
        if (cc->last_pointed_to_type) { cast_ptr = true; cast_type = cc->last_pointed_to_type; }
        while (cc->lex.token == '*') { cast_ptr = true; LexNext(cc); }
        cc->last_pointed_to_type = saved_pt;
        cc->last_type_class = saved_tc;
        if (cc->lex.token == ')' && !cc->error) {
          LexNext(cc);
          LexPopNoRestore(cc);
          ApplyCast(cc, cast_type, cast_ptr, cast_cls);
          cc->last_var_symbol = NULL;
          cc->last_global_var = NULL;
          cc->last_member = NULL;
          is_cast = true;
        }
      }
      if (!is_cast) { LexPopRestore(cc); break; }
      continue;
    }
    if (cc->lex.token == '[') {
      // Array subscripting: arr[index]
      // Result: (base_addr + index * element_size)
      
      LexNext(cc);  // Skip '['
      
      // Get element size from last variable's type info
      I64 elem_size = 8;  // Default to I64
      Symbol *saved_symbol = cc->last_var_symbol;
      CHashGlblVar *saved_global = cc->last_global_var;
      // Parsing the index expression overwrites cc->last_member (`m.rows[n]` re-binds it to
      // whatever `n` resolves to), so snapshot it alongside the symbol/global.
      CMemberLst *saved_member = cc->last_member;
      // ...and the expression's own pointer typing, for a base with no name behind it (a string
      // literal, a cast, a call): the index expression overwrites these too.
      U8 saved_ptr_depth = cc->expr_ptr_depth, saved_pointee = cc->expr_pointee;
      // Element type/size: through a pointer it is the pointee (class or primitive); for an
      // array it is the declared element. The final DEREF is typed accordingly.
      U8 elem_type = RT_I64;
      if (saved_symbol) {
        if (saved_symbol->pointed_to_type && !saved_symbol->is_array) {
          elem_type = saved_symbol->pointed_to_type;
          CHashClass *pc = (CHashClass *)saved_symbol->extra;
          elem_size = pc && pc->size > 0 ? pc->size : PrimitiveTypeSize(elem_type);
          if (saved_symbol->ptr_depth > 1) { elem_type = RT_I64; elem_size = 8; }   // `argv[i]` of `U8 **argv`
          else elem_type = ScalarTypeForSize(elem_type, elem_size);  // `U32 *p` / scalar-union pointee
          if (elem_size <= 0) elem_size = 8;
        } else {
          elem_size = saved_symbol->element_size ? saved_symbol->element_size : 8;
          elem_type = ScalarTypeForSize(saved_symbol->data_type, elem_size);
        }
        if (saved_symbol->ndims > 1 && cc->subscript_level < saved_symbol->ndims - 1)
          elem_size = saved_symbol->dim_stride[cc->subscript_level];
      } else if (!saved_symbol && !saved_global && cc->last_member) {
        CMemberLst *mb = cc->last_member;
        elem_type = mb->pointed_to_type ? mb->pointed_to_type : mb->raw_type;
        elem_size = mb->elem_size > 0 ? mb->elem_size : PrimitiveTypeSize(elem_type);
        // Prefer declared pointee class size for `U32 *member` (scalar unions are 4, not 8).
        if (mb->pointed_to_type && mb->ptr_depth <= 1 && !mb->is_array &&
            mb->member_class && mb->member_class->size > 0)
          elem_size = mb->member_class->size;
        elem_type = ScalarTypeForSize(elem_type, elem_size);
        if (mb->pointed_to_type && mb->ptr_depth > 1 && !mb->is_array) { elem_type = RT_I64; elem_size = 8; }
        if (!mb->is_array && !mb->pointed_to_type && mb->member_class && mb->member_class->size > 0) elem_size = mb->member_class->size;
        if (elem_size <= 0) elem_size = 8;
        if (mb->ndims > 1 && cc->subscript_level < mb->ndims - 1)
          elem_size = mb->dim_stride[cc->subscript_level];
      } else if (!saved_symbol && !saved_global && !saved_member && saved_ptr_depth == 1 && saved_pointee) {
        // no name behind the base -- a string literal, a cast, a call result typed as a pointer:
        // the element is the expression's pointee
        elem_type = saved_pointee;
        elem_size = PrimitiveTypeSize(elem_type);
        if (elem_size <= 0) elem_size = 8;
        elem_type = ScalarTypeForSize(elem_type, elem_size);
      } else if (saved_global) {
        if (saved_global->pointed_to_type && !(saved_global->flags & GVF_ARRAY)) {
          elem_type = saved_global->pointed_to_type;
          CHashClass *pc = saved_global->var_class;
          elem_size = pc && pc->size > 0 ? pc->size : PrimitiveTypeSize(elem_type);
          if (saved_global->ptr_depth > 1) { elem_type = RT_I64; elem_size = 8; }
          else elem_type = ScalarTypeForSize(elem_type, elem_size);
          if (elem_size <= 0) elem_size = 8;
        } else {
          elem_size = saved_global->element_size ? saved_global->element_size : 8;
          elem_type = ScalarTypeForSize((U8)saved_global->raw_type, elem_size);
        }
        if (saved_global->ndims > 1 && cc->subscript_level < saved_global->ndims - 1)
          elem_size = saved_global->dim_stride[cc->subscript_level];
      } else if (!saved_symbol && !saved_global && !cc->last_member && cc->expr_ptr_depth) {
        // `(**ppb)[i]`, `argv[1][0]`: the base is a pointer value whose depth a deref/subscript left
        elem_type = (cc->expr_ptr_depth > 1) ? RT_I64 : cc->expr_pointee;
        elem_size = PrimitiveTypeSize(elem_type);
        if (elem_size <= 0) elem_size = 8;
      } else if (cc->cast_elem_type) {
        elem_type = cc->cast_elem_type;
        CHashClass *pc = cc->cast_elem_class;
        elem_size = (pc && (pc->type & HTT_CLASS) && !(pc->type & HTT_INTERNAL_TYPE) && pc->size > 0) ? pc->size : PrimitiveTypeSize(elem_type);
        if (elem_size <= 0) elem_size = 8;
        cc->cast_elem_type = 0;
      }
      
      // An array's base is its address, not its first element: retract the auto-deref, and
      // push the base so the index math below cannot clobber it in a0.
      if (saved_symbol && saved_symbol->is_array) EnsureLvalueAddressPushed(cc);
      else if (saved_global && (saved_global->flags & GVF_ARRAY)) EnsureLvalueAddressPushed(cc);
      // Push element size
      ICAdd(cc, IC_IMM_I64, elem_size, RT_I64);
      
      int saved_level = cc->subscript_level;  // the index expression may reference variables
      CHashClass *saved_class = cc->last_expr_class;  // …and would clobber the element's class
      // Parse index expression (will clobber last_var_symbol, save it)
      if (!ParseExpression(cc)) return false;
      
      // Restore for potential chained subscripts
      cc->last_var_symbol = saved_symbol;
      cc->subscript_level = saved_level;
      cc->last_expr_class = saved_class;
      cc->last_global_var = saved_global;
      
      if (!LexExpect(cc, ']')) return false;
      
      // Multiply index by element size
      ICAdd(cc, IC_MUL, 0, RT_I64);
      
      // Add offset to base address
      ICAdd(cc, IC_ADD, 0, RT_I64);
      
      // Inner subscript of a multi-dimensional array: the result is a sub-array address. If
      // another '[' follows, keep it for that subscript. If NOT (a bare partial subscript like
      // `m[i]` on `m[8][16]`), the row ADDRESS is the result -- a pointer, not a load: keep a0
      // (CCF_RAX skips the deref below) and type it as a pointer. Without this, the bare partial
      // subscript fell through inconsistently and decayed to a wrong pointer (esp. a variable
      // index) -- e.g. `EdLn[k]` passed as an argument.
      if (saved_symbol && saved_symbol->ndims > 1 && cc->subscript_level < saved_symbol->ndims - 1) {
        if (cc->lex.token == '[') { cc->subscript_level++; continue; }
        cc->flags |= CCF_RAX; cc->last_expr_type = RT_I64;
      } else if (saved_global && saved_global->ndims > 1 && cc->subscript_level < saved_global->ndims - 1) {
        if (cc->lex.token == '[') { cc->subscript_level++; continue; }
        cc->flags |= CCF_RAX; cc->last_expr_type = RT_I64;
      } else if (!saved_symbol && !saved_global && saved_member &&
                 saved_member->ndims > 1 && cc->subscript_level < saved_member->ndims - 1) {
        if (cc->lex.token == '[') { cc->subscript_level++; continue; }
        cc->flags |= CCF_RAX; cc->last_expr_type = RT_I64;
      }
      cc->subscript_level = 0;
      // Dereference to get the value
      // This loads the value at the calculated address
      if (!(cc->flags & CCF_RAX)) {
        DerefDroppingAddressSlot(cc);
        if (cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) cc->ic_tail->arg1_type_pointed_to = elem_type;
        // The loaded element carries its type: an F64 element must stay F64 (else `a[i]*2.0` or
        // `ToI64(a[i])` would treat the raw bits as an integer).
        cc->last_expr_type = (elem_type == RT_F64) ? RT_F64 :
          (elem_type == RT_U8 || elem_type == RT_U16 || elem_type == RT_U32 || elem_type == RT_U64) ? RT_U64 : RT_I64;
      }
      // Through a multi-level pointer the element is itself a pointer: the next `[` or `*`
      // continues one level down (`argv[1][0]`).
      {
        U8 sdepth = 0, spointee = 0;
        if (saved_symbol && saved_symbol->pointed_to_type && !saved_symbol->is_array) { sdepth = saved_symbol->ptr_depth; spointee = saved_symbol->pointed_to_type; }
        else if (saved_global && saved_global->pointed_to_type && !(saved_global->flags & GVF_ARRAY)) { sdepth = saved_global->ptr_depth; spointee = saved_global->pointed_to_type; }
        else if (!saved_symbol && !saved_global && cc->last_member && cc->last_member->pointed_to_type && !cc->last_member->is_array) { sdepth = cc->last_member->ptr_depth; spointee = cc->last_member->pointed_to_type; }
        else if (cc->expr_ptr_depth) { sdepth = cc->expr_ptr_depth; spointee = cc->expr_pointee; }
        if (sdepth > 1) {
          cc->last_var_symbol = NULL; cc->last_global_var = NULL; cc->last_member = NULL;
          cc->expr_ptr_depth = (U8)(sdepth - 1); cc->expr_pointee = spointee;
        } else {
          // A subscript yielded a scalar value: it is no longer the container variable, so pointer
          // arithmetic and member-container logic must not see the array/pointer symbol.
          cc->last_var_symbol = NULL; cc->last_global_var = NULL; cc->last_member = NULL;
          cc->expr_ptr_depth = 0;
        }
      }
      
      continue;
    }
    
    if (cc->lex.token == '.') {
      // Member access: struct.member
      LexNext(cc);  // Skip '.'
      
      if (cc->lex.token != TK_IDENT && !(cc->lex.token >= 300 && cc->lex.token_str)) {   // `.reg`: keywords are member names too
        Error(cc, "Expected member name after '.'");
        return false;
      }
      
      char *member_name = strdup(cc->lex.token_str);
      
      // Look up member in class definition
      I64 member_offset = 0;
      CHashClass *member_class = NULL;
      CMemberLst *found = NULL;
      I64 bit_width = 0;
      I64 bit_offset = 0;
      
      if (cc->last_expr_class || (cc->last_var_symbol && cc->last_var_symbol->extra)) {
        // Get the class
        CHashClass *cls = cc->last_expr_class;
        if (!cls && cc->last_var_symbol && cc->last_var_symbol->extra) {
          cls = (CHashClass*)cc->last_var_symbol->extra;
        }
        
        // Look up member (including inherited)
        if (cls) {
          CMemberLst *member = HostMemberFind(cls, member_name);
          if (member) {
            member_offset = member->offset;
            found = member;
            member_class = member->member_class;
            bit_width = member->bit_width;
            bit_offset = member->bit_offset;
          } else {
            HostUnknownMember(cc, cls, member_name, '.');
          }
        }
      }
      
      LexNext(cc);
      // The base of `.` is the aggregate's address, not its first word: retract the auto-deref.
      EnsureLvalueAddressPushed(cc);
      
      if (found && member_offset != 0) {
        // Add offset to base address
        ICAdd(cc, IC_IMM_I64, member_offset, RT_I64);
        ICAdd(cc, IC_ADD, 0, RT_I64);
      }
      
      // Dereference to get member value (typed); an array member is its address instead.
      cc->last_var_symbol = NULL;
      cc->last_global_var = NULL;
      cc->last_member = found;
      if (found && found->is_array) {
        cc->flags |= CCF_ARRAY;
        if (cc->ic_tail && cc->ic_tail->ic_code == IC_PUSH_ARG) { /* offset 0: base already pushed */ }
      } else if (!(cc->flags & CCF_RAX)) {
        DerefDroppingAddressSlot(cc);
        // A scalar-union member (`U32 time;` where U32 is `U32i union U32`) records raw_type=I64 with
        // a sub-word size; use the size for the load/store width so `s.time` is 4 bytes, not 8 (an
        // 8-byte store to a 4-byte field at a struct's tail overruns it — CDate's date/time did).
        U8 mtype = found ? ScalarTypeForSize(found->raw_type, found->size) : RT_I64;
        if (found && cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) cc->ic_tail->arg1_type_pointed_to = mtype;
        if (found && !found->pointed_to_type) cc->last_expr_type = (mtype == RT_F64) ? RT_F64 :
          (mtype == RT_U8 || mtype == RT_U16 || mtype == RT_U32 || mtype == RT_U64) ? RT_U64 : RT_I64;
      }
      
      // Handle bit field extraction
      if (bit_width > 0) {
        // Extract bits: (value >> bit_offset) & ((1 << bit_width) - 1)
        if (bit_offset > 0) {
          ICAdd(cc, IC_IMM_I64, bit_offset, RT_I64);
          ICAdd(cc, IC_SHR, 0, RT_I64);
        }
        
        // Create mask: (1 << bit_width) - 1
        I64 mask = (1LL << bit_width) - 1;
        ICAdd(cc, IC_IMM_I64, mask, RT_I64);
        ICAdd(cc, IC_AND, 0, RT_I64);
      }
      
      // Update type tracking for potential chained access
      cc->last_expr_class = member_class;
      
      free(member_name);
      continue;
    }
    
    // Post-increment: var++
    if (cc->lex.token == TK_ADD_ADD) {
      LexNext(cc);
      // Operand must stay an address: retract the early auto-deref (first reference of a
      // variable in an expression gets one before this loop runs).
      // The retracted DEREF carries the lvalue's width — see the ++var site above.
      U8 lty_ppost = 0;
      if (cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) { lty_ppost = cc->ic_tail->arg1_type_pointed_to; cc->ic_tail->ic_code = IC_NOP1; }
      { U8 pe; I64 pd; I64 step = PtrElemInfo(cc, &pe, &pd); ICAdd(cc, IC__PP, step > 1 ? step : 0, RT_I64);
        if (!step && lty_ppost && cc->ic_tail) cc->ic_tail->arg1_type_pointed_to = lty_ppost; }  // post-increment (scaled)
      continue;
    }
    
    // Post-decrement: var--
    if (cc->lex.token == TK_SUB_SUB) {
      LexNext(cc);
      // Operand must stay an address: retract the early auto-deref (first reference of a
      // variable in an expression gets one before this loop runs).
      U8 lty_mpost = 0;
      if (cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) { lty_mpost = cc->ic_tail->arg1_type_pointed_to; cc->ic_tail->ic_code = IC_NOP1; }
      { U8 pe; I64 pd; I64 step = PtrElemInfo(cc, &pe, &pd); ICAdd(cc, IC__MM, step > 1 ? step : 0, RT_I64);
        if (!step && lty_mpost && cc->ic_tail) cc->ic_tail->arg1_type_pointed_to = lty_mpost; }  // post-decrement
      continue;
    }
    
    // Arrow operator: ptr->member (same as (*ptr).member)
    if (cc->lex.token == TK_ARROW) {
      LexNext(cc);
      
      if (cc->lex.token != TK_IDENT && !(cc->lex.token >= 300 && cc->lex.token_str)) {   // `->reg`
        Error(cc, "Expected member name after '->'");
        return false;
      }
      
      char *member_name = strdup(cc->lex.token_str);
      
      // First dereference the pointer — unless the auto-deref already loaded it.
      if (!(cc->flags & CCF_RAX) && !(cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF)) {
        ICAdd(cc, IC_DEREF, 0, RT_I64);
      }
      
      // Look up member offset (same as . operator)
      I64 member_offset = 0;
      CHashClass *member_class = NULL;
      CMemberLst *found = NULL;
      
      if (cc->last_expr_class) {
        CMemberLst *member = HostMemberFind(cc->last_expr_class, member_name);
        if (member) {
          member_offset = member->offset;
          found = member;
          member_class = member->member_class;
        } else {
          HostUnknownMember(cc, cc->last_expr_class, member_name, '>');
        }
      }
      
      LexNext(cc);
      
      if (found && member_offset != 0) {
        ICAdd(cc, IC_IMM_I64, member_offset, RT_I64);
        ICAdd(cc, IC_ADD, 0, RT_I64);
      }
      
      cc->last_var_symbol = NULL;
      cc->last_global_var = NULL;
      cc->last_member = found;
      if (found && found->is_array) {
        cc->flags |= CCF_ARRAY;
      } else if (!(cc->flags & CCF_RAX)) {
        DerefDroppingAddressSlot(cc);
        // A scalar-union member (`U32 time;` where U32 is `U32i union U32`) records raw_type=I64 with
        // a sub-word size; use the size for the load/store width so `s.time` is 4 bytes, not 8 (an
        // 8-byte store to a 4-byte field at a struct's tail overruns it — CDate's date/time did).
        U8 mtype = found ? ScalarTypeForSize(found->raw_type, found->size) : RT_I64;
        if (found && cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) cc->ic_tail->arg1_type_pointed_to = mtype;
        if (found && !found->pointed_to_type) cc->last_expr_type = (mtype == RT_F64) ? RT_F64 :
          (mtype == RT_U8 || mtype == RT_U16 || mtype == RT_U32 || mtype == RT_U64) ? RT_U64 : RT_I64;
      }
      cc->last_expr_class = member_class;
      
      free(member_name);
      continue;
    }
    
    // No more postfix operators
    break;
  }
  
  // PE_DEREFERENCE phase (PrsExp.HC:97-118)
  // ALWAYS add IC_DEREF after address computation
  // Assignments will change it to NOP later
  // BUT: Skip if we just processed a parenthesized expression (already dereferenced)
  CIntermediateCode *last_ic = cc->ic_tail;
  if (last_ic && (last_ic->ic_code == IC_ADD || last_ic->ic_code == IC_LEA) && !is_paren_expr && !(cc->flags & (CCF_RAX | CCF_ARRAY))) {
    // Last was IC_ADD or IC_LEA (address of variable)
    // Add IC_DEREF to load the value (PrsExp.HC:116-117)
    ICAdd(cc, IC_DEREF, 0, RT_I64);
    // Type the load like the early auto-deref does, so sub-word variables round-trip with the
    // typed store in IC_ASSIGN (an IC_ADD result is an element/member: keep the I64 default).
    if (last_ic->ic_code == IC_LEA && cc->last_var_symbol)
      cc->ic_tail->arg1_type_pointed_to = cc->last_var_symbol->data_type;
  }

  // No postfix operator consumed it: let a prefix pointer-cast's width reach an outer deref.
  if (cc->cast_elem_type == 0) cc->cast_elem_type = primary_ptr_cast;
  return true;
}


// Binary operator with HolyC numeric promotion: if either side is F64, convert the other
// (IC_TO_F64 on eval-stack slot 0 = right/top, 1 = left) and emit the F64 flavour.
static void EmitBinaryOp(Compiler *cc, U8 iop, U8 fop, U8 lt, U8 rt, bool result_is_bool) {
  if (lt == RT_F64 || rt == RT_F64) {
    if (lt != RT_F64) ICAdd(cc, IC_TO_F64, 1, RT_F64);
    if (rt != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
    ICAdd(cc, fop, 0, RT_F64);
    cc->last_expr_type = result_is_bool ? RT_I64 : RT_F64;
  } else if (lt == RT_U64 || rt == RT_U64) {
    // HolyC: an unsigned operand makes the operation unsigned (divu/remu/sltu/srl).
    U8 uop = iop == IC_DIV ? IC_UDIV : iop == IC_MOD ? IC_UMOD : iop == IC_LESS ? IC_ULESS :
             iop == IC_LESS_EQU ? IC_ULESS_EQU : iop == IC_GREATER ? IC_UGREATER :
             iop == IC_GREATER_EQU ? IC_UGREATER_EQU : iop == IC_SHR ? IC_USHR : iop;
    ICAdd(cc, uop, 0, RT_I64);
    cc->last_expr_type = result_is_bool ? RT_I64 : RT_U64;
  } else {
    ICAdd(cc, iop, 0, RT_I64);
    cc->last_expr_type = RT_I64;
  }
}

// `a`b`: HolyC's power operator (F64), through the runtime's Pow.
// PREC_EXP (tightest binary level in HolyC): `a`b` (power, F64) and `a<<b`/`a>>b` (shifts).
// Binds tighter than `*` `/`, and far tighter than `+` `&` — see Compiler/CInit.HC binary_ops.
static bool ParseExp(Compiler *cc) {
  if (!ParseUnary(cc)) return false;
  while (cc->lex.token == '`' || cc->lex.token == TK_SHL || cc->lex.token == TK_SHR) {
    int op = cc->lex.token;
    U8 lt = cc->last_expr_type;
    if (op == '`') {
      if (cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
      ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
      LexNext(cc);
      if (!ParseUnary(cc)) return false;
      if (cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
      ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
      if (!EmitCallByName(cc, "Pow", 2)) return false;
      ICAdd(cc, IC_CALL_END, 0, RT_I64);
      cc->last_expr_type = RT_F64;
      cc->last_var_symbol = NULL;
      cc->last_global_var = NULL;
    } else {
      LexNext(cc);
      if (!ParseUnary(cc)) return false;
      if (op == TK_SHL) { ICAdd(cc, IC_SHL, 0, RT_I64); }
      else { ICAdd(cc, lt == RT_U64 ? IC_USHR : IC_SHR, 0, RT_I64); }
      cc->last_expr_type = lt == RT_U64 ? RT_U64 : RT_I64;
    }
  }
  return true;
}

static bool ParseMul(Compiler *cc) {
  if (!ParseExp(cc)) return false;
  
  while (cc->lex.token == '*' || cc->lex.token == '/' || cc->lex.token == '%') {
    int op = cc->lex.token;
    U8 lt = cc->last_expr_type;
    LexNext(cc);
    if (!ParseExp(cc)) return false;
    U8 rt = cc->last_expr_type;
    if (op == '*') EmitBinaryOp(cc, IC_MUL, IC_FMUL, lt, rt, false);
    else if (op == '/') EmitBinaryOp(cc, IC_DIV, IC_FDIV, lt, rt, false);
    else EmitBinaryOp(cc, IC_MOD, IC_FMOD, lt, rt, false);
  }
  
  return true;
}


// Element size (bytes) of the current expression if it is a pointer/array, else 0; sets *pointee
// to the pointee type and *depth to the pointer level. Used to scale pointer arithmetic (`p+1`).
static I64 PtrElemInfo(Compiler *cc, U8 *pointee, I64 *depth) {
  *pointee = 0; *depth = 0;
  Symbol *s = cc->last_var_symbol;
  if (s) {
    if (s->is_array) { *pointee = s->data_type; *depth = 1; return s->element_size > 0 ? s->element_size : 8; }
    if (s->pointed_to_type) {
      *pointee = s->pointed_to_type; *depth = s->ptr_depth ? s->ptr_depth : 1;
      if (*depth > 1) return 8;
      CHashClass *pc = (CHashClass *)s->extra;
      if (pc && (pc->type & HTT_CLASS) && !(pc->type & HTT_INTERNAL_TYPE) && pc->size > 0) return pc->size;
      return PrimitiveTypeSize(s->pointed_to_type);
    }
    return 0;
  }
  CHashGlblVar *g = cc->last_global_var;
  if (g) {
    if (g->flags & GVF_ARRAY) { *pointee = (U8)g->raw_type; *depth = 1; return g->element_size > 0 ? g->element_size : 8; }
    if (g->pointed_to_type) {
      *pointee = g->pointed_to_type; *depth = g->ptr_depth ? g->ptr_depth : 1;
      if (*depth > 1) return 8;
      CHashClass *pc = g->var_class;
      if (pc && (pc->type & HTT_CLASS) && !(pc->type & HTT_INTERNAL_TYPE) && pc->size > 0) return pc->size;
      return PrimitiveTypeSize(g->pointed_to_type);
    }
    return 0;
  }
  CMemberLst *m = cc->last_member;
  if (m) {
    if (m->is_array) { *pointee = m->raw_type; *depth = 1; return m->elem_size > 0 ? m->elem_size : 8; }
    if (m->pointed_to_type) {
      *pointee = m->pointed_to_type; *depth = m->ptr_depth ? m->ptr_depth : 1;
      if (*depth > 1) return 8;
      if (m->member_class && m->member_class->size > 0) return m->member_class->size;
      return PrimitiveTypeSize(m->pointed_to_type);
    }
    return 0;
  }
  if (cc->expr_ptr_depth) {
    *pointee = cc->expr_pointee; *depth = cc->expr_ptr_depth;
    if (cc->expr_ptr_depth > 1) return 8;
    return PrimitiveTypeSize(cc->expr_pointee ? cc->expr_pointee : RT_I64);
  }
  return 0;
}

static bool ParseAdd(Compiler *cc) {
  if (!ParseBitwiseOr(cc)) return false;
  while (cc->lex.token == '+' || cc->lex.token == '-') {
    int op = cc->lex.token;
    U8 lt = cc->last_expr_type;
    U8 lpointee = 0; I64 ldepth = 0;
    I64 lsz = PtrElemInfo(cc, &lpointee, &ldepth);
    // Clear stale pointer-tracking so PtrElemInfo(right) reflects only the right operand
    // (an integer literal sets none of these, so it must not inherit the left's pointer state).
    cc->last_var_symbol = NULL; cc->last_global_var = NULL; cc->last_member = NULL; cc->expr_ptr_depth = 0;
    LexNext(cc);
    if (!ParseBitwiseOr(cc)) return false;
    U8 rt = cc->last_expr_type;
    U8 rpointee = 0; I64 rdepth = 0;
    I64 rsz = PtrElemInfo(cc, &rpointee, &rdepth);
    if (lsz > 0 && rsz == 0 && lt != RT_F64 && rt != RT_F64) {
      if (lsz > 1) { ICAdd(cc, IC_IMM_I64, lsz, RT_I64); ICAdd(cc, IC_MUL, 0, RT_I64); }
      ICAdd(cc, op == '+' ? IC_ADD : IC_SUB, 0, RT_I64);
      cc->last_var_symbol = NULL; cc->last_global_var = NULL; cc->last_member = NULL;
      cc->expr_ptr_depth = (U8)ldepth; cc->expr_pointee = lpointee;
      cc->last_expr_type = RT_I64;
    } else if (lsz > 0 && rsz > 0 && op == '-' && lt != RT_F64 && rt != RT_F64) {
      ICAdd(cc, IC_SUB, 0, RT_I64);
      if (lsz > 1) { ICAdd(cc, IC_IMM_I64, lsz, RT_I64); ICAdd(cc, IC_DIV, 0, RT_I64); }
      cc->last_var_symbol = NULL; cc->last_global_var = NULL; cc->last_member = NULL;
      cc->expr_ptr_depth = 0; cc->last_expr_type = RT_I64;
    } else {
      EmitBinaryOp(cc, op == '+' ? IC_ADD : IC_SUB, op == '+' ? IC_FADD : IC_FSUB, lt, rt, false);
      if (lsz == 0 && rsz > 0 && op == '+') { cc->expr_ptr_depth = (U8)rdepth; cc->expr_pointee = rpointee; }
    }
  }
  return true;
}


static bool ParseComparison(Compiler *cc) {
  if (!ParseAdd(cc)) return false;
  
  // HolyC chains relations: `2<=radix<=36` is `2<=radix && radix<=36` with `radix`
  // evaluated once (IC_CHAIN_CMP keeps the middle operand on the stack).
  bool chain = false;
  while (cc->lex.token == '<' || cc->lex.token == '>' ||
         cc->lex.token == TK_LESS_EQU || cc->lex.token == TK_GREATER_EQU) {
    int op = cc->lex.token;
    U8 lt = cc->last_expr_type;
    LexNext(cc);
    if (!ParseAdd(cc)) return false;
    U8 rt = cc->last_expr_type;
    bool more = (cc->lex.token == '<' || cc->lex.token == '>' ||
                 cc->lex.token == TK_LESS_EQU || cc->lex.token == TK_GREATER_EQU);
    int cmp = op == '<' ? IC_LESS : op == '>' ? IC_GREATER : op == TK_LESS_EQU ? IC_LESS_EQU : IC_GREATER_EQU;
    if (more) {
      ICAdd(cc, IC_CHAIN_CMP, cmp, RT_I64);
      if (chain) ICAdd(cc, IC_CHAIN_AND, 0, RT_I64);
    } else {
      switch (op) {
        case '<': EmitBinaryOp(cc, IC_LESS, IC_FLESS, lt, rt, true); break;
        case '>': EmitBinaryOp(cc, IC_GREATER, IC_FGREATER, lt, rt, true); break;
        case TK_LESS_EQU: EmitBinaryOp(cc, IC_LESS_EQU, IC_FLESS_EQU, lt, rt, true); break;
        case TK_GREATER_EQU: EmitBinaryOp(cc, IC_GREATER_EQU, IC_FGREATER_EQU, lt, rt, true); break;
      }
      if (chain) ICAdd(cc, IC_AND, 0, RT_I64);
    }
    chain = chain || more;
    cc->last_expr_type = more ? rt : RT_I64;   // the kept middle operand is the next link's left side
  }
  
  return true;
}


static bool ParseEquality(Compiler *cc) {
  if (!ParseComparison(cc)) return false;
  
  while (cc->lex.token == TK_EQU_EQU || cc->lex.token == TK_NOT_EQU) {
    int op = cc->lex.token;
    U8 lt = cc->last_expr_type;
    LexNext(cc);
    if (!ParseComparison(cc)) return false;
    U8 rt = cc->last_expr_type;
    EmitBinaryOp(cc, op == TK_EQU_EQU ? IC_EQU_EQU : IC_NOT_EQU, op == TK_EQU_EQU ? IC_FEQU_EQU : IC_FNOT_EQU, lt, rt, true);
  }
  
  return true;
}


static bool ParseBitwiseAnd(Compiler *cc) {
  if (!ParseMul(cc)) return false;
  
  while (cc->lex.token == '&') {
    LexNext(cc);
    if (!ParseMul(cc)) return false;
    ICAdd(cc, IC_AND, 0, RT_I64);
  }
  
  return true;
}


static bool ParseBitwiseXor(Compiler *cc) {
  if (!ParseBitwiseAnd(cc)) return false;
  
  while (cc->lex.token == '^') {
    LexNext(cc);
    if (!ParseBitwiseAnd(cc)) return false;
    ICAdd(cc, IC_XOR, 0, RT_I64);
  }
  
  return true;
}


static bool ParseBitwiseOr(Compiler *cc) {
  if (!ParseBitwiseXor(cc)) return false;
  
  while (cc->lex.token == '|') {
    LexNext(cc);
    if (!ParseBitwiseXor(cc)) return false;
    ICAdd(cc, IC_OR, 0, RT_I64);
  }
  
  return true;
}


static bool ParseLogicalAnd(Compiler *cc) {
  if (!ParseEquality(cc)) {
    return false;
  }

  CLabel *false_label = NULL;
  CLabel *end_label = NULL;

  while (cc->lex.token == TK_AND_AND) {
    if (!false_label) {
      false_label = LabelNew(cc, NULL);
      end_label = LabelNew(cc, NULL);
    }

    // If current value is zero, short-circuit the rest
    ICAdd(cc, IC_BR_ZERO, (I64)false_label, RT_I64);

    LexNext(cc);
    if (!ParseEquality(cc)) return false;
  }

  if (false_label) {
    // Check the final operand
    ICAdd(cc, IC_BR_ZERO, (I64)false_label, RT_I64);

    // All operands were non-zero ⇒ result is 1
    ICAdd(cc, IC_IMM_I64, 1, RT_I64);
    ICAdd(cc, IC_JMP, (I64)end_label, RT_I64);

    // False path
    ICAdd(cc, IC_LABEL, (I64)false_label, RT_I64);
    false_label->defined = true;
    ICAdd(cc, IC_IMM_I64, 0, RT_I64);

    // End label
    ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
    end_label->defined = true;
  }

  return true;
}


// `a ^^ b`: HolyC logical xor (no short circuit); operands normalized to 0/1.
static bool ParseLogicalXor(Compiler *cc) {
  if (!ParseLogicalAnd(cc)) return false;
  while (cc->lex.token == TK_XOR_XOR) {
    ICAdd(cc, IC_NOT, 0, RT_I64); ICAdd(cc, IC_NOT, 0, RT_I64);
    LexNext(cc);
    if (!ParseLogicalAnd(cc)) return false;
    ICAdd(cc, IC_NOT, 0, RT_I64); ICAdd(cc, IC_NOT, 0, RT_I64);
    ICAdd(cc, IC_XOR, 0, RT_I64);
    cc->last_expr_type = RT_I64;
  }
  return true;
}

static bool ParseLogicalOr(Compiler *cc) {
  if (!ParseLogicalXor(cc)) {
    return false;
  }

  CLabel *true_label = NULL;
  CLabel *end_label = NULL;

  while (cc->lex.token == TK_OR_OR) {
    if (!true_label) {
      true_label = LabelNew(cc, NULL);
      end_label = LabelNew(cc, NULL);
    }

    // If current value is non-zero, short-circuit to true
    ICAdd(cc, IC_BR_NOT_ZERO, (I64)true_label, RT_I64);

    LexNext(cc);
    if (!ParseLogicalXor(cc)) return false;
  }

  if (true_label) {
    // Evaluate the final operand
    ICAdd(cc, IC_BR_NOT_ZERO, (I64)true_label, RT_I64);

    // All operands were zero ⇒ result is 0
    ICAdd(cc, IC_IMM_I64, 0, RT_I64);
    ICAdd(cc, IC_JMP, (I64)end_label, RT_I64);

    // True path
    ICAdd(cc, IC_LABEL, (I64)true_label, RT_I64);
    true_label->defined = true;
    ICAdd(cc, IC_IMM_I64, 1, RT_I64);

    // End label
    ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
    end_label->defined = true;
  }

  return true;
}


static bool ParseTernary(Compiler *cc) {
  
  // Parse left-hand side (condition)
  if (!ParseLogicalOr(cc)) {
    return false;
  }
  
  
  // Check for ternary operator: condition ? true_expr : false_expr
  if (cc->lex.token == '?') {
    LexNext(cc);
    
    // Generate branches
    CLabel *false_label = LabelNew(cc, NULL);
    CLabel *end_label = LabelNew(cc, NULL);
    
    // Branch to false if condition is zero
    ICAdd(cc, IC_BR_ZERO, (I64)false_label, RT_I64);
    
    // Parse true expression
    if (!ParseExpression(cc)) return false;
    
    // Jump over false expression
    ICAdd(cc, IC_JMP, (I64)end_label, RT_I64);
    
    if (!LexExpect(cc, ':')) return false;
    
    // False label
    ICAdd(cc, IC_LABEL, (I64)false_label, RT_I64);
    false_label->defined = true;
    
    // Parse false expression
    if (!ParseExpression(cc)) return false;
    
    // End label
    ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
    end_label->defined = true;
    
    return true;
  }
  
  return true;
}


// Turn the expression just parsed into an lvalue whose address sits on the eval stack: retract
// the auto-deref, converting it into a push when its producer left the address in a0 only
// (IC_LEA / IC_EVAL_DROP); IC_IMM_I64 / IC_ADD producers already pushed it.
static void EnsureLvalueAddressPushed(Compiler *cc) {
  CIntermediateCode *ic = cc->ic_tail;
  if (ic && ic->ic_code == IC_DEREF) {
    CIntermediateCode *prev = cc->ic_head;
    while (prev && prev->next != ic) prev = prev->next;
    ic->ic_code = (prev && (prev->ic_code == IC_LEA || prev->ic_code == IC_EVAL_DROP)) ? IC_PUSH_ARG : IC_NOP1;
  } else if (ic && ic->ic_code == IC_LEA) {
    ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
  }
}

static bool ParseAssignment(Compiler *cc) {
  
  // Parse left-hand side
  if (!ParseTernary(cc)) {
    return false;
  }
  
  
  // Check for assignment operators (right-associative)
  if (cc->lex.token == '=') {
    // Whole-struct assignment `b = a`: a class INSTANCE (not a pointer/array) larger than one word
    // copies all its bytes, not just the first. Detect it from the LHS before the address is pushed.
    {
      CHashClass *lc = cc->last_expr_class;
      bool lhs_struct_inst =
        lc && (lc->type & HTT_CLASS) && !(lc->type & HTT_INTERNAL_TYPE) && lc->size > 8 && lc->size <= 2040 &&
        ((cc->last_var_symbol && !cc->last_var_symbol->pointed_to_type && !cc->last_var_symbol->is_array) ||
         (cc->last_global_var && !cc->last_global_var->pointed_to_type && !(cc->last_global_var->flags & GVF_ARRAY)));
      if (lhs_struct_inst) {
        I64 nbytes = lc->size;
        EnsureLvalueAddressPushed(cc);         // dst address on the eval stack
        LexNext(cc);                            // '='
        if (!ParseTernary(cc)) return false;    // RHS: the source struct instance
        EnsureLvalueAddressPushed(cc);         // src address on the eval stack (retract its auto-deref)
        CIntermediateCode *bc = ICNew(cc, IC_BLOCK_COPY);
        bc->ic_data = nbytes;
        if (cc->ic_tail) cc->ic_tail->next = bc; else cc->ic_head = bc;
        cc->ic_tail = bc;
        return true;
      }
    }
    // SET CCF_RAX to indicate lvalue (address needed, not value)
    // Match original PrsExp.HC:201-209
    CIntermediateCode *lval_ic = cc->ic_tail;
    U8 store_type = RT_I64;
    if (lval_ic && lval_ic->ic_code == IC_DEREF) {
      store_type = lval_ic->arg1_type_pointed_to;
      // Fall back to a global's own width ONLY when the deref carries no explicit pointed-to type
      // (a bare global array element). A typed-pointer deref — `*(U32*)p`, or `*r` for `U32 *r` —
      // already knows the width; the pointer variable is still in last_global_var here, and using
      // ITS raw_type (RT_I64 for any pointer) stored 8 bytes, clobbering the next 4-7 bytes and
      // faulting width-strict MMIO (e.g. the SiFive test finisher, which only takes 4-byte writes).
      if ((store_type == 0 || store_type == RT_I64) && cc->last_global_var)
        store_type = cc->last_global_var->raw_type ? cc->last_global_var->raw_type : RT_I64;
    }
    EnsureLvalueAddressPushed(cc);
    
    LexNext(cc);
    // The LHS must not leak into the RHS. ParseAdd reads the LEFT operand's pointer info with
    // PtrElemInfo AFTER parsing it, and that keys off last_var_symbol; a numeric constant sets
    // none of these, so it inherits whatever was current. In `p = 0x10000000 + off` that is the
    // assignment target itself, and the offset came out scaled by sizeof(*p) -- which is how
    // RVQspiFlashMap spent weeks writing 0x10040180 instead of 0x10040060 and the port recorded
    // "fctrl.en won't set" as a hardware quirk. ParseAdd already clears this state BETWEEN its
    // two operands for exactly this reason; nothing cleared it before the first one.
    //
    // Safe here because store_type is captured above, before this point, and because `p = p + 4`
    // re-establishes the state when the RHS's own `p` is parsed.
    // tests/exec/cases/e_ptr_assign_const_base.hc pins the four forms.
    cc->last_var_symbol = NULL;
    cc->last_global_var = NULL;
    cc->last_member = NULL;
    cc->expr_ptr_depth = 0;
    if (!ParseAssignment(cc)) return false;
    if (store_type == RT_F64 && cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
    else if (store_type != RT_F64 && cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64);
    
    // Create IC_ASSIGN with store type in arg1_type_pointed_to
    CIntermediateCode *ic = ICNew(cc, IC_ASSIGN);
    ic->res.type.raw_type = RT_I64;
    ic->res.type.mode = MDF_STK;
    ic->arg1_type_pointed_to = store_type;  // Type to store
    
    // Link into IC chain
    if (cc->ic_tail) cc->ic_tail->next = ic;
    else cc->ic_head = ic;
    cc->ic_tail = ic;
    
    return true;
  }
  
  // Compound assignments
  if (cc->lex.token == TK_SHL_EQU || cc->lex.token == TK_SHR_EQU || cc->lex.token == TK_MOD_EQU) {
    int op = cc->lex.token == TK_SHL_EQU ? IC_SHL_EQU : cc->lex.token == TK_SHR_EQU ? IC_SHR_EQU : IC_MOD_EQU;
    LexNext(cc);
    EnsureLvalueAddressPushed(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, op, 0, RT_I64);
    return true;
  }
  if (cc->lex.token == TK_ADD_EQU) {
    bool f64 = (cc->last_expr_type == RT_F64);
    LexNext(cc);
    EnsureLvalueAddressPushed(cc);
    if (!ParseAssignment(cc)) return false;
    if (f64) { if (cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64); ICAdd(cc, IC_FADD_EQU, 0, RT_F64); cc->last_expr_type = RT_F64; }
    else ICAdd(cc, IC_ADD_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_SUB_EQU) {
    bool f64 = (cc->last_expr_type == RT_F64);
    LexNext(cc);
    EnsureLvalueAddressPushed(cc);
    if (!ParseAssignment(cc)) return false;
    if (f64) { if (cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64); ICAdd(cc, IC_FSUB_EQU, 0, RT_F64); cc->last_expr_type = RT_F64; }
    else ICAdd(cc, IC_SUB_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_MUL_EQU) {
    bool f64 = (cc->last_expr_type == RT_F64);
    LexNext(cc);
    EnsureLvalueAddressPushed(cc);
    if (!ParseAssignment(cc)) return false;
    if (f64) { if (cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64); ICAdd(cc, IC_FMUL_EQU, 0, RT_F64); cc->last_expr_type = RT_F64; return true; }
    ICAdd(cc, IC_MUL_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_DIV_EQU) {
    bool f64 = (cc->last_expr_type == RT_F64);
    LexNext(cc);
    EnsureLvalueAddressPushed(cc);
    if (!ParseAssignment(cc)) return false;
    if (f64) { if (cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64); ICAdd(cc, IC_FDIV_EQU, 0, RT_F64); cc->last_expr_type = RT_F64; return true; }
    ICAdd(cc, IC_DIV_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_AND_EQU) {
    LexNext(cc);
    EnsureLvalueAddressPushed(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, IC_AND_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_OR_EQU) {
    LexNext(cc);
    EnsureLvalueAddressPushed(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, IC_OR_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_XOR_EQU) {
    LexNext(cc);
    EnsureLvalueAddressPushed(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, IC_XOR_EQU, 0, RT_I64);
    return true;
  }
  
  return true;
}


bool ParseExpression(Compiler *cc) {
  
  bool result = ParseAssignment(cc);
  
  
  return result;
}

// ----------------------------------------------------------------------------------------------
// PARSER - STATEMENTS
// ----------------------------------------------------------------------------------------------

static bool ParseBlock(Compiler *cc);

static bool ParseIfStatement(Compiler *cc) {
  LexNext(cc); // Skip 'if'
  
  if (!LexExpect(cc, '(')) return false;
  if (!ParseExpression(cc)) return false;
  if (!LexExpect(cc, ')')) return false;
  
  // Create label for false/else branch
  CLabel *else_label = LabelNew(cc, NULL);
  
  // Branch to else_label if condition is zero (false)
  ICAdd(cc, IC_BR_ZERO, (I64)else_label, RT_I64);
  
  // True block
  if (!ParseStatement(cc)) return false;
  
  // Check for else clause
  if (cc->lex.token == KW_ELSE) {
    // Need end label to skip else block
    CLabel *end_label = LabelNew(cc, NULL);
    
    // Jump over else block
    ICAdd(cc, IC_JMP, (I64)end_label, RT_I64);
    
    // Else label (where false branch lands)
    ICAdd(cc, IC_LABEL, (I64)else_label, RT_I64);
    else_label->defined = true;
    
    LexNext(cc); // Skip 'else'
    if (!ParseStatement(cc)) return false;
    
    // End label (after else block)
    ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
    end_label->defined = true;
  } else {
    // No else - else_label is where both paths converge
    ICAdd(cc, IC_LABEL, (I64)else_label, RT_I64);
    else_label->defined = true;
  }
  
  return true;
}


// do { body } while (cond);  — body first, then the test branches back.
static bool ParseDoStatement(Compiler *cc) {
  LexNext(cc); // Skip 'do'
  CLabel *start_label = LabelNew(cc, NULL);
  CLabel *cond_label = LabelNew(cc, NULL);
  CLabel *end_label = LabelNew(cc, NULL);
  CLabel *saved_break = cc->current_break_label;
  CLabel *saved_continue = cc->current_continue_label;
  cc->current_break_label = end_label;
  I64 saved_ltd = cc->loop_try_depth;
  cc->loop_try_depth = cc->try_depth;
  cc->current_continue_label = cond_label;
  ICAdd(cc, IC_LABEL, (I64)start_label, RT_I64);
  start_label->defined = true;
  bool ok = ParseStatement(cc);
  if (ok && cc->lex.token != KW_WHILE) { Error(cc, "Expected 'while' after do body"); ok = false; }
  if (ok) {
    LexNext(cc); // Skip 'while'
    ICAdd(cc, IC_LABEL, (I64)cond_label, RT_I64);
    cond_label->defined = true;
    ok = LexExpect(cc, '(') && ParseExpression(cc) && LexExpect(cc, ')');
  }
  if (ok) {
    ICAdd(cc, IC_BR_NOT_ZERO, (I64)start_label, RT_I64);
    ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
    end_label->defined = true;
    if (cc->lex.token == ';') LexNext(cc);
  }
  cc->current_break_label = saved_break;
  cc->loop_try_depth = saved_ltd;
  cc->current_continue_label = saved_continue;
  return ok;
}

static bool ParseWhileStatement(Compiler *cc) {
  LexNext(cc); // Skip 'while'
  
  CLabel *start_label = LabelNew(cc, NULL);
  CLabel *end_label = LabelNew(cc, NULL);
  
  // Save current loop context
  CLabel *saved_break = cc->current_break_label;
  CLabel *saved_continue = cc->current_continue_label;
  
  // Set new loop context
  cc->current_break_label = end_label;
  I64 saved_ltd = cc->loop_try_depth;
  cc->loop_try_depth = cc->try_depth;
  cc->current_continue_label = start_label;
  
  // Start label
  ICAdd(cc, IC_LABEL, (I64)start_label, RT_I64);
  start_label->defined = true;
  
  if (!LexExpect(cc, '(')) {
    cc->current_break_label = saved_break;
    cc->loop_try_depth = saved_ltd;
    cc->current_continue_label = saved_continue;
    return false;
  }
  if (!ParseExpression(cc)) {
    cc->current_break_label = saved_break;
    cc->loop_try_depth = saved_ltd;
    cc->current_continue_label = saved_continue;
    return false;
  }
  if (!LexExpect(cc, ')')) {
    cc->current_break_label = saved_break;
    cc->loop_try_depth = saved_ltd;
    cc->current_continue_label = saved_continue;
    return false;
  }
  
  // Branch if false (exit loop)
  ICAdd(cc, IC_BR_ZERO, (I64)end_label, RT_I64);
  
  // Loop body
  if (!ParseStatement(cc)) {
    cc->current_break_label = saved_break;
    cc->loop_try_depth = saved_ltd;
    cc->current_continue_label = saved_continue;
    return false;
  }
  
  // Jump back to start
  ICAdd(cc, IC_JMP, (I64)start_label, RT_I64);
  
  // End label
  ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
  end_label->defined = true;
  
  // Restore loop context
  cc->current_break_label = saved_break;
  cc->loop_try_depth = saved_ltd;
  cc->current_continue_label = saved_continue;
  
  return true;
}


static bool ParseForStatement(Compiler *cc) {
  LexNext(cc); // Skip 'for'
  
  if (!LexExpect(cc, '(')) return false;
  
  // Init
  if (cc->lex.token != ';') {
    if (!ParseStatement(cc)) return false;
  } else {
    LexNext(cc);
  }
  
  CLabel *start_label = LabelNew(cc, NULL);
  CLabel *end_label = LabelNew(cc, NULL);
  CLabel *continue_label = LabelNew(cc, NULL);
  
  // Save current loop context
  CLabel *saved_break = cc->current_break_label;
  CLabel *saved_continue = cc->current_continue_label;
  
  // Set new loop context
  cc->current_break_label = end_label;
  I64 saved_ltd = cc->loop_try_depth;
  cc->loop_try_depth = cc->try_depth;
  cc->current_continue_label = continue_label;
  
  // Start label
  ICAdd(cc, IC_LABEL, (I64)start_label, RT_I64);
  start_label->defined = true;
  
  // Condition
  if (cc->lex.token != ';') {
    if (!ParseExpression(cc)) {
      cc->current_break_label = saved_break;
      cc->loop_try_depth = saved_ltd;
      cc->current_continue_label = saved_continue;
      return false;
    }
    ICAdd(cc, IC_BR_ZERO, (I64)end_label, RT_I64);
  }
  
  if (!LexExpect(cc, ';')) {
    cc->current_break_label = saved_break;
    cc->loop_try_depth = saved_ltd;
    cc->current_continue_label = saved_continue;
    return false;
  }
  
  // Increment clause: parse into a side chain now, splice it in after the body (at the
  // continue label) so `for (…; …; i++)` actually increments.
  CIntermediateCode *incr_head = NULL, *incr_tail = NULL;
  if (cc->lex.token != ')') {
    CIntermediateCode *saved_head = cc->ic_head, *saved_tail = cc->ic_tail;
    cc->ic_head = cc->ic_tail = NULL;
    bool ok = ParseExpression(cc);
    if (ok) ICAdd(cc, IC_END_EXP, 0, RT_I64);
    while (ok && cc->lex.token == ',') {   // `i++,dv++`
      LexNext(cc);
      ok = ParseExpression(cc);
      if (ok) ICAdd(cc, IC_END_EXP, 0, RT_I64);
    }
    incr_head = cc->ic_head; incr_tail = cc->ic_tail;
    cc->ic_head = saved_head; cc->ic_tail = saved_tail;
    if (!ok) {
      cc->current_break_label = saved_break;
      cc->loop_try_depth = saved_ltd;
      cc->current_continue_label = saved_continue;
      return false;
    }
  }
  
  if (!LexExpect(cc, ')')) {
    cc->current_break_label = saved_break;
    cc->loop_try_depth = saved_ltd;
    cc->current_continue_label = saved_continue;
    return false;
  }
  
  // Body
  if (!ParseStatement(cc)) {
    cc->current_break_label = saved_break;
    cc->loop_try_depth = saved_ltd;
    cc->current_continue_label = saved_continue;
    return false;
  }
  
  // Continue label (increment)
  ICAdd(cc, IC_LABEL, (I64)continue_label, RT_I64);
  continue_label->defined = true;
  if (incr_head) {
    if (cc->ic_tail) cc->ic_tail->next = incr_head; else cc->ic_head = incr_head;
    incr_head->last = cc->ic_tail;
    cc->ic_tail = incr_tail;
  }
  
  // Jump back to start
  ICAdd(cc, IC_JMP, (I64)start_label, RT_I64);
  
  // End label
  ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
  end_label->defined = true;
  
  // Restore loop context
  cc->current_break_label = saved_break;
  cc->loop_try_depth = saved_ltd;
  cc->current_continue_label = saved_continue;
  
  return true;
}


// sub_switch markers inside a switch body: `start:` (1) / `end:` (2), else 0. Peeks past the ':'.
static int PeekSubMarker(Compiler *cc) {
  if (cc->lex.token != TK_IDENT || !cc->lex.token_str) return 0;
  int kind = strcmp(cc->lex.token_str, "start") == 0 ? 1 : strcmp(cc->lex.token_str, "end") == 0 ? 2 : 0;
  if (!kind) return 0;
  LexPush(cc);
  LexNext(cc);
  bool colon = (cc->lex.token == ':');
  LexPopRestore(cc);
  return colon ? kind : 0;
}
// One case test against the switch temp: branch to `target` when it matches.
static void EmitCaseTest(Compiler *cc, I64 tmp_marker, CSwitchCase *sc, CLabel *target) {
  if (sc->hi == sc->value) {
    ICAdd(cc, IC_LEA, tmp_marker, RT_I64);
    ICAdd(cc, IC_DEREF, 0, RT_I64);
    ICAdd(cc, IC_IMM_I64, sc->value, RT_I64);
    ICAdd(cc, IC_EQU_EQU, 0, RT_I64);
    ICAdd(cc, IC_BR_NOT_ZERO, (I64)target, RT_I64);
  } else {
    CLabel *skip = LabelNew(cc, NULL);
    ICAdd(cc, IC_LEA, tmp_marker, RT_I64);
    ICAdd(cc, IC_DEREF, 0, RT_I64);
    ICAdd(cc, IC_IMM_I64, sc->value, RT_I64);
    ICAdd(cc, IC_GREATER_EQU, 0, RT_I64);
    ICAdd(cc, IC_BR_ZERO, (I64)skip, RT_I64);
    ICAdd(cc, IC_LEA, tmp_marker, RT_I64);
    ICAdd(cc, IC_DEREF, 0, RT_I64);
    ICAdd(cc, IC_IMM_I64, sc->hi, RT_I64);
    ICAdd(cc, IC_LESS_EQU, 0, RT_I64);
    ICAdd(cc, IC_BR_NOT_ZERO, (I64)target, RT_I64);
    ICAdd(cc, IC_LABEL, (I64)skip, RT_I64);
    skip->defined = true;
  }
}

static bool ParseSwitchStatement(Compiler *cc) {
  LexNext(cc); // Skip 'switch'
  bool nobound = (cc->lex.token == '[');   // `switch [x]`: no range check (same code here)
  if (nobound) LexNext(cc);
  else if (!LexExpect(cc, '(')) return false;
  // Keep the switch value in a compiler temp local (patched to a real slot like any local),
  // so the dispatch block can compare it against every case without re-evaluating it.
  I64 tmp_marker = HOLY_LOCAL_MARKER(cc->locals_size);
  cc->locals_size += 8;
  ICAdd(cc, IC_LEA, tmp_marker, RT_I64);
  ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
  if (!ParseExpression(cc)) return false;
  if (!LexExpect(cc, nobound ? ']' : ')')) return false;
  ICAdd(cc, IC_ASSIGN, 0, RT_I64);
  ICAdd(cc, IC_END_EXP, 0, RT_I64);
  if (!LexExpect(cc, '{')) return false;
  CLabel *dispatch_label = LabelNew(cc, NULL);
  ICAdd(cc, IC_JMP, (I64)dispatch_label, RT_I64);  // bodies follow; the tests live after them
  
  // Build case list
  CSwitchCase *cases = NULL;
  CSwitchCase *last_case = NULL;
  CLabel *default_label = NULL;
  CLabel *end_label = LabelNew(cc, NULL);
  
  I64 min_val = 0x7FFFFFFFFFFFFFFFLL;  // I64_MAX
  I64 last_case_val = -1;
  // sub_switch groups: start: block runs before any of its cases, end: block after (on break)
  CLabel *sub_start[8], *sub_dispatch[8], *sub_end[8];
  int sub_n = 0, cur_sub = -1;
  // `start:` blocks NEST (PrsStmt has `start: case KW_ASM: … start: case KW_LOCK:`). A single
  // cur_sub let the inner `start:` overwrite the outer one, so the outer block's sub_end label
  // was never defined and every `break` inside it jumped to an unresolved label — a wild jump.
  // That is what made `asm{}` in the REPL die *after* its arm completed.
  int sub_stack[8], sub_sp = 0;
  I64 max_val = -0x8000000000000000LL; // I64_MIN
  
  // Save break context
  CLabel *saved_break = cc->current_break_label;
  cc->current_break_label = end_label;
  I64 saved_ltd = cc->loop_try_depth;
  cc->loop_try_depth = cc->try_depth;
  
  // Parse cases
  while (cc->lex.token != '}' && cc->lex.token != TK_EOF) {
    int mk = PeekSubMarker(cc);
    if (mk && sub_n < 8) {
      LexNext(cc);  // start / end
      LexNext(cc);  // ':'
      if (mk == 1) {
        cur_sub = sub_n++;
        if (sub_sp < 8) sub_stack[sub_sp++] = cur_sub;
        sub_start[cur_sub] = LabelNew(cc, NULL);
        sub_dispatch[cur_sub] = LabelNew(cc, NULL);
        sub_end[cur_sub] = LabelNew(cc, NULL);
        ICAdd(cc, IC_LABEL, (I64)sub_start[cur_sub], RT_I64);
        sub_start[cur_sub]->defined = true;
        cc->current_break_label = sub_end[cur_sub];
        while (cc->lex.token != KW_CASE && cc->lex.token != KW_DEFAULT &&
               cc->lex.token != '}' && cc->lex.token != TK_EOF && !PeekSubMarker(cc)) {
          if (!ParseStatement(cc)) {
            cc->current_break_label = saved_break;
            cc->loop_try_depth = saved_ltd;
            return false;
          }
        }
        ICAdd(cc, IC_JMP, (I64)sub_dispatch[cur_sub], RT_I64);   // then pick the actual case
      } else {
        // Close the innermost open `start:` block and fall back to the one enclosing it.
        if (sub_sp > 0) {
          int done = sub_stack[--sub_sp];
          ICAdd(cc, IC_LABEL, (I64)sub_end[done], RT_I64);
          sub_end[done]->defined = true;
        }
        cc->current_break_label = sub_sp > 0 ? sub_end[sub_stack[sub_sp - 1]] : end_label;
        cur_sub = sub_sp > 0 ? sub_stack[sub_sp - 1] : -1;
        while (cc->lex.token != KW_CASE && cc->lex.token != KW_DEFAULT &&
               cc->lex.token != '}' && cc->lex.token != TK_EOF && !PeekSubMarker(cc)) {
          if (!ParseStatement(cc)) {
            cc->current_break_label = saved_break;
            cc->loop_try_depth = saved_ltd;
            return false;
          }
        }
        // The end: block is reached by a break out of the sub_switch (or by falling off its
        // last case). When it finishes, control leaves the switch — it must NOT drop into the
        // body of whatever case happens to follow `end:`. Without this a break inside a
        // sub_switch silently ran the next case.
        ICAdd(cc, IC_JMP, (I64)(sub_sp > 0 ? sub_end[sub_stack[sub_sp - 1]] : end_label), RT_I64);
      }
      continue;
    }
    if (cc->lex.token == KW_CASE) {
      LexNext(cc);
      
      // Get case value; `case:` (no value) means one more than the previous case (0 first).
      I64 case_val;
      if (cc->lex.token == ':') {
        case_val = last_case_val + 1;
      } else {
        bool okc = true;
        // Name the identifier when the label is one: `case LK_FILE_LINE:` on a symbol the port
        // does not have read as "Expected integer constant in case", which sent two sessions
        // looking for a constant-folding bug instead of a missing define.
        char *unknown = (cc->lex.token == TK_IDENT && cc->lex.token_str &&
                         !cc->lex.hash_entry) ? strdup(cc->lex.token_str) : NULL;
        case_val = CEOr(cc, 0, &okc);   // `case -1:`, `case 'a':`, `case FLAG|2:`
        if (!okc) {
          if (unknown) {
            char umsg[192];
            snprintf(umsg, sizeof umsg, "Undefined variable '%s' in case", unknown);
            Error(cc, umsg);
          } else {
            Error(cc, "Expected integer constant in case");
          }
          free(unknown);
          cc->current_break_label = saved_break;
          cc->loop_try_depth = saved_ltd;
          return false;
        }
        free(unknown);
      }
      I64 case_hi = case_val;
      if (cc->lex.token == TK_ELLIPSIS) {   // case lo...hi:
        LexNext(cc);
        bool okh = true;
        case_hi = CEOr(cc, 0, &okh);
        if (!okh) {
          Error(cc, "Expected integer constant after '...'");
          cc->current_break_label = saved_break;
          cc->loop_try_depth = saved_ltd;
          return false;
        }
      }
      
      if (!LexExpect(cc, ':')) {
        cc->current_break_label = saved_break;
        cc->loop_try_depth = saved_ltd;
        return false;
      }
      
      // Create case entry
      CSwitchCase *sc = calloc(1, sizeof(CSwitchCase));
      sc->value = case_val;
      sc->hi = case_hi;
      last_case_val = case_hi;
      sc->via = cur_sub >= 0 ? sub_start[cur_sub] : NULL;
      sc->group = cur_sub;
      sc->label = LabelNew(cc, NULL);
      sc->next = NULL;
      
      if (last_case) {
        last_case->next = sc;
      } else {
        cases = sc;
      }
      last_case = sc;
      
      // Generate label for this case
      ICAdd(cc, IC_LABEL, (I64)sc->label, RT_I64);
      sc->label->defined = true;
      
      // Track min/max
      if (case_val < min_val) min_val = case_val;
      if (case_val > max_val) max_val = case_val;
      
      // Parse statements until next case/default/}
      while (cc->lex.token != KW_CASE && cc->lex.token != KW_DEFAULT && 
             cc->lex.token != '}' && cc->lex.token != TK_EOF && !PeekSubMarker(cc)) {
        if (!ParseStatement(cc)) {
          cc->current_break_label = saved_break;
          cc->loop_try_depth = saved_ltd;
          return false;
        }
      }
      
      continue;
    }
    
    if (cc->lex.token == KW_DEFAULT) {
      LexNext(cc);
      
      if (!LexExpect(cc, ':')) {
        cc->current_break_label = saved_break;
        cc->loop_try_depth = saved_ltd;
        return false;
      }
      
      // Create default label
      default_label = LabelNew(cc, NULL);
      ICAdd(cc, IC_LABEL, (I64)default_label, RT_I64);
      default_label->defined = true;
      
      // Parse statements until next case or }
      while (cc->lex.token != KW_CASE && cc->lex.token != '}' && cc->lex.token != TK_EOF && !PeekSubMarker(cc)) {
        if (!ParseStatement(cc)) {
          cc->current_break_label = saved_break;
          cc->loop_try_depth = saved_ltd;
          return false;
        }
      }
      
      continue;
    }
    
    // Unknown token, skip
    LexNext(cc);
  }
  
  if (!LexExpect(cc, '}')) {
    cc->current_break_label = saved_break;
    cc->loop_try_depth = saved_ltd;
    return false;
  }
  
  // Generate jump table (simplified - using if/else chain for now)
  // Full implementation would build actual jump table
  // For now, emit cascading comparisons
  ICAdd(cc, IC_JMP, (I64)end_label, RT_I64);  // fall off the last body
  ICAdd(cc, IC_LABEL, (I64)dispatch_label, RT_I64);
  dispatch_label->defined = true;
  CSwitchCase *sc = cases;
  while (sc) {
    EmitCaseTest(cc, tmp_marker, sc, sc->via ? sc->via : sc->label);
    sc = sc->next;
  }
  
  // Jump to default or end
  if (default_label) {
    ICAdd(cc, IC_JMP, (I64)default_label, RT_I64);
  } else {
    ICAdd(cc, IC_JMP, (I64)end_label, RT_I64);
  }
  // sub_switch groups: after the start: block, pick the actual case.
  for (int g = 0; g < sub_n; g++) {
    ICAdd(cc, IC_LABEL, (I64)sub_dispatch[g], RT_I64);
    sub_dispatch[g]->defined = true;
    for (sc = cases; sc; sc = sc->next)
      if (sc->group == g) EmitCaseTest(cc, tmp_marker, sc, sc->label);
    ICAdd(cc, IC_JMP, (I64)end_label, RT_I64);
  }
  
  // A `start:` block with no matching `end:` still has breaks pointing at its sub_end; define
  // them here (at the switch end) so no label is left unresolved.
  while (sub_sp > 0) {
    int done = sub_stack[--sub_sp];
    if (!sub_end[done]->defined) {
      ICAdd(cc, IC_LABEL, (I64)sub_end[done], RT_I64);
      sub_end[done]->defined = true;
    }
  }
  // End label
  ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
  end_label->defined = true;
  
  // Restore break context
  cc->current_break_label = saved_break;
  cc->loop_try_depth = saved_ltd;
  
  // Free case list
  while (cases) {
    CSwitchCase *next = cases->next;
    free(cases);
    cases = next;
  }
  
  return true;
}


// ---- local aggregate initializers: `T a[N] = {…}`, `T a[] = {…}`, `Cls c = {…}`, `U8 s[N] = "…"` ----
// A global's initializer can be folded into its `data_addr` while parsing; a local's storage is a
// frame slot that does not exist until the function runs, so every element becomes an ordinary
// store statement — the same `IC_LEA slot / IC_PUSH_ARG / <value> / IC_ASSIGN` shape that
// `a[k] = v;` already lowers to, addressed by giving each element its own frame-slot marker.
// Elements the list omits are stored as zero rather than left holding whatever the frame did.

// The frame slot at `base_pos + byte_off` as an assignment destination.
static void LocalInitDst(Compiler *cc, I64 base_pos, I64 byte_off) {
  ICAdd(cc, IC_LEA, HOLY_LOCAL_MARKER(base_pos + byte_off), RT_I64);
  ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
}

// Close the store opened by LocalInitDst; `store_type` picks the sb/sh/sw/sd/fsd width.
static void LocalInitStore(Compiler *cc, U8 store_type) {
  CIntermediateCode *ic = ICNew(cc, IC_ASSIGN);
  ic->res.type.raw_type = RT_I64;
  ic->res.type.mode = MDF_STK;
  ic->arg1_type_pointed_to = store_type;
  if (cc->ic_tail) cc->ic_tail->next = ic;
  else cc->ic_head = ic;
  cc->ic_tail = ic;
  ICAdd(cc, IC_END_EXP, 0, RT_I64);
}

static void LocalInitImm(Compiler *cc, I64 base_pos, I64 byte_off, U8 store_type, I64 v) {
  LocalInitDst(cc, base_pos, byte_off);
  ICAdd(cc, IC_IMM_I64, v, RT_I64);
  if (store_type == RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
  LocalInitStore(cc, store_type);
}

// Zero `nbytes` at `byte_off`, eight at a time where the offset allows it. A local's slot base is
// 8-aligned, so the wide stores are aligned whenever their offset is.
static void LocalInitZeroRange(Compiler *cc, I64 base_pos, I64 byte_off, I64 nbytes) {
  I64 i = 0;
  while (i < nbytes) {
    if (((byte_off + i) & 7) == 0 && nbytes - i >= 8) {
      LocalInitImm(cc, base_pos, byte_off + i, RT_I64, 0);
      i += 8;
    } else {
      LocalInitImm(cc, base_pos, byte_off + i, RT_U8, 0);
      i++;
    }
  }
}

// `U8 s[N] = "abc"` — copy the literal's bytes and its NUL into the slot, then zero the tail.
// (The scalar path this replaces stored the literal's ADDRESS into s[0] and dropped the string.)
static void LocalInitString(Compiler *cc, I64 base_pos, I64 byte_off, I64 size,
                            const char *s, I64 slen) {
  I64 i = 0;
  for (; i < slen && i < size - 1; i++) LocalInitImm(cc, base_pos, byte_off + i, RT_U8, (U8)s[i]);
  if (i < size) {
    LocalInitImm(cc, base_pos, byte_off + i, RT_U8, 0);
    i++;
  }
  if (i < size) LocalInitZeroRange(cc, base_pos, byte_off + i, size - i);
}

// One initializer element at `byte_off`. A non-NULL `cls` means the element is a class instance,
// so a nested `{…}` fills it member-wise (mirroring InitAggregateElement's global-side walk).
static bool ParseLocalInitElement(Compiler *cc, I64 base_pos, I64 byte_off, CHashClass *cls,
                                  U8 raw_type, I64 size, bool is_ptr) {
  if (cc->lex.token == '{') {
    if (!cls) { Error(cc, "Nested initializer for a non-class element"); return false; }
    LexNext(cc);
    I64 filled_to = 0;
    for (CMemberLst *m = cls->member_lst; m && cc->lex.token != '}'; m = m->next) {
      CHashClass *mcls = (!m->pointed_to_type && !m->is_array) ? m->member_class : NULL;
      I64 esz = m->elem_size > 0 ? m->elem_size : 8;
      bool str_member = (cc->lex.token == TK_STR && !m->pointed_to_type && esz == 1);
      if (m->is_array && !str_member && m->size > esz) {
        // An array member takes its extent's worth of consecutive elements, or its own `{…}`.
        bool sub = (cc->lex.token == '{');
        if (sub) LexNext(cc);
        I64 cnt = m->size / esz;
        CHashClass *ecls = (!m->pointed_to_type) ? m->member_class : NULL;
        I64 k = 0;
        for (; k < cnt && cc->lex.token != '}'; k++) {
          if (!ParseLocalInitElement(cc, base_pos, byte_off + m->offset + k * esz, ecls,
                                     m->raw_type, esz, m->pointed_to_type != 0)) return false;
          if (k + 1 < cnt) { if (cc->lex.token == ',') LexNext(cc); else { k++; break; } }
        }
        if (k < cnt) LocalInitZeroRange(cc, base_pos, byte_off + m->offset + k * esz, (cnt - k) * esz);
        if (sub && !LexExpect(cc, '}')) return false;
      } else if (!ParseLocalInitElement(cc, base_pos, byte_off + m->offset, mcls, m->raw_type,
                                        m->size, m->pointed_to_type != 0)) return false;
      filled_to = m->offset + m->size;
      if (cc->lex.token == ',') LexNext(cc); else break;
    }
    if (filled_to < size) LocalInitZeroRange(cc, base_pos, byte_off + filled_to, size - filled_to);
    return LexExpect(cc, '}');
  }

  // A string into a byte array member/element copies bytes; into a pointer it is an address.
  if (cc->lex.token == TK_STR && !is_ptr && size > 1 && PrimitiveTypeSize(raw_type) <= 1) {
    const char *s = cc->lex.token_str ? cc->lex.token_str : "";
    LocalInitString(cc, base_pos, byte_off, size, s, cc->lex.token_str_len);
    LexNext(cc);
    return true;
  }

  U8 store_type = is_ptr ? RT_I64 : ScalarTypeForSize(raw_type, size);
  LocalInitDst(cc, base_pos, byte_off);
  if (!ParseAssignment(cc)) return false;
  if (store_type == RT_F64 && cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
  else if (store_type != RT_F64 && cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64);
  LocalInitStore(cc, store_type);
  cc->last_var_symbol = NULL;
  return true;
}

static bool ParseLocalAggregateInit(Compiler *cc, Symbol *sym, U8 var_type, CHashClass *decl_class) {
  I64 base_pos = HOLY_LOCAL_MARKER_POS(sym->offset);
  bool braced = (cc->lex.token == '{');
  I64 elem_size = sym->is_array ? (sym->element_size > 0 ? sym->element_size : 8) : sym->size;
  bool elem_is_ptr = sym->pointed_to_type != 0;
  CHashClass *cls = elem_is_ptr ? NULL : decl_class;

  if (!sym->is_array)
    return ParseLocalInitElement(cc, base_pos, 0, cls, var_type, sym->size, elem_is_ptr);

  // `U8 s[N] = "…"`: the whole array takes the literal, not one element.
  if (cc->lex.token == TK_STR && !elem_is_ptr && elem_size == 1) {
    const char *s = cc->lex.token_str ? cc->lex.token_str : "";
    LocalInitString(cc, base_pos, 0, sym->size, s, cc->lex.token_str_len);
    LexNext(cc);
    return true;
  }

  if (braced) LexNext(cc);
  I64 total = sym->array_size > 0 ? sym->array_size : 1;
  // Row width for a nested-brace multi-dim initializer `{{…},{…}}`: elements per outermost group.
  I64 row = (sym->ndims > 1 && elem_size > 0) ? sym->dim_stride[0] / elem_size : 0;
  I64 idx = 0;
  while (cc->lex.token != (braced ? '}' : ';') && cc->lex.token != TK_EOF) {
    if (sym->ndims > 1 && cc->lex.token == '{' && row > 0) {
      // A braced row fills up to `row` flat elements; a short row zero-pads to the next boundary.
      LexNext(cc);
      I64 rstart = idx;
      while (cc->lex.token != '}' && cc->lex.token != TK_EOF && idx < rstart + row) {
        if (idx >= total) { Error(cc, "Too many initializers"); return false; }
        if (!ParseLocalInitElement(cc, base_pos, idx * elem_size, cls, var_type, elem_size, elem_is_ptr))
          return false;
        idx++;
        if (cc->lex.token == ',') LexNext(cc); else break;
      }
      if (!LexExpect(cc, '}')) return false;
      I64 rend = rstart + row < total ? rstart + row : total;
      if (idx < rend) LocalInitZeroRange(cc, base_pos, idx * elem_size, (rend - idx) * elem_size);
      idx = rend;
    } else {
      if (idx >= total) { Error(cc, "Too many initializers"); return false; }
      if (!ParseLocalInitElement(cc, base_pos, idx * elem_size, cls, var_type, elem_size, elem_is_ptr))
        return false;
      idx++;
    }
    if (cc->lex.token == ',') LexNext(cc); else break;
  }
  if (idx < total) LocalInitZeroRange(cc, base_pos, idx * elem_size, (total - idx) * elem_size);
  return braced ? LexExpect(cc, '}') : true;
}

static bool ParseVariableDeclWithName(Compiler *cc, U8 type, const char *var_name) {
  // type name;
  // type name = expr;
  // type name[size];
  // type name, name2, name3 = expr;
  // var_name is the first variable name, current token should be '=', '[', ',', or ';'
  
  // Preserve the class associated with this declaration (if any)
  CHashClass *decl_class = cc->last_type_class;

  // Loop to handle comma-separated declarations
  do {
    char *name = strdup(var_name);
    
    // Define symbol
    Symbol *sym = SymbolDefine(cc, name, SYM_VAR);
    sym->data_type = type;
    sym->pointed_to_type = cc->last_pointed_to_type;  // Save pointed-to type
    sym->ptr_depth = cc->last_ptr_depth;
    // Scalar-union pointees (`U32i union U32`) may record RT_I64 with size 4 — match members.
    if (sym->pointed_to_type && decl_class && decl_class->size > 0)
      sym->pointed_to_type = ScalarTypeForSize(sym->pointed_to_type, decl_class->size);
    if (cc->last_pointed_to_type) sym->data_type = RT_I64;  // the variable itself is a pointer: 8-byte loads/stores
    sym->extra = decl_class;
    
    // Determine base size
    int base_size;
    if (decl_class) {
      base_size = (int)decl_class->size;
      if (base_size <= 0) base_size = 8;
    } else {
      switch (type) {
        case RT_I8: case RT_U8: base_size = 1; break;
        case RT_I16: case RT_U16: base_size = 2; break;
        case RT_I32: case RT_U32: base_size = 4; break;
        default: base_size = 8; break;
      }
    }
    
    if (cc->last_pointed_to_type) base_size = 8;   // the variable itself is a pointer
    // Initialize array metadata
    sym->is_array = false;
    sym->array_size = 0;
    sym->element_size = base_size;
    
    // Handle arrays
    int total_size = base_size;
    if (cc->lex.token == '[') {
      // T name[N][M]...: flat storage; subscript k advances by dim_stride[k] bytes.
      I64 dims[4];
      int nd = 0;
      bool infer_first = false;
      while (cc->lex.token == '[') {
        LexNext(cc);  // Skip '['
        I64 dimv = 0;
        if (nd == 0 && cc->lex.token == ']') {
          infer_first = true;      // `T a[] = {…}`: extent counted from the initializer below
        } else if (!ParseConstDim(cc, &dimv)) {
          free(name);
          return false;
        }
        if (nd < 4) dims[nd] = dimv;
        nd++;
        if (!LexExpect(cc, ']')) {
          free(name);
          return false;
        }
      }
      if (nd > 4) {
        free(name);
        Error(cc, "Too many array dimensions (max 4)");
        return false;
      }
      if (infer_first) {
        // Count the initializer's top-level elements (rows, for `T a[][M]`) without consuming it.
        I64 n = 0;
        if (cc->lex.token == '=') {
          LexPush(cc);
          LexNext(cc);
          if (cc->lex.token == '{') n = CountAggregateElements(cc);
          else if (cc->lex.token == TK_STR && base_size == 1) n = cc->lex.token_str_len + 1;
          LexPopRestore(cc);
        }
        if (n <= 0) {
          free(name);
          Error(cc, "Expected constant array size");
          return false;
        }
        dims[0] = n;
      }
      I64 total = 1;
      for (int k = 0; k < nd; k++) total *= dims[k];
      sym->is_array = true;
      sym->array_size = total;
      sym->element_size = base_size;
      sym->ndims = nd;
      for (int k = 0; k < nd; k++) {
        I64 st = base_size;
        for (int j = k + 1; j < nd; j++) st *= dims[j];
        sym->dim_stride[k] = st;
      }
      total_size = (int)(base_size * total);
    }
    
    sym->size = total_size;
    
    // Allocate on stack (round up to 8-byte alignment)
    int aligned_size = (total_size + 7) & ~7;
    
    // Mark the position in the locals area (before incrementing locals_size)
    // Use NEGATIVE marker to avoid collision with real values
    sym->offset = HOLY_LOCAL_MARKER(cc->locals_size);  // Temporary: -10000-position marker
    
    cc->locals_size += aligned_size;
    
    // Handle initialization: I64 a = 5;
    if (cc->lex.token == '=') {
      LexNext(cc);
      
      // Aggregate initializer: a braced list, a class instance's `{…}`, or a string literal
      // filling a byte array. Each element becomes its own store into the frame slot.
      bool aggregate = (cc->lex.token == '{') ||
                       (sym->is_array && cc->lex.token == TK_STR && !sym->pointed_to_type &&
                        sym->element_size == 1 && sym->size > 1);
      if (aggregate) {
        if (!ParseLocalAggregateInit(cc, sym, type, decl_class)) {
          free(name);
          return false;
        }
        cc->last_var_symbol = NULL;
        cc->last_type_class = decl_class;
      } else {
      
      // Implement initialization: I64 a = 5;
      // Use the exact same pattern as regular assignment: LEA, PUSH_ARG, ParseExpression, ASSIGN
      // We need to push the address to preserve it before parsing the RHS
      ICAdd(cc, IC_LEA, sym->offset, RT_I64);
      ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
      
      // Parse the value expression
      if (!ParseExpression(cc)) {
        free(name);
        return false;
      }
      if (sym->data_type == RT_F64 && !sym->pointed_to_type && cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
      else if (!(sym->data_type == RT_F64 && !sym->pointed_to_type) && cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64);
      
      // Create IC_ASSIGN - ParseAssignment does this, but we do it manually here
      CIntermediateCode *ic = ICNew(cc, IC_ASSIGN);
      ic->res.type.raw_type = RT_I64;
      ic->res.type.mode = MDF_STK;
      ic->arg1_type_pointed_to = sym->data_type;
      
      // Link into IC chain
      if (cc->ic_tail) cc->ic_tail->next = ic;
      else cc->ic_head = ic;
      cc->ic_tail = ic;
      
      ICAdd(cc, IC_END_EXP, 0, RT_I64);  // initializer is a statement: drop the value
      cc->last_var_symbol = NULL;
      }
    }
    
    // Restore declaration class for subsequent comma-separated variables
    cc->last_type_class = decl_class;

    free(name);
    
    // Check for comma (more variables) or semicolon/comma (end)
    if (cc->lex.token == ',') {
      LexNext(cc);
      
      // Check if it's another variable or end of statement (`U8 *src=_src,*dst=_src;`)
      SkipRegQualifier(cc);
      cc->last_pointed_to_type = 0;
      cc->last_ptr_depth = 0;
      while (cc->lex.token == '*') {
        cc->last_pointed_to_type = type;
        cc->last_ptr_depth++;
        LexNext(cc);
      }
      if (cc->lex.token == TK_IDENT) {
        var_name = cc->lex.token_str;
        LexNext(cc);
        continue;  // Parse next variable in list
      } else {
        // Comma at end (statement separator)
        return true;
      }
    } else if (cc->lex.token == ';') {
      LexNext(cc);
      return true;
    } else {
      // No semicolon - might be end of block, be lenient
      return true;
    }
  } while (true);
  
  return true;  // Should not reach here
}

static bool ParseExpressionStatement(Compiler *cc) {
  
  // Parse expression (includes assignment now)
  if (!ParseExpression(cc)) {
    return false;
  }
  
  
  ICAdd(cc, IC_END_EXP, 0, RT_I64);
  
  // Semicolon or comma allowed
  if (cc->lex.token == ';') {
    LexNext(cc);
  } else if (cc->lex.token != ',' && cc->lex.token != '}' && cc->lex.token != TK_EOF) {
    Error(cc, "Expected ';' or ','");
    return false;
  }
  
  return true;
}


// ----------------------------------------------------------------------------------------------
// Native RISC-V assembler for asm{} blocks. The kernel's low-level primitives are written directly
// in RISC-V opcodes (native RV64, the ordinary calling convention: args in a0..a7, return in a0) and
// assembled here — NOT translated from x86. Supports a labeled function per block: register/mnemonic
// operands, local labels, branches/jumps resolved to PC-relative offsets. Anything unsupported makes
// TryAssembleRiscV return false and the caller skips the block (falling back to the runtime override).
// ----------------------------------------------------------------------------------------------
static int RvDigits(const char *p) { int v=0; if(!*p) return -1; for(;*p;p++){ if(*p<'0'||*p>'9') return -1; v=v*10+(*p-'0'); } return v; }
static void RvLowerCopy(char *dst, const char *src, int cap) {
  int i = 0;
  if (!src) { if (cap > 0) dst[0] = 0; return; }
  for (; src[i] && i < cap - 1; i++) {
    char c = src[i];
    if (c >= 'A' && c <= 'Z') c = (char)(c + 32);
    dst[i] = c;
  }
  dst[i] = 0;
}
static int RvRegNum(const char *n) {
  if (!n) return -1;
  if (!strcmp(n,"zero")||!strcmp(n,"x0")) return 0;
  if (!strcmp(n,"ra")) return 1;   if (!strcmp(n,"sp")) return 2;   if (!strcmp(n,"gp")) return 3;
  if (!strcmp(n,"tp")) return 4;   if (!strcmp(n,"fp")||!strcmp(n,"s0")) return 8;   if (!strcmp(n,"s1")) return 9;
  if (n[0]=='t') { int k=RvDigits(n+1); if (k>=0&&k<=2) return 5+k; if (k>=3&&k<=6) return 28+(k-3); }
  if (n[0]=='a' && n[1]) { int k=RvDigits(n+1); if (k>=0&&k<=7) return 10+k; }
  if (n[0]=='s' && n[1]) { int k=RvDigits(n+1); if (k>=2&&k<=11) return 16+k; }   // s2..s11 = x18..x27
  if (n[0]=='x') { int k=RvDigits(n+1); if (k>=0&&k<=31) return k; }
  return -1;
}
// Float register names (RV64D ABI): ft0-7=f0-7, fs0-1=f8-9, fa0-7=f10-17, fs2-11=f18-27, ft8-11=f28-31, fN raw.
static int RvFRegNum(const char *n) {
  if (!n || n[0]!='f') return -1;
  if (n[1]=='a') { int k=RvDigits(n+2); if (k>=0&&k<=7) return 10+k; }
  if (n[1]=='t') { int k=RvDigits(n+2); if (k>=0&&k<=7) return k; if (k>=8&&k<=11) return 28+(k-8); }
  if (n[1]=='s') { int k=RvDigits(n+2); if (k>=0&&k<=1) return 8+k; if (k>=2&&k<=11) return 16+k; }
  { int k=RvDigits(n+1); if (k>=0&&k<=31) return k; }
  return -1;
}
static U32 RvR(U32 f7,U32 f3,int rd,int rs1,int rs2){ return 0x33u|(rd<<7)|(f3<<12)|(rs1<<15)|(rs2<<20)|(f7<<25); }
static U32 RvI(U32 f3,int rd,int rs1,int imm){ return 0x13u|(rd<<7)|(f3<<12)|(rs1<<15)|(((U32)imm&0xFFF)<<20); }
static U32 RvIw(U32 f3,int rd,int rs1,int imm){ return 0x1Bu|(rd<<7)|(f3<<12)|(rs1<<15)|(((U32)imm&0xFFF)<<20); }
static U32 RvRw(U32 f7,U32 f3,int rd,int rs1,int rs2){ return 0x3Bu|(rd<<7)|(f3<<12)|(rs1<<15)|(rs2<<20)|(f7<<25); }
static U32 RvShiftW(U32 f3,U32 f7,int rd,int rs1,int sh){ return 0x1Bu|(rd<<7)|(f3<<12)|(rs1<<15)|(((U32)sh&0x1F)<<20)|(f7<<25); }
// fence pred/succ ordering mask: letters i(8) o(4) r(2) w(1); e.g. "rw"=3, "iorw"=15. -1 if any bad letter.
static int RvFenceMask(const char *s){ int m=0; if(!s||!s[0]) return -1; for(int i=0;s[i];i++){ char c=s[i]|0x20; if(c=='i')m|=8; else if(c=='o')m|=4; else if(c=='r')m|=2; else if(c=='w')m|=1; else return -1; } return m; }
static U32 RvShift(U32 f3,U32 hi6,int rd,int rs1,int sh){ return 0x13u|(rd<<7)|(f3<<12)|(rs1<<15)|(((U32)sh&0x3F)<<20)|(hi6<<26); }
static U32 RvLoad(U32 f3,int rd,int imm,int rs1){ return 0x03u|(rd<<7)|(f3<<12)|(rs1<<15)|(((U32)imm&0xFFF)<<20); }
static U32 RvStore(U32 f3,int rs2,int imm,int rs1){ return 0x23u|(((U32)imm&0x1F)<<7)|(f3<<12)|(rs1<<15)|(rs2<<20)|((((U32)imm>>5)&0x7F)<<25); }
// FP load/store: value reg is an FPR; f3=2 for .w (flw/fsw), 3 for .d (fld/fsd).
static U32 RvFLoad(U32 f3,int rd,int imm,int rs1){ return 0x07u|(rd<<7)|(f3<<12)|(rs1<<15)|(((U32)imm&0xFFF)<<20); }
static U32 RvFStore(U32 f3,int rs2,int imm,int rs1){ return 0x27u|(((U32)imm&0x1F)<<7)|(f3<<12)|(rs1<<15)|(rs2<<20)|((((U32)imm>>5)&0x7F)<<25); }
static U32 RvBr(U32 f3,int rs1,int rs2,int off){ return 0x63u|(((U32)(off>>11)&1)<<7)|(((U32)(off>>1)&0xF)<<8)|(f3<<12)|(rs1<<15)|(rs2<<20)|(((U32)(off>>5)&0x3F)<<25)|(((U32)(off>>12)&1)<<31); }
static U32 RvJ(int rd,int off){ return 0x6Fu|(rd<<7)|(((U32)(off>>12)&0xFF)<<12)|(((U32)(off>>11)&1)<<20)|(((U32)(off>>1)&0x3FF)<<21)|(((U32)(off>>20)&1)<<31); }
static U32 RvJalr(int rd,int rs1,int imm){ return 0x67u|(rd<<7)|(0u<<12)|(rs1<<15)|(((U32)imm&0xFFF)<<20); }
static U32 RvU(U32 opc,int rd,int imm20){ return opc|(rd<<7)|(((U32)imm20&0xFFFFFu)<<12); }
static U32 RvA(U32 f5,U32 aqrl,U32 f3,int rd,int rs1,int rs2){ return 0x2Fu|(rd<<7)|(f3<<12)|(rs1<<15)|(rs2<<20)|(aqrl<<25)|(f5<<27); }

typedef struct { char mn[16]; int rd,rs1,rs2,imm,rm; char label[48]; int kind; } RvI2;  // kind: 0 none,1 branch,2 jump,3 call,4 la-hi (auipc),5 la-lo (addi); rm=rounding mode (default 7=dyn)
// Parse an optional trailing ", <rm>" rounding mode. Returns rm code (0..7) or -1 if none.
// rne=0 rtz=1 rdn=2 rup=3 rmm=4 dyn=7. Errors on a bad name after the comma.
static int RvParseOptRm(Compiler *cc) {
  if (cc->lex.token != ',') return -1;
  LexNext(cc);
  if (cc->lex.token != TK_IDENT) { Error(cc, "expected rounding mode after ','"); return -1; }
  char r[8]; RvLowerCopy(r, cc->lex.token_str, 8);
  int code = -1;
  if (!strcmp(r,"rne")) code=0; else if (!strcmp(r,"rtz")) code=1; else if (!strcmp(r,"rdn")) code=2;
  else if (!strcmp(r,"rup")) code=3; else if (!strcmp(r,"rmm")) code=4; else if (!strcmp(r,"dyn")) code=7;
  else { Error(cc, "bad rounding mode (rne/rtz/rdn/rup/rmm/dyn)"); return -1; }
  LexNext(cc);
  return code;
}

// Parse one register token (IDENT); returns reg num or -1. Case-insensitive ABI names.
static int RvRegTok(Compiler *cc) {
  if (cc->lex.token != TK_IDENT) return -1;
  char buf[16]; RvLowerCopy(buf, cc->lex.token_str, 16);
  int r = RvRegNum(buf); LexNext(cc); return r;
}
// Parse one float register token; returns 0-31 or -1.
static int RvFRegTok(Compiler *cc) {
  if (cc->lex.token != TK_IDENT) return -1;
  char buf[16]; RvLowerCopy(buf, cc->lex.token_str, 16);
  int r = RvFRegNum(buf); LexNext(cc); return r;
}
// Append one assembled instruction entry (used by the lifp / wide-li expansion). Returns false if full.
static bool RvPushI(RvI2 *ins, int *nins, const char *mn, int rd, int rs1, int imm) {
  if (*nins >= 256) return false;
  RvI2 *I = &ins[*nins];
  { char *_p=(char*)I; for(unsigned _j=0;_j<sizeof(RvI2);_j++) _p[_j]=0; }
  { int _i=0; for(;mn[_i]&&_i<15;_i++) I->mn[_i]=mn[_i]; I->mn[_i]=0; }
  I->rd=rd; I->rs1=rs1; I->imm=imm;
  (*nins)++; return true;
}
static bool RvPushR(RvI2 *ins, int *nins, const char *mn, int rd, int rs1, int rs2) {
  if (*nins >= 256) return false;
  RvI2 *I = &ins[*nins];
  { char *_p=(char*)I; for(unsigned _j=0;_j<sizeof(RvI2);_j++) _p[_j]=0; }
  { int _i=0; for(;mn[_i]&&_i<15;_i++) I->mn[_i]=mn[_i]; I->mn[_i]=0; }
  I->rd=rd; I->rs1=rs1; I->rs2=rs2;
  (*nins)++; return true;
}
// Expand li rd,imm outside ±2047. 32-bit values follow GNU as (lui+addiw / specials); wider
// constants use EmitLoadImm64-style lui+addi (+ slli/srli zext when U32 bit31 set).
static bool RvExpandLi64(RvI2 *ins, int *nins, int rd, I64 v) {
  I64 lo32 = (I64)(I32)(U32)(v & 0xFFFFFFFF);
  I64 hi32 = (v - lo32) >> 32;
  if (hi32 == 0 && lo32 < 0) hi32 = 0;   /* positive U32 with bit31 */
  Bool fits_i32 = (v == lo32);
  Bool fits_u32 = (v >= 0 && v <= 0xFFFFFFFFLL);
  if (!fits_i32 && !fits_u32) {
    int scratch = 5; /* t0 */
    if (rd == scratch) scratch = 6; /* t1 */
    I64 hi = (I64)(I32)(U32)((v >> 32) & 0xFFFFFFFF);
    I64 hh = (hi + 0x800) >> 12, hl = hi - (hh << 12);
    if (!RvPushI(ins, nins, "lui", rd, 0, (int)(hh & 0xFFFFF))) return false;
    if (hl && !RvPushI(ins, nins, "addi", rd, rd, (int)hl)) return false;
    if (!RvPushI(ins, nins, "slli", rd, rd, 32)) return false;
    I64 lh = (lo32 + 0x800) >> 12, ll = lo32 - (lh << 12);
    if (!RvPushI(ins, nins, "lui", scratch, 0, (int)(lh & 0xFFFFF))) return false;
    if (ll && !RvPushI(ins, nins, "addi", scratch, scratch, (int)ll)) return false;
    if (lo32 < 0) {
      if (!RvPushI(ins, nins, "slli", scratch, scratch, 32)) return false;
      if (!RvPushI(ins, nins, "srli", scratch, scratch, 32)) return false;
    }
    return RvPushR(ins, nins, "add", rd, rd, scratch);
  }
  {
    I64 hi = (lo32 + 0x800) >> 12, lo = lo32 - (hi << 12);
    if (!RvPushI(ins, nins, "lui", rd, 0, (int)(hi & 0xFFFFF))) return false;
    if (lo && !RvPushI(ins, nins, "addi", rd, rd, (int)lo)) return false;
    if (!fits_i32) {
      if (!RvPushI(ins, nins, "slli", rd, rd, 32)) return false;
      if (!RvPushI(ins, nins, "srli", rd, rd, 32)) return false;
    }
  }
  return true;
}
static bool RvExpandLiGas32(RvI2 *ins, int *nins, int rd, I64 v) {
  I64 hi, lo;
  if (v == (1LL << 31)) {
    if (!RvPushI(ins, nins, "addiw", rd, 0, 1)) return false;
    return RvPushI(ins, nins, "slli", rd, rd, 31);
  }
  if (v == (I64)(I32)0x80000000)
    return RvPushI(ins, nins, "lui", rd, 0, 0x80000);
  if (v == 4294967295LL || v == (I64)(U32)0xFFFFFFFF) {
    if (!RvPushI(ins, nins, "addiw", rd, 0, 1)) return false;
    if (!RvPushI(ins, nins, "slli", rd, rd, 32)) return false;
    return RvPushI(ins, nins, "addiw", rd, rd, -1);
  }
  if (v < -2147483648LL || v > 2147483647LL)
    return false;
  hi = (v + 0x800) >> 12;
  lo = v - (hi << 12);
  if (lo == 0)
    return RvPushI(ins, nins, "lui", rd, 0, (int)(hi & 0xFFFFF));
  if (!RvPushI(ins, nins, "lui", rd, 0, (int)(hi & 0xFFFFF))) return false;
  return RvPushI(ins, nins, "addiw", rd, rd, (int)lo);
}
static bool RvExpandLi(RvI2 *ins, int *nins, int rd, I64 v) {
  if (RvExpandLiGas32(ins, nins, rd, v))
    return true;
  return RvExpandLi64(ins, nins, rd, v);
}
static int RvCsrNum(const char *n) {
  if (!n) return -1;
  if (!strcmp(n,"sstatus")) return 0x100;
  if (!strcmp(n,"sie")) return 0x104;
  if (!strcmp(n,"stvec")) return 0x105;
  if (!strcmp(n,"sscratch")) return 0x140;
  if (!strcmp(n,"sepc")) return 0x141;
  if (!strcmp(n,"scause")) return 0x142;
  if (!strcmp(n,"stval")) return 0x143;
  if (!strcmp(n,"sip")) return 0x144;
  if (!strcmp(n,"satp")) return 0x180;
  if (!strcmp(n,"mstatus")) return 0x300;
  if (!strcmp(n,"misa")) return 0x301;
  if (!strcmp(n,"medeleg")) return 0x302;
  if (!strcmp(n,"mideleg")) return 0x303;
  if (!strcmp(n,"mie")) return 0x304;
  if (!strcmp(n,"mtvec")) return 0x305;
  if (!strcmp(n,"mcounteren")) return 0x306;
  if (!strcmp(n,"mscratch")) return 0x340;
  if (!strcmp(n,"mepc")) return 0x341;
  if (!strcmp(n,"mcause")) return 0x342;
  if (!strcmp(n,"mtval")) return 0x343;
  if (!strcmp(n,"mip")) return 0x344;
  if (!strcmp(n,"mcycle")) return 0xB00;
  if (!strcmp(n,"minstret")) return 0xB02;
  if (!strcmp(n,"cycle")) return 0xC00;
  if (!strcmp(n,"time")) return 0xC01;
  if (!strcmp(n,"instret")) return 0xC02;
  if (!strcmp(n,"mhartid")) return 0xF14;
  return -1;
}
// Parse an immediate (optional '-' then number, or a CSR name). Returns 1 on success.
static int RvImmTok(Compiler *cc, int *out) {
  int neg = 0; if (cc->lex.token=='-'){ neg=1; LexNext(cc);}
  if (cc->lex.token==TK_I64) {
    *out = (int)(neg ? -cc->lex.token_i64 : cc->lex.token_i64); LexNext(cc); return 1;
  }
  if (!neg && cc->lex.token==TK_IDENT) {
    char buf[24]; RvLowerCopy(buf, cc->lex.token_str, 24);
    int c = RvCsrNum(buf);
    if (c >= 0) { *out = c; LexNext(cc); return 1; }
  }
  return 0;
}
// Hard-fail OOR immediates instead of silently masking into the instruction field.
static bool RvCheckSimm12(Compiler *cc, int imm) {
  if (imm >= -2048 && imm <= 2047) return true;
  Error(cc, "immediate out of range for 12-bit signed field (need -2048..2047; use li for constants)");
  return false;
}
static bool RvCheckShamt(Compiler *cc, int sh) {
  if (sh >= 0 && sh <= 63) return true;
  Error(cc, "shift amount out of range (need 0..63)");
  return false;
}
static bool RvCheckUimm20(Compiler *cc, int imm) {
  // gas: 20-bit U-type field; accept unsigned 0..0xFFFFF or sign-extended -0x80000..-1.
  if ((imm >= 0 && imm <= 0xFFFFF) || (imm >= -0x80000 && imm < 0)) return true;
  Error(cc, "lui/auipc immediate out of range (need 20-bit field 0..0xFFFFF; prefer li)");
  return false;
}
static bool RvCheckCsrImm(Compiler *cc, int imm) {
  if (imm >= 0 && imm <= 0xFFF) return true;
  Error(cc, "CSR immediate out of range (need 0..0xFFF)");
  return false;
}
static bool RvCheckZimm5(Compiler *cc, int z) {
  if (z >= 0 && z <= 31) return true;
  Error(cc, "CSR zimm out of range (need 0..31)");
  return false;
}

static bool TryAssembleRiscV(Compiler *cc) {
  // Two forms:
  //   asm { Name::  insn... }  — define/export a callable function (existing)
  //   asm { insn... }          — inline: emit IC_RAW_RV into the current statement stream
  //                              so REPL/top-level and in-function asm actually runs
  if (cc->lex.token != TK_IDENT && cc->lex.token != '}') return false;

  bool inline_mode = true;
  char label[128]; label[0] = 0;
  if (cc->lex.token == TK_IDENT) {
    LexPush(cc);
    { const char *_s = cc->lex.token_str; int _i = 0;
      for (; _s[_i] && _i < 127; _i++) label[_i] = _s[_i]; label[_i] = 0; }
    LexNext(cc);
    if (cc->lex.token == TK_DBL_COLON) {
      inline_mode = false;
      LexPopNoRestore(cc);   // keep position after Name
      LexNext(cc);           // consume ::
    } else {
      LexPopRestore(cc);     // back to first mnemonic / local label
      label[0] = 0;
    }
  }

  RvI2 ins[256]; int nins = 0;
  struct { char name[48]; int idx; int is_export; } labs[64]; int nlabs = 0;
  cc->asm_extra_export_n = 0;

  while (cc->lex.token != '}' && cc->lex.token != TK_EOF) {
    // TempleOS Asm.HC skips ';' between instructions; gas also allows ';' as a separator.
    while (cc->lex.token == ';') LexNext(cc);
    if (cc->lex.token == '}' || cc->lex.token == TK_EOF) break;
    if (cc->lex.token != TK_IDENT) return false;
    char raw[48]; { const char *_s=cc->lex.token_str; int _i=0; for(;_s[_i]&&_i<47;_i++) raw[_i]=_s[_i]; raw[_i]=0; }
    char w[48]; RvLowerCopy(w, raw, 48);
    // Local label?  `name:` or `name::`  (`::` also exports as HTT_FUN into this blob)
    LexPush(cc); LexNext(cc);
    int is_lab = (cc->lex.token == ':' || cc->lex.token == TK_DBL_COLON);
    int is_export = (cc->lex.token == TK_DBL_COLON);
    LexPopRestore(cc);
    if (is_lab) {
      LexNext(cc); LexNext(cc);   // consume name and ':'/'::'
      if (nlabs < 64) {
        int _i=0; for(;raw[_i]&&_i<47;_i++) labs[nlabs].name[_i]=raw[_i]; labs[nlabs].name[_i]=0;
        labs[nlabs].idx=nins; labs[nlabs].is_export=is_export; nlabs++;
      }
      continue;
    }
    LexNext(cc);   // consume mnemonic
    // Dotted forms: lr.d, amoswap.w, fence.i, and two-dot fcvt.w.d (lexer splits on '.').
    // Loop so multi-dot mnemonics (fcvt.<int>.<fmt>) fully fold into w.
    while (cc->lex.token == '.') {
      LexNext(cc);
      if (cc->lex.token == TK_IDENT) {
        char suf[8]; RvLowerCopy(suf, cc->lex.token_str, 8);
        int wl = 0, sl = 0; while (w[wl] && wl < 40) wl++; while (suf[sl] && sl < 7) sl++;
        if (wl + 1 + sl < 47) {
          w[wl++] = '.';
          for (int si = 0; suf[si] && wl < 47; si++) w[wl++] = suf[si];
          w[wl] = 0;
        }
        LexNext(cc);
      } else break;
    }
    if (nins >= 256) return false;
    RvI2 *I = &ins[nins]; { RvI2 _z; { char *_p=(char*)&_z; for(unsigned _j=0;_j<sizeof(_z);_j++) _p[_j]=0; } *I=_z; } I->rm = 7; { int _i=0; for(;w[_i]&&_i<15;_i++) I->mn[_i]=w[_i]; I->mn[_i]=0; }

    // Pseudo & real mnemonics.
    if (!strcmp(w,"ret") || !strcmp(w,"nop") || !strcmp(w,"wfi") || !strcmp(w,"fencei") ||
        !strcmp(w,"mret") || !strcmp(w,"sret") || !strcmp(w,"ecall") || !strcmp(w,"ebreak") ||
        !strcmp(w,"unimp")) {
      nins++; continue;
    }
    if (!strcmp(w,"mv") || !strcmp(w,"not") || !strcmp(w,"neg") ||
        !strcmp(w,"seqz") || !strcmp(w,"snez")) {                            // rd, rs
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc); I->rs1=RvRegTok(cc);
      if (I->rd<0||I->rs1<0) return false; nins++; continue;
    }
    if (!strcmp(w,"jr")) {                                                  // rs  (jalr zero, 0(rs))
      I->rs1=RvRegTok(cc); if (I->rs1<0) return false; nins++; continue;
    }
    if (!strcmp(w,"li")) {                                                  // rd, imm (wide → lui+addi[+zext])
      int rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      { int neg=0; if (cc->lex.token=='-'){ neg=1; LexNext(cc);} if (cc->lex.token!=TK_I64) return false;
        I64 v=neg ? -cc->lex.token_i64 : cc->lex.token_i64; LexNext(cc);
        if (rd<0) return false;
        if (v >= -2048 && v <= 2047) { I->rd=rd; I->imm=(int)v; nins++; continue; }
        if (!RvExpandLi(ins,&nins,rd,v)) return false;
      }
      continue;
    }
    // `la rd,label` — the address of a label in this block, PC-relative. Without it an asm{} block
    // cannot reference DATA at all: `auipc` takes a raw 20-bit field, and there was no pseudo that
    // resolves a label. That is what blocks Demo/Asm/AsmHelloWorld.HC's `MOV RSI,MY_WORLD_MSG`
    // (and PutDec/BuzzFizz) from being translated — a DU8 string in the block had no reachable
    // address. Emitted as the standard pair, both entries fixed up in the emit pass below:
    //     auipc rd, hi20(delta)   ; delta measured from THIS instruction
    //     addi  rd, rd, lo12(delta)
    if (!strcmp(w,"la")) {
      int rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if (cc->lex.token!=TK_IDENT || rd<0) return false;
      char lbl[48]; { int _i=0; for(;cc->lex.token_str[_i]&&_i<47;_i++) lbl[_i]=cc->lex.token_str[_i]; lbl[_i]=0; }
      LexNext(cc);
      if (nins+2 > 256) return false;
      { RvI2 *H=&ins[nins]; char *_p=(char*)H; for(unsigned _j=0;_j<sizeof(RvI2);_j++) _p[_j]=0;
        H->mn[0]='a';H->mn[1]='u';H->mn[2]='i';H->mn[3]='p';H->mn[4]='c';H->mn[5]=0;
        H->rd=rd; H->kind=4; { int _i=0; for(;lbl[_i];_i++) H->label[_i]=lbl[_i]; H->label[_i]=0; }
        nins++; }
      { RvI2 *L=&ins[nins]; char *_p=(char*)L; for(unsigned _j=0;_j<sizeof(RvI2);_j++) _p[_j]=0;
        L->mn[0]='a';L->mn[1]='d';L->mn[2]='d';L->mn[3]='i';L->mn[4]=0;
        L->rd=rd; L->rs1=rd; L->kind=5; { int _i=0; for(;lbl[_i];_i++) L->label[_i]=lbl[_i]; L->label[_i]=0; }
        nins++; }
      continue;
    }
    if (!strcmp(w,"j")) {                                                   // j label
      if (cc->lex.token!=TK_IDENT) return false; { int _i=0; for(;cc->lex.token_str[_i]&&_i<47;_i++) I->label[_i]=cc->lex.token_str[_i]; I->label[_i]=0; }
      LexNext(cc); I->kind=2; I->rd=0; nins++; continue;
    }
    // call Fun — HolyC/asm function in this unit (PC-rel jal via IC_CALL later). kind=3.
    if (!strcmp(w,"call")) {
      if (cc->lex.token!=TK_IDENT) return false;
      { int _i=0; for(;cc->lex.token_str[_i]&&_i<47;_i++) I->label[_i]=cc->lex.token_str[_i]; I->label[_i]=0; }
      LexNext(cc); I->kind=3; nins++; continue;
    }
    if (!strcmp(w,"beqz") || !strcmp(w,"bnez")) {                           // rs, label
      I->rs1=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if (cc->lex.token!=TK_IDENT) return false; { int _i=0; for(;cc->lex.token_str[_i]&&_i<47;_i++) I->label[_i]=cc->lex.token_str[_i]; I->label[_i]=0; }
      LexNext(cc); I->kind=1; I->rs2=0; if (I->rs1<0) return false; nins++; continue;
    }
    if (!strcmp(w,"beq")||!strcmp(w,"bne")||!strcmp(w,"blt")||!strcmp(w,"bge")||!strcmp(w,"bltu")||!strcmp(w,"bgeu")) {
      I->rs1=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      I->rs2=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if (cc->lex.token!=TK_IDENT) return false; { int _i=0; for(;cc->lex.token_str[_i]&&_i<47;_i++) I->label[_i]=cc->lex.token_str[_i]; I->label[_i]=0; }
      LexNext(cc); I->kind=1; if (I->rs1<0||I->rs2<0) return false; nins++; continue;
    }
    // Loads: rd, imm(rs1)   Stores: rs2, imm(rs1)
    if (!strcmp(w,"ld")||!strcmp(w,"lw")||!strcmp(w,"lwu")||!strcmp(w,"lh")||!strcmp(w,"lhu")||!strcmp(w,"lb")||!strcmp(w,"lbu")||
        !strcmp(w,"sd")||!strcmp(w,"sw")||!strcmp(w,"sh")||!strcmp(w,"sb")) {
      int first=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if(!RvImmTok(cc,&I->imm)) I->imm=0; if (cc->lex.token!='(') return false; LexNext(cc);
      I->rs1=RvRegTok(cc); if (cc->lex.token!=')') return false; LexNext(cc);
      if (first<0||I->rs1<0) return false;
      if (!RvCheckSimm12(cc, I->imm)) return false;
      if (w[0]=='s') I->rs2=first; else I->rd=first;   // store: first is rs2; load: first is rd
      nins++; continue;
    }
    if (!strcmp(w,"flw")||!strcmp(w,"fld")||!strcmp(w,"fsw")||!strcmp(w,"fsd")) { // fp load/store: fval, imm(rsBase)
      int first=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if(!RvImmTok(cc,&I->imm)) I->imm=0; if (cc->lex.token!='(') return false; LexNext(cc);
      I->rs1=RvRegTok(cc); if (cc->lex.token!=')') return false; LexNext(cc);
      if (first<0||I->rs1<0) return false;
      if (!RvCheckSimm12(cc, I->imm)) return false;
      if (w[1]=='s') I->rs2=first; else I->rd=first;   // fsw/fsd: rs2=fval; flw/fld: rd=fval
      nins++; continue;
    }
    // jalr rd, imm(rs1)  |  jalr rs1
    if (!strcmp(w,"jalr")) {
      int r1=RvRegTok(cc);
      if (cc->lex.token==',') { LexNext(cc); if(!RvImmTok(cc,&I->imm)) I->imm=0; if (cc->lex.token!='(') return false; LexNext(cc); I->rs1=RvRegTok(cc); if (cc->lex.token!=')') return false; LexNext(cc); I->rd=r1; }
      else { I->rd=1; I->rs1=r1; I->imm=0; }
      if (I->rs1<0) return false;
      if (!RvCheckSimm12(cc, I->imm)) return false;
      nins++; continue;
    }
    // R-type: rd, rs1, rs2   |   I-type arith: rd, rs1, imm
    // RV64D float ops (dot-free mnemonics; F64 travels as raw bits in an integer reg, so these
    // bracket fsqrt/fcvt with fmvdx/fmvxd). fsqrtd fd,fs | fmvdx fd,rs | fmvxd rd,fs |
    // fcvtld_{rtz,rdn,rmm} rd,fs | fcvtdl fd,rs.
    if (!strcmp(w,"rdtime")) {                                   // rd  (csrrs rd, time, x0)
      I->rd=RvRegTok(cc); if (I->rd<0) return false; nins++; continue;
    }
    if (!strcmp(w,"lifp")) {   // rd, imm64 -> materialize a full 64-bit constant (for F64 bit patterns):
      // li rd,bits[63:55]; then 5x (slli rd,rd,11; addi rd,rd,<11-bit chunk>). 11 one-word entries.
      int rd=RvRegTok(cc); if (rd<0) return false;
      if (cc->lex.token!=',') return false; LexNext(cc);
      { int neg=0; if (cc->lex.token=='-'){ neg=1; LexNext(cc);} if (cc->lex.token!=TK_I64) return false;
        U64 v=(U64)cc->lex.token_i64; if (neg) v=(U64)(-(I64)v); LexNext(cc);
        int sh[5]={44,33,22,11,0};
        if (!RvPushI(ins,&nins,"li",rd,0,(int)((v>>55)&0x1FF))) return false;
        for (int ci=0; ci<5; ci++) {
          if (!RvPushI(ins,&nins,"slli",rd,rd,11)) return false;
          if (!RvPushI(ins,&nins,"addi",rd,rd,(int)((v>>sh[ci])&0x7FF))) return false;
        }
      }
      continue;
    }
    if (!strcmp(w,"csrr")) {                                     // rd, csr  (csrrs rd, csr, x0)
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc); if(!RvImmTok(cc,&I->imm)) return false;
      if (I->rd<0) return false;
      if (!RvCheckCsrImm(cc, I->imm)) return false;
      nins++; continue;
    }
    if (!strcmp(w,"csrw")) {                                     // csr, rs  (csrrw x0, csr, rs)
      if(!RvImmTok(cc,&I->imm)) return false; if (cc->lex.token!=',') return false; LexNext(cc); I->rs1=RvRegTok(cc);
      if (I->rs1<0) return false;
      if (!RvCheckCsrImm(cc, I->imm)) return false;
      nins++; continue;
    }
    if (!strcmp(w,"csrs")) {                                     // csr, rs  (csrrs x0, csr, rs) -- set bits
      if(!RvImmTok(cc,&I->imm)) return false; if (cc->lex.token!=',') return false; LexNext(cc); I->rs1=RvRegTok(cc);
      if (I->rs1<0) return false;
      if (!RvCheckCsrImm(cc, I->imm)) return false;
      nins++; continue;
    }
    if (!strcmp(w,"csrc")) {                                     // csr, rs  (csrrc x0, csr, rs) -- clear bits
      if(!RvImmTok(cc,&I->imm)) return false; if (cc->lex.token!=',') return false; LexNext(cc); I->rs1=RvRegTok(cc);
      if (I->rs1<0) return false;
      if (!RvCheckCsrImm(cc, I->imm)) return false;
      nins++; continue;
    }
    // Full CSR forms: csrrw/csrrs/csrrc rd, csr, rs1
    if (!strcmp(w,"csrrw") || !strcmp(w,"csrrs") || !strcmp(w,"csrrc")) {
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if (!RvImmTok(cc,&I->imm)) return false; if (cc->lex.token!=',') return false; LexNext(cc);
      I->rs1=RvRegTok(cc); if (I->rd<0||I->rs1<0) return false;
      if (!RvCheckCsrImm(cc, I->imm)) return false;
      nins++; continue;
    }
    // No invented subi (not a standard gas mnemonic). Point at addi / sub rd,rs1,rs2.
    if (!strcmp(w,"subi")) {
      Error(cc, "no subi; use addi rd,rs1,-imm (or sub rd,rs1,rs2)");
      return false;
    }
    if (!strcmp(w,"sfence.vma") || !strcmp(w,"sfencevma")) {     // sfence.vma [rs1[, rs2]]  (bare = zero,zero)
      I->rs1 = 0; I->rs2 = 0;
      if (cc->lex.token == TK_IDENT) {
        LexPush(cc);
        int r1 = RvRegTok(cc);                                   // consumes the ident
        if (r1 >= 0) {
          I->rs1 = r1;
          if (cc->lex.token == ',') { LexNext(cc); int r2 = RvRegTok(cc); if (r2 < 0) { LexPopRestore(cc); return false; } I->rs2 = r2; }
          LexPopNoRestore(cc);
        } else {
          LexPopRestore(cc);                                     // TK_IDENT was next mnemonic -> bare sfence.vma
        }
      }
      nins++; continue;
    }
    if (!strcmp(w,"fence")) {                                     // fence [pred, succ]  (bare = iorw,iorw)
      I->imm = 0xFF;                                              // default fm=0, pred=succ=iorw
      if (cc->lex.token == TK_IDENT) {
        int pred = RvFenceMask(cc->lex.token_str);
        if (pred >= 0) {
          LexPush(cc);
          LexNext(cc);                                            // past pred
          if (cc->lex.token == ',') {
            LexNext(cc);                                          // past ','
            int succ = (cc->lex.token == TK_IDENT) ? RvFenceMask(cc->lex.token_str) : -1;
            if (succ >= 0) { LexNext(cc); LexPopNoRestore(cc); I->imm = (pred<<4)|succ; nins++; continue; }
          }
          LexPopRestore(cc);                                      // not fence operands -> bare fence
        }
      }
      nins++; continue;
    }
    if (!strcmp(w,"fsqrtd")||!strcmp(w,"fsqrt.s")||!strcmp(w,"fcvt.s.d")||!strcmp(w,"fcvt.d.s")) {  // fd, fs  (both float)
      I->rd=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc); I->rs1=RvFRegTok(cc);
      if (I->rd<0||I->rs1<0) return false;
      if (!strcmp(w,"fsqrtd")||!strcmp(w,"fsqrt.s")||!strcmp(w,"fcvt.s.d")) { int _r=RvParseOptRm(cc); if(_r>=0) I->rm=_r; }
      nins++; continue;
    }
    if (!strcmp(w,"fmadd.d")||!strcmp(w,"fmsub.d")||!strcmp(w,"fnmsub.d")||!strcmp(w,"fnmadd.d")||
        !strcmp(w,"fmadd.s")||!strcmp(w,"fmsub.s")||!strcmp(w,"fnmsub.s")||!strcmp(w,"fnmadd.s")) { // R4: fd, fs1, fs2, fs3 (all float); rs3 held in imm
      I->rd=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      I->rs1=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      I->rs2=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      I->imm=RvFRegTok(cc);
      if (I->rd<0||I->rs1<0||I->rs2<0||I->imm<0) return false;
      { int _r=RvParseOptRm(cc); if(_r>=0) I->rm=_r; }
      nins++; continue;
    }
    if (!strcmp(w,"fabs.d")||!strcmp(w,"fabsd")||!strcmp(w,"fneg.d")||!strcmp(w,"fnegd")||
        !strcmp(w,"fmv.d")||!strcmp(w,"fmvd")||!strcmp(w,"fabs.s")||!strcmp(w,"fabss")||
        !strcmp(w,"fneg.s")||!strcmp(w,"fnegs")||!strcmp(w,"fmv.s")||!strcmp(w,"fmvs")) {
      // fd, fs — the pseudo's single source fills BOTH register fields of the real fsgnj*.
      I->rd=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      I->rs1=RvFRegTok(cc); I->rs2=I->rs1;
      nins++; continue;
    }
    if (!strcmp(w,"faddd")||!strcmp(w,"fsubd")||!strcmp(w,"fmuld")||!strcmp(w,"fdivd")||
        !strcmp(w,"fsgnj.d")||!strcmp(w,"fsgnjn.d")||!strcmp(w,"fsgnjx.d")||!strcmp(w,"fmin.d")||!strcmp(w,"fmax.d")||
        !strcmp(w,"fadd.s")||!strcmp(w,"fsub.s")||!strcmp(w,"fmul.s")||!strcmp(w,"fdiv.s")||
        !strcmp(w,"fsgnj.s")||!strcmp(w,"fsgnjn.s")||!strcmp(w,"fsgnjx.s")||!strcmp(w,"fmin.s")||!strcmp(w,"fmax.s")) { // fd, fs1, fs2 (all float)
      I->rd=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      I->rs1=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc); I->rs2=RvFRegTok(cc);
      if (I->rd<0||I->rs1<0||I->rs2<0) return false;
      if (!strcmp(w,"faddd")||!strcmp(w,"fsubd")||!strcmp(w,"fmuld")||!strcmp(w,"fdivd")||!strcmp(w,"fadd.s")||!strcmp(w,"fsub.s")||!strcmp(w,"fmul.s")||!strcmp(w,"fdiv.s")) { int _r=RvParseOptRm(cc); if(_r>=0) I->rm=_r; }
      nins++; continue;
    }
    if (!strcmp(w,"fled")||!strcmp(w,"fltd")||!strcmp(w,"feqd")||!strcmp(w,"fle.s")||!strcmp(w,"flt.s")||!strcmp(w,"feq.s")) { // rd(int), fs1, fs2 (float) -> 0/1
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      I->rs1=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc); I->rs2=RvFRegTok(cc);
      if (I->rd<0||I->rs1<0||I->rs2<0) return false; nins++; continue;
    }
    if (!strcmp(w,"fmvdx")||!strcmp(w,"fcvtdl")||!strcmp(w,"fcvt.d.w")||!strcmp(w,"fcvt.d.wu")||!strcmp(w,"fcvt.d.l")||!strcmp(w,"fcvt.d.lu")||
        !strcmp(w,"fmv.w.x")||!strcmp(w,"fcvt.s.w")||!strcmp(w,"fcvt.s.wu")||!strcmp(w,"fcvt.s.l")||!strcmp(w,"fcvt.s.lu")) {  // fd(float), rs(int)
      I->rd=RvFRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc); I->rs1=RvRegTok(cc);
      if (I->rd<0||I->rs1<0) return false;
      if (!strcmp(w,"fcvt.d.l")||!strcmp(w,"fcvt.d.lu")||!strcmp(w,"fcvt.s.w")||!strcmp(w,"fcvt.s.wu")||!strcmp(w,"fcvt.s.l")||!strcmp(w,"fcvt.s.lu")) { int _r=RvParseOptRm(cc); if(_r>=0) I->rm=_r; }
      nins++; continue;
    }
    if (!strcmp(w,"fmvxd")||!strcmp(w,"fcvtld_rtz")||!strcmp(w,"fcvtld_rdn")||!strcmp(w,"fcvtld_rmm")||!strcmp(w,"fclass.d")||!strcmp(w,"fcvt.w.d")||!strcmp(w,"fcvt.wu.d")||!strcmp(w,"fcvt.l.d")||!strcmp(w,"fcvt.lu.d")||
        !strcmp(w,"fmv.x.w")||!strcmp(w,"fclass.s")||!strcmp(w,"fcvt.w.s")||!strcmp(w,"fcvt.wu.s")||!strcmp(w,"fcvt.l.s")||!strcmp(w,"fcvt.lu.s")) { // rd(int), fs(float)
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc); I->rs1=RvFRegTok(cc);
      if (I->rd<0||I->rs1<0) return false;
      if (!strcmp(w,"fcvt.w.d")||!strcmp(w,"fcvt.wu.d")||!strcmp(w,"fcvt.l.d")||!strcmp(w,"fcvt.lu.d")||!strcmp(w,"fcvt.w.s")||!strcmp(w,"fcvt.wu.s")||!strcmp(w,"fcvt.l.s")||!strcmp(w,"fcvt.lu.s")) { int _r=RvParseOptRm(cc); if(_r>=0) I->rm=_r; }
      nins++; continue;
    }
    if (!strcmp(w,"add")||!strcmp(w,"sub")||!strcmp(w,"and")||!strcmp(w,"or")||!strcmp(w,"xor")||!strcmp(w,"sll")||!strcmp(w,"srl")||!strcmp(w,"sra")||!strcmp(w,"slt")||!strcmp(w,"sltu")||!strcmp(w,"mul")||!strcmp(w,"mulh")||!strcmp(w,"mulhsu")||!strcmp(w,"mulhu")||!strcmp(w,"div")||!strcmp(w,"rem")||!strcmp(w,"divu")||!strcmp(w,"remu")||
        !strcmp(w,"addw")||!strcmp(w,"subw")||!strcmp(w,"sllw")||!strcmp(w,"srlw")||!strcmp(w,"sraw")||!strcmp(w,"mulw")||!strcmp(w,"divw")||!strcmp(w,"divuw")||!strcmp(w,"remw")||!strcmp(w,"remuw")||
        !strcmp(w,"addi")||!strcmp(w,"addiw")||!strcmp(w,"andi")||!strcmp(w,"ori")||!strcmp(w,"xori")||!strcmp(w,"slli")||!strcmp(w,"srli")||!strcmp(w,"srai")||!strcmp(w,"slliw")||!strcmp(w,"srliw")||!strcmp(w,"sraiw")||!strcmp(w,"slti")||!strcmp(w,"sltiu")) {
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc); I->rs1=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      bool shamt_form  = !strcmp(w,"slli")||!strcmp(w,"srli")||!strcmp(w,"srai");
      bool shamtw_form = !strcmp(w,"slliw")||!strcmp(w,"srliw")||!strcmp(w,"sraiw");
      bool imm_form = !strcmp(w,"addiw") || !strcmp(w,"addi") || !strcmp(w,"andi") || !strcmp(w,"ori") || !strcmp(w,"xori") || !strcmp(w,"slti") || !strcmp(w,"sltiu") || shamt_form || shamtw_form;
      if (imm_form) {
        if(!RvImmTok(cc,&I->imm)) return false;
        if (shamt_form) {
          if (!RvCheckShamt(cc, I->imm)) return false;
        } else if (shamtw_form) {
          if (I->imm < 0 || I->imm > 31) { Error(cc, "word shift amount out of range (need 0..31)"); return false; }
        } else if (!RvCheckSimm12(cc, I->imm)) return false;
      }
      else if (cc->lex.token==TK_I64 || cc->lex.token=='-') {
        // sub/add/and/… are R-type only — do not invent immediates.
        if (!strcmp(w,"sub"))
          Error(cc, "sub is R-type (rd,rs1,rs2); use addi rd,rs1,-imm for immediates");
        else if (!strcmp(w,"add"))
          Error(cc, "add is R-type (rd,rs1,rs2); use addi rd,rs1,imm for immediates");
        else
          Error(cc, "R-type op needs register rs2, not immediate");
        return false;
      }
      else { I->rs2=RvRegTok(cc); if (I->rs2<0) return false; }
      if (I->rd<0||I->rs1<0) return false; nins++; continue;
    }
    // U-type: lui/auipc rd, imm20 — imm is the *20-bit field* placed at bits[31:12] (gas-compatible).
    // Example: `lui a0, 0x81397` → rd gets 0x81397000 sign-extended on RV64. A full address such as
    // `lui a0, 0x81397000` is out of range (hard error; prefer `li`).
    if (!strcmp(w,"lui") || !strcmp(w,"auipc")) {
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if (!RvImmTok(cc,&I->imm)) return false;
      if (I->rd<0) return false;
      if (!RvCheckUimm20(cc, I->imm)) return false;
      nins++; continue;
    }
    // CSR imm forms: csrrwi/csrrsi/csrrci rd, csr, zimm  |  csrwi/csrsi/csrci csr, zimm
    if (!strcmp(w,"csrrwi") || !strcmp(w,"csrrsi") || !strcmp(w,"csrrci")) {
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if (!RvImmTok(cc,&I->imm)) return false; if (cc->lex.token!=',') return false; LexNext(cc);
      { int z=0; if(!RvImmTok(cc,&z)) return false;
        if (!RvCheckCsrImm(cc, I->imm) || !RvCheckZimm5(cc, z)) return false;
        I->rs1=z; }
      if (I->rd<0) return false; nins++; continue;
    }
    if (!strcmp(w,"csrwi") || !strcmp(w,"csrsi") || !strcmp(w,"csrci")) {
      if (!RvImmTok(cc,&I->imm)) return false; if (cc->lex.token!=',') return false; LexNext(cc);
      { int z=0; if(!RvImmTok(cc,&z)) return false;
        if (!RvCheckCsrImm(cc, I->imm) || !RvCheckZimm5(cc, z)) return false;
        I->rs1=z; }
      I->rd=0; nins++; continue;
    }
    // A-ext: lr.d/lr.w rd, (rs1)  |  sc.d/sc.w rd, rs2, (rs1)  |  amo* rd, rs2, (rs1)
    if (!strcmp(w,"lr.d") || !strcmp(w,"lr.w") || !strcmp(w,"lrd") || !strcmp(w,"lrw")) {
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if (cc->lex.token!='(') return false; LexNext(cc);
      I->rs1=RvRegTok(cc); if (cc->lex.token!=')') return false; LexNext(cc);
      I->rs2=0; if (I->rd<0||I->rs1<0) return false; nins++; continue;
    }
    if (!strcmp(w,"sc.d") || !strcmp(w,"sc.w") || !strcmp(w,"scd") || !strcmp(w,"scw") ||
        !strcmp(w,"amoswap.d")||!strcmp(w,"amoadd.d")||!strcmp(w,"amoxor.d")||!strcmp(w,"amoand.d")||
        !strcmp(w,"amoor.d")||!strcmp(w,"amomin.d")||!strcmp(w,"amomax.d")||!strcmp(w,"amominu.d")||!strcmp(w,"amomaxu.d")||
        !strcmp(w,"amoswap.w")||!strcmp(w,"amoadd.w")||!strcmp(w,"amoxor.w")||!strcmp(w,"amoand.w")||
        !strcmp(w,"amoor.w")||!strcmp(w,"amomin.w")||!strcmp(w,"amomax.w")||!strcmp(w,"amominu.w")||!strcmp(w,"amomaxu.w")||
        !strcmp(w,"amoswapd")||!strcmp(w,"amoaddd")||!strcmp(w,"amoxord")||!strcmp(w,"amoandd")||
        !strcmp(w,"amoord")||!strcmp(w,"amomind")||!strcmp(w,"amomaxd")||!strcmp(w,"amominud")||!strcmp(w,"amomaxud")||
        !strcmp(w,"amoswapw")||!strcmp(w,"amoaddw")||!strcmp(w,"amoxorw")||!strcmp(w,"amoandw")||
        !strcmp(w,"amoorw")||!strcmp(w,"amominw")||!strcmp(w,"amomaxw")||!strcmp(w,"amominuw")||!strcmp(w,"amomaxuw")) {
      I->rd=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      I->rs2=RvRegTok(cc); if (cc->lex.token!=',') return false; LexNext(cc);
      if (cc->lex.token!='(') return false; LexNext(cc);
      I->rs1=RvRegTok(cc); if (cc->lex.token!=')') return false; LexNext(cc);
      if (I->rd<0||I->rs1<0||I->rs2<0) return false; nins++; continue;
    }
    return false;   // unsupported mnemonic
  }
  if (cc->lex.token != '}') return false;   // single-function / single-inline block for now
  if (nins == 0) return false;

  // Resolve a label name to instruction index.
  #define RV_LBL(nm) ({ int _r=-1; for(int _k=0;_k<nlabs;_k++) if(!strcmp(labs[_k].name,nm)){_r=labs[_k].idx;break;} _r; })

  CHashFun *fn = NULL;
  CIntermediateCode *asm_prev_head = NULL, *asm_prev_tail = NULL;
  CLabel *export_lab[64];
  for (int zi = 0; zi < 64; zi++) export_lab[zi] = NULL;
  if (!inline_mode) {
    // Register + emit into a deferred function chain (like ParseFunction).
    CHashEntry *e = cc->hash_table ? HashFind(label, cc->hash_table, HTT_FUN) : NULL;
    if (e && (e->type & HTT_FUN)) fn = (CHashFun *)e;
    else { fn = calloc(1, sizeof(CHashFun)); fn->str = strdup(label); fn->type = HTT_FUN; fn->raw_type = RT_I64;
           if (cc->hash_table) HashAdd((CHashEntry *)fn, cc->hash_table); }
    CLabel *entry = LabelNew(cc, label);
    fn->entry_label = entry; fn->entry_label_defined = 1;
    fn->is_extern = FALSE;
    RewriteForwardImportCalls(cc, fn);
    asm_prev_head = cc->ic_head; asm_prev_tail = cc->ic_tail;
    cc->ic_head = cc->ic_tail = NULL;
    ICAdd(cc, IC_LABEL, (I64)entry, RT_I64); entry->defined = true;
    // Secondary `Name::` in the same block must be first-class AOT functions too.
    // Otherwise later HolyC calls become implicit `__imp_*` slots (never filled when
    // `_start` owns the blob) — HcCsrrMcause / ReplSetJmp / HcGet* hung or returned 0.
    for (int li = 0; li < nlabs; li++) {
      if (!labs[li].is_export) continue;
      CHashEntry *ae = cc->hash_table ? HashFind(labs[li].name, cc->hash_table, HTT_FUN) : NULL;
      CHashFun *afn;
      if (ae && (ae->type & HTT_FUN)) afn = (CHashFun *)ae;
      else {
        afn = calloc(1, sizeof(CHashFun));
        afn->str = strdup(labs[li].name); afn->type = HTT_FUN; afn->raw_type = RT_I64;
        if (cc->hash_table) HashAdd((CHashEntry *)afn, cc->hash_table);
      }
      CLabel *el = LabelNew(cc, labs[li].name);
      afn->entry_label = el; afn->entry_label_defined = 1; afn->is_extern = FALSE;
      RewriteForwardImportCalls(cc, afn);
      export_lab[li] = el;
    }
  }

  for (int i = 0; i < nins; i++) {
    for (int li = 0; li < nlabs; li++) {
      if (export_lab[li] && labs[li].idx == i) {
        ICAdd(cc, IC_LABEL, (I64)export_lab[li], RT_I64);
        export_lab[li]->defined = true;
      }
    }
    RvI2 *I = &ins[i]; const char *m = I->mn; U32 word = 0x00000013;  // default nop
    int boff = 0;
    // External HolyC call: emit IC_CALL to the callee's entry label (forward decls OK).
    if (I->kind == 3) {
      CHashEntry *ce = cc->hash_table ? HashFind(I->label, cc->hash_table, HTT_FUN) : NULL;
      CHashFun *cf;
      if (ce && (ce->type & HTT_FUN)) cf = (CHashFun *)ce;
      else {
        cf = calloc(1, sizeof(CHashFun));
        cf->str = strdup(I->label); cf->type = HTT_FUN; cf->raw_type = RT_I64;
        if (cc->hash_table) HashAdd((CHashEntry *)cf, cc->hash_table);
      }
      if (!cf->entry_label || !LabelInUnit(cc, (CLabel *)cf->entry_label))
        cf->entry_label = LabelNew(cc, I->label);
      ICAdd(cc, IC_CALL_START, 0, RT_I64);
      ICAdd(cc, IC_CALL, (I64)cf->entry_label, RT_I64);
      ICAdd(cc, IC_CALL_END, 0, RT_I64);
      continue;
    }
    if (I->kind == 1 || I->kind == 2) {
      int t = RV_LBL(I->label);
      if (t < 0) {
        if (!inline_mode) { cc->ic_head=asm_prev_head; cc->ic_tail=asm_prev_tail; }
        return false;
      }
      boff = (t - i) * 4;
    }
    // `la rd,label` halves. The delta is measured from the AUIPC, so the addi (kind 5, one slot
    // later) subtracts one extra word. The +0x800 before the shift is the usual carry correction:
    // addi's 12-bit immediate is SIGN-extended, so when lo12 would be negative the hi20 must be
    // one larger to compensate.
    if (I->kind == 4 || I->kind == 5) {
      int t = RV_LBL(I->label);
      if (t < 0) {
        if (!inline_mode) { cc->ic_head=asm_prev_head; cc->ic_tail=asm_prev_tail; }
        return false;
      }
      int delta = (I->kind == 4) ? (t - i) * 4 : (t - (i - 1)) * 4;
      U32 hi = ((U32)delta + 0x800u) >> 12;
      int lo = delta - (int)(hi << 12);
      if (I->kind == 4) { word = RvU(0x17u, I->rd, (int)(hi & 0xFFFFFu)); goto rv_word_done; }
      word = RvI(0, I->rd, I->rs1, lo);
      goto rv_word_done;
    }
    if (!strcmp(m,"ret"))       word = RvJalr(0,1,0);
    else if (!strcmp(m,"unimp")) word = 0xC0001073u;   // csrrw x0,cycle,x0 — illegal (cycle is RO)
    else if (!strcmp(m,"nop"))  word = RvI(0,0,0,0);
    else if (!strcmp(m,"mret")) word = 0x30200073u;
    else if (!strcmp(m,"sret")) word = 0x10200073u;   // SYSTEM funct12=0x102
    else if (!strcmp(m,"ecall")) word = 0x00000073u;
    else if (!strcmp(m,"ebreak")) word = 0x00100073u;
    else if (!strcmp(m,"mv"))   word = RvI(0,I->rd,I->rs1,0);
    else if (!strcmp(m,"not"))  word = RvI(4,I->rd,I->rs1,-1);
    else if (!strcmp(m,"neg"))  word = RvR(0x20,0,I->rd,0,I->rs1);
    else if (!strcmp(m,"seqz")) word = RvI(3,I->rd,I->rs1,1);              // sltiu rd, rs, 1
    else if (!strcmp(m,"snez")) word = RvR(0,3,I->rd,0,I->rs1);            // sltu rd, zero, rs
    else if (!strcmp(m,"jr"))   word = RvJalr(0,I->rs1,0);
    else if (!strcmp(m,"li"))   word = RvI(0,I->rd,0,I->imm);
    else if (!strcmp(m,"j"))    word = RvJ(0,boff);
    else if (!strcmp(m,"beqz")) word = RvBr(0,I->rs1,0,boff);
    else if (!strcmp(m,"bnez")) word = RvBr(1,I->rs1,0,boff);
    else if (!strcmp(m,"beq"))  word = RvBr(0,I->rs1,I->rs2,boff);
    else if (!strcmp(m,"bne"))  word = RvBr(1,I->rs1,I->rs2,boff);
    else if (!strcmp(m,"blt"))  word = RvBr(4,I->rs1,I->rs2,boff);
    else if (!strcmp(m,"bge"))  word = RvBr(5,I->rs1,I->rs2,boff);
    else if (!strcmp(m,"bltu")) word = RvBr(6,I->rs1,I->rs2,boff);
    else if (!strcmp(m,"bgeu")) word = RvBr(7,I->rs1,I->rs2,boff);
    else if (!strcmp(m,"ld"))   word = RvLoad(3,I->rd,I->imm,I->rs1);
    else if (!strcmp(m,"lw"))   word = RvLoad(2,I->rd,I->imm,I->rs1);
    else if (!strcmp(m,"lwu"))  word = RvLoad(6,I->rd,I->imm,I->rs1);
    else if (!strcmp(m,"lh"))   word = RvLoad(1,I->rd,I->imm,I->rs1);
    else if (!strcmp(m,"lhu"))  word = RvLoad(5,I->rd,I->imm,I->rs1);
    else if (!strcmp(m,"lb"))   word = RvLoad(0,I->rd,I->imm,I->rs1);
    else if (!strcmp(m,"lbu"))  word = RvLoad(4,I->rd,I->imm,I->rs1);
    else if (!strcmp(m,"sd"))   word = RvStore(3,I->rs2,I->imm,I->rs1);
    else if (!strcmp(m,"sw"))   word = RvStore(2,I->rs2,I->imm,I->rs1);
    else if (!strcmp(m,"sh"))   word = RvStore(1,I->rs2,I->imm,I->rs1);
    else if (!strcmp(m,"sb"))   word = RvStore(0,I->rs2,I->imm,I->rs1);
    else if (!strcmp(m,"flw"))  word = RvFLoad(2,I->rd,I->imm,I->rs1);
    else if (!strcmp(m,"fld"))  word = RvFLoad(3,I->rd,I->imm,I->rs1);
    else if (!strcmp(m,"fsw"))  word = RvFStore(2,I->rs2,I->imm,I->rs1);
    else if (!strcmp(m,"fsd"))  word = RvFStore(3,I->rs2,I->imm,I->rs1);
    else if (!strcmp(m,"jalr")) word = RvJalr(I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"addi")) word = RvI(0,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"addiw")) word = RvIw(0,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"andi")) word = RvI(7,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"ori"))  word = RvI(6,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"xori")) word = RvI(4,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"slti")) word = RvI(2,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"sltiu")) word = RvI(3,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"slli")) word = RvShift(1,0,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"srli")) word = RvShift(5,0,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"srai")) word = RvShift(5,0x10,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"add"))  word = RvR(0,0,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"sub"))  word = RvR(0x20,0,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"and"))  word = RvR(0,7,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"or"))   word = RvR(0,6,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"xor"))  word = RvR(0,4,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"sll"))  word = RvR(0,1,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"srl"))  word = RvR(0,5,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"sra"))  word = RvR(0x20,5,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"slt"))  word = RvR(0,2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"sltu")) word = RvR(0,3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"mul"))  word = RvR(1,0,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"mulh")) word = RvR(1,1,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"mulhsu")) word = RvR(1,2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"mulhu")) word = RvR(1,3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"div"))  word = RvR(1,4,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"rem"))  word = RvR(1,6,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"divu")) word = RvR(1,5,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"remu")) word = RvR(1,7,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"slliw")) word = RvShiftW(1,0,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"srliw")) word = RvShiftW(5,0,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"sraiw")) word = RvShiftW(5,0x20,I->rd,I->rs1,I->imm);
    else if (!strcmp(m,"addw")) word = RvRw(0,0,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"subw")) word = RvRw(0x20,0,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"sllw")) word = RvRw(0,1,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"srlw")) word = RvRw(0,5,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"sraw")) word = RvRw(0x20,5,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"mulw")) word = RvRw(1,0,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"divw")) word = RvRw(1,4,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"divuw")) word = RvRw(1,5,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"remw")) word = RvRw(1,6,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"remuw")) word = RvRw(1,7,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"fsqrtd"))     word = 0x5A000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15);
    else if (!strcmp(m,"faddd"))      word = 0x02000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fsubd"))      word = 0x0A000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fmuld"))      word = 0x12000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fdivd"))      word = 0x1A000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fled"))       word = 0xA2000053u | (I->rd<<7)  | (0u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fltd"))       word = 0xA2000053u | (I->rd<<7)  | (1u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"feqd"))       word = 0xA2000053u | (I->rd<<7)  | (2u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fmvdx"))      word = 0xF2000053u | (I->rd<<7)  | (I->rs1<<15);
    else if (!strcmp(m,"fmvxd"))      word = 0xE2000053u | (I->rd<<7)  | (I->rs1<<15);
    else if (!strcmp(m,"fcvtld_rtz")) word = 0xC2000053u | (I->rd<<7)  | (1u<<12) | (I->rs1<<15) | (2u<<20);
    else if (!strcmp(m,"fcvtld_rdn")) word = 0xC2000053u | (I->rd<<7)  | (2u<<12) | (I->rs1<<15) | (2u<<20);
    else if (!strcmp(m,"fcvtld_rmm")) word = 0xC2000053u | (I->rd<<7)  | (4u<<12) | (I->rs1<<15) | (2u<<20);
    else if (!strcmp(m,"fcvtdl"))     word = 0xD2000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (2u<<20);
    // RISC-V FP pseudo-instructions: fabs.d rd,rs IS fsgnjx.d rd,rs,rs (sign-inject XOR with
    // itself clears the sign bit), fneg.d IS fsgnjn.d rd,rs,rs, fmv.d IS fsgnj.d rd,rs,rs. There
    // is no fabs.d opcode. Kernel/KUtilsRV.HC's own Abs:: block wrote `fabsd`, so the WHOLE BLOCK
    // was rejected and dropped, while Floor and Trunc — written the same way immediately below it —
    // assembled. What that cost is measurable and was measured: `Abs` left the blob entirely and
    // became an UNRESOLVED HOST-IMPORT in the HOFYIMP1 trailer, which every harness linking
    // tests/exec/harness/oracle_out.c then satisfied from the C `Abs` in bootstrap/holy_rt_names.h.
    // So it behaved correctly in all 81 such gates and no test could see it. The blob is the only
    // witness: tools/blob_imports.py, and tests/scripts/check_blob_imports.sh pins it.
    // (Not claimed: what a bare image with no C runtime does with that slot. Not measured.)
    // Undotted spellings too, because that file uses them throughout (fmvdx, fmvxd, faddd).
    else if (!strcmp(m,"fmv.d")||!strcmp(m,"fmvd"))
                                      word = 0x22000053u | (I->rd<<7)  | (0u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fneg.d")||!strcmp(m,"fnegd"))
                                      word = 0x22000053u | (I->rd<<7)  | (1u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fabs.d")||!strcmp(m,"fabsd"))
                                      word = 0x22000053u | (I->rd<<7)  | (2u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fmv.s")||!strcmp(m,"fmvs"))
                                      word = 0x20000053u | (I->rd<<7)  | (0u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fneg.s")||!strcmp(m,"fnegs"))
                                      word = 0x20000053u | (I->rd<<7)  | (1u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fabs.s")||!strcmp(m,"fabss"))
                                      word = 0x20000053u | (I->rd<<7)  | (2u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fsgnj.d"))    word = 0x22000053u | (I->rd<<7)  | (0u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fsgnjn.d"))   word = 0x22000053u | (I->rd<<7)  | (1u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fsgnjx.d"))   word = 0x22000053u | (I->rd<<7)  | (2u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fmin.d"))     word = 0x2A000053u | (I->rd<<7)  | (0u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fmax.d"))     word = 0x2A000053u | (I->rd<<7)  | (1u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fclass.d"))   word = 0xE2000053u | (I->rd<<7)  | (1u<<12) | (I->rs1<<15);
    else if (!strcmp(m,"fcvt.w.d"))   word = 0xC2000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (0u<<20);
    else if (!strcmp(m,"fcvt.wu.d"))  word = 0xC2000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (1u<<20);
    else if (!strcmp(m,"fcvt.l.d"))   word = 0xC2000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (2u<<20);
    else if (!strcmp(m,"fcvt.lu.d"))  word = 0xC2000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (3u<<20);
    else if (!strcmp(m,"fcvt.d.w"))   word = 0xD2000053u | (I->rd<<7)  | (0u<<12) | (I->rs1<<15) | (0u<<20);
    else if (!strcmp(m,"fcvt.d.wu"))  word = 0xD2000053u | (I->rd<<7)  | (0u<<12) | (I->rs1<<15) | (1u<<20);
    else if (!strcmp(m,"fcvt.d.l"))   word = 0xD2000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (2u<<20);
    else if (!strcmp(m,"fcvt.d.lu"))  word = 0xD2000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (3u<<20);
    else if (!strcmp(m,"fcvt.s.d"))   word = 0x40000053u | (I->rd<<7)  | ((U32)I->rm<<12) | (I->rs1<<15) | (1u<<20);
    else if (!strcmp(m,"fcvt.d.s"))   word = 0x42000053u | (I->rd<<7)  | (0u<<12) | (I->rs1<<15) | (0u<<20);
    else if (!strcmp(m,"fmadd.d"))    word = 0x02000043u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20) | ((U32)I->imm<<27);
    else if (!strcmp(m,"fmsub.d"))    word = 0x02000047u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20) | ((U32)I->imm<<27);
    else if (!strcmp(m,"fnmsub.d"))   word = 0x0200004Bu | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20) | ((U32)I->imm<<27);
    else if (!strcmp(m,"fnmadd.d"))   word = 0x0200004Fu | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20) | ((U32)I->imm<<27);
    else if (!strcmp(m,"fmadd.s"))    word = 0x00000043u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20) | ((U32)I->imm<<27);
    else if (!strcmp(m,"fmsub.s"))    word = 0x00000047u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20) | ((U32)I->imm<<27);
    else if (!strcmp(m,"fnmsub.s"))   word = 0x0000004Bu | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20) | ((U32)I->imm<<27);
    else if (!strcmp(m,"fnmadd.s"))   word = 0x0000004Fu | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20) | ((U32)I->imm<<27);
    else if (!strcmp(m,"fadd.s"))     word = 0x00000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fsub.s"))     word = 0x08000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fmul.s"))     word = 0x10000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fdiv.s"))     word = 0x18000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fsqrt.s"))    word = 0x58000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15);
    else if (!strcmp(m,"fsgnj.s"))    word = 0x20000053u | (I->rd<<7) | (0u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fsgnjn.s"))   word = 0x20000053u | (I->rd<<7) | (1u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fsgnjx.s"))   word = 0x20000053u | (I->rd<<7) | (2u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fmin.s"))     word = 0x28000053u | (I->rd<<7) | (0u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fmax.s"))     word = 0x28000053u | (I->rd<<7) | (1u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fle.s"))      word = 0xA0000053u | (I->rd<<7) | (0u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"flt.s"))      word = 0xA0000053u | (I->rd<<7) | (1u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"feq.s"))      word = 0xA0000053u | (I->rd<<7) | (2u<<12) | (I->rs1<<15) | (I->rs2<<20);
    else if (!strcmp(m,"fclass.s"))   word = 0xE0000053u | (I->rd<<7) | (1u<<12) | (I->rs1<<15);
    else if (!strcmp(m,"fmv.x.w"))    word = 0xE0000053u | (I->rd<<7) | (0u<<12) | (I->rs1<<15);
    else if (!strcmp(m,"fmv.w.x"))    word = 0xF0000053u | (I->rd<<7) | (0u<<12) | (I->rs1<<15);
    else if (!strcmp(m,"fcvt.w.s"))   word = 0xC0000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (0u<<20);
    else if (!strcmp(m,"fcvt.wu.s"))  word = 0xC0000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (1u<<20);
    else if (!strcmp(m,"fcvt.l.s"))   word = 0xC0000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (2u<<20);
    else if (!strcmp(m,"fcvt.lu.s"))  word = 0xC0000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (3u<<20);
    else if (!strcmp(m,"fcvt.s.w"))   word = 0xD0000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (0u<<20);
    else if (!strcmp(m,"fcvt.s.wu"))  word = 0xD0000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (1u<<20);
    else if (!strcmp(m,"fcvt.s.l"))   word = 0xD0000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (2u<<20);
    else if (!strcmp(m,"fcvt.s.lu"))  word = 0xD0000053u | (I->rd<<7) | ((U32)I->rm<<12) | (I->rs1<<15) | (3u<<20);
    else if (!strcmp(m,"rdtime"))     word = 0xC0102073u | (I->rd<<7);
    else if (!strcmp(m,"csrr"))       word = 0x00002073u | (I->rd<<7)  | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrw"))       word = 0x00001073u | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrs"))       word = 0x00002073u | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrc"))       word = 0x00003073u | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrrw"))      word = 0x00001073u | (I->rd<<7) | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrrs"))      word = 0x00002073u | (I->rd<<7) | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrrc"))      word = 0x00003073u | (I->rd<<7) | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"sfence.vma") || !strcmp(m,"sfencevma"))  word = 0x12000073u | (I->rs2<<20) | (I->rs1<<15);
    else if (!strcmp(m,"fence"))      word = 0x0000000Fu | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"wfi"))        word = 0x10500073u;
    else if (!strcmp(m,"lui"))        word = RvU(0x37u, I->rd, I->imm);
    else if (!strcmp(m,"auipc"))      word = RvU(0x17u, I->rd, I->imm);
    else if (!strcmp(m,"csrrwi"))     word = 0x00005073u | (I->rd<<7) | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrrsi"))     word = 0x00006073u | (I->rd<<7) | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrrci"))     word = 0x00007073u | (I->rd<<7) | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrwi"))      word = 0x00005073u | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrsi"))      word = 0x00006073u | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"csrci"))      word = 0x00007073u | (I->rs1<<15) | (((U32)I->imm & 0xFFF)<<20);
    else if (!strcmp(m,"lr.d")||!strcmp(m,"lrd")) word = RvA(0x02,0,0x3,I->rd,I->rs1,0);
    else if (!strcmp(m,"lr.w")||!strcmp(m,"lrw")) word = RvA(0x02,0,0x2,I->rd,I->rs1,0);
    else if (!strcmp(m,"sc.d")||!strcmp(m,"scd")) word = RvA(0x03,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"sc.w")||!strcmp(m,"scw")) word = RvA(0x03,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoswap.d")||!strcmp(m,"amoswapd")) word = RvA(0x01,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoadd.d")||!strcmp(m,"amoaddd"))   word = RvA(0x00,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoxor.d")||!strcmp(m,"amoxord"))   word = RvA(0x04,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoand.d")||!strcmp(m,"amoandd"))   word = RvA(0x0C,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoor.d")||!strcmp(m,"amoord"))     word = RvA(0x08,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amomin.d")||!strcmp(m,"amomind"))   word = RvA(0x10,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amomax.d")||!strcmp(m,"amomaxd"))   word = RvA(0x14,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amominu.d")||!strcmp(m,"amominud")) word = RvA(0x18,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amomaxu.d")||!strcmp(m,"amomaxud")) word = RvA(0x1C,0,0x3,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoswap.w")||!strcmp(m,"amoswapw")) word = RvA(0x01,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoadd.w")||!strcmp(m,"amoaddw"))   word = RvA(0x00,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoxor.w")||!strcmp(m,"amoxorw"))   word = RvA(0x04,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoand.w")||!strcmp(m,"amoandw"))   word = RvA(0x0C,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amoor.w")||!strcmp(m,"amoorw"))     word = RvA(0x08,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amomin.w")||!strcmp(m,"amominw"))   word = RvA(0x10,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amomax.w")||!strcmp(m,"amomaxw"))   word = RvA(0x14,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amominu.w")||!strcmp(m,"amominuw")) word = RvA(0x18,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"amomaxu.w")||!strcmp(m,"amomaxuw")) word = RvA(0x1C,0,0x2,I->rd,I->rs1,I->rs2);
    else if (!strcmp(m,"fencei"))     word = 0x0000100Fu;
    rv_word_done:
    ICAdd(cc, IC_RAW_RV, (I64)word, RT_I64);
  }
  #undef RV_LBL

  if (inline_mode) {
    // Freeze GPRs into MEM_REGS_SNAP before the next Reg/Regs on this statement.
    ICEmitRegsSnap(cc);
    cc->asm_funcs_translated++;
    cc->last_expr_type = RT_I0;
    return true;
  }

  if (cc->defer_aot_compile) {
    AOTFnICChunk *chunk = calloc(1, sizeof(AOTFnICChunk));
    chunk->head = cc->ic_head; chunk->tail = cc->ic_tail; chunk->fun = fn; chunk->next = NULL;
    if (!cc->aot_fn_ic_tail) cc->aot_fn_ic_head = cc->aot_fn_ic_tail = chunk;
    else { cc->aot_fn_ic_tail->next = chunk; cc->aot_fn_ic_tail = chunk; }
  } else {
    // JIT (REPL): assemble the block's words into executable memory now and bind exe_addr, the
    // same way ParseFunction materializes a normal function. Without this the label symbol exists
    // but exe_addr stays 0 ("declared but not defined" at the call site). This is what makes
    // asm{}-defined functions -- e.g. editable boot assembly -- callable from the live REPL.
    extern U8 *CompileAOT(Compiler *cc, I64 *size_out);
    I64 asm_code_size = 0;
    U8 *asm_code = CompileAOT(cc, &asm_code_size);
    if (asm_code) {
      fn->exe_addr = (I64)asm_code; fn->size = asm_code_size;
      cc->code_buffer = asm_code; cc->code_size = asm_code_size;
      // Secondary `Name::` labels (TrapCtxSave, …): alias into the same blob for Man/Src/FnAddr.
      for (int li = 0; li < nlabs; li++) {
        if (!labs[li].is_export || !strcmp(labs[li].name, label)) continue;
        CHashEntry *ae = cc->hash_table ? HashFind(labs[li].name, cc->hash_table, HTT_FUN) : NULL;
        CHashFun *afn;
        if (ae && (ae->type & HTT_FUN)) afn = (CHashFun *)ae;
        else {
          afn = calloc(1, sizeof(CHashFun));
          afn->str = strdup(labs[li].name); afn->type = HTT_FUN; afn->raw_type = RT_I64;
          if (cc->hash_table) HashAdd((CHashEntry *)afn, cc->hash_table);
        }
        int next = nins;
        for (int lj = 0; lj < nlabs; lj++)
          if (labs[lj].is_export && labs[lj].idx > labs[li].idx && labs[lj].idx < next)
            next = labs[lj].idx;
        afn->exe_addr = (I64)(asm_code + labs[li].idx * 4);
        afn->size = (I64)((next - labs[li].idx) * 4);
        if (cc->asm_extra_export_n < 8) {
          int _i = 0; for (; labs[li].name[_i] && _i < 47; _i++)
            cc->asm_extra_exports[cc->asm_extra_export_n][_i] = labs[li].name[_i];
          cc->asm_extra_exports[cc->asm_extra_export_n][_i] = 0;
          cc->asm_extra_export_n++;
        }
      }
    }
  }
  cc->ic_head = asm_prev_head; cc->ic_tail = asm_prev_tail;
  cc->asm_funcs_translated++;
  cc->last_compiled_func = fn;   /* so Run()/srcmap remember asm exports (TrapVec, …) */
  return true;
}


bool ParseStatement(Compiler *cc) {
  // Match original PrsStmt.HC structure with while(TRUE) loop
  while (true) {
    // Skip leading commas (PrsStmt.HC line 921-922)
    while (cc->lex.token == ',')
      LexNext(cc);
    
    // Handle blocks
    if (cc->lex.token == '{') {
      if (!ParseBlock(cc)) return false;
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    // Handle empty statements
    if (cc->lex.token == ';') {
      LexNext(cc);
      if (cc->lex.token != ',') return true;
      continue;
    }

    if (cc->lex.token == KW_NO_WARN) {   // `no_warn x,y;` — silences unused-variable warnings
      while (cc->lex.token != ';' && cc->lex.token != TK_EOF) LexNext(cc);
      if (cc->lex.token == ';') LexNext(cc);
      return true;
    }
    // x86 opcodes HolyC accepts as bare statements (`PUSHFD CLI … POPFD`): mstatus.MIE here.
    if (cc->lex.token == TK_IDENT && !cc->lex.hash_entry && cc->lex.token_str) {
      if (!strcmp(cc->lex.token_str, "lock")) {
        // `lock stmt;` / `lock {…}` — amoswap spin (IC_LOCK_*), not a no-op.
        LexNext(cc);
        ICAdd(cc, IC_LOCK_ENTER, 0, RT_I64);
        if (!ParseStatement(cc)) return false;
        ICAdd(cc, IC_LOCK_LEAVE, 0, RT_I64);
        if (cc->lex.token != ',') return true;
        continue;
      }
      int sys_ic = 0;
      if (!strcmp(cc->lex.token_str, "CLI")) sys_ic = IC_CLI;
      else if (!strcmp(cc->lex.token_str, "STI")) sys_ic = IC_STI;
      else if (!strcmp(cc->lex.token_str, "PUSHFD")) sys_ic = IC_PUSHFD;
      else if (!strcmp(cc->lex.token_str, "POPFD")) sys_ic = IC_POPFD;
      else if (!strcmp(cc->lex.token_str, "PAUSE")) sys_ic = IC_PAUSE;
      else if (!strcmp(cc->lex.token_str, "HLT")) sys_ic = IC_HLT;
      else if (!strcmp(cc->lex.token_str, "NOP")) sys_ic = IC_PAUSE;
      // x86-only opcode statements with no RISC-V meaning: skipped (counted like asm blocks).
      else if (!strcmp(cc->lex.token_str, "CLD") || !strcmp(cc->lex.token_str, "STD") ||
               !strcmp(cc->lex.token_str, "MOV_RAX_CR2") || !strcmp(cc->lex.token_str, "MOV_CR2_RAX") ||
               !strcmp(cc->lex.token_str, "MOV_RAX_CR3") || !strcmp(cc->lex.token_str, "MOV_CR3_RAX") ||
               !strcmp(cc->lex.token_str, "WBINVD") || !strcmp(cc->lex.token_str, "INVD")) {
        HolyAsmSkipNote(cc, 0, cc->lex.token_str, NULL);
        LexNext(cc);
        if (cc->lex.token == ';') LexNext(cc);
        return true;
      }
      else if (cc->lex.token_str[0] >= 'A' && cc->lex.token_str[0] <= 'Z' && strcmp(cc->lex.token_str, "INT")) {
        // An x86 instruction written bare in HolyC code (`MOV U64 [RSI],R13`): an unknown
        // all-uppercase name at statement start; the instruction runs to the end of its line.
        bool upper = true;
        for (const char *q = cc->lex.token_str; *q; q++)
          if (!((*q >= 'A' && *q <= 'Z') || (*q >= '0' && *q <= '9') || *q == '_')) { upper = false; break; }
        if (upper) {
          LexPush(cc);
          LexNext(cc);
          bool operand = (cc->lex.token != '(' && cc->lex.token != '=' && cc->lex.token != ';' && cc->lex.token != '.' &&
                          cc->lex.token != TK_ARROW && cc->lex.token != ',' && cc->lex.token != ')');
          LexPopRestore(cc);
          if (operand) {
            int start_line = cc->lex.line;
            char *mnem = strdup(cc->lex.token_str);
            while (cc->lex.token != TK_EOF && cc->lex.line == start_line) LexNext(cc);
            HolyAsmSkipNote(cc, start_line, mnem, NULL);
            free(mnem);
            return true;
          }
        }
      }
      if (!strcmp(cc->lex.token_str, "INT")) {   // `INT I_DBG`: software interrupt
        LexNext(cc);
        bool oki = true;
        I64 n = CEOr(cc, 0, &oki);
        (void)n;
        if (!oki) { Error(cc, "Expected interrupt number"); return false; }
        ICAdd(cc, IC_INT, n, RT_I64);
        if (cc->lex.token == ';') LexNext(cc);
        return true;
      }
      if (sys_ic) {
        ICAdd(cc, sys_ic, 0, RT_I64);
        LexNext(cc);
        if (cc->lex.token == ';') LexNext(cc);
        return true;
      }
    }
    
    #ifdef BARE_METAL
    #endif
    
    // Check for static modifier
    bool is_static = false;
    if (cc->lex.token == KW_STATIC) {
      is_static = true;
      LexNext(cc);
    }
    
    #ifdef BARE_METAL
    #endif
    
    if (cc->lex.token == KW_ENUM) {
      if (!ParseEnum(cc)) return false;
      if (cc->lex.token != ',') return true;
      continue;
    }

    // Check for type declaration (keyword or identifier from hash table)
    bool is_type_decl = false;
    if (cc->lex.token >= KW_I0 && cc->lex.token <= KW_F64) {
      is_type_decl = true;
    } else if (cc->lex.token == TK_IDENT) {
      // Check if it's a type in the hash table
      if (cc->hash_table && cc->lex.hash_entry && 
          (cc->lex.hash_entry->type & (HTT_CLASS | HTT_INTERNAL_TYPE))) {
        is_type_decl = true;
      }
    }
    
    
    #ifdef BARE_METAL
    #endif
    
    if (is_type_decl) {
      U8 type = ParseType(cc);
      
      if (cc->lex.token == '(') {
        bool result = true;
        if (is_static) {
          result = ParseGlobalFunctionPointerDeclList(cc, type);
        } else {
          result = ParseLocalFunctionPointerDeclList(cc, type);
        }
        if (!result) return false;
        if (cc->lex.token != ',') return true;
        continue;
      }

      SkipRegQualifier(cc);
      while (cc->lex.token == '*') {   // `U8 reg *dst`: stars after the qualifier
        cc->last_pointed_to_type = type;
        cc->last_ptr_depth++;
        LexNext(cc);
      }
      if (cc->lex.token != TK_IDENT) {
        Error(cc, "Expected variable name after type");
        return false;
      }
      
      char *var_name = strdup(cc->lex.token_str);
      LexNext(cc);
      
      if (cc->lex.token == '(') {
        free(var_name);
        Error(cc, "Function definition not allowed in statement context");
        return false;
      }
      
      // For static variables, treat as globals scoped to function
      if (is_static) {
        bool result = ParseGlobalVariable(cc, type, var_name);
        free(var_name);
        if (!result) return false;
        while (cc->lex.token == ',') {   // `static I64 a=0,b=0;`
          LexNext(cc);
          while (cc->lex.token == '*') LexNext(cc);
          if (cc->lex.token != TK_IDENT) { Error(cc, "Expected variable name"); return false; }
          char *nm2 = strdup(cc->lex.token_str);
          LexNext(cc);
          bool r2 = ParseGlobalVariable(cc, type, nm2);
          free(nm2);
          if (!r2) return false;
        }
      } else {
        // `U8 *ptr,buf[N]`: later declarators start from the base type, not the pointer.
        U8 base_type = cc->last_pointed_to_type ? cc->last_pointed_to_type : type;
        bool result = ParseVariableDeclWithName(cc, base_type, var_name);
        free(var_name);
        if (!result) return false;
      }
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    #ifdef BARE_METAL
    #endif
    
    // Keywords
    if (cc->lex.token == KW_IF) {
      if (!ParseIfStatement(cc)) return false;
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    if (cc->lex.token == KW_DO) {
      if (!ParseDoStatement(cc)) return false;
      if (cc->lex.token != ',') return true;
      continue;
    }
    if (cc->lex.token == KW_WHILE) {
      if (!ParseWhileStatement(cc)) return false;
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    if (cc->lex.token == KW_FOR) {
      if (!ParseForStatement(cc)) return false;
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    if (cc->lex.token == KW_RETURN) {
      // Parse return statement (PrsStmt.HC:916-935)
      LexNext(cc);  // Skip 'return'
      
      if (cc->lex.token != ';' && cc->lex.token != ',' && cc->lex.token != KW_ELSE && cc->lex.token != '}') {
        // return <expression>;
        if (!ParseExpression(cc)) return false;
        if (cc->current_fn_ret_type == RT_F64 && cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
        else if (cc->current_fn_ret_type != RT_F64 && cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64);
        // Convert to the DECLARED return type. C does this ("return 0xCA00000D" from an int32
        // function yields -905969651) and the RISC-V ABI expects a properly extended value in a0.
        // Without it a narrow return was whatever the expression happened to leave behind: an I32
        // status came back zero-extended, so `f() < 0` was false for a negative code while the
        // same value stored in an I32 variable compared correctly.
        {
          I64 retconv = 0;
          if (cc->current_fn_ret_type == RT_I8 || cc->current_fn_ret_type == RT_U8 ||
              cc->current_fn_ret_type == RT_I16 || cc->current_fn_ret_type == RT_U16 ||
              cc->current_fn_ret_type == RT_I32 || cc->current_fn_ret_type == RT_U32)
            retconv = cc->current_fn_ret_type;
          ICAdd(cc, IC_RETURN_VAL, retconv, RT_I64);
        }
      }
      
      // Leaving open try blocks by return: pop their handler contexts first.
      for (I64 td = 0; td < cc->try_depth; td++) ICAdd(cc, IC_TRY_LEAVE, 0, RT_I64);
      // Jump to function exit label
      if (cc->current_function_exit) {
        ICAdd(cc, IC_JMP, (I64)cc->current_function_exit, RT_I64);
      }
      if (cc->lex.token == ';') LexNext(cc);  // consume, so `if (c) return x; else …` works
      
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    if (cc->lex.token == KW_SWITCH) {
      if (!ParseSwitchStatement(cc)) return false;
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    #ifdef BARE_METAL
    #endif
    
    if (cc->lex.token == KW_BREAK) {
      // Break statement - jump to end of current loop
      LexNext(cc);
      
      if (!cc->current_break_label) {
        Error(cc, "'break' not allowed outside loop");
        return false;
      }
      
      // Leaving try blocks opened inside the loop: pop their handler contexts first.
      for (I64 td = cc->loop_try_depth; td < cc->try_depth; td++) ICAdd(cc, IC_TRY_LEAVE, 0, RT_I64);
      // Generate jump to loop end label
      ICAdd(cc, IC_JMP, (I64)cc->current_break_label, RT_I64);
      
      LexExpect(cc, ';');
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    if (cc->lex.token == KW_CONTINUE) {
      // Continue statement - jump to start/increment of current loop
      LexNext(cc);
      
      if (!cc->current_continue_label) {
        Error(cc, "'continue' not allowed outside loop");
        return false;
      }
      
      for (I64 td = cc->loop_try_depth; td < cc->try_depth; td++) ICAdd(cc, IC_TRY_LEAVE, 0, RT_I64);
      // Generate jump to loop continue label
      ICAdd(cc, IC_JMP, (I64)cc->current_continue_label, RT_I64);
      
      LexExpect(cc, ';');
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    if (cc->lex.token == KW_GOTO) {
      // Goto statement: goto label_name;
      LexNext(cc);
      
      if (cc->lex.token != TK_IDENT) {
        Error(cc, "Expected label name after goto");
        return false;
      }
      
      char *label_name = strdup(cc->lex.token_str);
      LexNext(cc);
      
      // Find or create label
      CLabel *label = LabelFind(cc, label_name);
      if (!label) {
        label = LabelNew(cc, label_name);
      }
      // Backward goto out of try blocks: pop the handler contexts being left.
      if (label->defined)
        for (I64 td = label->flags; td < cc->try_depth; td++) ICAdd(cc, IC_TRY_LEAVE, 0, RT_I64);
      
      // Generate jump to label
      ICAdd(cc, IC_JMP, (I64)label, RT_I64);
      
      free(label_name);
      LexExpect(cc, ';');
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    #ifdef BARE_METAL
    #endif
    
    // Try/catch block (following original PrsTryBlk from PrsStmt.HC:842-902)
    if (cc->lex.token == KW_TRY) {
      // try { } catch { }: push a handler context {prev, sp, s0, catch pc} kept in a compiler
      // temp of this frame onto __try_top; throw unwinds to the innermost one (any depth).
      LexNext(cc);
      CLabel *catch_label = LabelNew(cc, NULL);
      CLabel *done_label = LabelNew(cc, NULL);
      I64 ctx_marker = HOLY_LOCAL_MARKER(cc->locals_size);
      cc->locals_size += 32;
      ICAdd(cc, IC_LEA, ctx_marker, RT_I64);
      ICAdd(cc, IC_TRY_ENTER, (I64)catch_label, RT_I64);
      cc->try_depth++;
      bool body_ok = ParseStatement(cc);
      cc->try_depth--;
      if (!body_ok) return false;
      ICAdd(cc, IC_TRY_LEAVE, 0, RT_I64);
      ICAdd(cc, IC_JMP, (I64)done_label, RT_I64);
      if (cc->lex.token != KW_CATCH) {
        Error(cc, "Expected 'catch' after 'try' block");
        return false;
      }
      LexNext(cc);  // Skip 'catch'
      ICAdd(cc, IC_LABEL, (I64)catch_label, RT_I64);
      catch_label->defined = true;
      if (!ParseStatement(cc)) return false;
      ICAdd(cc, IC_LABEL, (I64)done_label, RT_I64);
      done_label->defined = true;
      if (cc->lex.token != ',') return true;
      continue;
    }
    // Throw statement
    if (cc->lex.token == KW_THROW) {
      LexNext(cc);
      
      // Optional throw expression (exception code)
      if (cc->lex.token != ';') {
        if (!ParseExpression(cc)) return false;
      } else {
        // Default exception code
        ICAdd(cc, IC_IMM_I64, -1, RT_I64);
      }
      ICAdd(cc, IC_THROW, 0, RT_I64);  // except_ch = value; unwind to __try_top's catch
      LexExpect(cc, ';');
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    // Asm block (following PrsStmt.HC:949-955)
    if (cc->lex.token == KW_ASM) {
      I64 asm_start_line = cc->lex.line;   // the construct STARTS here; after the skip loop the
                                           // lexer sits on the closing brace
      LexNext(cc);
      
      // Expect opening brace
      if (!LexExpect(cc, '{')) return false;
      
      // Peek: labeled `Name::` (function export) vs unlabeled inline (run in place).
      // TempleOS glbl asm often starts with USE32/ALIGN before the label — scan for any `::`.
      bool want_inline = true;
      {
        LexPush(cc);
        int bc = 1;
        while (bc > 0 && cc->lex.token != TK_EOF) {
          if (cc->lex.token == '{') bc++;
          else if (cc->lex.token == '}') bc--;
          else if (cc->lex.token == TK_DBL_COLON) { want_inline = false; break; }
          if (bc > 0) LexNext(cc);
        }
        LexPopRestore(cc);
      }

      // Try to assemble RISC-V. Labeled x86-only blocks still skip (runtime override by name).
      // Host AOT must soft-skip TempleOS x86 asm (Kernel CallExtStr / PCIBIOS / etc.).
      // Bare-metal REPL: unlabeled inline that fails hard-errors — silent skip was "s2 unchanged".
      CIntermediateCode *asm_saved_tail = cc->ic_tail;
      bool asm_translated = TryAssembleRiscV(cc) && cc->lex.token == (char)0x7d;
      if (!asm_translated) {
        if (asm_saved_tail) { asm_saved_tail->next = NULL; cc->ic_tail = asm_saved_tail; }
        else { cc->ic_head = cc->ic_tail = NULL; }
        int brace_count = 1;
        char *first_label = NULL;   // `_GR_UPDATE_LINE64::` — the name the block would have exported
        char *prev_ident = NULL;
        while (brace_count > 0 && cc->lex.token != TK_EOF) {
          if (cc->lex.token == '{') brace_count++;
          if (cc->lex.token == '}') brace_count--;
          if (!first_label && cc->lex.token == TK_DBL_COLON && prev_ident) first_label = strdup(prev_ident);
          if (cc->lex.token == TK_IDENT && cc->lex.token_str) {
            free(prev_ident);
            prev_ident = strdup(cc->lex.token_str);
          }
          if (brace_count > 0) LexNext(cc);
        }
        free(prev_ident);
#ifdef BARE_METAL
        if (want_inline) {
          // TryAssembleRiscV may already have set a specific hint (e.g. sub+imm → addi).
          if (!cc->error)
            Error(cc, "Invalid or unsupported RISC-V asm{} (inline statements must assemble)");
          if (cc->lex.token == '}') LexNext(cc);
          return false;
        }
#endif
        HolyAsmSkipNote(cc, asm_start_line, "asm{} block", first_label);
        free(first_label);
      }
      // Skip closing brace
      if (cc->lex.token == '}') {
        LexNext(cc);
      }
      
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    // For REPL: skip label lookahead (uses LexPush which crashes in bare metal)
    // Labels are not commonly used in REPL mode anyway
    
    // Match original PrsStmt.HC:1201-1203
    if (cc->lex.token == TK_IDENT) {
      // Label definition: `name:` (target of goto). Peek for the ':'.
      LexPush(cc);
      LexNext(cc);
      bool is_label = (cc->lex.token == ':');
      LexPopRestore(cc);
      if (is_label) {
        CLabel *label = LabelFind(cc, cc->lex.token_str);
        if (!label) label = LabelNew(cc, cc->lex.token_str);
        LexNext(cc);  // name
        LexNext(cc);  // ':'
        ICAdd(cc, IC_LABEL, (I64)label, RT_I64);
        label->defined = true;
        label->flags = cc->try_depth;   // for goto: how many try blocks enclose the label
        if (cc->lex.token == '}') return true;   // `me_done: }` — a label may end a block
        continue;
      }
    }
    // Char literal as statement: `'ab\n';` ≡ PutChars('ab\n');
    if (cc->lex.token == TK_I64 && cc->lex.token_is_char) {
      bool empty = (cc->lex.token_i64 == 0 && cc->lex.token_str && !cc->lex.token_str[0]);
      LexPush(cc);
      LexNext(cc);
      bool whole = (cc->lex.token == ';');
      LexPopRestore(cc);
      if (!whole && empty) {
        // `'' ch;` ≡ PutChars(ch)
        LexNext(cc);
        ICAdd(cc, IC_CALL_START, 0, RT_I64);
        if (!ParseExpression(cc)) return false;
        ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
        if (!EmitCallByName(cc, "PutChars", 1)) return false;
        ICAdd(cc, IC_CALL_END, 0, RT_I64);
        ICAdd(cc, IC_END_EXP, 0, RT_I64);
        if (cc->lex.token == ';') LexNext(cc);
        return true;
      }
      if (whole) {
        ICAdd(cc, IC_CALL_START, 0, RT_I64);
        if (!ParsePrimary(cc)) return false;
        ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
        if (!EmitCallByName(cc, "PutChars", 1)) return false;
        ICAdd(cc, IC_CALL_END, 0, RT_I64);
        ICAdd(cc, IC_END_EXP, 0, RT_I64);
        if (cc->lex.token == ';') LexNext(cc);
        return true;
      }
    }
    // String literal as statement — HolyC's implicit print: `"fmt", args…;` ≡ Print("fmt", args…);
    if (cc->lex.token == TK_STR) {
      ICAdd(cc, IC_CALL_START, 0, RT_I64);
      bool fmt_follows = false;
      if (cc->lex.token_str && !cc->lex.token_str[0]) {   // `"" fmt,args;` ≡ Print(fmt,args)
        LexPush(cc);
        LexNext(cc);
        fmt_follows = (cc->lex.token != ',' && cc->lex.token != ';');
        LexPopRestore(cc);
      }
      if (fmt_follows) {
        LexNext(cc);
        if (!ParseAssignment(cc)) return false;
      } else if (!ParsePrimary(cc)) return false;   // IC_STR_CONST: address in a0 + eval-stack slot
      ICAdd(cc, IC_PUSH_RES, 0, RT_I64);             // fmt (fixed arg 0)
      // Print may be the kernel's HolyC VARARGS Print (`U0 Print(U8*fmt,...)`, ABI = fmt,argc,argv:
      // the caller collects the args into a frame temp `argv` and passes a count+pointer), or a
      // C-variadic runtime stub in a bare program (args in the arg registers). Match the general
      // call path (see the varargs handling in ParsePrimary): for a varargs Print, store each arg
      // into argv and pass argc/argv; otherwise push them directly. Without this the string-statement
      // form fed the kernel Print its args from the wrong place — %d/%s printed garbage / hung.
      CHashEntry *pe_print = cc->hash_table ? HashFind("Print", cc->hash_table, HTT_FUN) : NULL;
      CHashFun *pfn_print = (pe_print && (pe_print->type & HTT_FUN)) ? (CHashFun *)pe_print : NULL;
      if (pfn_print && pfn_print->is_varargs) {
        int va_cnt = 0; I64 va_base = -1;
        while (cc->lex.token == ',') {
          LexNext(cc);
          if (va_base < 0) va_base = cc->locals_size;
          I64 marker = HOLY_LOCAL_MARKER(va_base + 8 * va_cnt);
          cc->locals_size += 8;
          ICAdd(cc, IC_LEA, marker, RT_I64);
          ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
          if (!ParseAssignment(cc)) return false;
          CIntermediateCode *aic = ICNew(cc, IC_ASSIGN);
          aic->res.type.raw_type = RT_I64;
          aic->res.type.mode = MDF_STK;
          aic->arg1_type_pointed_to = RT_I64;
          if (cc->ic_tail) cc->ic_tail->next = aic; else cc->ic_head = aic;
          cc->ic_tail = aic;
          ICAdd(cc, IC_EVAL_DROP, 8, RT_I64);
          va_cnt++;
        }
        ICAdd(cc, IC_IMM_I64, va_cnt, RT_I64);
        ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
        if (va_cnt > 0) {
          ICAdd(cc, IC_LEA, HOLY_LOCAL_MARKER(va_base), RT_I64);
          ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
        } else {
          ICAdd(cc, IC_IMM_I64, 0, RT_I64);
        }
        ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
        if (!EmitCallByName(cc, "Print", pfn_print->param_cnt)) return false;  // fmt + argc + argv
      } else {
      I64 argc = 1;
      while (cc->lex.token == ',') {
        LexNext(cc);
        if (!ParseAssignment(cc)) return false;
        ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
        argc++;
      }
      if (!EmitCallByName(cc, "Print", argc)) return false;
      }
      ICAdd(cc, IC_CALL_END, 0, RT_I64);
      ICAdd(cc, IC_END_EXP, 0, RT_I64);
      if (cc->lex.token == ';') LexNext(cc);
      cc->last_expr_type = RT_I0;   // an implicit-print statement is void (no command-line answer)
      return true;
    }
    if (!ParseExpressionStatement(cc)) return false;
    if (cc->lex.token != ',') return true;
    // Continue for comma-separated statements
  }
  
  return true;
}


static bool ParseBlock(Compiler *cc) {
  if (!LexExpect(cc, '{')) return false;
  
  SymTablePush(cc);
  
  while (cc->lex.token != '}' && cc->lex.token != TK_EOF) {
    if (!ParseStatement(cc)) {
      SymTablePop(cc);
      return false;
    }
  }
  
  // Don't pop for function bodies - ParseFunction handles that
  // Function bodies share the same scope as parameters
  if (!cc->current_function_exit) {
    SymTablePop(cc);
  }
  
  return LexExpect(cc, '}');
}

// ----------------------------------------------------------------------------------------------
// PARSER - CLASSES
// ----------------------------------------------------------------------------------------------


// ---- compile-time constant expressions (array sizes, `$$=` in class bodies) ----
static I64 CEOr(Compiler *cc, I64 dollar, bool *ok);
static I64 CEPrimary(Compiler *cc, I64 dollar, bool *ok) {
  if (cc->lex.token == TK_I64) { I64 v = cc->lex.token_i64; LexNext(cc); return v; }
  if (cc->lex.token == TK_DOLLAR) { LexNext(cc); return dollar; }
  if (cc->lex.token == '(') { LexNext(cc); I64 v = CEOr(cc, dollar, ok); if (!LexExpect(cc, ')')) *ok = false; return v; }
  if (cc->lex.token == '-') { LexNext(cc); return -CEPrimary(cc, dollar, ok); }
  if (cc->lex.token == '+') { LexNext(cc); return  CEPrimary(cc, dollar, ok); } // unary plus: identity
  if (cc->lex.token == '~') { LexNext(cc); return ~CEPrimary(cc, dollar, ok); }
  if (cc->lex.token == '!') { LexNext(cc); return !CEPrimary(cc, dollar, ok); }
  if (cc->lex.token == KW_SIZEOF) {
    LexNext(cc);
    bool paren = (cc->lex.token == '(');
    if (paren) LexNext(cc);
    I64 sz = 8;
    if (IsTypeStartToken(cc)) {
      U8 t = ParseType(cc);
      sz = cc->last_ptr_depth ? 8 : (cc->last_type_class && cc->last_type_class->size > 0 ? cc->last_type_class->size : PrimitiveTypeSize(t));   // depth, not pointed-to type: U0 * has base type 0
      CHashClass *mc = cc->last_type_class;
      while (cc->lex.token == '.' && mc) {   // sizeof(Class.member)
        LexNext(cc);
        CMemberLst *m = mc->member_lst;
        while (m && !(cc->lex.token_str && strcmp(m->str, cc->lex.token_str) == 0)) m = m->next;
        if (!m) { *ok = false; break; }
        sz = m->size;
        mc = m->member_class;
        LexNext(cc);
      }
    } else { *ok = false; }
    if (paren && !LexExpect(cc, ')')) *ok = false;
    return sz;
  }
  if (cc->lex.token == TK_IDENT && cc->lex.hash_entry && (cc->lex.hash_entry->type & HTT_ENUM)) {
    I64 v = ((CHashEnumValue *)cc->lex.hash_entry)->value; LexNext(cc); return v;
  }
  *ok = false;
  return 0;
}
static I64 CEMul(Compiler *cc, I64 d, bool *ok) {
  I64 v = CEPostfixCast(cc, CEPrimary(cc, d, ok));
  while (cc->lex.token == '*' || cc->lex.token == '/' || cc->lex.token == '%') {
    int op = cc->lex.token; LexNext(cc); I64 r = CEPostfixCast(cc, CEPrimary(cc, d, ok));
    v = op == '*' ? v * r : (r ? (op == '/' ? v / r : v % r) : 0);
  }
  return v;
}
static I64 CEAdd(Compiler *cc, I64 d, bool *ok) {
  I64 v = CEMul(cc, d, ok);
  while (cc->lex.token == '+' || cc->lex.token == '-') { int op = cc->lex.token; LexNext(cc); I64 r = CEMul(cc, d, ok); v = op == '+' ? v + r : v - r; }
  return v;
}
static I64 CEShift(Compiler *cc, I64 d, bool *ok) {
  I64 v = CEAdd(cc, d, ok);
  while (cc->lex.token == TK_SHL || cc->lex.token == TK_SHR) { int op = cc->lex.token; LexNext(cc); I64 r = CEAdd(cc, d, ok); v = op == TK_SHL ? v << r : v >> r; }
  return v;
}
static I64 CEAnd(Compiler *cc, I64 d, bool *ok) { I64 v = CEShift(cc, d, ok); while (cc->lex.token == '&') { LexNext(cc); v &= CEShift(cc, d, ok); } return v; }
static I64 CEXor(Compiler *cc, I64 d, bool *ok) { I64 v = CEAnd(cc, d, ok); while (cc->lex.token == '^') { LexNext(cc); v ^= CEAnd(cc, d, ok); } return v; }
// `0x7FEFFFFFFFFFFFFF(F64)` (F64_MAX, inf): a postfix cast on a constant keeps the bits.
static I64 CEPostfixCast(Compiler *cc, I64 v) {
  while (cc->lex.token == '(') {
    LexPush(cc);
    LexNext(cc);
    if (IsTypeStartToken(cc)) {
      U8 saved_pt = cc->last_pointed_to_type;
      CHashClass *saved_tc = cc->last_type_class;
      ParseType(cc);
      while (cc->lex.token == '*') LexNext(cc);
      cc->last_pointed_to_type = saved_pt;
      cc->last_type_class = saved_tc;
      if (cc->lex.token == ')') { LexNext(cc); LexPopNoRestore(cc); continue; }
    }
    LexPopRestore(cc);
    break;
  }
  return v;
}
static I64 CEOr(Compiler *cc, I64 d, bool *ok) { I64 v = CEXor(cc, d, ok); while (cc->lex.token == '|') { LexNext(cc); v |= CEXor(cc, d, ok); } return v; }
// Array dimension `[expr]` (after the '['): constant expression up to ']'.
static bool ParseConstDim(Compiler *cc, I64 *out) {
  bool ok = true;
  I64 v = CEOr(cc, 0, &ok);
  if (!ok) { Error(cc, "Expected constant array size"); return false; }
  *out = v;
  return true;
}

// Members of a class/union body up to (not including) the closing '}'. Class: sequential from
// `start`; union: all at `start`. Nested anonymous `union {…};` / `class {…};` recurse, sharing
// the parent's member list. *agg_size = bytes the body occupies.
static bool ParseClassMembers(Compiler *cc, CHashClass *tmpc, bool is_union, I64 start, I64 *agg_size) {
  I64 cur = start, max_sz = 0;
  CMemberLst *last = tmpc->member_lst;
  while (last && last->next) last = last->next;
  cc->in_class_body++;
  while (cc->lex.token != '}' && cc->lex.token != TK_EOF) {
    if (cc->lex.token == ';') { LexNext(cc); continue; }
    if (cc->lex.token == TK_DOLLAR) {                 // `$$=($$+15)&-16;` — set the current offset
      LexNext(cc);
      if (!LexExpect(cc, '=')) { cc->in_class_body--; return false; }
      bool ok = true;
      I64 v = CEOr(cc, is_union ? start : cur, &ok);
      if (!ok) { Error(cc, "Expected constant offset expression"); cc->in_class_body--; return false; }
      if (is_union) { if (v - start > max_sz) max_sz = v - start; } else cur = v;
      if (cc->lex.token == ';') LexNext(cc);
      continue;
    }
    if (cc->lex.token == KW_UNION || cc->lex.token == KW_CLASS) {
      bool sub_union = (cc->lex.token == KW_UNION);
      LexPush(cc);
      LexNext(cc);
      bool anon = (cc->lex.token == '{');
      LexPopRestore(cc);
      if (anon) {
        LexNext(cc);  // union/class
        LexNext(cc);  // '{'
        I64 sub = 0;
        if (!ParseClassMembers(cc, tmpc, sub_union, is_union ? start : cur, &sub)) return false;
        if (!LexExpect(cc, '}')) return false;
        if (cc->lex.token == ';') LexNext(cc);
        if (is_union) { if (sub > max_sz) max_sz = sub; } else cur += sub;
        last = tmpc->member_lst;
        while (last && last->next) last = last->next;
        continue;
      }
    }
    // Type, then one or more declarators.
    U8 member_type = ParseType(cc);
    CHashClass *mcls = cc->last_type_class;
    U8 base_ptr = cc->last_pointed_to_type;
    if (cc->error) return false;
    for (;;) {
      U8 ptr = base_ptr;
      U8 mdepth = base_ptr ? cc->last_ptr_depth : 0;
      while (cc->lex.token == '*') { ptr = member_type ? member_type : RT_I64; mdepth++; LexNext(cc); }
      char *member_name = NULL;
      bool is_fnptr = false;
      if (cc->lex.token == '(') {                     // T (*name)(params), T (**name)(...)
        LexNext(cc);
        while (cc->lex.token == '*') LexNext(cc);
        if (cc->lex.token != TK_IDENT && !(cc->lex.token >= 300 && cc->lex.token_str)) { Error(cc, "Expected member name"); return false; }
        member_name = strdup(cc->lex.token_str);
        LexNext(cc);
        if (!LexExpect(cc, ')')) return false;
        if (cc->lex.token == '(') {
          int depth = 0;
          do {
            if (cc->lex.token == '(') depth++;
            else if (cc->lex.token == ')') depth--;
            LexNext(cc);
          } while (depth > 0 && cc->lex.token != TK_EOF);
        }
        is_fnptr = true;
      } else if (cc->lex.token == TK_IDENT ||
                 (cc->lex.token >= 300 && cc->lex.token_str)) {
        // Keywords may be member names (`U16 reg` in CICArg; TempleOS allows this).
        member_name = strdup(cc->lex.token_str);
        LexNext(cc);
      } else {
        // Junk (e.g. asm-only constructs): skip this declaration.
        while (cc->lex.token != ';' && cc->lex.token != '}' && cc->lex.token != TK_EOF) LexNext(cc);
        break;
      }
      I64 member_size;
      if (ptr || is_fnptr) member_size = 8;
      else if (mcls && mcls->size > 0) member_size = mcls->size;
      else if (member_type == RT_U0 || member_type == RT_I0) member_size = 0;   // zero-size position marker (e.g. CDirEntry.start, CMemUsed.start) — must not consume a slot
      else { member_size = PrimitiveTypeSize(member_type); if (member_size <= 0) member_size = 8; }
      I64 elem_size = member_size;
      bool is_array = false;
      I64 mdims[4]; int m_nd = 0;
      while (cc->lex.token == '[') {                  // T name[N][M], N a constant expression
        LexNext(cc);
        is_array = true;
        if (cc->lex.token != ']') {
          I64 n = 0;
          if (!ParseConstDim(cc, &n)) { free(member_name); return false; }
          member_size *= n;
          if (m_nd < 4) mdims[m_nd++] = n;
        } else if (m_nd < 4) mdims[m_nd++] = 0;       // `name[]`
        if (!LexExpect(cc, ']')) { free(member_name); return false; }
      }
      CMemberLst *m = calloc(1, sizeof(CMemberLst));
      m->str = member_name;
      m->raw_type = (ptr || is_fnptr) ? RT_I64 : member_type;
      m->pointed_to_type = ptr;
      m->ptr_depth = ptr ? (mdepth ? mdepth : 1) : 0;
      m->is_array = is_array;
      // Pointer member stride/width: prefer the pointee class size (e.g. `U32i union U32` is
      // 4 bytes even when raw_type stayed RT_I64). Matches local `U32 *p` / PtrElemInfo.
      // Without this, `rv_fb.pixels[i]` stepped 8 bytes and left every other FB pixel black.
      m->elem_size = ptr ? PrimitiveTypeSize(ptr) : elem_size;
      if (ptr && mcls && mcls->size > 0) m->elem_size = mcls->size;
      if (ptr) m->pointed_to_type = ScalarTypeForSize(ptr, m->elem_size);
      // `T *arr[N]` member: the ELEMENTS are pointers (8 bytes), not T. With the pointee
      // size above, `cmp.internal_types[raw_type]=tmpc` strode by sizeof(CHashClass) and
      // scattered heap pointers across the compiler unit's globals (char_bmp_hex_numeric
      // lost bits A-E; only `0xF` lexed).
      if (ptr && is_array) { m->elem_size = 8; m->pointed_to_type = RT_I64; }
      m->member_class = (ptr || is_array) ? mcls : mcls;
      m->size = member_size;
      // Multi-dim member: subscript k steps by the product of the dims below it.
      if (m_nd > 1 && !ptr) {
        m->ndims = m_nd;
        for (int k = 0; k < m_nd; k++) {
          I64 st = elem_size;
          for (int j = k + 1; j < m_nd; j++) st *= mdims[j];
          m->dim_stride[k] = st;
        }
      }
      if (cc->lex.token == ':') {                     // bit field
        LexNext(cc);
        if (cc->lex.token != TK_I64) { Error(cc, "Expected bit field width"); return false; }
        m->bit_width = cc->lex.token_i64;
        LexNext(cc);
        m->size = (m->bit_width + 7) / 8;
      }
      if (is_union) { m->offset = start; if (m->size > max_sz) max_sz = m->size; }
      else { m->offset = cur; cur += m->size; }
      if (last) last->next = m; else tmpc->member_lst = m;
      last = m;
      // `U8 name[STR_LEN] format "$$DA-P,…$$";` — DolDoc form meta-data on a member: skipped.
      if (cc->lex.token == TK_IDENT && cc->lex.token_str && !strcmp(cc->lex.token_str, "format")) {
        LexNext(cc);
        if (cc->lex.token == TK_STR) LexNext(cc);
      }
      if (cc->lex.token == ',') { LexNext(cc); continue; }
      break;
    }
    while (cc->lex.token != ';' && cc->lex.token != '}' && cc->lex.token != TK_EOF) LexNext(cc);
    if (cc->lex.token == ';') LexNext(cc);
  }
  cc->in_class_body--;
  *agg_size = is_union ? max_sz : cur - start;
  return true;
}

bool ParseClass(Compiler *cc) {
  // Parse: class ClassName { members }; or union ClassName { members };
  
  bool is_union = false;
  if (cc->lex.token == KW_UNION) {
    is_union = true;
    LexNext(cc);
  } else if (cc->lex.token == KW_CLASS) {
    LexNext(cc);
  } else {
    { PF_TRACE(__LINE__); return false; }
  }
  
  if (cc->lex.token != TK_IDENT) {
    Error(cc, "Expected class name");
    { PF_TRACE(__LINE__); return false; }
  }
  
  char *class_name = strdup(cc->lex.token_str);
  LexNext(cc);
  cc->class_decl_follows = false;
  if (cc->lex.token == ';') {
    // Forward declaration (`extern class CDoc;`): register an empty class so pointers to it parse.
    if (!HashFind(class_name, cc->hash_table, HTT_CLASS)) {
      CHashClass *fwd = calloc(1, sizeof(CHashClass));
      fwd->str = strdup(class_name);
      fwd->type = HTT_CLASS;
      fwd->raw_type = RT_I64;
      HashAdd((CHashEntry *)fwd, cc->hash_table);
    }
    free(class_name);
    LexNext(cc);
    return true;
  }
  
  // Create class hash entry — or refill a forward-declared / built-in one in place, so pointers
  // to it (and `extern class X;` users) see the real definition.
  CHashClass *existing_cls = (CHashClass *)HashFind(class_name, cc->hash_table, HTT_CLASS);
  CHashClass *tmpc = existing_cls ? existing_cls : calloc(1, sizeof(CHashClass));
  if (existing_cls) { tmpc->member_lst = NULL; tmpc->size = 0; tmpc->base_class = NULL; }
  else tmpc->str = strdup(class_name);
  tmpc->type = HTT_CLASS;
  tmpc->raw_type = RT_I64;  // Classes are pointers
  tmpc->size = 0;  // Will be calculated from members
  tmpc->ptr_stars_cnt = 0;
  tmpc->base_class = NULL;
  tmpc->member_lst = NULL;
  // Register now so members may refer to the class itself (`class Lst { Lst *next; }`);
  // size is filled in below. Error paths leave the entry in place (never freed).
  if (!existing_cls) HashAdd((CHashEntry*)tmpc, cc->hash_table);
  
  // Handle inheritance: class Name : BaseClass
  if (cc->lex.token == ':') {
    LexNext(cc);
    if (cc->lex.token != TK_IDENT) {
      Error(cc, "Expected base class name");
      free(class_name);
      /* tmpc stays registered */
      { PF_TRACE(__LINE__); return false; }
    }
    
    // Look up base class
    CHashEntry *base = HashFind(cc->lex.token_str, cc->hash_table, HTT_CLASS);
    if (base && (base->type & HTT_CLASS)) {
      tmpc->base_class = (CHashClass*)base;
      tmpc->size = tmpc->base_class->size;  // Inherit size
    }
    
    LexNext(cc);
  }
  
  if (!LexExpect(cc, '{')) {
    free(class_name);
    /* tmpc stays registered */
    { PF_TRACE(__LINE__); return false; }
  }
  
  // Parse members (nested anonymous unions/classes, comma declarators, fn-pointer members)
  {
    I64 base_off = tmpc->size;      // after a base class
    I64 min_size = 0;
    if (cc->class_base_type) {      // `I64 class X`: the value is that scalar; members overlay it
      tmpc->raw_type = cc->class_base_type;
      min_size = PrimitiveTypeSize(cc->class_base_type);
      base_off = 0;
      cc->class_base_type = 0;
    }
    I64 agg = 0;
    if (!ParseClassMembers(cc, tmpc, is_union, base_off, &agg)) {
      free(class_name);
      { PF_TRACE(__LINE__); return false; }
    }
    I64 total = is_union ? (agg > base_off ? agg : base_off) : base_off + agg;
    tmpc->size = total > min_size ? total : min_size;
#ifndef BARE_METAL
    // HOLYC_DUMP_CLASS=<name> prints the member table this parse produced. The
    // question it answers: when `offset(C.m)` says "unknown member", was m never
    // added, or added and unfindable? Those have different fixes.
    {
      const char *want = getenv("HOLYC_DUMP_CLASS");
      if (want && class_name && !strcmp(want, class_name)) {
        I64 n = 0;
        fprintf(stderr, "[class] %s size=%lld\n", class_name, (long long)tmpc->size);
        for (CMemberLst *m = tmpc->member_lst; m; m = m->next, n++)
          fprintf(stderr, "  [%2lld] %-24s off=%-5lld size=%-4lld raw=%d ptr=%d depth=%d arr=%d\n",
                  (long long)n, m->str ? m->str : "(null)", (long long)m->offset,
                  (long long)m->size, (int)m->raw_type, (int)m->pointed_to_type,
                  (int)m->ptr_depth, (int)m->is_array);
        fprintf(stderr, "[class] %s: %lld member(s)\n", class_name, (long long)n);
      }
    }
    // HOLYC_WARN_ALIGN=1 reports 2/4/8-byte members placed at an offset that is not a
    // multiple of their size. HolyC packs members with no padding (correct TempleOS
    // semantics — x86 tolerates misaligned loads, and Terry hand-padded instead), but
    // RISC-V does not make that promise: a misaligned ld/sd may be emulated in
    // hardware, trapped to firmware, or faulted, depending on the core. The RV backend
    // emits a real full-width ld/sd at whatever offset the member lands on, so this is
    // a portability signal and not a style nit.
    // Off by default and layout-changing nothing: stock TempleOS headers are
    // hand-padded and pass silently. Arrays are skipped — `size` there is the whole
    // array, not the element, so its alignment requirement is not `size`.
    if (getenv("HOLYC_WARN_ALIGN") && class_name) {
      for (CMemberLst *m = tmpc->member_lst; m; m = m->next) {
        if (m->is_array || !m->str) continue;
        if (m->size != 2 && m->size != 4 && m->size != 8) continue;
        if (m->offset % m->size == 0) continue;
        fprintf(stderr, "[align] %s.%s off=%lld size=%lld (off %% %lld == %lld)\n",
                class_name, m->str, (long long)m->offset, (long long)m->size,
                (long long)m->size, (long long)(m->offset % m->size));
      }
    }
#endif
  }
  if (!LexExpect(cc, '}')) {
    free(class_name);
    /* tmpc stays registered */
    { PF_TRACE(__LINE__); return false; }
  }
  
  // (already in the hash table — registered before the members)
  
  free(class_name);
  
  // `class X {…} a, *b[N];` — leave the declarators to the caller (ParseTopLevel). After a
  // consumed ';' nothing follows: the caller must not mistake the next statement's first
  // identifier (a global's name) for a declarator.
  cc->last_type_class = tmpc;
  cc->last_pointed_to_type = 0;
  if (cc->lex.token == '*' ||
      (cc->lex.token == TK_IDENT && !(cc->lex.hash_entry &&
       (cc->lex.hash_entry->type & (HTT_CLASS | HTT_INTERNAL_TYPE | HTT_FUN))))) { cc->class_decl_follows = true; return true; }
  return LexExpect(cc, ';');
}

// ----------------------------------------------------------------------------------------------
// PARSER - GLOBAL VARIABLES
// ----------------------------------------------------------------------------------------------

// ---- aggregate initializers: `T a[] = {…}`, `Cls c = {…}`, `Cls arr[] = {{…},{…}}` ----
// Literals (numbers, strings into U8 arrays) are stored into the global's memory at parse time;
// anything else becomes a runtime assignment statement to that address.
static I64 CountAggregateElements(Compiler *cc) {   // at '{': number of top-level elements
  I64 count = 0, depth = 0; bool any = false;
  LexPush(cc);
  LexNext(cc);
  while (cc->lex.token != TK_EOF) {
    if (cc->lex.token == '{') depth++;
    else if (cc->lex.token == '}') { if (depth == 0) break; depth--; }
    else if (cc->lex.token == ',' && depth == 0) count++;
    if (cc->lex.token != ',' || depth) any = true;
    LexNext(cc);
  }
  LexPopRestore(cc);
  return any ? count + 1 : 0;
}
static void StoreTyped(U8 *dst, U8 raw_type, I64 size, I64 v, F64 f, bool is_f64) {
  if (raw_type == RT_F64) { F64 x = is_f64 ? f : (F64)v; for (int i = 0; i < 8; i++) dst[i] = ((U8 *)&x)[i]; return; }
  if (is_f64) v = (I64)f;
  I64 n = size >= 8 ? 8 : size;
  for (I64 i = 0; i < n; i++) dst[i] = (U8)(v >> (8 * i));
}
static bool InitAggregateElement(Compiler *cc, U8 *dst, CHashClass *cls, U8 raw_type, I64 size, bool is_ptr) {
  if (cc->lex.token == '{') {
    if (!cls) { Error(cc, "Nested initializer for a non-class element"); return false; }
    LexNext(cc);
    for (CMemberLst *m = cls->member_lst; m && cc->lex.token != '}'; m = m->next) {
      CHashClass *mcls = (!m->pointed_to_type && !m->is_array) ? m->member_class : NULL;
      I64 esz = m->elem_size > 0 ? m->elem_size : 8;
      if (m->is_array && !(cc->lex.token == TK_STR && !m->pointed_to_type && esz == 1) && m->size > esz) {
        // An array member takes its extent's worth of consecutive elements (`pad[3]` <- 0,0,0),
        // or its own braced list (`{0,2,3,5,7,8,10}`).
        bool sub = (cc->lex.token == '{');
        if (sub) LexNext(cc);
        I64 cnt = m->size / esz;
        CHashClass *ecls = (!m->pointed_to_type) ? m->member_class : NULL;
        for (I64 k = 0; k < cnt && cc->lex.token != '}'; k++) {
          if (!InitAggregateElement(cc, dst + m->offset + k * esz, ecls, m->raw_type, esz, m->pointed_to_type != 0)) return false;
          if (k + 1 < cnt) { if (cc->lex.token == ',') LexNext(cc); else break; }
        }
        if (sub && !LexExpect(cc, '}')) return false;
      } else if (!InitAggregateElement(cc, dst + m->offset, mcls, m->raw_type, m->size, m->pointed_to_type != 0)) return false;
      if (cc->lex.token == ',') LexNext(cc); else break;
    }
    return LexExpect(cc, '}');
  }
  // Literal followed by ',' or '}' → store now.
  if (cc->lex.token == TK_STR || cc->lex.token == TK_I64 || cc->lex.token == TK_F64) {
    LexPush(cc);
    LexNext(cc);
    bool simple = (cc->lex.token == ',' || cc->lex.token == '}');
    LexPopRestore(cc);
    if (simple) {
      if (cc->lex.token == TK_STR && !is_ptr) {           // string into a U8 array
        const char *s = cc->lex.token_str ? cc->lex.token_str : "";
        I64 i = 0;
        for (; s[i] && i < size - 1; i++) dst[i] = (U8)s[i];
        if (size > 0) dst[i] = 0;
        LexNext(cc);
        return true;
      }
      if (cc->lex.token != TK_STR) {
        StoreTyped(dst, raw_type, size, cc->lex.token_i64, cc->lex.token_f64, cc->lex.token == TK_F64);
        LexNext(cc);
        return true;
      }
    }
  }
  // Expression: assign at run time.
  ICAdd(cc, IC_IMM_I64, (I64)dst, RT_I64);
  cc->ic_tail->ic_flags = ICF_GLBL_ADDR;
  ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
  if (!ParseAssignment(cc)) return false;
  if (raw_type == RT_F64 && cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
  else if (raw_type != RT_F64 && cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64);
  ICAdd(cc, IC_ASSIGN, 0, RT_I64);
  cc->ic_tail->arg1_type_pointed_to = raw_type;
  ICAdd(cc, IC_END_EXP, 0, RT_I64);
  return true;
}
static bool ParseGlobalAggregateInit(Compiler *cc, CHashGlblVar *g, U8 var_type) {
  bool is_arr = (g->flags & GVF_ARRAY) != 0;
  bool braced = (cc->lex.token == '{');   // `T a[N]= v1,v2,…;` — HolyC allows no braces
  if (is_arr && g->dim.cnt == 0) {                       // `T a[] = {…}`: size from the initializer
    I64 n = CountAggregateElements(cc);
    g->dim.cnt = g->dim.total_cnt = n;
    g->size = g->element_size * n;
    g->data_addr = calloc(1, (size_t)(g->size > 0 ? g->size : 8));
  }
  I64 elem_size = is_arr ? g->element_size : g->size;
  CHashClass *cls = g->pointed_to_type ? NULL : g->var_class;
  if (!is_arr) return InitAggregateElement(cc, g->data_addr, cls, var_type, g->size, g->pointed_to_type != 0);
  if (braced) LexNext(cc);  // '{'
  I64 total = g->dim.total_cnt > 0 ? g->dim.total_cnt : g->dim.cnt;
  // Row width for a nested-brace multi-dim initializer `{{…},{…}}`: elements per outermost group.
  I64 row = (g->ndims > 1 && elem_size > 0) ? g->dim_stride[0] / elem_size : 0;
  I64 idx = 0;
  while (cc->lex.token != (braced ? '}' : ';') && cc->lex.token != TK_EOF) {
    if (g->ndims > 1 && cc->lex.token == '{' && row > 0) {
      // A braced row: fill up to `row` flat elements, then skip to the next row boundary (short
      // rows zero-pad). Inner arrays deeper than 2-D must use the flat form.
      LexNext(cc);  // '{'
      I64 rstart = idx;
      while (cc->lex.token != '}' && cc->lex.token != TK_EOF && idx < rstart + row) {
        if (idx >= total) { Error(cc, "Too many initializers"); return false; }
        if (!InitAggregateElement(cc, g->data_addr + idx * elem_size, cls, var_type, elem_size, g->pointed_to_type != 0)) return false;
        idx++;
        if (cc->lex.token == ',') LexNext(cc); else break;
      }
      if (!LexExpect(cc, '}')) return false;
      idx = rstart + row;   // align to the next row
    } else {
      if (idx >= total) { Error(cc, "Too many initializers"); return false; }
      if (!InitAggregateElement(cc, g->data_addr + idx * elem_size, cls, var_type, elem_size, g->pointed_to_type != 0)) return false;
      idx++;
    }
    if (cc->lex.token == ',') LexNext(cc); else break;
  }
  if (!braced && cc->lex.token == '}') LexNext(cc);   // TempleOS: `= v1,v2,…};` (stray brace)
  return braced ? LexExpect(cc, '}') : true;
}

static bool ParseGlobalVariable(Compiler *cc, U8 var_type, char *var_name) {
  // Simplified global variable parsing
  // Full version would handle: extern, import, initialization, arrays, etc.
  
  CHashClass *decl_class = cc->last_type_class;

  // Create global variable hash entry
  // `extern I64 x;` then `I64 x = 3;` (or a REPL redefinition): reuse the existing entry.
  CHashGlblVar *existing = (CHashGlblVar *)HashFind(var_name, cc->hash_table, HTT_GLBL_VAR);
  // Capture what the name meant BEFORE this declaration repurposes the entry — a redefinition
  // with a DIFFERENT type silently re-aims every offset already compiled against the old one.
  CHashClass *prev_class = existing ? existing->var_class : NULL;
  I64 prev_elem = existing ? existing->element_size : 0;
  CHashGlblVar *tmpg = existing ? existing : calloc(1, sizeof(CHashGlblVar));
  tmpg->str = strdup(var_name);
  tmpg->type = HTT_GLBL_VAR;
  tmpg->use_cnt = 0;
  tmpg->flags = 0;
  tmpg->var_class = decl_class;
  tmpg->raw_type = var_type;
  tmpg->pointed_to_type = cc->last_pointed_to_type;
  tmpg->ptr_depth = cc->last_ptr_depth;
  if (tmpg->pointed_to_type && decl_class && decl_class->size > 0)
    tmpg->pointed_to_type = ScalarTypeForSize(tmpg->pointed_to_type, decl_class->size);
  if (cc->last_pointed_to_type) tmpg->raw_type = RT_I64;  // the variable itself is a pointer: 8-byte loads/stores
  
  // Find type class in hash table
  // For now, just use default size based on var_type
  I64 base_size = 8;
  if (decl_class) {
    base_size = decl_class->size;
    if (base_size <= 0) base_size = 8;
  } else {
    switch (var_type) {
      case RT_I8: case RT_U8: base_size = 1; break;
      case RT_I16: case RT_U16: base_size = 2; break;
      case RT_I32: case RT_U32: base_size = 4; break;
      case RT_F64: case RT_I64: case RT_U64: base_size = 8; break;
      default: base_size = 8; break;
    }
  }
  if (cc->last_pointed_to_type) {
    base_size = 8;  // Pointers are 8 bytes
  }
  // A global redefined with a different type is almost always a COLLISION, not an intent.
  // Demo/Games/Maze.HC declares `U32 text[TEXT_ROWS][TEXT_COLS]`, which lands on the kernel's
  // `CTextGlbls text;` (KGlbls.HC:30) and re-aims the kernel's own member offsets at a U32
  // array — the game then faulted during boot with nothing to point at. Re-declaring the SAME
  // type stays silent: `extern I64 x;` then `I64 x = 3;` is the documented reason this path
  // reuses the entry at all. HOLYC_STRICT_GLOBALS=0 downgrades to a warning.
  if (existing && prev_elem && (prev_class != decl_class || prev_elem != base_size)) {
    const char *genv = getenv("HOLYC_STRICT_GLOBALS");
    const char *pname = prev_class && prev_class->str ? prev_class->str : "scalar";
    const char *nname = decl_class && decl_class->str ? decl_class->str : "scalar";
    char gmsg[256];
    snprintf(gmsg, sizeof gmsg,
             "Global '%s' redefined with a different type (was %s/%lld bytes, now %s/%lld)",
             var_name, pname, (long long)prev_elem, nname, (long long)base_size);
    if (genv && genv[0] == '0')
      fprintf(stderr, "WARN: %s\n", gmsg);
    else
      Error(cc, gmsg);
  }
  tmpg->element_size = base_size;
  tmpg->size = base_size;
  
  // Handle array dimensions
  tmpg->dim.next = NULL;
  tmpg->dim.cnt = 0;
  tmpg->dim.total_cnt = 1;
  
  if (cc->lex.token == '[') {
    // `T name[N][M]…`: flat storage; subscript k advances by dim_stride[k] bytes (mirrors locals).
    I64 dims[4]; int nd = 0; I64 first = 0;
    while (cc->lex.token == '[') {
      LexNext(cc);
      I64 dimv = 0;   // `[]` on the first dimension: sized by the aggregate initializer
      if (cc->lex.token != ']' && !ParseConstDim(cc, &dimv)) { PF_TRACE(__LINE__); return false; }
      if (!LexExpect(cc, ']')) { PF_TRACE(__LINE__); return false; }
      if (nd == 0) first = dimv;
      if (nd < 4) dims[nd] = dimv;
      nd++;
    }
    if (nd > 4) { Error(cc, "Too many array dimensions (max 4)"); return false; }
    I64 total = 1; for (int k = 0; k < nd; k++) total *= dims[k];
    tmpg->dim.cnt = first;              // first dimension count (for `[]`-init sizing)
    tmpg->dim.total_cnt = total;
    tmpg->ndims = nd;
    for (int k = 0; k < nd; k++) { I64 st = base_size; for (int j = k+1; j < nd; j++) st *= dims[j]; tmpg->dim_stride[k] = st; }
    tmpg->size *= total;
    tmpg->flags |= GVF_ARRAY;
  }
  
  // Allocate memory for the global
  tmpg->data_addr = calloc(1, tmpg->size);
  // Register first so the initializer may refer to the variable, then compile the initializer
  // as an assignment statement (any expression, not just a literal). At top level it runs in
  // source order (REPL: now; AOT: in the entry chunk).
  if (!existing) HashAdd((CHashEntry*)tmpg, cc->hash_table);
  if (cc->lex.token == '=') {
    LexNext(cc);
    if (cc->lex.token == '{' || ((tmpg->flags & GVF_ARRAY) && cc->lex.token != TK_STR && tmpg->dim.cnt > 0)) {
      if (!ParseGlobalAggregateInit(cc, tmpg, var_type)) return false;
      goto after_init;
    }
    // Plain literal initializer: store it now (init-once — matters for `static` locals, whose
    // declaration is re-executed on every call).
    bool literal = false;
    if (cc->lex.token == TK_I64 || cc->lex.token == TK_F64) {
      LexPush(cc);
      LexNext(cc);
      literal = (cc->lex.token == ';' || cc->lex.token == ',');
      LexPopRestore(cc);
    }
    if (literal) {
      bool is_f64_var = (var_type == RT_F64 && !cc->last_pointed_to_type);
      if (cc->lex.token == TK_I64) {
        I64 v = cc->lex.token_i64;
        if (is_f64_var) *(F64*)tmpg->data_addr = (F64)v;
        else if (tmpg->size == 1) *(I8*)tmpg->data_addr = (I8)v;
        else if (tmpg->size == 2) *(I16*)tmpg->data_addr = (I16)v;
        else if (tmpg->size == 4) *(I32*)tmpg->data_addr = (I32)v;
        else *(I64*)tmpg->data_addr = v;
      } else if (is_f64_var) {
        *(F64*)tmpg->data_addr = cc->lex.token_f64;
      } else {
        *(I64*)tmpg->data_addr = (I64)cc->lex.token_f64;
      }
      LexNext(cc);
      return true;
    }
    ICAdd(cc, IC_IMM_I64, (I64)tmpg->data_addr, RT_I64);
    cc->ic_tail->ic_flags = ICF_GLBL_ADDR;
    ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
    if (!ParseAssignment(cc)) return false;
    {
      bool is_f64_var = (var_type == RT_F64 && !cc->last_pointed_to_type);
      if (is_f64_var && cc->last_expr_type != RT_F64) ICAdd(cc, IC_TO_F64, 0, RT_F64);
      else if (!is_f64_var && cc->last_expr_type == RT_F64) ICAdd(cc, IC_TO_I64, 0, RT_I64);
    }
    ICAdd(cc, IC_ASSIGN, 0, RT_I64);
    if (cc->ic_tail) cc->ic_tail->arg1_type_pointed_to = (tmpg->flags & GVF_ARRAY) ? RT_I64 : var_type;
    ICAdd(cc, IC_END_EXP, 0, RT_I64);
  }
after_init:
  
  // Handle comma-separated declarations (`T a, *b, c[4]`: each declarator has its own stars)
  if (cc->lex.token == ',') {
    LexNext(cc);
    cc->last_pointed_to_type = 0;
    while (cc->lex.token == '*') {
      cc->last_pointed_to_type = var_type;
      LexNext(cc);
    }
    if (cc->lex.token == TK_IDENT) {
      char *next_name = strdup(cc->lex.token_str);
      LexNext(cc);
      cc->last_type_class = decl_class;
      bool result = ParseGlobalVariable(cc, var_type, next_name);
      free(next_name);
      return result;
    }
  }
  
  // Expect semicolon
  bool ok = LexExpect(cc, ';');
  cc->last_type_class = decl_class;
  return ok;
}

// ----------------------------------------------------------------------------------------------
// PARSER - FUNCTIONS
// ----------------------------------------------------------------------------------------------

// `...`: HolyC passes the extra arguments as hidden `argc` and `I64 *argv` parameters after
// the fixed ones (the caller builds the array; see the varargs call site in ParsePrimary).
static void DefineVarargParams(Compiler *cc, int *param_count, Symbol **first_param) {
  const char *names[2] = { "argc", "argv" };
  for (int i = 0; i < 2; i++) {
    Symbol *p = SymbolDefine(cc, names[i], SYM_VAR);
    p->data_type = RT_I64;
    p->pointed_to_type = i ? RT_I64 : 0;
    p->size = 8;
    p->offset = -1000 - *param_count;
    if (!*first_param) *first_param = p;
    (*param_count)++;
  }
}

bool ParseFunction(Compiler *cc) {
  // Clear IC chain for this function (TempleOS does this per-function)
  cc->ic_head = NULL;
  cc->ic_tail = NULL;
  
  // Parse return type - could be keyword OR identifier from hash table
  U8 return_type = RT_I64;  // Default
  
  // With hash table, types like I64, U8, Bool are TK_IDENT
  if ((cc->lex.token >= KW_I0 && cc->lex.token <= KW_F64) ||
      (cc->lex.token == TK_IDENT && cc->lex.hash_entry && 
       (cc->lex.hash_entry->type & (HTT_CLASS | HTT_INTERNAL_TYPE)))) {
    return_type = ParseType(cc);
  } else if (cc->lex.token == TK_IDENT) {
    // Unknown type name - treat as I64 for now
    LexNext(cc);
    return_type = RT_I64;
  } else {
    Error(cc, "Expected type");
    { PF_TRACE(__LINE__); return false; }
  }
  // Pointer-ness of the RETURN type, captured here because parsing the parameter
  // list calls ParseType again and overwrites last_pointed_to_type/last_ptr_depth.
  // Without this a call result has no pointee, so `*Fn()` on a `U32 *`-returning
  // function derefs 8 bytes instead of 4 (see ParseUnary's deref width sources).
  U8 ret_pointee = cc->last_pointed_to_type;
  U8 ret_depth = cc->last_ptr_depth;

  // Parse function name
  if (cc->lex.token == KW_THROW) {
    // `U0 throw(I64 ch=0,Bool no_log=FALSE) {…}` — the kernel's own throw; here `throw` is
    // an intrinsic (IC_THROW unwinds to the handler), so skip the declaration or definition.
    int depth = 0;
    while (cc->lex.token != TK_EOF) {
      if (cc->lex.token == '(' ) depth++;
      else if (cc->lex.token == ')') depth--;
      else if (depth == 0 && cc->lex.token == ';') { LexNext(cc); return true; }
      else if (depth == 0 && cc->lex.token == '{') {
        int bd = 0;
        while (cc->lex.token != TK_EOF) {
          if (cc->lex.token == '{') bd++;
          else if (cc->lex.token == '}') { bd--; if (bd == 0) { LexNext(cc); return true; } }
          LexNext(cc);
        }
        return true;
      }
      LexNext(cc);
    }
    return true;
  }
  if (cc->lex.token != TK_IDENT) {
    Error(cc, "Expected function name");
    { PF_TRACE(__LINE__); return false; }
  }
  
  char *name = strdup(cc->lex.token_str);
  LexNext(cc);
  if ((!strcmp(name, "Fs") || !strcmp(name, "Gs")) && cc->fs_var) {
    // `public _intern IC_FS CTask *Fs();` — the register intrinsic; `Fs` is a built-in global here.
    int depth = 0;
    while (cc->lex.token != TK_EOF && !(depth == 0 && cc->lex.token == ';')) {
      if (cc->lex.token == '(') depth++; else if (cc->lex.token == ')') depth--;
      LexNext(cc);
    }
    if (cc->lex.token == ';') LexNext(cc);
    free(name);
    return true;
  }
  
  // Define function symbol
  Symbol *sym = SymbolDefine(cc, name, SYM_FUNCTION);
  sym->data_type = return_type;
  // Parameters get their own scope; every exit below restores the enclosing one.
  SymTable *fn_scope = cc->symtab;
  SymTablePush(cc);
  
  // Hash entry: one CHashFun per name (forward decl + definition share it); label lives on hash
  CHashFun *func_hash = (CHashFun *)HashFind(name, cc->hash_table, HTT_FUN);
  CLabel *func_label;
  if (func_hash) {
    // Reuse the forward-decl label only within this unit; a stale one (REPL redefinition)
    // would never be re-resolved against the new buffer.
    func_label = (func_hash->entry_label && LabelInUnit(cc, (CLabel *)func_hash->entry_label))
                     ? (CLabel *)func_hash->entry_label : LabelNew(cc, name);
    func_hash->entry_label = func_label;
  } else {
    func_hash = calloc(1, sizeof(CHashFun));
    if (!func_hash) {
      free(name);
      { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
    }
    func_hash->str = strdup(name);
    if (!func_hash->str) {
      free(func_hash);
      free(name);
      { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
    }
    func_hash->type = HTT_FUN;
    func_hash->exe_addr = 0;
    func_hash->return_class = NULL;
    func_hash->arg_cnt = 0;
    func_hash->member_lst = NULL;
    HashAdd((CHashEntry *)func_hash, cc->hash_table);
    func_label = LabelNew(cc, name);
    func_hash->entry_label = func_label;
  }
  cc->last_compiled_func = func_hash;
  sym->address = (I64)func_label;
  cc->last_var_symbol = NULL;
  cc->last_global_var = NULL;
  cc->current_fn_ret_type = return_type;
  
  if (!LexExpect(cc, '(')) {
    free(name);
    { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
  }
  
  // Track parameters for saving in prologue
  int param_count = 0;
  bool has_varargs = false;
  Symbol *first_param = NULL;  // Track first parameter to save them later
  
  if (cc->lex.token != ')') {
    // Check for varargs first
    if (cc->lex.token == TK_ELLIPSIS) {
      has_varargs = true;
      DefineVarargParams(cc, &param_count, &first_param);
      LexNext(cc);
      // Varargs must be last parameter
      if (cc->lex.token != ')') {
        Error(cc, "... must be last parameter");
        free(name);
        { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
      }
    } else {
      do {
        // Check for ... in parameter list
        if (cc->lex.token == TK_ELLIPSIS) {
          has_varargs = true;
          DefineVarargParams(cc, &param_count, &first_param);
          LexNext(cc);
          break;  // ... must be last
        }
        
        U8 param_type = ParseType(cc);
        CHashClass *param_decl_class = cc->last_type_class;
        if (cc->lex.token == '(') {
          char *fp_name = NULL;
          int fp_param_cnt = 0;
          // A `T (*f[N])(…)` parameter decays to the same pointer as `T (*f)(…)`: ignore the extent.
          if (!ParseFunctionPointerDeclarator(cc, &fp_name, &fp_param_cnt, NULL)) {
            free(name);
            { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
          }

          // `U8 (*link_cvt)(U8 *st)=&TOSLinkCvt1`: a function-pointer parameter may carry a
          // default like any other. It is never an integer constant, so it keeps its source text
          // and is re-read at each call site (Demo/ToHtmlToTXTDemo/ToHtml.HC and two others).
          bool fp_has_default = false;
          I64 fp_default_val = 0;
          char *fp_default_src = NULL;
          ParseParamDefault(cc, RT_I64, &fp_has_default, &fp_default_val, &fp_default_src);

          Symbol *param = SymbolDefine(cc, fp_name, SYM_VAR);
          param->data_type = RT_I64;
          param->has_default = fp_has_default;
          param->default_val = fp_default_val;
          param->default_src = fp_default_src;
          param->extra = NULL;
          param->pointed_to_type = RT_I64;
          param->is_function_pointer = true;
          param->function_return_type = param_type;
          param->func_ptr_param_count = fp_param_cnt;
          param->size = 8;
          param->offset = -1000 - param_count;

          if (!first_param) first_param = param;

          free(fp_name);

          param_count++;
          cc->last_type_class = NULL;

          if (cc->lex.token == ',' || cc->lex.token == ';') {   // TempleOS sources also use ';' here
            LexNext(cc);
          }
          continue;
        }
      char *param_name;
      if (cc->lex.token == TK_IDENT) {
        param_name = strdup(cc->lex.token_str);
        LexNext(cc);
      } else if (cc->lex.token == ',' || cc->lex.token == ';' || cc->lex.token == ')') {
        char unnamed[32] = "__unnamed";   // `U0 LoadPass2(U8 *src,U8 *module_base,I64)`: unnamed parameter
        { int k = 9, v = param_count, nd = 0; char d[8];
          do { d[nd++] = (char)('0' + v % 10); v /= 10; } while (v);
          while (nd) unnamed[k++] = d[--nd];
          unnamed[k] = 0; }
        param_name = strdup(unnamed);
      } else {
        Error(cc, "Expected parameter name");
        free(name);
        { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
      }
      
      // Handle array parameters
      if (cc->lex.token == '[') {
        LexNext(cc);  // Skip '['
        // Skip array size if present
        if (cc->lex.token == TK_I64) {
          LexNext(cc);
        }
        if (!LexExpect(cc, ']')) {
          free(param_name);
          free(name);
          { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
        }
        // Arrays passed as pointers
        param_type = RT_I64;
        param_decl_class = NULL;
      }
      
      // Handle default parameter values
      bool has_default = false;
      I64 default_val = 0;
      char *default_src = NULL;
      ParseParamDefault(cc, param_type, &has_default, &default_val, &default_src);
      
      // Define parameter as local variable
      // ALL parameters go on stack (spilled in prologue)
      Symbol *param = SymbolDefine(cc, param_name, SYM_VAR);
      param->data_type = param_type;
      param->has_default = has_default;
      param->default_val = default_val;
      param->default_src = default_src;
      param->extra = param_decl_class;
      param->pointed_to_type = cc->last_pointed_to_type;
      param->ptr_depth = cc->last_ptr_depth;
      if (param->pointed_to_type && param_decl_class && param_decl_class->size > 0)
        param->pointed_to_type = ScalarTypeForSize(param->pointed_to_type, param_decl_class->size);
      if (cc->last_pointed_to_type) param->data_type = RT_I64;

      // Record size metadata for class parameters (best effort)
      int param_size;
      if (param_decl_class) {
        param_size = (int)param_decl_class->size;
        if (param_size <= 0) param_size = 8;
      } else {
        switch (param_type) {
          case RT_I8: case RT_U8: param_size = 1; break;
          case RT_I16: case RT_U16: param_size = 2; break;
          case RT_I32: case RT_U32: param_size = 4; break;
          default: param_size = 8; break;
        }
      }
      param->size = param_size;
      
      // Parameters saved at [sp+16], [sp+24], [sp+32], ...
      // Frame size = 16 + params*8 + locals
      // S0 = sp + frame_size (points to old SP)
      // param[i] saved at sp + 16 + i*8
      // Relative to S0: param[i] at S0 - (frame_size - 16 - i*8)
      //                            = S0 - 16 - params*8 - locals + 16 + i*8
      //                            = S0 - params*8 - locals + i*8
      // For first param (i=0): S0 - params*8 - locals
      // For second param (i=1): S0 - params*8 - locals + 8
      // Temporary - mark as parameter with index
      param->offset = -1000 - param_count;  // Will be fixed after parsing all params
      
      // Track param list
      if (!first_param) first_param = param;
      
      free(param_name);
      
      // Increment AFTER setting offset to use correct index
      param_count++;
      cc->last_type_class = param_decl_class;
      
        if (cc->lex.token == ',' || cc->lex.token == ';') {   // `I64 num;I64 width` (HolyC allows ';')
          LexNext(cc);
        }
      } while (cc->lex.token != ')' && cc->lex.token != TK_EOF && !has_varargs);
    }
  }
  
  cc->last_type_class = NULL;

  // Update hash entry with arg count
  func_hash->arg_cnt = param_count;
  func_hash->raw_type = return_type;   // call sites type the result from this (F64 results)
  // Pointer returns: call sites need the pointee to size a deref of the result.
  // Only widen — a forward decl and its definition share one CHashFun, and the
  // declaration that knew the pointee must not be cleared by one that did not.
  if (ret_depth > 0 && ret_pointee) {
    func_hash->ptr_stars_cnt = ret_depth;
    func_hash->ret_pointed_to = ret_pointee;
  }
  
  if (!LexExpect(cc, ')')) {
    free(name);
    { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
  }
  
  // Collect all parameter symbols
  Symbol *params[16] = {0};  // Max 16 params
  Symbol *param_sym = cc->symtab->symbols;
  while (param_sym) {
    if (param_sym->offset < -900) {  // It's a parameter marker
      int i = -(param_sym->offset + 1000);
      if (i >= 0 && i < 16) {
        params[i] = param_sym;
      }
    }
    param_sym = param_sym->next;
  }
  // Remember per-parameter defaults on the function entry (parameter symbols die with the scope).
  func_hash->param_cnt = param_count;
  func_hash->is_varargs = has_varargs;
  func_hash->param_typed = true;
  func_hash->param_f64_mask = 0;
  for (int i = 0; i < param_count && i < 16; i++)
    if (params[i] && params[i]->data_type == RT_F64 && !params[i]->pointed_to_type) func_hash->param_f64_mask |= 1u << i;
  for (int i = 0; i < param_count && i < 16; i++) {
    func_hash->param_has_default[i] = params[i] ? (U8)params[i]->has_default : 0;
    func_hash->param_default[i] = params[i] ? params[i]->default_val : 0;
    func_hash->param_default_src[i] = params[i] ? params[i]->default_src : NULL;
  }
  // Forward declaration: I64 F(...);  (TempleOS also writes prototypes without the ';')
  if (cc->lex.token == ';' || cc->lex.token != '{') {
    if (cc->lex.token == ';') LexNext(cc);
    free(name);
    { SymTablePopTo(cc, fn_scope); return true; }
  }
  func_hash->is_extern = FALSE;            // a body follows: defined here, not imported
  func_hash->entry_label_defined = 1;
  RewriteForwardImportCalls(cc, func_hash);
  
  // Fix parameter offsets now that we know total count
  // Frame layout: sp+0=locals, sp+16=param[0], sp+24=param[1], ...
  // S0 = sp + frame_size
  // param[i] saved at sp + 16 + i*8
  // From S0: param[i] at S0 - (frame_size - 16 - i*8)
  // Store param_count in cc for local variable offset calculation
  cc->current_function_param_count = param_count;
  
  // Keep temporary markers for now - they will be patched after parsing the function body
  
  // Function body - emit label first
  ICAdd(cc, IC_LABEL, (I64)func_label, RT_I64);
  
  // IC_ENTER will save register parameters to stack
  // NOTE: We need to patch this later with locals_size!
  // For now, just mark the position
  CIntermediateCode *enter_ic = ICNew(cc, IC_ENTER);
  enter_ic->ic_data = param_count;  // Will be updated after parsing body
  
  // Manual linking (ICNew doesn't auto-link in TempleOS)
  if (!cc->ic_head) cc->ic_head = enter_ic;
  if (cc->ic_tail) cc->ic_tail->next = enter_ic;
  cc->ic_tail = enter_ic;
  
  I64 saved_locals = cc->locals_size;
  cc->locals_size = 0;
  
  // Create function exit label for return statements
  CLabel *func_exit_label = LabelNew(cc, NULL);
  CLabel *saved_exit_label = cc->current_function_exit;
  cc->current_function_exit = func_exit_label;
  cc->current_function_entry_label = func_label;
  
  if (!ParseBlock(cc)) {
    cc->current_function_exit = saved_exit_label;
    cc->current_function_entry_label = NULL;
    free(name);
    { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
  }
  
  // Update ENTER with actual locals size
  // ic_data low 32 bits = param_count, high 32 bits = locals_size
  CIntermediateCode *ic_enter = cc->ic_head;
  while (ic_enter && ic_enter->ic_code != IC_ENTER) {
    ic_enter = ic_enter->next;
  }
  if (ic_enter) {
    // Encode both param_count and locals_size
    I64 param_cnt = ic_enter->ic_data;
    ic_enter->ic_data = (cc->locals_size << 32) | param_cnt;
  }
  
  // Now fix ALL variable offsets with final locals_size known
  // Frame layout (as generated by IC_ENTER):
  //   sp+0: saved ra
  //   sp+8: saved s0
  //   sp+16+i*8: params 0-7 (saved from a0-a7, i=0..7)
  //   sp+16+reg_param_cnt*8+position: locals (position=0,8,16,...)
  //   S0 = sp + frame_size (points to caller's sp)
  //   Params 8+ are at s0+0, s0+8, ... (on caller's stack, above old sp)
  I64 reg_param_cnt = param_count;
  if (reg_param_cnt > 8) reg_param_cnt = 8;
  I64 frame_size = 16 + reg_param_cnt * 8 + cc->locals_size;
  
  // Fix parameter offsets
  // Params 0-7: saved at sp+locals_size+i*8 → offset from s0 is -(frame_size - locals_size - i*8)
  // Params 8+: on caller's stack at s0+0, s0+8, ... → offset from s0 is +(i-8)*8
  for (int i = 0; i < param_count; i++) {
    if (params[i]) {
      I64 old_param_marker = params[i]->offset;  // Use current offset (still the temporary marker)
      I64 final_param_offset;
      
      if (i < 8) {
        // Register parameter: saved at sp+16+i*8, s0=sp+frame_size
        // Offset from s0 = (sp+16+i*8) - (sp+frame_size) = 16+i*8-frame_size
        final_param_offset = -(frame_size - 16 - i * 8);
      } else {
        // Stack parameter: on caller's stack (no cleanup before call)
        // Before call: arg9 at sp+0, arg10 at sp+8, arg11 at sp+16, ...
        // After prologue: s0 = old_sp (the sp before prologue)
        // So arg9 is at old_sp+0 = s0+0, arg10 at old_sp+8 = s0+8, arg11 at old_sp+16 = s0+16, ...
        // General: arg[i] is at s0 + (i - 8) * 8
        // For 9 params: arg9 at s0+0, arg8 at s0+8, ..., arg1 at s0+64
        // For 10 params: arg10 at s0+0, arg9 at s0+8, ..., arg1 at s0+72
        // For 11 params: arg11 at s0+16, arg10 at s0+8, arg9 at s0+0
        final_param_offset = (i - 8) * 8;
      }
      
      // Patch IC chain: find IC_LEA with old marker, update to new offset
      CIntermediateCode *ic_scan = cc->ic_head;
      while (ic_scan) {
        if (ic_scan->ic_code == IC_LEA && ic_scan->ic_data == (I64)old_param_marker) {
          ic_scan->ic_data = (I64)final_param_offset;
        }
        ic_scan = ic_scan->next;
      }
      
      params[i]->offset = final_param_offset;
    }
  }
  
  // Fix local variable offsets: locals at sp + 16 + reg_param_cnt*8 + position.
  // Walk the IC chain, not the symbol table: locals declared inside the body block (i.e. all
  // of them) live in scopes that ParseBlock has already popped, so the symbol walk below only
  // sees function-level symbols and every other local would keep its -(10000+pos) marker and
  // be addressed 10KB below the frame.
  for (CIntermediateCode *ic_scan = cc->ic_head; ic_scan; ic_scan = ic_scan->next) {
    if (ic_scan->ic_code == IC_LEA && HOLY_IS_LOCAL_MARKER(ic_scan->ic_data)) {
      I64 position_in_locals = HOLY_LOCAL_MARKER_POS(ic_scan->ic_data);
      ic_scan->ic_data = -(frame_size - 16 - reg_param_cnt * 8 - position_in_locals);
    }
  }
  Symbol *local_sym = cc->symtab->symbols;
  while (local_sym) {
    if (local_sym->type == SYM_VAR && HOLY_IS_LOCAL_MARKER(local_sym->offset)) {
      // This is a local (has temporary marker -(10000+position))
      I64 position_in_locals = HOLY_LOCAL_MARKER_POS(local_sym->offset);
      // Locals start at sp+16+reg_param_cnt*8, so offset from s0 = -(frame_size - 16 - reg_param_cnt*8 - position)
      I64 final_offset = -(frame_size - 16 - reg_param_cnt * 8 - position_in_locals);
      I64 old_marker = local_sym->offset;
      
      // Patch IC chain: find ALL IC_LEA with old marker, update to new offset
      CIntermediateCode *ic_scan = cc->ic_head;
      while (ic_scan) {
        if (ic_scan->ic_code == IC_LEA && ic_scan->ic_data == (I64)old_marker) {
          ic_scan->ic_data = (I64)final_offset;
        }
        ic_scan = ic_scan->next;
      }
      // Debug: verify patching occurred (would need UART but can't use here)
      
      local_sym->offset = final_offset;
    }
    local_sym = local_sym->next;
  }
  
  // Emit function exit label before LEAVE
  ICAdd(cc, IC_LABEL, (I64)func_exit_label, RT_I64);
  func_exit_label->defined = true;
  
  // Patch IC_ENTER with final locals_size (now that we know it)
  enter_ic->ic_data = (cc->locals_size << 32) | param_count;
  
  // LEAVE needs both params and locals
  ICAdd(cc, IC_LEAVE, (cc->locals_size << 32) | param_count, RT_I64);
  
  // Restore exit label
  cc->current_function_exit = saved_exit_label;
  cc->current_function_entry_label = NULL;
  
  cc->locals_size = saved_locals;
  
  extern U8 *CompileAOT(Compiler *cc, I64 *code_size);
  if (cc->defer_aot_compile) {
    AOTFnICChunk *chunk = calloc(1, sizeof(AOTFnICChunk));
    if (!chunk) {
      free(name);
      { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
    }
    chunk->head = cc->ic_head;
    chunk->tail = cc->ic_tail;
    chunk->fun = func_hash;
    chunk->next = NULL;
    if (!cc->aot_fn_ic_tail) {
      cc->aot_fn_ic_head = cc->aot_fn_ic_tail = chunk;
    } else {
      cc->aot_fn_ic_tail->next = chunk;
      cc->aot_fn_ic_tail = chunk;
    }
    cc->ic_head = NULL;
    cc->ic_tail = NULL;
  } else {
    I64 code_size = 0;
    U8 *compiled_code = CompileAOT(cc, &code_size);
    if (!compiled_code) {
      free(name);
      { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
    }
    func_hash->exe_addr = (I64)compiled_code;
    func_hash->size = code_size;      // TempleOS idiom: the hash entry knows the code size (Uf)
    cc->code_buffer = compiled_code;
    cc->code_size = code_size;
    cc->ic_head = NULL;   // consumed: the caller must not run/collect the body as a statement
    cc->ic_tail = NULL;
    cc->labels = NULL;    // this unit is closed: later statements must call through exe_addr
  }
  
  free(name);
  { SymTablePopTo(cc, fn_scope); return true; }
}


// ----------------------------------------------------------------------------------------------
// PARSER - TOP LEVEL
// ----------------------------------------------------------------------------------------------

// Global declaration list at top level: `T *a, b[4] = 1, c;` — HolyC top-level variables
// are globals, never locals.
static bool ParseGlobalDeclListTyped(Compiler *cc, U8 type) {
  for (;;) {
    U8 saved_ptr_type = cc->last_pointed_to_type;
    while (cc->lex.token == '*') {
      cc->last_pointed_to_type = type;
      LexNext(cc);
    }
    if (cc->lex.token != TK_IDENT) {
      Error(cc, "Expected variable name in global declaration");
      { PF_TRACE(__LINE__); return false; }
    }
    char *name = strdup(cc->lex.token_str);
    LexNext(cc);
    bool ok = ParseGlobalVariable(cc, type, name);
    free(name);
    if (!ok) return false;
    cc->last_pointed_to_type = saved_ptr_type;
    if (cc->lex.token == ',') { LexNext(cc); continue; }
    break;
  }
  if (cc->lex.token == ';') LexNext(cc);
  return true;
}

static bool ParseGlobalDeclList(Compiler *cc) {
  cc->last_pointed_to_type = 0;
  U8 type = ParseType(cc);
  if (cc->error) return false;
  return ParseGlobalDeclListTyped(cc, type);
}

// One top-level item — the same grammar for a source file (ParseProgram) and a REPL line.
// Definitions (function/class/enum/global) register themselves in the hash table; a plain
// statement leaves its IC on cc->ic_head for the caller to run (REPL) or collect (AOT entry).
// Returns false with cc->error set.
// Turn cc->ic_head (top-level statements) into a function body: IC_ENTER … IC_RETURN_VAL2,
// IC_LEAVE, with the -(10000+pos) local markers (switch/try temps, block locals) patched to a
// real frame. Used for REPL statements and the AOT entry chunk; the last statement's value is
// left in a0.
void WrapStatementsAsFrame(Compiler *cc) {
  I64 locals = cc->locals_size;
  I64 frame_size = 16 + locals;
  CIntermediateCode *ent;
#ifdef BARE_METAL
  extern void *parse_calloc(size_t n, size_t sz);
  ent = parse_calloc(1, sizeof(CIntermediateCode));
#else
  ent = calloc(1, sizeof(CIntermediateCode));
#endif
  if (!ent) return;
  ent->ic_code = IC_ENTER;
  ent->ic_data = (locals << 32);
  ent->next = cc->ic_head;
  if (cc->ic_head) cc->ic_head->last = ent;
  cc->ic_head = ent;
  if (!cc->ic_tail) cc->ic_tail = ent;
  ICAdd(cc, IC_RETURN_VAL2, 0, RT_I64);
  ICAdd(cc, IC_LEAVE, (locals << 32), RT_I64);
  for (CIntermediateCode *ic = cc->ic_head; ic; ic = ic->next) {
    if (ic->ic_code == IC_LEA && HOLY_IS_LOCAL_MARKER(ic->ic_data)) {
      I64 pos = HOLY_LOCAL_MARKER_POS(ic->ic_data);
      ic->ic_data = -(frame_size - 16 - pos);
    }
  }
  cc->locals_size = 0;
}

// --- TempleOS registry: the declaration RegDft makes at compile time ------------------------------
//
// Eleven stock games and two templates open with the pair
//
//   RegDft("TempleOS/FlapBat","F64 best_score=9999;\n");
//   RegExe("TempleOS/FlapBat");
//
// In TempleOS a top-level statement RUNS while the file is being compiled, so RegDft runs, RegExe
// compiles the branch's text, and compiling that text is what DECLARES best_score. Every later
// mention of best_score in the file then resolves. An AOT compiler never runs either call, so
// without this the rest of the file is one long list of "Undefined variable 'best_score'" — the
// single largest entry in docs/DEMO_SURVEY.md's L0 list.
//
// So: remember the text at RegDft, parse it as declarations at RegExe. Recording at RegDft and
// declaring at RegExe rather than declaring at RegDft keeps a RegDft with no RegExe from
// declaring anything, which is what TempleOS does too. Both calls are still emitted; they resolve
// against the in-memory Kernel/RVRegistry.HC.
typedef struct RegistryBranch {
  char *branch;
  char *text;
  struct RegistryBranch *next;
} RegistryBranch;
// Never reset: one holyc-riscv run compiles one program, and a branch defaulted in an #include is
// meant to be visible to the file that included it.
static RegistryBranch *reg_branches = NULL;

// The concatenation of the string literals at the current token, or NULL if there is no literal.
// Adjacent literals join, as they do in an expression (X-Caliber's default spans four lines).
static char *RegLexStrCat(Compiler *cc, size_t *out_len) {
  if (cc->lex.token != TK_STR) return NULL;
  size_t n = 0;
  char *s = malloc(1);
  s[0] = 0;
  while (cc->lex.token == TK_STR) {
    size_t k = cc->lex.token_str ? (size_t)cc->lex.token_str_len : 0;
    s = realloc(s, n + k + 1);
    if (k) memcpy(s + n, cc->lex.token_str, k);
    n += k;
    s[n] = 0;
    LexNext(cc);
  }
  if (out_len) *out_len = n;
  return s;
}

static int LexIncludeDepth(Compiler *cc) {
  int n = 0;
  for (IncludeFile *f = cc->lex.include_stack; f; f = f->next) n++;
  return n;
}

// Read the two literal arguments of `RegDft(branch, text)` without consuming anything, or the one
// of `RegExe(branch)`. Returns false when an argument is not a plain literal (a computed branch
// name is legal HolyC and simply cannot be resolved here).
static bool RegPeekCallArgs(Compiler *cc, bool want_two, char **a1, char **a2) {
  *a1 = *a2 = NULL;
  LexPush(cc);
  LexNext(cc);                      // past the name
  bool ok = false;
  if (cc->lex.token == '(') {
    LexNext(cc);
    *a1 = RegLexStrCat(cc, NULL);
    if (*a1) {
      if (!want_two) {
        ok = (cc->lex.token == ')');
      } else if (cc->lex.token == ',') {
        LexNext(cc);
        *a2 = RegLexStrCat(cc, NULL);
        ok = (*a2 && cc->lex.token == ')');
      }
    }
  }
  LexPopRestore(cc);
  if (!ok) { free(*a1); free(*a2); *a1 = *a2 = NULL; }
  return ok;
}

// Parse `text` here, as top-level items, then resume at the token that was held back. Any IC it
// produces (an initializer that is not a constant) goes to the entry chunk, as ParseProgram does.
// The loop needs the text to be complete items; all 20 RegDft call sites in the tree end in ';'.
static bool RegParseDecls(Compiler *cc, const char *text) {
  int depth0 = LexIncludeDepth(cc);
  LexPushStringPending(cc, text);
  while (LexIncludeDepth(cc) > depth0 && cc->lex.token != TK_EOF) {
    if (!ParseTopLevel(cc)) {
      LexAbandonPendingString(cc);
      return false;
    }
    if (cc->ic_head) {
      if (cc->aot_main_tail) cc->aot_main_tail->next = cc->ic_head;
      else cc->aot_main_head = cc->ic_head;
      cc->aot_main_tail = cc->ic_tail;
      cc->ic_head = cc->ic_tail = NULL;
    }
  }
  return true;
}

// At a top-level `RegDft`/`RegExe`, before the statement itself is parsed.
static bool ParseRegistryDecls(Compiler *cc) {
  if (cc->lex.token != TK_IDENT || !cc->lex.token_str) return true;
  bool is_dft = !strcmp(cc->lex.token_str, "RegDft");
  bool is_exe = !strcmp(cc->lex.token_str, "RegExe");
  if (!is_dft && !is_exe) return true;
  char *branch = NULL, *text = NULL;
  if (!RegPeekCallArgs(cc, is_dft, &branch, &text)) return true;
  if (is_dft) {
    RegistryBranch *b = malloc(sizeof(RegistryBranch));
    b->branch = branch;
    b->text = text;
    b->next = reg_branches;
    reg_branches = b;
    return true;
  }
  for (RegistryBranch *b = reg_branches; b; b = b->next) {
    if (!strcmp(b->branch, branch)) {
      free(branch);
      return RegParseDecls(cc, b->text);
    }
  }
  free(branch);   // RegExe on a branch this file never defaulted: nothing to declare
  return true;
}

static bool ParseTopLevelInner(Compiler *cc);
bool ParseTopLevel(Compiler *cc) {
  bool ok = ParseTopLevelInner(cc);
#ifndef BARE_METAL
  if (!ok && getenv("HOLYC_TRACE"))
    fprintf(stderr, "[trace] ParseTopLevel failed: token=%d ('%s') line=%d error=%s\n",
            cc->lex.token, cc->lex.token_str ? cc->lex.token_str : "", cc->lex.line, cc->error ? cc->error : "(none)");
#endif
  return ok;
}
static bool ParseTopLevelInner(Compiler *cc) {
  cc->lex.brace_depth = 0;   // every top-level item starts outside any body
  while (cc->lex.token == ',' || cc->lex.token == ';') LexNext(cc);
  if (cc->lex.token == TK_EOF) return true;
  // `RegDft(...)` / `RegExe(...)`: TempleOS declares globals by running these during the compile.
  if (!ParseRegistryDecls(cc)) return false;
  // Declaration qualifiers and function attributes. `extern`/`import` mean "defined elsewhere":
  // an undefined extern function becomes a runtime import (resolved by name at load).
  bool is_extern = false;
  for (;;) {
    int t = cc->lex.token;
    if (t == KW_PUBLIC || t == KW__INTERN || t == KW_INTERRUPT || t == KW_HASERRCODE ||
        t == KW_ARGPOP || t == KW_NOREG || t == KW_REG || t == KW_NO_WARN) { LexNext(cc); continue; }
    if (t == KW_EXTERN || t == KW__EXTERN || t == KW_IMPORT || t == KW__IMPORT) { is_extern = true; LexNext(cc); continue; }
    break;
  }
  // `_extern SYMBOL type name(...)` / `_intern IC_BSF type name(`: an intrinsic/link symbol
  // precedes the declaration — skip it when a type follows.
  if (cc->lex.token == TK_IDENT || cc->lex.token == TK_I64) {   // the symbol may be a #define'd number
    LexPush(cc);
    LexNext(cc);
    bool type_follows = IsTypeStartToken(cc) || cc->lex.token == KW_CLASS || cc->lex.token == KW_UNION;
    LexPopRestore(cc);
    // Do not skip a leading type name (`U32i union U32`): INTERNAL `U32i` can lex as TK_IDENT
    // and would be eaten here, dropping the scalar base so the union stays raw_type RT_I64.
    if (type_follows && !IsTypeStartToken(cc)) {
      // Skipping is right — the symbol is not part of the type — but REMEMBER it. For
      // `_extern _DIV_U64_BY_U64 I64 DivU64ByU64(...)` the symbol names an asm{} label that
      // this declaration is an alias FOR, which is how TempleOS makes an asm routine
      // C-callable (117 such declarations across 20 files). Dropping it on the floor turned
      // every one of them into an unresolved import. MakeImportSlot consumes this.
      free(cc->pending_link_symbol);
      cc->pending_link_symbol = (cc->lex.token == TK_IDENT && cc->lex.token_str)
                                  ? strdup(cc->lex.token_str) : NULL;
      LexNext(cc);
    }
  }
  // `extern CUAsmGlbls uasm;` before the class is defined: forward-declare the class.
  if (is_extern && cc->lex.token == TK_IDENT && !IsTypeStartToken(cc)) {
    LexPush(cc);
    LexNext(cc);
    bool decl_follows = (cc->lex.token == TK_IDENT || cc->lex.token == '*');
    LexPopRestore(cc);
    if (decl_follows) {
      CHashClass *fwd = calloc(1, sizeof(CHashClass));
      fwd->str = strdup(cc->lex.token_str);
      fwd->type = HTT_CLASS;
      fwd->raw_type = RT_I64;
      HashAdd((CHashEntry *)fwd, cc->hash_table);
      cc->lex.hash_entry = (CHashEntry *)fwd;
    }
  }
  // `I64 class X {…}` / `U16i union U16 {…}`: a scalar type before class/union.
  if (IsTypeStartToken(cc) && cc->lex.token != KW_CLASS && cc->lex.token != KW_UNION) {
    LexPush(cc);
    LexNext(cc);
    bool typed_class = (cc->lex.token == KW_CLASS || cc->lex.token == KW_UNION);
    LexPopRestore(cc);
    if (typed_class) {
      cc->class_base_type = ParseType(cc);
      if (!ParseClass(cc)) return false;
      bool declarator = cc->class_decl_follows;
      if (declarator) return ParseGlobalDeclListTyped(cc, RT_I64);
      return true;
    }
  }
  if (cc->lex.token == KW_CLASS || cc->lex.token == KW_UNION) {
    if (!ParseClass(cc)) return false;
    // `class X {…} a, *b;` — a declarator follows. (Type names like `I64` also lex as
    // identifiers with a hash entry: those start the next item, not a declarator.)
    bool declarator = cc->class_decl_follows;
    if (declarator) return ParseGlobalDeclListTyped(cc, RT_I64);
    return true;
  }
  if (cc->lex.token == KW_ENUM) return ParseEnum(cc);
  if (IsTypeStartToken(cc)) {
    // Peek past `type * name` to see what follows: '(' → function, `(*` → fn-pointer global,
    // anything else → global variable(s).
    LexPush(cc);
    LexNext(cc);
    while (cc->lex.token == '*') LexNext(cc);
    bool fn_ptr = false, is_fn = false;
    if (cc->lex.token == '(') {
      LexNext(cc);
      fn_ptr = (cc->lex.token == '*');
    } else if (cc->lex.token == TK_IDENT || cc->lex.token == KW_THROW) {   // `extern U0 throw(...)`
      LexNext(cc);
      is_fn = (cc->lex.token == '(');
    }
    LexPopRestore(cc);
    if (fn_ptr) {
      U8 t = ParseType(cc);
      return ParseGlobalFunctionPointerDeclList(cc, t);
    }
    if (is_fn) {
      if (!ParseFunction(cc)) return false;
      CHashFun *f = cc->last_compiled_func;
      if (is_extern && f && !f->exe_addr && !f->import_var && !f->entry_label_defined) {
        MakeImportSlot(cc, f);
      }
      return true;
    }
    return ParseGlobalDeclList(cc);
  }
  return ParseStatement(cc);
}

// After a parse error, skip to the end of the current top-level item: a ';' at brace depth 0
// or the matching '}' of an open block.
static void RecoverTopLevel(Compiler *cc) {
  // The error hit inside a body: skip to the brace that closes the top-level item, so the
  // rest of that function is not re-parsed as top-level statements.
  if (cc->lex.brace_depth > 0) {
    while (cc->lex.token != TK_EOF && cc->lex.brace_depth > 0) LexNext(cc);
    if (cc->lex.token == '}') LexNext(cc);
    cc->lex.brace_depth = 0;
    return;
  }
  int depth = 0;
  while (cc->lex.token != TK_EOF) {
    if (cc->lex.token == '{') {
      depth++;
    } else if (cc->lex.token == '}') {
      if (depth > 0) depth--;
      if (depth == 0) { LexNext(cc); return; }
    } else if (cc->lex.token == ';' && depth == 0) {
      LexNext(cc);
      return;
    }
    LexNext(cc);
  }
}

bool ParseProgram(Compiler *cc) {
  while (cc->lex.token != TK_EOF) {
    if (!ParseTopLevel(cc)) {
      // Recover so later items still get checked, but the compilation as a whole fails.
      if (cc->error_count < 256) {
        cc->errors[cc->error_count].line = cc->error ? cc->error_line : cc->lex.line;
        cc->errors[cc->error_count].col = cc->error ? cc->error_col : cc->lex.col;
        cc->errors[cc->error_count].file = cc->error ? cc->error_file : cc->lex.filename;
        cc->errors[cc->error_count].msg = cc->error ? cc->error : "parse error";
      }
      cc->error_count++;
      if (!cc->first_error) cc->first_error = cc->error ? cc->error : "parse error";
      cc->error = NULL;
      cc->ic_head = cc->ic_tail = NULL;
      RecoverTopLevel(cc);
      continue;
    }
    if (cc->ic_head) {
      // Top-level statement: append to the entry chunk in source order.
      if (cc->aot_main_tail) cc->aot_main_tail->next = cc->ic_head;
      else cc->aot_main_head = cc->ic_head;
      cc->aot_main_tail = cc->ic_tail;
      cc->ic_head = cc->ic_tail = NULL;
    }
  }
  if (cc->error_count) {
    cc->error = (char *)cc->first_error;
    return false;
  }
  return true;
}


static bool ParseEnumDefinitionBody(Compiler *cc, const char *enum_name, bool register_type) {
  if (!LexExpect(cc, '{')) {
    return false;
  }

  bool first = true;
  I64 last_value = -1;

  while (cc->lex.token != '}' && cc->lex.token != TK_EOF) {
    if (cc->lex.token != TK_IDENT) {
      Error(cc, "Expected enumerator name");
      return false;
    }

    char *member_name = strdup(cc->lex.token_str);
    LexNext(cc);

    I64 value;
    if (cc->lex.token == '=') {
      LexNext(cc);
      if (cc->lex.token != TK_I64) {
        free(member_name);
        Error(cc, "Expected constant integer value for enum");
        return false;
      }
      value = cc->lex.token_i64;
      LexNext(cc);
    } else {
      value = first ? 0 : last_value + 1;
    }

    CHashEnumValue *enum_val = calloc(1, sizeof(CHashEnumValue));
    enum_val->str = member_name;
    enum_val->type = HTT_ENUM;
    enum_val->value = value;
    HashAdd((CHashEntry*)enum_val, cc->hash_table);

    last_value = value;
    first = false;

    if (cc->lex.token == ',') {
      LexNext(cc);
      if (cc->lex.token == '}') {
        break;
      }
      continue;
    }
  }

  if (cc->lex.token != '}') {
    Error(cc, "Expected '}' to close enum");
    return false;
  }
  if (!LexExpect(cc, '}')) {
    return false;
  }

  if (register_type && enum_name) {
    CHashEntry *existing = HashFind(enum_name, cc->hash_table, HTT_CLASS | HTT_INTERNAL_TYPE);
    if (!existing || !(existing->type & (HTT_CLASS | HTT_INTERNAL_TYPE))) {
      CHashClass *enum_type = calloc(1, sizeof(CHashClass));
      enum_type->str = strdup(enum_name);
      enum_type->type = HTT_INTERNAL_TYPE;
      enum_type->raw_type = RT_I64;
      enum_type->size = 8;
      enum_type->ptr_stars_cnt = 0;
      enum_type->flags = 0;
      enum_type->base_class = NULL;
      enum_type->member_lst = NULL;
      HashAdd((CHashEntry*)enum_type, cc->hash_table);
    }
  }

  return true;
}

bool ParseEnum(Compiler *cc) {
  LexNext(cc);  // Skip 'enum'

  char *enum_name = NULL;
  if (cc->lex.token == TK_IDENT) {
    enum_name = strdup(cc->lex.token_str);
    LexNext(cc);
  }

  if (cc->lex.token != '{') {
    Error(cc, "Expected '{' after enum");
    if (enum_name) free(enum_name);
    return false;
  }

  bool ok = ParseEnumDefinitionBody(cc, enum_name, enum_name != NULL);
  if (enum_name) free(enum_name);
  if (!ok) {
    return false;
  }

  if (cc->lex.token == ';') {
    LexNext(cc);
  }

  return true;
}



