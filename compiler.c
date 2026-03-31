/* HolyC→RISC-V Compiler - Main File
 * 
 * This file contains:
 * - Compiler initialization
 * - IC (Intermediate Code) management
 * - AOT/JIT code generation
 * - Main entry point
 */

#include "holyc_compiler.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef BARE_METAL
#include <sys/mman.h>
#else
// Bare metal stubs
#define PAGE_SIZE 4096
#define PROT_READ 1
#define PROT_WRITE 2
#define PROT_EXEC 4
#define MAP_PRIVATE 2
#define MAP_ANONYMOUS 0x20
#define MAP_FAILED ((void*)-1)
static inline void* mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    extern void* malloc(size_t size);
    (void)addr; (void)prot; (void)flags; (void)fd; (void)offset;
    return malloc(len);
}
static inline int munmap(void *addr, size_t len) {
    extern void free(void* ptr);
    (void)len;
    free(addr);
    return 0;
}
#endif

// ═══════════════════════════════════════════════════════════════
// COMPILER MANAGEMENT
// ═══════════════════════════════════════════════════════════════

Compiler *CompilerNew(const char *source, const char *filename) {
  Compiler *cc = calloc(1, sizeof(Compiler));
  
  // Initialize lexer
  cc->lex.src = strdup(source);
  cc->lex.ptr = cc->lex.src;
  cc->lex.line = 1;
  cc->lex.col = 1;
  cc->lex.filename = filename ? strdup(filename) : strdup("<source>");
  cc->lex.hash_entry = NULL;
  cc->lex.stack = NULL;  // Initialize lexer stack for LexPush/LexPop
  cc->lex.include_stack = NULL;  // Initialize include file stack
  
  // Initialize symbol table
  cc->symtab = calloc(1, sizeof(SymTable));
  
  // Initialize hash table (like original)
  cc->hash_table = HashTableNew(1024);
  
  // Initialize define table for #define macros
  cc->define_table = HashTableNew(256);
  
  // Preprocessor state
  cc->preprocessor_skip = false;
  cc->ifdef_depth = 0;
  
  // Add internal types (I0, U0, I8, U8, ..., F64, Bool)
  HashInitInternalTypes(cc->hash_table);
  
  // Add keywords to hash table (NOT types - types are already added)
  const struct { const char *name; int code; } keywords[] = {
    {"if", KW_IF}, {"else", KW_ELSE}, {"while", KW_WHILE},
    {"for", KW_FOR}, {"return", KW_RETURN}, {"break", KW_BREAK},
    {"class", KW_CLASS}, {"enum", KW_ENUM}, {"public", KW_PUBLIC},
    {"goto", KW_GOTO}, {"continue", KW_CONTINUE},
    {"switch", KW_SWITCH}, {"case", KW_CASE}, {"default", KW_DEFAULT},
    {"sizeof", KW_SIZEOF}, {"union", KW_UNION}, {"static", KW_STATIC},
    {"try", KW_TRY}, {"catch", KW_CATCH}, {"throw", KW_THROW},
    {"asm", KW_ASM},
  };
  for (unsigned i = 0; i < sizeof(keywords)/sizeof(keywords[0]); i++) {
    CHashKeyword *kw = HashKeywordNew(keywords[i].name, keywords[i].code);
    HashAdd((CHashEntry*)kw, cc->hash_table);
  }
  
  // IC list starts empty
  cc->ic_head = NULL;
  cc->ic_tail = NULL;
  
  // Labels
  cc->labels = NULL;
  cc->label_counter = 0;
  cc->current_function_entry_label = NULL;
  cc->defer_aot_compile = FALSE;
  cc->aot_fn_ic_head = NULL;
  cc->aot_fn_ic_tail = NULL;
  
  // Loop context
  cc->current_break_label = NULL;
  cc->current_continue_label = NULL;
  
  // Expression type tracking
  cc->last_var_symbol = NULL;
  cc->last_expr_class = NULL;
  cc->last_type_class = NULL;
  cc->last_global_var = NULL;
  cc->last_pointed_to_type = 0;
  
  // Compiler flags
  cc->flags = 0;
  
  // Locals
  cc->locals_size = 0;
  
  // Modes
  cc->aot_mode = true;
  cc->optimize = true;
  
  // Get first token
  LexNext(cc);
  
  return cc;
}

static void FreeDeferredFnICChunks(Compiler *cc) {
  AOTFnICChunk *n = cc->aot_fn_ic_head;
  while (n) {
    AOTFnICChunk *nx = n->next;
    free(n);
    n = nx;
  }
  cc->aot_fn_ic_head = cc->aot_fn_ic_tail = NULL;
}

void CompilerFree(Compiler *cc) {
  if (!cc) return;
  
  // Free lexer
  if (cc->lex.src) free(cc->lex.src);
  if (cc->lex.filename) free((void*)cc->lex.filename);
  if (cc->lex.token_str) free(cc->lex.token_str);
  
  // Free symbol table (TODO: proper cleanup)
  free(cc->symtab);
  
  // Free IC list
  CIntermediateCode *ic = cc->ic_head;
  while (ic) {
    CIntermediateCode *next = ic->next;
    free(ic);
    ic = next;
  }
  
  FreeDeferredFnICChunks(cc);
  
  // Free code buffer if allocated
  if (cc->code_buffer) free(cc->code_buffer);
  
  free(cc);
}

// ═══════════════════════════════════════════════════════════════
// RISC-V INSTRUCTION ENCODING
// ═══════════════════════════════════════════════════════════════

// Minimal RISC-V backend integration
// (Full backend is in Back*_RV.HC, this is simplified version)

// RISC-V register definitions
#define RV_ZERO 0
#define RV_RA   1
#define RV_SP   2
#define RV_T0   5
#define RV_T1   6
#define RV_T2   7
#define RV_S0   8
#define RV_A0   10
#define RV_A1   11
#define RV_A2   12
#define RV_A3   13
#define RV_A4   14
#define RV_A5   15
#define RV_A6   16
#define RV_A7   17

// ═══════════════════════════════════════════════════════════════
// UNIFIED EMIT FUNCTIONS (TempleOS ICU8/ICU16/ICU32 pattern)
// ═══════════════════════════════════════════════════════════════

// These functions work in two modes:
// - If buf==NULL: only count bytes (for sizing passes)
// - If buf!=NULL: emit bytes and count (for final emission pass)

