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
    {"class", KW_CLASS}, {"public", KW_PUBLIC},
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
  
  // Loop context
  cc->current_break_label = NULL;
  cc->current_continue_label = NULL;
  
  // Expression type tracking
  cc->last_var_symbol = NULL;
  cc->last_expr_class = NULL;
  
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
  
  // Free code buffer if allocated
  if (cc->code_buffer) free(cc->code_buffer);
  
  free(cc);
}

// ═══════════════════════════════════════════════════════════════
// RISC-V INSTRUCTION ENCODING
// ═══════════════════════════════════════════════════════════════

// Minimal RISC-V backend integration
// (Full backend is in Back*_RV.HC, this is simplified version)

static void EmitU32(U8 **buf, U32 val) {
  **(U32**)buf = val;
  *buf += 4;
}

static void EmitRISCVAdd(U8 **buf, U8 rd, U8 rs1, U8 rs2) {
  U32 inst = 0x33 | (rd<<7) | (0<<12) | (rs1<<15) | (rs2<<20) | (0<<25);
  EmitU32(buf, inst);
}

static void EmitRISCVAddi(U8 **buf, U8 rd, U8 rs1, I64 imm) {
  U32 inst = 0x13 | (rd<<7) | (0<<12) | (rs1<<15) | ((imm&0xFFF)<<20);
  EmitU32(buf, inst);
}

static void EmitRISCVSub(U8 **buf, U8 rd, U8 rs1, U8 rs2) {
  U32 inst = 0x33 | (rd<<7) | (0<<12) | (rs1<<15) | (rs2<<20) | (0x20<<25);
  EmitU32(buf, inst);
}

static void EmitRISCVMul(U8 **buf, U8 rd, U8 rs1, U8 rs2) {
  U32 inst = 0x33 | (rd<<7) | (0<<12) | (rs1<<15) | (rs2<<20) | (0x01<<25);
  EmitU32(buf, inst);
}

static void EmitRISCVAnd(U8 **buf, U8 rd, U8 rs1, U8 rs2) {
  U32 inst = 0x33 | (rd<<7) | (7<<12) | (rs1<<15) | (rs2<<20);  // AND funct3=7
  EmitU32(buf, inst);
}

static void EmitRISCVOr(U8 **buf, U8 rd, U8 rs1, U8 rs2) {
  U32 inst = 0x33 | (rd<<7) | (6<<12) | (rs1<<15) | (rs2<<20);  // OR funct3=6
  EmitU32(buf, inst);
}

static void EmitRISCVXor(U8 **buf, U8 rd, U8 rs1, U8 rs2) {
  U32 inst = 0x33 | (rd<<7) | (4<<12) | (rs1<<15) | (rs2<<20);  // XOR funct3=4
  EmitU32(buf, inst);
}

static void EmitRISCVLd(U8 **buf, U8 rd, U8 rs1, I64 offset) {
  U32 inst = 0x03 | (rd<<7) | (3<<12) | (rs1<<15) | ((offset&0xFFF)<<20);
  EmitU32(buf, inst);
}

static void EmitRISCVSd(U8 **buf, U8 rs2, U8 rs1, I64 offset) {
  U32 imm_low = offset & 0x1F;
  U32 imm_high = (offset >> 5) & 0x7F;
  U32 inst = 0x23 | (imm_low<<7) | (3<<12) | (rs1<<15) | (rs2<<20) | (imm_high<<25);
  EmitU32(buf, inst);
}

static void EmitRISCVRet(U8 **buf) {
  // RET = JALR x0, 0(ra) = JALR rd=0, rs1=1 (ra), imm=0
  U32 inst = 0x67 | (0<<7) | (0<<12) | (1<<15) | (0<<20);
  EmitU32(buf, inst);
}

static void EmitRISCVJal(U8 **buf, U8 rd, I64 offset) {
  // Simplified - full version in BackLib_RV.HC
  U32 imm_20 = (offset >> 20) & 0x1;
  U32 imm_10_1 = (offset >> 1) & 0x3FF;
  U32 imm_11 = (offset >> 11) & 0x1;
  U32 imm_19_12 = (offset >> 12) & 0xFF;
  U32 inst = 0x6F | (rd<<7) | (imm_19_12<<12) | (imm_11<<20) | 
             (imm_10_1<<21) | (imm_20<<31);
  EmitU32(buf, inst);
}

