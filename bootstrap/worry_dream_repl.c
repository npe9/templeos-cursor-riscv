// Worry Dream Machine - Live Interactive REPL
// Type HolyC code over UART, compile and execute it

#include <stdint.h>
#include <stddef.h>
#include "../holyc_compiler.h"

#define UART_BASE 0x10000000
#define true 1
#define false 0

// UART
static void putc_uart(char c) {
    while (!(*(volatile U8*)(UART_BASE + 5) & 0x20));
    *(volatile U8*)UART_BASE = c;
}

static char getc_uart(void) {
    // Non-blocking: return 0 if no data available
    if (!(*(volatile U8*)(UART_BASE + 5) & 0x01)) {
        return 0;
    }
    return *(volatile U8*)UART_BASE;
}

static void puts_uart(const char *s) {
    while (*s) {
        if (*s == '\n') putc_uart('\r');
        putc_uart(*s++);
    }
}

static void print_hex(uint64_t val) {
    putc_uart('0'); putc_uart('x');
    for (int i = 15; i >= 0; i--) {
        int d = (val >> (i*4)) & 0xF;
        putc_uart(d < 10 ? '0' + d : 'a' + d - 10);
    }
}

static void print_hex_byte(unsigned char val) {
    int hi = (val >> 4) & 0xF;
    int lo = val & 0xF;
    putc_uart(hi < 10 ? '0' + hi : 'a' + hi - 10);
    putc_uart(lo < 10 ? '0' + lo : 'a' + lo - 10);
}

// Separate code and heap areas to prevent overwriting  
static U8 code_mem[4*1024*1024];   // 4MB for compiled code (never reused)
static size_t code_pos = 0;
static U8 heap_mem[12*1024*1024];  // 12MB heap for compiler structures (reusable)
static size_t heap_pos = 0;

// Special malloc for CODE - never freed, never reused
void *code_malloc(size_t sz) {
    if (sz == 0) return NULL;
    size_t aligned = (sz + 7) & ~7;
    if (code_pos + aligned > sizeof(code_mem)) {
        return NULL;
    }
    // Ensure code is in executable memory range
    void *p = &code_mem[code_pos];
    code_pos += aligned;
    // Debug: verify address is valid
    U64 addr = (U64)p;
    if (addr < 0x80000000 || addr > 0x90000000) {
        return NULL;  // Invalid address range
    }
    return p;
}

