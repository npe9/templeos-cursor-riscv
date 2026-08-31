/* Runtime stubs for bare metal linking */

#include <stdint.h>
#include <stddef.h>

// External heap functions from kernel_main.c
extern void* malloc(size_t size);
extern void free(void *ptr);
extern void* memset(void *s, int c, size_t n);
extern void* memcpy(void *dst, const void *src, size_t n);
extern int my_strlen(const char *s);
extern void my_strcpy(char *dst, const char *src);
extern int my_strcmp(const char *s1, const char *s2);

// Stubs for newlib functions
void* calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void *ptr = malloc(total);
    if (ptr) {
        memset(ptr, 0, total);
    }
    return ptr;
}

char* strdup(const char *s) {
    int len = my_strlen(s);
    char *new_str = malloc(len + 1);
    if (new_str) {
        my_strcpy(new_str, s);
    }
    return new_str;
}

int strcmp(const char *s1, const char *s2) {
    return my_strcmp(s1, s2);
}

int strlen(const char *s) {
    return my_strlen(s);
}

void strcpy(char *dst, const char *src) {
    my_strcpy(dst, src);
}

// Printf/fprintf stubs (no-ops for now)
int printf(const char *format, ...) {
    (void)format;
    return 0;
}

int fprintf(void *stream, const char *format, ...) {
    (void)stream;
    (void)format;
    return 0;
}

// Newlib's _impure_ptr (FILE* structure)
struct _reent {
    int _errno;
};
struct _reent _impure_data;
struct _reent *_impure_ptr = &_impure_data;

// Standard file descriptors (FILE*)
struct _FILE {
    int fd;
};
struct _FILE __sf[3] = {{0}, {1}, {2}};
void *stdin = &__sf[0];
void *stdout = &__sf[1];
void *stderr = &__sf[2];

// More stub functions
long long strtoll(const char *nptr, char **endptr, int base) {
    (void)nptr; (void)endptr; (void)base;
    return 0;  // Stub
}

// ctype stub
const char _ctype_[256] = {0};

// File I/O stubs (all no-ops)
void* fopen(const char *path, const char *mode) {
    (void)path; (void)mode;
    return NULL;
}

int fseek(void *stream, long offset, int whence) {
    (void)stream; (void)offset; (void)whence;
    return -1;
}

long ftell(void *stream) {
    (void)stream;
    return -1;
}

size_t fread(void *ptr, size_t size, size_t nmemb, void *stream) {
    (void)ptr; (void)size; (void)nmemb; (void)stream;
    return 0;
}

size_t fwrite(const void *ptr, size_t size, size_t nmemb, void *stream) {
    (void)ptr; (void)size; (void)nmemb; (void)stream;
    return 0;
}

int fclose(void *stream) {
    (void)stream;
    return 0;
}

