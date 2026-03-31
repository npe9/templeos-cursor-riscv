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

void repl(void) {
    char input[512];
    int pos;
    char c;
    
    // Create compiler once and reuse across REPL iterations
    // This ensures the hash table persists across inputs
    Compiler *cc = CompilerNew("", "repl");
    
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
            }
        }
        
        if (pos == 0) continue;
        
        // Skip comment-only lines starting with '#'
        int i_start = 0;
        while (i_start < pos && (input[i_start] == ' ' || input[i_start] == '\t')) i_start++;
        if (i_start < pos && input[i_start] == '#') {
            // Ignore comment line
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
        
        // Get first token
        extern void LexNext(Compiler *cc);
        LexNext(cc);
        
        // Try ParseFunction first (for function definitions)
        extern Bool ParseFunction(Compiler *cc);
        Bool is_function = ParseFunction(cc);
        
        if (is_function) {
            // Function definition - compile and store in hash table
            extern U8 *CompileAOT(Compiler *cc, I64 *size_out);
            I64 code_size = 0;
            U8 *machine_code = CompileAOT(cc, &code_size);
            if (machine_code && code_size > 0) {
                // Update exe_addr in hash table for function calls
                if (cc->last_compiled_func) {
                    cc->last_compiled_func->exe_addr = (I64)machine_code;
                    // Debug: print the function address
                    puts_uart("Function address stored: 0x");
                    print_hex((U64)machine_code);
                    puts_uart("\n");
                    puts_uart("Hash table entry address: 0x");
                    print_hex((U64)cc->last_compiled_func);
                    puts_uart("\n");
                    puts_uart("exe_addr field address: 0x");
                    print_hex((U64)&cc->last_compiled_func->exe_addr);
                    puts_uart("\n");
                }
                // Just ensure instruction cache coherency
                // __asm__ volatile("fence.i" ::: "memory"); // Not supported in this RISC-V implementation
                puts_uart("Function compiled successfully\n");
                // Don't free machine_code - it's needed for function calls
            } else {
                puts_uart("Function compilation failed\n");
            }
            
            // Note: Hash table is preserved for function calls
        } else {
            // Expression/statement - parse, compile, execute immediately
            // Match TempleOS LexStmt2Bin flow (CMain.HC:1-33)
            
            // Reset lexer since ParseFunction consumed input
            cc->lex.ptr = cc->lex.src;
            cc->lex.line = 1;
            cc->lex.col = 1;
            
            // Reset IC chain since ParseFunction may have added some ICs
            cc->ic_head = NULL;
            cc->ic_tail = NULL;
            cc->labels = NULL;
            cc->label_counter = 0;
            cc->locals_size = 0;
            
            // Parse statement (like TempleOS PrsStmt)
            // Get first token after lexer reset
            LexNext(cc);
            extern Bool ParseStatement(Compiler *cc);
            Bool parsed = ParseStatement(cc);
            
            
            if (parsed) {
                // Add return (match TempleOS LexStmt2Bin:13-14)
                ICAdd(cc, 0x09, 0, 0);  // IC_RETURN_VAL2
                ICAdd(cc, 0x5B, 0, 0);  // IC_RET
                
                // Compile and execute (match TempleOS COCCompile)
                extern U8 *CompileExpression(Compiler *cc, I64 *size_out);
                I64 code_size = 0;
                U8 *machine_code = CompileExpression(cc, &code_size);
                
                if (!machine_code) {
                    puts_uart("[COMPILE FAILED]\n");
                    continue;
                }
                
                if (machine_code && code_size > 0) {
                    // Instruction cache coherency
                    // __asm__ volatile("fence.i" ::: "memory"); // Not supported in this RISC-V implementation
                    
                    // TempleOS approach: Just cast compiled code to function and call it
                    // This is EXACTLY what LexStmt2Bin does (CMain.HC:15,32)
                    typedef I64 (*FuncPtr)();
                    FuncPtr func_ptr = (FuncPtr)machine_code;
                    I64 result = func_ptr();
                    
                    // Store and display result (match TempleOS Fs->answer)
                    g_answer = result;
                    print_hex(result);
                    puts_uart("\n");
                    
                    // Free the allocated buffer to prevent memory leak
                    free(machine_code);
                }
            }
        }
        
        // Don't free the compiler - reuse it for the next iteration
    }
}

int main(void) {
    repl();
    while (1) __asm__ volatile ("wfi");
}

