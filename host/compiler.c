/* HolyC→RISC-V Compiler - Main File
 * 
 * This file contains:
 * - Compiler initialization
 * - IC (Intermediate Code) management
 * - AOT/JIT code generation
 * - Main entry point
 */

#include "holyc_compiler.h"
#include "rv32_lift.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef BARE_METAL
#include <stdarg.h>
#include <unistd.h>
#include <sys/mman.h>

/* Bytes reserved for __task, the block Fs points at for the life of an image.
 * Must be >= sizeof(CTask) as the KERNEL defines it (Kernel/KernelA.HH), not as the
 * bootstrap stub in this file defines it -- kernel code compiles `Fs->member` against the
 * real layout and will write at those offsets. The real class measures 1192 bytes today, so
 * this is snug ON PURPOSE: the reservation is emitted as DATA in every blob and an
 * over-generous one is not free. An 8 KiB first attempt pushed SoftCmpSrc.BIN from 2128 to
 * 9504 bytes and blew kernel-thin-loader's 4 KiB SoftCall Load cap.
 * AotCheckTaskBlockReserve() verifies it once the real class has actually been parsed, so
 * growing CTask past this is a compile error rather than silent corruption. */
#define TASK_BLOCK_RESERVE 1280

/* Guard the reservation above against the CTask the SOURCES actually define.
 * Called after parsing, when a kernel header may have replaced the bootstrap stub with the
 * real class. Returns 0 and prints when the real CTask does not fit in TASK_BLOCK_RESERVE:
 * every `Fs->member` past the reserve is an out-of-bounds write into the next global, and it
 * is silent, layout-dependent and brutal to track down -- one such write cost a full session
 * (docs/NEXT_STEPS.md 3.1b-ter). Diagnose it at compile time instead. */
int AotCheckTaskBlockReserve(Compiler *cc) {
  if (!cc || !cc->hash_table) return 1;
  CHashClass *t = (CHashClass *)HashFind("CTask", cc->hash_table, HTT_CLASS);
  if (!t || t->size <= TASK_BLOCK_RESERVE) return 1;
  fprintf(stderr,
          "error: CTask is %lld bytes but __task reserves only %d. `Fs->member` past the "
          "reserve would write into the next global, silently. Raise TASK_BLOCK_RESERVE in "
          "host/compiler.c (see docs/NEXT_STEPS.md 3.1b-ter).\n",
          (long long)t->size, TASK_BLOCK_RESERVE);
  return 0;
}

/* Visible AOT progress (stderr). Default: on when stderr is a TTY.
 * HOLYC_PROGRESS=1 forces on (pipes/CI logs); =0 forces off.
 * HOLYC_QUIET=1 forces off (smokes that must stay silent). */
int HolyProgressOn(void) {
  static int cached = -1;
  if (cached >= 0) return cached;
  const char *q = getenv("HOLYC_QUIET");
  if (q && *q && strcmp(q, "0") != 0) { cached = 0; return 0; }
  const char *p = getenv("HOLYC_PROGRESS");
  if (p && *p) {
    cached = (strcmp(p, "0") == 0) ? 0 : 1;
    return cached;
  }
  cached = isatty(STDERR_FILENO) ? 1 : 0;
  return cached;
}

const char *HolyProgressRel(const char *path) {
  if (!path || !*path) return path ? path : "?";
  const char *root = getenv("HOLYC_INCLUDE_ROOT");
  if (root && *root) {
    size_t n = strlen(root);
    if (n > 0 && strncmp(path, root, n) == 0) {
      const char *rest = path + n;
      while (*rest == '/') rest++;
      if (*rest) return rest;
    }
  }
  return path;
}

void HolyProgress(const char *fmt, ...) {
  if (!HolyProgressOn()) return;
  fputs("holyc: ", stderr);
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fputc('\n', stderr);
  fflush(stderr);
}
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
    (void)addr; (void)flags; (void)fd; (void)offset;
    /* Executable blobs must outlive heap resets (parse/IC bump allocator). */
    if (prot & PROT_EXEC) {
      extern void *code_malloc(size_t size);
      void *p = code_malloc(len);
      return p ? p : MAP_FAILED;
    }
    extern void* malloc(size_t size);
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

/* Code-generation target descriptors (multi-arch seam; see host/holyc_target.h).
 * rv64 is the default and the only one any codegen path acts on today. */
const holyc_target holyc_target_rv64 = {
  HOLYC_ARCH_RV64, "rv64", /*xlen*/64, /*ptr_width*/8, /*slot_size*/8,
  /*stack_align*/16, /*little_endian*/1, /*ld_funct3*/3, /*sd_funct3*/3,
};
const holyc_target holyc_target_rv32 = {
  HOLYC_ARCH_RV32, "rv32", /*xlen*/32, /*ptr_width*/4, /*slot_size*/8,
  /*stack_align*/16, /*little_endian*/1, /*ld_funct3*/2, /*sd_funct3*/2,
};

Compiler *CompilerNewBuf(const char *source, size_t size, const char *filename) {
  Compiler *cc = calloc(1, sizeof(Compiler));
  // Active codegen target: HOLYC_ARCH env (set from --target by main), else rv64.
  { const char *a = getenv("HOLYC_ARCH");
    cc->tgt = (a && !strcmp(a, "rv32")) ? &holyc_target_rv32 : &holyc_target_rv64; }

  // Initialize lexer — copy full buffer (may contain trailing CDocBin after text NUL).
  if (!source) source = "";
  cc->lex.src = malloc(size + 1);
  if (cc->lex.src) {
    if (size) memcpy(cc->lex.src, source, size);
    cc->lex.src[size] = '\0';
  }
  cc->lex.src_size = size;
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
      // __task backs Fs for the whole image. The bootstrap CTask below is a STUB (except_ch,
      // catch_except, except_callers[8]) but kernel sources define the real CTask
      // (Kernel/KernelA.HH), which is over a kilobyte, and every `Fs->member` they compile
      // resolves against THAT layout -- e.g. cur_dir at 0x70. Reserving the stub's 80 bytes
      // meant any such access wrote PAST __task into whichever global the linker placed next,
      // silently, with the victim changing whenever the layout changed. That is how
      // `Fs->cur_dir = StrNew("/Apps/Span")` in Cd came to overwrite blkdev.blkdevs and take
      // kernel-span down; see docs/NEXT_STEPS.md 3.1b-ter for the full read-out.
      // TASK_BLOCK_RESERVE is a ceiling for the real CTask, not a computed size: the stub is
      // built here, before any kernel header is parsed, so there is nothing to measure yet.
      // AotCheckTaskBlockReserve() re-checks it against the real class once that IS parsed.
      g->size = i == 1 ? TASK_BLOCK_RESERVE : 8;
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
  cc->var_just_loaded = false;
  cc->global_just_loaded = false;
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

Compiler *CompilerNew(const char *source, const char *filename) {
  return CompilerNewBuf(source, source ? strlen(source) : 0, filename);
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

#ifndef BARE_METAL
  if (cc->aot_deps) {
    for (I64 di = 0; di < cc->aot_dep_n; di++) free(cc->aot_deps[di]);
    free(cc->aot_deps);
  }
#endif
  
  free(cc);
}

#ifndef BARE_METAL
void AOTDepAdd(Compiler *cc, const char *path) {
  if (!cc || !path || !*path) return;
  for (I64 i = 0; i < cc->aot_dep_n; i++)
    if (cc->aot_deps[i] && !strcmp(cc->aot_deps[i], path)) return;
  if (cc->aot_dep_n >= cc->aot_dep_cap) {
    I64 ncap = cc->aot_dep_cap ? cc->aot_dep_cap * 2 : 64;
    char **nd = realloc(cc->aot_deps, (size_t)ncap * sizeof(char *));
    if (!nd) return;
    cc->aot_deps = nd;
    cc->aot_dep_cap = ncap;
  }
  cc->aot_deps[cc->aot_dep_n++] = strdup(path);
}

void AOTWriteDeps(Compiler *cc, const char *dep_path, const char *target) {
  if (!cc || !dep_path || !target) return;
  FILE *f = fopen(dep_path, "w");
  if (!f) return;
  fprintf(f, "%s:", target);
  for (I64 i = 0; i < cc->aot_dep_n; i++)
    if (cc->aot_deps[i]) fprintf(f, " \\\n  %s", cc->aot_deps[i]);
  fputc('\n', f);
  fclose(f);
}

void AOTWriteMap(Compiler *cc, const char *map_path) {
  if (!cc || !map_path || !cc->hash_table) return;
  FILE *mf = fopen(map_path, "w");
  if (!mf) return;
  for (I64 i = 0; i <= cc->hash_table->mask; i++) {
    for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next) {
      if (!(e->type & HTT_FUN)) continue;
      CHashFun *fn = (CHashFun *)e;
      if (!fn->entry_label || !fn->entry_label_defined) continue;
      bool in_unit = false;
      for (CLabel *l = cc->labels; l; l = l->next)
        if (l == (CLabel *)fn->entry_label) { in_unit = true; break; }
      if (in_unit)
        fprintf(mf, "%08llx %s\n", (long long)((CLabel *)fn->entry_label)->addr,
                fn->str ? fn->str : "?");
    }
  }
  if (cc->aot_data_layout) {
    for (I64 i = 0; i <= cc->hash_table->mask; i++) {
      for (CHashEntry *e = cc->hash_table->body[i]; e; e = e->next) {
        if (!(e->type & HTT_GLBL_VAR)) continue;
        CHashGlblVar *g = (CHashGlblVar *)e;
        fprintf(mf, "%08llx %s\n", (long long)(cc->aot_data_base + g->data_addr_rip),
                g->str ? g->str : "?");
      }
    }
  }
  fclose(mf);
}
#endif

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
#define RV_S1   9
#define RV_A0   10
#define RV_A1   11
#define RV_A2   12
#define RV_A3   13
#define RV_A4   14
#define RV_A5   15
#define RV_A6   16
#define RV_A7   17
#define RV_S2   18
#define RV_S3   19
#define RV_S4   20
#define RV_S5   21
#define RV_S6   22
#define RV_S7   23
#define RV_S8   24

// ═══════════════════════════════════════════════════════════════
// UNIFIED EMIT FUNCTIONS (TempleOS ICU8/ICU16/ICU32 pattern)
// ═══════════════════════════════════════════════════════════════

// These functions work in two modes:
// - If buf==NULL: only count bytes (for sizing passes)
// - If buf!=NULL: emit bytes and count (for final emission pass)

// ---- Tier 1 peephole: cancel adjacent eval-stack push/pop / push-abandon --------------------
// The codegen bakes stack traffic into each op's emit (IMM auto-pushes, consumers pop), so the
// dominant redundancy is `addi sp,-8; sd rX,0(sp); ld rX,0(sp); addi sp,+8` -- push a value and
// immediately pop it back into the SAME register, which is pure waste (the value is still in rX).
// Also: `addi sp,-8; sd; addi sp,+8` with no load (EVAL_DROP / assign-zero abandon) is pure dead.
// RVU32 keeps the last three emitted words; when a pattern completes it rewinds rip. It runs
// identically in the sizing (buf==NULL) and emit passes so the relaxation loop still converges.
//
// CAUTION: CompileAOT has TWO emit loops -- the do-while sizing loop AND a separate final-emission
// pass. The window (g_pp_n) must be reset at the START of each and at EVERY IC_LABEL in BOTH, or
// the two passes cancel differently: mismatched sizes, and push/pops wrongly cancelled across a
// branch target (which silently miscompiles every loop). We only cancel push/pop when rX==rY.
// push rX; pop rY -> mv is intentionally OFF (miscompiled PjPutHex / Print). Gated by g_pp_on.
static U32 g_pp[3];
static int g_pp_n;
static int g_pp_on;
/* Doubleword (8-byte slot) load/store funct3 of the word stream the emitter produces. It is
 * 3 (ld/sd) for every target: on rv32 the stream is VIRTUAL rv64 that RvEmitWord hands to
 * host/rv32_lift.c, which turns each ld/sd into a lw/sw pair (lo @+0, hi @+4). Narrower
 * lb/lh/lw/lwu mean the same on both. */
static int g_wd3 = 3;
/* Target XLEN (64/32). 32 routes every emitted word through Rv32Lift. */
static int g_xlen = 64;
static int g_rv32_args;   /* RV32_ARG_SPILL / RV32_ARG_LOAD: a0-a7 are call args a_i : s(1+i) */
static int g_rv32_raw;    /* asm{} words: already target code, emit untouched */
static I64 g_rv32_divmod; /* blob offset of the rv32_divmod helper (from the previous pass) */
static I64 g_o1_slot_off[32];
static int g_o1_slot_reg[32], g_o1_slot_n;
/* HOLYC_O1_MODE (default 3 — Tier-1 + frame folds + I64 local promotion):
 *   0 = no frame opts
 *   1 = LEA+DEREF → IC_MOV
 *   2 = + LEA+ASSIGN → FRAME_SLOT
 *   3 = + s1–s8 promotion of non-escaping I64/U64 locals in leaf fns  ← default
 *   4 = + BB frame-slot forwarding  (alias-unsafe; opt-in via HOLYC_O1_MODE=4)
 */
static int O1Mode(void) {
  const char *m = getenv("HOLYC_O1_MODE");
  if (!m || !*m) return 3;
  int v = 0;
  while (*m >= '0' && *m <= '9') v = v * 10 + (*m++ - '0');
  return v;
}
static void O1SlotClear(void) { g_o1_slot_n = 0; }
static int O1SlotFind(I64 off) { for (int i=0;i<g_o1_slot_n;i++) if (g_o1_slot_off[i]==off) return i; return -1; }
static void O1SlotForgetReg(int reg) { for (int i=0;i<g_o1_slot_n;) if (g_o1_slot_reg[i]==reg) { g_o1_slot_off[i]=g_o1_slot_off[--g_o1_slot_n]; g_o1_slot_reg[i]=g_o1_slot_reg[g_o1_slot_n]; } else i++; }
static void O1SlotSet(I64 off, int reg) { int i=O1SlotFind(off); if (i<0 && g_o1_slot_n<32) i=g_o1_slot_n++; if (i>=0) { g_o1_slot_off[i]=off; g_o1_slot_reg[i]=reg; } }
static I64 RvImmI(U32 w) { return (I64)(I32)w >> 20; }
static I64 RvImmS(U32 w) { I64 x=((w>>7)&31)|(((w>>25)&127)<<5); return x&0x800 ? x|~0xFFF : x; }
static int RvIsAddi(U32 w, int rd, int rs1, int imm) {
  return (w & 0x7F) == 0x13 && ((w >> 12) & 7) == 0 && (int)((w >> 7) & 0x1F) == rd &&
         (int)((w >> 15) & 0x1F) == rs1 && (((I32)w) >> 20) == imm;
}
/* sd rs2,0(sp) — eval-stack push store (sw on rv32: doubleword = g_wd3). */
static int RvIsSdSp0(U32 w, int *rs2) {
  if ((w & 0x7F) != 0x23 || ((w >> 12) & 7) != (U32)g_wd3 || ((w >> 15) & 0x1F) != 2) return 0;
  if ((int)(((w >> 7) & 0x1F) | (((w >> 25) & 0x7F) << 5)) != 0) return 0;
  if (rs2) *rs2 = (int)((w >> 20) & 0x1F);
  return 1;
}
/* mv rd,rs ≡ addi rd,rs,0 */
static int RvIsMv(U32 w, int *rd, int *rs) {
  if ((w & 0x7F) != 0x13 || ((w >> 12) & 7) != 0 || (((I32)w) >> 20) != 0) return 0;
  if (rd) *rd = (int)((w >> 7) & 0x1F);
  if (rs) *rs = (int)((w >> 15) & 0x1F);
  return 1;
}
static void PpRewind(U8 *buf, U8 **ptr, I64 *rip, int n) {
  if (n <= 0 || n > g_pp_n) return;
  if (buf && ptr) *ptr -= 4 * n;
  *rip -= 4 * n;
  g_pp_n -= n;
}
/* Raw little-endian 32-bit word emit + rip advance — the arch-neutral half of the
 * word writer (the other half, RVU32, adds the RISC-V push/pop + O1-slot peephole).
 * A non-RV backend reuses this and supplies its own peephole, or none. */
