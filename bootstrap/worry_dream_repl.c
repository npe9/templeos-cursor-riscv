// Worry Dream Machine - Live Interactive REPL
// Type HolyC code over UART, compile and execute it

#include <stdint.h>
#include <stddef.h>

#define UART_BASE 0x10000000
#define NULL ((void*)0)

typedef long long I64;
typedef unsigned char U8;
typedef unsigned int U32;
typedef unsigned long long U64;
typedef int bool;
typedef int Bool;
#define true 1
#define false 0

// UART
static void putc_uart(char c) {
    while (!(*(volatile U8*)(UART_BASE + 5) & 0x20));
    *(volatile U8*)UART_BASE = c;
}

static char getc_uart(void) {
    while (!(*(volatile U8*)(UART_BASE + 5) & 0x01));
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
int printf(const char *fmt, ...) { return 0; }
int fprintf(void *f, const char *fmt, ...) { return 0; }
int snprintf(char *s, size_t n, const char *fmt, ...) { return 0; }
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
typedef struct { int dummy; } FILE;
FILE *fopen(const char *p, const char *m) { return NULL; }
int fclose(FILE *f) { return 0; }
size_t fread(void *ptr, size_t size, size_t n, FILE *f) { return 0; }
size_t fwrite(const void *ptr, size_t size, size_t n, FILE *f) { return 0; }
int fseek(FILE *f, long offset, int whence) { return 0; }
long ftell(FILE *f) { return 0; }
long long strtoll(const char *s, char **end, int base) { return atoll(s); }
double atof(const char *s) { return 0.0; }
const char _ctype_[256] = {0};
void *_impure_ptr = NULL;
void *stdin = NULL;
void *stdout = NULL;
void *stderr = NULL;

// Compiler interface
typedef struct Compiler Compiler;
extern Compiler *CompilerNew(const char *src, const char *fn);
extern void CompilerFree(Compiler *cc);
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
    
    // Note: We don't create a hash table here.
    // CompilerNew() creates and manages the global persistent hash table (g_persistent_hash_table)
    // This ensures ALL compiler instances share the SAME hash table across REPL iterations
    
    while (1) {
        puts_uart("> ");
        pos = 0;
        
        // Read line
        while (1) {
            c = getc_uart();
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
        
        // Compile and execute like TempleOS LexStmt2Bin
        Compiler *cc = CompilerNew(input, "repl");
        if (!cc) continue;
        
        // Try ParseFunction first (for function definitions)
        extern Bool ParseFunction(Compiler *cc);
        Bool is_function = ParseFunction(cc);
        
        if (is_function) {
            // Function definition - compile and store in hash table
            extern U8 *CompileAOT(Compiler *cc, I64 *size_out);
            I64 code_size = 0;
            U8 *machine_code = CompileAOT(cc, &code_size);
            if (machine_code && code_size > 0) {
                // Set exe_addr in hash table (match TempleOS PrsStmt.HC:172 or 183)
                extern void **CompilerGetLastFuncAddr(void *cc);
                void **func_exe_addr_ptr = CompilerGetLastFuncAddr(cc);
                if (func_exe_addr_ptr) {
                    puts_uart("[SET exe_addr=");
                    print_hex((U64)machine_code);
                    puts_uart("]\n");
                    *func_exe_addr_ptr = machine_code;
                    // Instruction cache coherency for function code
                    __asm__ volatile("fence.i" ::: "memory");
                }
            }
        } else {
            // Expression/statement - parse, compile, execute immediately
            // Match TempleOS LexStmt2Bin flow (CMain.HC:1-33)
            CompilerFree(cc);
            cc = CompilerNew(input, "repl");
            if (!cc) continue;
            
            // Parse statement (like TempleOS PrsStmt)
            extern Bool ParseStatement(Compiler *cc);
            Bool parsed = ParseStatement(cc);
            
            if (parsed) {
                // Add return (match TempleOS LexStmt2Bin:13-14)
                extern void ICAdd(void *cc, int code, long arg1, int arg2);
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
                    __asm__ volatile("fence.i" ::: "memory");
                    
                    // TempleOS approach: Just cast compiled code to function and call it
                    // This is EXACTLY what LexStmt2Bin does (CMain.HC:15,32)
                    typedef I64 (*FuncPtr)();
                    FuncPtr func_ptr = (FuncPtr)machine_code;
                    I64 result = func_ptr();
                    
                    // Store and display result (match TempleOS Fs->answer)
                    g_answer = result;
                    print_hex(result);
                    puts_uart("\n");
                }
            }
        }
        
        CompilerFree(cc);
    }
}

int main(void) {
    repl();
    while (1) __asm__ volatile ("wfi");
}

