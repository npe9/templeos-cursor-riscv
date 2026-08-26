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

// ═══════════════════════════════════════════════════════════════
// IC GENERATION
// ═══════════════════════════════════════════════════════════════

CIntermediateCode *ICNew(Compiler *cc, U8 opcode) {
  (void)cc;
  CIntermediateCode *ic = calloc(1, sizeof(CIntermediateCode));
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

// ═══════════════════════════════════════════════════════════════
// SYMBOL TABLE
// ═══════════════════════════════════════════════════════════════

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

static bool ParseFunctionPointerDeclarator(Compiler *cc, char **out_name, int *out_param_count) {
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

static bool ParseLocalFunctionPointerDeclList(Compiler *cc, U8 return_type) {
  do {
    char *name = NULL;
    int parameter_count = 0;
    if (!ParseFunctionPointerDeclarator(cc, &name, &parameter_count)) {
      return false;
    }

    Symbol *sym = SymbolDefine(cc, name, SYM_VAR);
    sym->data_type = RT_I64;
    sym->size = 8;
    sym->is_function_pointer = true;
    sym->function_return_type = return_type;
    sym->func_ptr_param_count = parameter_count;
    sym->pointed_to_type = RT_I64;

    int aligned_size = (sym->size + 7) & ~7;
    sym->offset = HOLY_LOCAL_MARKER(cc->locals_size);
    cc->locals_size += aligned_size;

    if (cc->lex.token == '=') {
      LexNext(cc);
      if (!EmitLocalFunctionPointerInitialization(cc, sym)) {
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

static CHashGlblVar *CreateGlobalFunctionPointerEntry(Compiler *cc, const char *name, U8 return_type, int param_count) {
  CHashGlblVar *tmpg = calloc(1, sizeof(CHashGlblVar));
  tmpg->str = strdup(name);
  tmpg->type = HTT_GLBL_VAR;
  tmpg->use_cnt = 0;
  tmpg->size = 8;
  tmpg->flags = GVF_FUN;
  tmpg->is_function_pointer = true;
  tmpg->function_return_type = return_type;
  tmpg->func_ptr_param_count = param_count;
  tmpg->raw_type = RT_I64;
  tmpg->pointed_to_type = 0;
  tmpg->element_size = 8;
  tmpg->data_addr = calloc(1, tmpg->size);
  HashAdd((CHashEntry*)tmpg, cc->hash_table);
  return tmpg;
}

static bool InitializeGlobalFunctionPointer(Compiler *cc, CHashGlblVar *global_entry) {
  if (cc->lex.token != '=') {
    return true;
  }

  LexNext(cc);

  bool has_amp = false;
  if (cc->lex.token == '&') {
    has_amp = true;
    LexNext(cc);
  }

  I64 init_val = 0;
  bool have_value = false;

  if (cc->lex.token == TK_IDENT) {
    CHashEntry *fn_entry = HashFind(cc->lex.token_str, cc->hash_table, HTT_FUN);
    if (!fn_entry || !(fn_entry->type & HTT_FUN)) {
      Error(cc, "Expected function name in initialization");
      return false;
    }
    CHashFun *fn = (CHashFun*)fn_entry;
    LexNext(cc);
    // Stored at run time (the entry chunk / this REPL unit): the address is PC-relative in AOT.
    ICAdd(cc, IC_IMM_I64, (I64)global_entry->data_addr, RT_I64);
    cc->ic_tail->ic_flags = ICF_GLBL_ADDR;
    if (!EmitFnAddress(cc, fn)) return false;
    CIntermediateCode *aic = ICNew(cc, IC_ASSIGN);
    aic->res.type.raw_type = RT_I64;
    aic->res.type.mode = MDF_STK;
    aic->arg1_type_pointed_to = RT_I64;
    if (cc->ic_tail) cc->ic_tail->next = aic; else cc->ic_head = aic;
    cc->ic_tail = aic;
    ICAdd(cc, IC_END_EXP, 0, RT_I64);
    (void)has_amp;
    return true;
  } else if (cc->lex.token == TK_I64) {
    init_val = cc->lex.token_i64;
    have_value = true;
    LexNext(cc);
  } else {
    Error(cc, "Unsupported initializer for function pointer");
    return false;
  }

  if (!have_value) {
    return true;
  }

  *(I64*)global_entry->data_addr = init_val;
  (void)has_amp;
  return true;
}

static bool ParseGlobalFunctionPointerDeclList(Compiler *cc, U8 return_type) {
  do {
    char *name = NULL;
    int parameter_count = 0;
    if (!ParseFunctionPointerDeclarator(cc, &name, &parameter_count)) {
      return false;
    }

    CHashGlblVar *entry = CreateGlobalFunctionPointerEntry(cc, name, return_type, parameter_count);
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

// ═══════════════════════════════════════════════════════════════
// LABELS
// ═══════════════════════════════════════════════════════════════

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
  if (t && (t->ic_code == IC_ADD || t->ic_code == IC_PUSH_ARG || t->ic_code == IC_IMM_I64 || t->ic_code == IC_DEREF))
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

// ═══════════════════════════════════════════════════════════════
// PARSER - EXPRESSIONS
// ═══════════════════════════════════════════════════════════════

// Forward declarations for expression parsing
static bool ParsePrimary(Compiler *cc);
static bool ParsePostfix(Compiler *cc);
static I64 CEOr(Compiler *cc, I64 dollar, bool *ok);
static bool ParseUnary(Compiler *cc);
static bool ParseGlobalVariable(Compiler *cc, U8 var_type, char *var_name);
static bool ParseEnumDefinitionBody(Compiler *cc, const char *enum_name, bool register_type);
bool ParseEnum(Compiler *cc);
static bool ParseFunctionPointerDeclarator(Compiler *cc, char **out_name, int *out_param_count);
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

// Declared (or merely called) but not defined here: calls go through an import slot the
// loader fills by name (`__imp_<name>`).
void MakeImportSlot(Compiler *cc, CHashFun *f) {
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
  cc->last_expr_type = (cc->call_ret_type == RT_F64) ? RT_F64 : RT_I64;
  cc->last_global_var = NULL;
  cc->last_member = NULL; cc->expr_ptr_depth = 0;  // call result is the callee's return type, not an argument's
  ICAdd(cc, IC_CALL_END, 0, RT_I64);
  return true;
}

static bool ParsePrimary(Compiler *cc) {
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
        if (cc->lex.token != TK_IDENT || !ocls) { Error(cc, "offset: expected member name"); return false; }
        CMemberLst *om = ocls->member_lst;
        while (om && strcmp(om->str, cc->lex.token_str)) om = om->next;
        if (!om) { Error(cc, "offset: unknown member"); return false; }
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
              Error(cc, "Omitted argument has no default value");
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
      if (entry && (entry->type & HTT_FUN)) {
        // Function found in hash table
        CHashFun *func = (CHashFun*)entry;
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
          ICAdd(cc, IC_DEREF, 0, RT_I64);  // Push pointer (address of exe_addr)
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
      
      cc->last_expr_type = (cc->call_ret_type == RT_F64) ? RT_F64 : RT_I64;
      
      cc->last_global_var = NULL;
      cc->last_member = NULL; cc->expr_ptr_depth = 0;  // call result is the callee's return type, not an argument's
      
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
      // `&`, where it is the function's address (pointer to its exe_addr slot).
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
      
      Error(cc, "Undefined variable");
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
        cc->last_var_symbol = NULL;
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
    if (cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) cc->ic_tail->ic_code = IC_NOP1;
    { U8 pe; I64 pd; I64 step = PtrElemInfo(cc, &pe, &pd); ICAdd(cc, IC_PP_, step > 1 ? step : 0, RT_I64); }  // pre-increment (scaled for pointers)
    return true;
  }
  
  // Pre-decrement: --var
  if (cc->lex.token == TK_SUB_SUB) {
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    // Operand must stay an address: retract the auto-deref ParsePostfix appended.
    if (cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) cc->ic_tail->ic_code = IC_NOP1;
    { U8 pe; I64 pd; I64 step = PtrElemInfo(cc, &pe, &pd); ICAdd(cc, IC_MM_, step > 1 ? step : 0, RT_I64); }  // pre-decrement
    return true;
  }
  
  if (cc->lex.token == '-') {
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    if (cc->last_expr_type == RT_F64) ICAdd(cc, IC_FNEG, 0, RT_F64);
    else ICAdd(cc, IC_UNARY_MINUS, 0, RT_I64);
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
    // address is on the eval stack (that is the whole of `&`).
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
    } else if (!cc->last_var_symbol && cc->last_global_var && cc->last_global_var->pointed_to_type) {
      pointee = cc->last_global_var->pointed_to_type; depth = cc->last_global_var->ptr_depth;
    } else if (!cc->last_var_symbol && !cc->last_global_var && cc->last_member && cc->last_member->pointed_to_type) {
      pointee = cc->last_member->pointed_to_type; depth = cc->last_member->ptr_depth;
    } else if (cc->expr_ptr_depth) {   // `**pp`: the inner deref left a pointer
      pointee = cc->expr_pointee; depth = cc->expr_ptr_depth;
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
  Symbol *pre_symbol = cc->last_var_symbol;  // Save to detect if variable was loaded
  bool is_paren_expr = (cc->lex.token == '(');  // Track parenthesized expressions
  if (!ParsePrimary(cc)) return false;
  
  // Auto-dereference variables (match original PE_DEREFERENCE phase PrsExp.HC:97-118)
  // Only if a variable was just loaded AND not lvalue/array
  // Skip auto-deref for parenthesized expressions
  if (cc->last_var_symbol && cc->last_var_symbol != pre_symbol && !(cc->flags & (CCF_RAX | CCF_ARRAY)) && !is_paren_expr) {
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
  } else if (!cc->last_var_symbol && cc->last_global_var &&
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
  
  // Handle postfix operators (array subscript, member access)
  cc->cast_elem_type = 0;
  if (!is_paren_expr) cc->expr_ptr_depth = 0;   // `(**ppb)[i]` keeps the depth the parens computed
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
      // Element type/size: through a pointer it is the pointee (class or primitive); for an
      // array it is the declared element. The final DEREF is typed accordingly.
      U8 elem_type = RT_I64;
      if (saved_symbol) {
        if (saved_symbol->pointed_to_type && !saved_symbol->is_array) {
          elem_type = saved_symbol->pointed_to_type;
          CHashClass *pc = (CHashClass *)saved_symbol->extra;
          elem_size = pc && pc->size > 0 ? pc->size : PrimitiveTypeSize(elem_type);
          if (saved_symbol->ptr_depth > 1) { elem_type = RT_I64; elem_size = 8; }   // `argv[i]` of `U8 **argv`
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
        if (!mb->pointed_to_type) elem_type = ScalarTypeForSize(elem_type, elem_size);
        if (mb->pointed_to_type && mb->ptr_depth > 1 && !mb->is_array) { elem_type = RT_I64; elem_size = 8; }
        if (!mb->is_array && !mb->pointed_to_type && mb->member_class && mb->member_class->size > 0) elem_size = mb->member_class->size;
        if (elem_size <= 0) elem_size = 8;
      } else if (saved_global) {
        if (saved_global->pointed_to_type && !(saved_global->flags & GVF_ARRAY)) {
          elem_type = saved_global->pointed_to_type;
          CHashClass *pc = saved_global->var_class;
          elem_size = pc && pc->size > 0 ? pc->size : PrimitiveTypeSize(elem_type);
          if (saved_global->ptr_depth > 1) { elem_type = RT_I64; elem_size = 8; }
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
      
      // Inner subscript of a multi-dimensional array: the result is a sub-array address —
      // keep it for the next '[' instead of loading through it.
      if (saved_symbol && saved_symbol->ndims > 1 && cc->subscript_level < saved_symbol->ndims - 1) {
        cc->subscript_level++;
        continue;
      }
      if (saved_global && saved_global->ndims > 1 && cc->subscript_level < saved_global->ndims - 1) {
        cc->subscript_level++;
        continue;
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
        
        // Look up member
        if (cls && cls->member_lst) {
          CMemberLst *member = cls->member_lst;
          while (member) {
            if (strcmp(member->str, member_name) == 0) {
              member_offset = member->offset;
              found = member;
              member_class = member->member_class;
              bit_width = member->bit_width;
              bit_offset = member->bit_offset;
              break;
            }
            member = member->next;
          }
        }
      }
      
      LexNext(cc);
      // The base of `.` is the aggregate's address, not its first word: retract the auto-deref.
      EnsureLvalueAddressPushed(cc);
      
      if (member_offset != 0) {
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
      if (cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) cc->ic_tail->ic_code = IC_NOP1;
      { U8 pe; I64 pd; I64 step = PtrElemInfo(cc, &pe, &pd); ICAdd(cc, IC__PP, step > 1 ? step : 0, RT_I64); }  // post-increment (scaled)
      continue;
    }
    
    // Post-decrement: var--
    if (cc->lex.token == TK_SUB_SUB) {
      LexNext(cc);
      // Operand must stay an address: retract the early auto-deref (first reference of a
      // variable in an expression gets one before this loop runs).
      if (cc->ic_tail && cc->ic_tail->ic_code == IC_DEREF) cc->ic_tail->ic_code = IC_NOP1;
      { U8 pe; I64 pd; I64 step = PtrElemInfo(cc, &pe, &pd); ICAdd(cc, IC__MM, step > 1 ? step : 0, RT_I64); }  // post-decrement
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
        CMemberLst *member = cc->last_expr_class->member_lst;
        while (member) {
          if (strcmp(member->str, member_name) == 0) {
            member_offset = member->offset;
            found = member;
            member_class = member->member_class;
            break;
          }
          member = member->next;
        }
      }
      
      LexNext(cc);
      
      if (member_offset != 0) {
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
      if (cc->last_global_var) store_type = cc->last_global_var->raw_type ? cc->last_global_var->raw_type : RT_I64;
    }
    EnsureLvalueAddressPushed(cc);
    
    LexNext(cc);
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

// ═══════════════════════════════════════════════════════════════
// PARSER - STATEMENTS
// ═══════════════════════════════════════════════════════════════

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
        if (cur_sub >= 0) {
          ICAdd(cc, IC_LABEL, (I64)sub_end[cur_sub], RT_I64);
          sub_end[cur_sub]->defined = true;
        }
        cc->current_break_label = end_label;
        cur_sub = -1;
        while (cc->lex.token != KW_CASE && cc->lex.token != KW_DEFAULT &&
               cc->lex.token != '}' && cc->lex.token != TK_EOF && !PeekSubMarker(cc)) {
          if (!ParseStatement(cc)) {
            cc->current_break_label = saved_break;
            cc->loop_try_depth = saved_ltd;
            return false;
          }
        }
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
        case_val = CEOr(cc, 0, &okc);   // `case -1:`, `case 'a':`, `case FLAG|2:`
        if (!okc) {
          Error(cc, "Expected integer constant in case");
          cc->current_break_label = saved_break;
          cc->loop_try_depth = saved_ltd;
          return false;
        }
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
      while (cc->lex.token == '[') {
        LexNext(cc);  // Skip '['
        I64 dimv = 0;
        if (!ParseConstDim(cc, &dimv)) {
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
      if (!strcmp(cc->lex.token_str, "lock")) { LexNext(cc); continue; }   // `lock x++;`: single core here
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
        cc->asm_blocks_skipped++;
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
            while (cc->lex.token != TK_EOF && cc->lex.line == start_line) LexNext(cc);
            cc->asm_blocks_skipped++;
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
        ICAdd(cc, IC_RETURN_VAL, 0, RT_I64);
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
      LexNext(cc);
      
      // Expect opening brace
      if (!LexExpect(cc, '{')) return false;
      
      // Skip asm block contents (architecture-specific)
      // For RISC-V port, we skip x86-64 assembly
      int brace_count = 1;
      while (brace_count > 0 && cc->lex.token != TK_EOF) {
        if (cc->lex.token == '{') brace_count++;
        if (cc->lex.token == '}') brace_count--;
        if (brace_count > 0) LexNext(cc);
      }
      
      // Skip closing brace
      if (cc->lex.token == '}') {
        LexNext(cc);
      }
      cc->asm_blocks_skipped++;
      
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
      ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
      I64 argc = 1;
      while (cc->lex.token == ',') {
        LexNext(cc);
        if (!ParseAssignment(cc)) return false;
        ICAdd(cc, IC_PUSH_RES, 0, RT_I64);
        argc++;
      }
      if (!EmitCallByName(cc, "Print", argc)) return false;
      ICAdd(cc, IC_CALL_END, 0, RT_I64);
      ICAdd(cc, IC_END_EXP, 0, RT_I64);
      if (cc->lex.token == ';') LexNext(cc);
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

// ═══════════════════════════════════════════════════════════════
// PARSER - CLASSES
// ═══════════════════════════════════════════════════════════════


// ---- compile-time constant expressions (array sizes, `$$=` in class bodies) ----
static I64 CEOr(Compiler *cc, I64 dollar, bool *ok);
static I64 CEPrimary(Compiler *cc, I64 dollar, bool *ok) {
  if (cc->lex.token == TK_I64) { I64 v = cc->lex.token_i64; LexNext(cc); return v; }
  if (cc->lex.token == TK_DOLLAR) { LexNext(cc); return dollar; }
  if (cc->lex.token == '(') { LexNext(cc); I64 v = CEOr(cc, dollar, ok); if (!LexExpect(cc, ')')) *ok = false; return v; }
  if (cc->lex.token == '-') { LexNext(cc); return -CEPrimary(cc, dollar, ok); }
  if (cc->lex.token == '~') { LexNext(cc); return ~CEPrimary(cc, dollar, ok); }
  if (cc->lex.token == '!') { LexNext(cc); return !CEPrimary(cc, dollar, ok); }
  if (cc->lex.token == KW_SIZEOF) {
    LexNext(cc);
    bool paren = (cc->lex.token == '(');
    if (paren) LexNext(cc);
    I64 sz = 8;
    if (IsTypeStartToken(cc)) {
      U8 t = ParseType(cc);
      sz = cc->last_pointed_to_type ? 8 : (cc->last_type_class && cc->last_type_class->size > 0 ? cc->last_type_class->size : PrimitiveTypeSize(t));
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
      } else if (cc->lex.token == TK_IDENT) {
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
      else { member_size = PrimitiveTypeSize(member_type); if (member_size <= 0) member_size = 8; }
      I64 elem_size = member_size;
      bool is_array = false;
      while (cc->lex.token == '[') {                  // T name[N][M], N a constant expression
        LexNext(cc);
        is_array = true;
        if (cc->lex.token != ']') { I64 n = 0; if (!ParseConstDim(cc, &n)) { free(member_name); return false; } member_size *= n; }
        if (!LexExpect(cc, ']')) { free(member_name); return false; }
      }
      CMemberLst *m = calloc(1, sizeof(CMemberLst));
      m->str = member_name;
      m->raw_type = (ptr || is_fnptr) ? RT_I64 : member_type;
      m->pointed_to_type = ptr;
      m->ptr_depth = ptr ? (mdepth ? mdepth : 1) : 0;
      m->is_array = is_array;
      m->elem_size = ptr ? PrimitiveTypeSize(ptr) : elem_size;
      m->member_class = (ptr || is_array) ? mcls : mcls;
      m->size = member_size;
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

// ═══════════════════════════════════════════════════════════════
// PARSER - GLOBAL VARIABLES
// ═══════════════════════════════════════════════════════════════

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
  I64 idx = 0;
  while (cc->lex.token != (braced ? '}' : ';') && cc->lex.token != TK_EOF) {
    if (idx >= (g->dim.total_cnt > 0 ? g->dim.total_cnt : g->dim.cnt)) { Error(cc, "Too many initializers"); return false; }
    if (!InitAggregateElement(cc, g->data_addr + idx * elem_size, cls, var_type, elem_size, g->pointed_to_type != 0)) return false;
    idx++;
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
  CHashGlblVar *tmpg = existing ? existing : calloc(1, sizeof(CHashGlblVar));
  tmpg->str = strdup(var_name);
  tmpg->type = HTT_GLBL_VAR;
  tmpg->use_cnt = 0;
  tmpg->flags = 0;
  tmpg->var_class = decl_class;
  tmpg->raw_type = var_type;
  tmpg->pointed_to_type = cc->last_pointed_to_type;
  tmpg->ptr_depth = cc->last_ptr_depth;
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

// ═══════════════════════════════════════════════════════════════
// PARSER - FUNCTIONS
// ═══════════════════════════════════════════════════════════════

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
          if (!ParseFunctionPointerDeclarator(cc, &fp_name, &fp_param_cnt)) {
            free(name);
            { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
          }

          if (cc->lex.token == '=') {
            free(fp_name);
            free(name);
            Error(cc, "Default values for function pointer parameters are not supported");
            { SymTablePopTo(cc, fn_scope); PF_TRACE(__LINE__); return false; }
          }

          Symbol *param = SymbolDefine(cc, fp_name, SYM_VAR);
          param->data_type = RT_I64;
          param->has_default = false;
          param->default_val = 0;
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
      if (cc->lex.token == '=') {
        const char *dflt_start = cc->lex.ptr;   // the default's source text begins after '='
        LexNext(cc);
        
        // Constant-expression defaults (`=0x80`, `=I64_MIN`, `=1<<JOBf_X`, `=-1`); `lastclass` → 0
        if (cc->lex.token == KW_LASTCLASS) {
          has_default = true;
          default_val = 0;
          LexNext(cc);
        } else {
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
          has_default = true;
          if (okc && param_type != RT_F64) {
            default_val = v;
          } else {
            // Anything else (`=gr.dc`, `=2.75`, `=-π`): HolyC evaluates the default at each
            // call site, in the caller's context — keep its source text for that.
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
              default_src = malloc(n + 1);
              memcpy(default_src, dflt_start, n);
              default_src[n] = 0;
            }
            default_val = 0;
          }
        }
      }
      
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
    cc->code_buffer = compiled_code;
    cc->code_size = code_size;
    cc->ic_head = NULL;   // consumed: the caller must not run/collect the body as a statement
    cc->ic_tail = NULL;
    cc->labels = NULL;    // this unit is closed: later statements must call through exe_addr
  }
  
  free(name);
  { SymTablePopTo(cc, fn_scope); return true; }
}


// ═══════════════════════════════════════════════════════════════
// PARSER - TOP LEVEL
// ═══════════════════════════════════════════════════════════════

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
  CIntermediateCode *ent = calloc(1, sizeof(CIntermediateCode));
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
    if (type_follows) LexNext(cc);
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



