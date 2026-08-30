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
    {"goto", KW_GOTO}, {"continue", KW_CONTINUE}, {"do", KW_DO},
    {"switch", KW_SWITCH}, {"case", KW_CASE}, {"default", KW_DEFAULT},
    {"sizeof", KW_SIZEOF}, {"union", KW_UNION}, {"static", KW_STATIC},
    {"try", KW_TRY}, {"catch", KW_CATCH}, {"throw", KW_THROW},
    {"asm", KW_ASM},
    {"extern", KW_EXTERN}, {"_extern", KW__EXTERN}, {"_intern", KW__INTERN},
    {"import", KW_IMPORT}, {"_import", KW__IMPORT}, {"interrupt", KW_INTERRUPT},
    {"haserrcode", KW_HASERRCODE}, {"argpop", KW_ARGPOP}, {"noreg", KW_NOREG},
    {"reg", KW_REG}, {"no_warn", KW_NO_WARN}, {"lastclass", KW_LASTCLASS},
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
  // Runtime globals the generated code needs: the handler-context stack top and the last
  // throw's code (HolyC's Fs->except_ch). Ordinary globals: absolute in the REPL, data section in AOT.
  {
    // class CTask { I64 except_ch; }; __task is one of those; Fs points at it (HolyC's
    // Fs->except_ch). The REPL sets Fs at init; AOT does it first thing in the entry chunk.
    CHashClass *task = calloc(1, sizeof(CHashClass));
    task->str = strdup("CTask");
    task->type = HTT_CLASS;
    task->raw_type = RT_I64;
    CMemberLst *m = calloc(1, sizeof(CMemberLst));
    m->str = strdup("except_ch");
    m->offset = 0;
    m->size = 8;
    CMemberLst *m2 = calloc(1, sizeof(CMemberLst));
    m2->str = strdup("catch_except");
    m2->offset = 8;
    m2->size = 8;
    m2->raw_type = RT_I64;
    CMemberLst *m3 = calloc(1, sizeof(CMemberLst));   // I64 except_callers[8]
    m3->str = strdup("except_callers");
    m3->offset = 16;
    m3->size = 64;
    m3->raw_type = RT_I64;
    m3->is_array = true;
    m3->elem_size = 8;
    m->raw_type = RT_I64;
    m->next = m2;
    m2->next = m3;
    task->member_lst = m;
    task->size = 80;
    HashAdd((CHashEntry *)task, cc->hash_table);
    // HolyC predefined constants
    struct { const char *n; I64 v; } consts[] = {
      { "NULL", 0 }, { "TRUE", 1 }, { "FALSE", 0 }, { "ON", 1 }, { "OFF", 0 },
      { "I64_MAX", 0x7FFFFFFFFFFFFFFFLL }, { "I64_MIN", (I64)0x8000000000000000ULL },
      { "U8_MAX", 255 }, { "U16_MAX", 65535 }, { "U32_MAX", 0xFFFFFFFFLL }, { "I32_MAX", 0x7FFFFFFF }, { "I32_MIN", -0x80000000LL },
    };
    for (size_t ci = 0; ci < sizeof(consts) / sizeof(consts[0]); ci++) {
      CHashEnumValue *ev = calloc(1, sizeof(CHashEnumValue));
      ev->str = strdup(consts[ci].n);
      ev->type = HTT_ENUM;
      ev->value = consts[ci].v;
      HashAdd((CHashEntry *)ev, cc->hash_table);
    }
    // `Gs` (per-CPU block) is a pointer to a forward-declared CCPU the kernel fills in.
    CHashClass *cpu = calloc(1, sizeof(CHashClass));
    cpu->str = strdup("CCPU");
    cpu->type = HTT_CLASS;
    cpu->raw_type = RT_I64;
    HashAdd((CHashEntry *)cpu, cc->hash_table);
    // F64 limits are compiler built-ins in TempleOS as well; as text so they lex as F64.
    struct { const char *n; const char *v; } fdefs[] = {
      { "F64_MAX", "(0x7FEFFFFFFFFFFFFF(F64))" }, { "F64_MIN", "(0xFFEFFFFFFFFFFFFF(F64))" }, { "F64_EPSILON", "(0x3CB0000000000000(F64))" },   // as Kernel/KernelA.HH
    };
    for (size_t fi = 0; fi < sizeof(fdefs) / sizeof(fdefs[0]); fi++) {
      CHashDefine *def = calloc(1, sizeof(CHashDefine));
      def->str = strdup(fdefs[fi].n);
      def->type = HTT_DEFINE_STR;
      def->data = strdup(fdefs[fi].v);
      def->param_count = 0;
      HashAdd((CHashEntry *)def, cc->define_table);
    }
    const char *names[4] = { "__try_top", "__task", "Fs", "Gs" };
    for (int i = 0; i < 4; i++) {
      CHashGlblVar *g = calloc(1, sizeof(CHashGlblVar));
      g->str = strdup(names[i]);
      g->type = HTT_GLBL_VAR;
      g->size = i == 1 ? 80 : 8;   // __task: CTask (except_ch, catch_except, except_callers[8])
      g->element_size = 8;
      g->raw_type = RT_I64;
      if (i == 1) g->var_class = task;
      if (i == 2) { g->var_class = task; g->pointed_to_type = RT_I64; }
      if (i == 3) { g->var_class = cpu; g->pointed_to_type = RT_I64; }
      g->data_addr = calloc(1, (size_t)g->size);
      HashAdd((CHashEntry *)g, cc->hash_table);
      if (i == 0) cc->try_top_var = g;
      else if (i == 1) cc->except_ch_var = g;   // except_ch is the task block's first field
      else if (i == 2) cc->fs_var = g;
    }
  }
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

// ---- Tier 1 peephole: cancel an adjacent eval-stack push/pop -------------------------------
// The codegen bakes stack traffic into each op's emit (IMM auto-pushes, consumers pop), so the
// dominant redundancy is `addi sp,-8; sd rX,0(sp); ld rX,0(sp); addi sp,+8` -- push a value and
// immediately pop it back into the SAME register, which is pure waste (the value is still in rX).
// RVU32 keeps the last three emitted words; when a fourth completes the pattern it rewinds rip by
// three words and drops the fourth. It runs identically in the sizing (buf==NULL) and emit passes
// -- rip is adjusted the same way in both -- so the relaxation loop still converges.
//
// CAUTION: CompileAOT has TWO emit loops -- the do-while sizing loop AND a separate final-emission
// pass. The window (g_pp_n) must be reset at the START of each and at EVERY IC_LABEL in BOTH, or
// the two passes cancel differently: mismatched sizes, and push/pops wrongly cancelled across a
// branch target (which silently miscompiles every loop). We only cancel when rX==rY -- the pop
// target equals the push source -- which is unambiguously safe; the rX!=rY (-> `mv rY,rX`) case is
// left on the table. Gated by g_pp_on (= cc->optimize).
static U32 g_pp[3];
static int g_pp_n;
static int g_pp_on;
static int RvIsAddi(U32 w, int rd, int rs1, int imm) {
  return (w & 0x7F) == 0x13 && ((w >> 12) & 7) == 0 && (int)((w >> 7) & 0x1F) == rd &&
         (int)((w >> 15) & 0x1F) == rs1 && (((I32)w) >> 20) == imm;
}
static void RVU32(U8 *buf, U8 **ptr, I64 *rip, U32 val) {
  if (g_pp_on && g_pp_n >= 3) {
    U32 w0 = g_pp[0], w1 = g_pp[1], w2 = g_pp[2];
    int isDec = RvIsAddi(w0, 2, 2, -8);                                                   // addi sp,sp,-8
    int isSd  = (w1 & 0x7F) == 0x23 && ((w1 >> 12) & 7) == 3 && ((w1 >> 15) & 0x1F) == 2 &&
                (int)(((w1 >> 7) & 0x1F) | (((w1 >> 25) & 0x7F) << 5)) == 0;              // sd rX,0(sp)
    int isLd  = (w2 & 0x7F) == 0x03 && ((w2 >> 12) & 7) == 3 && ((w2 >> 15) & 0x1F) == 2 &&
                (int)((w2 >> 20) & 0xFFF) == 0;                                           // ld rY,0(sp)
    int isInc = RvIsAddi(val, 2, 2, 8);                                                   // addi sp,sp,+8
    int rX = (w1 >> 20) & 0x1F, rY = (w2 >> 7) & 0x1F;
    if (isDec && isSd && isLd && isInc && rX == rY) {  // push rX; pop rX -> nothing (value already in rX)
      if (buf && ptr) *ptr -= 12;                      // drop the three buffered words
      *rip -= 12;
      g_pp_n = 0;
      return;                                          // the fourth word (addi sp,+8) is cancelled too
    }
  }
  if (buf && ptr) { *(U32 *)(*ptr) = val; (*ptr) += 4; }
  (*rip) += 4;
  if (g_pp_on) {
    if (g_pp_n < 3) g_pp[g_pp_n++] = val;
    else { g_pp[0] = g_pp[1]; g_pp[1] = g_pp[2]; g_pp[2] = val; }
  }
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

// Materialize an arbitrary 64-bit constant in rd. lui/addi alone sign-extends bit 31, which
// breaks every bare-metal RAM address (0x8000_0000+); zero-extend 32-bit values and build
// wider ones from two halves. Same sequence in the sizing and emit passes.
static void EmitLoadImm64(U8 *pass_buf, U8 **pass_ptr, I64 *rip, U8 rd, I64 v) {
  if (v >= -2048 && v <= 2047) {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (rd << 7) | ((v & 0xFFF) << 20));               // addi rd, zero, v
    return;
  }
  I64 lo32 = (I64)(I32)(U32)(v & 0xFFFFFFFF);
  I64 hi32 = (v - lo32) >> 32;
  if (hi32 == 0 && lo32 < 0) hi32 = 0;   /* value is a positive 32-bit quantity */
  Bool fits_i32 = (v == lo32);
  Bool fits_u32 = (v >= 0 && v <= 0xFFFFFFFFLL);
  if (!fits_i32 && !fits_u32) {
    I64 hi = (I64)(I32)(U32)((v >> 32) & 0xFFFFFFFF);
    I64 hh = (hi + 0x800) >> 12, hl = hi - (hh << 12);
    RVU32(pass_buf, pass_ptr, rip, 0x37 | (rd << 7) | ((hh & 0xFFFFF) << 12));           // lui rd, hh
    if (hl) RVU32(pass_buf, pass_ptr, rip, 0x13 | (rd << 7) | (rd << 15) | ((hl & 0xFFF) << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (rd << 7) | (1 << 12) | (rd << 15) | (32 << 20)); // slli rd, rd, 32
    I64 lh = (lo32 + 0x800) >> 12, ll = lo32 - (lh << 12);
    RVU32(pass_buf, pass_ptr, rip, 0x37 | (RV_T0 << 7) | ((lh & 0xFFFFF) << 12));        // lui t0, lh
    if (ll) RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (RV_T0 << 15) | ((ll & 0xFFF) << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (1 << 12) | (RV_T0 << 15) | (32 << 20)); // slli t0, 32
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (5 << 12) | (RV_T0 << 15) | (32 << 20)); // srli t0, 32
    RVU32(pass_buf, pass_ptr, rip, 0x33 | (rd << 7) | (rd << 15) | (RV_T0 << 20));          // add rd, rd, t0
    return;
  }
  I64 hi = (lo32 + 0x800) >> 12, lo = lo32 - (hi << 12);
  RVU32(pass_buf, pass_ptr, rip, 0x37 | (rd << 7) | ((hi & 0xFFFFF) << 12));               // lui rd, hi
  if (lo) RVU32(pass_buf, pass_ptr, rip, 0x13 | (rd << 7) | (rd << 15) | ((lo & 0xFFF) << 20)); // addi
  if (!fits_i32) {                                                                           // zero-extend
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (rd << 7) | (1 << 12) | (rd << 15) | (32 << 20));   // slli rd, 32
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (rd << 7) | (5 << 12) | (rd << 15) | (32 << 20));   // srli rd, 32
  }
}

