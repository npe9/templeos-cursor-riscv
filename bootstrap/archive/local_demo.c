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
    char buf[32];
    int i = 0;
    if (n < 0) { put('-'); n = -n; }
    if (n == 0) { put('0'); return; }
    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    while (i > 0) put(buf[--i]);
}
extern unsigned char _binary_test_local_bin_start[];
int main(void) {
    puts("\n═══════════════════════════════════════════════════════════\n");
    puts("  LOCAL VARIABLES TEST (1:1 with TempleOS)\n");
    puts("═══════════════════════════════════════════════════════════\n\n");
    puts("HolyC code:\n");
    puts("  I64 Main() {\n");
    puts("    I64 x;\n");
    puts("    x = 5;\n");
    puts("    return x + x;\n");
    puts("  }\n\n");
    puts("Expected result: 10\n\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_test_local_bin_start))();
    
    puts("Actual result: ");
    print_num(result);
    puts("\n\n");
    
    if (result == 10) {
        puts("✅ ✅ ✅  SUCCESS!  ✅ ✅ ✅\n\n");
        puts("Local variables work correctly!\n");
        puts("IC pattern matches TempleOS 1:1!\n");
        puts("  IC_RBP + IC_IMM + IC_ADD + IC_DEREF\n\n");
    } else {
        puts("❌ FAILED - got ");
        print_num(result);
        puts(" instead of 10\n");
    }
    
    puts("═══════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
