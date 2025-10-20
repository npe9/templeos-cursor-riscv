// Spike-Compatible Runtime Library for RISC-V
// Uses proxy kernel syscalls instead of direct UART access

// Syscall numbers (RISC-V Linux ABI)
#define SYS_read   63
#define SYS_write  64
#define SYS_exit   93

// File descriptors
#define STDIN  0
#define STDOUT 1
#define STDERR 2

// Syscall wrapper (inline assembly)
I64 syscall(I64 n, I64 arg0, I64 arg1, I64 arg2) {
    // In HolyC, we need to use asm blocks
    // For now, this is a placeholder that would be implemented
    // in the compiler's asm block support
    return 0; // Placeholder
}

// Console I/O using syscalls

U0 putc(U8 c) {
    // write(STDOUT, &c, 1)
    U8 buf[1];
    buf[0] = c;
    syscall(SYS_write, STDOUT, buf, 1);
}

U8 getc() {
    // read(STDIN, &c, 1)
    U8 c;
    syscall(SYS_read, STDIN, &c, 1);
    return c;
}

U0 puts(U8 *str) {
    I64 len = 0;
    U8 *s = str;
    while (*s++) len++;
    
    // write(STDOUT, str, len)
    syscall(SYS_write, STDOUT, str, len);
    
    // Add newline
    U8 nl = '\n';
    syscall(SYS_write, STDOUT, &nl, 1);
}

U0 print_i64(I64 val) {
    U8 buf[32];
    I64 i = 0;
    Bool neg = FALSE;
    
    if (val < 0) {
        neg = TRUE;
        val = -val;
    }
    
    if (val == 0) {
        putc('0');
        return;
    }
    
    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    
    if (neg) putc('-');
    
    while (i > 0) {
        putc(buf[--i]);
    }
}

U0 print_hex(U64 val) {
    U8 *hex = "0123456789ABCDEF";
    putc('0');
    putc('x');
    
    for (I64 i = 60; i >= 0; i -= 4) {
        putc(hex[(val >> i) & 0xF]);
    }
}

// Memory management (simple bump allocator)
U8 *_heap_ptr = 0x80400000;  // Start after 4MB
U8 *_heap_end = 0x88000000;  // 128MB heap

U8 *malloc(I64 size) {
    size = (size + 7) & ~7;  // Align to 8 bytes
    
    if (_heap_ptr + size >= _heap_end) {
        puts("ERROR: Out of memory!");
        syscall(SYS_exit, 1, 0, 0);
        return NULL;
    }
    
    U8 *ptr = _heap_ptr;
    _heap_ptr += size;
    return ptr;
}

U0 free(U8 *ptr) {
    // Simple bump allocator - no-op for free
}

// String functions
I64 strlen(U8 *str) {
    I64 len = 0;
    while (*str++) len++;
    return len;
}

U8 *strcpy(U8 *dst, U8 *src) {
    U8 *ret = dst;
    while ((*dst++ = *src++));
    return ret;
}

I64 strcmp(U8 *s1, U8 *s2) {
    while (*s1 && *s1 == *s2) {
        s1++;
        s2++;
    }
    return *s1 - *s2;
}

U8 *strdup(U8 *str) {
    I64 len = strlen(str);
    U8 *new_str = malloc(len + 1);
    if (new_str) {
        strcpy(new_str, str);
    }
    return new_str;
}

// Initialization
U0 RuntimeInit() {
    puts("");
    puts("=== TempleOS RISC-V Spike Runtime ===");
    puts("Runtime initialized for Spike simulator");
    puts("Using proxy kernel syscalls for I/O");
    puts("");
}

// Exit function
U0 Exit(I64 code) {
    syscall(SYS_exit, code, 0, 0);
}


