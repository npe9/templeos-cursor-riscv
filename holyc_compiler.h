/* Cicl to RISC-V Compiler - Main Header
 * Complete standalone compiler with frontend and backend
 */

#ifndef HOLYC_COMPILER_H
#define HOLYC_COMPILER_H

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hash_table.h"
#include "holy_api.h"

// ═══════════════════════════════════════════════════════════════
// BASIC TYPES (TempleOS compatible)
// ═══════════════════════════════════════════════════════════════

typedef void      U0;
typedef uint8_t   U8;
typedef uint16_t  U16;
typedef uint32_t  U32;
typedef uint64_t  U64;
typedef int8_t    I8;
typedef int16_t   I16;
typedef int32_t   I32;
typedef int64_t   I64;
typedef double    F64;
typedef bool      Bool;

#define TRUE  1
#define FALSE 0
#ifndef NULL
#define NULL  ((void*)0)
#endif

// ═══════════════════════════════════════════════════════════════
// INTERMEDIATE CODE (IC) DEFINITIONS
// ═══════════════════════════════════════════════════════════════

// IC Opcodes (from CompilerA.HH)
#define IC_END           0x00
#define IC_NOP1          0x01
#define IC_END_EXP       0x02
#define IC_NOP2          0x03
#define IC_LABEL         0x04
#define IC_CALL_START    0x05
#define IC_CALL_END      0x06
#define IC_CALL_END2     0x07
#define IC_RETURN_VAL    0x08
#define IC_RETURN_VAL2   0x09
#define IC_IMM_I64       0x0A
#define IC_IMM_F64       0x0B
#define IC_STR_CONST     0x0C
#define IC_ABS_ADDR      0x0D
#define IC_PUSH_RES      0x0E
#define IC_RBP           0x13
#define IC_LEA           0x19
#define IC_MOV           0x1A
#define IC_TO_I64        0x1B
#define IC_TO_F64        0x1C
#define IC_TO_BOOL       0x1D
#define IC_ADDR          0x20
#define IC_COM           0x21
#define IC_NOT           0x22
#define IC_UNARY_MINUS   0x23
#define IC_DEREF         0x24
#define IC_DEREF_PP      0x25
#define IC_DEREF_MM      0x26
#define IC__PP           0x27  // Post-increment
#define IC__MM           0x28  // Post-decrement
#define IC_PP_           0x29  // Pre-increment
#define IC_MM_           0x2A  // Pre-decrement
#define IC_SHL           0x2B
#define IC_SHR           0x2C
#define IC_MUL           0x30
#define IC_DIV           0x31
#define IC_MOD           0x32
#define IC_AND           0x33
#define IC_OR            0x34
#define IC_XOR           0x35
#define IC_ADD           0x36
#define IC_SUB           0x37
#define IC_ADD_CONST     0x38
#define IC_SUB_CONST     0x39
#define IC_EQU_EQU       0x3A
#define IC_NOT_EQU       0x3B
#define IC_LESS          0x3C
#define IC_GREATER_EQU   0x3D
#define IC_GREATER       0x3E
#define IC_LESS_EQU      0x3F
#define IC_AND_AND       0x41
#define IC_OR_OR         0x42
#define IC_XOR_XOR       0x43
#define IC_ASSIGN        0x44
#define IC_ADD_EQU       0x45
#define IC_SUB_EQU       0x46
#define IC_MUL_EQU       0x47
#define IC_DIV_EQU       0x48
#define IC_AND_EQU       0x49
#define IC_OR_EQU        0x4A
#define IC_XOR_EQU       0x4B
#define IC_JMP           0x51
#define IC_SUB_CALL      0x52
#define IC_ENTER         0x57
#define IC_PUSH_REGS     0x58
#define IC_POP_REGS      0x59
#define IC_LEAVE         0x5A
#define IC_RET           0x5B
#define IC_CALL          0x5C
#define IC_CALL_INDIRECT 0x5D
#define IC_CALL_INDIRECT2 0x5E
#define IC_PUSH          0x62
#define IC_POP           0x63
#define IC_BR_ZERO       0x85
#define IC_BR_NOT_ZERO   0x86
#define IC_SWITCH        0x87
#define IC_NOBOUND_SWITCH 0x88
#define IC_BR_EQU_EQU    0x89
#define IC_BR_NOT_EQU    0x8A
#define IC_BR_LESS       0x8B
#define IC_BR_GREATER_EQU 0x8C
#define IC_BR_GREATER    0x8D

