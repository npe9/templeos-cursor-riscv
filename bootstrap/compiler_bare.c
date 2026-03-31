/* HolyC to RISC-V Compiler - Main Driver
 * Complete AOT and JIT compiler
 */

#include "holyc_compiler_bare.h"

// Bare metal - mmap already defined in bare_runtime.h

// ═══════════════════════════════════════════════════════════════
// COMPILER INITIALIZATION
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
  cc->last_type_class = NULL;
  cc->last_global_var = NULL;
  
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
  free(cc->lex.src);
  free(cc->lex.filename);
  free(cc->lex.token_str);
  
  // Free IC list
  CIntermediateCode *ic = cc->ic_head;
  while (ic) {
    CIntermediateCode *next = ic->next;
    free(ic);
    ic = next;
  }
  
  // Free labels
  CLabel *lb = cc->labels;
  while (lb) {
    CLabel *next = lb->next;
    free(lb->name);
    free(lb);
    lb = next;
  }
  
  // Free symbol table
  while (cc->symtab) {
    SymTablePop(cc);
  }
  
  free(cc->error);
  free(cc->code_buffer);
  free(cc);
}

// ═══════════════════════════════════════════════════════════════
// RISC-V BACKEND INTERFACE
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
  U32 inst = 0x67;  // JALR x0, 0(ra)
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