// Typed store of a0 through rs1 (mirror of DerefLoadFromRs1).
static U32 StoreA0ToRs1(U8 pointed_to, U8 rs1) {
  U32 f3;
  switch (pointed_to) {
  case RT_I8: case RT_U8:   f3 = 0; break; /* sb */
  case RT_I16: case RT_U16: f3 = 1; break; /* sh */
  case RT_I32: case RT_U32: f3 = 2; break; /* sw */
  default:                  f3 = 3; break; /* sd */
  }
  return 0x23 | (f3 << 12) | (rs1 << 15) | (RV_A0 << 20);
}

// Struct copy for `b = a` (same class, size>8): eval stack holds [dst, src] with src on top and
// ic_data = the byte count. Pops both, copies n bytes (8-byte words then a byte tail), and leaves
// the dst address (assignment is an expression). Offsets are unrolled, so n is capped by the
// caller to fit the 12-bit load/store immediate.
static void EmitBlockCopy(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, I64 n) {
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));              // ld t1, 0(sp)  (src)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));              // addi sp,sp,8
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0<<7) | (3<<12) | (RV_SP<<15));              // ld t0, 0(sp)  (dst)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));              // addi sp,sp,8
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A5<<7) | (RV_T0<<15));                        // mv a5, t0 (save dst)
  I64 off = 0;
  for (; off + 8 <= n; off += 8) {
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2<<7) | (3<<12) | (RV_T1<<15) | (((U32)(off & 0xFFF))<<20));                       // ld t2, off(t1)
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (((U32)(off & 0x1F))<<7) | (3<<12) | (RV_T0<<15) | (RV_T2<<20) | (((U32)((off>>5)&0x7F))<<25)); // sd t2, off(t0)
  }
  for (; off < n; off++) {
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2<<7) | (0<<12) | (RV_T1<<15) | (((U32)(off & 0xFFF))<<20));                       // lb t2, off(t1)
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (((U32)(off & 0x1F))<<7) | (0<<12) | (RV_T0<<15) | (RV_T2<<20) | (((U32)((off>>5)&0x7F))<<25)); // sb t2, off(t0)
  }
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0<<7) | (RV_A5<<15));                        // mv a0, a5 (result = dst)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));          // addi sp,sp,-8
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));             // sd a0, 0(sp)
  *stack_depth -= 1;   // popped 2 (dst,src), pushed 1 (result)
}

// PC-relative call: always auipc+jalr (full ±2 GiB range, fixed 2-word size).
// A jal fast path (1 word, ±1 MiB) was tempting but unsafe here: choosing jal vs auipc+jalr per call
// changes the instruction count, and the address passes don't re-converge, so a call sitting near the
// ±1 MiB boundary is sized in one pass and emitted in another -> a truncated jal target and an
// immediate trap. Blobs are now routinely >1 MiB (many native primitives), so that boundary is hit in
// practice (it silently broke the spawn demo). A fixed 2-word encoding keeps every address stable
// regardless of distance; the one extra instruction per call is worth the guaranteed correctness.
static void EmitJalToLabel(U8 *pass_buf, U8 **pass_ptr, I64 *rip, CLabel *lb, U8 rd) {
  I64 pc = *rip;
  I64 target = lb->addr;
  I64 rel = target - pc;
  I64 hi = (rel + 0x800) >> 12;
  I64 lo = rel - (hi << 12);
  RVU32(pass_buf, pass_ptr, rip, 0x17u | ((U32)rd << 7) | (((U32)hi & 0xFFFFFu) << 12));       // auipc rd, hi
  RVU32(pass_buf, pass_ptr, rip,
        0x67u | ((U32)rd << 7) | ((U32)rd << 15) | (((U32)lo & 0xFFFu) << 20));                 // jalr  rd, lo(rd)
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

// Unary op on the eval-stack top (a0 mirrors it): pop, apply, push.
static void EmitUnaryOp(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, U32 insn) {
  if (*stack_depth > 0) {
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (3 << 12) | (RV_SP << 15));            // ld a0, 0(sp)
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));            // addi sp, sp, 8
    (*stack_depth)--;
  }
  RVU32(pass_buf, pass_ptr, rip, insn);
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));          // addi sp, sp, -8
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_SP << 15) | (RV_A0 << 20));             // sd a0, 0(sp)
  (*stack_depth)++;
}
#define RV_UNARY_MINUS (0x40000033u | (RV_A0 << 7) | (RV_A0 << 20))               /* sub a0, zero, a0 */
#define RV_LOGICAL_NOT (0x13u | (RV_A0 << 7) | (3 << 12) | (RV_A0 << 15) | (1 << 20)) /* sltiu a0, a0, 1 */
#define RV_BIT_COM     (0x13u | (RV_A0 << 7) | (4 << 12) | (RV_A0 << 15) | (0xFFFu << 20)) /* xori a0, a0, -1 */

// Compound assignment: stack holds [..., lvalue address, rhs value] (parser pushes the address,
// see EnsureLvalueAddressPushed). Load, apply `rtype` (R-type opcode with rd/rs1/rs2 = 0), store,
// and leave the new value in a0 and on the stack.
static void EmitCompoundAssign(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, U32 rtype) {
  if (*stack_depth >= 2) {
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (3 << 12) | (RV_SP << 15));            // ld t1, 0(sp)
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));            // addi sp, sp, 8
    (*stack_depth)--;
  } else {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T1 << 7) | (RV_A0 << 15));                        // mv t1, a0
  }
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_SP << 15));              // ld t0, 0(sp)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));              // addi sp, sp, 8
  if (*stack_depth > 0) (*stack_depth)--;
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (3 << 12) | (RV_T0 << 15));              // ld t2, 0(t0)
  RVU32(pass_buf, pass_ptr, rip, rtype | (RV_T2 << 7) | (RV_T2 << 15) | (RV_T1 << 20));         // op t2, t2, t1
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T0 << 15) | (RV_T2 << 20));             // sd t2, 0(t0)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (RV_T2 << 15));                          // mv a0, t2
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));          // addi sp, sp, -8
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_SP << 15) | (RV_A0 << 20));             // sd a0, 0(sp)
  (*stack_depth)++;
}
#define RV_R_ADD 0x00000033u
#define RV_R_SUB 0x40000033u
#define RV_R_MUL 0x02000033u
#define RV_R_DIV 0x02004033u
#define RV_R_AND 0x00007033u
#define RV_R_OR  0x00006033u
#define RV_R_XOR 0x00004033u
#define RV_R_SLL 0x00001033u
#define RV_R_SRA 0x40005033u
#define RV_R_REM 0x02006033u