static void RvEmitWordRaw(U8 *buf, U8 **ptr, I64 *rip, U32 val) {
  if (buf && ptr) { *(U32 *)(*ptr) = val; (*ptr) += 4; }
  (*rip) += 4;
}
typedef struct { U8 *buf; U8 **ptr; I64 *rip; } RvEmitCtx;
static void RvEmitLifted(void *c, uint32_t w) {
  RvEmitCtx *e = (RvEmitCtx *)c;
  RvEmitWordRaw(e->buf, e->ptr, e->rip, w);
}
static void RvEmitWord(U8 *buf, U8 **ptr, I64 *rip, U32 val) {
  if (g_xlen == 32 && !g_rv32_raw) {   /* rv32: expand the virtual rv64 word (rip advances per word) */
    RvEmitCtx e = { buf, ptr, rip };
    Rv32LiftEnv env = { g_rv32_args, *rip, g_rv32_divmod };
    Rv32Lift(val, &env, RvEmitLifted, &e);
    return;
  }
  RvEmitWordRaw(buf, ptr, rip, val);
}

static void RVU32(U8 *buf, U8 **ptr, I64 *rip, U32 val) {
  if (g_pp_on && g_pp_n >= 3) {
    U32 w0 = g_pp[0], w1 = g_pp[1], w2 = g_pp[2];
    int isDec = RvIsAddi(w0, 2, 2, -8);                                                   // addi sp,sp,-8
    int isSd  = RvIsSdSp0(w1, NULL);                                                     // sd rX,0(sp)
    int isLd  = (w2 & 0x7F) == 0x03 && ((w2 >> 12) & 7) == (U32)g_wd3 && ((w2 >> 15) & 0x1F) == 2 &&
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
  /* Pure dead push: addi sp,-8; sd rX,0(sp); addi sp,+8 with no load — EVAL_DROP / assign-zero abandon.
   * Do NOT add push rX; pop rY → mv here: that miscompiled indexed stores (PjPutHex / Print). */
  if (g_pp_on && g_pp_n >= 2 && RvIsAddi(val, 2, 2, 8)) {
    int rX = 0;
    U32 wDec = g_pp[g_pp_n - 2], wSd = g_pp[g_pp_n - 1];
    if (RvIsAddi(wDec, 2, 2, -8) && RvIsSdSp0(wSd, &rX)) {
      if (buf && ptr) *ptr -= 8;
      *rip -= 8;
      g_pp_n -= 2;
      return;
    }
  }
  // BB-local frame-slot forwarding (mode>=4). Unsafe w/ pointer aliases — gated for bisect.
  if (g_pp_on && O1Mode()>=4 && (val&0x7F)==0x03 && ((val>>15)&31)==RV_S0) {
    int rd=(val>>7)&31, i=O1SlotFind(RvImmI(val));
    if (i>=0) {
      int rs=g_o1_slot_reg[i];
      if (rd==rs) return;  // already in place
      val=0x13|((U32)rd<<7)|((U32)rs<<15);  // mv rd, rs
    }
  }
  if (g_pp_on && O1Mode()>=4 && (val&0x7F)==0x23 && ((val>>15)&31)==RV_S0) O1SlotSet(RvImmS(val),(val>>20)&31);
  if (g_pp_on && ((val&0x7F)==0x6F || ((val&0x7F)==0x67 && ((val>>7)&31)))) O1SlotClear();
  int rd_def = -1;
  if (g_pp_on) {
    U32 op=val&0x7F;
    if (op==0x03||op==0x13||op==0x33||op==0x37||op==0x17||op==0x67) rd_def=(int)((val>>7)&31);
  }
  RvEmitWord(buf, ptr, rip, val);
  if (g_pp_on) {
    if (g_pp_n < 3) g_pp[g_pp_n++] = val;
    else { g_pp[0] = g_pp[1]; g_pp[1] = g_pp[2]; g_pp[2] = val; }
    if (rd_def > 0) O1SlotForgetReg(rd_def);
  }
}

/* IC_DEREF / IncDec: load *rs1 into rd; width from arg1_type_pointed_to (U32 → lwu, not ld). */
static U32 LoadRdFromRs1(U8 pointed_to, U8 rd, U8 rs1) {
  switch (pointed_to) {
  case RT_I8:
    return 0x03 | (rd << 7) | (0 << 12) | (rs1 << 15); /* lb */
  case RT_U8:
    return 0x03 | (rd << 7) | (4 << 12) | (rs1 << 15); /* lbu */
  case RT_I16:
    return 0x03 | (rd << 7) | (1 << 12) | (rs1 << 15); /* lh */
  case RT_U16:
    return 0x03 | (rd << 7) | (5 << 12) | (rs1 << 15); /* lhu */
  case RT_I32:
    return 0x03 | (rd << 7) | (2 << 12) | (rs1 << 15); /* lw */
  case RT_U32:
    return 0x03 | (rd << 7) | (6 << 12) | (rs1 << 15); /* lwu */
  default:
    return 0x03 | (rd << 7) | (g_wd3<<12) | (rs1 << 15); /* ld */
  }
}
static U32 DerefLoadFromRs1(U8 pointed_to, U8 rs1) {
  return LoadRdFromRs1(pointed_to, RV_A0, rs1);
}
static U32 DerefLoadFromRs1Off(U8 p, U8 rs1, I64 off) { return DerefLoadFromRs1(p,rs1)|(((U32)off&0xFFF)<<20); }

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
  // lui 0x80000 (lo32 in [0x7FFFF800, 0x7FFFFFFF], addi negative) sign-extends to
  // 0xFFFFFFFF7FFFxxxx on rv64 — zero-extend that case too.
  if (!fits_i32 || ((hi & 0xFFFFF) == 0x80000 && lo32 > 0)) {                               // zero-extend
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (rd << 7) | (1 << 12) | (rd << 15) | (32 << 20));   // slli rd, 32
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (rd << 7) | (5 << 12) | (rd << 15) | (32 << 20));   // srli rd, 32
  }
}

// Typed store of rs2 through rs1 (mirror of LoadRdFromRs1).
static U32 StoreRs2ToRs1(U8 pointed_to, U8 rs1, U8 rs2) {
  U32 f3;
  switch (pointed_to) {
  case RT_I8: case RT_U8:   f3 = 0; break; /* sb */
  case RT_I16: case RT_U16: f3 = 1; break; /* sh */
  case RT_I32: case RT_U32: f3 = 2; break; /* sw */
  default:                  f3 = g_wd3; break; /* sd */
  }
  return 0x23 | (f3 << 12) | (rs1 << 15) | (rs2 << 20);
}
static U32 StoreA0ToRs1(U8 pointed_to, U8 rs1) {
  return StoreRs2ToRs1(pointed_to, rs1, RV_A0);
}
static U32 StoreA0ToRs1Off(U8 p, U8 rs1, I64 off) { return StoreA0ToRs1(p,rs1)|(((U32)off&31)<<7)|(((U32)off&0xFE0)<<20); }
static U32 StoreZeroToRs1(U8 pointed_to, U8 rs1) {
  return StoreRs2ToRs1(pointed_to, rs1, RV_ZERO); /* rs2 = x0 */
}

/* After *p=0 / ASSIGN: is a0 (the stored value) observed? Statement + LEAVE → no;
 * return / outer expr / REPL RETURN_VAL2 → yes (keep li a0,0 after store). */
static int AssignResultNeeded(CIntermediateCode *ic) {
  CIntermediateCode *n = ic ? ic->next : NULL;
  while (n && (n->ic_code == IC_NOP1 || n->ic_code == IC_NOP2)) n = n->next;
  if (!n) return 0;
  if (n->ic_code == IC_END_EXP) {
    CIntermediateCode *n2 = n->next;
    while (n2 && (n2->ic_code == IC_NOP1 || n2->ic_code == IC_NOP2)) n2 = n2->next;
    if (!n2) return 0;
    if (n2->ic_code == IC_RETURN_VAL || n2->ic_code == IC_RETURN_VAL2) return 1;
    if (n2->ic_code == IC_JMP) return 1; /* return *p=0: a0 live across jmp to leave */
    if (n2->ic_code == IC_LEAVE || n2->ic_code == IC_RET) return 0;
    return 0; /* next statement */
  }
  return 1;
}

/* Ptr ASSIGN with ICF_ASSIGN_ZERO: addr on eval stack (a0 still holds it after skipped IMM 0);
 * store x0 through the live address reg (no useless `mv t0,a0` / `addi t0,a0,0`).
 * Push result only when observed. Relies on push-abandon peep when safe. */
static void EmitAssignStoreZero(U8 *b, U8 **q, I64 *r, I64 *d, CIntermediateCode *ic) {
  int rd = 0, rs = RV_A0, rX = 0, have_t0 = 0;
  int addr_reg = RV_A0;
  if (*d >= 1) {
    int can_abandon = 0;
    if (g_pp_on && g_pp_n >= 2) {
      int idx_dec = g_pp_n - 2, idx_sd = g_pp_n - 1;
      if (RvIsAddi(g_pp[idx_dec], 2, 2, -8) && RvIsSdSp0(g_pp[idx_sd], &rX) && rX == RV_A0)
        can_abandon = 1;
    }
    if (can_abandon) {
      RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20)); /* peep drops push */
      (*d)--;
      addr_reg = RV_A0;
    } else {
      RVU32(b, q, r, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));
      RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
      (*d)--;
      have_t0 = 1;
      addr_reg = RV_T0;
    }
  }
  if (!have_t0) {
    if (g_pp_on && g_pp_n >= 1 && RvIsMv(g_pp[g_pp_n - 1], &rd, &rs) && rd == RV_A0 && rs != RV_A0) {
      /* Dead mv a0,rs — addr already in rs; drop mv and store through rs. */
      U32 k0 = 0, k1 = 0;
      int kn = 0;
      if (g_pp_n == 2) { k0 = g_pp[0]; kn = 1; }
      else if (g_pp_n == 3) { k0 = g_pp[0]; k1 = g_pp[1]; kn = 2; }
      PpRewind(b, q, r, 1);
      if (kn == 1) { g_pp[0] = k0; g_pp_n = 1; }
      else if (kn == 2) { g_pp[0] = k0; g_pp[1] = k1; g_pp_n = 2; }
      addr_reg = rs;
    } else {
      addr_reg = RV_A0; /* sd zero,0(a0) — no addi t0,a0,0 */
    }
  }
  RVU32(b, q, r, StoreZeroToRs1(ic->arg1_type_pointed_to, addr_reg));
  if (AssignResultNeeded(ic)) {
    RVU32(b, q, r, 0x13 | (RV_A0 << 7)); /* li a0,0 */
    RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
    RVU32(b, q, r, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_A0 << 20));
    (*d)++;
  }
}

// Struct copy for `b = a` (same class, size>8): eval stack holds [dst, src] with src on top and
// ic_data = the byte count. Pops both, copies n bytes (8-byte words then a byte tail), and leaves
// the dst address (assignment is an expression). Offsets are unrolled, so n is capped by the
// caller to fit the 12-bit load/store immediate.
static void EmitBlockCopy(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, I64 n) {
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1<<7) | (g_wd3<<12) | (RV_SP<<15));              // ld t1, 0(sp)  (src)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));              // addi sp,sp,8
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0<<7) | (g_wd3<<12) | (RV_SP<<15));              // ld t0, 0(sp)  (dst)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));              // addi sp,sp,8
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A5<<7) | (RV_T0<<15));                        // mv a5, t0 (save dst)
  I64 off = 0;
  for (; off + 8 <= n; off += 8) {
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2<<7) | (g_wd3<<12) | (RV_T1<<15) | (((U32)(off & 0xFFF))<<20));                       // ld t2, off(t1)
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (((U32)(off & 0x1F))<<7) | (g_wd3<<12) | (RV_T0<<15) | (RV_T2<<20) | (((U32)((off>>5)&0x7F))<<25)); // sd t2, off(t0)
  }
  for (; off < n; off++) {
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2<<7) | (0<<12) | (RV_T1<<15) | (((U32)(off & 0xFFF))<<20));                       // lb t2, off(t1)
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (((U32)(off & 0x1F))<<7) | (0<<12) | (RV_T0<<15) | (RV_T2<<20) | (((U32)((off>>5)&0x7F))<<25)); // sb t2, off(t0)
  }
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0<<7) | (RV_A5<<15));                        // mv a0, a5 (result = dst)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));          // addi sp,sp,-8
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));             // sd a0, 0(sp)
  *stack_depth -= 1;   // popped 2 (dst,src), pushed 1 (result)
}

// PC-relative call to a same-unit label: always auipc+jalr (full ±2 GiB, fixed 2-word size).
//
// Why not `jal` (±1 MiB)? Distance-dependent 1- vs 2-word encoding desyncs the sizing loop vs
// final emit near the ±1 MiB edge (broke spawn demo). Blobs are routinely >1 MiB.
//
// Why not direct `jal` for every HTT_FUN? Import / undefined prototype / host RT slots need
// `ld` from a mutable slot + `jalr` so the loader can fill and TempleOS-style redefinition
// still works. Do not “directize” those without a frozen binding.
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
    g_rv32_args = RV32_ARG_LOAD;
    RVU32(pass_buf, pass_ptr, rip,
          0x03 | (reg << 7) | (g_wd3<<12) | (RV_SP << 15) | ((offset & 0xFFF) << 20));
    g_rv32_args = 0;
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
    g_rv32_args = RV32_ARG_LOAD;
    RVU32(pass_buf, pass_ptr, rip,
          0x03 | (reg << 7) | (g_wd3<<12) | (RV_T2 << 15) | ((offset & 0xFFF) << 20));
    g_rv32_args = 0;
  }
  I64 out_sz = (N - 8) * 8;
  RVU32(pass_buf, pass_ptr, rip,
        0x13 | (RV_SP << 7) | (RV_SP << 15) | (((-out_sz) & 0xFFF) << 20)); // addi sp, sp, -out_sz
  for (I64 j = 9; j <= N; j++) {
    I64 src = (N - j) * 8;
    I64 dst = (j - 9) * 8;
    RVU32(pass_buf, pass_ptr, rip,
          0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_T2 << 15) | ((src & 0xFFF) << 20));
    RVU32(pass_buf, pass_ptr, rip,
          0x23 | ((dst & 0x1F) << 7) | (g_wd3<<12) | (RV_SP << 15) | (RV_T0 << 20) | ((dst >> 5) << 25));
  }
}