static void RVU32(U8 *buf, U8 **ptr, I64 *rip, U32 val) {
  if (buf && ptr) {
    *(U32*)(*ptr) = val;
    (*ptr) += 4;
  }
  (*rip) += 4;
}

/* IC_DEREF: load *rs1 into a0; width from arg1_type_pointed_to (U32* → lwu, not ld). */
static U32 DerefLoadFromRs1(U8 pointed_to, U8 rs1) {
  switch (pointed_to) {
  case RT_I8:
    return 0x03 | (RV_A0 << 7) | (0 << 12) | (rs1 << 15); /* lb */
  case RT_U8:
    return 0x03 | (RV_A0 << 7) | (4 << 12) | (rs1 << 15); /* lbu */
  case RT_I16:
    return 0x03 | (RV_A0 << 7) | (1 << 12) | (rs1 << 15); /* lh */
  case RT_U16:
    return 0x03 | (RV_A0 << 7) | (5 << 12) | (rs1 << 15); /* lhu */
  case RT_I32:
    return 0x03 | (RV_A0 << 7) | (2 << 12) | (rs1 << 15); /* lw */
  case RT_U32:
    return 0x03 | (RV_A0 << 7) | (6 << 12) | (rs1 << 15); /* lwu */
  default:
    return 0x03 | (RV_A0 << 7) | (3 << 12) | (rs1 << 15); /* ld */
  }
}

// PC-relative call: jal rd, target (or auipc+jalr if out of ±1 MiB range)
static void EmitJalToLabel(U8 *pass_buf, U8 **pass_ptr, I64 *rip, CLabel *lb, U8 rd) {
  I64 offset = lb->addr - *rip;
  if (offset >= -(1 << 20) && offset < (1 << 20) && ((offset & 1) == 0)) {
    U32 imm_20 = (U32)(offset >> 20) & 1u;
    U32 imm_10_1 = (U32)(offset >> 1) & 0x3FFu;
    U32 imm_11 = (U32)(offset >> 11) & 1u;
    U32 imm_19_12 = (U32)(offset >> 12) & 0xFFu;
    RVU32(pass_buf, pass_ptr, rip,
          0x6Fu | ((U32)rd << 7) | (imm_19_12 << 12) | (imm_11 << 20) | (imm_10_1 << 21) | (imm_20 << 31));
  } else {
    I64 pc = *rip;
    I64 target = lb->addr;
    I64 rel = target - pc;
    I64 hi = (rel + 0x800) >> 12;
    I64 lo = rel - (hi << 12);
    RVU32(pass_buf, pass_ptr, rip, 0x17u | ((U32)rd << 7) | (((U32)hi & 0xFFFFFu) << 12));
    RVU32(pass_buf, pass_ptr, rip,
          0x67u | ((U32)rd << 7) | ((U32)rd << 15) | (((U32)lo & 0xFFFu) << 20));
  }
}

// Eval stack: arg1 pushed first … argN at sp (N<=8). RISC-V: a0=arg1 … a_{N-1}=argN.
static void EmitLoadArgsFromEvalStack(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth,
                                      I64 arg_count) {
  if (arg_count < 2 || arg_count > 8) return;
  for (I64 k = 0; k < arg_count; k++) {
    U8 reg = RV_A0 + (U8)k;
    I64 offset = (arg_count - 1 - k) * 8;
    RVU32(pass_buf, pass_ptr, rip,
          0x03 | (reg << 7) | (3 << 12) | (RV_SP << 15) | ((offset & 0xFFF) << 20));
  }
  I64 cleanup = arg_count * 8;
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | ((cleanup & 0xFFF) << 20));
  *stack_depth -= arg_count;
}

// N>8: eval stack has arg1..argN (argN at sp). Load a0..a7; lay out stack args so arg9 is at 0(sp), arg10 at 8(sp), … (matches parser IC_ENTER stack-param offsets).
static void EmitPrepareGt8CallArgs(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 N) {
  if (N <= 8) return;
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T2 << 7) | (RV_SP << 15)); // mv t2, sp
  for (I64 k = 0; k < 8; k++) {
    U8 reg = RV_A0 + (U8)k;
    I64 offset = (N - 1 - k) * 8;
    RVU32(pass_buf, pass_ptr, rip,
          0x03 | (reg << 7) | (3 << 12) | (RV_T2 << 15) | ((offset & 0xFFF) << 20));
  }
  I64 out_sz = (N - 8) * 8;
  RVU32(pass_buf, pass_ptr, rip,
        0x13 | (RV_SP << 7) | (RV_SP << 15) | (((-out_sz) & 0xFFF) << 20)); // addi sp, sp, -out_sz
  for (I64 j = 9; j <= N; j++) {
    I64 src = (N - j) * 8;
    I64 dst = (j - 9) * 8;
    RVU32(pass_buf, pass_ptr, rip,
          0x03 | (RV_T0 << 7) | (3 << 12) | (RV_T2 << 15) | ((src & 0xFFF) << 20));
    RVU32(pass_buf, pass_ptr, rip,
          0x23 | ((dst & 0x1F) << 7) | (3 << 12) | (RV_SP << 15) | (RV_T0 << 20) | ((dst >> 5) << 25));
  }
}

// Shared: argument shuffle for IC_CALL / IC_CALL_INDIRECT2, then PC-rel or host-indirect tail.
static void EmitCallArgsAndInvoke(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth,
                                  Compiler *cc, CLabel *pc_target, I64 *exe_addr_host_ptr) {
  I64 arg_count = cc->last_call_arg_cnt;

  if (arg_count > 8) {
    EmitPrepareGt8CallArgs(pass_buf, pass_ptr, rip, arg_count);
  } else if (arg_count >= 2 && arg_count <= 8) {
    EmitLoadArgsFromEvalStack(pass_buf, pass_ptr, rip, stack_depth, arg_count);
  } else if (arg_count == 1) {
    // IC_IMM_I64 leaves a duplicate on the eval stack; arg is already in a0 — drop slot only.
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    (*stack_depth)--;
  }

  if (pc_target) {
    EmitJalToLabel(pass_buf, pass_ptr, rip, pc_target, RV_RA);
  } else {
    I64 addr = (I64)exe_addr_host_ptr;
    U32 hi = (U32)((addr >> 12) & 0xFFFFF);
    RVU32(pass_buf, pass_ptr, rip, 0x37 | (RV_T0 << 7) | (hi << 12));
    I64 lo = addr & 0xFFF;
    if (lo) {
      RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (RV_T0 << 15) | ((lo & 0xFFF) << 20));
    }
    if (addr & 0x80000000) {
      RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (1 << 12) | (RV_T0 << 15) | (32 << 20));
      RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (5 << 12) | (RV_T0 << 15) | (32 << 20));
    }
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_T0 << 15));
    RVU32(pass_buf, pass_ptr, rip, 0x67 | (RV_RA << 7) | (RV_T0 << 15));
  }

  if (arg_count > 8) {
    I64 out_sz = (arg_count - 8) * 8;
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | ((out_sz & 0xFFF) << 20));
    I64 eval_sz = arg_count * 8;
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | ((eval_sz & 0xFFF) << 20));
    *stack_depth -= arg_count;
  }

  // Return value is in a0; match the virtual eval stack (IC_RETURN_VAL / binary ops pop from sp).
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (3 << 12));
  (*stack_depth)++;
}