// ---- RV64D helpers: F64 values live as raw bits in integer registers / eval-stack slots ----
#define RV_FA0 10
#define RV_FA1 11
#define RV_FMV_D_X(fd, rs)      (0xF2000053u | ((fd) << 7) | ((rs) << 15))
#define RV_FMV_X_D(rd, fs)      (0xE2000053u | ((rd) << 7) | ((fs) << 15))
#define RV_FCVT_D_L(fd, rs)     (0xD2000053u | ((fd) << 7) | (7u << 12) | ((rs) << 15) | (2u << 20))
#define RV_FCVT_L_D(rd, fs)     (0xC2000053u | ((rd) << 7) | (1u << 12) | ((fs) << 15) | (2u << 20)) /* rtz */
#define RV_FOP(f7, fd, f1, f2)  ((f7) | ((fd) << 7) | (7u << 12) | ((f1) << 15) | ((f2) << 20))
#define RV_FCMP(f3, rd, f1, f2) (0xA2000053u | ((rd) << 7) | ((f3) << 12) | ((f1) << 15) | ((f2) << 20))
// F64 compound assignment (`d *= 2.0`): load *addr and the rhs as doubles, F64-op, store back.
static void EmitF64CompoundAssign(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, U8 ic_code) {
  if (*stack_depth >= 2) {
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (3 << 12) | (RV_SP << 15));            // ld t1, 0(sp)  rhs bits
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    (*stack_depth)--;
  } else {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T1 << 7) | (RV_A0 << 15));                        // mv t1, a0
  }
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_SP << 15));              // ld t0, 0(sp)  addr
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  if (*stack_depth > 0) (*stack_depth)--;
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (3 << 12) | (RV_T0 << 15));              // ld t2, 0(t0)  *addr bits
  RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA0, RV_T2));
  RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA1, RV_T1));
  U32 fop = ic_code == IC_FADD_EQU ? 0x02000053u : ic_code == IC_FSUB_EQU ? 0x0A000053u :
            ic_code == IC_FMUL_EQU ? 0x12000053u : 0x1A000053u;
  RVU32(pass_buf, pass_ptr, rip, RV_FOP(fop, RV_FA0, RV_FA0, RV_FA1));
  RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T0 << 15) | (RV_A0 << 20));             // sd a0, 0(t0)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_SP << 15) | (RV_A0 << 20));
  (*stack_depth)++;
}
static void EmitF64Op(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, U8 ic_code) {
  if (ic_code == IC_FNEG) {
    if (*stack_depth > 0) {
      RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (3 << 12) | (RV_SP << 15));
      RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
      (*stack_depth)--;
    }
    RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA0, RV_A0));
    RVU32(pass_buf, pass_ptr, rip, 0x22000053u | (RV_FA0 << 7) | (1u << 12) | (RV_FA0 << 15) | (RV_FA0 << 20)); // fsgnjn.d
    RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0));
  } else {
    // pop right into t1, left into t0 (same order as the integer binary ops)
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (3 << 12) | (RV_SP << 15));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_SP << 15));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    if (*stack_depth >= 2) *stack_depth -= 2; else *stack_depth = 0;
    RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA0, RV_T0));
    RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA1, RV_T1));
    switch (ic_code) {
    case IC_FADD: RVU32(pass_buf, pass_ptr, rip, RV_FOP(0x02000053u, RV_FA0, RV_FA0, RV_FA1)); RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0)); break;
    case IC_FSUB: RVU32(pass_buf, pass_ptr, rip, RV_FOP(0x0A000053u, RV_FA0, RV_FA0, RV_FA1)); RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0)); break;
    case IC_FMUL: RVU32(pass_buf, pass_ptr, rip, RV_FOP(0x12000053u, RV_FA0, RV_FA0, RV_FA1)); RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0)); break;
    case IC_FDIV: RVU32(pass_buf, pass_ptr, rip, RV_FOP(0x1A000053u, RV_FA0, RV_FA0, RV_FA1)); RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0)); break;
    case IC_FMOD:  // a - trunc(a/b)*b
      RVU32(pass_buf, pass_ptr, rip, RV_FOP(0x1A000053u, 12, RV_FA0, RV_FA1));        // fdiv.d fa2, fa0, fa1
      RVU32(pass_buf, pass_ptr, rip, RV_FCVT_L_D(RV_T2, 12));                          // fcvt.l.d (rtz) t2, fa2
      RVU32(pass_buf, pass_ptr, rip, RV_FCVT_D_L(12, RV_T2));                          // fcvt.d.l fa2, t2
      RVU32(pass_buf, pass_ptr, rip, RV_FOP(0x12000053u, 12, 12, RV_FA1));             // fmul.d fa2, fa2, fa1
      RVU32(pass_buf, pass_ptr, rip, RV_FOP(0x0A000053u, RV_FA0, RV_FA0, 12));         // fsub.d fa0, fa0, fa2
      RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0)); break;
    case IC_FLESS:        RVU32(pass_buf, pass_ptr, rip, RV_FCMP(1, RV_A0, RV_FA0, RV_FA1)); break;
    case IC_FLESS_EQU:    RVU32(pass_buf, pass_ptr, rip, RV_FCMP(0, RV_A0, RV_FA0, RV_FA1)); break;
    case IC_FGREATER:     RVU32(pass_buf, pass_ptr, rip, RV_FCMP(1, RV_A0, RV_FA1, RV_FA0)); break;
    case IC_FGREATER_EQU: RVU32(pass_buf, pass_ptr, rip, RV_FCMP(0, RV_A0, RV_FA1, RV_FA0)); break;
    case IC_FEQU_EQU:     RVU32(pass_buf, pass_ptr, rip, RV_FCMP(2, RV_A0, RV_FA0, RV_FA1)); break;
    case IC_FNOT_EQU:     RVU32(pass_buf, pass_ptr, rip, RV_FCMP(2, RV_A0, RV_FA0, RV_FA1));
                          RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (4 << 12) | (RV_A0 << 15) | (1 << 20)); break; // xori 1
    default: break;
    }
  }
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_SP << 15) | (RV_A0 << 20));
  (*stack_depth)++;
}
// Convert eval-stack slot k in place (k = ic_data: 0 = top); a0 mirrors the top afterwards.
static void EmitF64Convert(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 slot, Bool to_f64) {
  U32 off = (U32)((slot * 8) & 0xFFF);
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (3 << 12) | (RV_SP << 15) | (off << 20));   // ld a0, off(sp)
  if (to_f64) {
    RVU32(pass_buf, pass_ptr, rip, RV_FCVT_D_L(RV_FA0, RV_A0));
  } else {
    RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA0, RV_A0));
    RVU32(pass_buf, pass_ptr, rip, RV_FCVT_L_D(RV_A0, RV_FA0));
  }
  if (to_f64) RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_SP << 15) | (RV_A0 << 20) | ((off & 0x1F) << 7) | ((off >> 5) << 25)); // sd a0, off(sp)
  if (slot) RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (3 << 12) | (RV_SP << 15));           // ld a0, 0(sp)
}

