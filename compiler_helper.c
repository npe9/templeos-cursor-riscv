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
#endif
