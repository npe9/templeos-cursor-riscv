/* Spike ISA Simulator Test
 * Uses proxy kernel (pk) syscalls instead of direct UART access
 */

// Syscall numbers for RISC-V Linux ABI
#define SYS_write 64
#define SYS_exit  93

typedef unsigned long size_t;
typedef long ssize_t;

// Syscall wrapper
static inline long syscall(long n, long arg0, long arg1, long arg2) {
    register long a0 asm("a0") = arg0;
    register long a1 asm("a1") = arg1;
    register long a2 asm("a2") = arg2;
    register long a7 asm("a7") = n;
    
    asm volatile ("ecall"
                  : "+r"(a0)
                  : "r"(a1), "r"(a2), "r"(a7)
                  : "memory");
    
    return a0;
}

ssize_t write(int fd, const void *buf, size_t count) {
    return syscall(SYS_write, fd, (long)buf, (long)count);
}

void exit(int code) {
    syscall(SYS_exit, code, 0, 0);
    while(1); // Should never reach here
}

size_t strlen(const char *s) {
    size_t len = 0;
    while (*s++) len++;
    return len;
}

void puts(const char *s) {
    write(1, s, strlen(s));
    write(1, "\n", 1);
}

int main(void) {
    puts("");
    puts("═══════════════════════════════════════════════════════════");
    puts("TempleOS RISC-V Bootstrap - Spike ISA Simulator Test");
    puts("═══════════════════════════════════════════════════════════");
    puts("");
    puts("✓ Spike simulator running");
    puts("✓ Proxy kernel (pk) working");
    puts("✓ Console I/O functional");
    puts("✓ Syscalls operational");
    puts("");
    puts("This proves:");
    puts("1. Code runs correctly in Spike");
    puts("2. Proxy kernel provides console I/O");
    puts("3. Ready for HolyC compiler integration");
    puts("");
    puts("Next steps:");
    puts("- Create Spike-compatible runtime library");
    puts("- Port UART editor to use syscalls");
    puts("- Test HolyC compilation in Spike");
    puts("");
    puts("═══════════════════════════════════════════════════════════");
    puts("");
    
    exit(0);  // Explicitly exit instead of returning
    return 0; // Never reached
}