// ---- AOT data section for globals -------------------------------------------------------
// Lay every HTT_GLBL_VAR out after code+strings (offset in data_addr_rip); global-address
// immediates then become auipc-relative and the initial values are copied into the blob.
static void AOTLayoutGlobals(Compiler *cc) {
  I64 off = 0;
  if (!cc->hash_table) return;
  for (I64 i = 0; i <= cc->hash_table->mask; i++) {
    for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next) {
      if (!(e->type & HTT_GLBL_VAR)) continue;
      CHashGlblVar *g = (CHashGlblVar *)e;
      I64 sz = g->size > 0 ? g->size : 8;
      g->data_addr_rip = off;
      off += (sz + 7) & ~7LL;
    }
  }
  cc->aot_data_size = off;
  cc->aot_data_layout = TRUE;
}
static CHashGlblVar *AOTGlobalByAddr(Compiler *cc, I64 addr) {
  if (!cc->hash_table) return NULL;
  for (I64 i = 0; i <= cc->hash_table->mask; i++)
    for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next)
      if ((e->type & HTT_GLBL_VAR)) {
        CHashGlblVar *g = (CHashGlblVar *)e;
        I64 base = (I64)g->data_addr, sz = g->size > 0 ? g->size : 8;
        if (addr >= base && addr < base + sz) return g;   // interior addresses: aggregate elements/members
      }
  return NULL;
}
// Address of a global into rd: auipc-relative into the data section (AOT) or absolute (REPL).
static void EmitGlobalAddrOff(U8 *pass_buf, U8 **pass_ptr, I64 *rip, Compiler *cc, U8 rd, CHashGlblVar *g, I64 data_base, I64 off);
static void EmitGlobalAddr(U8 *pass_buf, U8 **pass_ptr, I64 *rip, Compiler *cc, U8 rd, CHashGlblVar *g, I64 data_base) {
  EmitGlobalAddrOff(pass_buf, pass_ptr, rip, cc, rd, g, data_base, 0);
}
static void EmitGlobalAddrOff(U8 *pass_buf, U8 **pass_ptr, I64 *rip, Compiler *cc, U8 rd, CHashGlblVar *g, I64 data_base, I64 off) {
  if (cc->aot_data_layout && g) {
    I64 rel = pass_buf ? (data_base + g->data_addr_rip + off - *rip) : 0;
    I64 hi = (rel + 0x800) >> 12, lo = rel - (hi << 12);
    RVU32(pass_buf, pass_ptr, rip, 0x17 | (rd << 7) | (((U32)hi & 0xFFFFF) << 12));           // auipc
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (rd << 7) | (rd << 15) | (((U32)lo & 0xFFF) << 20));  // addi
  } else {
    EmitLoadImm64(pass_buf, pass_ptr, rip, rd, (g ? (I64)g->data_addr : 0) + off);
  }
}
// ---- unsigned integer ops ---------------------------------------------------------------
static void EmitUnsignedOp(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, U8 ic_code) {
  if (*stack_depth < 2) {   // mirror the integer ops: a0 holds the right operand not yet pushed
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_SP << 15) | (RV_A0 << 20));
    (*stack_depth)++;
  }
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (3 << 12) | (RV_SP << 15));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_SP << 15));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  *stack_depth -= 2;
  #define RTYPE(f7, f3, rd, r1, r2) ((f7) | ((rd) << 7) | ((f3) << 12) | ((r1) << 15) | ((r2) << 20) | 0x33u)
  switch (ic_code) {
  case IC_UDIV: RVU32(pass_buf, pass_ptr, rip, RTYPE(0x02000000u, 5, RV_A0, RV_T0, RV_T1)); break;   // divu
  case IC_UMOD: RVU32(pass_buf, pass_ptr, rip, RTYPE(0x02000000u, 7, RV_A0, RV_T0, RV_T1)); break;   // remu
  case IC_USHR: RVU32(pass_buf, pass_ptr, rip, RTYPE(0, 5, RV_A0, RV_T0, RV_T1)); break;             // srl
  case IC_ULESS:        RVU32(pass_buf, pass_ptr, rip, RTYPE(0, 3, RV_A0, RV_T0, RV_T1)); break;     // sltu
  case IC_UGREATER:     RVU32(pass_buf, pass_ptr, rip, RTYPE(0, 3, RV_A0, RV_T1, RV_T0)); break;
  case IC_ULESS_EQU:    RVU32(pass_buf, pass_ptr, rip, RTYPE(0, 3, RV_A0, RV_T1, RV_T0));
                        RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (4 << 12) | (RV_A0 << 15) | (1 << 20)); break;
  case IC_UGREATER_EQU: RVU32(pass_buf, pass_ptr, rip, RTYPE(0, 3, RV_A0, RV_T0, RV_T1));
                        RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (4 << 12) | (RV_A0 << 15) | (1 << 20)); break;
  default: break;
  }
  #undef RTYPE
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_SP << 15) | (RV_A0 << 20));
  (*stack_depth)++;
}
// ---- try/catch/throw --------------------------------------------------------------------
// Handler context (32 bytes, a compiler temp in the try's frame): {prev, sp, s0, catch pc}.
static void EmitTryEnter(U8 *pass_buf, U8 **pass_ptr, I64 *rip, Compiler *cc, CLabel *catch_lb, I64 data_base) {
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T2 << 7) | (RV_A0 << 15));                                   // mv t2, a0 (ctx)
  EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T1, cc->try_top_var, data_base);                        // t1 = &__try_top
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_T1 << 15));                       // ld t0, 0(t1)
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T2 << 15) | (RV_T0 << 20));                      // sd t0, 0(t2)  prev
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T2 << 15) | (RV_SP << 20) | (8 << 7));           // sd sp, 8(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T2 << 15) | (RV_S0 << 20) | (16 << 7));          // sd s0, 16(t2)
  I64 rel = pass_buf ? (catch_lb->addr - *rip) : 0;
  I64 hi = (rel + 0x800) >> 12, lo = rel - (hi << 12);
  RVU32(pass_buf, pass_ptr, rip, 0x17 | (RV_T0 << 7) | (((U32)hi & 0xFFFFF) << 12));                    // auipc t0, catch
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (RV_T0 << 15) | (((U32)lo & 0xFFF) << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T2 << 15) | (RV_T0 << 20) | (24 << 7));          // sd t0, 24(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T1 << 15) | (RV_T2 << 20));                      // __try_top = ctx
}
// PUSHFD/POPFD/CLI/STI as bare statements: HolyC lets kernel code use these x86 opcodes
// directly. On RISC-V they act on mstatus (MIE = bit 3); PUSHFD/POPFD go through the stack.
static void EmitSysIntrinsic(U8 *pass_buf, U8 **pass_ptr, I64 *rip, int ic_code) {
  const U32 MSTATUS = 0x300;
  switch (ic_code) {
    case IC_CLI: RVU32(pass_buf, pass_ptr, rip, 0x73 | (7 << 12) | (8 << 15) | (MSTATUS << 20)); break; // csrci mstatus,8
    case IC_STI: RVU32(pass_buf, pass_ptr, rip, 0x73 | (6 << 12) | (8 << 15) | (MSTATUS << 20)); break; // csrsi mstatus,8
    case IC_PUSHFD:
      RVU32(pass_buf, pass_ptr, rip, 0x73 | (RV_T0 << 7) | (2 << 12) | (MSTATUS << 20));                 // csrr t0,mstatus
      RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | ((U32)(-8 & 0xFFF) << 20));   // addi sp,sp,-8
      RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_SP << 15) | (RV_T0 << 20));                  // sd t0,0(sp)
      break;
    case IC_POPFD:
      RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_SP << 15));                   // ld t0,0(sp)
      RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));                   // addi sp,sp,8
      RVU32(pass_buf, pass_ptr, rip, 0x73 | (1 << 12) | (RV_T0 << 15) | (MSTATUS << 20));                // csrw mstatus,t0
      break;
  }
}
// Chained relations (`a<b<c`): [a,b] -> [(a cmp b), b], the middle operand stays for the next
// compare; IC_CHAIN_AND folds [x,y,z] -> [x&y, z]. Same push/pop discipline as the compares.
static void EmitChainCmp(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *depth, int cmp) {
  if (*depth == 1) {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (3 << 12));
    (*depth)++;
  }
  if (*depth < 2) return;
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (3 << 12) | (RV_SP << 15));              // t1 = b
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_SP << 15));              // t0 = a
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  *depth -= 2;
  if (cmp == IC_LESS) {
    RVU32(pass_buf, pass_ptr, rip, 0x33 | (RV_A0 << 7) | (0x2 << 12) | (RV_T0 << 15) | (RV_T1 << 20));
  } else if (cmp == IC_GREATER) {
    RVU32(pass_buf, pass_ptr, rip, 0x33 | (RV_A0 << 7) | (0x2 << 12) | (RV_T1 << 15) | (RV_T0 << 20));
  } else if (cmp == IC_LESS_EQU) {
    RVU32(pass_buf, pass_ptr, rip, 0x33 | (RV_A0 << 7) | (0x2 << 12) | (RV_T1 << 15) | (RV_T0 << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (4 << 12) | (RV_A0 << 15) | (1 << 20));
  } else {
    RVU32(pass_buf, pass_ptr, rip, 0x33 | (RV_A0 << 7) | (0x2 << 12) | (RV_T0 << 15) | (RV_T1 << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (4 << 12) | (RV_A0 << 15) | (1 << 20));
  }
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));          // push r
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (3 << 12));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));          // push b
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_T1 << 20) | (3 << 12));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (RV_T1 << 15));                          // a0 = b
  *depth += 2;
}
static void EmitChainAnd(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *depth) {
  if (*depth == 2) {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (3 << 12));
    (*depth)++;
  }
  if (*depth < 3) return;
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (3 << 12) | (RV_SP << 15));              // t2 = z
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (3 << 12) | (RV_SP << 15));              // t1 = y
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_SP << 15));              // t0 = x
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  *depth -= 3;
  RVU32(pass_buf, pass_ptr, rip, 0x33 | (RV_A0 << 7) | (7 << 12) | (RV_T0 << 15) | (RV_T1 << 20));   // a0 = x & y
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (3 << 12));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_T2 << 20) | (3 << 12));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (RV_T2 << 15));                          // a0 = z
  *depth += 2;
}
// rd = address of a label in this unit (function pointers are code addresses).
static void EmitLabelAddr(U8 *pass_buf, U8 **pass_ptr, I64 *rip, CLabel *lb, U8 rd) {
  I64 rel = lb->addr - *rip;
  I64 hi = (rel + 0x800) >> 12;
  I64 lo = rel - (hi << 12);
  RVU32(pass_buf, pass_ptr, rip, 0x17u | ((U32)rd << 7) | (((U32)hi & 0xFFFFFu) << 12));          // auipc rd, hi
  RVU32(pass_buf, pass_ptr, rip, 0x13u | ((U32)rd << 7) | ((U32)rd << 15) | (((U32)lo & 0xFFFu) << 20)); // addi rd, rd, lo
}
// rd = rs + imm for any 32-bit imm (frames beyond the 12-bit addi range use lui/addi/add via t0).
static void EmitAddImm(U8 *pass_buf, U8 **pass_ptr, I64 *rip, int rd, int rs, I64 imm) {
  if (imm >= -2048 && imm <= 2047) {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | ((U32)rd << 7) | ((U32)rs << 15) | (((U32)imm & 0xFFF) << 20));
    return;
  }
  I64 hi = (imm + 0x800) >> 12, lo = imm - (hi << 12);
  RVU32(pass_buf, pass_ptr, rip, 0x37 | (RV_T0 << 7) | (((U32)hi & 0xFFFFF) << 12));                    // lui t0, hi
  if (lo) RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (RV_T0 << 15) | (((U32)lo & 0xFFF) << 20)); // addi t0, t0, lo
  RVU32(pass_buf, pass_ptr, rip, 0x33 | ((U32)rd << 7) | ((U32)rs << 15) | (RV_T0 << 20));               // add rd, rs, t0
}
// Unconditional jump to a label: `jal zero` reaches ±1 MB; a farther target uses auipc+jalr
// through t0 (t0 is caller-saved and free at a jump point).
static void EmitJump(U8 *pass_buf, U8 **pass_ptr, I64 *rip, CLabel *lb) {
  I64 offset = lb->addr - *rip;
  if (offset >= -(1 << 20) && offset < (1 << 20)) {
    RVU32(pass_buf, pass_ptr, rip, 0x6F | (((U32)(offset >> 12) & 0xFF) << 12) | (((U32)(offset >> 11) & 1) << 20) |
          (((U32)(offset >> 1) & 0x3FF) << 21) | (((U32)(offset >> 20) & 1) << 31));
    return;
  }
  I64 rel = lb->addr - *rip;
  I64 hi = (rel + 0x800) >> 12, lo = rel - (hi << 12);
  RVU32(pass_buf, pass_ptr, rip, 0x17 | (RV_T0 << 7) | (((U32)hi & 0xFFFFF) << 12));                 // auipc t0, hi
  RVU32(pass_buf, pass_ptr, rip, 0x67 | (RV_ZERO << 7) | (RV_T0 << 15) | (((U32)lo & 0xFFF) << 20)); // jalr zero, lo(t0)
}

// Conditional branch on a0 to a label, relaxed for range: a B-type beq/bne reaches ±4 KB; a
// larger target uses the inverse branch over a `jal zero,target` (±1 MB). `br_zero` picks beq.
static void EmitCondBranch(U8 *pass_buf, U8 **pass_ptr, I64 *rip, bool br_zero, CLabel *lb) {
  I64 offset = lb->addr - *rip;
  if (offset >= -4096 && offset <= 4094) {
    U32 f3 = br_zero ? 0u : (1u << 12);
    RVU32(pass_buf, pass_ptr, rip, 0x63 | f3 | (((U32)(offset >> 11) & 1) << 7) | (((U32)(offset >> 1) & 0xF) << 8) |
          (RV_A0 << 15) | (RV_ZERO << 20) | (((U32)(offset >> 5) & 0x3F) << 25) | (((U32)(offset >> 12) & 1) << 31));
    return;
  }
  // Inverse short branch over the long jump: `b{ne,eq} a0,zero,+8; jal zero,target`.
  U32 inv = br_zero ? (1u << 12) : 0u;   // BR_ZERO → skip when a0 != 0
  RVU32(pass_buf, pass_ptr, rip, 0x63 | inv | (0 << 7) | (4 << 8) | (RV_A0 << 15) | (RV_ZERO << 20));  // to +8 (imm=8)
  I64 joff = lb->addr - *rip;
  RVU32(pass_buf, pass_ptr, rip, 0x6F | (((U32)(joff >> 12) & 0xFF) << 12) | (((U32)(joff >> 11) & 1) << 20) |
        (((U32)(joff >> 1) & 0x3FF) << 21) | (((U32)(joff >> 20) & 1) << 31));  // jal zero, target
}
static void EmitTryLeave(U8 *pass_buf, U8 **pass_ptr, I64 *rip, Compiler *cc, I64 data_base) {
  EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T1, cc->try_top_var, data_base);
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (3 << 12) | (RV_T1 << 15));                       // ld t2, 0(t1)  ctx
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_T2 << 15));                       // ld t0, 0(t2)  prev
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T1 << 15) | (RV_T0 << 20));                      // __try_top = prev
}
static void EmitThrow(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, Compiler *cc, I64 data_base) {
  if (*stack_depth > 0) {                                                                                 // value -> a0
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (3 << 12) | (RV_SP << 15));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    (*stack_depth)--;
  }
  EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T1, cc->except_ch_var, data_base);
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T1 << 15) | (RV_A0 << 20));                      // except_ch = a0
  EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T1, cc->try_top_var, data_base);
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (3 << 12) | (RV_T1 << 15));                       // ld t2, 0(t1)
  RVU32(pass_buf, pass_ptr, rip, 0x63 | (1 << 12) | (RV_T2 << 15) | (4 << 8));                           // bnez t2, +8
  RVU32(pass_buf, pass_ptr, rip, 0x00100073);                                                            // ebreak: no handler
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_T2 << 15));                       // ld t0, 0(t2) prev
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T1 << 15) | (RV_T0 << 20));                      // __try_top = prev
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_SP << 7) | (3 << 12) | (RV_T2 << 15) | (8 << 20));           // ld sp, 8(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_S0 << 7) | (3 << 12) | (RV_T2 << 15) | (16 << 20));          // ld s0, 16(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_T2 << 15) | (24 << 20));          // ld t0, 24(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x67 | (RV_T0 << 15));                                                  // jr t0
}

