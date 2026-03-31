#ifndef HOLY_API_H
#define HOLY_API_H

#include <stdarg.h>
#include <stddef.h>

int StrPrintFV(char *dst, size_t size, const char *fmt, va_list ap);
int StrPrintF(char *dst, size_t size, const char *fmt, ...);

#endif /* HOLY_API_H */

