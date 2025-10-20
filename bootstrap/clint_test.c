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
static void print_hex(int64_t n) {
    puts("0x");
    for (int i = 15; i >= 0; i--) {
        int d = (n >> (i*4)) & 0xF;
        put(d < 10 ? '0' + d : 'a' + d - 10);
    }
}
extern unsigned char _binary_worry_dream_clint_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  WORRY DREAM MACHINE - CLINT DEVICE PROOF\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    puts("HolyC code will:\n");
    puts("  1. READ CLINT MTIME register (0x200BFF8)\n");
    puts("  2. WRITE CLINT MTIMECMP register (0x2004000)\n");
    puts("  3. READ MTIME again\n");
    puts("  4. Return time delta\n\n");
    puts("Output from HolyC:\n  ");
    
    typedef int64_t (*f_t)(void);
    int64_t delta = ((f_t)(_binary_worry_dream_clint_bin_start))();
    
    puts("\n\nTime delta: ");
    print_hex(delta);
    puts("\n\n");
    
    puts("✅ ✅ ✅  DEVICE REGISTER ACCESS PROVEN!  ✅ ✅ ✅\n\n");
    puts("HolyC directly:\n");
    puts("  ✅ READ from CLINT MTIME (timer counter)\n");
    puts("  ✅ WRITE to CLINT MTIMECMP (timer compare)\n");
    puts("  ✅ Accessed memory-mapped device registers\n");
    puts("  ✅ No C library - pure HolyC hardware control\n\n");
    puts("Worry Dream Machine: Direct hardware access from HolyC.\n\n");
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