// ++/-- : IC_PP_/IC_MM_ (pre) and IC__PP/IC__MM (post). The operand address is in a0 (IC_LEA
// leaves it there without pushing; the parser retracts any auto-deref). Result value goes to a0
// and onto the eval stack, like IC_DEREF.
static void EmitIncDec(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, I64 delta, Bool post) {
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (RV_A0 << 15));                          // mv t0, a0
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (3 << 12) | (RV_T0 << 15));              // ld t1, 0(t0)
  if (delta >= -2048 && delta <= 2047) {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T2 << 7) | (RV_T1 << 15) | ((delta & 0xFFF) << 20)); // addi t2, t1, delta
  } else {   // pointer step of a large struct: build the constant, then add
    EmitLoadImm64(pass_buf, pass_ptr, rip, RV_T2, delta);
    RVU32(pass_buf, pass_ptr, rip, 0x33 | (RV_T2 << 7) | (RV_T1 << 15) | (RV_T2 << 20));         // add t2, t1, t2
  }
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_T0 << 15) | (RV_T2 << 20));             // sd t2, 0(t0)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | ((post ? RV_T1 : RV_T2) << 15));         // mv a0, old/new
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));          // addi sp, sp, -8
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (3 << 12) | (RV_SP << 15) | (RV_A0 << 20));             // sd a0, 0(sp)
  (*stack_depth)++;
}

static void EmitGlobalAddr(U8 *pass_buf, U8 **pass_ptr, I64 *rip, Compiler *cc, U8 rd, CHashGlblVar *g, I64 data_base);
// Shared: argument shuffle for IC_CALL / IC_CALL_INDIRECT2, then PC-rel or host-indirect tail.
static void EmitCallArgsAndInvoke(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth,
                                  Compiler *cc, CLabel *pc_target, I64 *exe_addr_host_ptr, I64 arg_count,
                                  CHashGlblVar *import_var) {

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
  } else if (import_var && cc->aot_data_layout) {
    // Runtime import: the slot lives in the data section; the loader fills it by name.
    EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T0, import_var, cc->aot_data_base);
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (3 << 12) | (RV_T0 << 15));
    RVU32(pass_buf, pass_ptr, rip, 0x67 | (RV_RA << 7) | (RV_T0 << 15));
  } else {
    I64 addr = (I64)exe_addr_host_ptr;
    // addi sign-extends its 12-bit immediate: round hi up when lo >= 0x800.
    U32 hi = (U32)(((addr + 0x800) >> 12) & 0xFFFFF);
    RVU32(pass_buf, pass_ptr, rip, 0x37 | (RV_T0 << 7) | (hi << 12));
    I64 lo = addr - (I64)((addr + 0x800) & ~0xFFFLL);
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

// ---- Optimization passes on the IC stream (safe: the emitter re-resolves labels each pass) ----
// Tier 2: constant folding + algebraic identities. IC_IMM_I64 auto-pushes, so `2+3` is the node
// sequence IMM(2), IMM(3), ADD -- fold adjacent IMM;IMM;binop to one IMM, and drop identity ops
// (x+0, x*1, ...). Only sign-agnostic ops are folded (ADD/SUB/MUL keep the same low 64 bits for
// signed and unsigned; AND/OR/XOR are bitwise) -- DIV/MOD/shifts are left alone to avoid a
// signedness mistake. Gated on cc->optimize.
static int IcFoldBinop(U8 op, I64 a, I64 b, int *ok) {
  *ok = 1;
  switch (op) {
    case IC_ADD: return a + b;
    case IC_SUB: return a - b;
    case IC_MUL: return a * b;
    case IC_AND: return a & b;
    case IC_OR:  return a | b;
    case IC_XOR: return a ^ b;
    default: *ok = 0; return 0;
  }
}
static void IcOptimize(Compiler *cc) {
  if (!cc->optimize) return;
  int changed = 1;
  while (changed) {
    changed = 0;
    for (CIntermediateCode *ic = cc->ic_head; ic; ic = ic->next) {
      CIntermediateCode *n1 = ic->next, *n2 = n1 ? n1->next : (CIntermediateCode *)0;
      // Constant fold: IMM(a); IMM(b); binop -> IMM(a op b)
      if (ic->ic_code == IC_IMM_I64 && !(ic->ic_flags & ICF_GLBL_ADDR) &&
          n1 && n1->ic_code == IC_IMM_I64 && !(n1->ic_flags & ICF_GLBL_ADDR) && n2) {
        int ok; I64 r = IcFoldBinop(n2->ic_code, ic->ic_data, n1->ic_data, &ok);
        if (ok) {
          ic->ic_data = r;                       // ic becomes IMM(r); splice out n1 and n2
          ic->next = n2->next;
          if (n2->next) n2->next->last = ic; else cc->ic_tail = ic;
          changed = 1; break;
        }
      }
      // Algebraic identity: IMM(id); binop -> drop both (the left operand stays pushed). x+0,
      // x-0, x|0, x^0 (id 0); x*1, x/1 (id 1) -- all identities for signed AND unsigned.
      if (ic->ic_code == IC_IMM_I64 && !(ic->ic_flags & ICF_GLBL_ADDR) && n1 && ic->last) {
        U8 op = n1->ic_code; I64 v = ic->ic_data; int drop = 0;
        if ((op == IC_ADD || op == IC_SUB || op == IC_OR || op == IC_XOR) && v == 0) drop = 1;
        else if ((op == IC_MUL || op == IC_DIV) && v == 1) drop = 1;
        if (drop) {
          ic->last->next = n1->next;
          if (n1->next) n1->next->last = ic->last; else cc->ic_tail = ic->last;
          changed = 1; break;
        }
      }
    }
  }
}

U8 *CompileAOT(Compiler *cc, I64 *code_size) {
  IcOptimize(cc);
  g_pp_on = cc->optimize;   // Tier 1 push/pop peephole in RVU32
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
    g_pp_n = 0;   // reset the push/pop peephole window each pass
    
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
        g_pp_n = 0;   // don't cancel a push/pop across a branch target
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
          EmitAddImm(pass_buf, &pass_ptr, &rip, RV_SP, RV_SP, -frame_size);
          // sd ra, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (3<<12) | (RV_SP<<15) | (RV_RA<<20));
          // sd s0, 8(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (8<<7) | (3<<12) | (RV_SP<<15) | (RV_S0<<20));
          // addi s0, sp, frame_size
          EmitAddImm(pass_buf, &pass_ptr, &rip, RV_S0, RV_SP, frame_size);
          
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
          
          // addi sp, s0, -frame_size — sp from the frame pointer, so eval-stack residue cannot
          // shift the restores below.
          EmitAddImm(pass_buf, &pass_ptr, &rip, RV_SP, RV_S0, -frame_size_leave);
          // ld ra, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_RA<<7) | (3<<12) | (RV_SP<<15));
          // ld s0, 8(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_S0<<7) | (3<<12) | (RV_SP<<15) | (8<<20));
          // addi sp, sp, frame_size
          EmitAddImm(pass_buf, &pass_ptr, &rip, RV_SP, RV_SP, frame_size_leave);
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
      case IC_IMM_F64:  // F64 travels as its raw 64-bit pattern in integer registers / eval stack
        if (ic->ic_flags == ICF_GLBL_ADDR && cc->aot_data_layout) {
          {
            CHashGlblVar *g = AOTGlobalByAddr(cc, ic->ic_data);
            EmitGlobalAddrOff(pass_buf, &pass_ptr, &rip, cc, RV_A0, g, 0, g ? ic->ic_data - (I64)g->data_addr : 0);
          }
        } else {
          // Load immediate into a0 (full 64-bit; see EmitLoadImm64)
          EmitLoadImm64(pass_buf, &pass_ptr, &rip, RV_A0, ic->ic_data);
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
      case IC_BLOCK_COPY:
        EmitBlockCopy(pass_buf, &pass_ptr, &rip, &stack_depth_pass, ic->ic_data);
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
          RVU32(pass_buf, &pass_ptr, &rip, StoreA0ToRs1(ic->arg1_type_pointed_to, RV_T0)); // typed store a0 -> (t0)
          // Assignment is an expression: leave the value in a0 and on the eval stack (IC_END_EXP drops it).
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_pass++;
        } else {
          // Fallback: no address on stack, assume address currently in a0
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (RV_A0<<15));
          RVU32(pass_buf, &pass_ptr, &rip, StoreA0ToRs1(ic->arg1_type_pointed_to, RV_T0)); // typed store a0 -> (t0)
          // Assignment is an expression: leave the value in a0 and on the eval stack (IC_END_EXP drops it).
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_pass++;
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
          EmitCondBranch(pass_buf, &pass_ptr, &rip, true, lb);
          lb->sd = stack_depth_pass; lb->sd_set = true;   // the taken path reaches lb at this depth; fall-through keeps it
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
          EmitCondBranch(pass_buf, &pass_ptr, &rip, false, lb);
          lb->sd = stack_depth_pass; lb->sd_set = true;
        }
        break;
      case IC_JMP:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          lb->sd = stack_depth_pass; lb->sd_set = true;   // the jump reaches lb at this depth
          EmitJump(pass_buf, &pass_ptr, &rip, lb);
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
          I64 arg_count = ic->ic_flags;  // set by the parser on this call IC

          // Pop pointer to exe_addr field into t1 (t0/t2 used by arg shuffle)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_pass--;

          if (arg_count > 8) {
            EmitPrepareGt8CallArgs(pass_buf, &pass_ptr, &rip, arg_count);
          } else if (arg_count >= 2 && arg_count <= 8) {
            EmitLoadArgsFromEvalStack(pass_buf, &pass_ptr, &rip, &stack_depth_pass, arg_count);
          } else if (arg_count == 1) {
            // The pointer load above clobbered a0: pop the single argument into it.
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
            stack_depth_pass--;
          }

          RVU32(pass_buf, &pass_ptr, &rip, 0x67 | (RV_RA<<7) | (RV_T1<<15));   // jalr ra, t1: the pointer is the code address

          if (arg_count > 8) {
            I64 out_sz = (arg_count - 8) * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((out_sz & 0xFFF)<<20));
            I64 eval_sz = arg_count * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((eval_sz & 0xFFF)<<20));
            stack_depth_pass -= arg_count;
          }

          // Return value to a0 and the eval stack (same convention as EmitCallArgsAndInvoke).
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_pass++;
        }
        break;
      case IC_CALL_INDIRECT2:
        EmitCallArgsAndInvoke(pass_buf, &pass_ptr, &rip, &stack_depth_pass, cc, NULL, (I64 *)ic->ic_data, ic->ic_flags, (CHashGlblVar *)ic->ic_class);
        break;
      case IC_CALL:
        EmitCallArgsAndInvoke(pass_buf, &pass_ptr, &rip, &stack_depth_pass, cc, (CLabel *)ic->ic_data, NULL, ic->ic_flags, NULL);
        break;
      case IC_UNARY_MINUS: EmitUnaryOp(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_UNARY_MINUS); break;
      case IC_NOT:         EmitUnaryOp(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_LOGICAL_NOT); break;
      case IC_COM:         EmitUnaryOp(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_BIT_COM); break;
      case IC_ADDR:
        // Address is in a0 (the parser retracted the auto-deref after IC_LEA); publish it.
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (3<<12) | (RV_SP<<15) | (RV_A0<<20));
        stack_depth_pass++;
        break;
      case IC_ADD_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_ADD); break;
      case IC_SUB_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_SUB); break;
      case IC_MUL_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_MUL); break;
      case IC_DIV_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_DIV); break;
      case IC_AND_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_AND); break;
      case IC_OR_EQU:  EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_OR);  break;
      case IC_XOR_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_XOR); break;
      case IC_SHL_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_SLL); break;
      case IC_SHR_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_SRA); break;
      case IC_MOD_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, RV_R_REM); break;
      case IC_FADD_EQU: case IC_FSUB_EQU: case IC_FMUL_EQU: case IC_FDIV_EQU: EmitF64CompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_pass, ic->ic_code); break;
      case IC_PAUSE:   RVU32(pass_buf, &pass_ptr, &rip, 0x13); break;
      case IC_FN_ADDR:
        EmitLabelAddr(pass_buf, &pass_ptr, &rip, (CLabel *)ic->ic_data, RV_A0);
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        stack_depth_pass++;
        break;
      case IC_PC:      // `$$`: address of this instruction, pushed like an immediate
        RVU32(pass_buf, &pass_ptr, &rip, 0x17 | (RV_A0 << 7));                                        // auipc a0, 0
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        stack_depth_pass++;
        break;
      case IC_HLT:     RVU32(pass_buf, &pass_ptr, &rip, 0x10500073); break;   // wfi
      case IC_INT:     RVU32(pass_buf, &pass_ptr, &rip, 0x00100073); break;   // ebreak
      case IC_CHAIN_CMP: EmitChainCmp(pass_buf, &pass_ptr, &rip, &stack_depth_pass, (int)ic->ic_data); break;
      case IC_CHAIN_AND: EmitChainAnd(pass_buf, &pass_ptr, &rip, &stack_depth_pass); break;
      case IC_FADD: case IC_FSUB: case IC_FMUL: case IC_FDIV:
      case IC_FLESS: case IC_FLESS_EQU: case IC_FGREATER: case IC_FGREATER_EQU:
      case IC_FEQU_EQU: case IC_FNOT_EQU: case IC_FNEG: case IC_FMOD:
        EmitF64Op(pass_buf, &pass_ptr, &rip, &stack_depth_pass, ic->ic_code);
        break;
      case IC_TO_F64: EmitF64Convert(pass_buf, &pass_ptr, &rip, ic->ic_data, TRUE);  break;
      case IC_TO_I64: EmitF64Convert(pass_buf, &pass_ptr, &rip, ic->ic_data, FALSE); break;
      case IC_UDIV: case IC_UMOD: case IC_USHR:
      case IC_ULESS: case IC_ULESS_EQU: case IC_UGREATER: case IC_UGREATER_EQU:
        EmitUnsignedOp(pass_buf, &pass_ptr, &rip, &stack_depth_pass, ic->ic_code);
        break;
      case IC_TRY_ENTER: EmitTryEnter(pass_buf, &pass_ptr, &rip, cc, (CLabel *)ic->ic_data, 0); break;
      case IC_TRY_LEAVE: EmitTryLeave(pass_buf, &pass_ptr, &rip, cc, 0); break;
      case IC_THROW:     EmitThrow(pass_buf, &pass_ptr, &rip, &stack_depth_pass, cc, 0); break;
      case IC_CLI: case IC_STI: case IC_PUSHFD: case IC_POPFD: EmitSysIntrinsic(pass_buf, &pass_ptr, &rip, ic->ic_code); break;
      case IC_STR_CONST: {
        // PC-relative address of the literal; the bytes are appended after the code.
        StringLiteral *sl = (StringLiteral *)ic->ic_data;
        I64 rel = pass_buf ? (sl->offset - rip) : 0;
        I64 hi = (rel + 0x800) >> 12, lo = rel - (hi << 12);
        RVU32(pass_buf, &pass_ptr, &rip, 0x17 | (RV_A0<<7) | (((U32)hi & 0xFFFFF)<<12));          // auipc a0, hi
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_A0<<15) | (((U32)lo & 0xFFF)<<20)); // addi a0, a0, lo
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        stack_depth_pass++;
        break;
      }
      case IC_PP_:  EmitIncDec(pass_buf, &pass_ptr, &rip, &stack_depth_pass,  (ic->ic_data ? ic->ic_data : 1), FALSE); break;
      case IC_MM_:  EmitIncDec(pass_buf, &pass_ptr, &rip, &stack_depth_pass, -(ic->ic_data ? ic->ic_data : 1), FALSE); break;
      case IC__PP:  EmitIncDec(pass_buf, &pass_ptr, &rip, &stack_depth_pass,  (ic->ic_data ? ic->ic_data : 1), TRUE);  break;
      case IC__MM:  EmitIncDec(pass_buf, &pass_ptr, &rip, &stack_depth_pass, -(ic->ic_data ? ic->ic_data : 1), TRUE);  break;
      case IC_END_EXP:
        // End of expression statement: discard residual eval-stack slots so sp is back at
        // the frame base (the epilogue/ret loads are sp-relative). Keep the top value in a0
        // — it is the REPL's Fs->answer via the trailing IC_RETURN_VAL2.
        if (stack_depth_pass > 0) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15)); // ld a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (((stack_depth_pass * 8) & 0xFFF)<<20)); // addi sp, sp, depth*8
        }
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
        { CLabel *lb = (CLabel*)ic->ic_data; if (lb->sd_set) stack_depth_pass = lb->sd; }
        break;
      case IC_NOP1:
      case IC_NOP2:
        // Explicit no-op – leave stack depth unchanged
        break;
      case IC_RAW_RV:
        RVU32(pass_buf, &pass_ptr, &rip, (U32)ic->ic_data);   // pre-assembled RISC-V word (x86 translation)
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
            // Epilogue: restore ra/s0 (sp from the frame pointer, s0 = entry sp + 16)
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_S0<<15) | (0xFF0<<20)); // addi sp, s0, -16
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
#ifndef BARE_METAL
  if (getenv("HOLYC_TRACE")) {
    // A branch to a label whose IC_LABEL was never emitted keeps a stale addr → wrong target.
    for (CIntermediateCode *jc = cc->ic_head; jc; jc = jc->next) {
      if (jc->ic_code == IC_JMP || jc->ic_code == IC_BR_ZERO || jc->ic_code == IC_BR_NOT_ZERO) {
        CLabel *tl = (CLabel *)jc->ic_data;
        if (tl && !tl->defined)
          fprintf(stderr, "[trace] branch (ic %#x) to UNDEFINED label %p '%s' addr=%#llx\n", jc->ic_code, (void *)tl, tl->name ? tl->name : "(anon)", (long long)tl->addr);
      }
    }
  }