static void EmitRISCVBne(U8 **buf, U8 rs1, U8 rs2, I64 offset) {
  U32 imm_11 = (offset >> 11) & 0x1;
  U32 imm_4_1 = (offset >> 1) & 0xF;
  U32 imm_10_5 = (offset >> 5) & 0x3F;
  U32 imm_12 = (offset >> 12) & 0x1;
  U32 inst = 0x63 | (imm_11<<7) | (imm_4_1<<8) | (1<<12) |
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

static U32 DerefLoadFromRs1(U8 pointed_to, U8 rs1) {
  switch (pointed_to) {
  case RT_I8:
    return 0x03 | (RV_A0 << 7) | (0 << 12) | (rs1 << 15);
  case RT_U8:
    return 0x03 | (RV_A0 << 7) | (4 << 12) | (rs1 << 15);
  case RT_I16:
    return 0x03 | (RV_A0 << 7) | (1 << 12) | (rs1 << 15);
  case RT_U16:
    return 0x03 | (RV_A0 << 7) | (5 << 12) | (rs1 << 15);
  case RT_I32:
    return 0x03 | (RV_A0 << 7) | (2 << 12) | (rs1 << 15);
  case RT_U32:
    return 0x03 | (RV_A0 << 7) | (6 << 12) | (rs1 << 15);
  default:
    return 0x03 | (RV_A0 << 7) | (3 << 12) | (rs1 << 15);
  }
}

// ═══════════════════════════════════════════════════════════════
// CODE GENERATION (AOT)
// ═══════════════════════════════════════════════════════════════

U8 *CompileAOT(Compiler *cc, I64 *code_size) {
  // Allocate buffer (estimate 16 bytes per IC operation)
  I64 estimated_size = 0;
  CIntermediateCode *ic = cc->ic_head;
  while (ic) {
    estimated_size += 16;
    ic = ic->next;
  }
  
  U8 *buffer = malloc(estimated_size);
  U8 *ptr = buffer;
  I64 rip = 0;
  
  // First pass: assign addresses to labels
  ic = cc->ic_head;
  while (ic) {
    if (ic->ic_code == IC_LABEL) {
      CLabel *lb = (CLabel*)ic->ic_data;
      lb->addr = rip;
    }
    
    // Estimate instruction count (simplified)
    switch (ic->ic_code) {
      case IC_ENTER:
        rip += 12;  // 3 instructions
        break;
      case IC_LEAVE:
        rip += 16;  // 4 instructions
        break;
      case IC_IMM_I64:
        if (ic->ic_data >= -2048 && ic->ic_data <= 2047) {
          rip += 4;   // 1 instruction
        } else {
          rip += 12;  // 3 instructions for LUI+ADDI
        }
        break;
      case IC_ADD:
      case IC_SUB:
      case IC_MUL:
        rip += 4;  // 1 instruction
        break;
      case IC_MOV:
        rip += 4;  // 1 instruction (simplified)
        break;
      case IC_RET:
        rip += 4;
        break;
      case IC_CALL:
        rip += 4;
        break;
      case IC_BR_ZERO:
      case IC_BR_NOT_ZERO:
        rip += 4;
        break;
      case IC_EVAL_DROP:
        rip += 4;
        break;
      case IC_DEREF:
        rip += 12;
        break;
      default:
        rip += 4;
    }
    
    ic = ic->next;
  }
  
  // Second pass: generate code
  ptr = buffer;
  ic = cc->ic_head;
  
  while (ic) {
    switch (ic->ic_code) {
      case IC_ENTER:
        // Prologue
        EmitRISCVAddi(&ptr, RV_SP, RV_SP, -16);
        EmitRISCVSd(&ptr, RV_S0, RV_SP, 8);
        EmitRISCVAddi(&ptr, RV_S0, RV_SP, 16);
        if (ic->ic_data > 0) {
          EmitRISCVAddi(&ptr, RV_SP, RV_SP, -ic->ic_data);
        }
        break;
        
      case IC_LEAVE:
        // Epilogue
        if (ic->ic_data > 0) {
          EmitRISCVAddi(&ptr, RV_SP, RV_SP, ic->ic_data);
        }
        EmitRISCVLd(&ptr, RV_S0, RV_SP, 8);
        EmitRISCVAddi(&ptr, RV_SP, RV_SP, 16);
        EmitRISCVRet(&ptr);
        break;
        
      case IC_RET:
        EmitRISCVRet(&ptr);
        break;
        
      case IC_IMM_I64:
        // Load immediate to a0
        if (ic->ic_data >= -2048 && ic->ic_data <= 2047) {
          EmitRISCVAddi(&ptr, RV_A0, RV_ZERO, ic->ic_data);
        } else {
          // LUI + ADDI for larger values
          I64 hi = (ic->ic_data + 0x800) >> 12;
          I64 lo = ic->ic_data & 0xFFF;
          if (lo & 0x800) lo |= 0xFFFFFFFFFFFFF000LL;
          
          U32 lui = 0x37 | (RV_A0<<7) | ((hi & 0xFFFFF)<<12);
          EmitU32(&ptr, lui);
          
          if (lo) {
            EmitRISCVAddi(&ptr, RV_A0, RV_A0, lo);
          }
        }
        break;
        
      case IC_ADD:
        // Pop two values, add, push result
        // Simplified: assume operands in t0, t1
        EmitRISCVAdd(&ptr, RV_A0, RV_T0, RV_T1);
        break;
        
      case IC_SUB:
        EmitRISCVSub(&ptr, RV_A0, RV_T0, RV_T1);
        break;
        
      case IC_MUL:
        EmitRISCVMul(&ptr, RV_A0, RV_T0, RV_T1);
        break;
        
      case IC_RETURN_VAL:
        // Value to return is already in a0
        break;
        
      case IC_LABEL:
        // No code generated
        break;
        
      case IC_JMP:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - (ptr - buffer);
          EmitRISCVJal(&ptr, RV_ZERO, offset);
        }
        break;
        
      case IC_BR_ZERO:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - (ptr - buffer);
          EmitRISCVBeq(&ptr, RV_A0, RV_ZERO, offset);
        }
        break;
        
      case IC_BR_NOT_ZERO:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          I64 offset = lb->addr - (ptr - buffer);
          EmitRISCVBne(&ptr, RV_A0, RV_ZERO, offset);
        }
        break;
        
      case IC_END_EXP:
      case IC_CALL_START:
      case IC_CALL_END:
        // Markers, no code
        break;

      case IC_EVAL_DROP:
        if (ic->ic_data != 0) {
          EmitRISCVAddi(&ptr, RV_SP, RV_SP, (I64)(ic->ic_data & 0xFFF));
        }
        break;

      case IC_DEREF:
        EmitU32(&ptr, DerefLoadFromRs1(ic->arg1_type_pointed_to, RV_A0));
        EmitRISCVAddi(&ptr, RV_SP, RV_SP, -8);
        EmitRISCVSd(&ptr, RV_A0, RV_SP, 0);
        break;
        
      default:
        // Emit NOP for unimplemented operations
        EmitRISCVAddi(&ptr, RV_ZERO, RV_ZERO, 0);
    }
    
    ic = ic->next;
  }
  
  *code_size = ptr - buffer;
  return buffer;
}