static void EmitRISCVBeq(U8 **buf, U8 rs1, U8 rs2, I64 offset) {
  // Simplified branch encoding
  U32 imm_11 = (offset >> 11) & 0x1;
  U32 imm_4_1 = (offset >> 1) & 0xF;
  U32 imm_10_5 = (offset >> 5) & 0x3F;
  U32 imm_12 = (offset >> 12) & 0x1;
  U32 inst = 0x63 | (imm_11<<7) | (imm_4_1<<8) | (0<<12) | 
             (rs1<<15) | (rs2<<20) | (imm_10_5<<25) | (imm_12<<31);
  EmitU32(buf, inst);
}

// RISC-V register definitions
#define RV_ZERO 0
#define RV_RA   1
#define RV_SP   2
#define RV_T0   5
#define RV_T1   6
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

static void RVU8(U8 *buf, U8 **ptr, I64 *rip, U8 val) {
  if (buf && ptr) {
    **ptr = val;
    (*ptr)++;
  }
  (*rip)++;
}

static void RVU16(U8 *buf, U8 **ptr, I64 *rip, U16 val) {
  if (buf && ptr) {
    *(U16*)(*ptr) = val;
    (*ptr) += 2;
  }
  (*rip) += 2;
}

static void RVU32(U8 *buf, U8 **ptr, I64 *rip, U32 val) {
  if (buf && ptr) {
    *(U32*)(*ptr) = val;
    (*ptr) += 4;
  }
  (*rip) += 4;
}