// ═══════════════════════════════════════════════════════════════
// IC GENERATION
// ═══════════════════════════════════════════════════════════════

void ICAdd(Compiler *cc, U8 opcode, I64 data, U8 type) {
  CIntermediateCode *ic = ICNew(cc, opcode);
  if (!ic) return;  // Allocation failed, skip
  
  ic->ic_data = data;
  ic->res.type.raw_type = type;
  ic->res.type.mode = MDF_STK;  // Default: stack-based
  
  // Link into IC chain (TempleOS does this in ICAdd, not ICNew)
  ic->last = cc->ic_tail;
  ic->next = NULL;
  
  if (cc->ic_tail) {
    cc->ic_tail->next = ic;
            } else {
    cc->ic_head = ic;
  }
  cc->ic_tail = ic;
}

// ═══════════════════════════════════════════════════════════════
// CODE GENERATION (AOT)
// ═══════════════════════════════════════════════════════════════

U8 *CompileAOT(Compiler *cc, I64 *code_size) {
  // Check if this is a function or expression
  CIntermediateCode *ic = cc->ic_head;
  Bool is_function = false;
  Bool has_call = false;
  while (ic) {
    if (ic->ic_code == IC_ENTER) is_function = true;
    if (ic->ic_code == IC_CALL || ic->ic_code == IC_CALL_INDIRECT || ic->ic_code == IC_CALL_INDIRECT2) has_call = true;
    ic = ic->next;
  }
  // Multi-pass until convergence (TempleOS OptPass789A.HC approach).
  // Sizing uses pass_buf == NULL so rip is the true code size. Do not malloc
  // from IC_count*16 — IC_ENTER and friends emit many words per IC; a small
  // buffer corrupts the heap and truncates the guest blob.
  I64 prev_size = 0;
  I64 rip = 0;
  int pass = 0;
  U8 *pass_buf = NULL;
  U8 *pass_ptr = NULL;

  do {
    prev_size = rip;
    rip = 0;
    pass++;

    ic = cc->ic_head;
    I64 stack_depth_pass = 0;
    pass_ptr = NULL;

    pass_buf = NULL;
    
    // Add prologue for expressions with calls
    if (has_call && !is_function) {
      RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF0<<20)); // addi sp, sp, -16
      RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (8<<7) | (3<<12) | (RV_SP<<15) | (RV_RA<<20)); // sd ra, 8(sp)
      RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (0<<7) | (3<<12) | (RV_SP<<15) | (RV_S0<<20)); // sd s0, 0(sp)
      RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_S0<<7) | (RV_SP<<15) | (16<<20)); // addi s0, sp, 16
    }
    
    while (ic) {
      // Set label addresses
      if (ic->ic_code == IC_LABEL) {
        CLabel *lb = (CLabel*)ic->ic_data;
        lb->addr = rip;
      }
      
      // Use SAME logic for sizing and emission (TempleOS 1:1)
      switch (ic->ic_code) {
      case IC_ENTER:
        {
          I64 param_cnt = ic->ic_data & 0xFFFFFFFF;
          I64 locals_size = ic->ic_data >> 32;
          I64 reg_param_cnt = param_cnt > 8 ? 8 : param_cnt; // Only first 8 in frame
          I64 param_size = reg_param_cnt * 8;
          I64 frame_size = 16 + param_size + locals_size;
          
          // addi sp, sp, -frame_size
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((-frame_size & 0xFFF)<<20));
          // sd ra, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (3<<12) | (RV_SP<<15) | (RV_RA<<20));
          // sd s0, 8(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (8<<7) | (3<<12) | (RV_SP<<15) | (RV_S0<<20));
          // addi s0, sp, frame_size
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_S0<<7) | (RV_SP<<15) | ((frame_size & 0xFFF)<<20));
          
          // Save register parameters (only first 8, args 9+ stay on original stack)
          for (I64 i = 0; i < reg_param_cnt; i++) {
            // sd aX, (16+i*8)(sp)
            U8 reg = RV_A0 + i;
            I64 offset = 16 + i * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x23 | ((offset & 0x1F)<<7) | (3<<12) | (RV_SP<<15) | (reg<<20) | ((offset>>5)<<25));
          }
        }
        break;
      case IC_LEAVE:
        {
          I64 param_cnt_leave = ic->ic_data & 0xFFFFFFFF;
          I64 locals_size_leave = ic->ic_data >> 32;
          I64 reg_param_cnt_leave = param_cnt_leave > 8 ? 8 : param_cnt_leave;
          I64 frame_size_leave = 16 + (reg_param_cnt_leave * 8) + locals_size_leave;
          
          // ld ra, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_RA<<7) | (3<<12) | (RV_SP<<15));
          // ld s0, 8(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_S0<<7) | (3<<12) | (RV_SP<<15) | (8<<20));
          // addi sp, sp, frame_size
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((frame_size_leave & 0xFFF)<<20));
          // ret (jalr x0, 0(ra))
          RVU32(pass_buf, &pass_ptr, &rip, 0x67 | (RV_RA<<15));
        }
        break;
      case IC_RBP:
        if (stack_depth_pass > 0) {
          // addi sp, sp, -8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          // sd a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        }
        // mv a0, s0 (addi a0, s0, 0)
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_S0<<15));
        stack_depth_pass++;
        break;
      case IC_LEA:
        // Load Effective Address: addi a0, s0, offset
        // Don't push - IC_PUSH_ARG handles it for assignments, IC_DEREF handles it for loads
        {
          I64 offset = ic->ic_data;
          if (offset >= -2048 && offset <= 2047) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_S0<<15) | ((offset & 0xFFF)<<20)); // addi a0, s0, offset
          } else {
            // Large offset: LUI + ADDI
            I64 hi = (offset + 0x800) >> 12;
            I64 lo = offset & 0xFFF;
            if (lo & 0x800) lo |= 0xFFFFFFFFFFFFF000LL;
            RVU32(pass_buf, &pass_ptr, &rip, 0x37 | (RV_A0<<7) | ((hi & 0xFFFFF)<<12));
            if (lo) {
              RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_A0<<15) | ((lo & 0xFFF)<<20));
            }
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_A0<<15) | (RV_S0<<20)); // add a0, a0, s0
          }
        }
        // Don't push here - IC_PUSH_ARG will handle it for assignments, IC_DEREF handles it for loads
        break;
        
      case IC_IMM_I64:
        // Load immediate into a0
        if (ic->ic_data >= -2048 && ic->ic_data <= 2047) {
          // addi a0, zero, imm
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | ((ic->ic_data & 0xFFF)<<20));
        } else {
          // LUI + ADDI for large values
          I64 hi = (ic->ic_data + 0x800) >> 12;
          I64 lo = ic->ic_data & 0xFFF;
          if (lo & 0x800) lo |= 0xFFFFFFFFFFFFF000LL;
          RVU32(pass_buf, &pass_ptr, &rip, 0x37 | (RV_A0<<7) | ((hi & 0xFFFFF)<<12));
          if (lo) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_A0<<15) | ((lo & 0xFFF)<<20));
          }
        }
        // Push value to stack so binary ops find it
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12)); // sd a0, 0(sp)
        stack_depth_pass++;
        break;
      case IC_ADD:
      case IC_SUB:
      case IC_MUL:
      case IC_DIV:
      case IC_MOD:
        if (stack_depth_pass >= 2) {
          // Pop right operand into t1
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_pass--;
          // Pop left operand into t0
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_pass--;
          // Compute result (result stays in a0)
          if (ic->ic_code == IC_ADD) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_T1<<20));
          } else if (ic->ic_code == IC_SUB) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25));
          } else if (ic->ic_code == IC_MUL) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_T1<<20) | (1<<25));
          } else if (ic->ic_code == IC_DIV) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (4<<12) | (RV_T0<<15) | (RV_T1<<20) | (1<<25));
          } else if (ic->ic_code == IC_MOD) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (6<<12) | (RV_T0<<15) | (RV_T1<<20) | (1<<25));
          }
          // Push result back
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_pass++;
        }
        break;
      case IC_AND:
      case IC_OR:
      case IC_XOR:
      case IC_SHL:
      case IC_SHR:
        if (stack_depth_pass == 1) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12)); // sd a0, 0(sp)
          stack_depth_pass++;
        }
        if (stack_depth_pass >= 2) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_pass--;
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_pass--;
          U32 inst = 0;
          if (ic->ic_code == IC_AND) {
            inst = 0x33 | (RV_A0<<7) | (0x7<<12) | (RV_T0<<15) | (RV_T1<<20);
          } else if (ic->ic_code == IC_OR) {
            inst = 0x33 | (RV_A0<<7) | (0x6<<12) | (RV_T0<<15) | (RV_T1<<20);
          } else if (ic->ic_code == IC_XOR) {
            inst = 0x33 | (RV_A0<<7) | (0x4<<12) | (RV_T0<<15) | (RV_T1<<20);
          } else if (ic->ic_code == IC_SHL) {
            inst = 0x33 | (RV_A0<<7) | (0x1<<12) | (RV_T0<<15) | (RV_T1<<20);
          } else if (ic->ic_code == IC_SHR) {
            inst = 0x33 | (RV_A0<<7) | (0x5<<12) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25);
          }
          if (inst) {
            RVU32(pass_buf, &pass_ptr, &rip, inst);
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
            RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
            stack_depth_pass++;
          }
        }
        break;
      case IC_EVAL_DROP:
        {
          I64 adj = ic->ic_data;
          if (adj != 0) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((adj & 0xFFF)<<20));
            if (adj > 0)
              stack_depth_pass -= adj / 8;
            else
              stack_depth_pass += (-adj) / 8;
          }
        }
        break;
      case IC_DEREF:
        RVU32(pass_buf, &pass_ptr, &rip, DerefLoadFromRs1(ic->arg1_type_pointed_to, RV_A0));
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12)); // sd a0, 0(sp)
        stack_depth_pass++;
        break;
      case IC_ASSIGN:
        if (stack_depth_pass >= 1) {
          // If both value and address are on the stack, pop value first and move to a0
          if (stack_depth_pass >= 2) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15)); // ld t1, 0(sp) - pop value
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
            stack_depth_pass--;
            // Move value from t1 into a0 (mv a0, t1)
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_T1<<15));
          }

          // Pop address into t0
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_pass--;

          // Store value (in a0) to address (in t0)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_T0<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_pass = 0;
        } else {
          // Fallback: no address on stack, assume address currently in a0
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (RV_A0<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_T0<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_pass = 0;
        }
        break;
      case IC_PUSH_ARG:
        // Push argument to stack (don't clear a0 - let IC_IMM_I64 handle it)
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (0<<7) | (3<<12) | (RV_SP<<15) | (RV_A0<<20) | (0<<25)); // sd a0, 0(sp)
        stack_depth_pass++;
        break;
      case IC_POP_ARG:
        // Pop argument from stack
        RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15) | (0<<20)); // ld a0, 0(sp)
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
        stack_depth_pass--;
        break;
      case IC_LESS:
      case IC_GREATER:
      case IC_LESS_EQU:
      case IC_GREATER_EQU:
      case IC_EQU_EQU:
      case IC_NOT_EQU:
        if (stack_depth_pass == 1) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_pass++;
        }
        if (stack_depth_pass >= 2) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_pass--;
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_pass--;
          if (ic->ic_code == IC_LESS) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T0<<15) | (RV_T1<<20));
          } else if (ic->ic_code == IC_GREATER) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T1<<15) | (RV_T0<<20));
          } else if (ic->ic_code == IC_LESS_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T1<<15) | (RV_T0<<20));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20));
          } else if (ic->ic_code == IC_GREATER_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T0<<15) | (RV_T1<<20));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20));
          } else if (ic->ic_code == IC_EQU_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x0<<12) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (3<<12) | (RV_A0<<15) | (1<<20));
          } else if (ic->ic_code == IC_NOT_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x0<<12) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25));
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x3<<12) | (RV_ZERO<<15) | (RV_A0<<20));
          }
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_pass++;
        }
        break;
      case IC_BR_ZERO:
        {
          if (stack_depth_pass > 0) {
            // Pop value from stack into a0
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
            stack_depth_pass--;
          }

          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - rip;
          // beq a0, zero, offset
          U32 imm_12 = (offset >> 12) & 0x1;
          U32 imm_10_5 = (offset >> 5) & 0x3F;
          U32 imm_4_1 = (offset >> 1) & 0xF;
          U32 imm_11 = (offset >> 11) & 0x1;
          RVU32(pass_buf, &pass_ptr, &rip, 0x63 | (imm_11<<7) | (imm_4_1<<8) | (RV_A0<<15) | (RV_ZERO<<20) | (imm_10_5<<25) | (imm_12<<31));
          stack_depth_pass = 0;
        }
        break;
      case IC_BR_NOT_ZERO:
        {
          if (stack_depth_pass > 0) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
            stack_depth_pass--;
          }

          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - rip;
          // bne a0, zero, offset
          U32 imm_12 = (offset >> 12) & 0x1;
          U32 imm_10_5 = (offset >> 5) & 0x3F;
          U32 imm_4_1 = (offset >> 1) & 0xF;
          U32 imm_11 = (offset >> 11) & 0x1;
          RVU32(pass_buf, &pass_ptr, &rip, 0x63 | (1<<12) | (imm_11<<7) | (imm_4_1<<8) | (RV_A0<<15) | (RV_ZERO<<20) | (imm_10_5<<25) | (imm_12<<31));
          stack_depth_pass = 0;
        }
        break;
      case IC_JMP:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - rip;
          // jal zero, offset
          U32 imm_20 = (offset >> 20) & 0x1;
          U32 imm_10_1 = (offset >> 1) & 0x3FF;
          U32 imm_11 = (offset >> 11) & 0x1;
          U32 imm_19_12 = (offset >> 12) & 0xFF;
          RVU32(pass_buf, &pass_ptr, &rip, 0x6F | (imm_19_12<<12) | (imm_11<<20) | (imm_10_1<<21) | (imm_20<<31));
          // Jump targets (like loop starts or epilogue) should have clean stack
          // Reset stack depth to 0 at jump targets (don't adjust sp - epilogue expects it at frame_base)
          stack_depth_pass = 0;
        }
        break;
      case IC_MOV:
        // Load from parameter or local variable
        // For now, handles simple register loads and stack loads
        if (stack_depth_pass > 0) {
          // addi sp, sp, -8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          // sd a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        }
        // ld a0, offset(s0) - simplified, actual depends on ic_data
        RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_S0<<15) | ((ic->ic_data & 0xFFF)<<20));
        stack_depth_pass++;
        break;
      case IC_CALL_INDIRECT:
        {
          I64 arg_count = cc->last_call_arg_cnt;

          // Pop pointer to exe_addr field into t1 (t0/t2 used by arg shuffle)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_pass--;

          if (arg_count > 8) {
            EmitPrepareGt8CallArgs(pass_buf, &pass_ptr, &rip, arg_count);
          } else if (arg_count >= 2 && arg_count <= 8) {
            EmitLoadArgsFromEvalStack(pass_buf, &pass_ptr, &rip, &stack_depth_pass, arg_count);
          } else if (arg_count == 1) {
            stack_depth_pass--;
          }

          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_T1<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x67 | (RV_RA<<7) | (RV_T0<<15));

          if (arg_count > 8) {
            I64 out_sz = (arg_count - 8) * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((out_sz & 0xFFF)<<20));
            I64 eval_sz = arg_count * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((eval_sz & 0xFFF)<<20));
            stack_depth_pass -= arg_count;
          }

          stack_depth_pass++;
        }
        break;
      case IC_CALL_INDIRECT2:
        EmitCallArgsAndInvoke(pass_buf, &pass_ptr, &rip, &stack_depth_pass, cc, NULL, (I64 *)ic->ic_data);
        break;
      case IC_CALL:
        EmitCallArgsAndInvoke(pass_buf, &pass_ptr, &rip, &stack_depth_pass, cc, (CLabel *)ic->ic_data, NULL);
        break;
      case IC_END_EXP:
        stack_depth_pass = 0;
        break;
      case IC_PUSH_RES:
        // Push result to stack - this is just a marker, doesn't change stack_depth
        break;
      case IC_CALL_START:
      case IC_CALL_END:
        // Markers for function call boundaries
        break;
      case IC_LABEL:
        break;
      case IC_NOP1:
      case IC_NOP2:
        // Explicit no-op – leave stack depth unchanged
        break;
      case IC_RETURN_VAL:
      case IC_RETURN_VAL2:
        // Return value should be in a0
        // If it's on the stack, pop it to a0
        if (stack_depth_pass > 0) {
          // Pop value from stack to a0
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15)); // ld a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
          stack_depth_pass--;
        }
        // Value is now in a0, ready for return
        // Do NOT adjust sp further - the epilogue expects sp at frame_base
        stack_depth_pass = 0;
        break;
      case IC_RET:
        // Generate ret instruction with epilogue for expressions
        if (!is_function) {
          if (has_call) {
            // Epilogue: restore ra/s0
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_RA<<7) | (3<<12) | (RV_SP<<15) | (8<<20)); // ld ra, 8(sp)
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_S0<<7) | (3<<12) | (RV_SP<<15)); // ld s0, 0(sp)
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (16<<20)); // addi sp, sp, 16
          }
          RVU32(pass_buf, &pass_ptr, &rip, 0x00008067); // ret
        }
        break;
      default:
        // Skip unimplemented ICs
        break;
    }
    
    ic = ic->next;
  }
  
  } while (rip != prev_size && pass < 10);  // Iterate until convergence

  I64 buf_sz = rip + 256;
  if (buf_sz < 64) buf_sz = 64;
  U8 *buffer = malloc((size_t)buf_sz);
  if (!buffer) return NULL;

  // After convergence, do one final pass with emission enabled
  if (pass_buf == NULL) {
  pass_buf = buffer;
  pass_ptr = buffer;
  rip = 0;
  ic = cc->ic_head;
  I64 stack_depth_final = 0;
    
    // Add prologue for expressions with calls (same as in multi-pass loop)
    if (has_call && !is_function) {
      RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF0<<20)); // addi sp, sp, -16
      RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (8<<7) | (3<<12) | (RV_SP<<15) | (RV_RA<<20)); // sd ra, 8(sp)
      RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (0<<7) | (3<<12) | (RV_SP<<15) | (RV_S0<<20)); // sd s0, 0(sp)
      RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_S0<<7) | (RV_SP<<15) | (16<<20)); // addi s0, sp, 16
    }
    
    while (ic) {
      // Same unified switch, but now with pass_buf = buffer
      switch (ic->ic_code) {
      case IC_ENTER:
        {
          I64 param_cnt = ic->ic_data & 0xFFFFFFFF;
          I64 locals_size = ic->ic_data >> 32;
          I64 reg_param_cnt = param_cnt > 8 ? 8 : param_cnt; // Only first 8 in frame
          I64 param_size = reg_param_cnt * 8;
          I64 frame_size = 16 + param_size + locals_size;
          
          // addi sp, sp, -frame_size
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((-frame_size & 0xFFF)<<20));
          // sd ra, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (3<<12) | (RV_SP<<15) | (RV_RA<<20));
          // sd s0, 8(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (8<<7) | (3<<12) | (RV_SP<<15) | (RV_S0<<20));
          // addi s0, sp, frame_size
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_S0<<7) | (RV_SP<<15) | ((frame_size & 0xFFF)<<20));
          
          // Save register parameters (only first 8, args 9+ stay on original stack)
          for (I64 i = 0; i < reg_param_cnt; i++) {
            U8 reg = RV_A0 + i;
            I64 offset = 16 + i * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x23 | ((offset & 0x1F)<<7) | (3<<12) | (RV_SP<<15) | (reg<<20) | ((offset>>5)<<25));
          }
        }
        break;
      case IC_LEAVE:
        {
          I64 param_cnt_leave = ic->ic_data & 0xFFFFFFFF;
          I64 locals_size_leave = ic->ic_data >> 32;
          I64 reg_param_cnt_leave = param_cnt_leave > 8 ? 8 : param_cnt_leave;
          I64 frame_size_leave = 16 + (reg_param_cnt_leave * 8) + locals_size_leave;
          
          // ld ra, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_RA<<7) | (3<<12) | (RV_SP<<15));
          // ld s0, 8(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_S0<<7) | (3<<12) | (RV_SP<<15) | (8<<20));
          // addi sp, sp, frame_size
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((frame_size_leave & 0xFFF)<<20));
          // ret (jalr x0, 0(ra))
          RVU32(pass_buf, &pass_ptr, &rip, 0x67 | (RV_RA<<15));
        }
        break;
        
      case IC_RBP:
        if (stack_depth_final > 0) {
          // addi sp, sp, -8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          // sd a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        }
        // mv a0, s0 (addi a0, s0, 0)
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_S0<<15));
        stack_depth_final++;
        break;
        
      case IC_LEA:
        // Load Effective Address: addi a0, s0, offset
        // Don't push - IC_PUSH_ARG handles it for assignments, IC_DEREF handles it for loads
        {
          I64 offset = ic->ic_data;
          if (offset >= -2048 && offset <= 2047) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_S0<<15) | ((offset & 0xFFF)<<20)); // addi a0, s0, offset
          } else {
            // Large offset: LUI + ADDI
            I64 hi = (offset + 0x800) >> 12;
            I64 lo = offset & 0xFFF;
            if (lo & 0x800) lo |= 0xFFFFFFFFFFFFF000LL;
            RVU32(pass_buf, &pass_ptr, &rip, 0x37 | (RV_A0<<7) | ((hi & 0xFFFFF)<<12));
            if (lo) {
              RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_A0<<15) | ((lo & 0xFFF)<<20));
            }
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_A0<<15) | (RV_S0<<20)); // add a0, a0, s0
          }
        }
        // Don't push here - IC_PUSH_ARG will handle it for assignments, IC_DEREF handles it for loads
        break;
        
      case IC_IMM_I64:
        // Load immediate into a0
        if (ic->ic_data >= -2048 && ic->ic_data <= 2047) {
          // addi a0, zero, imm
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | ((ic->ic_data & 0xFFF)<<20));
        } else {
          // LUI + ADDI for large values
          I64 hi = (ic->ic_data + 0x800) >> 12;
          I64 lo = ic->ic_data & 0xFFF;
          if (lo & 0x800) lo |= 0xFFFFFFFFFFFFF000LL;
          RVU32(pass_buf, &pass_ptr, &rip, 0x37 | (RV_A0<<7) | ((hi & 0xFFFFF)<<12));
          if (lo) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_A0<<15) | ((lo & 0xFFF)<<20));
          }
        }
        // Push value to stack so binary ops find it
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12)); // sd a0, 0(sp)
        stack_depth_final++;
        break;
        
      case IC_ADD:
      case IC_SUB:
      case IC_MUL:
      case IC_DIV:
      case IC_MOD:
        if (stack_depth_final >= 2) {
          // Pop right operand into t1
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_final--;
          // Pop left operand into t0
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_final--;
          // Compute result (result stays in a0)
          if (ic->ic_code == IC_ADD) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_T1<<20));
          } else if (ic->ic_code == IC_SUB) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25));
          } else if (ic->ic_code == IC_MUL) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_T1<<20) | (1<<25));
          } else if (ic->ic_code == IC_DIV) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (4<<12) | (RV_T0<<15) | (RV_T1<<20) | (1<<25));
          } else if (ic->ic_code == IC_MOD) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (6<<12) | (RV_T0<<15) | (RV_T1<<20) | (1<<25));
          }
          // Push result back
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final++;
        }
        break;
      case IC_AND:
      case IC_OR:
      case IC_XOR:
      case IC_SHL:
      case IC_SHR:
        if (stack_depth_final == 1) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final++;
        }
        if (stack_depth_final >= 2) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_final--;
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_final--;
          U32 inst = 0;
          if (ic->ic_code == IC_AND) {
            inst = 0x33 | (RV_A0<<7) | (0x7<<12) | (RV_T0<<15) | (RV_T1<<20);
          } else if (ic->ic_code == IC_OR) {
            inst = 0x33 | (RV_A0<<7) | (0x6<<12) | (RV_T0<<15) | (RV_T1<<20);
          } else if (ic->ic_code == IC_XOR) {
            inst = 0x33 | (RV_A0<<7) | (0x4<<12) | (RV_T0<<15) | (RV_T1<<20);
          } else if (ic->ic_code == IC_SHL) {
            inst = 0x33 | (RV_A0<<7) | (0x1<<12) | (RV_T0<<15) | (RV_T1<<20);
          } else if (ic->ic_code == IC_SHR) {
            inst = 0x33 | (RV_A0<<7) | (0x5<<12) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25);
          }
          if (inst) {
            RVU32(pass_buf, &pass_ptr, &rip, inst);
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
            RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
            stack_depth_final++;
          }
        }
        break;
        
      case IC_EVAL_DROP:
        {
          I64 adj = ic->ic_data;
          if (adj != 0) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((adj & 0xFFF)<<20));
            if (adj > 0)
              stack_depth_final -= adj / 8;
            else
              stack_depth_final += (-adj) / 8;
          }
        }
        break;
      case IC_DEREF:
        RVU32(pass_buf, &pass_ptr, &rip, DerefLoadFromRs1(ic->arg1_type_pointed_to, RV_A0));
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12)); // sd a0, 0(sp)
        stack_depth_final++;
        break;
      case IC_ASSIGN:
        if (stack_depth_final >= 1) {
          if (stack_depth_final >= 2) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15)); // ld t1, 0(sp) - pop value
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
            stack_depth_final--;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_T1<<15)); // mv a0, t1
          }

          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_final--;

          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_T0<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final = 0;
        } else {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (RV_A0<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_T0<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final = 0;
        }
        break;
      case IC_PUSH_ARG:
        // Push argument to stack (don't clear a0 - let IC_IMM_I64 handle it)
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (0<<7) | (3<<12) | (RV_SP<<15) | (RV_A0<<20) | (0<<25)); // sd a0, 0(sp)
        stack_depth_final++;
        break;
      case IC_POP_ARG:
        // Pop argument from stack
        RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15) | (0<<20)); // ld a0, 0(sp)
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
        stack_depth_final--;
        break;
      case IC_LESS:
      case IC_GREATER:
      case IC_LESS_EQU:
      case IC_GREATER_EQU:
      case IC_EQU_EQU:
      case IC_NOT_EQU:
        if (stack_depth_final == 1) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final++;
        }
        if (stack_depth_final >= 2) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_final--;
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_final--;
          if (ic->ic_code == IC_LESS) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T0<<15) | (RV_T1<<20));
          } else if (ic->ic_code == IC_GREATER) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T1<<15) | (RV_T0<<20));
          } else if (ic->ic_code == IC_LESS_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T1<<15) | (RV_T0<<20));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20));
          } else if (ic->ic_code == IC_GREATER_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T0<<15) | (RV_T1<<20));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20));
          } else if (ic->ic_code == IC_EQU_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x0<<12) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (3<<12) | (RV_A0<<15) | (1<<20));
          } else if (ic->ic_code == IC_NOT_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x0<<12) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25));
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (0x3<<12) | (RV_ZERO<<15) | (RV_A0<<20));
          }
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final++;
        }
        break;
      case IC_BR_ZERO:
        {
          if (stack_depth_final > 0) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
            stack_depth_final--;
          }

          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - rip;
          // beq a0, zero, offset
          U32 imm_12 = (offset >> 12) & 0x1;
          U32 imm_10_5 = (offset >> 5) & 0x3F;
          U32 imm_4_1 = (offset >> 1) & 0xF;
          U32 imm_11 = (offset >> 11) & 0x1;
          RVU32(pass_buf, &pass_ptr, &rip, 0x63 | (imm_11<<7) | (imm_4_1<<8) | (RV_A0<<15) | (RV_ZERO<<20) | (imm_10_5<<25) | (imm_12<<31));
          stack_depth_final = 0;
        }
        break;
      case IC_BR_NOT_ZERO:
        {
          if (stack_depth_final > 0) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
            stack_depth_final--;
          }

          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - rip;
          // bne a0, zero, offset
          U32 imm_12 = (offset >> 12) & 0x1;
          U32 imm_10_5 = (offset >> 5) & 0x3F;
          U32 imm_4_1 = (offset >> 1) & 0xF;
          U32 imm_11 = (offset >> 11) & 0x1;
          RVU32(pass_buf, &pass_ptr, &rip, 0x63 | (1<<12) | (imm_11<<7) | (imm_4_1<<8) | (RV_A0<<15) | (RV_ZERO<<20) | (imm_10_5<<25) | (imm_12<<31));
          stack_depth_final = 0;
        }
        break;
      case IC_JMP:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - rip;
          // jal zero, offset
          U32 imm_20 = (offset >> 20) & 0x1;
          U32 imm_10_1 = (offset >> 1) & 0x3FF;
          U32 imm_11 = (offset >> 11) & 0x1;
          U32 imm_19_12 = (offset >> 12) & 0xFF;
          RVU32(pass_buf, &pass_ptr, &rip, 0x6F | (imm_19_12<<12) | (imm_11<<20) | (imm_10_1<<21) | (imm_20<<31));
          // Jump targets (like loop starts or epilogue) should have clean stack
          // Reset stack depth to 0 at jump targets (don't adjust sp - epilogue expects it at frame_base)
          stack_depth_final = 0;
        }
        break;
      case IC_MOV:
        // Load from parameter or local variable
        // For now, handles simple register loads and stack loads
        if (stack_depth_final > 0) {
          // addi sp, sp, -8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          // sd a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        }
        // ld a0, offset(s0) - simplified, actual depends on ic_data
        RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_S0<<15) | ((ic->ic_data & 0xFFF)<<20));
        stack_depth_final++;
        break;
      case IC_CALL_INDIRECT:
        {
          I64 arg_count = cc->last_call_arg_cnt;

          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_final--;

          if (arg_count > 8) {
            EmitPrepareGt8CallArgs(pass_buf, &pass_ptr, &rip, arg_count);
          } else if (arg_count >= 2 && arg_count <= 8) {
            EmitLoadArgsFromEvalStack(pass_buf, &pass_ptr, &rip, &stack_depth_final, arg_count);
          } else if (arg_count == 1) {
            stack_depth_final--;
          }

          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_T1<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x67 | (RV_RA<<7) | (RV_T0<<15));

          if (arg_count > 8) {
            I64 out_sz = (arg_count - 8) * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((out_sz & 0xFFF)<<20));
            I64 eval_sz = arg_count * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((eval_sz & 0xFFF)<<20));
            stack_depth_final -= arg_count;
          }

          stack_depth_final++;
        }
        break;
      case IC_CALL_INDIRECT2:
        EmitCallArgsAndInvoke(pass_buf, &pass_ptr, &rip, &stack_depth_final, cc, NULL, (I64 *)ic->ic_data);
        break;
      case IC_CALL:
        EmitCallArgsAndInvoke(pass_buf, &pass_ptr, &rip, &stack_depth_final, cc, (CLabel *)ic->ic_data, NULL);
        break;
      case IC_END_EXP:
        stack_depth_final = 0;
        break;
      case IC_PUSH_RES:
        // Push result to stack - this is just a marker, doesn't change stack_depth
        break;
      case IC_CALL_START:
      case IC_CALL_END:
        // Markers for function call boundaries
        break;
      case IC_LABEL:
        break;
      case IC_NOP1:
      case IC_NOP2:
        // Explicit no-op – leave stack depth unchanged
        break;
      case IC_RETURN_VAL:
      case IC_RETURN_VAL2:
        // Return value should be in a0
        // If it's on the stack, pop it to a0
        if (stack_depth_final > 0) {
          // Pop value from stack to a0
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15)); // ld a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
          stack_depth_final--;
        }
        // Value is now in a0, ready for return
        // Do NOT adjust sp further - the epilogue expects sp at frame_base
        stack_depth_final = 0;
        break;
      case IC_RET:
        // Generate ret instruction with epilogue for expressions
        if (!is_function) {
          if (has_call) {
            // Epilogue: restore ra/s0
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_RA<<7) | (3<<12) | (RV_SP<<15) | (8<<20)); // ld ra, 8(sp)
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_S0<<7) | (3<<12) | (RV_SP<<15)); // ld s0, 0(sp)
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (16<<20)); // addi sp, sp, 16
          }
          RVU32(pass_buf, &pass_ptr, &rip, 0x00008067); // ret
        }
        break;
      default:
        // Skip unimplemented ICs
        break;
      }
      
      ic = ic->next;
    }
    }
  
  // Debug: show convergence
  // printf("Converged after %d passes, code_size=%lld\n", pass, rip);
  
  // Set output code size
  if (code_size) *code_size = rip;
  return buffer;
}