#endif

  // Lay out this unit's string literals right after the code (8-aligned).
  I64 str_base = (rip + 7) & ~7LL, str_total = 0;
  for (StringLiteral *sl = cc->strings; sl; sl = sl->next) {
    I64 len = sl->len;
    if (len == 0) while (sl->str[len]) len++;
    sl->offset = str_base + str_total;
    str_total += len + 1;
  }
  I64 data_base = (str_base + str_total + 7) & ~7LL;
  I64 data_total = cc->aot_data_layout ? cc->aot_data_size : 0;
  cc->aot_data_base = data_base;
  // Import directory trailer: {slot, name[24]} per used runtime import + {count, magic}.
  I64 import_cnt = 0;
  if (cc->aot_data_layout && cc->hash_table) {
    for (I64 i = 0; i <= cc->hash_table->mask; i++)
      for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next)
        if ((e->type & HTT_GLBL_VAR) && e->str && e->str[0] == '_' && e->str[1] == '_' && e->str[2] == 'i' && e->str[3] == 'm' && e->str[4] == 'p' && e->use_cnt > 0 && !((CHashGlblVar *)e)->self_resolved)
          import_cnt++;
  }
  I64 dir_total = import_cnt ? import_cnt * 32 + 16 : 0;
  I64 buf_sz = data_base + data_total + dir_total + 256;
  if (buf_sz < 64) buf_sz = 64;
  U8 *buffer = malloc((size_t)buf_sz);
  if (!buffer) return NULL;

  // After convergence, do one final pass with emission enabled
  if (pass_buf == NULL) {
  pass_buf = buffer;
  pass_ptr = buffer;
  rip = 0;
  g_pp_n = 0;   // the final emission pass is a second emit loop -- reset its peephole window too
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
          EmitAddImm(pass_buf, &pass_ptr, &rip, RV_SP, RV_SP, -frame_size);
          // sd ra, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (3<<12) | (RV_SP<<15) | (RV_RA<<20));
          // sd s0, 8(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (8<<7) | (3<<12) | (RV_SP<<15) | (RV_S0<<20));
          // addi s0, sp, frame_size
          EmitAddImm(pass_buf, &pass_ptr, &rip, RV_S0, RV_SP, frame_size);
          
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
          
          // addi sp, s0, -frame_size — sp from the frame pointer, so eval-stack residue cannot
          // shift the restores below.
          EmitAddImm(pass_buf, &pass_ptr, &rip, RV_SP, RV_S0, -frame_size_leave);
          // ld ra, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_RA<<7) | (3<<12) | (RV_SP<<15));
          // ld s0, 8(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_S0<<7) | (3<<12) | (RV_SP<<15) | (8<<20));
          // addi sp, sp, frame_size
          EmitAddImm(pass_buf, &pass_ptr, &rip, RV_SP, RV_SP, frame_size_leave);
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
      case IC_IMM_F64:  // F64 travels as its raw 64-bit pattern in integer registers / eval stack
        if (ic->ic_flags == ICF_GLBL_ADDR && cc->aot_data_layout) {
          {
            CHashGlblVar *g = AOTGlobalByAddr(cc, ic->ic_data);
            EmitGlobalAddrOff(pass_buf, &pass_ptr, &rip, cc, RV_A0, g, data_base, g ? ic->ic_data - (I64)g->data_addr : 0);
          }
        } else {
          // Load immediate into a0 (full 64-bit; see EmitLoadImm64)
          EmitLoadImm64(pass_buf, &pass_ptr, &rip, RV_A0, ic->ic_data);
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
      case IC_BLOCK_COPY:
        EmitBlockCopy(pass_buf, &pass_ptr, &rip, &stack_depth_final, ic->ic_data);
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

          RVU32(pass_buf, &pass_ptr, &rip, StoreA0ToRs1(ic->arg1_type_pointed_to, RV_T0)); // typed store a0 -> (t0)
          // Assignment is an expression: leave the value in a0 and on the eval stack (IC_END_EXP drops it).
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final++;
        } else {
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_T0<<7) | (RV_A0<<15));
          RVU32(pass_buf, &pass_ptr, &rip, StoreA0ToRs1(ic->arg1_type_pointed_to, RV_T0)); // typed store a0 -> (t0)
          // Assignment is an expression: leave the value in a0 and on the eval stack (IC_END_EXP drops it).
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final++;
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
          EmitCondBranch(pass_buf, &pass_ptr, &rip, true, lb);
          lb->sd = stack_depth_final; lb->sd_set = true;   // the taken path reaches lb at this depth; fall-through keeps it
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
          EmitCondBranch(pass_buf, &pass_ptr, &rip, false, lb);
          lb->sd = stack_depth_final; lb->sd_set = true;
        }
        break;
      case IC_JMP:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          lb->sd = stack_depth_final; lb->sd_set = true;   // the jump reaches lb at this depth
          EmitJump(pass_buf, &pass_ptr, &rip, lb);
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
          I64 arg_count = ic->ic_flags;  // set by the parser on this call IC

          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_T1<<7) | (3<<12) | (RV_SP<<15));
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          stack_depth_final--;

          if (arg_count > 8) {
            EmitPrepareGt8CallArgs(pass_buf, &pass_ptr, &rip, arg_count);
          } else if (arg_count >= 2 && arg_count <= 8) {
            EmitLoadArgsFromEvalStack(pass_buf, &pass_ptr, &rip, &stack_depth_final, arg_count);
          } else if (arg_count == 1) {
            // The pointer load above clobbered a0: pop the single argument into it.
            RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15));
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
            stack_depth_final--;
          }

          RVU32(pass_buf, &pass_ptr, &rip, 0x67 | (RV_RA<<7) | (RV_T1<<15));   // jalr ra, t1: the pointer is the code address

          if (arg_count > 8) {
            I64 out_sz = (arg_count - 8) * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((out_sz & 0xFFF)<<20));
            I64 eval_sz = arg_count * 8;
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((eval_sz & 0xFFF)<<20));
            stack_depth_final -= arg_count;
          }

          // Return value to a0 and the eval stack (same convention as EmitCallArgsAndInvoke).
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
          stack_depth_final++;
        }
        break;
      case IC_CALL_INDIRECT2:
        EmitCallArgsAndInvoke(pass_buf, &pass_ptr, &rip, &stack_depth_final, cc, NULL, (I64 *)ic->ic_data, ic->ic_flags, (CHashGlblVar *)ic->ic_class);
        break;
      case IC_CALL:
        EmitCallArgsAndInvoke(pass_buf, &pass_ptr, &rip, &stack_depth_final, cc, (CLabel *)ic->ic_data, NULL, ic->ic_flags, NULL);
        break;
      case IC_UNARY_MINUS: EmitUnaryOp(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_UNARY_MINUS); break;
      case IC_NOT:         EmitUnaryOp(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_LOGICAL_NOT); break;
      case IC_COM:         EmitUnaryOp(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_BIT_COM); break;
      case IC_ADDR:
        // Address is in a0 (the parser retracted the auto-deref after IC_LEA); publish it.
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (3<<12) | (RV_SP<<15) | (RV_A0<<20));
        stack_depth_final++;
        break;
      case IC_ADD_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_ADD); break;
      case IC_SUB_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_SUB); break;
      case IC_MUL_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_MUL); break;
      case IC_DIV_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_DIV); break;
      case IC_AND_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_AND); break;
      case IC_OR_EQU:  EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_OR);  break;
      case IC_XOR_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_XOR); break;
      case IC_SHL_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_SLL); break;
      case IC_SHR_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_SRA); break;
      case IC_MOD_EQU: EmitCompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, RV_R_REM); break;
      case IC_FADD_EQU: case IC_FSUB_EQU: case IC_FMUL_EQU: case IC_FDIV_EQU: EmitF64CompoundAssign(pass_buf, &pass_ptr, &rip, &stack_depth_final, ic->ic_code); break;
      case IC_PAUSE:   RVU32(pass_buf, &pass_ptr, &rip, 0x13); break;
      case IC_FN_ADDR:
        EmitLabelAddr(pass_buf, &pass_ptr, &rip, (CLabel *)ic->ic_data, RV_A0);
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        stack_depth_final++;
        break;
      case IC_PC:      // `$$`: address of this instruction, pushed like an immediate
        RVU32(pass_buf, &pass_ptr, &rip, 0x17 | (RV_A0 << 7));                                        // auipc a0, 0
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        stack_depth_final++;
        break;
      case IC_HLT:     RVU32(pass_buf, &pass_ptr, &rip, 0x10500073); break;   // wfi
      case IC_INT:     RVU32(pass_buf, &pass_ptr, &rip, 0x00100073); break;   // ebreak
      case IC_CHAIN_CMP: EmitChainCmp(pass_buf, &pass_ptr, &rip, &stack_depth_final, (int)ic->ic_data); break;
      case IC_CHAIN_AND: EmitChainAnd(pass_buf, &pass_ptr, &rip, &stack_depth_final); break;
      case IC_FADD: case IC_FSUB: case IC_FMUL: case IC_FDIV:
      case IC_FLESS: case IC_FLESS_EQU: case IC_FGREATER: case IC_FGREATER_EQU:
      case IC_FEQU_EQU: case IC_FNOT_EQU: case IC_FNEG: case IC_FMOD:
        EmitF64Op(pass_buf, &pass_ptr, &rip, &stack_depth_final, ic->ic_code);
        break;
      case IC_TO_F64: EmitF64Convert(pass_buf, &pass_ptr, &rip, ic->ic_data, TRUE);  break;
      case IC_TO_I64: EmitF64Convert(pass_buf, &pass_ptr, &rip, ic->ic_data, FALSE); break;
      case IC_UDIV: case IC_UMOD: case IC_USHR:
      case IC_ULESS: case IC_ULESS_EQU: case IC_UGREATER: case IC_UGREATER_EQU:
        EmitUnsignedOp(pass_buf, &pass_ptr, &rip, &stack_depth_final, ic->ic_code);
        break;
      case IC_TRY_ENTER: EmitTryEnter(pass_buf, &pass_ptr, &rip, cc, (CLabel *)ic->ic_data, data_base); break;
      case IC_TRY_LEAVE: EmitTryLeave(pass_buf, &pass_ptr, &rip, cc, data_base); break;
      case IC_THROW:     EmitThrow(pass_buf, &pass_ptr, &rip, &stack_depth_final, cc, data_base); break;
      case IC_CLI: case IC_STI: case IC_PUSHFD: case IC_POPFD: EmitSysIntrinsic(pass_buf, &pass_ptr, &rip, ic->ic_code); break;
      case IC_STR_CONST: {
        // PC-relative address of the literal; the bytes are appended after the code.
        StringLiteral *sl = (StringLiteral *)ic->ic_data;
        I64 rel = pass_buf ? (sl->offset - rip) : 0;
        I64 hi = (rel + 0x800) >> 12, lo = rel - (hi << 12);
        RVU32(pass_buf, &pass_ptr, &rip, 0x17 | (RV_A0<<7) | (((U32)hi & 0xFFFFF)<<12));          // auipc a0, hi
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_A0<<7) | (RV_A0<<15) | (((U32)lo & 0xFFF)<<20)); // addi a0, a0, lo
        RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (3<<12));
        stack_depth_final++;
        break;
      }
      case IC_PP_:  EmitIncDec(pass_buf, &pass_ptr, &rip, &stack_depth_final,  (ic->ic_data ? ic->ic_data : 1), FALSE); break;
      case IC_MM_:  EmitIncDec(pass_buf, &pass_ptr, &rip, &stack_depth_final, -(ic->ic_data ? ic->ic_data : 1), FALSE); break;
      case IC__PP:  EmitIncDec(pass_buf, &pass_ptr, &rip, &stack_depth_final,  (ic->ic_data ? ic->ic_data : 1), TRUE);  break;
      case IC__MM:  EmitIncDec(pass_buf, &pass_ptr, &rip, &stack_depth_final, -(ic->ic_data ? ic->ic_data : 1), TRUE);  break;
      case IC_END_EXP:
        // End of expression statement: discard residual eval-stack slots so sp is back at
        // the frame base (the epilogue/ret loads are sp-relative). Keep the top value in a0
        // — it is the REPL's Fs->answer via the trailing IC_RETURN_VAL2.
        if (stack_depth_final > 0) {
          RVU32(pass_buf, &pass_ptr, &rip, 0x03 | (RV_A0<<7) | (3<<12) | (RV_SP<<15)); // ld a0, 0(sp)
          RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (((stack_depth_final * 8) & 0xFFF)<<20)); // addi sp, sp, depth*8
        }
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
        { CLabel *lb = (CLabel*)ic->ic_data; if (lb->sd_set) stack_depth_final = lb->sd; }
        g_pp_n = 0;   // don't cancel a push/pop across a branch target (matches the sizing pass)
        break;
      case IC_NOP1:
      case IC_NOP2:
        // Explicit no-op – leave stack depth unchanged
        break;
      case IC_RAW_RV:
        RVU32(pass_buf, &pass_ptr, &rip, (U32)ic->ic_data);   // pre-assembled RISC-V word (x86 translation)
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
            // Epilogue: restore ra/s0 (sp from the frame pointer, s0 = entry sp + 16)
            RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_S0<<15) | (0xFF0<<20)); // addi sp, s0, -16
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
  
  // Copy the string literals in after the code; the blob/buffer size includes them.
  if (str_total) {
    for (StringLiteral *sl = cc->strings; sl; sl = sl->next) {
      const char *sp = sl->str;
      U8 *dp = buffer + sl->offset;
      I64 len = sl->len;
      if (len == 0) while (sp[len]) len++;
      for (I64 q = 0; q < len; q++) *dp++ = (U8)sp[q];
      *dp = 0;
    }
    rip = str_base + str_total;
    cc->strings = NULL;  // consumed by this unit
  }
  // AOT: globals' initial values into the data section (their addresses are auipc-relative).
  if (data_total && cc->hash_table) {
    for (I64 i = 0; i <= cc->hash_table->mask; i++) {
      for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next) {
        if (!(e->type & HTT_GLBL_VAR)) continue;
        CHashGlblVar *g = (CHashGlblVar *)e;
        I64 sz = g->size > 0 ? g->size : 8;
        U8 *src = g->data_addr, *dst = buffer + data_base + g->data_addr_rip;
        for (I64 k = 0; k < sz; k++) dst[k] = src ? src[k] : 0;
      }
    }
    rip = data_base + data_total;
    if (import_cnt) {
      U8 *dp = buffer + rip;
      for (I64 i = 0; i <= cc->hash_table->mask; i++) {
        for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next) {
          if (!((e->type & HTT_GLBL_VAR) && e->str && e->str[0] == '_' && e->str[1] == '_' && e->str[2] == 'i' && e->str[3] == 'm' && e->str[4] == 'p' && e->use_cnt > 0 && !((CHashGlblVar *)e)->self_resolved)) continue;
          CHashGlblVar *g = (CHashGlblVar *)e;
          U64 slot = (U64)(data_base + g->data_addr_rip);
          for (int k = 0; k < 8; k++) dp[k] = (U8)(slot >> (8 * k));
          const char *nm = e->str + 6;   /* skip "__imp_" */
          for (int k = 0; k < 24; k++) { dp[8 + k] = (U8)(*nm ? *nm : 0); if (*nm) nm++; }
          dp += 32;
        }
      }
      U64 cnt = (U64)import_cnt, magic = 0x31504D4959464F48ULL;
      for (int k = 0; k < 8; k++) { dp[k] = (U8)(cnt >> (8 * k)); dp[8 + k] = (U8)(magic >> (8 * k)); }
      rip += dir_total;
    }
  }
  // Set output code size
  if (code_size) *code_size = rip;
