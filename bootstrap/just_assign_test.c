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
extern unsigned char _binary_just_assign_bin_start[];
int main(void) {
    puts("\n══ ASSIGN TEST ══\n\n");
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_just_assign_bin_start))();
    put('R'); put('='); put('0'+result); puts("\n\n");
    if (result == 0) {
        puts("✅ Assign works!\n\n");
    }
    while (1) __asm__ volatile ("wfi");
}
