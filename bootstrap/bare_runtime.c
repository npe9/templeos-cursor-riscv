/* Bare Metal Runtime Implementation */

#include "bare_runtime.h"

#define UART_BASE 0x10000000
#define UART_LSR  5
#define UART_LSR_TX_IDLE  0x20
#define UART_LSR_RX_READY 0x01

// UART
void uart_putc(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + UART_LSR) & UART_LSR_TX_IDLE));
    *(volatile uint8_t*)UART_BASE = c;
}

char uart_getc(void) {
    while (!(*(volatile uint8_t*)(UART_BASE + UART_LSR) & UART_LSR_RX_READY));
    return *(volatile uint8_t*)UART_BASE;
}

void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

void uart_print_i64(int64_t val) {
    char buf[32];
    int i = 0;
    bool neg = false;
    
    if (val < 0) {
        neg = true;
        val = -val;
    }
    
    if (val == 0) {
        uart_putc('0');
        return;
    }
    
    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    
    if (neg) uart_putc('-');
    while (i > 0) uart_putc(buf[--i]);
}

// Memory - heap must start AFTER BSS section ends (at 0x8040A500)
// Add some safety margin and align to page
static uint8_t *heap_ptr = (uint8_t*)0x80500000;  // Start at 5MB mark
static uint8_t *heap_end = (uint8_t*)0x88000000;  // 128MB total

void* MAlloc(size_t size) {
    size = (size + 7) & ~7;
    if (heap_ptr + size >= heap_end) return NULL;
    uint8_t *ptr = heap_ptr;
    heap_ptr += size;
    // Zero memory
    for (size_t i = 0; i < size; i++) ptr[i] = 0;
    return ptr;
}

void Free(void *ptr) {}

void* MemSet(void *s, int c, size_t n) {
    uint8_t *p = s;
    while (n--) *p++ = c;
    return s;
}

void* MemCpy(void *dst, const void *src, size_t n) {
    uint8_t *d = dst;
    const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dst;
}

// String
int StrLen(const char *s) {
    int len = 0;
    while (*s++) len++;
    return len;
}

char* StrCpy(char *dst, const char *src) {
    char *ret = dst;
    while ((*dst++ = *src++));
    return ret;
}

int StrCmp(const char *s1, const char *s2) {
    while (*s1 && *s1 == *s2) {
        s1++;
        s2++;
    }
    return *s1 - *s2;
}

char* StrDup(const char *s) {
    int len = StrLen(s);
    char *new_str = MAlloc(len + 1);
    if (new_str) StrCpy(new_str, s);
    return new_str;
}

char* StrCat(char *dst, const char *src) {
    char *ret = dst;
    while (*dst) dst++;
    while ((*dst++ = *src++));
    return ret;
}

int StrNCmp(const char *s1, const char *s2, size_t n) {
    while (n && *s1 && *s1 == *s2) {
        s1++;
        s2++;
        n--;
    }
    return n == 0 ? 0 : (*s1 - *s2);
}

// Number parsing
long long AToI64(const char *s) {
    long long val = 0;
    bool neg = false;
    while (*s == ' ' || *s == '\t') s++;
    if (*s == '-') { neg = true; s++; }
    while (*s >= '0' && *s <= '9') {
        val = val * 10 + (*s - '0');
        s++;
    }
    return neg ? -val : val;
}

double AToF64(const char *s) {
    return (double)AToI64(s);  // Simplified
}

long long StrToI64(const char *nptr, char **endptr, int base) {
    long long val = 0;
    bool neg = false;
    
    while (*nptr == ' ') nptr++;
    if (*nptr == '-') { neg = true; nptr++; }
    if (*nptr == '+') nptr++;
    
    if (base == 0) {
        if (*nptr == '0') {
            nptr++;
            if (*nptr == 'x' || *nptr == 'X') {
                base = 16;
                nptr++;
            } else if (*nptr == 'b' || *nptr == 'B') {
                base = 2;
                nptr++;
            } else {
                base = 8;
            }
        } else {
            base = 10;
        }
    }
    
    while (1) {
        int digit;
        if (*nptr >= '0' && *nptr <= '9') {
            digit = *nptr - '0';
        } else if (*nptr >= 'a' && *nptr <= 'f') {
            digit = *nptr - 'a' + 10;
        } else if (*nptr >= 'A' && *nptr <= 'F') {
            digit = *nptr - 'A' + 10;
        } else {
            break;
        }
        
        if (digit >= base) break;
        val = val * base + digit;
        nptr++;
    }
    
    if (endptr) *endptr = (char*)nptr;
    return neg ? -val : val;
}

// Character classification
bool IsAlpha(int c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

bool IsDigit(int c) {
    return c >= '0' && c <= '9';
}

bool IsAlNum(int c) {
    return IsAlpha(c) || IsDigit(c);
}

bool IsSpace(int c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

bool IsXDigit(int c) {
    return IsDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

// I/O
void Print(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

void PrintI64(int64_t val) {
    char buf[32];
    int i = 0;
    bool neg = false;
    
    if (val < 0) {
        neg = true;
        val = -val;
    }
    
    if (val == 0) {
        uart_putc('0');
        return;
    }
    
    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    
    if (neg) uart_putc('-');
    while (i > 0) uart_putc(buf[--i]);
}

void PrintF64(double val) {
    PrintI64((int64_t)val);  // Simplified
}

// Newlib stubs
struct _reent {
    int _errno;
};
struct _reent _impure_data = {0};
void* _impure_ptr = &_impure_data;

struct _FILE { int fd; };
struct _FILE __sf[3] = {{0}, {1}, {2}};
void *stdin = &__sf[0];
void *stdout = &__sf[1];
void *stderr = &__sf[2];

