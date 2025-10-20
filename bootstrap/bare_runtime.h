/* Bare Metal Runtime for HolyC Compiler
 * Replaces all libc dependencies with HolyC-style functions
 */

#ifndef BARE_RUNTIME_H
#define BARE_RUNTIME_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// Memory management
void* MAlloc(size_t size);
void Free(void *ptr);
void* MemSet(void *s, int c, size_t n);
void* MemCpy(void *dst, const void *src, size_t n);

// String functions
int StrLen(const char *s);
char* StrCpy(char *dst, const char *src);
int StrCmp(const char *s1, const char *s2);
char* StrDup(const char *s);
char* StrCat(char *dst, const char *src);
int StrNCmp(const char *s1, const char *s2, size_t n);

// Number parsing
long long AToI64(const char *s);
double AToF64(const char *s);
long long StrToI64(const char *nptr, char **endptr, int base);

// Character classification
bool IsAlpha(int c);
bool IsDigit(int c);
bool IsAlNum(int c);
bool IsSpace(int c);
bool IsXDigit(int c);

// I/O (UART-based, no-ops allowed for now)
void uart_putc(char c);
char uart_getc(void);
void uart_puts(const char *s);
void uart_print_i64(int64_t val);
void Print(const char *s);
void PrintI64(int64_t val);
void PrintF64(double val);

// Map libc names to HolyC-style names
#define malloc MAlloc
#define free Free
#define calloc(n, s) MemSet(MAlloc((n)*(s)), 0, (n)*(s))
#define realloc(p, s) MAlloc(s)  // Simplified
#define memset MemSet
#define memcpy MemCpy
#define strlen StrLen
#define strcpy StrCpy
#define strcmp StrCmp
#define strdup StrDup
#define strcat StrCat
#define strncmp StrNCmp
#define atoll AToI64
#define atof AToF64
#define strtoll StrToI64
#define isalpha IsAlpha
#define isdigit IsDigit
#define isalnum IsAlNum
#define isspace IsSpace
#define isxdigit IsXDigit

// Disable stdio (all no-ops or stubs)
typedef void FILE;
typedef long off_t;
#define printf(...) ((void)0)
#define fprintf(...) ((void)0)
#define snprintf(buf, size, fmt, ...) (buf[0]='\0', 0)
#define fopen(path, mode) ((FILE*)NULL)
#define fclose(f) 0
#define fread(ptr, size, nmemb, stream) 0
#define fwrite(ptr, size, nmemb, stream) 0
#define fseek(stream, offset, whence) 0
#define ftell(stream) 0

// mmap stubs
#define PAGE_SIZE 4096
#define PROT_READ 1
#define PROT_WRITE 2
#define PROT_EXEC 4
#define MAP_PRIVATE 2
#define MAP_ANONYMOUS 0x20
#define MAP_FAILED ((void*)-1)
static inline void* mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    (void)addr; (void)prot; (void)flags; (void)fd; (void)offset;
    return MAlloc(len);
}
static inline int munmap(void *addr, size_t len) {
    (void)addr; (void)len;
    return 0;
}

// Newlib compatibility
extern void* _impure_ptr;
extern void* stdin;
extern void* stdout;
extern void* stderr;

#endif // BARE_RUNTIME_H

