/* HolyC Parser - Generates Intermediate Code */

#include "holyc_compiler.h"

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

  if (pointer_depth != 1) {
    Error(cc, "Nested function pointers are not supported yet");
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

      param_count++;

      if (cc->lex.token == ',') {
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
    sym->offset = -(10000 + cc->locals_size);
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
    init_val = (I64)&fn->exe_addr;
    have_value = true;
    LexNext(cc);
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
    type = RT_I64;  // Pointers are 64-bit addresses
    cc->last_type_class = NULL;  // Pointer to class treated as pointer type
  } else {
    cc->last_pointed_to_type = 0;  // Not a pointer
  }
  
  return type;
}

static bool ParsePrimary(Compiler *cc) {
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

      if (!LexExpect(cc, ')')) return false;

      if (type_class && type_class->size > 0) {
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
      if (sym) {
        if (sym->is_array && sym->array_size >= 0 && sym->element_size > 0) {
          size = sym->array_size * sym->element_size;
        } else if (sym->size > 0) {
          size = sym->size;
        } else {
          size = PrimitiveTypeSize(sym->data_type);
        }
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
          computed = true;
        } else {
          Error(cc, "Unknown identifier in sizeof");
          free(name);
          return false;
        }
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
    // Integer literal
    ICAdd(cc, IC_IMM_I64, cc->lex.token_i64, RT_I64);
    LexNext(cc);
    return true;
  }
  
  if (cc->lex.token == TK_F64) {
    // Float literal - store as I64 bit pattern
    I64 bits = *(I64*)&cc->lex.token_f64;
    ICAdd(cc, IC_IMM_F64, bits, RT_F64);
    LexNext(cc);
    return true;
  }
  
  if (cc->lex.token == TK_STR) {
    // String literal - add to string table
    char *str = cc->lex.token_str ? strdup(cc->lex.token_str) : strdup("");
    
    // Add to string table (will be emitted at end of code)
    StringLiteral *sl = malloc(sizeof(StringLiteral));
    sl->str = str;
    sl->offset = 0;  // Will be set during code generation
    sl->next = cc->strings;
    cc->strings = sl;
    
    // Use special IC to mark string literal (offset will be patched)
    ICAdd(cc, IC_STR_CONST, (I64)sl, RT_I64);
    LexNext(cc);
    return true;
  }
  
  if (cc->lex.token == TK_IDENT) {
    // Variable or function call
    char *name = strdup(cc->lex.token_str);
    if (!name) return false;  // malloc failed
    
    LexNext(cc);
    
    if (cc->lex.token == '(') {
      // Function call
      LexNext(cc); // Skip '('
      
      ICAdd(cc, IC_CALL_START, 0, RT_I64);
      
      // Parse arguments
      int arg_count = 0;
      if (cc->lex.token != ')') {
        do {
          if (arg_count > 0) {
            if (!LexExpect(cc, ',')) {
              free(name);
              return false;
            }
          }
          if (!ParseExpression(cc)) {
            free(name);
            return false;
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
          // Same-unit calls: PC-relative jal via stable entry label (AOT under QEMU).
          if (cc->current_function_entry_label && func == cc->last_compiled_func) {
            ICAdd(cc, IC_CALL, (I64)cc->current_function_entry_label, RT_I64);
          } else if (func->entry_label) {
            ICAdd(cc, IC_CALL, (I64)func->entry_label, RT_I64);
          } else {
            ICAdd(cc, IC_CALL_INDIRECT2, (I64)&func->exe_addr, RT_I64);
          }
          // Store actual arg_cnt for compiler to use (not func->arg_cnt)
          cc->last_call_arg_cnt = arg_count;
          
          
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
          ICAdd(cc, IC_CALL_INDIRECT, 0, RT_I64);
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
            ICAdd(cc, IC_DEREF, 0, RT_I64);
            cc->last_call_arg_cnt = arg_count;
            ICAdd(cc, IC_CALL_INDIRECT, 0, RT_I64);
            ICAdd(cc, IC_CALL_END, 0, RT_I64);
            free(name);
            return true;
          }
        }

        // Function not found - emit warning result
        Error(cc, "Unknown function or function pointer");
        ICAdd(cc, IC_IMM_I64, 0, RT_I64);
      }
      
      ICAdd(cc, IC_CALL_END, 0, RT_I64);
      free(name);
      return true;
    } else {
      // Variable reference - check local symbol table first, then globals
      Symbol *sym = SymbolLookup(cc, name);
      if (sym) {
        // Local variable - save symbol for array subscripting
        cc->last_var_symbol = sym;
        cc->last_global_var = NULL;
        cc->last_expr_class = sym->extra ? (CHashClass*)sym->extra : NULL;
        
        // Match original (PrsExp.HC:765-807)
        // Clear CCF_RAX flag (line 765)
        cc->flags &= ~(CCF_RAX | CCF_ARRAY);
        
        // ALL variables (including parameters) use same pattern
        // Generate address of variable: addi a0, s0, offset
        // Use IC_LEA (Load Effective Address) with offset
        ICAdd(cc, IC_LEA, sym->offset, RT_I64);
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
        
        // Generate load from global (absolute address)
        CICType type = {0};
        type.mode = MDF_IMM;
        type.raw_type = RT_I64;
        
        // For now, push the address of the global
        // Full implementation would load the value
        CIntermediateCode *ic = ICNew(cc, IC_IMM_I64);
        ic->ic_data = (I64)global->data_addr;
        cc->last_expr_class = global->var_class;
        cc->flags &= ~(CCF_RAX | CCF_ARRAY);
        
        // Link into IC chain
        if (cc->ic_tail) cc->ic_tail->next = ic;
        else cc->ic_head = ic;
        cc->ic_tail = ic;
        
        free(name);
        return true;
      }
      
      // Check for function reference (decays to pointer)
      CHashEntry *func_entry = HashFind(name, cc->hash_table, HTT_FUN);
      if (func_entry && (func_entry->type & HTT_FUN)) {
        CHashFun *func = (CHashFun*)func_entry;
        // Load pointer to exe_addr field (resolved at runtime)
        ICAdd(cc, IC_IMM_I64, (I64)&func->exe_addr, RT_I64);
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
      (void)ParseType(cc);
      if (cc->lex.token == ')') {
        LexNext(cc);  // Skip ')'
        LexPopNoRestore(cc);
        // Cast to pointer/int: value remains in a0/eval stack; no extra IC for (T*) on I64.
        if (!ParseUnary(cc)) {
          cc->last_pointed_to_type = saved_pt;
          cc->last_type_class = saved_tc;
          return false;
        }
        cc->last_pointed_to_type = saved_pt;
        cc->last_type_class = saved_tc;
        cc->last_var_symbol = NULL;
        return true;
      }
    }
    LexPopRestore(cc);
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
    ICAdd(cc, IC_PP_, 0, RT_I64);  // IC_PP_ is pre-increment
    return true;
  }
  
  // Pre-decrement: --var
  if (cc->lex.token == TK_SUB_SUB) {
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    ICAdd(cc, IC_MM_, 0, RT_I64);  // IC_MM_ is pre-decrement
    return true;
  }
  
  if (cc->lex.token == '-') {
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    ICAdd(cc, IC_UNARY_MINUS, 0, RT_I64);
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
    I64 saved_flags = cc->flags;
    cc->flags |= CCF_RAX;
    if (!ParseUnary(cc)) {
      cc->flags = saved_flags;
      return false;
    }
    cc->flags = saved_flags;
    ICAdd(cc, IC_ADDR, 0, RT_I64);
    cc->last_var_symbol = NULL;
    cc->last_global_var = NULL;
    return true;
  }
  
  if (cc->lex.token == '*') {
    // Dereference operator - explicit dereference
    LexNext(cc);

    if (!ParseUnary(cc)) return false;

    U8 deref_type = RT_I64;
    if (cc->last_var_symbol && cc->last_var_symbol->pointed_to_type != 0) {
      deref_type = cc->last_var_symbol->pointed_to_type;
    }
    /* Drop duplicate pointer slot (still in a0) before DEREF pushes *a0 — else DROP after would
     * pop the loaded value. */
    ICAdd(cc, IC_EVAL_DROP, 8, RT_I64);
    ICAdd(cc, IC_DEREF, 0, RT_I64);
    if (cc->ic_tail) cc->ic_tail->arg1_type_pointed_to = deref_type;
    cc->last_var_symbol = NULL;
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
    // Auto-deref for global variables
    CIntermediateCode *ic = ICNew(cc, IC_DEREF);
    ic->res.type.raw_type = RT_I64;
    ic->res.type.mode = MDF_STK;
    ic->arg1_type_pointed_to = cc->last_global_var->raw_type;
    
    if (cc->ic_tail) cc->ic_tail->next = ic;
    else cc->ic_head = ic;
    cc->ic_tail = ic;
  }
  
  // Handle postfix operators (array subscript, member access)
  while (true) {
    if (cc->lex.token == '[') {
      // Array subscripting: arr[index]
      // Result: (base_addr + index * element_size)
      
      LexNext(cc);  // Skip '['
      
      // Get element size from last variable's type info
      I64 elem_size = 8;  // Default to I64
      Symbol *saved_symbol = cc->last_var_symbol;
      CHashGlblVar *saved_global = cc->last_global_var;
      if (saved_symbol) {
        elem_size = saved_symbol->element_size;
      } else if (saved_global) {
        elem_size = saved_global->element_size ? saved_global->element_size : 8;
      }
      
      // Push element size
      ICAdd(cc, IC_IMM_I64, elem_size, RT_I64);
      
      // Parse index expression (will clobber last_var_symbol, save it)
      if (!ParseExpression(cc)) return false;
      
      // Restore for potential chained subscripts
      cc->last_var_symbol = saved_symbol;
      cc->last_global_var = saved_global;
      
      if (!LexExpect(cc, ']')) return false;
      
      // Multiply index by element size
      ICAdd(cc, IC_MUL, 0, RT_I64);
      
      // Add offset to base address
      ICAdd(cc, IC_ADD, 0, RT_I64);
      
      // Dereference to get the value
      // This loads the value at the calculated address
      if (!(cc->flags & CCF_RAX)) {
        ICAdd(cc, IC_DEREF, 0, RT_I64);
      }
      
      continue;
    }
    
    if (cc->lex.token == '.') {
      // Member access: struct.member
      LexNext(cc);  // Skip '.'
      
      if (cc->lex.token != TK_IDENT) {
        Error(cc, "Expected member name after '.'");
        return false;
      }
      
      char *member_name = strdup(cc->lex.token_str);
      
      // Look up member in class definition
      I64 member_offset = 0;
      CHashClass *member_class = NULL;
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
      
      if (member_offset != 0) {
        // Add offset to base address
        ICAdd(cc, IC_IMM_I64, member_offset, RT_I64);
        ICAdd(cc, IC_ADD, 0, RT_I64);
      }
      
      // Dereference to get member value
      if (!(cc->flags & CCF_RAX)) {
        ICAdd(cc, IC_DEREF, 0, RT_I64);
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
      ICAdd(cc, IC__PP, 0, RT_I64);  // IC__PP is post-increment
      continue;
    }
    
    // Post-decrement: var--
    if (cc->lex.token == TK_SUB_SUB) {
      LexNext(cc);
      ICAdd(cc, IC__MM, 0, RT_I64);  // IC__MM is post-decrement
      continue;
    }
    
    // Arrow operator: ptr->member (same as (*ptr).member)
    if (cc->lex.token == TK_ARROW) {
      LexNext(cc);
      
      if (cc->lex.token != TK_IDENT) {
        Error(cc, "Expected member name after '->'");
        return false;
      }
      
      char *member_name = strdup(cc->lex.token_str);
      
      // First dereference the pointer
      if (!(cc->flags & CCF_RAX)) {
        ICAdd(cc, IC_DEREF, 0, RT_I64);
      }
      
      // Look up member offset (same as . operator)
      I64 member_offset = 0;
      CHashClass *member_class = NULL;
      
      if (cc->last_expr_class) {
        CMemberLst *member = cc->last_expr_class->member_lst;
        while (member) {
          if (strcmp(member->str, member_name) == 0) {
            member_offset = member->offset;
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
      
      if (!(cc->flags & CCF_RAX)) {
        ICAdd(cc, IC_DEREF, 0, RT_I64);
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
  if (last_ic && (last_ic->ic_code == IC_ADD || last_ic->ic_code == IC_LEA) && !is_paren_expr && !(cc->flags & CCF_RAX)) {
    // Last was IC_ADD or IC_LEA (address of variable)
    // Add IC_DEREF to load the value (PrsExp.HC:116-117)
    ICAdd(cc, IC_DEREF, 0, RT_I64);
  }
  
  return true;
}


static bool ParseMul(Compiler *cc) {
  if (!ParseUnary(cc)) return false;
  
  while (cc->lex.token == '*' || cc->lex.token == '/' || cc->lex.token == '%') {
    int op = cc->lex.token;
    LexNext(cc);
    if (!ParseUnary(cc)) return false;
    
    if (op == '*') ICAdd(cc, IC_MUL, 0, RT_I64);
    else if (op == '/') ICAdd(cc, IC_DIV, 0, RT_I64);
    else ICAdd(cc, IC_MOD, 0, RT_I64);
  }
  
  return true;
}


static bool ParseAdd(Compiler *cc) {
  if (!ParseMul(cc)) return false;
  
  while (cc->lex.token == '+' || cc->lex.token == '-') {
    int op = cc->lex.token;
    LexNext(cc);
    if (!ParseMul(cc)) return false;
    
    if (op == '+') ICAdd(cc, IC_ADD, 0, RT_I64);
    else ICAdd(cc, IC_SUB, 0, RT_I64);
  }
  
  return true;
}


static bool ParseShift(Compiler *cc) {
  if (!ParseAdd(cc)) return false;
  
  while (cc->lex.token == TK_SHL || cc->lex.token == TK_SHR) {
    int op = cc->lex.token;
    LexNext(cc);
    if (!ParseAdd(cc)) return false;
    
    if (op == TK_SHL) ICAdd(cc, IC_SHL, 0, RT_I64);
    else ICAdd(cc, IC_SHR, 0, RT_I64);
  }
  
  return true;
}


static bool ParseComparison(Compiler *cc) {
  if (!ParseShift(cc)) return false;
  
  while (cc->lex.token == '<' || cc->lex.token == '>' ||
         cc->lex.token == TK_LESS_EQU || cc->lex.token == TK_GREATER_EQU) {
    int op = cc->lex.token;
    LexNext(cc);
    if (!ParseShift(cc)) return false;
    
    switch (op) {
      case '<': ICAdd(cc, IC_LESS, 0, RT_I64); break;
      case '>': ICAdd(cc, IC_GREATER, 0, RT_I64); break;
      case TK_LESS_EQU: ICAdd(cc, IC_LESS_EQU, 0, RT_I64); break;
      case TK_GREATER_EQU: ICAdd(cc, IC_GREATER_EQU, 0, RT_I64); break;
    }
  }
  
  return true;
}


static bool ParseEquality(Compiler *cc) {
  if (!ParseComparison(cc)) return false;
  
  while (cc->lex.token == TK_EQU_EQU || cc->lex.token == TK_NOT_EQU) {
    int op = cc->lex.token;
    LexNext(cc);
    if (!ParseComparison(cc)) return false;
    
    if (op == TK_EQU_EQU) ICAdd(cc, IC_EQU_EQU, 0, RT_I64);
    else ICAdd(cc, IC_NOT_EQU, 0, RT_I64);
  }
  
  return true;
}


static bool ParseBitwiseAnd(Compiler *cc) {
  if (!ParseEquality(cc)) return false;
  
  while (cc->lex.token == '&') {
    LexNext(cc);
    if (!ParseEquality(cc)) return false;
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
  if (!ParseBitwiseOr(cc)) {
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
    if (!ParseBitwiseOr(cc)) return false;
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


static bool ParseLogicalOr(Compiler *cc) {
  if (!ParseLogicalAnd(cc)) {
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
    if (!ParseLogicalAnd(cc)) return false;
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


static bool ParseAssignment(Compiler *cc) {
  
  // Parse left-hand side
  if (!ParseTernary(cc)) {
    return false;
  }
  
  
  // Check for assignment operators (right-associative)
  if (cc->lex.token == '=') {
    // SET CCF_RAX to indicate lvalue (address needed, not value)
    // Match original PrsExp.HC:201-209
    CIntermediateCode *lval_ic = cc->ic_tail;
    U8 store_type = RT_I64;  // Default
    CIntermediateCode *lea_ic = NULL;
    CHashGlblVar *lval_global = cc->last_global_var;
    
    if (lval_ic && lval_ic->ic_code == IC_DEREF) {
      // Save the pointed-to type for typed store
      store_type = lval_ic->arg1_type_pointed_to;
      if (lval_global) {
        store_type = lval_global->raw_type ? lval_global->raw_type : RT_I64;
      }
      
      // Find the LEA before this DEREF by walking from head
      // We need to push the address BEFORE the DEREF executes
      CIntermediateCode *ic_scan = cc->ic_head;
      while (ic_scan && ic_scan != lval_ic) {
        if (ic_scan->ic_code == IC_LEA) {
          lea_ic = ic_scan;
        }
        ic_scan = ic_scan->next;
      }
      
      // If we found a LEA, insert IC_PUSH_ARG right after it (before DEREF)
      // This preserves the address before DEREF overwrites a0 with the value
      if (lea_ic) {
        // Check if IC_PUSH_ARG is already present (avoid double insertion)
        if (lea_ic->next && lea_ic->next->ic_code == IC_PUSH_ARG) {
          // Already has IC_PUSH_ARG, skip insertion
        } else {
          CIntermediateCode *push_ic = ICNew(cc, IC_PUSH_ARG);
          push_ic->res.type.raw_type = RT_I64;
          push_ic->res.type.mode = MDF_STK;
          
          // Insert after LEA, before DEREF
          push_ic->next = lea_ic->next;
          lea_ic->next = push_ic;
        }
      } else if (lval_global) {
        // Global variable assignment: insert push after the IMM that loaded address
        CIntermediateCode *imm_ic = cc->ic_head;
        while (imm_ic && imm_ic->next != lval_ic) {
          imm_ic = imm_ic->next;
        }
        if (imm_ic && imm_ic->ic_code == IC_IMM_I64 && imm_ic->ic_data == (I64)lval_global->data_addr) {
          if (!(imm_ic->next && imm_ic->next->ic_code == IC_PUSH_ARG)) {
            CIntermediateCode *push_ic = calloc(1, sizeof(CIntermediateCode));
            push_ic->ic_code = IC_PUSH_ARG;
            push_ic->res.type.raw_type = RT_I64;
            push_ic->res.type.mode = MDF_STK;
            push_ic->last = imm_ic;
            push_ic->next = imm_ic->next;
            if (push_ic->next) {
              push_ic->next->last = push_ic;
            } else {
              cc->ic_tail = push_ic;
            }
            imm_ic->next = push_ic;
          }
        }
      }
      
      // Remove the auto-deref that was added (we need address for assignment)
      lval_ic->ic_code = IC_NOP1;
    } else if (lval_ic && lval_ic->ic_code == IC_LEA) {
      // LEA without DEREF - insert PUSH_ARG after it
      if (lval_ic->next && lval_ic->next->ic_code == IC_PUSH_ARG) {
        // Already has IC_PUSH_ARG immediately after, skip insertion
      } else {
        CIntermediateCode *push_ic = ICNew(cc, IC_PUSH_ARG);
        push_ic->res.type.raw_type = RT_I64;
        push_ic->res.type.mode = MDF_STK;
        
        push_ic->next = lval_ic->next;
        lval_ic->next = push_ic;
        
        if (cc->ic_tail == lval_ic) {
          cc->ic_tail = push_ic;
        }
      }
    }
    
    LexNext(cc);
    if (!ParseAssignment(cc)) return false;
    
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
  if (cc->lex.token == TK_ADD_EQU) {
    LexNext(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, IC_ADD_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_SUB_EQU) {
    LexNext(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, IC_SUB_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_MUL_EQU) {
    LexNext(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, IC_MUL_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_DIV_EQU) {
    LexNext(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, IC_DIV_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_AND_EQU) {
    LexNext(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, IC_AND_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_OR_EQU) {
    LexNext(cc);
    if (!ParseAssignment(cc)) return false;
    ICAdd(cc, IC_OR_EQU, 0, RT_I64);
    return true;
  }
  
  if (cc->lex.token == TK_XOR_EQU) {
    LexNext(cc);
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


static bool ParseWhileStatement(Compiler *cc) {
  LexNext(cc); // Skip 'while'
  
  CLabel *start_label = LabelNew(cc, NULL);
  CLabel *end_label = LabelNew(cc, NULL);
  
  // Save current loop context
  CLabel *saved_break = cc->current_break_label;
  CLabel *saved_continue = cc->current_continue_label;
  
  // Set new loop context
  cc->current_break_label = end_label;
  cc->current_continue_label = start_label;
  
  // Start label
  ICAdd(cc, IC_LABEL, (I64)start_label, RT_I64);
  start_label->defined = true;
  
  if (!LexExpect(cc, '(')) {
    cc->current_break_label = saved_break;
    cc->current_continue_label = saved_continue;
    return false;
  }
  if (!ParseExpression(cc)) {
    cc->current_break_label = saved_break;
    cc->current_continue_label = saved_continue;
    return false;
  }
  if (!LexExpect(cc, ')')) {
    cc->current_break_label = saved_break;
    cc->current_continue_label = saved_continue;
    return false;
  }
  
  // Branch if false (exit loop)
  ICAdd(cc, IC_BR_ZERO, (I64)end_label, RT_I64);
  
  // Loop body
  if (!ParseStatement(cc)) {
    cc->current_break_label = saved_break;
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
  cc->current_continue_label = continue_label;
  
  // Start label
  ICAdd(cc, IC_LABEL, (I64)start_label, RT_I64);
  start_label->defined = true;
  
  // Condition
  if (cc->lex.token != ';') {
    if (!ParseExpression(cc)) {
      cc->current_break_label = saved_break;
      cc->current_continue_label = saved_continue;
      return false;
    }
    ICAdd(cc, IC_BR_ZERO, (I64)end_label, RT_I64);
  }
  
  if (!LexExpect(cc, ';')) {
    cc->current_break_label = saved_break;
    cc->current_continue_label = saved_continue;
    return false;
  }
  
  // Advance lexer through the increment clause (not re-parsed into IC here).
  int paren_depth = 0;
  while (cc->lex.token != ')' || paren_depth > 0) {
    if (cc->lex.token == '(') paren_depth++;
    if (cc->lex.token == ')') paren_depth--;
    LexNext(cc);
  }
  
  if (!LexExpect(cc, ')')) {
    cc->current_break_label = saved_break;
    cc->current_continue_label = saved_continue;
    return false;
  }
  
  // Body
  if (!ParseStatement(cc)) {
    cc->current_break_label = saved_break;
    cc->current_continue_label = saved_continue;
    return false;
  }
  
  // Continue label (increment)
  ICAdd(cc, IC_LABEL, (I64)continue_label, RT_I64);
  continue_label->defined = true;
  
  // Jump back to start
  ICAdd(cc, IC_JMP, (I64)start_label, RT_I64);
  
  // End label
  ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
  end_label->defined = true;
  
  // Restore loop context
  cc->current_break_label = saved_break;
  cc->current_continue_label = saved_continue;
  
  return true;
}


static bool ParseSwitchStatement(Compiler *cc) {
  LexNext(cc); // Skip 'switch'
  
  if (!LexExpect(cc, '(')) return false;
  
  // Parse switch expression
  if (!ParseExpression(cc)) return false;
  
  if (!LexExpect(cc, ')')) return false;
  if (!LexExpect(cc, '{')) return false;
  
  // Build case list
  CSwitchCase *cases = NULL;
  CSwitchCase *last_case = NULL;
  CLabel *default_label = NULL;
  CLabel *end_label = LabelNew(cc, NULL);
  
  I64 min_val = 0x7FFFFFFFFFFFFFFFLL;  // I64_MAX
  I64 max_val = -0x8000000000000000LL; // I64_MIN
  
  // Save break context
  CLabel *saved_break = cc->current_break_label;
  cc->current_break_label = end_label;
  
  // Parse cases
  while (cc->lex.token != '}' && cc->lex.token != TK_EOF) {
    if (cc->lex.token == KW_CASE) {
      LexNext(cc);
      
      // Get case value
      if (cc->lex.token != TK_I64) {
        Error(cc, "Expected integer constant in case");
        cc->current_break_label = saved_break;
        return false;
      }
      
      I64 case_val = cc->lex.token_i64;
      LexNext(cc);
      
      if (!LexExpect(cc, ':')) {
        cc->current_break_label = saved_break;
        return false;
      }
      
      // Create case entry
      CSwitchCase *sc = calloc(1, sizeof(CSwitchCase));
      sc->value = case_val;
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
             cc->lex.token != '}' && cc->lex.token != TK_EOF) {
        if (!ParseStatement(cc)) {
          cc->current_break_label = saved_break;
          return false;
        }
      }
      
      continue;
    }
    
    if (cc->lex.token == KW_DEFAULT) {
      LexNext(cc);
      
      if (!LexExpect(cc, ':')) {
        cc->current_break_label = saved_break;
        return false;
      }
      
      // Create default label
      default_label = LabelNew(cc, NULL);
      ICAdd(cc, IC_LABEL, (I64)default_label, RT_I64);
      default_label->defined = true;
      
      // Parse statements until next case or }
      while (cc->lex.token != KW_CASE && cc->lex.token != '}' && cc->lex.token != TK_EOF) {
        if (!ParseStatement(cc)) {
          cc->current_break_label = saved_break;
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
    return false;
  }
  
  // Generate jump table (simplified - using if/else chain for now)
  // Full implementation would build actual jump table
  // For now, emit cascading comparisons
  CSwitchCase *sc = cases;
  while (sc) {
    // Compare with case value
    ICAdd(cc, IC_IMM_I64, sc->value, RT_I64);
    ICAdd(cc, IC_EQU_EQU, 0, RT_I64);
    ICAdd(cc, IC_BR_NOT_ZERO, (I64)sc->label, RT_I64);
    sc = sc->next;
  }
  
  // Jump to default or end
  if (default_label) {
    ICAdd(cc, IC_JMP, (I64)default_label, RT_I64);
  } else {
    ICAdd(cc, IC_JMP, (I64)end_label, RT_I64);
  }
  
  // End label
  ICAdd(cc, IC_LABEL, (I64)end_label, RT_I64);
  end_label->defined = true;
  
  // Restore break context
  cc->current_break_label = saved_break;
  
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
    
    // Initialize array metadata
    sym->is_array = false;
    sym->array_size = 0;
    sym->element_size = base_size;
    
    // Handle arrays
    int total_size = base_size;
    if (cc->lex.token == '[') {
      LexNext(cc);  // Skip '['
      
      if (cc->lex.token != TK_I64) {
        free(name);
        Error(cc, "Expected array size");
        return false;
      }
      
      int array_size = cc->lex.token_i64;
      LexNext(cc);  // Skip size
      
      if (!LexExpect(cc, ']')) {
        free(name);
        return false;
      }
      
      // Store array metadata
      sym->is_array = true;
      sym->array_size = array_size;
      sym->element_size = base_size;
      
      total_size = base_size * array_size;
    }
    
    sym->size = total_size;
    
    // Allocate on stack (round up to 8-byte alignment)
    int aligned_size = (total_size + 7) & ~7;
    
    // Mark the position in the locals area (before incrementing locals_size)
    // Use NEGATIVE marker to avoid collision with real values
    sym->offset = -(10000 + cc->locals_size);  // Temporary: -10000-position marker
    
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
      
      // Create IC_ASSIGN - ParseAssignment does this, but we do it manually here
      CIntermediateCode *ic = ICNew(cc, IC_ASSIGN);
      ic->res.type.raw_type = RT_I64;
      ic->res.type.mode = MDF_STK;
      ic->arg1_type_pointed_to = RT_I64;
      
      // Link into IC chain
      if (cc->ic_tail) cc->ic_tail->next = ic;
      else cc->ic_head = ic;
      cc->ic_tail = ic;
      
      cc->last_var_symbol = NULL;
    }
    
    // Restore declaration class for subsequent comma-separated variables
    cc->last_type_class = decl_class;

    free(name);
    
    // Check for comma (more variables) or semicolon/comma (end)
    if (cc->lex.token == ',') {
      LexNext(cc);
      
      // Check if it's another variable or end of statement
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
      } else {
        bool result = ParseVariableDeclWithName(cc, type, var_name);
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
      
      if (cc->lex.token != ';' && cc->lex.token != ',') {
        // return <expression>;
        if (!ParseExpression(cc)) return false;
        ICAdd(cc, IC_RETURN_VAL, 0, RT_I64);
      }
      
      // Jump to function exit label
      if (cc->current_function_exit) {
        ICAdd(cc, IC_JMP, (I64)cc->current_function_exit, RT_I64);
      }
      
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
      LexNext(cc);
      
      // Create labels for exception handling (bare metal safe - no StrPrintF)
      // Use NULL for name - labels don't need names at runtime
      CLabel *catch_label = LabelNew(cc, NULL);
      CLabel *done_label = LabelNew(cc, NULL);
      CLabel *untry_label = LabelNew(cc, NULL);
      
      // Setup try: push catch and untry labels as exception handler
      // IC_CALL_START marks beginning of call sequence
      ICAdd(cc, IC_CALL_START, 0, RT_I64);
      
      // Push untry and catch label addresses as function arguments
      ICAdd(cc, IC_IMM_I64, (I64)untry_label, RT_I64);
      ICAdd(cc, IC_IMM_I64, (I64)catch_label, RT_I64);
      
      // TODO: Call SysTry(catch_label, untry_label) - system function to register exception handler
      // For now, just mark the call setup
      ICAdd(cc, IC_CALL_END, 0, RT_I64);
      
      // Parse try block (PrsStmt.HC:877)
      if (!ParseStatement(cc)) return false;
      
      // Untry label: cleanup exception handler (PrsStmt.HC:879-890)
      ICAdd(cc, IC_LABEL, (I64)untry_label, RT_I64);
      ICAdd(cc, IC_CALL_START, 0, RT_I64);
      // TODO: Call SysUntry() - system function to unregister exception handler
      ICAdd(cc, IC_CALL_END, 0, RT_I64);
      
      // Jump past catch block (PrsStmt.HC:892)
      ICAdd(cc, IC_JMP, (I64)done_label, RT_I64);
      
      // Expect catch keyword (PrsStmt.HC:894-895)
      if (cc->lex.token != KW_CATCH) {
        Error(cc, "Expected 'catch' after 'try' block");
        return false;
      }
      LexNext(cc);  // Skip 'catch'
      
      // Catch label: where exceptions jump to (PrsStmt.HC:898)
      ICAdd(cc, IC_LABEL, (I64)catch_label, RT_I64);
      
      // Parse catch block (PrsStmt.HC:899)
      if (!ParseStatement(cc)) return false;
      
      // Return from catch (PrsStmt.HC:900)
      ICAdd(cc, IC_IMM_I64, 0, RT_I64);
      ICAdd(cc, IC_RET, 0, RT_I64);
      
      // Done label (PrsStmt.HC:901)
      ICAdd(cc, IC_LABEL, (I64)done_label, RT_I64);
      
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
      
      // TODO: Generate exception throw IC (calls Throw() which jumps to registered catch handler)
      // For now, treat as forced return with error code
      ICAdd(cc, IC_RET, 0, RT_I64);
      
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
      
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    // For REPL: skip label lookahead (uses LexPush which crashes in bare metal)
    // Labels are not commonly used in REPL mode anyway
    
    // Match original PrsStmt.HC:1201-1203
    // String or char literal as statement -> auto-call Print() or PutChars()
    if (cc->lex.token == TK_STR) {
      // Store the string literal
      char *str_lit = strdup(cc->lex.token_str);
      LexNext(cc);  // Skip string
      
      // Look up Print function
      CHashEntry *print_entry = HashFind("Print", cc->hash_table, HTT_FUN);
      if (print_entry && (print_entry->type & HTT_FUN)) {
        // Generate Print(str) call
        ICAdd(cc, IC_CALL_START, 0, RT_I64);
        
        // Push string argument (use IC_STR_CONST to store string)
        // For now, just push the string pointer as immediate
        ICAdd(cc, IC_IMM_I64, (I64)str_lit, RT_I64);
        
        // Call Print
        CHashFun *print_fun = (CHashFun*)print_entry;
        if (print_fun->exe_addr) {
          CLabel *print_label = (CLabel*)print_fun->exe_addr;
          ICAdd(cc, IC_CALL, (I64)print_label, RT_I64);
        }
        ICAdd(cc, IC_CALL_END, 0, RT_I64);
        ICAdd(cc, IC_END_EXP, 0, RT_I64);  // Discard return value
      } else {
        // No Print function - just discard the string
        free(str_lit);
      }
      
      if (cc->lex.token == ';') LexNext(cc);
      if (cc->lex.token != ',') return true;
      continue;
    }
    
    
    // Expression statement
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

bool ParseClass(Compiler *cc) {
  // Parse: class ClassName { members }; or union ClassName { members };
  
  bool is_union = false;
  if (cc->lex.token == KW_UNION) {
    is_union = true;
    LexNext(cc);
  } else if (cc->lex.token == KW_CLASS) {
    LexNext(cc);
  } else {
    return false;
  }
  
  if (cc->lex.token != TK_IDENT) {
    Error(cc, "Expected class name");
    return false;
  }
  
  char *class_name = strdup(cc->lex.token_str);
  LexNext(cc);
  
  // Create class hash entry
  CHashClass *tmpc = calloc(1, sizeof(CHashClass));
  tmpc->str = strdup(class_name);
  tmpc->type = HTT_CLASS;
  tmpc->raw_type = RT_I64;  // Classes are pointers
  tmpc->size = 0;  // Will be calculated from members
  tmpc->ptr_stars_cnt = 0;
  tmpc->base_class = NULL;
  tmpc->member_lst = NULL;
  
  // Handle inheritance: class Name : BaseClass
  if (cc->lex.token == ':') {
    LexNext(cc);
    if (cc->lex.token != TK_IDENT) {
      Error(cc, "Expected base class name");
      free(class_name);
      free(tmpc->str);
      free(tmpc);
      return false;
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
    free(tmpc->str);
    free(tmpc);
    return false;
  }
  
  // Parse members
  I64 member_offset = tmpc->size;  // Start after base class size
  I64 max_member_size = 0;  // For unions
  CMemberLst *last_member = NULL;
  
  while (cc->lex.token != '}' && cc->lex.token != TK_EOF) {
    // Parse member type
    U8 member_type = ParseType(cc);
    
    if (cc->lex.token != TK_IDENT) {
      // Skip to recovery point
      while (cc->lex.token != ';' && cc->lex.token != '}' && cc->lex.token != TK_EOF) {
        LexNext(cc);
      }
      if (cc->lex.token == ';') LexNext(cc);
      continue;
    }
    
    char *member_name = strdup(cc->lex.token_str);
    LexNext(cc);
    
    // Get member size
    I64 member_size = 8;  // Default
    switch (member_type) {
      case RT_I8: case RT_U8: member_size = 1; break;
      case RT_I16: case RT_U16: member_size = 2; break;
      case RT_I32: case RT_U32: member_size = 4; break;
      default: member_size = 8; break;
    }
    
    // Handle arrays
    if (cc->lex.token == '[') {
      LexNext(cc);
      if (cc->lex.token == TK_I64) {
        I64 array_size = cc->lex.token_i64;
        member_size *= array_size;
        LexNext(cc);
      }
      if (!LexExpect(cc, ']')) {
        free(member_name);
        continue;
      }
    }
    
    // Create member
    CMemberLst *member = calloc(1, sizeof(CMemberLst));
    member->str = member_name;
    
    if (is_union) {
      // Union: all members at offset 0, size is max of all members
      member->offset = 0;
      if (member_size > max_member_size) {
        max_member_size = member_size;
      }
    } else {
      // Struct: members have sequential offsets
      member->offset = member_offset;
    }
    
    member->size = member_size;
    member->next = NULL;
    member->bit_offset = 0;
    member->bit_width = 0;
    
    // Check for bit field: member_name:width
    if (cc->lex.token == ':') {
      LexNext(cc);
      
      // Parse bit width
      if (cc->lex.token != TK_I64) {
        Error(cc, "Expected bit field width");
        return false;
      }
      
      member->bit_width = cc->lex.token_i64;
      LexNext(cc);
      
      // For simplicity, each bit field starts at a byte boundary
      // Full implementation would pack bits within bytes
      member->bit_offset = 0;
      
      // Adjust size to fit the bits
      I64 bytes_needed = (member->bit_width + 7) / 8;
      member->size = bytes_needed;
    }
    
    // Add to list
    if (last_member) {
      last_member->next = member;
    } else {
      tmpc->member_lst = member;
    }
    last_member = member;
    
    // Advance offset (for structs only)
    if (!is_union) {
      member_offset += member->size;
    }
    
    // Skip any metadata attributes (print_str, dft_val, output_fun, etc.)
    // These come after the member name, before the semicolon
    while (cc->lex.token != ';' && cc->lex.token != '}' && cc->lex.token != TK_EOF) {
      LexNext(cc);
    }
    
    // Expect semicolon
    if (!LexExpect(cc, ';')) {
      break;
    }
  }
  
  // Set total size
  if (is_union) {
    tmpc->size = max_member_size;
  } else {
    tmpc->size = member_offset;
  }
  
  if (!LexExpect(cc, '}')) {
    free(class_name);
    free(tmpc->str);
    free(tmpc);
    return false;
  }
  
  // Add class to hash table
  HashAdd((CHashEntry*)tmpc, cc->hash_table);
  
  free(class_name);
  
  // Expect semicolon after class definition
  return LexExpect(cc, ';');
}

// ═══════════════════════════════════════════════════════════════
// PARSER - GLOBAL VARIABLES
// ═══════════════════════════════════════════════════════════════

static bool ParseGlobalVariable(Compiler *cc, U8 var_type, char *var_name) {
  // Simplified global variable parsing
  // Full version would handle: extern, import, initialization, arrays, etc.
  
  CHashClass *decl_class = cc->last_type_class;

  // Create global variable hash entry
  CHashGlblVar *tmpg = calloc(1, sizeof(CHashGlblVar));
  tmpg->str = strdup(var_name);
  tmpg->type = HTT_GLBL_VAR;
  tmpg->use_cnt = 0;
  tmpg->flags = 0;
  tmpg->var_class = decl_class;
  tmpg->raw_type = var_type;
  tmpg->pointed_to_type = cc->last_pointed_to_type;
  
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
    LexNext(cc);
    I64 array_size = 0;
    if (cc->lex.token == TK_I64) {
      array_size = cc->lex.token_i64;
      LexNext(cc);
    }
    if (!LexExpect(cc, ']')) {
      free(tmpg->str);
      free(tmpg);
      return false;
    }
    
    tmpg->dim.cnt = array_size;
    tmpg->dim.total_cnt = array_size;
    tmpg->size *= array_size;
    tmpg->flags |= GVF_ARRAY;
  }
  
  // Allocate memory for the global
  tmpg->data_addr = calloc(1, tmpg->size);
  
  // Handle initialization
  if (cc->lex.token == '=') {
    LexNext(cc);
    
    // For constant initialization, evaluate and store directly
    if (cc->lex.token == TK_I64) {
      I64 init_val = cc->lex.token_i64;
      LexNext(cc);
      
      // Store initialization value
      if (tmpg->size == 1) *(I8*)tmpg->data_addr = (I8)init_val;
      else if (tmpg->size == 2) *(I16*)tmpg->data_addr = (I16)init_val;
      else if (tmpg->size == 4) *(I32*)tmpg->data_addr = (I32)init_val;
      else if (tmpg->size == 8) *(I64*)tmpg->data_addr = init_val;
    } else if (cc->lex.token == TK_F64) {
      F64 init_val = cc->lex.token_f64;
      LexNext(cc);
      
      if (tmpg->size == 8) *(F64*)tmpg->data_addr = init_val;
    } else {
      // Non-constant initialization - skip for now
      // Full implementation would evaluate complex expressions
      int depth = 0;
      while (cc->lex.token != ';' && cc->lex.token != ',' && cc->lex.token != TK_EOF) {
        if (cc->lex.token == '{') depth++;
        if (cc->lex.token == '}') {
          if (depth > 0) depth--;
          else break;
        }
        LexNext(cc);
      }
    }
  }
  
  // Add to hash table
  HashAdd((CHashEntry*)tmpg, cc->hash_table);
  
  // Handle comma-separated declarations
  if (cc->lex.token == ',') {
    LexNext(cc);
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
    return false;
  }
  
  // Parse function name
  if (cc->lex.token != TK_IDENT) {
    Error(cc, "Expected function name");
    return false;
  }
  
  char *name = strdup(cc->lex.token_str);
  LexNext(cc);
  
  // Define function symbol
  Symbol *sym = SymbolDefine(cc, name, SYM_FUNCTION);
  sym->data_type = return_type;
  
  // Hash entry: one CHashFun per name (forward decl + definition share it); label lives on hash
  CHashFun *func_hash = (CHashFun *)HashFind(name, cc->hash_table, HTT_FUN);
  CLabel *func_label;
  if (func_hash) {
    func_label = func_hash->entry_label ? (CLabel *)func_hash->entry_label : LabelNew(cc, name);
    func_hash->entry_label = func_label;
  } else {
    func_hash = calloc(1, sizeof(CHashFun));
    if (!func_hash) {
      free(name);
      return false;
    }
    func_hash->str = strdup(name);
    if (!func_hash->str) {
      free(func_hash);
      free(name);
      return false;
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
  
  if (!LexExpect(cc, '(')) {
    free(name);
    return false;
  }
  
  // Track parameters for saving in prologue
  int param_count = 0;
  bool has_varargs = false;
  Symbol *first_param = NULL;  // Track first parameter to save them later
  
  if (cc->lex.token != ')') {
    // Check for varargs first
    if (cc->lex.token == TK_ELLIPSIS) {
      has_varargs = true;
      LexNext(cc);
      // Varargs must be last parameter
      if (cc->lex.token != ')') {
        Error(cc, "... must be last parameter");
        free(name);
        return false;
      }
    } else {
      do {
        // Check for ... in parameter list
        if (cc->lex.token == TK_ELLIPSIS) {
          has_varargs = true;
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
            return false;
          }

          if (cc->lex.token == '=') {
            free(fp_name);
            free(name);
            Error(cc, "Default values for function pointer parameters are not supported");
            return false;
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

          if (cc->lex.token == ',') {
            LexNext(cc);
          }
          continue;
        }
      if (cc->lex.token != TK_IDENT) {
        Error(cc, "Expected parameter name");
        free(name);
        return false;
      }
      
      char *param_name = strdup(cc->lex.token_str);
      LexNext(cc);
      
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
          return false;
        }
        // Arrays passed as pointers
        param_type = RT_I64;
        param_decl_class = NULL;
      }
      
      // Handle default parameter values
      bool has_default = false;
      I64 default_val = 0;
      
      if (cc->lex.token == '=') {
        LexNext(cc);
        
        // For now, only support constant defaults
        if (cc->lex.token == TK_I64) {
          has_default = true;
          default_val = cc->lex.token_i64;
          LexNext(cc);
        } else {
          // Complex default - skip for now
          int paren_depth = 0;
          while (cc->lex.token != ',' && cc->lex.token != ')' && cc->lex.token != TK_EOF) {
            if (cc->lex.token == '(') paren_depth++;
            if (cc->lex.token == ')' && paren_depth > 0) paren_depth--;
            else if (cc->lex.token == ')') break;
            LexNext(cc);
          }
        }
      }
      
      // Define parameter as local variable
      // ALL parameters go on stack (spilled in prologue)
      Symbol *param = SymbolDefine(cc, param_name, SYM_VAR);
      param->data_type = param_type;
      param->has_default = has_default;
      param->default_val = default_val;
      param->extra = param_decl_class;
      param->pointed_to_type = cc->last_pointed_to_type;

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
      
        if (cc->lex.token == ',') {
          LexNext(cc);
        }
      } while (cc->lex.token != ')' && cc->lex.token != TK_EOF && !has_varargs);
    }
  }
  
  cc->last_type_class = NULL;

  // Update hash entry with arg count
  func_hash->arg_cnt = param_count;
  
  if (!LexExpect(cc, ')')) {
    free(name);
    return false;
  }
  
  // Forward declaration: I64 F(...);
  if (cc->lex.token == ';') {
    LexNext(cc);
    free(name);
    return true;
  }
  
  // Fix parameter offsets now that we know total count
  // Frame layout: sp+0=locals, sp+16=param[0], sp+24=param[1], ...
  // S0 = sp + frame_size
  // param[i] saved at sp + 16 + i*8
  // From S0: param[i] at S0 - (frame_size - 16 - i*8)
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
    return false;
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
  
  // Fix local variable offsets: locals at sp + 16 + reg_param_cnt*8 + position
  Symbol *local_sym = cc->symtab->symbols;
  while (local_sym) {
    if (local_sym->type == SYM_VAR && local_sym->offset < -9000) {
      // This is a local (has temporary marker -(10000+position))
      I64 position_in_locals = -(local_sym->offset + 10000);
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
      return false;
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
      return false;
    }
    func_hash->exe_addr = (I64)compiled_code;
    cc->code_buffer = compiled_code;
    cc->code_size = code_size;
  }
  
  free(name);
  return true;
}


// ═══════════════════════════════════════════════════════════════
// PARSER - TOP LEVEL
// ═══════════════════════════════════════════════════════════════

bool ParseProgram(Compiler *cc) {
  // Top-level parsing - try to parse functions, skip everything else safely
  while (cc->lex.token != TK_EOF) {
    // Skip whitespace tokens
    while (cc->lex.token == ',' || cc->lex.token == ';') {
      LexNext(cc);
    }
    
    if (cc->lex.token == TK_EOF) break;
    
    // Handle modifiers and class definitions
    while (cc->lex.token == KW_PUBLIC || cc->lex.token == KW_CLASS || cc->lex.token == KW_UNION) {
      if (cc->lex.token == KW_CLASS || cc->lex.token == KW_UNION) {
        // Parse class definition
        if (!ParseClass(cc)) {
          // Failed - skip to recovery
          int depth = 0;
          while (cc->lex.token != TK_EOF) {
            if (cc->lex.token == '{') depth++;
            if (cc->lex.token == '}') {
              if (depth > 0) depth--;
              else { LexNext(cc); break; }
            }
            if (cc->lex.token == ';' && depth == 0) {
              LexNext(cc);
              break;
            }
            LexNext(cc);
          }
          cc->error = NULL;
        }
        continue;
      }
      LexNext(cc);  // Skip KW_PUBLIC
    }
    
    if (cc->lex.token == KW_ENUM) {
      if (!ParseEnum(cc)) {
        while (cc->lex.token != ';' && cc->lex.token != TK_EOF) {
          if (cc->lex.token == '{') {
            int depth = 1;
            LexNext(cc);
            while (depth > 0 && cc->lex.token != TK_EOF) {
              if (cc->lex.token == '{') depth++;
              else if (cc->lex.token == '}') depth--;
              LexNext(cc);
            }
          } else {
            LexNext(cc);
          }
        }
        if (cc->lex.token == ';') LexNext(cc);
        cc->error = NULL;
      }
      continue;
    }
    
    // Skip inline statements (strings, numbers)
    if (cc->lex.token == TK_STR || cc->lex.token == TK_I64 || cc->lex.token == TK_F64) {
      while (cc->lex.token != ';' && cc->lex.token != TK_EOF) {
        LexNext(cc);
      }
      if (cc->lex.token == ';') LexNext(cc);
      continue;
    }
    
    // Check for type (built-in or from hash table)
    bool is_type = false;
    if (cc->lex.token >= KW_I0 && cc->lex.token <= KW_F64) {
      is_type = true;
    } else if (cc->lex.token == TK_IDENT && cc->lex.hash_entry &&
               (cc->lex.hash_entry->type & (HTT_CLASS | HTT_INTERNAL_TYPE))) {
      is_type = true;
    }
    
    if (is_type) {
      // Use LexPush/LexPop to peek ahead and determine if function or global
      LexPush(cc);
      
      // Consume type name (built-in or typedef/class); global decl body not finished here.
      if (cc->lex.token >= KW_I0 && cc->lex.token <= KW_F64) {
        LexNext(cc);
      } else if (cc->lex.token == TK_IDENT && cc->lex.hash_entry) {
        LexNext(cc);
      }
      
      while (cc->lex.token == '*') {
        LexNext(cc);
      }

      bool is_function_pointer_decl = false;
      if (cc->lex.token == '(') {
        LexNext(cc);
        if (cc->lex.token == '*') {
          is_function_pointer_decl = true;
        }
      }

      if (is_function_pointer_decl) {
        LexPopRestore(cc);
        U8 ptr_type = ParseType(cc);
        if (!ParseGlobalFunctionPointerDeclList(cc, ptr_type)) {
          return false;
        }
        continue;
      }
      
      // Should be identifier now
      if (cc->lex.token != TK_IDENT) {
        LexPopNoRestore(cc);
        LexNext(cc);  // Skip unknown token
        continue;
      }
      
      char *name = strdup(cc->lex.token_str);
      LexNext(cc);
      
      // Check what follows to determine if function or global
      bool is_function = (cc->lex.token == '(');
      
      if (is_function) {
        // It's a function - restore and parse as function
        free(name);
        LexPopRestore(cc);
        
        if (!ParseFunction(cc)) {
          // Failed - skip to recovery point
          int depth = 0;
          bool found_recovery = false;
          while (cc->lex.token != TK_EOF && !found_recovery) {
            if (cc->lex.token == '{') depth++;
            else if (cc->lex.token == '}') {
              if (depth > 0) depth--;
              if (depth == 0) { LexNext(cc); found_recovery = true; }
            } else if (cc->lex.token == ';' && depth == 0) {
              LexNext(cc);
              found_recovery = true;
            }
            if (!found_recovery) LexNext(cc);
          }
          cc->error = NULL;
        }
      } else {
        free(name);
        LexPopNoRestore(cc);
      }
      
      continue;
    }
    
    // Unknown token - skip it
    LexNext(cc);
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



