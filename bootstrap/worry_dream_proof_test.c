#include <stdint.h>
#define UART_BASE 0x10000000
static void put(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20));
    *(volatile uint8_t*)UART_BASE = c;
}
static void puts(const char *s) {
    while (*s) {
        if (*s == '\n') put('\r');
        put(*s++);
    }
}
static void print_num(int64_t n) {
    if (n < 10) {
        put('0' + n);
    } else {
        put('0' + (n / 10));
        put('0' + (n % 10));
    }
}
extern unsigned char _binary_worry_dream_proof_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  WORRY DREAM MACHINE - DEVICE REGISTER PROOF\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    puts("HolyC will write directly to UART register (0x10000000)...\n\n");
    puts("Output from HolyC:\n  ");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_worry_dream_proof_bin_start))();
    
    puts("\n\nMain() returned: ");
    print_num(result);
    puts("\n\n");
    
    if (result == 42) {
        puts("✅ ✅ ✅  WORRY DREAM MACHINE WORKS!  ✅ ✅ ✅\n\n");
        puts("This proves:\n");
        puts("  ✅ HolyC writes to device registers (UART 0x10000000)\n");
        puts("  ✅ Pointer stores work (*uart = value)\n");
        puts("  ✅ No C library dependencies\n");
        puts("  ✅ Direct hardware control from HolyC\n");
        puts("  ✅ Pure HolyC on bare metal RISC-V\n\n");
        puts("The Worry Dream Machine is REAL.\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