#define IC_BR_LESS_EQU    0x8E
#define IC_PUSH_ARG       0x8F
#define IC_POP_ARG        0x90
// F64 flavours (operands/results travel as raw 64-bit patterns on the eval stack)
#define IC_FADD          0x93
#define IC_FSUB          0x94
#define IC_FMUL          0x95
#define IC_FDIV          0x96
#define IC_FLESS         0x97
#define IC_FLESS_EQU     0x98
#define IC_FGREATER      0x99
#define IC_FGREATER_EQU  0x9A
#define IC_FEQU_EQU      0x9B
#define IC_FNOT_EQU      0x9C
#define IC_FNEG          0x9D
#define IC_FMOD          0xA8
#define IC_CLI           0xA9   // HolyC bare-statement intrinsics: mstatus.MIE on RISC-V
#define IC_STI           0xAA
#define IC_PUSHFD        0xAB   // push mstatus / pop mstatus
#define IC_POPFD         0xAC
#define IC_SHL_EQU       0xAD
#define IC_SHR_EQU       0xAE
#define IC_MOD_EQU       0xAF
#define IC_PAUSE         0xB0   // spin-loop hint: nop
#define IC_CHAIN_CMP     0xB1   // chained compare `a<b<c`: [a,b] -> [(a op b), b]; ic_data = compare IC
#define IC_CHAIN_AND     0xB2   // [x,y,z] -> [x&y, z]
#define IC_HLT           0xB3   // `HLT` statement: wfi
#define IC_INT           0xB4   // `INT n` statement: ebreak (debugger entry)
#define IC_PC            0xB5   // `$$` in code: the current address (auipc)
#define IC_FN_ADDR       0xB6   // ic_data = CLabel*: a function's address as a value (auipc/addi)
#define IC_UDIV          0x9E
#define IC_UMOD          0x9F
#define IC_ULESS         0xA0
#define IC_ULESS_EQU     0xA1
#define IC_UGREATER      0xA2
#define IC_UGREATER_EQU  0xA3
#define IC_USHR          0xA4
#define IC_TRY_ENTER     0xA5   // ic_data = catch CLabel*; a0 = handler context (32 bytes)
#define IC_TRY_LEAVE     0xA6
#define IC_THROW         0xA7   // value on eval stack/a0
#define ICF_GLBL_ADDR    1      // ic_flags on IC_IMM_I64: ic_data is a global's data_addr (AOT: data section)
#define IC_EVAL_DROP      0x92 /* addi sp,sp,ic_data (drop eval slots); signed ic_data */

// Raw types
#define RT_I0    0
#define RT_I8    1
#define RT_I16   2
#define RT_I32   3
#define RT_I64   4
#define RT_U0    5
#define RT_U8    6
#define RT_U16   7
#define RT_U32   8
#define RT_U64   9
#define RT_F64   10
#define RT_PTR   11

#define RTF_UNSIGNED 0x80

// Addressing modes
#define MDF_NULL  0x00
#define MDF_REG   0x01
#define MDF_DISP  0x02
#define MDF_SIB   0x04
#define MDF_IMM   0x08
#define MDF_STK   0x10

// Combined mode + type
typedef union {
  U64 raw;
  struct {
    U8 raw_type;
    U8 mode;
    U16 pad1;
    U32 pad2;
  };
} CICType;

// IC Argument
typedef struct {
  CICType type;
  I64 reg;
  I64 disp;
} CICArg;

// Intermediate Code Operation
#define IC_BODY_SIZE 1024

typedef struct CIntermediateCode {
  struct CIntermediateCode *next, *last;
  U8 ic_code;
  U8 ic_body[IC_BODY_SIZE];
  I64 ic_cnt;
  I64 ic_data;
  I64 ic_flags;
  CICArg arg1, arg2, res;
  void *ic_class;
  U8 arg1_type_pointed_to;
} CIntermediateCode;

// Label for jumps/branches
typedef struct CLabel {
  struct CLabel *next;
  char *name;
  I64 addr;
  I64 flags;
  bool defined;
} CLabel;

// Switch case entry
typedef struct CSwitchCase {
  struct CSwitchCase *next;
  I64 value;
  I64 hi;      // case value...hi (== value for a single case)
  struct CLabel *via;   // sub_switch: outer dispatch enters here (the start: block) instead of label
  int group;            // sub_switch group index (-1 = none)
  CLabel *label;
} CSwitchCase;

// ═══════════════════════════════════════════════════════════════
// LEXER STRUCTURES
// ═══════════════════════════════════════════════════════════════

