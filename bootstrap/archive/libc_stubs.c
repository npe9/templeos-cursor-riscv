/* Complete libc stubs for bare metal compiler integration */

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdarg.h>
#include "holy_api.h"

// External functions from kernel
extern void* malloc(size_t size);
extern void free(void *ptr);
extern int my_strlen(const char *s);
extern void my_strcpy(char *dst, const char *src);
extern int my_strcmp(const char *s1, const char *s2);
extern void* memset(void *s, int c, size_t n);
extern void* memcpy(void *dst, const void *src, size_t n);
extern void uart_puts(const char *s);
extern void uart_print_i64(int64_t val);

// String functions that call kernel versions
int strlen(const char *s) { return my_strlen(s); }
int strcmp(const char *s1, const char *s2) { return my_strcmp(s1, s2); }
void strcpy(char *dst, const char *src) { my_strcpy(dst, src); }

char* strdup(const char *s) {
    int len = my_strlen(s);
    char *new_str = malloc(len + 1);
    if (new_str) my_strcpy(new_str, s);
    return new_str;
}

void* calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void *ptr = malloc(total);
    if (ptr) memset(ptr, 0, total);
    return ptr;
}

void* realloc(void *ptr, size_t size) {
    void *new_ptr = malloc(size);
    if (new_ptr && ptr) {
        memcpy(new_ptr, ptr, size);
    }
    return new_ptr;
}

// Number parsing
long long atoll(const char *nptr) {
    long long val = 0;
    bool neg = false;
    while (*nptr == ' ' || *nptr == '\t') nptr++;
    if (*nptr == '-') { neg = true; nptr++; }
    while (*nptr >= '0' && *nptr <= '9') {
        val = val * 10 + (*nptr - '0');
        nptr++;
    }
    return neg ? -val : val;
}

double atof(const char *nptr) {
    return (double)atoll(nptr);  // Simplified
}

long long strtoll(const char *nptr, char **endptr, int base) {
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
    
    while (true) {
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
const char _ctype_[256] = {0};

bool isalpha(int c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

bool isdigit(int c) {
    return c >= '0' && c <= '9';
}

bool isalnum(int c) {
    return isalpha(c) || isdigit(c);
}

bool isspace(int c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

bool isxdigit(int c) {
    return isdigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

// Printf family (route through Holy API)
int snprintf(char *str, size_t size, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int result = StrPrintFV(str, size, format, ap);
    va_end(ap);
    return result;
}

int printf(const char *format, ...) {
    uart_puts(format);
    return 0;
}

int fprintf(void *stream, const char *format, ...) {
    uart_puts(format);
    return 0;
}

// File I/O (all no-ops for bare metal)
void* fopen(const char *path, const char *mode) {
    (void)path; (void)mode;
    return (void*)1;  // Return fake file handle
}

int fseek(void *stream, long offset, int whence) {
    (void)stream; (void)offset; (void)whence;
    return 0;
}

long ftell(void *stream) {
    (void)stream;
    return 0;
}

size_t fread(void *ptr, size_t size, size_t nmemb, void *stream) {
    (void)ptr; (void)size; (void)nmemb; (void)stream;
    return 0;
}

size_t fwrite(const void *ptr, size_t size, size_t nmemb, void *stream) {
    (void)ptr; (void)size; (void)nmemb; (void)stream;
    return nmemb;  // Pretend we wrote it
}

int fclose(void *stream) {
    (void)stream;
    return 0;
}

// Newlib _impure_ptr
struct _reent {
    int _errno;
};
struct _reent _impure_data = {0};
struct _reent *_impure_ptr = &_impure_data;

struct _FILE {
    int fd;
};
struct _FILE __sf[3] = {{0}, {1}, {2}};
void *stdin = &__sf[0];
void *stdout = &__sf[1];
void *stderr = &__sf[2];