// Unary op on the eval-stack top (a0 mirrors it): pop, apply, push.
static void EmitUnaryOp(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, U32 insn) {
  if (*stack_depth > 0) {
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (g_wd3<<12) | (RV_SP << 15));            // ld a0, 0(sp)
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));            // addi sp, sp, 8
    (*stack_depth)--;
  }
  RVU32(pass_buf, pass_ptr, rip, insn);
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));          // addi sp, sp, -8
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_A0 << 20));             // sd a0, 0(sp)
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
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (g_wd3<<12) | (RV_SP << 15));            // ld t1, 0(sp)
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));            // addi sp, sp, 8
    (*stack_depth)--;
  } else {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T1 << 7) | (RV_A0 << 15));                        // mv t1, a0
  }
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));              // ld t0, 0(sp)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));              // addi sp, sp, 8
  if (*stack_depth > 0) (*stack_depth)--;
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (g_wd3<<12) | (RV_T0 << 15));              // ld t2, 0(t0)
  RVU32(pass_buf, pass_ptr, rip, rtype | (RV_T2 << 7) | (RV_T2 << 15) | (RV_T1 << 20));         // op t2, t2, t1
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T0 << 15) | (RV_T2 << 20));             // sd t2, 0(t0)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (RV_T2 << 15));                          // mv a0, t2
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));          // addi sp, sp, -8
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_A0 << 20));             // sd a0, 0(sp)
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
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (g_wd3<<12) | (RV_SP << 15));            // ld t1, 0(sp)  rhs bits
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    (*stack_depth)--;
  } else {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T1 << 7) | (RV_A0 << 15));                        // mv t1, a0
  }
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));              // ld t0, 0(sp)  addr
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  if (*stack_depth > 0) (*stack_depth)--;
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (g_wd3<<12) | (RV_T0 << 15));              // ld t2, 0(t0)  *addr bits
  RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA0, RV_T2));
  RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA1, RV_T1));
  U32 fop = ic_code == IC_FADD_EQU ? 0x02000053u : ic_code == IC_FSUB_EQU ? 0x0A000053u :
            ic_code == IC_FMUL_EQU ? 0x12000053u : 0x1A000053u;
  RVU32(pass_buf, pass_ptr, rip, RV_FOP(fop, RV_FA0, RV_FA0, RV_FA1));
  RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T0 << 15) | (RV_A0 << 20));             // sd a0, 0(t0)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_A0 << 20));
  (*stack_depth)++;
}
static void EmitF64Op(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, U8 ic_code) {
  if (ic_code == IC_FNEG) {
    if (*stack_depth > 0) {
      RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (g_wd3<<12) | (RV_SP << 15));
      RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
      (*stack_depth)--;
    }
    RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA0, RV_A0));
    RVU32(pass_buf, pass_ptr, rip, 0x22000053u | (RV_FA0 << 7) | (1u << 12) | (RV_FA0 << 15) | (RV_FA0 << 20)); // fsgnjn.d
    RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0));
  } else {
    // pop right into t1, left into t0 (same order as the integer binary ops)
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (g_wd3<<12) | (RV_SP << 15));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));
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
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_A0 << 20));
  (*stack_depth)++;
}
// Convert eval-stack slot k in place (k = ic_data: 0 = top); a0 mirrors the top afterwards.
static void EmitF64Convert(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 slot, Bool to_f64) {
  U32 off = (U32)((slot * 8) & 0xFFF);
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (g_wd3<<12) | (RV_SP << 15) | (off << 20));   // ld a0, off(sp)
  if (to_f64) {
    RVU32(pass_buf, pass_ptr, rip, RV_FCVT_D_L(RV_FA0, RV_A0));
  } else {
    RVU32(pass_buf, pass_ptr, rip, RV_FMV_D_X(RV_FA0, RV_A0));
    RVU32(pass_buf, pass_ptr, rip, RV_FCVT_L_D(RV_A0, RV_FA0));
  }
  if (to_f64) RVU32(pass_buf, pass_ptr, rip, RV_FMV_X_D(RV_A0, RV_FA0));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_A0 << 20) | ((off & 0x1F) << 7) | ((off >> 5) << 25)); // sd a0, off(sp)
  if (slot) RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (g_wd3<<12) | (RV_SP << 15));           // ld a0, 0(sp)
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
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_A0 << 20));
    (*stack_depth)++;
  }
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (g_wd3<<12) | (RV_SP << 15));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));
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
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_A0 << 20));
  (*stack_depth)++;
}
// ---- try/catch/throw --------------------------------------------------------------------
// Handler context (32 bytes, a compiler temp in the try's frame): {prev, sp, s0, catch pc}.
static void EmitTryEnter(U8 *pass_buf, U8 **pass_ptr, I64 *rip, Compiler *cc, CLabel *catch_lb, I64 data_base) {
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T2 << 7) | (RV_A0 << 15));                                   // mv t2, a0 (ctx)
  EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T1, cc->try_top_var, data_base);                        // t1 = &__try_top
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_T1 << 15));                       // ld t0, 0(t1)
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T2 << 15) | (RV_T0 << 20));                      // sd t0, 0(t2)  prev
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T2 << 15) | (RV_SP << 20) | (8 << 7));           // sd sp, 8(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T2 << 15) | (RV_S0 << 20) | (16 << 7));          // sd s0, 16(t2)
  I64 rel = pass_buf ? (catch_lb->addr - *rip) : 0;
  I64 hi = (rel + 0x800) >> 12, lo = rel - (hi << 12);
  RVU32(pass_buf, pass_ptr, rip, 0x17 | (RV_T0 << 7) | (((U32)hi & 0xFFFFF) << 12));                    // auipc t0, catch
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (RV_T0 << 15) | (((U32)lo & 0xFFF) << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T2 << 15) | (RV_T0 << 20) | (24 << 7));          // sd t0, 24(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T1 << 15) | (RV_T2 << 20));                      // __try_top = ctx
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
      RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_T0 << 20));                  // sd t0,0(sp)
      break;
    case IC_POPFD:
      RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));                   // ld t0,0(sp)
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
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (g_wd3<<12));
    (*depth)++;
  }
  if (*depth < 2) return;
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (g_wd3<<12) | (RV_SP << 15));              // t1 = b
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));              // t0 = a
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
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (g_wd3<<12));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));          // push b
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_T1 << 20) | (g_wd3<<12));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | (RV_T1 << 15));                          // a0 = b
  *depth += 2;
}
static void EmitChainAnd(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *depth) {
  if (*depth == 2) {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (g_wd3<<12));
    (*depth)++;
  }
  if (*depth < 3) return;
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (g_wd3<<12) | (RV_SP << 15));              // t2 = z
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (g_wd3<<12) | (RV_SP << 15));              // t1 = y
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));              // t0 = x
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
  *depth -= 3;
  RVU32(pass_buf, pass_ptr, rip, 0x33 | (RV_A0 << 7) | (7 << 12) | (RV_T0 << 15) | (RV_T1 << 20));   // a0 = x & y
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (g_wd3<<12));
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_T2 << 20) | (g_wd3<<12));
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
// Unconditional jump: always auipc+jalr (fixed 2 words), same rationale as EmitJalToLabel.
// Distance-dependent jal vs auipc+jalr desynced sizing vs final emit on large AOTs
// (CInit `j` into mid-auipc/addi). ICF_RELAX_LONG kept for call-site compatibility.
static void EmitJump(U8 *pass_buf, U8 **pass_ptr, I64 *rip, CIntermediateCode *ic, CLabel *lb) {
  (void)ic;
  I64 rel = lb->addr - *rip;
  I64 hi = (rel + 0x800) >> 12, lo = rel - (hi << 12);
  RVU32(pass_buf, pass_ptr, rip, 0x17 | (RV_T0 << 7) | (((U32)hi & 0xFFFFF) << 12));                 // auipc t0, hi
  RVU32(pass_buf, pass_ptr, rip, 0x67 | (RV_ZERO << 7) | (RV_T0 << 15) | (((U32)lo & 0xFFF) << 20)); // jalr zero, lo(t0)
}

// B-type branch: always inverse + jal (fixed 2 words). Short B-type ±4KB oscillation
// prevented AOT convergence on Kernel+Compiler blobs (pass cap → stale labels).
static void EmitBrRsRs(U8 *pass_buf, U8 **pass_ptr, I64 *rip, CIntermediateCode *ic, int f3, int rs1, int rs2,
                       CLabel *lb) {
  (void)ic;
  int inv = f3 ^ 1; /* beq↔bne; blt↔bge; bltu↔bgeu */
  RVU32(pass_buf, pass_ptr, rip,
        0x63 | ((U32)inv << 12) | (0 << 7) | (4 << 8) | ((U32)rs1 << 15) | ((U32)rs2 << 20));
  I64 joff = lb->addr - *rip;
  RVU32(pass_buf, pass_ptr, rip,
        0x6F | (((U32)(joff >> 12) & 0xFF) << 12) | (((U32)(joff >> 11) & 1) << 20) |
            (((U32)(joff >> 1) & 0x3FF) << 21) | (((U32)(joff >> 20) & 1) << 31));
}

// Conditional branch on a0: always inverse beq/bne + jal (fixed 2 words).
static void EmitCondBranch(U8 *pass_buf, U8 **pass_ptr, I64 *rip, CIntermediateCode *ic, bool br_zero, CLabel *lb) {
  (void)ic;
  U32 inv = br_zero ? (1u << 12) : 0u;
  RVU32(pass_buf, pass_ptr, rip, 0x63 | inv | (0 << 7) | (4 << 8) | (RV_A0 << 15) | (RV_ZERO << 20));
  I64 joff = lb->addr - *rip;
  RVU32(pass_buf, pass_ptr, rip, 0x6F | (((U32)(joff >> 12) & 0xFF) << 12) | (((U32)(joff >> 11) & 1) << 20) |
        (((U32)(joff >> 1) & 0x3FF) << 21) | (((U32)(joff >> 20) & 1) << 31));
}

/* Map IC_BR_EQU_EQU…LESS_EQU → (f3, swap_operands). GREATER uses blt with swapped regs. */
static void BrCmpF3(U8 code, int *f3, int *swap) {
  *swap = 0;
  switch (code) {
  case IC_BR_EQU_EQU: *f3 = 0; break;
  case IC_BR_NOT_EQU: *f3 = 1; break;
  case IC_BR_LESS: *f3 = 4; break;
  case IC_BR_GREATER_EQU: *f3 = 5; break;
  case IC_BR_GREATER: *f3 = 4; *swap = 1; break;
  case IC_BR_LESS_EQU: *f3 = 5; *swap = 1; break;
  default: *f3 = 0; break;
  }
}

/* Pop lhs (+ optional imm rhs) and emit compare-and-branch. Stack depth updated. */
static void EmitIC_BrCmp(U8 *b, U8 **q, I64 *r, I64 *d, CIntermediateCode *ic) {
  CLabel *lb = (CLabel *)ic->ic_data;
  int f3 = 0, swap = 0, lhs = RV_T0, rhs = RV_T1;
  BrCmpF3(ic->ic_code, &f3, &swap);
  if (ic->ic_flags & ICF_CMP_IMM) {
    int rX = 0, abandoned = 0;
    if (*d >= 1 && g_pp_on && g_pp_n >= 2) {
      if (RvIsAddi(g_pp[g_pp_n - 2], 2, 2, -8) && RvIsSdSp0(g_pp[g_pp_n - 1], &rX) && rX == RV_A0) {
        RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
        (*d)--;
        abandoned = 1;
        lhs = RV_A0;
      }
    }
    if (!abandoned && *d >= 1) {
      RVU32(b, q, r, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));
      RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
      (*d)--;
      lhs = RV_T0;
    }
    EmitLoadImm64(b, q, r, RV_T1, ic->arg2.disp);
    rhs = RV_T1;
  } else {
    if (*d >= 2) {
      RVU32(b, q, r, 0x03 | (RV_T1 << 7) | (g_wd3<<12) | (RV_SP << 15));
      RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
      (*d)--;
      RVU32(b, q, r, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_SP << 15));
      RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
      (*d)--;
      lhs = RV_T0;
      rhs = RV_T1;
    }
  }
  if (swap) { int t = lhs; lhs = rhs; rhs = t; }
  EmitBrRsRs(b, q, r, ic, f3, lhs, rhs, lb);
  lb->sd = *d;
  lb->sd_set = true;
}
static void EmitTryLeave(U8 *pass_buf, U8 **pass_ptr, I64 *rip, Compiler *cc, I64 data_base) {
  EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T1, cc->try_top_var, data_base);
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (g_wd3<<12) | (RV_T1 << 15));                       // ld t2, 0(t1)  ctx
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_T2 << 15));                       // ld t0, 0(t2)  prev
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T1 << 15) | (RV_T0 << 20));                      // __try_top = prev
}
static void EmitThrow(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, Compiler *cc, I64 data_base) {
  if (*stack_depth > 0) {                                                                                 // value -> a0
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_A0 << 7) | (g_wd3<<12) | (RV_SP << 15));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    (*stack_depth)--;
  }
  EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T1, cc->except_ch_var, data_base);
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T1 << 15) | (RV_A0 << 20));                      // except_ch = a0
  // And the cell every HolyC catcher actually reads. __task.except_ch is only Fs->except_ch while
  // Fs still points at __task; the kernel repoints Fs at a CTask of its own (Fs = adam) and from
  // then on PutExcept, DirContextNew's catch and the REPL all read Fs->except_ch and saw 0 -- a
  // missing Print argument (StrPrintJoin: throw('StrPrint')) came out as silence and ans=0.
  // The real class is parsed from the kernel headers, so its offset is looked up here, at emit.
  {
    CHashClass *tcls = (CHashClass *)HashFind("CTask", cc->hash_table, HTT_CLASS);
    CMemberLst *m = NULL;
    for (CHashClass *c = tcls; c && !m; c = c->base_class)
      for (CMemberLst *mm = c->member_lst; mm; mm = mm->next)
        if (mm->str && strcmp(mm->str, "except_ch") == 0) { m = mm; break; }
    if (m && cc->fs_var && m->offset >= 0 && m->offset < 2048) {
      EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T1, cc->fs_var, data_base);                          // t1 = &Fs
      RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T1 << 7) | (g_wd3<<12) | (RV_T1 << 15));                   // t1 = Fs
      RVU32(pass_buf, pass_ptr, rip, 0x63 | (0 << 12) | (RV_T1 << 15) | (4 << 8));                         // beqz t1, +8
      RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T1 << 15) | (RV_A0 << 20) | ((m->offset & 0x1f) << 7) | ((m->offset >> 5) << 25)); // Fs->except_ch = a0
    }
  }
  EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T1, cc->try_top_var, data_base);
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T2 << 7) | (g_wd3<<12) | (RV_T1 << 15));                       // ld t2, 0(t1)
  RVU32(pass_buf, pass_ptr, rip, 0x63 | (1 << 12) | (RV_T2 << 15) | (4 << 8));                           // bnez t2, +8
  RVU32(pass_buf, pass_ptr, rip, 0x00100073);                                                            // ebreak: no handler
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_T2 << 15));                       // ld t0, 0(t2) prev
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_T1 << 15) | (RV_T0 << 20));                      // __try_top = prev
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_SP << 7) | (g_wd3<<12) | (RV_T2 << 15) | (8 << 20));           // ld sp, 8(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_S0 << 7) | (g_wd3<<12) | (RV_T2 << 15) | (16 << 20));          // ld s0, 16(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_T2 << 15) | (24 << 20));          // ld t0, 24(t2)
  RVU32(pass_buf, pass_ptr, rip, 0x67 | (RV_T0 << 15));                                                  // jr t0
}

// ++/-- : IC_PP_/IC_MM_ (pre) and IC__PP/IC__MM (post). The operand address is in a0 (IC_LEA
// leaves it there without pushing; the parser retracts any auto-deref). Result value goes to a0
// and onto the eval stack, like IC_DEREF.
// Width from arg1_type_pointed_to: CDoc's adjacent U32 cur_bin_num / I64 max_entries must use
// lwu/sw — a plain ld/sd on member++ corrupts max_entries and feeds MStrPrint a huge vararg.
static void EmitIncDec(U8 *pass_buf, U8 **pass_ptr, I64 *rip, I64 *stack_depth, I64 delta, Bool post, U8 pty) {
  if (!pty) pty = RT_I64;
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (RV_A0 << 15));                          // mv t0, a0
  RVU32(pass_buf, pass_ptr, rip, LoadRdFromRs1(pty, RV_T1, RV_T0));                             // typed load t1, 0(t0)
  if (delta >= -2048 && delta <= 2047) {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T2 << 7) | (RV_T1 << 15) | ((delta & 0xFFF) << 20)); // addi t2, t1, delta
  } else {   // pointer step of a large struct: build the constant, then add
    EmitLoadImm64(pass_buf, pass_ptr, rip, RV_T2, delta);
    RVU32(pass_buf, pass_ptr, rip, 0x33 | (RV_T2 << 7) | (RV_T1 << 15) | (RV_T2 << 20));         // add t2, t1, t2
  }
  RVU32(pass_buf, pass_ptr, rip, StoreRs2ToRs1(pty, RV_T0, RV_T2));                             // typed store t2, 0(t0)
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_A0 << 7) | ((post ? RV_T1 : RV_T2) << 15));         // mv a0, old/new
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));          // addi sp, sp, -8
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_A0 << 20));             // sd a0, 0(sp)
  (*stack_depth)++;
}

