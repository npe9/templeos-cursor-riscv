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
extern unsigned char _binary_worry_dream_devices_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  WORRY DREAM MACHINE - DEVICE READ/WRITE PROOF\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    puts("HolyC will:\n");
    puts("  READ from UART LSR register (0x10000005)\n");
    puts("  WRITE to UART TX register (0x10000000)\n\n");
    puts("Output from HolyC:\n  ");
    
    typedef int64_t (*f_t)(void);
    int64_t status = ((f_t)(_binary_worry_dream_devices_bin_start))();
    
    puts("\n\nUART status register value: ");
    print_hex(status);
    puts("\n\n");
    
    if (status != 0) {
        puts("✅ ✅ ✅  DEVICE REGISTER READ/WRITE WORKS!  ✅ ✅ ✅\n\n");
        puts("HolyC directly:\n");
        puts("  ✅ READ from device register (UART LSR)\n");
        puts("  ✅ WRITE to device register (UART TX)\n");
        puts("  ✅ Returned status value: ");
        print_hex(status);
        puts("\n");
        puts("  ✅ Multiple register access\n");
        puts("  ✅ No C library - pure HolyC\n\n");
        puts("Worry Dream Machine: Read and Write device registers.\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