// ═══════════════════════════════════════════════════════════════
// JIT COMPILATION
// ═══════════════════════════════════════════════════════════════

// CompileExpression - for REPL expression compilation
U8 *CompileExpression(Compiler *cc, I64 *size_out) {
  // Check if this is a function (has IC_ENTER) or expression
  CIntermediateCode *ic = cc->ic_head;
  Bool is_function = false;
  while (ic) {
    if (ic->ic_code == IC_ENTER) {
      is_function = true;
      break;
    }
    ic = ic->next;
  }
  
  // For functions, just compile normally
  if (is_function) {
    return CompileAOT(cc, size_out);
  }
  
  // For expressions, add wrapper and compile
  // Check if expression has function calls
  Bool has_call = false;
  ic = cc->ic_head;
  while (ic) {
    if (ic->ic_code == IC_CALL || ic->ic_code == IC_CALL_INDIRECT || ic->ic_code == IC_CALL_INDIRECT2) {
      has_call = true;
      break;
    }
    ic = ic->next;
  }
  
  // If no calls, compile directly
  if (!has_call) {
    return CompileAOT(cc, size_out);
  }
  
  // Has calls - need wrapper with prologue/epilogue
  // Prepend IC_ENTER and append proper IC_LEAVE
  // Actually, just use CompileAOT which already handles IC_RET
  // The issue is we need to save ra for the call
  // TempleOS does this by having COCCompile add the wrapper
  // For now, CompileAOT should handle it via IC_RET
  return CompileAOT(cc, size_out);
}

