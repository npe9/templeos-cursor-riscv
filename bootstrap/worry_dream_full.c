// Worry Dream Machine - Full REPL with Compiler Integration
#include <stdint.h>
#include <stddef.h>

#define UART_BASE 0x10000000

// Include compiler headers
typedef long long I64;
typedef unsigned char U8;
typedef int Bool;

// UART I/O
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
    char buf[20];
    buf[0] = '0'; buf[1] = 'x';
    for (int i = 0; i < 16; i++) {
        int d = (val >> (60 - i*4)) & 0xF;
        buf[2+i] = d < 10 ? '0' + d : 'a' + d - 10;
    }
    buf[18] = '\0';
    puts_uart(buf);
}

// Simple memory allocator
static U8 *heap_ptr = (U8*)0x80100000;  // After code

static void *simple_malloc(size_t sz) {
    void *p = heap_ptr;
    heap_ptr += (sz + 7) & ~7;  // 8-byte align
    return p;
}

// Minimal string functions for compiler
void *malloc(size_t sz) { return simple_malloc(sz); }
void *calloc(size_t n, size_t sz) {
    void *p = simple_malloc(n * sz);
    U8 *b = p;
    for (size_t i = 0; i < n * sz; i++) b[i] = 0;
    return p;
}
void free(void *p) { }  // No-op for now
void *realloc(void *p, size_t sz) { return simple_malloc(sz); }

size_t strlen(const char *s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
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

int printf(const char *fmt, ...) { puts_uart(fmt); return 0; }
int fprintf(void *f, const char *fmt, ...) { puts_uart(fmt); return 0; }
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

// Stubs for file I/O (not supported)
typedef struct { int dummy; } FILE;
FILE *fopen(const char *path, const char *mode) { return NULL; }
int fclose(FILE *f) { return 0; }
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *f) { return 0; }
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *f) { return 0; }
int fseek(FILE *f, long offset, int whence) { return 0; }
long ftell(FILE *f) { return 0; }

// Stubs for number parsing
long long strtoll(const char *s, char **end, int base) {
    return atoll(s);
}
double atof(const char *s) { return 0.0; }

// ctype stubs
const char _ctype_[256] = {0};
void *_impure_ptr = NULL;
void *stdin = NULL;
void *stdout = NULL;
void *stderr = NULL;

// Include compiler (assuming we compile it separately)
typedef struct Compiler Compiler;
extern Compiler *CompilerNew(const char *src, const char *fn);
extern Bool ParseProgram(Compiler *cc);
extern U8 *CompileAOT(Compiler *cc, I64 *size);

// REPL state
static U8 *code_space = (U8*)0x80200000;  // Compiled code goes here
static I64 code_offset = 0;

#define REPL_MAX_LINE 256

void repl_loop(void) {
    char line[REPL_MAX_LINE];
    
    while (1) {
        puts_uart("> ");
        int len = 0;
        int pos = 0;
        
        while (1) {
            char c = getc_uart();
            if (c == '\r' || c == '\n') {
                line[pos] = '\0';
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
            if (pos < REPL_MAX_LINE - 1 && c >= 32 && c < 127) {
                line[pos++] = c;
                putc_uart(c);
            }
        }
        
        if (pos == 0) continue;
        
        // Compile and execute
        Compiler *cc = CompilerNew(line, "repl");
        if (!ParseProgram(cc)) {
            puts_uart("Parse error\n");
            continue;
        }
        
        I64 size = 0;
        U8 *code = CompileAOT(cc, &size);
        if (!code || size == 0) {
            puts_uart("Compile error\n");
            continue;
        }
        
        // Copy to executable space
        for (I64 i = 0; i < size; i++) {
            code_space[code_offset + i] = code[i];
        }
        
        // Execute
        typedef I64 (*Func)(void);
        Func f = (Func)(code_space + code_offset);
        I64 result = f();
        
        // Print result
        print_hex(result);
        puts_uart("\n");
        
        code_offset += size;
    }
}

int main(void) {
    repl_loop();
    return 0;
}