// Tokens
#define TK_EOF          0
#define TK_IDENT        256
#define TK_I64          257
#define TK_F64          258
#define TK_STR          259
#define TK_EQU_EQU      260  // ==
#define TK_NOT_EQU      261  // !=
#define TK_LESS_EQU     262  // <=
#define TK_GREATER_EQU  263  // >=
#define TK_SHL          264  // <<
#define TK_SHR          265  // >>
#define TK_AND_AND      266  // &&
#define TK_OR_OR        267  // ||
#define TK_XOR_XOR      268  // ^^
#define TK_ADD_ADD      269  // ++
#define TK_SUB_SUB      270  // --
#define TK_ADD_EQU      271  // +=
#define TK_SUB_EQU      272  // -=
#define TK_MUL_EQU      273  // *=
#define TK_DIV_EQU      274  // /=
#define TK_AND_EQU      275  // &=
#define TK_OR_EQU       276  // |=
#define TK_XOR_EQU      277  // ^=
#define TK_DBL_COLON    278  // ::
#define TK_PLUS_PLUS    279  // ++
#define TK_MINUS_MINUS  280  // --
#define TK_ARROW        281  // ->
#define TK_ELLIPSIS     282  // ...
#define TK_DOLLAR       283  // $$ inside a class body: the current member offset
#define TK_SHL_EQU      284  // <<=
#define TK_SHR_EQU      285  // >>=
#define TK_MOD_EQU      286  // %=

// Keywords
#define KW_IF       300
#define KW_ELSE     301
#define KW_WHILE    302
#define KW_FOR      303
#define KW_RETURN   304
#define KW_BREAK    305
#define KW_CLASS    306
#define KW_PUBLIC   307
#define KW_GOTO     319
#define KW_CONTINUE 320
#define KW_SWITCH   321
#define KW_CASE     322
#define KW_DEFAULT  323
#define KW_DFT      323  // Alias for default
#define KW_SIZEOF   324
#define KW_UNION    325
#define KW_STATIC   326
#define KW_TRY      327
#define KW_CATCH    328
#define KW_THROW    329
#define KW_ASM      330
#define KW_ENUM     331
#define KW_DO       332
#define KW_EXTERN   333
#define KW__EXTERN  334
#define KW__INTERN  335
#define KW_IMPORT   336
#define KW__IMPORT  337
#define KW_INTERRUPT 338
#define KW_HASERRCODE 339
#define KW_ARGPOP   340
#define KW_NOREG    341
#define KW_REG      342
#define KW_NO_WARN  343
#define KW_LASTCLASS 344
#define KW_I0       308
#define KW_U0       309
#define KW_I8       310
#define KW_U8       311
#define KW_I16      312
#define KW_U16      313
#define KW_I32      314
#define KW_U32      315
#define KW_I64      316
#define KW_U64      317
#define KW_F64      318

typedef struct CHashEntry CHashEntry;

// Include file stack
typedef struct IncludeFile {
  struct IncludeFile *next;
  char *src;         // Source code
  char *ptr;         // Current position
  char *filename;    // Filename
  int line;          // Line number in this file
  int col;           // Column number
  // A token held while a pushed string (default-argument text) is read; returned when the
  // string is exhausted instead of lexing on from ptr.
  bool has_pending;
  int p_token; I64 p_i64; F64 p_f64; char *p_str; int p_str_len; bool p_is_char; CHashEntry *p_hash;
} IncludeFile;

// Lexer state stack for LexPush/LexPop
struct IncludeFile;
typedef struct LexerStack {
  struct LexerStack *next;
  char *ptr;         // Saved position in source
  int line;          // Saved line number
  int col;           // Saved column number
  int token;         // Saved current token
  I64 token_i64;     // Saved integer value
  F64 token_f64;     // Saved float value
  char *token_str;   // Saved string (owned by this struct)
  int token_str_len; // Saved string length (TK_STR may hold NULs)
  int brace_depth;
  CHashEntry *hash_entry;  // Saved hash entry
  char *src;               // Saved source buffer (a macro expansion may have been entered since)
  char *filename;
  struct IncludeFile *include_stack;  // Saved include/expansion depth
} LexerStack;

typedef struct {
  char *src;
  char *ptr;
  int line;
  int col;
  
  int token;
  I64 token_i64;
  F64 token_f64;
  char *token_str;
  
  CHashEntry *hash_entry;  // Hash table entry for current identifier
  
  char *filename;
  
  LexerStack *stack;  // Stack for LexPush/LexPop
  IncludeFile *include_stack;  // Stack for #include files
  bool token_is_char;
  int token_str_len;   // TK_STR: byte length (may contain NULs)
  int brace_depth;     // { } nesting of the token stream (error recovery)          // TK_I64 came from a char literal ('x' statements call PutChars)
} Lexer;