static void RVU64(U8 *buf, U8 **ptr, I64 *rip, U64 val) {
  if (buf && ptr) {
    *(U64*)(*ptr) = val;
    (*ptr) += 8;
  }
  (*rip) += 8;
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
    if (ic->ic_code == IC_CALL || ic->ic_code == IC_CALL_INDIRECT2) has_call = true;
    ic = ic->next;
  }
  
  
  // Allocate buffer (estimate 16 bytes per IC operation)
  I64 estimated_size = 0;
  ic = cc->ic_head;
  while (ic) {
    estimated_size += 16;
    ic = ic->next;
  }
  if (has_call && !is_function) estimated_size += 64; // Extra for wrapper
  
  U8 *buffer = malloc(estimated_size);
  U8 *ptr = buffer;
  
  // Multi-pass until convergence (TempleOS OptPass789A.HC approach)
  I64 prev_size = 0;
  I64 rip = 0;
  int pass = 0;
  U8 *pass_buf = NULL;  // NULL for sizing passes, buffer for final pass
  U8 *pass_ptr = NULL;
  
  do {
    prev_size = rip;
    rip = 0;
    pass++;
    
    ic = cc->ic_head;
    I64 stack_depth_pass = 0;  // Track stack depth for accurate sizing
    pass_ptr = buffer;  // Reset pointer each pass
    
    // Check if we converged in previous pass (and this is final emission pass)
    Bool is_final_pass = (pass > 2 && prev_size == rip);  // rip is 0 here, will be updated during pass
    // For now, always use NULL for sizing, we'll do final emission after loop
    pass_buf = NULL;    // Just count bytes
    
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
        if (stack_depth_pass > 0) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12)); // sd a0, 0(sp)
        }
        {
          I64 offset = ic->ic_data;
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_S0<<15) | ((offset & 0xFFF)<<20)); // addi a0, s0, offset
        }
        stack_depth_pass++;
        break;
        
      case IC_IMM_I64:
        if (stack_depth_pass > 0) {
          // addi sp, sp, -8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          // sd a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        }
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
        stack_depth_pass++;
        break;
      case IC_ADD:
      case IC_SUB:
      case IC_MUL:
      case IC_DIV:
      case IC_MOD:
        if (stack_depth_pass >= 2) {
          // ld t0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          // addi sp, sp, 8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          // op a0, t0, a0
          if (ic->ic_code == IC_ADD) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20));
          } else if (ic->ic_code == IC_SUB) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20) | (0x20<<25));
          } else if (ic->ic_code == IC_MUL) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20) | (1<<25));
          } else if (ic->ic_code == IC_DIV) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (4<<12) | (RV_T0<<15) | (RV_A0<<20) | (1<<25));
          } else if (ic->ic_code == IC_MOD) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (6<<12) | (RV_T0<<15) | (RV_A0<<20) | (1<<25));
          }
          stack_depth_pass--;
        }
        break;
      case IC_DEREF:
        // ld a0, 0(a0)
        RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_A0<<15));
        break;
      case IC_ASSIGN:
        if (stack_depth_pass >= 2) {
          // ld t0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          // addi sp, sp, 8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          // sd a0, 0(t0)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_T0<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_pass--;
        }
        break;
      case IC_LESS:
      case IC_GREATER:
      case IC_LESS_EQU:
      case IC_GREATER_EQU:
      case IC_EQU_EQU:
      case IC_NOT_EQU:
        if (stack_depth_pass >= 2) {
          // ld t0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          // addi sp, sp, 8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          // Comparison operations
          if (ic->ic_code == IC_LESS) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (2<<12) | (RV_T0<<15) | (RV_A0<<20)); // slt
          } else if (ic->ic_code == IC_GREATER) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (2<<12) | (RV_A0<<15) | (RV_T0<<20)); // slt a0,a0,t0
          } else if (ic->ic_code == IC_LESS_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (2<<12) | (RV_A0<<15) | (RV_T0<<20)); // slt
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20)); // xori a0,a0,1
          } else if (ic->ic_code == IC_GREATER_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (2<<12) | (RV_T0<<15) | (RV_A0<<20)); // slt
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20)); // xori a0,a0,1
          } else if (ic->ic_code == IC_EQU_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20) | (0x20<<25)); // sub
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (3<<12) | (RV_A0<<15) | (1<<20)); // sltiu a0,a0,1
          } else if (ic->ic_code == IC_NOT_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20) | (0x20<<25)); // sub
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (3<<12) | (RV_ZERO<<15) | (RV_A0<<20)); // sltu a0,zero,a0
          }
          stack_depth_pass--;
        }
        break;
      case IC_BR_ZERO:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - rip;
          // beq a0, zero, offset
          U32 imm_12 = (offset >> 12) & 0x1;
          U32 imm_10_5 = (offset >> 5) & 0x3F;
          U32 imm_4_1 = (offset >> 1) & 0xF;
          U32 imm_11 = (offset >> 11) & 0x1;
          RVU32(pass_buf, &pass_ptr, &rip, 0x63 | (imm_11<<7) | (imm_4_1<<8) | (RV_A0<<15) | (RV_ZERO<<20) | (imm_10_5<<25) | (imm_12<<31));
          if (stack_depth_pass > 0) stack_depth_pass--;
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
      case IC_CALL_INDIRECT2:
        {
          // Indirect call - load exe_addr at runtime
          // ic_data = &func->exe_addr (pointer to the field)
          I64 *exe_addr_ptr = (I64*)ic->ic_data;
          I64 arg_count = cc->last_call_arg_cnt;
          
          // Handle argument passing (RISC-V calling convention: a0-a7 registers, rest on stack)
          if (arg_count > 8) {
            // More than 8 args: first 8 in a0-a7, rest on stack
            // Current state: arg9+ in a0, args 1-8 on stack
            // Need to push a0 (arg9+) to stack first
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
            RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12)); // sd a0, 0(sp)
            stack_depth_pass++;
            
            // Now all args are on stack: arg1 at sp+0, arg2 at sp+8, ..., arg8 at sp+56, arg9+ at sp+64+
            // Load a0-a7 from stack (arg1-arg8)
            for (I64 i = 0; i < 8; i++) {
              U8 reg = RV_A0 + i;
              I64 offset = i * 8; // arg1 at sp+0, arg2 at sp+8, ..., arg8 at sp+56
              RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (reg<<7) | (3<<12) | (RV_SP<<15) | ((offset & 0xFFF)<<20)); // ld aX, offset(sp)
            }
            // Don't clean up yet - all args stay on stack for callee to access
          } else if (arg_count == 8) {
            // Exactly 8 args: all in registers
            // Current: arg7 in a0, args 0-6 on stack
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A7<<7) | (RV_A0<<15)); // mv a7, a0
            for (I64 i = 0; i < 7; i++) {
              U8 reg = RV_A0 + i;
              I64 offset = (7 - i - 1) * 8;
              RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (reg<<7) | (3<<12) | (RV_SP<<15) | ((offset & 0xFFF)<<20)); // ld aX, offset(sp)
            }
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((56 & 0xFFF)<<20)); // addi sp, sp, 56
            stack_depth_pass -= 8;
          } else if (arg_count >= 3) {
            // 3-7 args: all in registers
            // Current: last arg in a0, others on stack
            U8 last_reg = RV_A0 + (arg_count - 1);
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (last_reg<<7) | (RV_A0<<15)); // mv aX, a0
            for (I64 i = 0; i < arg_count - 1; i++) {
              U8 reg = RV_A0 + i;
              I64 offset = (arg_count - 2 - i) * 8;
              RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (reg<<7) | (3<<12) | (RV_SP<<15) | ((offset & 0xFFF)<<20)); // ld aX, offset(sp)
            }
            I64 cleanup = (arg_count - 1) * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((cleanup & 0xFFF)<<20)); // addi sp, sp, cleanup
            stack_depth_pass -= arg_count;
          } else if (arg_count == 2) {
            // 2 args: a1 in a0, a0 on stack
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A1<<7) | (RV_A0<<15)); // mv a1, a0
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15)); // ld a0, 0(sp)
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
            stack_depth_pass -= 2;
          } else if (arg_count == 1) {
            // 1 arg: already in a0
            stack_depth_pass--;
          }
          
          // Load exe_addr from memory (indirect)
          // exe_addr_ptr points to the exe_addr field in CHashFun struct
          I64 addr = (I64)exe_addr_ptr;
          
          
          // Load address into t0 (TempleOS approach with conditionals)
          U32 hi = (addr >> 12) & 0xFFFFF;
          RVU32(pass_buf, &pass_ptr, &rip, 0x37 | (RV_T0<<7) | (hi<<12)); // lui t0, hi
          I64 lo = addr & 0xFFF;
          if (lo) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (RV_T0<<15) | ((lo & 0xFFF)<<20)); // addi t0, t0, lo
          }
          if (addr & 0x80000000) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (1<<12) | (RV_T0<<15) | (32<<20)); // slli
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (5<<12) | (RV_T0<<15) | (32<<20)); // srli
          }
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_T0<<15)); // ld t0, 0(t0)
          RVU32(pass_buf, &pass_ptr, &rip, 0x67 | (RV_RA<<7) | (RV_T0<<15)); // jalr ra, t0
          
          // Clean up stack after call
          if (arg_count > 8) {
            // For >8 params, we pushed arg9+ to stack, so clean up arg_count * 8 bytes
            I64 cleanup_bytes = arg_count * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((cleanup_bytes & 0xFFF)<<20)); // addi sp, sp, cleanup_bytes
            stack_depth_pass -= arg_count;
          }
          
          stack_depth_pass++;
        }
        break;
      case IC_CALL:
        // Not used in REPL - functions use IC_CALL_INDIRECT2
        stack_depth_pass++;
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
      case IC_NOP1:
      case IC_NOP2:
      case IC_RETURN_VAL:
      case IC_RETURN_VAL2:
        // No code generated
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
        if (stack_depth_final > 0) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12)); // sd a0, 0(sp)
        }
        {
          I64 offset = ic->ic_data;
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_S0<<15) | ((offset & 0xFFF)<<20)); // addi a0, s0, offset
        }
        stack_depth_final++;
        break;
        
      case IC_IMM_I64:
        if (stack_depth_final > 0) {
          // addi sp, sp, -8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          // sd a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        }
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
        stack_depth_final++;
        break;
        
      case IC_ADD:
      case IC_SUB:
      case IC_MUL:
      case IC_DIV:
      case IC_MOD:
        if (stack_depth_final >= 2) {
          // ld t0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          // addi sp, sp, 8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          // op a0, t0, a0
          if (ic->ic_code == IC_ADD) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20));
          } else if (ic->ic_code == IC_SUB) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20) | (0x20<<25));
          } else if (ic->ic_code == IC_MUL) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20) | (1<<25));
          } else if (ic->ic_code == IC_DIV) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (4<<12) | (RV_T0<<15) | (RV_A0<<20) | (1<<25));
          } else if (ic->ic_code == IC_MOD) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (6<<12) | (RV_T0<<15) | (RV_A0<<20) | (1<<25));
          }
          stack_depth_final--;
        }
        break;
        
      case IC_DEREF:
        // ld a0, 0(a0)
        RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_A0<<15));
        break;
      case IC_ASSIGN:
        if (stack_depth_final >= 2) {
          // ld t0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          // addi sp, sp, 8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          // sd a0, 0(t0)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_T0<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final--;
        }
        break;
      case IC_LESS:
      case IC_GREATER:
      case IC_LESS_EQU:
      case IC_GREATER_EQU:
      case IC_EQU_EQU:
      case IC_NOT_EQU:
        if (stack_depth_final >= 2) {
          // ld t0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));
          // addi sp, sp, 8
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          // Comparison operations
          if (ic->ic_code == IC_LESS) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (2<<12) | (RV_T0<<15) | (RV_A0<<20)); // slt
          } else if (ic->ic_code == IC_GREATER) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (2<<12) | (RV_A0<<15) | (RV_T0<<20)); // slt a0,a0,t0
          } else if (ic->ic_code == IC_LESS_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (2<<12) | (RV_A0<<15) | (RV_T0<<20)); // slt
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20)); // xori a0,a0,1
          } else if (ic->ic_code == IC_GREATER_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (2<<12) | (RV_T0<<15) | (RV_A0<<20)); // slt
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20)); // xori a0,a0,1
          } else if (ic->ic_code == IC_EQU_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20) | (0x20<<25)); // sub
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (3<<12) | (RV_A0<<15) | (1<<20)); // sltiu a0,a0,1
          } else if (ic->ic_code == IC_NOT_EQU) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_A0<<20) | (0x20<<25)); // sub
            RVU32(pass_buf, &pass_ptr, &rip, 0x33 | (RV_A0<<7) | (3<<12) | (RV_ZERO<<15) | (RV_A0<<20)); // sltu a0,zero,a0
          }
          stack_depth_final--;
        }
        break;
      case IC_BR_ZERO:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - rip;
          // beq a0, zero, offset
          U32 imm_12 = (offset >> 12) & 0x1;
          U32 imm_10_5 = (offset >> 5) & 0x3F;
          U32 imm_4_1 = (offset >> 1) & 0xF;
          U32 imm_11 = (offset >> 11) & 0x1;
          RVU32(pass_buf, &pass_ptr, &rip, 0x63 | (imm_11<<7) | (imm_4_1<<8) | (RV_A0<<15) | (RV_ZERO<<20) | (imm_10_5<<25) | (imm_12<<31));
          if (stack_depth_final > 0) stack_depth_final--;
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
      case IC_CALL_INDIRECT2:
        {
          // Indirect call - load exe_addr at runtime
          // ic_data = &func->exe_addr (pointer to the field)
          I64 *exe_addr_ptr = (I64*)ic->ic_data;
          I64 arg_count = cc->last_call_arg_cnt;
          
          // Handle argument passing (RISC-V calling convention: a0-a7 registers, rest on stack)
          if (arg_count > 8) {
            // More than 8 args: first 8 in a0-a7, rest on stack
            // Current state: arg9+ in a0, args 1-8 on stack
            // Need to push a0 (arg9+) to stack first
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
            RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12)); // sd a0, 0(sp)
            stack_depth_final++;
            
            // Now all args are on stack: arg1 at sp+0, arg2 at sp+8, ..., arg8 at sp+56, arg9+ at sp+64+
            // Load a0-a7 from stack (arg1-arg8)
            for (I64 i = 0; i < 8; i++) {
              U8 reg = RV_A0 + i;
              I64 offset = i * 8; // arg1 at sp+0, arg2 at sp+8, ..., arg8 at sp+56
              RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (reg<<7) | (3<<12) | (RV_SP<<15) | ((offset & 0xFFF)<<20)); // ld aX, offset(sp)
            }
            // Don't clean up yet - all args stay on stack for callee to access
          } else if (arg_count == 8) {
            // Exactly 8 args: all in registers
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A7<<7) | (RV_A0<<15)); // mv a7, a0
            for (I64 i = 0; i < 7; i++) {
              U8 reg = RV_A0 + i;
              I64 offset = (7 - i - 1) * 8;
              RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (reg<<7) | (3<<12) | (RV_SP<<15) | ((offset & 0xFFF)<<20)); // ld aX, offset(sp)
            }
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((56 & 0xFFF)<<20)); // addi sp, sp, 56
            stack_depth_final -= 8;
          } else if (arg_count >= 3) {
            // 3-7 args: all in registers
            U8 last_reg = RV_A0 + (arg_count - 1);
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (last_reg<<7) | (RV_A0<<15)); // mv aX, a0
            for (I64 i = 0; i < arg_count - 1; i++) {
              U8 reg = RV_A0 + i;
              I64 offset = (arg_count - 2 - i) * 8;
              RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (reg<<7) | (3<<12) | (RV_SP<<15) | ((offset & 0xFFF)<<20)); // ld aX, offset(sp)
            }
            I64 cleanup = (arg_count - 1) * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((cleanup & 0xFFF)<<20)); // addi sp, sp, cleanup
            stack_depth_final -= arg_count;
          } else if (arg_count == 2) {
            // 2 args: a1 in a0, a0 on stack
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A1<<7) | (RV_A0<<15)); // mv a1, a0
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15)); // ld a0, 0(sp)
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
            stack_depth_final -= 2;
          } else if (arg_count == 1) {
            // 1 arg: already in a0
            stack_depth_final--;
          }
          
          // Load exe_addr from memory (indirect)
          // exe_addr_ptr points to the exe_addr field in CHashFun struct
          I64 addr = (I64)exe_addr_ptr;
          
          
          // Load address into t0 (TempleOS approach with conditionals)
          U32 hi = (addr >> 12) & 0xFFFFF;
          RVU32(pass_buf, &pass_ptr, &rip, 0x37 | (RV_T0<<7) | (hi<<12)); // lui t0, hi
          I64 lo = addr & 0xFFF;
          if (lo) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (RV_T0<<15) | ((lo & 0xFFF)<<20)); // addi t0, t0, lo
          }
          if (addr & 0x80000000) {
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (1<<12) | (RV_T0<<15) | (32<<20)); // slli
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (5<<12) | (RV_T0<<15) | (32<<20)); // srli
          }
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_T0<<15)); // ld t0, 0(t0)
          RVU32(pass_buf, &pass_ptr, &rip, 0x67 | (RV_RA<<7) | (RV_T0<<15)); // jalr ra, t0
          
          // Clean up stack after call
          if (arg_count > 8) {
            // For >8 params, we pushed arg9+ to stack, so clean up arg_count * 8 bytes
            I64 cleanup_bytes = arg_count * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((cleanup_bytes & 0xFFF)<<20)); // addi sp, sp, cleanup_bytes
            stack_depth_final -= arg_count;
          }
          
          stack_depth_final++;
        }
        break;
      case IC_CALL:
        // Not used in REPL - functions use IC_CALL_INDIRECT2
        stack_depth_final++;
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
      case IC_NOP1:
      case IC_NOP2:
      case IC_RETURN_VAL:
      case IC_RETURN_VAL2:
        // No code generated
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
    if (ic->ic_code == IC_CALL || ic->ic_code == IC_CALL_INDIRECT2) {
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
  
  // Parse the program
  if (!ParseProgram(cc)) {
    // fprintf(stderr, "Compilation failed: %s\n", 
    //         cc->error ? cc->error : "Unknown error");
    return cc;
  }
  
  // Generate code
  if (aot) {
    cc->code_buffer = CompileAOT(cc, &cc->code_size);
  } else {
    cc->code_buffer = CompileJIT(cc, &cc->code_size);
  }
  
  return cc;
}