static void EmitGlobalAddr(U8 *pass_buf, U8 **pass_ptr, I64 *rip, Compiler *cc, U8 rd, CHashGlblVar *g, I64 data_base);
static void EmitRegsSnapStub(U8 *pass_buf, U8 **pass_ptr, I64 *rip) {
#ifdef HOLYC_STANDALONE
  /* AOT guest (repl-holyc blob): never embed host regs_snap_only_stub PC. */
  (void)pass_buf;
  (void)pass_ptr;
  (void)rip;
  return;
#else
  extern void regs_snap_only_stub(void);
  I64 addr = (I64)regs_snap_only_stub;
  U32 hi = (U32)(((addr + 0x800) >> 12) & 0xFFFFF);
  RVU32(pass_buf, pass_ptr, rip, 0x37 | (RV_T0 << 7) | (hi << 12));
  I64 lo = addr - (I64)((addr + 0x800) & ~0xFFFLL);
  if (lo)
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (RV_T0 << 15) | ((lo & 0xFFF) << 20));
  if (addr & 0x80000000) {
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (1 << 12) | (RV_T0 << 15) | (32 << 20));
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T0 << 7) | (5 << 12) | (RV_T0 << 15) | (32 << 20));
  }
  RVU32(pass_buf, pass_ptr, rip, 0x67 | (RV_RA << 7) | (RV_T0 << 15));
#endif
}

/* A-ext AMO word: opcode 0x2F; aqrl is {aq,rl} in bits [26:25]. */
static U32 RvAmo(U32 f5, U32 aqrl, U32 f3, int rd, int rs1, int rs2) {
  return 0x2Fu | ((U32)rd << 7) | (f3 << 12) | ((U32)rs1 << 15) | ((U32)rs2 << 20) |
         (aqrl << 25) | (f5 << 27);
}

/* HolyC `lock`: spin acquire matching HolyLock (amoswap.d.aq 1 until old==0). */
static void EmitLockEnter(U8 *pass_buf, U8 **pass_ptr, I64 *rip) {
  EmitLoadImm64(pass_buf, pass_ptr, rip, RV_T0, (I64)HOLYC_STMT_LOCK_ADDR);
  RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_T1 << 7) | (1 << 20));  // addi t1, zero, 1
  I64 loop = *rip;
  RVU32(pass_buf, pass_ptr, rip, RvAmo(0x01, 2, (U32)g_wd3, RV_T2, RV_T0, RV_T1));  // amoswap.d.aq t2,t1,(t0)
  I64 offset = loop - *rip;  // bnez t2, loop (−4)
  RVU32(pass_buf, pass_ptr, rip,
        0x63 | (1u << 12) | (((U32)(offset >> 11) & 1) << 7) | (((U32)(offset >> 1) & 0xF) << 8) |
            ((U32)RV_T2 << 15) | (((U32)(offset >> 5) & 0x3F) << 25) | (((U32)(offset >> 12) & 1) << 31));
}

/* HolyC `lock` leave: release store 0 matching HolyUnlock (amoswap.d.rl zero). */
static void EmitLockLeave(U8 *pass_buf, U8 **pass_ptr, I64 *rip) {
  EmitLoadImm64(pass_buf, pass_ptr, rip, RV_T0, (I64)HOLYC_STMT_LOCK_ADDR);
  RVU32(pass_buf, pass_ptr, rip, RvAmo(0x01, 1, (U32)g_wd3, RV_ZERO, RV_T0, RV_ZERO));  // amoswap.d.rl zero,zero,(t0)
}
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
    if (g_xlen == 32) RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_S1 << 7) | (RV_A1 << 15));  // mv s1, a1: arg hi
    RVU32(pass_buf, pass_ptr, rip, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    (*stack_depth)--;
  }

  if (pc_target) {
    EmitJalToLabel(pass_buf, pass_ptr, rip, pc_target, RV_RA);
  } else if (import_var && cc->aot_data_layout) {
    // Runtime import: the slot lives in the data section; the loader fills it by name.
    EmitGlobalAddr(pass_buf, pass_ptr, rip, cc, RV_T0, import_var, cc->aot_data_base);
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_T0 << 15));
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
    RVU32(pass_buf, pass_ptr, rip, 0x03 | (RV_T0 << 7) | (g_wd3<<12) | (RV_T0 << 15));
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
  RVU32(pass_buf, pass_ptr, rip, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (g_wd3<<12));
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

void ICEmitRegsSnap(Compiler *cc) {
  ICAdd(cc, IC_REGS_SNAP, 0, RT_I0);
}

// ═══════════════════════════════════════════════════════════════
// CODE GENERATION (AOT)
// ═══════════════════════════════════════════════════════════════

// O1-lite: map of frame offsets promoted to callee-saved s1–s8 (per function).
static I64 g_o1_off[8];
static int g_o1_reg[8], g_o1_n;

static void O1LoadMapFromFun(CIntermediateCode *enter) {
  g_o1_n = 0;
  for (CIntermediateCode *p = enter->next; p && p->ic_code != IC_LEAVE; p = p->next) {
    if (!(p->ic_flags & ICF_REG_LOCAL) || g_o1_n >= 8) continue;
    int seen = 0;
    for (int i = 0; i < g_o1_n; i++)
      if (g_o1_reg[i] == p->arg1.reg) { seen = 1; break; }
    if (!seen) {
      g_o1_off[g_o1_n] = p->ic_data;
      g_o1_reg[g_o1_n++] = p->arg1.reg;
    }
  }
}

/* PUSHFD parks mstatus on sp and POPFD pops it, neither tracked in stack_depth, and a single
 * PUSHFD routinely has several POPFD exits — so a linear walk cannot say how many flag slots are
 * parked at a given statement boundary. IC_END_EXP's exact `sp = s0 - frame` restore would
 * discard them (it silently ate Spawn's / TaskExe's saved mstatus). In such functions keep the
 * old static pop, which those stock kernel CLI/STI windows already ran correctly. */
static bool FnParksFlags(CIntermediateCode *enter) {
  for (CIntermediateCode *p = enter->next; p; p = p->next) {
    if (p->ic_code == IC_LEAVE) return false;
    if (p->ic_code == IC_PUSHFD) return true;
  }
  return false;
}
static I64 EmitIC_ENTER(U8 *b, U8 **q, I64 *r, CIntermediateCode *ic) {
  I64 n = ic->ic_data & 0xffffffff, l = ic->ic_data >> 32;
  I64 rp = n > 8 ? 8 : n, f = 16 + rp * 8 + l;
  O1LoadMapFromFun(ic);
  O1SlotClear();
  EmitAddImm(b, q, r, RV_SP, RV_SP, -f);
  RVU32(b, q, r, 0x23 | (g_wd3<<12) | (RV_SP << 15) | (RV_RA << 20));           // sd ra, 0(sp)
  RVU32(b, q, r, 0x23 | (8 << 7) | (g_wd3<<12) | (RV_SP << 15) | (RV_S0 << 20)); // sd s0, 8(sp)
  EmitAddImm(b, q, r, RV_S0, RV_SP, f);
  // Spill caller's sN into the promoted local's frame slot (never into stack-arg slots: off>=0).
  for (int j = 0; j < g_o1_n; j++) {
    if (g_o1_off[j] >= 0) continue;
    U32 w = StoreA0ToRs1Off(RT_I64, RV_S0, g_o1_off[j]);
    RVU32(b, q, r, (w & ~(31u << 20)) | ((U32)g_o1_reg[j] << 20));
  }
  for (I64 i = 0; i < rp; i++) {
    I64 o = -(f - 16 - i * 8);
    int j;
    for (j = 0; j < g_o1_n && g_o1_off[j] != o; j++) {}
    if (j < g_o1_n)
      RVU32(b, q, r, 0x13 | ((U32)g_o1_reg[j] << 7) | ((RV_A0 + i) << 15)); // mv sN, a_i
    else {
      I64 so = 16 + i * 8;
      g_rv32_args = RV32_ARG_SPILL;
      RVU32(b, q, r, 0x23 | ((so & 31) << 7) | (g_wd3<<12) | (RV_SP << 15) |
                     ((RV_A0 + i) << 20) | ((so >> 5) << 25));
      g_rv32_args = 0;
    }
  }
  return f;
}

static void EmitIC_LEAVE(U8 *b, U8 **q, I64 *r, CIntermediateCode *ic) {
  I64 n = ic->ic_data & 0xffffffff, l = ic->ic_data >> 32;
  I64 rp = n > 8 ? 8 : n, f = 16 + rp * 8 + l;
  for (int i = 0; i < g_o1_n; i++) {
    if (g_o1_off[i] >= 0) continue;
    U32 w = DerefLoadFromRs1Off(RT_I64, RV_S0, g_o1_off[i]);
    RVU32(b, q, r, (w & ~(31u << 7)) | ((U32)g_o1_reg[i] << 7)); // ld sN, off(s0)
  }
  EmitAddImm(b, q, r, RV_SP, RV_S0, -f);
  RVU32(b, q, r, 0x03 | (RV_RA << 7) | (g_wd3<<12) | (RV_SP << 15));
  RVU32(b, q, r, 0x03 | (RV_S0 << 7) | (g_wd3<<12) | (RV_SP << 15) | (8 << 20));
  EmitAddImm(b, q, r, RV_SP, RV_SP, f);
  RVU32(b, q, r, 0x67 | (RV_RA << 15)); // ret
  g_o1_n = 0;
  O1SlotClear();
}

// IC_MOV after O1 fold = former LEA+DEREF: load local/param into a0 and push.
static void EmitIC_MOV(U8 *b, U8 **q, I64 *r, I64 *d, CIntermediateCode *ic) {
  U8 pty = ic->arg1_type_pointed_to;
  if (!pty) pty = RT_I64;
  if (ic->ic_flags & ICF_REG_LOCAL)
    RVU32(b, q, r, 0x13 | (RV_A0 << 7) | ((U32)ic->arg1.reg << 15)); // mv a0, sN
  else
    RVU32(b, q, r, DerefLoadFromRs1Off(pty, RV_S0, ic->ic_data));
  RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(b, q, r, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (g_wd3<<12));
  (*d)++;
}

// Frame-slot ASSIGN: value on stack → s0+off or promoted reg; leave result pushed.
static void EmitIC_ASSIGN(U8 *b, U8 **q, I64 *r, I64 *d, CIntermediateCode *ic) {
  U8 pty = ic->arg1_type_pointed_to;
  if (!pty) pty = RT_I64;
  if (*d) {
    RVU32(b, q, r, 0x03 | (RV_A0 << 7) | (g_wd3<<12) | (RV_SP << 15));
    RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (8 << 20));
    (*d)--;
  }
  if (ic->ic_flags & ICF_REG_LOCAL)
    RVU32(b, q, r, 0x13 | ((U32)ic->arg1.reg << 7) | (RV_A0 << 15)); // mv sN, a0
  else
    RVU32(b, q, r, StoreA0ToRs1Off(pty, RV_S0, ic->ic_data));
  RVU32(b, q, r, 0x13 | (RV_SP << 7) | (RV_SP << 15) | (0xFF8 << 20));
  RVU32(b, q, r, 0x23 | (RV_SP << 15) | (RV_A0 << 20) | (g_wd3<<12));
  (*d)++;
}

// ---- Optimization passes on the IC stream (safe: the emitter re-resolves labels each pass) ----
// Tier 2: constant folding + algebraic identities. IC_IMM_I64 auto-pushes, so `2+3` is the node
// sequence IMM(2), IMM(3), ADD -- fold adjacent IMM;IMM;binop to one IMM, and drop identity ops
// (x+0, x*1, ...). Only sign-agnostic ops are folded (ADD/SUB/MUL keep the same low 64 bits for
// signed and unsigned; AND/OR/XOR are bitwise) -- DIV/MOD/shifts are left alone to avoid a
// signedness mistake. Gated on cc->optimize.
static int IcFoldFitsI32(I64 v) { return v == (I64)(I32)v; }
static int IcFoldBinop(U8 op, I64 a, I64 b, int *ok) {
  /* Unsigned wrap so host C cannot treat overflow as UB under -O2. */
  U64 ua = (U64)a, ub = (U64)b;
  *ok = 1;
  switch (op) {
    case IC_ADD: return (I64)(ua + ub);
    case IC_SUB: return (I64)(ua - ub);
    case IC_MUL: return (I64)(ua * ub);
    case IC_AND: return (I64)(ua & ub);
    case IC_OR:  return (I64)(ua | ub);
    case IC_XOR: return (I64)(ua ^ ub);
    default: *ok = 0; return 0;
  }
}
/* True when a frame slot is a full 64-bit local (safe to keep in an sN without trunc/ext).
 * Require an explicit RT_I64/RT_U64 — unset (0) must not count as wide: Gr* U8/U32 slots
 * sometimes lack pointed_to on MOV and must stay memory-backed for truncating stores. */
static int O1IsWideLocal(U8 pty) {
  return pty == RT_I64 || pty == RT_U64;
}
/* Conservative eval-stack net for FRAME_SLOT matching (addr under RHS value). */
static int IcNetStack(CIntermediateCode *p) {
  switch (p->ic_code) {
  case IC_IMM_I64: case IC_IMM_F64: case IC_STR_CONST: case IC_MOV: case IC_DEREF:
  case IC_PUSH_ARG: case IC_FN_ADDR: case IC_PC: case IC_ADDR:
  /* EmitIncDec always pushes the old/new value (same as DEREF). */
  case IC_PP_: case IC_MM_: case IC__PP: case IC__MM: return 1;
  case IC_ADD: case IC_SUB: case IC_MUL: case IC_DIV: case IC_MOD:
  case IC_AND: case IC_OR: case IC_XOR: case IC_SHL: case IC_SHR: case IC_USHR:
  case IC_FADD: case IC_FSUB: case IC_FMUL: case IC_FDIV:
  case IC_LESS: case IC_GREATER: case IC_LESS_EQU: case IC_GREATER_EQU:
  case IC_EQU_EQU: case IC_NOT_EQU:
  case IC_ULESS: case IC_ULESS_EQU: case IC_UGREATER: case IC_UGREATER_EQU:
  case IC_CHAIN_AND: case IC_BLOCK_COPY: return -1;
  case IC_ASSIGN:
    return (p->ic_flags & ICF_FRAME_SLOT) ? 0 : -1;
  case IC_EVAL_DROP:
    return p->ic_data > 0 ? (int)(-(p->ic_data / 8)) : (int)((-p->ic_data) / 8);
  case IC_CALL: case IC_CALL_INDIRECT: case IC_CALL_INDIRECT2:
    return 1 - (int)p->ic_flags;
  default: return 0;
  }
}
static int O1OffFits12(I64 off) { return off >= -2048 && off <= 2047; }
/* LEA+DEREF→MOV, LEA+PUSH_ARG…ASSIGN→FRAME_SLOT, then optional s1–s8 promotion. */
static void IcOptFrameAccess(Compiler *cc) {
  int mode = O1Mode();
  if (mode < 1) return;
  int changed = 1;
  while (changed) {
    changed = 0;
    for (CIntermediateCode *p = cc->ic_head; p; p = p->next) {
      CIntermediateCode *n = p->next;
      /* Direct ld/sd imm(s0) only encodes a 12-bit signed offset; keep LEA for large frames. */
      if (p->ic_code == IC_LEA && n && n->ic_code == IC_DEREF && O1OffFits12(p->ic_data)) {
        p->ic_code = IC_MOV;
        if (n->arg1_type_pointed_to)
          p->arg1_type_pointed_to = n->arg1_type_pointed_to;
        else if (!p->arg1_type_pointed_to)
          p->arg1_type_pointed_to = RT_I64;
        n->ic_code = IC_NOP1;
        changed = 1;
        continue;
      }
      if (mode < 2) continue;
      /* Varargs / call argv: LEA; PUSH_ARG; PUSH_RES — address must stay on the eval stack.
       * Do not walk into a call: `v = MStrPrint(fmt, doc->cur_bin_num++)` is LEA v; PUSH;
       * CALL_START; …; ASSIGN(argv) — folding that ASSIGN onto v corrupts argc/argv (PsmMenu BI). */
      if (p->ic_code == IC_LEA && n && n->ic_code == IC_PUSH_ARG && O1OffFits12(p->ic_data) &&
          (!n->next || n->next->ic_code != IC_PUSH_RES)) {
        int depth = 1;
        for (CIntermediateCode *q = n->next; q; q = q->next) {
          if (q->ic_code == IC_LABEL) break;
          if (q->ic_code == IC_CALL_START || q->ic_code == IC_CALL ||
              q->ic_code == IC_CALL_INDIRECT || q->ic_code == IC_CALL_INDIRECT2)
            break;
          if (q->ic_code == IC_ASSIGN && !(q->ic_flags & ICF_FRAME_SLOT) && depth == 2) {
            q->ic_flags |= ICF_FRAME_SLOT;
            q->ic_data = p->ic_data;
            if (!q->arg1_type_pointed_to) q->arg1_type_pointed_to = RT_I64;
            p->ic_code = IC_NOP1;
            n->ic_code = IC_NOP1;
            changed = 1;
            break;
          }
          depth += IcNetStack(q);
          if (depth < 1) break;
        }
      }
    }
  }
  if (mode < 3 || getenv("HOLYC_NO_PROMOTE")) return;
  if (cc->tgt->xlen == 32) return;   // s1-s8 hold 32 bits; an I64 local would need two
  for (CIntermediateCode *e = cc->ic_head; e; ) {
    if (e->ic_code != IC_ENTER) { e = e->next; continue; }
    I64 off[64], loads[64], uses[64];
    Bool esc[64], wide[64];
    int c = 0, any_lea = 0;
    CIntermediateCode *z = e->next;
    /* Narrow (U8/U16/U32) slots are never promoted — REG_LOCAL emit is full-width mv.
     * If the function takes the address of any frame slot, skip promotion entirely:
     * field offsets of aggregates are otherwise hard to prove non-aliasing. */
    for (; z && z->ic_code != IC_LEAVE; z = z->next) {
      I64 o; int i = -1;
      if (z->ic_code == IC_LEA || z->ic_code == IC_ADDR) {
        any_lea = 1;
        o = z->ic_data;
        for (int j = 0; j < c; j++) if (off[j] == o) i = j;
        if (i < 0 && c < 64) {
          i = c; off[c] = o; loads[c] = uses[c] = 0; esc[c] = TRUE; wide[c] = FALSE; c++;
        } else if (i >= 0) esc[i] = TRUE;
        continue;
      }
      if (z->ic_code == IC_MOV ||
          (z->ic_code == IC_ASSIGN && (z->ic_flags & ICF_FRAME_SLOT))) {
        o = z->ic_data;
        for (int j = 0; j < c; j++) if (off[j] == o) i = j;
        if (i < 0 && c < 64) {
          i = c; off[c] = o; loads[c] = uses[c] = 0; esc[c] = FALSE;
          wide[c] = O1IsWideLocal(z->arg1_type_pointed_to); c++;
        }
        if (i >= 0) {
          uses[i]++;
          if (z->ic_code == IC_MOV) loads[i]++;
          if (!O1IsWideLocal(z->arg1_type_pointed_to)) wide[i] = FALSE;
        }
      }
    }
    if (any_lea) { e = z ? z->next : NULL; continue; }
    /* Non-leaf promotion is unsafe until promoted locals have a spill home distinct from
     * the caller's sN save slot (calls / host RT can otherwise desync mem vs reg). */
    {
      int has_call = 0;
      for (CIntermediateCode *q = e->next; q && q != z; q = q->next)
        if (q->ic_code == IC_CALL || q->ic_code == IC_CALL_INDIRECT ||
            q->ic_code == IC_CALL_INDIRECT2) { has_call = 1; break; }
      if (has_call) { e = z ? z->next : NULL; continue; }
    }
    // Skip off>=0: stack args live in the caller's frame (s0+0,+8,…). Spilling a callee-saved
    // reg there at ENTER would clobber Get11th's k / argc staging / similar.
    for (int k = 0; k < 8; k++) {
      int best = -1;
      for (int i = 0; i < c; i++)
        if (!esc[i] && wide[i] && loads[i] > 0 && off[i] < 0 && O1OffFits12(off[i]) &&
            (best < 0 || uses[i] > uses[best])) best = i;
      if (best < 0) break;
      int reg = k == 0 ? RV_S1 : RV_S2 + k - 1;
      for (CIntermediateCode *q = e->next; q != z; q = q->next)
        if ((q->ic_code == IC_MOV ||
             (q->ic_code == IC_ASSIGN && (q->ic_flags & ICF_FRAME_SLOT))) &&
            q->ic_data == off[best]) {
          q->ic_flags |= ICF_REG_LOCAL;
          q->arg1.reg = reg;
        }
      esc[best] = TRUE;
    }
    e = z ? z->next : NULL;
  }
}