// ═══════════════════════════════════════════════════════════════
// JIT COMPILATION
// ═══════════════════════════════════════════════════════════════

void *CompileJIT(Compiler *cc) {
  I64 code_size = 0;
  U8 *code = CompileAOT(cc, &code_size);
  
  // Allocate executable memory
  void *exec_mem = mmap(NULL, code_size,
                        PROT_READ | PROT_WRITE | PROT_EXEC,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  
  if (exec_mem == MAP_FAILED) {
    fprintf(stderr, "Failed to allocate executable memory\n");
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
    fprintf(stderr, "Compilation failed: %s\n", 
            cc->error ? cc->error : "Unknown error");
    return cc;
  }
  
  // Generate code
  if (aot) {
    cc->code_buffer = CompileAOT(cc, &cc->code_size);
  } else {
    cc->code_buffer = CompileJIT(cc);
    cc->code_size = 0;  // JIT doesn't track size separately
  }
  
  return cc;
}

// ═══════════════════════════════════════════════════════════════
// TEST / MAIN
// ═══════════════════════════════════════════════════════════════

#ifdef HOLYC_STANDALONE

int main(int argc, char **argv) {
  printf("═══════════════════════════════════════════════════════════\n");
  printf("HolyC to RISC-V Compiler (AOT/JIT)\n");
  printf("═══════════════════════════════════════════════════════════\n\n");
  
  if (argc < 2) {
    printf("Usage: %s <source.hc> [-o output.bin]\n", argv[0]);
    printf("       %s -jit <source.hc>\n", argv[0]);
    printf("\n");
    printf("Examples:\n");
    printf("  %s test.hc -o test.bin        # AOT compilation\n", argv[0]);
    printf("  %s -jit test.hc                # JIT execution\n", argv[0]);
    return 1;
  }
  
  bool jit_mode = false;
  const char *input_file = NULL;
  const char *output_file = "a.out";
  
  // Parse arguments
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-jit") == 0) {
      jit_mode = true;
    } else if (strcmp(argv[i], "-o") == 0 && i+1 < argc) {
      output_file = argv[++i];
    } else {
      input_file = argv[i];
    }
  }
  
  if (!input_file) {
    fprintf(stderr, "Error: No input file specified\n");
    return 1;
  }
  
  // Read source file
  FILE *f = fopen(input_file, "r");
  if (!f) {
    fprintf(stderr, "Error: Cannot open %s\n", input_file);
    return 1;
  }
  
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  
  char *source = malloc(size + 1);
  fread(source, 1, size, f);
  source[size] = '\0';
  fclose(f);
  
  printf("Compiling %s...\n", input_file);
  
  // Compile
  Compiler *cc = Compile(source, input_file, !jit_mode);
  free(source);
  
  if (cc->error) {
    fprintf(stderr, "Compilation failed.\n");
    CompilerFree(cc);
    return 1;
  }
  
  if (jit_mode) {
    printf("✓ Compiled successfully (JIT mode)\n");
    printf("Executing...\n\n");
    printf("─────────────────────────────────────\n");
    
    I64 result = ExecuteJIT(cc->code_buffer);
    
    printf("─────────────────────────────────────\n");
    printf("\nProgram returned: %lld\n", result);
  } else {
    printf("✓ Compiled successfully (AOT mode)\n");
    printf("Code size: %lld bytes\n", cc->code_size);
    
    // Write output file
    f = fopen(output_file, "wb");
    if (!f) {
      fprintf(stderr, "Error: Cannot write %s\n", output_file);
      CompilerFree(cc);
      return 1;
    }
    
    fwrite(cc->code_buffer, 1, cc->code_size, f);
    fclose(f);
    
    printf("✓ Wrote %s\n\n", output_file);
    
    printf("To disassemble:\n");
    printf("  riscv64-unknown-elf-objdump -D -b binary -m riscv:rv64 %s\n\n", output_file);
    
    printf("To run in QEMU:\n");
    printf("  qemu-riscv64 %s\n", output_file);
  }
  
  CompilerFree(cc);
  return 0;
}

#endif // HOLYC_STANDALONE