void *malloc(size_t sz) { 
    if (sz == 0) return NULL;
    size_t aligned = (sz + 7) & ~7;
    if (heap_pos + aligned > sizeof(heap_mem)) {
        puts_uart("[malloc: OUT OF MEMORY! sz=");
        print_hex(sz);
        puts_uart(" pos=");
        print_hex(heap_pos);
        puts_uart("]\n");
        // Reset heap for REPL - free everything except code
        heap_pos = 0;
        void *p = &heap_mem[heap_pos];
        heap_pos += aligned;
        return p;
    }
    void *p = &heap_mem[heap_pos];
    heap_pos += aligned;
    return p;
}
void *calloc(size_t n, size_t sz) { 
    size_t total = n * sz;
    void *p = malloc(total);
    if (!p) return NULL;
    // Zero out memory
    for (size_t i = 0; i < total; i++) ((U8*)p)[i] = 0;
    return p;
}
// Don't free in REPL - we need to keep function code alive!
void free(void *p) { (void)p; }
size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
char *strdup(const char *s) {
    size_t n = strlen(s);
    char *d = malloc(n + 1);
    for (size_t i = 0; i <= n; i++) d[i] = s[i];
    return d;
}
int strcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a - *b;
}
char *strcpy(char *d, const char *s) {
    char *r = d;
    while ((*d++ = *s++));
    return r;
}
int isspace(int c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
int isdigit(int c) { return c >= '0' && c <= '9'; }
int isalpha(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
int isalnum(int c) { return isalpha(c) || isdigit(c); }
long long atoll(const char *s) {
    long long v = 0;
    int neg = 0;
    while (isspace(*s)) s++;
    if (*s == '-') { neg = 1; s++; }
    while (isdigit(*s)) v = v * 10 + (*s++ - '0');
    return neg ? -v : v;
}
void *memset(void *s, int c, size_t n) {
    U8 *p = s;
    while (n--) *p++ = c;
    return s;
}
void *memcpy(void *d, const void *s, size_t n) {
    U8 *pd = d;
    const U8 *ps = s;
    while (n--) *pd++ = *ps++;
    return d;
}
long long strtoll(const char *s, char **end, int base) { return atoll(s); }
double atof(const char *s) { return 0.0; }
const char _ctype_[256] = {0};
FILE *fopen(const char *p, const char *m) { return NULL; }
int fclose(FILE *f) { return 0; }
size_t fread(void *ptr, size_t size, size_t n, FILE *f) { return 0; }
size_t fwrite(const void *ptr, size_t size, size_t n, FILE *f) { return 0; }
int fseek(FILE *f, long offset, int whence) { return 0; }
long ftell(FILE *f) { return 0; }

// Compiler interface - now provided by holyc_compiler.h
extern Bool ParseProgram(Compiler *cc);
extern U8 *CompileAOT(Compiler *cc, I64 *size);

// Code execution space
static U8 *code_area = (U8*)0x80200000;

// Global answer variable (like TempleOS Fs->answer)
static I64 g_answer = 0;

// ---- HolyC runtime (shared with the exec harness: bootstrap/holy_rt.h) -------------------
#define HOLY_RT_PUTC(c) putc_uart(c)
#define HOLY_RT_MALLOC(sz) malloc(sz)
#include "holy_rt.h"

static void RuntimeRegister(Compiler *cc, const char *name, void *fn, I64 argc) {
    CHashFun *f = calloc(1, sizeof(CHashFun));
    f->str = strdup(name);
    f->type = HTT_FUN;
    f->raw_type = HolyRtRetF64(name) ? RT_F64 : RT_I64;
    f->param_typed = true;
    f->param_f64_mask = HolyRtF64Mask(name);
    f->exe_addr = (I64)fn;
    f->arg_cnt = argc;
    HashAdd((CHashEntry *)f, cc->hash_table);
}
static void RuntimeInit(Compiler *cc) {
    // Fs -> the task block (Fs->except_ch)
    if (cc->fs_var && cc->except_ch_var) *(I64 *)cc->fs_var->data_addr = (I64)cc->except_ch_var->data_addr;
    for (HRT_I64 i = 0; i < HOLY_RT_COUNT; i++)
        RuntimeRegister(cc, holy_rt_table[i].name, holy_rt_table[i].fn, holy_rt_table[i].argc);
}

void repl(void) {
    char input[512];
    int pos;
    char c;
    
    // Create compiler once and reuse across REPL iterations
    // This ensures the hash table persists across inputs
    Compiler *cc = CompilerNew("", "repl");
    RuntimeInit(cc);
    
    // Accumulation buffer for multi-line inputs (functions/blocks)
    static char accum[4096];
    int accum_len = 0;
    int brace_depth = 0;
    int paren_depth = 0;
    
    while (1) {
        puts_uart("> ");
        pos = 0;
        
        // Read line
        while (1) {
            c = getc_uart();
            if (c == 0) {
                // No data available, continue waiting
                continue;
            }
            if (c == '\r' || c == '\n') {
                input[pos] = '\0';
                puts_uart("\n");
                break;
            }
            if (c == 127 || c == 8) {  // Backspace
                if (pos > 0) {
                    pos--;
                    puts_uart("\b \b");
                }
                continue;
            }
            if (pos < 511 && c >= 32 && c < 127) {
                input[pos++] = c;
                putc_uart(c);
            } else if (c == '\t' && pos < 511) {   // TABs (common in TempleOS sources) become a space
                input[pos++] = ' ';
                putc_uart(' ');
            }
        }
        
        if (pos == 0) continue;
        
        // Skip comment-only lines starting with '#'
        int i_start = 0;
        while (i_start < pos && (input[i_start] == ' ' || input[i_start] == '\t')) i_start++;
        // '#' + letter is a preprocessor directive (#define, #include, …) and goes to the
        // lexer as its own line; anything else starting with '#' is treated as a comment.
        int is_directive = (i_start + 1 < pos && input[i_start] == '#' &&
                            ((input[i_start+1] >= 'a' && input[i_start+1] <= 'z') ||
                             (input[i_start+1] >= 'A' && input[i_start+1] <= 'Z')));
        if (i_start < pos && input[i_start] == '#' && !is_directive) {
            continue;
        }
        
        // Append this line to accumulation buffer (with a newline)
        if (accum_len + pos + 2 < (int)sizeof(accum)) {
            for (int i = 0; i < pos; i++) accum[accum_len++] = input[i];
            accum[accum_len++] = '\n';
            accum[accum_len] = '\0';
        } else {
            puts_uart("[ERROR] Input too long\n");
            accum_len = 0; brace_depth = 0; paren_depth = 0;
            continue;
        }
        
        // Track simple brace/paren depth to detect statement/function completion
        for (int i = 0; i < pos; i++) {
            char ch = input[i];
            if (ch == '{') brace_depth++;
            else if (ch == '}') { if (brace_depth > 0) brace_depth--; }
            else if (ch == '(') paren_depth++;
            else if (ch == ')') { if (paren_depth > 0) paren_depth--; }
        }
        
        // Determine if we should attempt to parse now
        int should_parse = 0;
        // If in a block, wait until braces balance back to zero
        if (brace_depth == 0) {
            // If not in parens and line ends with ';', treat as complete statement/expression
            if (paren_depth == 0) {
                if (pos > 0 && input[pos-1] == ';') should_parse = 1;
                // Or if this line closed a block '}'
                if (pos > 0 && input[pos-1] == '}') should_parse = 1;
            }
        }
        
        if (is_directive && brace_depth == 0 && paren_depth == 0) should_parse = 1;
        if (!should_parse) {
            // Prompt for more lines
            continue;
        }
        
        // Reinitialize lexer and compiler state for accumulated input (keep hash table)
        if (cc->lex.src) free(cc->lex.src);
        cc->lex.src = strdup(accum);
        cc->lex.ptr = cc->lex.src;
        cc->lex.line = 1;
        cc->lex.col = 1;
        cc->lex.hash_entry = NULL;
        
        // Reset IC chain for new statement
        cc->ic_head = NULL;
        cc->ic_tail = NULL;
        cc->labels = NULL;
        cc->label_counter = 0;
        cc->locals_size = 0;
        
        // Reset accumulation after capturing into lexer
        accum_len = 0;
        brace_depth = 0;
        paren_depth = 0;
        
        if (!cc) continue;
        
        // Parse the input as top-level HolyC (same grammar as a source file): definitions
        // register themselves (functions are compiled by the parser and get an exe_addr);
        // plain statements leave IC behind, which we compile and run right away.
        extern void LexNext(Compiler *cc);
        extern Bool ParseTopLevel(Compiler *cc);
        extern U8 *CompileExpression(Compiler *cc, I64 *size_out);
        LexNext(cc);
        Bool ok = true;
        int defined_fn = 0;
        while (ok && cc->lex.token != TK_EOF) {
            CHashFun *fn_before = cc->last_compiled_func;
            I64 addr_before = fn_before ? fn_before->exe_addr : 0;
            ok = ParseTopLevel(cc);
            if (ok && cc->last_compiled_func &&
                (cc->last_compiled_func != fn_before || cc->last_compiled_func->exe_addr != addr_before) &&
                cc->last_compiled_func->exe_addr) {
                defined_fn++;
            }
        }
        // Everything compiled above (functions, statement) is fresh code: order the I-side.
        __asm__ volatile("fence.i" ::: "memory");
        if (!ok) {
            puts_uart("[ERROR] ");
            puts_uart(cc->error ? cc->error : "parse error");
            puts_uart(" near '");
            puts_uart(cc->lex.token_str ? cc->lex.token_str : "");
            puts_uart("' line ");
            print_hex((U64)cc->lex.line);
            puts_uart("\n");
            cc->error = NULL;
            cc->ic_head = NULL;
            cc->ic_tail = NULL;
            continue;
        }
        if (defined_fn) puts_uart("Function compiled successfully\n");
        if (cc->ic_head) {
            // Statement: compile it as a frame of its own (switch/try temps get real slots);
            // the last value is the answer (match TempleOS LexStmt2Bin:13-14).
            extern void WrapStatementsAsFrame(Compiler *cc);
            extern U8 *CompileAOT(Compiler *cc, I64 *size_out);
            WrapStatementsAsFrame(cc);
            I64 code_size = 0;
            U8 *machine_code = CompileAOT(cc, &code_size);
            cc->ic_head = NULL;
            cc->ic_tail = NULL;
            if (!machine_code || code_size <= 0) {
                puts_uart("[COMPILE FAILED]\n");
                continue;
            }
            __asm__ volatile("fence.i" ::: "memory");
            // TempleOS approach: cast the compiled code to a function and call it (CMain.HC:15,32)
            typedef I64 (*FuncPtr)();
            FuncPtr func_ptr = (FuncPtr)machine_code;
            I64 result = func_ptr();
            g_answer = result;
            print_hex(result);
            puts_uart("\n");
            free(machine_code);
        }
        
        // Don't free the compiler - reuse it for the next iteration
    }
}

int main(void) {
    repl();
    while (1) __asm__ volatile ("wfi");
}

