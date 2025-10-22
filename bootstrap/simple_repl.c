// Simple REPL - One function at a time
// This avoids the complex REPL issues

#include <stdint.h>
#include <stddef.h>
#include "../holyc_compiler.h"

#define UART_BASE 0x10000000
#define true 1
#define false 0

// UART functions
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

// Simple malloc implementation
static U8 heap_mem[1024*1024];  // 1MB heap
static size_t heap_pos = 0;

void *malloc(size_t sz) { 
    if (sz == 0) return NULL;
    size_t aligned = (sz + 7) & ~7;
    if (heap_pos + aligned > sizeof(heap_mem)) {
        return NULL;
    }
    void *p = &heap_mem[heap_pos];
    heap_pos += aligned;
    return p;
}

void free(void *ptr) {
    // Simple implementation - don't actually free
    // This prevents memory corruption issues
}

void *calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void *ptr = malloc(total);
    if (ptr) {
        memset(ptr, 0, total);
    }
    return ptr;
}

// String functions
size_t strlen(const char *s) {
    size_t len = 0;
    while (s[len]) len++;
    return len;
}

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

// Simple REPL - one function at a time
int main() {
    puts_uart("Simple HolyC REPL - One function at a time\n");
    puts_uart("Type 'quit' to exit\n");
    
    // Initialize compiler
    Compiler *cc = CompilerNew(NULL, NULL);
    if (!cc) {
        puts_uart("Failed to initialize compiler\n");
        return 1;
    }
    
    char input[512];
    int pos = 0;
    char c;
    
    while (1) {
        puts_uart("> ");
        
        // Read line
        pos = 0;
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
        
        // Check for quit command
        if (strcmp(input, "quit") == 0) {
            puts_uart("Goodbye!\n");
            break;
        }
        
        // Process input
        if (cc->lex.src) free(cc->lex.src);
        cc->lex.src = strdup(input);
        cc->lex.ptr = cc->lex.src;
        cc->lex.line = 1;
        cc->lex.col = 1;
        cc->lex.hash_entry = NULL;
        
        // Reset IC chain
        cc->ic_head = NULL;
        cc->ic_tail = NULL;
        cc->labels = NULL;
        cc->label_counter = 0;
        cc->locals_size = 0;
        
        // Get first token
        extern void LexNext(Compiler *cc);
        LexNext(cc);
        
        // Try ParseFunction first
        extern Bool ParseFunction(Compiler *cc);
        Bool is_function = ParseFunction(cc);
        
        if (is_function) {
            // Function definition
            puts_uart("Function definition detected\n");
            extern U8 *CompileAOT(Compiler *cc, I64 *size_out);
            I64 code_size = 0;
            U8 *machine_code = CompileAOT(cc, &code_size);
            if (machine_code && code_size > 0) {
                __asm__ volatile("fence.i" ::: "memory");
                puts_uart("Function compiled successfully\n");
                free(machine_code);
            } else {
                puts_uart("Function compilation failed\n");
            }
        } else {
            // Expression/statement
            puts_uart("Expression detected\n");
            // Reset lexer
            cc->lex.ptr = cc->lex.src;
            cc->lex.line = 1;
            cc->lex.col = 1;
            
            // Reset IC chain
            cc->ic_head = NULL;
            cc->ic_tail = NULL;
            cc->labels = NULL;
            cc->label_counter = 0;
            cc->locals_size = 0;
            
            // Parse statement
            LexNext(cc);
            extern Bool ParseStatement(Compiler *cc);
            Bool parsed = ParseStatement(cc);
            
            if (parsed) {
                // Add return
                ICAdd(cc, 0x09, 0, 0);  // IC_RETURN_VAL2
                ICAdd(cc, 0x5B, 0, 0);  // IC_RET
                
                // Compile and execute
                extern U8 *CompileExpression(Compiler *cc, I64 *size_out);
                I64 code_size = 0;
                U8 *machine_code = CompileExpression(cc, &code_size);
                
                if (machine_code && code_size > 0) {
                    __asm__ volatile("fence.i" ::: "memory");
                    
                    typedef I64 (*FuncPtr)();
                    FuncPtr func_ptr = (FuncPtr)machine_code;
                    I64 result = func_ptr();
                    
                    print_hex(result);
                    puts_uart("\n");
                    
                    free(machine_code);
                } else {
                    puts_uart("Compilation failed\n");
                }
            } else {
                puts_uart("Parse failed\n");
            }
        }
    }
    
    return 0;
}