/* Unlink [first..last] inclusive from the IC list; does not free nodes. */
static void IcUnlinkRange(Compiler *cc, CIntermediateCode *first, CIntermediateCode *last) {
  CIntermediateCode *prev = first->last, *nxt = last->next;
  if (prev) prev->next = nxt; else cc->ic_head = nxt;
  if (nxt) nxt->last = prev; else cc->ic_tail = prev;
}

/* Count JMP/BR references to lb across the whole IC list. */
static int IcLabelRefs(Compiler *cc, CLabel *lb) {
  int n = 0;
  for (CIntermediateCode *p = cc->ic_head; p; p = p->next) {
    U8 c = p->ic_code;
    if ((c == IC_JMP || c == IC_BR_ZERO || c == IC_BR_NOT_ZERO ||
         c == IC_BR_EQU_EQU || c == IC_BR_NOT_EQU || c == IC_BR_LESS ||
         c == IC_BR_GREATER_EQU || c == IC_BR_GREATER || c == IC_BR_LESS_EQU ||
         c == IC_FN_ADDR || c == IC_TRY_ENTER) &&
        (CLabel *)p->ic_data == lb)
      n++;
  }
  return n;
}

/* True if [start..end) has no nested control-flow / labels (safe to equate for arm merge). */
static int IcArmIsStraight(CIntermediateCode *start, CIntermediateCode *end) {
  for (CIntermediateCode *p = start; p && p != end; p = p->next) {
    U8 c = p->ic_code;
    if (c == IC_LABEL || c == IC_JMP || c == IC_BR_ZERO || c == IC_BR_NOT_ZERO ||
        c == IC_BR_EQU_EQU || c == IC_BR_NOT_EQU || c == IC_BR_LESS ||
        c == IC_BR_GREATER_EQU || c == IC_BR_GREATER || c == IC_BR_LESS_EQU ||
        c == IC_SWITCH || c == IC_NOBOUND_SWITCH || c == IC_TRY_ENTER ||
        c == IC_TRY_LEAVE || c == IC_THROW || c == IC_SUB_CALL)
      return 0;
  }
  return 1;
}

static int IcArmEqual(CIntermediateCode *a, CIntermediateCode *a_end,
                      CIntermediateCode *b, CIntermediateCode *b_end) {
  while (a != a_end && b != b_end) {
    if (!a || !b) return 0;
    if (a->ic_code != b->ic_code) return 0;
    if (a->ic_data != b->ic_data) return 0;
    if (a->ic_flags != b->ic_flags) return 0;
    if (a->arg1_type_pointed_to != b->arg1_type_pointed_to) return 0;
    if ((a->ic_flags & ICF_REG_LOCAL) && a->arg1.reg != b->arg1.reg) return 0;
    a = a->next;
    b = b->next;
  }
  return a == a_end && b == b_end;
}

/* IMM k; BR_ZERO/BR_NOT_ZERO → drop IMM; fold to JMP or delete branch.
 * When BR_ZERO of nonzero (if(1)…) becomes fall-through, drop a classic dead else arm
 * if the else label has no remaining refs. */
static int IcOptConstBranch(Compiler *cc) {
  int changed = 0;
  for (CIntermediateCode *ic = cc->ic_head; ic; ) {
    CIntermediateCode *br = ic->next;
    if (ic->ic_code == IC_IMM_I64 && !(ic->ic_flags & ICF_GLBL_ADDR) && br &&
        (br->ic_code == IC_BR_ZERO || br->ic_code == IC_BR_NOT_ZERO) &&
        IcFoldFitsI32(ic->ic_data)) {
      I64 v = ic->ic_data;
      int taken = (br->ic_code == IC_BR_ZERO) ? (v == 0) : (v != 0);
      CLabel *targ = (CLabel *)br->ic_data;
      CIntermediateCode *after = br->next;

      if (taken) {
        /* Always branch: drop IMM, BR → JMP. */
        br->ic_code = IC_JMP;
        IcUnlinkRange(cc, ic, ic);
        changed = 1;
        ic = after;
        continue;
      }

      /* Never taken: drop IMM + BR. Optionally delete dead else of if(1) else. */
      CIntermediateCode *then0 = after;
      IcUnlinkRange(cc, ic, br);
      changed = 1;

      /* Classic if/else: [then] JMP end; LABEL else; [else]; LABEL end — else only
       * targeted by the removed BR. */
      if (then0 && targ) {
        CIntermediateCode *p = then0, *jmp_end = NULL, *lab_else = NULL;
        while (p && p->ic_code != IC_LABEL) {
          if (p->ic_code == IC_JMP) jmp_end = p;
          p = p->next;
        }
        if (p && p->ic_code == IC_LABEL && (CLabel *)p->ic_data == targ)
          lab_else = p;
        if (jmp_end && lab_else && jmp_end->next == lab_else &&
            IcArmIsStraight(then0, jmp_end) && IcLabelRefs(cc, targ) == 0) {
          CLabel *end_lb = (CLabel *)jmp_end->ic_data;
          CIntermediateCode *lab_end = lab_else->next;
          while (lab_end &&
                 !(lab_end->ic_code == IC_LABEL && (CLabel *)lab_end->ic_data == end_lb))
            lab_end = lab_end->next;
          if (lab_end && IcArmIsStraight(lab_else->next, lab_end) &&
              IcLabelRefs(cc, end_lb) == 1) {
            /* Drop JMP end + LABEL else + else body; keep LABEL end (join). */
            IcUnlinkRange(cc, jmp_end, lab_end->last);
          }
        }
      }
      ic = then0;
      continue;
    }
    ic = ic->next;
  }
  return changed;
}

/* if (c) { A } else { A } with straight identical arms → just A (drop branch/jmp/labels). */
static int IcOptIfElseTailMerge(Compiler *cc) {
  int changed = 0;
  for (CIntermediateCode *br = cc->ic_head; br; br = br->next) {
    if (br->ic_code != IC_BR_ZERO) continue;
    CLabel *else_lb = (CLabel *)br->ic_data;
    CIntermediateCode *then0 = br->next;
    CIntermediateCode *p = then0, *jmp_end = NULL;
    while (p && p->ic_code != IC_LABEL) {
      if (p->ic_code == IC_JMP) jmp_end = p;
      p = p->next;
    }
    if (!jmp_end || !p || p->ic_code != IC_LABEL || (CLabel *)p->ic_data != else_lb)
      continue;
    if (jmp_end->next != p) continue; /* JMP must immediately precede else label */
    CIntermediateCode *lab_else = p;
    CLabel *end_lb = (CLabel *)jmp_end->ic_data;
    CIntermediateCode *else0 = lab_else->next;
    CIntermediateCode *lab_end = else0;
    while (lab_end &&
           !(lab_end->ic_code == IC_LABEL && (CLabel *)lab_end->ic_data == end_lb))
      lab_end = lab_end->next;
    if (!lab_end) continue;
    /* then = [then0 .. jmp_end), else = [else0 .. lab_end) */
    if (!IcArmIsStraight(then0, jmp_end) || !IcArmIsStraight(else0, lab_end))
      continue;
    if (!IcArmEqual(then0, jmp_end, else0, lab_end))
      continue;
    if (IcLabelRefs(cc, else_lb) != 1 || IcLabelRefs(cc, end_lb) != 1)
      continue;
    /* Condition value would have been popped by BR_ZERO — drop it; keep then arm. */
    br->ic_code = IC_EVAL_DROP;
    br->ic_data = 8;
    IcUnlinkRange(cc, jmp_end, lab_end);
    changed = 1; /* drain all identical if/else in one scan (boot blob size) */
  }
  return changed;
}

static int IcIsIntCmp(U8 c) { return c >= IC_EQU_EQU && c <= IC_LESS_EQU; }
static int IcIsBrCmp(U8 c) { return c >= IC_BR_EQU_EQU && c <= IC_BR_LESS_EQU; }

/* EQU_EQU…LESS_EQU followed by BR_ZERO/BR_NOT_ZERO → IC_BR_* (TempleOS OptBr*).
 * When RHS is a nearby IMM_I64, attach ICF_CMP_IMM and drop the IMM (lhs stays on stack). */
static int IcOptCmpToBranch(Compiler *cc) {
  int changed = 0;
  for (CIntermediateCode *br = cc->ic_head; br; br = br->next) {
    if (br->ic_code != IC_BR_ZERO && br->ic_code != IC_BR_NOT_ZERO) continue;
    CIntermediateCode *cmp = br->last;
    while (cmp && (cmp->ic_code == IC_NOP1 || cmp->ic_code == IC_NOP2)) cmp = cmp->last;
    if (!cmp || !IcIsIntCmp(cmp->ic_code)) continue;
    U8 neu;
    if (br->ic_code == IC_BR_NOT_ZERO)
      neu = (U8)(cmp->ic_code + (IC_BR_EQU_EQU - IC_EQU_EQU));
    else
      neu = (U8)(((cmp->ic_code - IC_EQU_EQU) ^ 1) + IC_BR_EQU_EQU);
    CIntermediateCode *imm = cmp->last;
    while (imm && (imm->ic_code == IC_NOP1 || imm->ic_code == IC_NOP2)) imm = imm->last;
    br->ic_code = neu;
    if (imm && imm->ic_code == IC_IMM_I64 && !(imm->ic_flags & ICF_GLBL_ADDR) &&
        IcFoldFitsI32(imm->ic_data) && imm->next == cmp) {
      br->ic_flags |= ICF_CMP_IMM;
      br->arg2.disp = imm->ic_data;
      IcUnlinkRange(cc, imm, cmp);
    } else {
      IcUnlinkRange(cc, cmp, cmp);
    }
    changed = 1;
  }
  return changed;
}

/* Scratch on CLabel during BoolElide only (emit overwrites addr). */
#define LB_F_BAD_EDGE  0x10000

static void IcBoolElideBuildStats(Compiler *cc) {
  for (CIntermediateCode *p = cc->ic_head; p; p = p->next) {
    if (p->ic_code != IC_LABEL) continue;
    CLabel *lb = (CLabel *)p->ic_data;
    if (!lb) continue;
    lb->addr = 0; /* temp ref count */
    lb->flags &= ~LB_F_BAD_EDGE;
  }
  for (CIntermediateCode *p = cc->ic_head; p; p = p->next) {
    U8 c = p->ic_code;
    if (!(c == IC_JMP || c == IC_BR_ZERO || c == IC_BR_NOT_ZERO || IcIsBrCmp(c) ||
          c == IC_FN_ADDR || c == IC_TRY_ENTER))
      continue;
    CLabel *lb = (CLabel *)p->ic_data;
    if (!lb) continue;
    lb->addr++;
    if (c == IC_JMP) continue;
    if (!IcIsBrCmp(c)) lb->flags |= LB_F_BAD_EDGE;
  }
}

/* Retarget JMP/BR/BrCmp that point at `from` to `to`. Required when deleting a
 * short-circuit label after a prior OR elision turned an outer AND's BR_ZERO into
 * a JMP to that label — missing JMP here left VCmd with `j` to a deleted addr
 * (illegal insn). */
static void IcRetargetLabel(Compiler *cc, CLabel *from, CLabel *to) {
  for (CIntermediateCode *p = cc->ic_head; p; p = p->next) {
    U8 c = p->ic_code;
    if ((c == IC_JMP || c == IC_BR_ZERO || c == IC_BR_NOT_ZERO || IcIsBrCmp(c)) &&
        (CLabel *)p->ic_data == from)
      p->ic_data = (I64)to;
  }
}

/* Parser || / && manufacture IMM 0/1 then BR_ZERO/NOT_ZERO → direct then/else.
 * Nested `(a||b) && c`: OR elision turns AND's BR_ZERO into JMP F; AND elision
 * must IcRetargetLabel(F → Else) including that JMP.
 *
 * One O(n) stats pass per elision (not per BR candidate) — boot blob was O(n²). */