U8 *CompileJIT(Compiler *cc, I64 *size_out) {
  I64 code_size = 0;
  U8 *code = CompileAOT(cc, &code_size);
  if (size_out) *size_out = code_size;
  
  // Allocate executable memory
  U8 *exec_mem = (U8 *)mmap(NULL, code_size,
                        PROT_READ | PROT_WRITE | PROT_EXEC,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  
  if (exec_mem == (U8 *)MAP_FAILED) {
    // fprintf(stderr, "Failed to allocate executable memory\n");
    free(code);
    return NULL;
  }
  
  // Copy code to executable memory
  memcpy(exec_mem, code, code_size);
  free(code);
  
  return exec_mem;
}

I64 ExecuteJIT(void *code) {
  // Cast to function pointer and call
  typedef I64 (*FuncPtr)();
  FuncPtr func = (FuncPtr)code;
  return func();
}

// ═══════════════════════════════════════════════════════════════
// MAIN COMPILER INTERFACE
// ═══════════════════════════════════════════════════════════════

Compiler *Compile(const char *source, const char *filename, bool aot) {
  Compiler *cc = CompilerNew(source, filename);
  cc->aot_mode = aot;
  cc->defer_aot_compile = TRUE;
  
  // Parse the program
  if (!ParseProgram(cc)) {
    // fprintf(stderr, "Compilation failed: %s\n", 
    //         cc->error ? cc->error : "Unknown error");
    return cc;
  }
  
  // Stitch deferred per-function IC chains (source order) then single AOT pass
  AOTFnICChunk *stitched = NULL;
  if (cc->defer_aot_compile && cc->aot_fn_ic_head) {
    stitched = cc->aot_fn_ic_head;
    AOTFnICChunk *ch = stitched;
    while (ch->next) {
      ch->tail->next = ch->next->head;
      ch = ch->next;
    }
    cc->ic_head = stitched->head;
    cc->ic_tail = ch->tail;
  }
  
  // Generate code (AOT malloc blob or JIT RWX mmap — same label offsets)
  if (aot) {
    cc->code_buffer = CompileAOT(cc, &cc->code_size);
  } else {
    cc->code_buffer = CompileJIT(cc, &cc->code_size);
  }
  if (cc->code_buffer && stitched) {
    for (AOTFnICChunk *ch = stitched; ch; ch = ch->next) {
      if (ch->fun && ch->fun->entry_label) {
        CLabel *lb = (CLabel *)ch->fun->entry_label;
        ch->fun->exe_addr = (I64)(cc->code_buffer + lb->addr);
      }
    }
  }
  
  if (stitched) {
    AOTFnICChunk *n = stitched;
    while (n) {
      AOTFnICChunk *nx = n->next;
      free(n);
      n = nx;
    }
    cc->aot_fn_ic_head = cc->aot_fn_ic_tail = NULL;
  }
  
  return cc;
}