// ═══════════════════════════════════════════════════════════════
// SYMBOL TABLE
// ═══════════════════════════════════════════════════════════════

typedef enum {
  SYM_VAR,
  SYM_FUNCTION,
  SYM_TYPE,
  SYM_LABEL
} SymbolType;

typedef struct Symbol {
  struct Symbol *next;
  char *name;
  SymbolType type;
  I64 offset;    // For variables: stack offset
  I64 address;   // For functions/labels
  U8 data_type;  // RT_I64, RT_F64, etc.
  U8 size;
  void *extra;   // Function signature, etc.
  
  // Array information
  bool is_array;
  I64 array_size;    // Number of elements
  I64 element_size;  // Size of each element in bytes
  int ndims;          // 0/1 = flat; >1 = multi-dimensional (dim_stride per subscript level)
  I64 dim_stride[4];  // bytes advanced by one step of subscript k
  
  // Pointer information
  U8 pointed_to_type; // For pointers: RT_U8, RT_U32, RT_I64, etc. (0 if not pointer)

  // Function pointer metadata
  bool is_function_pointer;
  U8 function_return_type;
  int func_ptr_param_count;
  
  // Default parameter value
  bool has_default;
  I64 default_val;
  char *default_src;   // default that is an expression: source text, re-lexed at call sites
} Symbol;

typedef struct SymTable {
  Symbol *symbols;
  struct SymTable *parent;
} SymTable;

// Deferred per-function IC chains (stitched into one CompileAOT pass for multi-function AOT blobs)
typedef struct AOTFnICChunk {
  CIntermediateCode *head;
  CIntermediateCode *tail;
  CHashFun *fun;
  struct AOTFnICChunk *next;
} AOTFnICChunk;

// ═══════════════════════════════════════════════════════════════
// COMPILER STATE
// ═══════════════════════════════════════════════════════════════

// Compiler flags (match original CCF_* from TempleOS)
#define CCF_RAX         0x01  // Result in RAX/a0, skip auto-deref
#define CCF_ARRAY       0x02  // Result is array address
#define CCF_PAREN       0x04  // Inside parentheses

typedef struct {
  // Lexer
  Lexer lex;
  
  // Symbol table
  SymTable *symtab;
  
  // Hash table (for types, classes, keywords - like original)
  CHashTable *hash_table;
  
  // IC list
  CIntermediateCode *ic_head;
  CIntermediateCode *ic_tail;
  
  // Labels
  CLabel *labels;
  int label_counter;
  
  // Loop context (for break/continue)
  CLabel *current_break_label;    // Label to jump to on break
  CLabel *current_continue_label; // Label to jump to on continue
  CLabel *current_function_exit;  // Label to jump to on return
  
  // Expression type tracking
  Symbol *last_var_symbol;  // Last variable referenced (for array subscripting)
  CHashClass *last_expr_class;  // Last expression's class (for member access)
  CHashClass *last_type_class;  // Most recently parsed type's class (for decls)
  struct CHashGlblVar *last_global_var;  // Last global variable referenced
  U8 last_pointed_to_type;  // For pointer declarations (RT_U8, RT_U32, etc.)
  
  // Compiler flags (match original CCF_* flags)
  I64 flags;  // CCF_RAX, CCF_ARRAY, CCF_PAREN, etc.
  
  // Macro definitions (#define)
  CHashTable *define_table;
  
  // Preprocessor state
  bool preprocessor_skip;  // Skip code due to #if 0 or #ifdef
  int ifdef_depth;         // Nesting depth of #ifdef blocks
  
  // Local variables
  I64 locals_size;
  I64 current_function_param_count;  // For calculating local var offsets
  
  // Compilation mode
  bool aot_mode;     // AOT vs JIT
  bool optimize;
  
  // Error handling
  char *error;
  int error_line;
  char *error_file;
  U8 cast_elem_type;       // pointee type after a pointer cast (`s(U8 *)[i]`), 0 = none
  CHashClass *cast_elem_class;
  bool addr_of_ident;      // `&name` pending: a function name here is an address, not a call
  bool class_decl_follows; // ParseClass returned at `class X {…} a`: the caller parses declarators        // File where the first pending error was raised
  
  // Output
  U8 *code_buffer;
  I64 code_size;
  
  // String literals (for target code)
  struct StringLiteral *strings;
  
  // Last compiled function (for setting exe_addr after CompileAOT)
  CHashFun *last_compiled_func;
  // Entry label of the function currently being parsed (for direct PC-rel self-calls)
  CLabel *current_function_entry_label;
  
  // Last function call arg count (for IC_CALL_INDIRECT2 in compiler)
  I64 last_call_arg_cnt;

  // Multi-function AOT: defer CompileAOT until all functions parsed; stitch IC chains in order
  Bool defer_aot_compile;
  AOTFnICChunk *aot_fn_ic_head;
  AOTFnICChunk *aot_fn_ic_tail;
  // Top-level statements (HolyC runs them in source order): collected by ParseProgram into
  // the entry chunk that Compile() places first in the blob.
  struct CIntermediateCode *aot_main_head;
  struct CIntermediateCode *aot_main_tail;
  // Parse errors are recovered from (skip to the end of the item) but never dropped silently.
  const char *first_error;
  I64 error_count;
  struct { I64 line; const char *file; const char *msg; } errors[256];   // first 64 (HOLYC_ALL_ERRORS)
  int subscript_level;   // consecutive [ ] applied to the current array reference
  U8 last_expr_type;     // RT_F64 / RT_U64 (unsigned) / RT_I64 for the expression just parsed
  // AOT data section: globals laid out after code+strings (data_addr_rip = offset)
  Bool aot_data_layout;
  I64 aot_data_base;     // data section offset in the blob (set for the emit pass)
  I64 aot_data_size;
  struct CHashGlblVar *try_top_var;    // __try_top: innermost handler context
  struct CHashGlblVar *except_ch_var;  // except_ch: code of the last throw
  I64 try_depth;                       // open try blocks in the function being parsed
  I64 loop_try_depth;                  // try depth at the innermost loop/switch entry (break/continue unwind to it)
  struct CHashGlblVar *fs_var;         // Fs: pointer to the task block (__task); Fs->except_ch
  struct CMemberLst *last_member;      // member just accessed by . or -> (typing for [ ] and *)
  U8 call_ret_type;                    // raw_type of the function just called (F64 → F64 result)
  I64 asm_blocks_skipped;              // x86 asm {} blocks parsed and dropped
  U8 class_base_type;                  // `I64 class X {…}`: the class is that scalar; members overlay it
  int in_class_body;                   // `$$` lexes as TK_DOLLAR (current offset) while > 0
  U8 current_fn_ret_type;

} Compiler;