static int IcOptLogicalBoolElide(Compiler *cc) {
  int changed = 0;
  for (;;) {
    IcBoolElideBuildStats(cc);
    int progress = 0;
    for (CIntermediateCode *ifbr = cc->ic_head; ifbr; ifbr = ifbr->next) {
      if (ifbr->ic_code != IC_BR_ZERO && ifbr->ic_code != IC_BR_NOT_ZERO) continue;
      CIntermediateCode *lab_e = ifbr->last;
      if (!lab_e || lab_e->ic_code != IC_LABEL) continue;
      CLabel *e = (CLabel *)lab_e->ic_data;
      CIntermediateCode *imm1 = lab_e->last;
      if (!imm1 || imm1->ic_code != IC_IMM_I64 || (imm1->ic_flags & ICF_GLBL_ADDR)) continue;
      CIntermediateCode *lab_t = imm1->last;
      if (!lab_t || lab_t->ic_code != IC_LABEL) continue;
      CLabel *t = (CLabel *)lab_t->ic_data;
      CIntermediateCode *jmp_e = lab_t->last;
      if (!jmp_e || jmp_e->ic_code != IC_JMP || (CLabel *)jmp_e->ic_data != e) continue;
      CIntermediateCode *imm0 = jmp_e->last;
      if (!imm0 || imm0->ic_code != IC_IMM_I64 || (imm0->ic_flags & ICF_GLBL_ADDR)) continue;
      int is_or = (imm0->ic_data == 0 && imm1->ic_data == 1);
      int is_and = (imm0->ic_data == 1 && imm1->ic_data == 0);
      if (!is_or && !is_and) continue;
      if (!e || !t || e->addr != 1 || t->addr < 1) continue;
      if (t->flags & LB_F_BAD_EDGE) continue; /* value edges keep bool manufacture */

      if (is_or && ifbr->ic_code == IC_BR_ZERO) {
        ifbr->ic_code = IC_JMP;
        IcUnlinkRange(cc, imm0, jmp_e);
        IcUnlinkRange(cc, imm1, lab_e);
        if (lab_t->next == ifbr) {
          IcUnlinkRange(cc, lab_t, lab_t);
          lab_t->next = ifbr->next;
          lab_t->last = ifbr;
          if (ifbr->next) ifbr->next->last = lab_t;
          else cc->ic_tail = lab_t;
          ifbr->next = lab_t;
        }
        progress = 1;
        break;
      }
      if (is_or && ifbr->ic_code == IC_BR_NOT_ZERO) {
        IcRetargetLabel(cc, t, (CLabel *)ifbr->ic_data);
        IcUnlinkRange(cc, imm0, ifbr);
        progress = 1;
        break;
      }
      if (is_and && ifbr->ic_code == IC_BR_ZERO) {
        IcRetargetLabel(cc, t, (CLabel *)ifbr->ic_data);
        IcUnlinkRange(cc, imm0, ifbr);
        progress = 1;
        break;
      }
    }
    if (!progress) break;
    changed = 1;
  }
  return changed;
}

/* True if [call..jmp] is CALL (+ CALL_END) (+ END_EXP) JMP — statement call then goto/continue. */
static int IcIsCallThenJmp(CIntermediateCode *call, CIntermediateCode *jmp,
                          CIntermediateCode **out_end_exp) {
  if (out_end_exp) *out_end_exp = NULL;
  if (!call || !jmp) return 0;
  if (call->ic_code != IC_CALL && call->ic_code != IC_CALL_INDIRECT2) return 0;
  if (call->ic_flags != 0) return 0; /* arity 0 only (VClrCnt) */
  CIntermediateCode *p = call->next;
  if (p && p->ic_code == IC_CALL_END) p = p->next;
  if (p && p->ic_code == IC_END_EXP) {
    if (out_end_exp) *out_end_exp = p;
    p = p->next;
  }
  return p == jmp && jmp->ic_code == IC_JMP;
}

/* CALL X; END_EXP; JMP L ×N → one shared CALL+END_EXP+JMP; others JMP share. */
static int IcOptCallJmpTailMerge(Compiler *cc) {
  int changed = 0;
  for (CIntermediateCode *jmp = cc->ic_head; jmp; jmp = jmp->next) {
    if (jmp->ic_code != IC_JMP) continue;
    CIntermediateCode *call = jmp->last;
    while (call && (call->ic_code == IC_END_EXP || call->ic_code == IC_CALL_END ||
                    call->ic_code == IC_NOP1 || call->ic_code == IC_NOP2))
      call = call->last;
    CIntermediateCode *end_exp = NULL;
    if (!IcIsCallThenJmp(call, jmp, &end_exp)) continue;
    CLabel *dest = (CLabel *)jmp->ic_data;
    for (CIntermediateCode *j2 = cc->ic_head; j2 && j2 != jmp; j2 = j2->next) {
      if (j2->ic_code != IC_JMP || (CLabel *)j2->ic_data != dest) continue;
      CIntermediateCode *c2 = j2->last;
      while (c2 && (c2->ic_code == IC_END_EXP || c2->ic_code == IC_CALL_END ||
                    c2->ic_code == IC_NOP1 || c2->ic_code == IC_NOP2))
        c2 = c2->last;
      CIntermediateCode *ee2 = NULL;
      if (!IcIsCallThenJmp(c2, j2, &ee2)) continue;
      if (c2->ic_code != call->ic_code || c2->ic_data != call->ic_data) continue;
      if (call->ic_code == IC_CALL_INDIRECT2 && c2->ic_class != call->ic_class) continue;
      /* Keep c2..j2; replace call..jmp with JMP to label at c2. */
      CLabel *share = LabelNew(cc, NULL);
      CIntermediateCode *lab = ICNew(cc, IC_LABEL);
      if (!lab || !share) return changed;
      lab->ic_data = (I64)share;
      share->defined = true;
      lab->last = c2->last;
      lab->next = c2;
      if (c2->last) c2->last->next = lab;
      else cc->ic_head = lab;
      c2->last = lab;
      call->ic_code = IC_JMP;
      call->ic_data = (I64)share;
      call->ic_flags = 0;
      call->ic_class = NULL;
      IcUnlinkRange(cc, call->next, jmp);
      changed = 1;
      return 1;
    }
  }
  return changed;
}

/* Unconditional JMP: drop unreachable IC until next LABEL (no other IR entries).
 * Drain every match in one scan — one-per-outer-iter was O(regions×n) and hung
 * host AOT of Kernel+Compiler_RV (make kernel-win-run never left holyc-riscv). */
static int IcOptDeadAfterJmp(Compiler *cc) {
  int changed = 0;
  for (CIntermediateCode *jmp = cc->ic_head; jmp; jmp = jmp->next) {
    if (jmp->ic_code != IC_JMP) continue;
    CIntermediateCode *p = jmp->next;
    if (!p || p->ic_code == IC_LABEL || p->ic_code == IC_LEAVE || p->ic_code == IC_ENTER)
      continue;
    CIntermediateCode *last = p;
    while (last->next && last->next->ic_code != IC_LABEL &&
           last->next->ic_code != IC_LEAVE && last->next->ic_code != IC_ENTER)
      last = last->next;
    IcUnlinkRange(cc, p, last);
    changed = 1;
  }
  return changed;
}

static void IcOptimize(Compiler *cc) {
  if (!cc->optimize) return;
  /* Tier-2 on by default. HOLYC_NO_TIER2=1 disables (bisect). */
  int changed = getenv("HOLYC_NO_TIER2") ? 0 : 1;
  int guard = 0;
  HolyProgress("optimize …");
  while (changed) {
    if (++guard > 50000) {
      fprintf(stderr, "IcOptimize: iteration cap (%d) — possible non-termination\n", guard);
      break;
    }
    if ((guard % 5000) == 0)
      HolyProgress("optimize … iter %d", guard);
    changed = 0;
    /* Fold/identity: apply all matches in one scan (was one-per-outer-iter → O(n²)). */
    for (CIntermediateCode *ic = cc->ic_head; ic; ) {
      CIntermediateCode *n1 = ic->next, *n2 = n1 ? n1->next : (CIntermediateCode *)0;
      if (ic->ic_code == IC_IMM_I64 && !(ic->ic_flags & ICF_GLBL_ADDR) &&
          n1 && n1->ic_code == IC_IMM_I64 && !(n1->ic_flags & ICF_GLBL_ADDR) && n2 &&
          IcFoldFitsI32(ic->ic_data) && IcFoldFitsI32(n1->ic_data)) {
        int ok; I64 r = IcFoldBinop(n2->ic_code, ic->ic_data, n1->ic_data, &ok);
        if (ok && IcFoldFitsI32(r)) {
          ic->ic_data = r;
          ic->next = n2->next;
          if (n2->next) n2->next->last = ic; else cc->ic_tail = ic;
          changed = 1;
          continue; /* recheck from folded IMM */
        }
      }
      if (ic->ic_code == IC_IMM_I64 && !(ic->ic_flags & ICF_GLBL_ADDR) && n1 && ic->last &&
          ic->last->ic_code != IC_LABEL && ic->last->ic_code != IC_ENTER &&
          ic->last->ic_code != IC_NOP1) {
        U8 op = n1->ic_code; I64 v = ic->ic_data; int drop = 0;
        if ((op == IC_ADD || op == IC_SUB || op == IC_OR || op == IC_XOR) && v == 0) drop = 1;
        else if ((op == IC_MUL || op == IC_DIV) && v == 1) drop = 1;
        if (drop) {
          CIntermediateCode *prev = ic->last;
          prev->next = n1->next;
          if (n1->next) n1->next->last = prev; else cc->ic_tail = prev;
          changed = 1;
          ic = prev;
          continue;
        }
      }
      ic = ic->next;
    }
    if (!getenv("HOLYC_NO_TIER2")) {
      if (IcOptCmpToBranch(cc)) changed = 1;
      /* Bool elision on by default (BrCmp-only; JMP retarget for nested OR-in-AND).
       * HOLYC_NO_BOOL_ELIDE=1 to bisect. */
      if (!getenv("HOLYC_NO_BOOL_ELIDE") && IcOptLogicalBoolElide(cc)) changed = 1;
      if (IcOptConstBranch(cc)) changed = 1;
      if (!getenv("HOLYC_NO_TAIL_MERGE") && IcOptIfElseTailMerge(cc)) changed = 1;
      if (!getenv("HOLYC_NO_CALL_TAIL") && IcOptCallJmpTailMerge(cc)) changed = 1;
      if (!getenv("HOLYC_NO_DEAD_JMP") && IcOptDeadAfterJmp(cc)) changed = 1;
    }
  }
  IcOptFrameAccess(cc);

  HolyProgress("optimize done (%d iters)", guard);
}

/* Unified IC->machine lowering, shared by the sizing/relaxation pass and the final
 * emit pass (PR-0b). Mutable state is threaded by pointer; data_base is 0 during
 * sizing (addresses not yet placed) and the real base during emit. Extracted from
 * the emit-pass switch body verbatim — see docs/MULTIARCH.md. */
