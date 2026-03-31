/* Helper functions for compiler to expose internals to REPL */

#include "holyc_compiler.h"

void CompilerSetHashTable(Compiler *cc, void *table) {
    cc->hash_table = (CHashTable*)table;
}

// Get pointer to last compiled function's exe_addr field
void **CompilerGetLastFuncAddr(Compiler *cc) {
    if (!cc || !cc->last_compiled_func) return NULL;
    return (void**)&cc->last_compiled_func->exe_addr;
}

// UART output for debug (bare metal)
#ifdef BARE_METAL
void uart_putc(char c) {
    volatile char *uart = (volatile char *)0x10000000;
    *uart = c;
}

static int append_char(char **dst, size_t *remaining, int *total, char c) {
    if (*remaining > 1) {
        **dst = c;
        (*dst)++;
        (*remaining)--;
    }
    (*total)++;
    return 0;
}

static void append_string(char **dst, size_t *remaining, int *total, const char *s) {
    if (!s) s = "(null)";
    while (*s) {
        append_char(dst, remaining, total, *s++);
    }
}

static void append_unsigned(char **dst, size_t *remaining, int *total,
                            unsigned long long value, unsigned base, bool negative) {
    char buffer[32];
    const char *digits = "0123456789abcdef";
    int pos = 0;

    if (value == 0) {
        buffer[pos++] = '0';
    } else {
        while (value && pos < (int)sizeof(buffer)) {
            buffer[pos++] = digits[value % base];
            value /= base;
        }
    }

    if (negative) {
        append_char(dst, remaining, total, '-');
    }

    while (pos--) {
        append_char(dst, remaining, total, buffer[pos]);
    }
}

int StrPrintFV(char *dst, size_t size, const char *format, va_list ap) {
    char *cursor = dst;
    size_t remaining = size ? size : 0;
    int total = 0;

    while (*format) {
        if (*format != '%') {
            append_char(&cursor, &remaining, &total, *format++);
            continue;
        }

        format++;  // Skip '%'
        bool long_flag = false;
        bool longlong_flag = false;

        if (*format == 'l') {
            format++;
            if (*format == 'l') {
                longlong_flag = true;
                format++;
            } else {
                long_flag = true;
            }
        }

        char spec = *format ? *format++ : '\0';
        switch (spec) {
            case 'd':
            case 'i': {
                long long val;
                if (longlong_flag) {
                    val = va_arg(ap, long long);
                } else if (long_flag) {
                    val = va_arg(ap, long);
                } else {
                    val = va_arg(ap, int);
                }
                bool negative = (val < 0);
                unsigned long long mag = negative ? (unsigned long long)(-val) : (unsigned long long)val;
                append_unsigned(&cursor, &remaining, &total, mag, 10, negative);
                break;
            }
            case 'u': {
                unsigned long long val;
                if (longlong_flag) {
                    val = va_arg(ap, unsigned long long);
                } else if (long_flag) {
                    val = va_arg(ap, unsigned long);
                } else {
                    val = va_arg(ap, unsigned int);
                }
                append_unsigned(&cursor, &remaining, &total, val, 10, false);
                break;
            }
            case 'x':
            case 'p': {
                unsigned long long val;
                if (spec == 'p') {
                    uintptr_t ptr = (uintptr_t)va_arg(ap, void *);
                    append_char(&cursor, &remaining, &total, '0');
                    append_char(&cursor, &remaining, &total, 'x');
                    val = (unsigned long long)ptr;
                } else if (longlong_flag) {
                    val = va_arg(ap, unsigned long long);
                } else if (long_flag) {
                    val = va_arg(ap, unsigned long);
                } else {
                    val = va_arg(ap, unsigned int);
                }
                append_unsigned(&cursor, &remaining, &total, val, 16, false);
                break;
            }
            case 's': {
                const char *s = va_arg(ap, const char *);
                append_string(&cursor, &remaining, &total, s);
                break;
            }
            case 'c': {
                int ch = va_arg(ap, int);
                append_char(&cursor, &remaining, &total, (char)ch);
                break;
            }
            case '%': {
                append_char(&cursor, &remaining, &total, '%');
                break;
            }
            default: {
                append_char(&cursor, &remaining, &total, '%');
                if (spec) {
                    append_char(&cursor, &remaining, &total, spec);
                }
                break;
            }
        }
    }

    if (size > 0) {
        if (remaining == 0) {
            dst[size - 1] = '\0';
        } else {
            *cursor = '\0';
        }
    }

    return total;
}

int StrPrintF(char *dst, size_t size, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int result = StrPrintFV(dst, size, format, ap);
    va_end(ap);
    return result;
}

char *strrchr(const char *s, int c) {
    const char *last = NULL;
    while (*s) {
        if (*s == (char)c) {
            last = s;
        }
        s++;
    }
    if (c == '\0') {
        return (char *)s;
    }
    return (char *)last;
}
#else
int StrPrintFV(char *dst, size_t size, const char *fmt, va_list ap) {
    return vsnprintf(dst, size, fmt, ap);
}

int StrPrintF(char *dst, size_t size, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int result = StrPrintFV(dst, size, fmt, ap);
    va_end(ap);
    return result;
}
#endif
