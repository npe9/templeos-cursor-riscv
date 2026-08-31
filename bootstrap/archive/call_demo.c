#include <stdint.h>
#define UART_BASE 0x10000000
static inline void put(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20));
    *(volatile uint8_t*)UART_BASE = c;
}
extern unsigned char _binary_test_call_only_bin_start[];
typedef int64_t (*func_t)(void);
int main(void) {
    put('M');
    // Main() is now at offset 0x24
    volatile int64_t result = ((func_t)(_binary_test_call_only_bin_start + 0x24))();
    put('=');
    put('0' + (result & 0xF));
    put('\n');
    if (result == 9) {
        put('O'); put('K'); put('\n');
    }
    while (1) __asm__ volatile ("wfi");
}