static void EmitOneIC(Compiler *cc, CIntermediateCode *ic,
                      U8 *buf, U8 **pptr, I64 *prip, I64 *psd, I64 *pcf,
                      I64 data_base, Bool is_function, Bool has_call) {
  switch (ic->ic_code) {
      case IC_ENTER:
        (*pcf) = EmitIC_ENTER(buf, pptr, prip, ic);
        if (FnParksFlags(ic)) (*pcf) = -1;   // keep the static pop; see FnParksFlags
        break;
      case IC_LEAVE:
        // A stale (*pcf) past the end of a function would aim `addi sp,s0,-N` at a foreign s0.
        (*pcf) = -1;
        EmitIC_LEAVE(buf, pptr, prip, ic); break;
        
      case IC_RBP:
        if ((*psd) > 0) {
          // addi sp, sp, -8
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          // sd a0, 0(sp)
          RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
        }
        // mv a0, s0 (addi a0, s0, 0)
        RVU32(buf, pptr, prip, 0x13 | (RV_A0<<7) | (RV_S0<<15));
        (*psd)++;
        break;
        
      case IC_LEA:
        // Load Effective Address: addi a0, s0, offset
        // Don't push - IC_PUSH_ARG handles it for assignments, IC_DEREF handles it for loads
        {
          I64 offset = ic->ic_data;
          if (offset >= -2048 && offset <= 2047) {
          RVU32(buf, pptr, prip, 0x13 | (RV_A0<<7) | (RV_S0<<15) | ((offset & 0xFFF)<<20)); // addi a0, s0, offset
          } else {
            // Large offset: LUI + ADDI
            I64 hi = (offset + 0x800) >> 12;
            I64 lo = offset & 0xFFF;
            if (lo & 0x800) lo |= 0xFFFFFFFFFFFFF000LL;
            RVU32(buf, pptr, prip, 0x37 | (RV_A0<<7) | ((hi & 0xFFFFF)<<12));
            if (lo) {
              RVU32(buf, pptr, prip, 0x13 | (RV_A0<<7) | (RV_A0<<15) | ((lo & 0xFFF)<<20));
            }
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (RV_A0<<15) | (RV_S0<<20)); // add a0, a0, s0
          }
        }
        // Don't push here - IC_PUSH_ARG will handle it for assignments, IC_DEREF handles it for loads
        break;
        
      case IC_IMM_I64:
      case IC_IMM_F64:  // F64 travels as its raw 64-bit pattern in integer registers / eval stack
        if (cc->optimize && ic->ic_code == IC_IMM_I64 && !(ic->ic_flags & ICF_GLBL_ADDR) &&
            ic->ic_data == 0 && ic->next && ic->next->ic_code == IC_ASSIGN &&
            !(ic->next->ic_flags & ICF_FRAME_SLOT)) {
          ic->next->ic_flags |= ICF_ASSIGN_ZERO;
          break;
        }
        if (ic->ic_flags == ICF_GLBL_ADDR && cc->aot_data_layout) {
          {
            CHashGlblVar *g = AOTGlobalByAddr(cc, ic->ic_data);
            EmitGlobalAddrOff(buf, pptr, prip, cc, RV_A0, g, data_base, g ? ic->ic_data - (I64)g->data_addr : 0);
          }
        } else {
          // Load immediate into a0 (full 64-bit; see EmitLoadImm64)
          EmitLoadImm64(buf, pptr, prip, RV_A0, ic->ic_data);
        }
        // Push value to stack so binary ops find it
        RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
        RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12)); // sd a0, 0(sp)
        (*psd)++;
        break;
        
      case IC_ADD:
      case IC_SUB:
      case IC_MUL:
      case IC_DIV:
      case IC_MOD:
        if ((*psd) >= 2) {
          // Pop right operand into t1
          RVU32(buf, pptr, prip, 0x03 | (RV_T1<<7) | (g_wd3<<12) | (RV_SP<<15));
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          (*psd)--;
          // Pop left operand into t0
          RVU32(buf, pptr, prip, 0x03 | (RV_T0<<7) | (g_wd3<<12) | (RV_SP<<15));
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          (*psd)--;
          // Compute result (result stays in a0)
          if (ic->ic_code == IC_ADD) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_T1<<20));
          } else if (ic->ic_code == IC_SUB) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25));
          } else if (ic->ic_code == IC_MUL) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (RV_T0<<15) | (RV_T1<<20) | (1<<25));
          } else if (ic->ic_code == IC_DIV) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (4<<12) | (RV_T0<<15) | (RV_T1<<20) | (1<<25));
          } else if (ic->ic_code == IC_MOD) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (6<<12) | (RV_T0<<15) | (RV_T1<<20) | (1<<25));
          }
          // Push result back
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
          (*psd)++;
        }
        break;
      case IC_AND:
      case IC_OR:
      case IC_XOR:
      case IC_SHL:
      case IC_SHR:
        if ((*psd) == 1) {
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
          (*psd)++;
        }
        if ((*psd) >= 2) {
          RVU32(buf, pptr, prip, 0x03 | (RV_T1<<7) | (g_wd3<<12) | (RV_SP<<15));
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          (*psd)--;
          RVU32(buf, pptr, prip, 0x03 | (RV_T0<<7) | (g_wd3<<12) | (RV_SP<<15));
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          (*psd)--;
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
            RVU32(buf, pptr, prip, inst);
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
            RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
            (*psd)++;
          }
        }
        break;
        
      case IC_EVAL_DROP:
        {
          I64 adj = ic->ic_data;
          if (adj != 0) {
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((adj & 0xFFF)<<20));
            if (adj > 0)
              (*psd) -= adj / 8;
            else
              (*psd) += (-adj) / 8;
          }
        }
        break;
      case IC_DEREF:
        RVU32(buf, pptr, prip, DerefLoadFromRs1(ic->arg1_type_pointed_to, RV_A0));
        RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
        RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12)); // sd a0, 0(sp)
        (*psd)++;
        break;
      case IC_BLOCK_COPY:
        EmitBlockCopy(buf, pptr, prip, psd, ic->ic_data);
        break;
      case IC_ASSIGN:
        if (ic->ic_flags & ICF_FRAME_SLOT) { EmitIC_ASSIGN(buf,pptr,prip,psd,ic); break; }
        if (ic->ic_flags & ICF_ASSIGN_ZERO) {
          EmitAssignStoreZero(buf, pptr, prip, psd, ic);
          break;
        }
        if ((*psd) >= 1) {
          if ((*psd) >= 2) {
            RVU32(buf, pptr, prip, 0x03 | (RV_T1<<7) | (g_wd3<<12) | (RV_SP<<15)); // ld t1, 0(sp) - pop value
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
            (*psd)--;
            RVU32(buf, pptr, prip, 0x13 | (RV_A0<<7) | (RV_T1<<15)); // mv a0, t1
          }

          RVU32(buf, pptr, prip, 0x03 | (RV_T0<<7) | (g_wd3<<12) | (RV_SP<<15));
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          (*psd)--;

          RVU32(buf, pptr, prip, StoreA0ToRs1(ic->arg1_type_pointed_to, RV_T0)); // typed store a0 -> (t0)
          // Assignment is an expression: leave the value in a0 and on the eval stack (IC_END_EXP drops it).
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
          (*psd)++;
        } else {
          RVU32(buf, pptr, prip, 0x13 | (RV_T0<<7) | (RV_A0<<15));
          RVU32(buf, pptr, prip, StoreA0ToRs1(ic->arg1_type_pointed_to, RV_T0)); // typed store a0 -> (t0)
          // Assignment is an expression: leave the value in a0 and on the eval stack (IC_END_EXP drops it).
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
          (*psd)++;
        }
        break;
      case IC_PUSH_ARG:
        // Push argument to stack (don't clear a0 - let IC_IMM_I64 handle it)
        RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20)); // addi sp, sp, -8
        RVU32(buf, pptr, prip, 0x23 | (0<<7) | (g_wd3<<12) | (RV_SP<<15) | (RV_A0<<20) | (0<<25)); // sd a0, 0(sp)
        (*psd)++;
        break;
      case IC_POP_ARG:
        // Pop argument from stack
        RVU32(buf, pptr, prip, 0x03 | (RV_A0<<7) | (g_wd3<<12) | (RV_SP<<15) | (0<<20)); // ld a0, 0(sp)
        RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
        (*psd)--;
        break;
      case IC_LESS:
      case IC_GREATER:
      case IC_LESS_EQU:
      case IC_GREATER_EQU:
      case IC_EQU_EQU:
      case IC_NOT_EQU:
        if ((*psd) == 1) {
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
          (*psd)++;
        }
        if ((*psd) >= 2) {
          RVU32(buf, pptr, prip, 0x03 | (RV_T1<<7) | (g_wd3<<12) | (RV_SP<<15));
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          (*psd)--;
          RVU32(buf, pptr, prip, 0x03 | (RV_T0<<7) | (g_wd3<<12) | (RV_SP<<15));
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          (*psd)--;
          if (ic->ic_code == IC_LESS) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T0<<15) | (RV_T1<<20));
          } else if (ic->ic_code == IC_GREATER) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T1<<15) | (RV_T0<<20));
          } else if (ic->ic_code == IC_LESS_EQU) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T1<<15) | (RV_T0<<20));
            RVU32(buf, pptr, prip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20));
          } else if (ic->ic_code == IC_GREATER_EQU) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (0x2<<12) | (RV_T0<<15) | (RV_T1<<20));
            RVU32(buf, pptr, prip, 0x13 | (RV_A0<<7) | (4<<12) | (RV_A0<<15) | (1<<20));
          } else if (ic->ic_code == IC_EQU_EQU) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (0x0<<12) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25));
            RVU32(buf, pptr, prip, 0x13 | (RV_A0<<7) | (3<<12) | (RV_A0<<15) | (1<<20));
          } else if (ic->ic_code == IC_NOT_EQU) {
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (0x0<<12) | (RV_T0<<15) | (RV_T1<<20) | (0x20<<25));
            RVU32(buf, pptr, prip, 0x33 | (RV_A0<<7) | (0x3<<12) | (RV_ZERO<<15) | (RV_A0<<20));
          }
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
          (*psd)++;
        }
        break;
      case IC_BR_ZERO:
        {
          if ((*psd) > 0) {
            RVU32(buf, pptr, prip, 0x03 | (RV_A0<<7) | (g_wd3<<12) | (RV_SP<<15));
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
            (*psd)--;
          }

          CLabel *lb = (CLabel*)ic->ic_data;
          EmitCondBranch(buf, pptr, prip, ic, true, lb);
          lb->sd = (*psd); lb->sd_set = true;   // the taken path reaches lb at this depth; fall-through keeps it
        }
        break;
      case IC_BR_NOT_ZERO:
        {
          if ((*psd) > 0) {
            RVU32(buf, pptr, prip, 0x03 | (RV_A0<<7) | (g_wd3<<12) | (RV_SP<<15));
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
            (*psd)--;
          }

          CLabel *lb = (CLabel*)ic->ic_data;
          EmitCondBranch(buf, pptr, prip, ic, false, lb);
          lb->sd = (*psd); lb->sd_set = true;
        }
        break;
      case IC_BR_EQU_EQU:
      case IC_BR_NOT_EQU:
      case IC_BR_LESS:
      case IC_BR_GREATER_EQU:
      case IC_BR_GREATER:
      case IC_BR_LESS_EQU:
        EmitIC_BrCmp(buf, pptr, prip, psd, ic);
        break;
      case IC_JMP:
        {
          CLabel *lb = (CLabel*)ic->ic_data;
          lb->sd = (*psd); lb->sd_set = true;   // the jump reaches lb at this depth
          EmitJump(buf, pptr, prip, ic, lb);
        }
        break;
      case IC_MOV:
        EmitIC_MOV(buf,pptr,prip,psd,ic); break;
        // Load from parameter or local variable
        // For now, handles simple register loads and stack loads
        if ((*psd) > 0) {
          // addi sp, sp, -8
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          // sd a0, 0(sp)
          RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
        }
        // ld a0, offset(s0) - simplified, actual depends on ic_data
        RVU32(buf, pptr, prip, 0x03 | (RV_A0<<7) | (g_wd3<<12) | (RV_S0<<15) | ((ic->ic_data & 0xFFF)<<20));
        (*psd)++;
        break;
      case IC_CALL_INDIRECT:
        {
          I64 arg_count = ic->ic_flags;  // set by the parser on this call IC

          RVU32(buf, pptr, prip, 0x03 | (RV_T1<<7) | (g_wd3<<12) | (RV_SP<<15));
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
          (*psd)--;

          if (arg_count > 8) {
            EmitPrepareGt8CallArgs(buf, pptr, prip, arg_count);
          } else if (arg_count >= 2 && arg_count <= 8) {
            EmitLoadArgsFromEvalStack(buf, pptr, prip, psd, arg_count);
          } else if (arg_count == 1) {
            // The pointer load above clobbered a0: pop the single argument into it.
            g_rv32_args = RV32_ARG_LOAD;
            RVU32(buf, pptr, prip, 0x03 | (RV_A0<<7) | (g_wd3<<12) | (RV_SP<<15));
            g_rv32_args = 0;
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20));
            (*psd)--;
          }

          RVU32(buf, pptr, prip, 0x67 | (RV_RA<<7) | (RV_T1<<15));   // jalr ra, t1: the pointer is the code address

          if (arg_count > 8) {
            I64 out_sz = (arg_count - 8) * 8;
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((out_sz & 0xFFF)<<20));
            I64 eval_sz = arg_count * 8;
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((eval_sz & 0xFFF)<<20));
            (*psd) -= arg_count;
          }

          // Return value to a0 and the eval stack (same convention as EmitCallArgsAndInvoke).
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
          RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
          (*psd)++;
        }
        break;
      case IC_CALL_INDIRECT2:
        EmitCallArgsAndInvoke(buf, pptr, prip, psd, cc, NULL, (I64 *)ic->ic_data, ic->ic_flags, (CHashGlblVar *)ic->ic_class);
        break;
      case IC_CALL:
        EmitCallArgsAndInvoke(buf, pptr, prip, psd, cc, (CLabel *)ic->ic_data, NULL, ic->ic_flags, NULL);
        break;
      case IC_UNARY_MINUS: EmitUnaryOp(buf, pptr, prip, psd, RV_UNARY_MINUS); break;
      case IC_NOT:         EmitUnaryOp(buf, pptr, prip, psd, RV_LOGICAL_NOT); break;
      case IC_COM:         EmitUnaryOp(buf, pptr, prip, psd, RV_BIT_COM); break;
      case IC_ADDR:
        // Address is in a0 (the parser retracted the auto-deref after IC_LEA); publish it.
        RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(buf, pptr, prip, 0x23 | (g_wd3<<12) | (RV_SP<<15) | (RV_A0<<20));
        (*psd)++;
        break;
      case IC_ADD_EQU: EmitCompoundAssign(buf, pptr, prip, psd, RV_R_ADD); break;
      case IC_SUB_EQU: EmitCompoundAssign(buf, pptr, prip, psd, RV_R_SUB); break;
      case IC_MUL_EQU: EmitCompoundAssign(buf, pptr, prip, psd, RV_R_MUL); break;
      case IC_DIV_EQU: EmitCompoundAssign(buf, pptr, prip, psd, RV_R_DIV); break;
      case IC_AND_EQU: EmitCompoundAssign(buf, pptr, prip, psd, RV_R_AND); break;
      case IC_OR_EQU:  EmitCompoundAssign(buf, pptr, prip, psd, RV_R_OR);  break;
      case IC_XOR_EQU: EmitCompoundAssign(buf, pptr, prip, psd, RV_R_XOR); break;
      case IC_SHL_EQU: EmitCompoundAssign(buf, pptr, prip, psd, RV_R_SLL); break;
      case IC_SHR_EQU: EmitCompoundAssign(buf, pptr, prip, psd, RV_R_SRA); break;
      case IC_MOD_EQU: EmitCompoundAssign(buf, pptr, prip, psd, RV_R_REM); break;
      case IC_FADD_EQU: case IC_FSUB_EQU: case IC_FMUL_EQU: case IC_FDIV_EQU: EmitF64CompoundAssign(buf, pptr, prip, psd, ic->ic_code); break;
      case IC_PAUSE:   RVU32(buf, pptr, prip, 0x13); break;
      case IC_FN_ADDR:
        EmitLabelAddr(buf, pptr, prip, (CLabel *)ic->ic_data, RV_A0);
        RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
        (*psd)++;
        break;
      case IC_PC:      // `$$`: address of this instruction, pushed like an immediate
        RVU32(buf, pptr, prip, 0x17 | (RV_A0 << 7));                                        // auipc a0, 0
        RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
        (*psd)++;
        break;
      case IC_HLT:     RVU32(buf, pptr, prip, 0x10500073); break;   // wfi
      case IC_INT:     RVU32(buf, pptr, prip, 0x00100073); break;   // ebreak
      case IC_CHAIN_CMP: EmitChainCmp(buf, pptr, prip, psd, (int)ic->ic_data); break;
      case IC_CHAIN_AND: EmitChainAnd(buf, pptr, prip, psd); break;
      case IC_FADD: case IC_FSUB: case IC_FMUL: case IC_FDIV:
      case IC_FLESS: case IC_FLESS_EQU: case IC_FGREATER: case IC_FGREATER_EQU:
      case IC_FEQU_EQU: case IC_FNOT_EQU: case IC_FNEG: case IC_FMOD:
        EmitF64Op(buf, pptr, prip, psd, ic->ic_code);
        break;
      case IC_TO_F64: EmitF64Convert(buf, pptr, prip, ic->ic_data, TRUE);  break;
      case IC_TO_I64: EmitF64Convert(buf, pptr, prip, ic->ic_data, FALSE); break;
      case IC_UDIV: case IC_UMOD: case IC_USHR:
      case IC_ULESS: case IC_ULESS_EQU: case IC_UGREATER: case IC_UGREATER_EQU:
        EmitUnsignedOp(buf, pptr, prip, psd, ic->ic_code);
        break;
      case IC_TRY_ENTER: EmitTryEnter(buf, pptr, prip, cc, (CLabel *)ic->ic_data, data_base); break;
      case IC_TRY_LEAVE: EmitTryLeave(buf, pptr, prip, cc, data_base); break;
      case IC_THROW:     EmitThrow(buf, pptr, prip, psd, cc, data_base); break;
      case IC_CLI: case IC_STI: case IC_PUSHFD: case IC_POPFD: EmitSysIntrinsic(buf, pptr, prip, ic->ic_code); break;
      case IC_STR_CONST: {
        // PC-relative address of the literal; the bytes are appended after the code.
        StringLiteral *sl = (StringLiteral *)ic->ic_data;
        I64 rel = buf ? (sl->offset - (*prip)) : 0;
        I64 hi = (rel + 0x800) >> 12, lo = rel - (hi << 12);
        RVU32(buf, pptr, prip, 0x17 | (RV_A0<<7) | (((U32)hi & 0xFFFFF)<<12));          // auipc a0, hi
        RVU32(buf, pptr, prip, 0x13 | (RV_A0<<7) | (RV_A0<<15) | (((U32)lo & 0xFFF)<<20)); // addi a0, a0, lo
        RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF8<<20));
        RVU32(buf, pptr, prip, 0x23 | (RV_SP<<15) | (RV_A0<<20) | (g_wd3<<12));
        (*psd)++;
        break;
      }
      case IC_PP_:  EmitIncDec(buf, pptr, prip, psd,  (ic->ic_data ? ic->ic_data : 1), FALSE, ic->arg1_type_pointed_to); break;
      case IC_MM_:  EmitIncDec(buf, pptr, prip, psd, -(ic->ic_data ? ic->ic_data : 1), FALSE, ic->arg1_type_pointed_to); break;
      case IC__PP:  EmitIncDec(buf, pptr, prip, psd,  (ic->ic_data ? ic->ic_data : 1), TRUE,  ic->arg1_type_pointed_to); break;
      case IC__MM:  EmitIncDec(buf, pptr, prip, psd, -(ic->ic_data ? ic->ic_data : 1), TRUE,  ic->arg1_type_pointed_to); break;
      case IC_END_EXP:
        // End of expression statement: sp must go back to the frame base (s0 - frame_size).
        // Popping `depth*8` instead trusted a STATIC counter, and that counter diverges from
        // the real depth whenever a branch skips pushes that the fall-through path makes — the
        // pop then ran past the frame base and the next push overwrote the saved ra, so the
        // function `ret`ed into whatever a0 held. Restore from s0 (exact, path-insensitive);
        // fall back to the counter only in frameless JIT fragments (LexExpression2Bin), where
        // s0 still belongs to the caller.
        if ((*psd) > 0) {
          RVU32(buf, pptr, prip, 0x03 | (RV_A0<<7) | (g_wd3<<12) | (RV_SP<<15)); // ld a0, 0(sp)
          if ((*pcf) >= 0)
            EmitAddImm(buf, pptr, prip, RV_SP, RV_S0, -(*pcf));  // sp = frame base (exact)
          else
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | ((((*psd) * 8) & 0xFFF)<<20));
        }
        (*psd) = 0;
        break;
      case IC_PUSH_RES:
        // Push result to stack - this is just a marker, doesn't change stack_depth
        break;
      case IC_CALL_START:
      case IC_CALL_END:
        // Markers for function call boundaries
        break;
      case IC_LABEL:
        { CLabel *lb = (CLabel*)ic->ic_data;
          if (lb) lb->addr = (*prip);   /* keep map/exe_addr in sync with emitted code */
          if (lb && lb->sd_set) (*psd) = lb->sd; O1SlotClear(); }
        g_pp_n = 0;   // don't cancel a push/pop across a branch target (matches the sizing pass)
        break;
      case IC_NOP1:
      case IC_NOP2:
        // Explicit no-op – leave stack depth unchanged
        break;
      case IC_RAW_RV:
        g_rv32_raw = 1;
        RVU32(buf, pptr, prip, (U32)ic->ic_data);   // pre-assembled RISC-V word (x86 translation)
        g_rv32_raw = 0;
        break;
      case IC_REGS_SNAP:
        EmitRegsSnapStub(buf, pptr, prip);
        break;
      case IC_LOCK_ENTER:
        EmitLockEnter(buf, pptr, prip);
        break;
      case IC_LOCK_LEAVE:
        EmitLockLeave(buf, pptr, prip);
        break;
      case IC_RETURN_VAL:
      case IC_RETURN_VAL2:
        // Return value should be in a0
        // If it's on the stack, pop it to a0
        if ((*psd) > 0) {
          // Pop value from stack to a0
          RVU32(buf, pptr, prip, 0x03 | (RV_A0<<7) | (g_wd3<<12) | (RV_SP<<15)); // ld a0, 0(sp)
          RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (8<<20)); // addi sp, sp, 8
          (*psd)--;
        }
        // Convert to the DECLARED return type HERE, after the eval-stack pop -- not before it.
        // HolyC otherwise gets its narrowing from typed STORES and the sign-extending loads that
        // follow, so a value that never visits memory is never converted: an I32 status came back
        // ZERO-extended, making `f() < 0` false for a negative code, while the same value read
        // from an I32 variable compared correctly. ic_data carries the RT_ type, 0 for none.
        if (ic->ic_data) {
          U8 rsh = 0;
          Bool rsgn = TRUE;
          switch (ic->ic_data) {
          case RT_I8:  rsh = 56; rsgn = TRUE;  break;
          case RT_U8:  rsh = 56; rsgn = FALSE; break;
          case RT_I16: rsh = 48; rsgn = TRUE;  break;
          case RT_U16: rsh = 48; rsgn = FALSE; break;
          case RT_I32: rsh = 32; rsgn = TRUE;  break;
          case RT_U32: rsh = 32; rsgn = FALSE; break;
          default:     rsh = 0;  break;
          }
          if (rsh) {
            RVU32(buf, pptr, prip, 0x13 | (RV_A0 << 7) | (1 << 12) | (RV_A0 << 15) | ((U32)rsh << 20));
            RVU32(buf, pptr, prip, 0x13 | (RV_A0 << 7) | (5 << 12) | (RV_A0 << 15)
                                   | ((U32)rsh << 20) | (rsgn ? (0x20u << 25) : 0u));
          }
        }
        // Value is now in a0, ready for return
        // Do NOT adjust sp further - the epilogue expects sp at frame_base
        (*psd) = 0;
        break;
      case IC_RET:
        // Generate ret instruction with epilogue for expressions
        if (!is_function) {
          if (has_call) {
            // Epilogue: restore ra/s0 (sp from the frame pointer, s0 = entry sp + 16)
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_S0<<15) | (0xFF0<<20)); // addi sp, s0, -16
            RVU32(buf, pptr, prip, 0x03 | (RV_RA<<7) | (g_wd3<<12) | (RV_SP<<15) | (8<<20)); // ld ra, 8(sp)
            RVU32(buf, pptr, prip, 0x03 | (RV_S0<<7) | (g_wd3<<12) | (RV_SP<<15)); // ld s0, 0(sp)
            RVU32(buf, pptr, prip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (16<<20)); // addi sp, sp, 16
          }
          RVU32(buf, pptr, prip, 0x00008067); // ret
        }
        break;
      default:
        // Skip unimplemented ICs
        break;
  }
}