#ifndef BARE_METAL
  // HOLYC_MAP=file: "offset name" per function in this unit (fault addresses -> functions).
  if (getenv("HOLYC_MAP") && cc->hash_table) {
    FILE *mf = fopen(getenv("HOLYC_MAP"), "w");
    if (mf) {
      for (I64 i = 0; i <= cc->hash_table->mask; i++) {
        for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next) {
          if (!(e->type & HTT_FUN)) continue;
          CHashFun *f = (CHashFun *)e;
          if (!f->entry_label || !f->entry_label_defined) continue;
          bool in_unit = false;
          for (CLabel *l = cc->labels; l; l = l->next) if (l == (CLabel *)f->entry_label) { in_unit = true; break; }
          if (in_unit) fprintf(mf, "%08llx %s\n", (long long)((CLabel *)f->entry_label)->addr, f->str ? f->str : "?");
        }
      }
      if (cc->aot_data_layout) {   // data symbols too (globals, `__imp_` slots): "offset name"
        for (I64 i = 0; i <= cc->hash_table->mask; i++) {
          for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next) {
            if (!(e->type & HTT_GLBL_VAR)) continue;
            CHashGlblVar *g = (CHashGlblVar *)e;
            fprintf(mf, "%08llx %s\n", (long long)(cc->aot_data_base + g->data_addr_rip), g->str ? g->str : "?");
          }
        }
      }
      fclose(mf);
    }
  }
