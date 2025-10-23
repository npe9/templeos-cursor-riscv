// Bare metal stubs for missing libc functions
#include <stddef.h>

void *malloc(size_t size) {
    static char heap[1024*1024];  // 1MB heap
    static size_t offset = 0;
    if (offset + size > sizeof(heap)) return NULL;
    void *ptr = &heap[offset];
    offset += size;
    return ptr;
}

void *calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void *ptr = malloc(total);
    if (ptr) {
        for (size_t i = 0; i < total; i++)
            ((char*)ptr)[i] = 0;
    }
    return ptr;
}

void free(void *ptr) { /* no-op */ }

char *strdup(const char *s) {
    size_t len = 0;
    while (s[len]) len++;
    char *dup = malloc(len + 1);
    if (dup) {
        for (size_t i = 0; i <= len; i++)
            dup[i] = s[i];
    }
    return dup;
}

int strcmp(const char *s1, const char *s2) {
    while (*s1 && *s1 == *s2) {
        s1++; s2++;
    }
    return *(unsigned char*)s1 - *(unsigned char*)s2;
}

void *memcpy(void *dest, const void *src, size_t n) {
    char *d = dest;
    const char *s = src;
    for (size_t i = 0; i < n; i++)
        d[i] = s[i];
    return dest;
}

void *memset(void *s, int c, size_t n) {
    unsigned char *p = s;
    for (size_t i = 0; i < n; i++)
        p[i] = c;
    return s;
}

size_t strlen(const char *s) {
    size_t len = 0;
    while (s[len]) len++;
    return len;
}

char *strcpy(char *dest, const char *src) {
    char *d = dest;
    while ((*d++ = *src++));
    return dest;
}

long long strtoll(const char *nptr, char **endptr, int base) {
    long long result = 0;
    int neg = 0;
    while (*nptr == ' ' || *nptr == '\t') nptr++;
    if (*nptr == '-') { neg = 1; nptr++; }
    else if (*nptr == '+') nptr++;
    while (*nptr) {
        int digit;
        if (*nptr >= '0' && *nptr <= '9') digit = *nptr - '0';
        else if (*nptr >= 'a' && *nptr <= 'z') digit = *nptr - 'a' + 10;
        else if (*nptr >= 'A' && *nptr <= 'Z') digit = *nptr - 'A' + 10;
        else break;
        if (digit >= base) break;
        result = result * base + digit;
        nptr++;
    }
    if (endptr) *endptr = (char*)nptr;
    return neg ? -result : result;
}

// Stubs for FILE operations
typedef struct { int dummy; } FILE;
FILE *fopen(const char *path, const char *mode) { return NULL; }
int fclose(FILE *stream) { return 0; }
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) { return 0; }
int fseek(FILE *stream, long offset, int whence) { return -1; }
long ftell(FILE *stream) { return -1; }

// Stub for ctype
const unsigned short *_ctype_ = NULL;