// rv32: the backend's one runtime helper (64-bit div/rem) follows the code of every blob.
static void EmitRv32Helpers(U8 *buf, U8 **pptr, I64 *prip) {
  if (g_xlen != 32) return;
  int n;
  const uint32_t *w = Rv32DivmodWords(&n);
  g_rv32_divmod = *prip;
  g_rv32_raw = 1;
  for (int i = 0; i < n; i++) RvEmitWord(buf, pptr, prip, w[i]);
  g_rv32_raw = 0;
}

U8 *CompileAOT(Compiler *cc, I64 *code_size) {
  if (getenv("HOLYC_NO_OPT")) cc->optimize = false;
  IcOptimize(cc);
  HolyProgress("size …");
  g_xlen = cc->tgt->xlen;
  // Tier 1 push/pop peephole (sound; kept on with O1 default). Off on rv32: it rewinds
  // emitted words by count, and Rv32Lift expands each one.
  g_pp_on = cc->optimize && g_xlen == 64;
  g_rv32_args = g_rv32_raw = 0;
  g_rv32_divmod = 0;
  Rv32LiftReset();
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
    HolyProgress("size pass %d …", pass);

    ic = cc->ic_head;
    I64 stack_depth_pass = 0;
    I64 cur_frame = -1;   // frame size of the function being emitted (-1 = frameless fragment)
    pass_ptr = NULL;

    pass_buf = NULL;
    g_pp_n = 0;   // reset the push/pop peephole window each pass
    O1SlotClear();
    
    // Add prologue for expressions with calls
    if (has_call && !is_function) {
      RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF0<<20)); // addi sp, sp, -16
      RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (8<<7) | (g_wd3<<12) | (RV_SP<<15) | (RV_RA<<20)); // sd ra, 8(sp)
      RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (0<<7) | (g_wd3<<12) | (RV_SP<<15) | (RV_S0<<20)); // sd s0, 0(sp)
      RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_S0<<7) | (RV_SP<<15) | (16<<20)); // addi s0, sp, 16
    }
    
    while (ic) {
      // Lower this IC (sizing/relaxation pass: pass_buf==NULL counts bytes; data_base=0
      // since addresses are not placed yet). EmitOneIC sets label addrs for IC_LABEL.
      EmitOneIC(cc, ic, pass_buf, &pass_ptr, &rip, &stack_depth_pass, &cur_frame, 0, is_function, has_call);

    ic = ic->next;
  }
  EmitRv32Helpers(pass_buf, &pass_ptr, &rip);
  
  // Fixed-size jmp/br encodings (always long). Pass cap of 10 used to abort mid-shrink
  // with stale label addrs → final emit `j` into auipc/addi (CInit load fault).
  } while (rip != prev_size && pass < 8);
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
  I64 sized_rip = rip;
  if (rip != prev_size) {
    fprintf(stderr, "HOLYC AOT: sizing did not converge after %d passes (last %lld → %lld)\n",
            pass, (long long)prev_size, (long long)rip);
#ifndef BARE_METAL
    return NULL;
#endif
  }

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
#ifdef BARE_METAL
  extern void *code_malloc(size_t);
  U8 *buffer = code_malloc((size_t)buf_sz);   /* lasting code; heap may reset */
#else
  U8 *buffer = malloc((size_t)buf_sz);
#endif
  if (!buffer) return NULL;

  // After convergence, do one final pass with emission enabled
  if (pass_buf == NULL) {
  HolyProgress("emit …");
  pass_buf = buffer;
  pass_ptr = buffer;
  rip = 0;
  g_pp_n = 0;   // the final emission pass is a second emit loop -- reset its peephole window too
  O1SlotClear();
  ic = cc->ic_head;
  I64 stack_depth_final = 0;
  I64 cur_frame = -1;   // frame size of the function being emitted (-1 = frameless fragment)
    
    // Add prologue for expressions with calls (same as in multi-pass loop)
    if (has_call && !is_function) {
      RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_SP<<7) | (RV_SP<<15) | (0xFF0<<20)); // addi sp, sp, -16
      RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (8<<7) | (g_wd3<<12) | (RV_SP<<15) | (RV_RA<<20)); // sd ra, 8(sp)
      RVU32(pass_buf, &pass_ptr, &rip, 0x23 | (0<<7) | (g_wd3<<12) | (RV_SP<<15) | (RV_S0<<20)); // sd s0, 0(sp)
      RVU32(pass_buf, &pass_ptr, &rip, 0x13 | (RV_S0<<7) | (RV_SP<<15) | (16<<20)); // addi s0, sp, 16
    }
    
    while (ic) {
      // Lower this IC (final emit pass: pass_buf=buffer, real data_base). Same EmitOneIC
      // as the sizing loop above — one body, no duplicated switch.
      EmitOneIC(cc, ic, pass_buf, &pass_ptr, &rip, &stack_depth_final, &cur_frame, data_base, is_function, has_call);
      
      ic = ic->next;
    }
    EmitRv32Helpers(pass_buf, &pass_ptr, &rip);
    }
  
  if (rip != sized_rip) {
    fprintf(stderr, "HOLYC AOT: emit size %lld != sized %lld (pass %d) — label/call mismatch\n",
            (long long)rip, (long long)sized_rip, pass);
#ifndef BARE_METAL
    free(buffer);
    return NULL;
#endif
  }
  
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
  HolyProgress("done (%lld bytes)", (long long)rip);
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

// A unit that defines `_start` owns boot, so the synthetic entry chunk that normally runs the
// top-level statements cannot be placed first — QEMU (`-bios none`) enters at blob offset 0 and
// `_start` has to be there. The statements still have to run: a file-scope initializer whose
// value is not a compile-time constant (a string literal's address, `&glbl`, a call) compiles to
// a store, not to data bytes, so dropping the statement stream loses it with no diagnostic —
// `U8 *RN[32] = {"zero", …}` read back as (null) throughout repl-holyc.
//
// Wrap the statements in a callable `__init_globals` chunk and hand `_start`'s first outgoing
// call to it; `__init_globals` runs the stores, then calls whatever `_start` meant to call and
// returns its value. Retargeting one IC_CALL keeps `_start`'s prologue (mstatus.FS, sp) and the
// asm word stream untouched — inserting instructions there would desync the branch offsets
// ParseAsmFunction already baked — and the initializers land before *any* HolyC code, which is
// the order the non-`_start` entry chunk gives.
static void AOTInitGlobalsForStart(Compiler *cc, CHashFun *start_f) {
  // No top-level statements: no chunk and no retarget (a `_start`-only bootloader stays byte
  // for byte what it was).
  if (!cc->aot_main_head || !cc->aot_fn_ic_head) return;
  AOTFnICChunk *sc = NULL;
  for (AOTFnICChunk *c = cc->aot_fn_ic_head; c; c = c->next)
    if (c->fun == start_f) { sc = c; break; }
  if (!sc) return;
  // `call Name` inside asm{} is IC_CALL to the callee's entry label: that first handoff out of
  // `_start` is where the C runtime would run its init array.
  CIntermediateCode *hook = NULL;
  for (CIntermediateCode *ic = sc->head; ic; ic = ic->next) {
    if (ic->ic_code == IC_CALL) { hook = ic; break; }
    if (ic == sc->tail) break;
  }
  if (!hook) {
#ifndef BARE_METAL
    fprintf(stderr, "HOLYC AOT: `_start` never calls into HolyC — %s has top-level statements "
                    "(file-scope initializers) with nowhere to run\n",
            cc->lex.filename ? cc->lex.filename : "this unit");
#endif
    return;
  }
  CLabel *onward = (CLabel *)hook->ic_data;
  I64 onward_flags = hook->ic_flags;

  // Everything is allocated before any state moves, so a failure here cannot leave the
  // statement stream half-detached.
  CHashFun *initf = calloc(1, sizeof(CHashFun));
  AOTFnICChunk *chunk = calloc(1, sizeof(AOTFnICChunk));
  CIntermediateCode *lab = ICNew(cc, IC_LABEL);
  if (!initf || !chunk || !lab) { free(initf); free(chunk); return; }
  initf->str = strdup("__init_globals");
  initf->type = HTT_FUN;
  initf->raw_type = RT_I64;
  initf->is_extern = FALSE;
  initf->entry_label_defined = 1;
  CLabel *entry = LabelNew(cc, "__init_globals");
  initf->entry_label = entry;
  if (cc->hash_table) HashAdd((CHashEntry *)initf, cc->hash_table);

  cc->ic_head = cc->aot_main_head;
  cc->ic_tail = cc->aot_main_tail;
  cc->aot_main_head = cc->aot_main_tail = NULL;
  ICAdd(cc, IC_CALL_START, 0, RT_I64);
  ICAdd(cc, IC_CALL, (I64)onward, RT_I64);
  cc->ic_tail->ic_flags = onward_flags;   // `_start` passed no args; keep its a0 as our result
  ICAdd(cc, IC_CALL_END, 0, RT_I64);
  WrapStatementsAsFrame(cc);
  // The entry label goes ahead of IC_ENTER, the way ParseFunction orders a body.
  lab->ic_data = (I64)entry;
  lab->next = cc->ic_head;
  if (cc->ic_head) cc->ic_head->last = lab;
  cc->ic_head = lab;
  entry->defined = true;

  chunk->head = cc->ic_head;
  chunk->tail = cc->ic_tail;
  chunk->fun = initf;
  chunk->next = NULL;
  cc->ic_head = cc->ic_tail = NULL;
  // Last chunk: `_start` keeps offset 0 and every other function keeps its place in the blob.
  cc->aot_fn_ic_tail->next = chunk;
  cc->aot_fn_ic_tail = chunk;
  hook->ic_data = (I64)entry;
}

Compiler *CompileBuf(const char *source, size_t size, const char *filename, bool aot) {
  /* Progress before CompilerNew: New() calls LexNext, which may walk nested
   * #includes while fetching the first token. */
  HolyProgress("compile %s", HolyProgressRel(filename ? filename : "<source>"));
  HolyProgress("parse …");
  Compiler *cc = CompilerNewBuf(source, size, filename);
  cc->aot_mode = aot;
  cc->defer_aot_compile = TRUE;
  if (aot) RuntimeDeclare(cc);
#ifndef BARE_METAL
  if (filename) AOTDepAdd(cc, filename);
#endif

  // Parse the program
  if (!ParseProgram(cc)) {
    // fprintf(stderr, "Compilation failed: %s\n", 
    //         cc->error ? cc->error : "Unknown error");
    HolyProgress("parse failed");
    return cc;
  }
  HolyProgress("parse ok");
  
  // Stitch deferred per-function IC chains (source order) then single AOT pass
  AOTFnICChunk *stitched = NULL;
  // HolyC asm `_start::` (bare-metal entry): place it first in the blob so QEMU -bios none can
  // jump to offset 0 without a separate crt0.S. `_start` must `call main` (or equivalent).
  CHashEntry *start_e = (cc->defer_aot_compile && cc->hash_table) ? HashFind("_start", cc->hash_table, HTT_FUN) : NULL;
  bool have_start = start_e && ((CHashFun *)start_e)->entry_label_defined;
  if (have_start && cc->aot_fn_ic_head) {
    AOTFnICChunk *prev = NULL, *c = cc->aot_fn_ic_head;
    while (c) {
      if (c->fun == (CHashFun *)start_e) {
        if (prev) {
          prev->next = c->next;
          if (cc->aot_fn_ic_tail == c) cc->aot_fn_ic_tail = prev;
          c->next = cc->aot_fn_ic_head;
          cc->aot_fn_ic_head = c;
        }
        break;
      }
      prev = c; c = c->next;
    }
  }
  // Run top-level statements (globals' initializers, `#exe`) first; if a main() is defined here,
  // call it after them and its return is the program's result.
  // When `_start` owns boot there is no synthetic entry chunk (offset 0 belongs to `_start`);
  // the statements go into `__init_globals`, which `_start`'s first call reaches instead.
  CHashEntry *main_e = (cc->defer_aot_compile && cc->hash_table) ? HashFind("main", cc->hash_table, HTT_FUN) : NULL;
  if (main_e && !((CHashFun *)main_e)->entry_label_defined) main_e = NULL;
  if (have_start) {
    stitched = cc->aot_fn_ic_head;
    AOTInitGlobalsForStart(cc, (CHashFun *)start_e);
  } else if (cc->defer_aot_compile && (cc->aot_main_head || main_e)) {
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
        // TempleOS idiom: record the size too -- up to the next chunk's entry, else end of blob.
        I64 fn_end = cc->code_size;
        for (AOTFnICChunk *nx = ch->next; nx; nx = nx->next)
          if (nx->fun && nx->fun->entry_label) { fn_end = ((CLabel *)nx->fun->entry_label)->addr; break; }
        ch->fun->size = fn_end - lb->addr;
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

Compiler *Compile(const char *source, const char *filename, bool aot) {
  return CompileBuf(source, source ? strlen(source) : 0, filename, aot);
}