// String literal for target code
typedef struct StringLiteral {
  char *str;
  I64 len;     // bytes (literals may contain \0)
  I64 offset;  // Offset in final binary
  struct StringLiteral *next;
} StringLiteral;

// ═══════════════════════════════════════════════════════════════
// FUNCTION PROTOTYPES
// ═══════════════════════════════════════════════════════════════

// Lexer
Compiler *CompilerNew(const char *source, const char *filename);
void LexPushStringPending(Compiler *cc, const char *text);
void LexAbandonPendingString(Compiler *cc);
void CompilerFree(Compiler *cc);
Compiler *Compile(const char *source, const char *filename, bool aot);
void LexNext(Compiler *cc);
bool LexExpect(Compiler *cc, int token);

// Parser
bool ParseExpression(Compiler *cc);
bool ParseStatement(Compiler *cc);
bool ParseFunction(Compiler *cc);
bool ParseProgram(Compiler *cc);
bool ParseTopLevel(Compiler *cc);
void WrapStatementsAsFrame(Compiler *cc);
bool ParseREPLStatement(Compiler *cc);  // For REPL: parse one statement

// IC Generation
CIntermediateCode *ICNew(Compiler *cc, U8 opcode);
void ICAdd(Compiler *cc, U8 opcode, I64 data, U8 type);
void ICSetArg1(CIntermediateCode *ic, CICType type, I64 reg, I64 disp);
void ICSetArg2(CIntermediateCode *ic, CICType type, I64 reg, I64 disp);
void ICSetRes(CIntermediateCode *ic, CICType type, I64 reg, I64 disp);

// Symbol table
Symbol *SymbolLookup(Compiler *cc, const char *name);
Symbol *SymbolDefine(Compiler *cc, const char *name, SymbolType type);
void SymTablePush(Compiler *cc);
void SymTablePop(Compiler *cc);

// Labels
CLabel *LabelNew(Compiler *cc, const char *name);
CLabel *LabelFind(Compiler *cc, const char *name);

// Lexer state stack
void LexPush(Compiler *cc);
void LexPopRestore(Compiler *cc);
void LexPopNoRestore(Compiler *cc);

// Code generation (links to RISC-V backend)
U8 *CompileAOT(Compiler *cc, I64 *code_size);
U8 *CompileJIT(Compiler *cc, I64 *size_out);

// Execution
I64 ExecuteJIT(void *code);

// Utilities
void Error(Compiler *cc, const char *msg);
bool IsKeyword(const char *str);

#endif // HOLYC_COMPILER_H