#endif
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

// AOT: declare the runtime as externs; each gets an import slot global (`__imp_<name>`) that the
// loader fills by name (see bootstrap/holy_rt.h, holy_resolve_imports).
#include "bootstrap/holy_rt_names.h"
void RuntimeDeclare(Compiler *cc) {
  struct { const char *name; I64 argc; } names[] = {
#define HOLY_RT_DECL(n, a) { #n, a },
    HOLY_RT_NAMES(HOLY_RT_DECL)
#undef HOLY_RT_DECL
  };
  for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
    if (HashFind(names[i].name, cc->hash_table, HTT_FUN)) continue;
    CHashGlblVar *slot = calloc(1, sizeof(CHashGlblVar));
    char nm[64];
    {  /* "__imp_" + name (no snprintf on bare metal) */
      const char *pre = "__imp_"; int k = 0;
      while (*pre && k < 60) nm[k++] = *pre++;
      for (const char *q = names[i].name; *q && k < 62; q++) nm[k++] = *q;
      nm[k] = 0;
    }
    slot->str = strdup(nm);
    slot->type = HTT_GLBL_VAR;
    slot->size = 8; slot->element_size = 8; slot->raw_type = RT_I64;
    slot->data_addr = calloc(1, 8);
    HashAdd((CHashEntry *)slot, cc->hash_table);
    CHashFun *f = calloc(1, sizeof(CHashFun));
    f->str = strdup(names[i].name);
    f->type = HTT_FUN;
    f->raw_type = HolyRtRetF64(names[i].name) ? RT_F64 : RT_I64;
    f->param_typed = true;
    f->param_f64_mask = HolyRtF64Mask(names[i].name);
    f->arg_cnt = names[i].argc;
    f->is_extern = TRUE;
    f->import_var = slot;
    HashAdd((CHashEntry *)f, cc->hash_table);
  }
}

Compiler *Compile(const char *source, const char *filename, bool aot) {
  Compiler *cc = CompilerNew(source, filename);
  cc->aot_mode = aot;
  cc->defer_aot_compile = TRUE;
  if (aot) RuntimeDeclare(cc);
  
  // Parse the program
  if (!ParseProgram(cc)) {
    // fprintf(stderr, "Compilation failed: %s\n", 
    //         cc->error ? cc->error : "Unknown error");
    return cc;
  }
  
  // Stitch deferred per-function IC chains (source order) then single AOT pass
  AOTFnICChunk *stitched = NULL;
  // Run top-level statements (globals' initializers, `#exe`) first; if a main() is defined here,
  // call it after them and its return is the program's result.
  CHashEntry *main_e = (cc->defer_aot_compile && cc->hash_table) ? HashFind("main", cc->hash_table, HTT_FUN) : NULL;
  if (main_e && !((CHashFun *)main_e)->entry_label_defined) main_e = NULL;
  if (cc->defer_aot_compile && (cc->aot_main_head || main_e)) {
    // Entry chunk, placed first: `Fs = &__task`, then the top-level statements (HolyC runs
    // them in source order) — or, when there are none, a call to main() for C-style files.
    // The last value is left in a0 (the REPL's answer; the exec harness prints it as ORACLE).
    CIntermediateCode *stmts_head = cc->aot_main_head, *stmts_tail = cc->aot_main_tail;
    cc->ic_head = cc->ic_tail = NULL;
    ICAdd(cc, IC_IMM_I64, (I64)cc->fs_var->data_addr, RT_I64);      cc->ic_tail->ic_flags = ICF_GLBL_ADDR;
    ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
    ICAdd(cc, IC_IMM_I64, (I64)cc->except_ch_var->data_addr, RT_I64); cc->ic_tail->ic_flags = ICF_GLBL_ADDR;
    ICAdd(cc, IC_ASSIGN, 0, RT_I64);
    ICAdd(cc, IC_END_EXP, 0, RT_I64);
    // Imports of functions this unit defines after their first use (`extern` in a header, the
    // body later): store the definition's address into the slot here, PC-relative; the loader
    // directory skips them.
    if (cc->hash_table) {
      for (I64 bi = 0; bi <= cc->hash_table->mask; bi++) {
        for (CHashEntry *e = cc->hash_table->body[bi]; e; e = e->next) {
          if (!(e->type & HTT_FUN)) continue;
          CHashFun *f = (CHashFun *)e;
          if (!f->import_var || !f->entry_label_defined || !f->entry_label) continue;
          bool in_unit = false;
          for (CLabel *l = cc->labels; l; l = l->next) if (l == (CLabel *)f->entry_label) { in_unit = true; break; }
          if (!in_unit) continue;
          ICAdd(cc, IC_IMM_I64, (I64)f->import_var->data_addr, RT_I64); cc->ic_tail->ic_flags = ICF_GLBL_ADDR;
          ICAdd(cc, IC_PUSH_ARG, 0, RT_I64);
          ICAdd(cc, IC_FN_ADDR, (I64)f->entry_label, RT_I64);
          ICAdd(cc, IC_ASSIGN, 0, RT_I64);
          ICAdd(cc, IC_END_EXP, 0, RT_I64);
          f->import_var->self_resolved = true;
        }
      }
    }
    if (stmts_head) {
      cc->ic_tail->next = stmts_head;
      stmts_head->last = cc->ic_tail;
      cc->ic_tail = stmts_tail;
    }
    if (main_e) {   // call main() after the initializers; its return is the result
      CHashFun *mf = (CHashFun *)main_e;
      ICAdd(cc, IC_CALL_START, 0, RT_I64);
      ICAdd(cc, IC_CALL, (I64)mf->entry_label, RT_I64);
      cc->ic_tail->ic_flags = 0;
      ICAdd(cc, IC_CALL_END, 0, RT_I64);
    }
    WrapStatementsAsFrame(cc);
    AOTFnICChunk *mainch = calloc(1, sizeof(AOTFnICChunk));
    mainch->head = cc->ic_head;  mainch->tail = cc->ic_tail;  mainch->fun = NULL;  mainch->next = cc->aot_fn_ic_head;
    cc->ic_head = cc->ic_tail = NULL;
    stitched = mainch;
  } else if (cc->defer_aot_compile && cc->aot_fn_ic_head) {
    stitched = cc->aot_fn_ic_head;
  }
  if (stitched) {
    AOTFnICChunk *ch = stitched;
    while (ch->next) {
      ch->tail->next = ch->next->head;
      ch = ch->next;
    }
    cc->ic_head = stitched->head;
    cc->ic_tail = ch->tail;
  }
  
  // Functions declared (prototype) but never defined in this unit: their labels would resolve
  // to 0. Call them through import slots resolved by name at load instead (an unresolved one
  // reaches the loader's diagnostic stub, not address 0).
  if (aot && cc->hash_table) {
    for (I64 i = 0; i <= cc->hash_table->mask; i++) {
      for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next) {
        if (!(e->type & HTT_FUN)) continue;
        CHashFun *f = (CHashFun *)e;
        if (!f->entry_label || f->entry_label_defined || f->import_var || f->exe_addr) continue;
        bool in_unit = false;
        for (CLabel *l = cc->labels; l; l = l->next) if (l == (CLabel *)f->entry_label) { in_unit = true; break; }
        if (!in_unit) continue;
        MakeImportSlot(cc, f);
        for (CIntermediateCode *ic = cc->ic_head; ic; ic = ic->next) {
          if (ic->ic_code == IC_CALL && ic->ic_data == (I64)f->entry_label) {
            ic->ic_code = IC_CALL_INDIRECT2;
            ic->ic_data = (I64)f->import_var->data_addr;
            ic->ic_class = f->import_var;
            f->import_var->use_cnt++;
          }
        }
      }
    }
  }
  // Generate code (AOT malloc blob or JIT RWX mmap — same label offsets)
  if (aot) AOTLayoutGlobals(cc);
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

