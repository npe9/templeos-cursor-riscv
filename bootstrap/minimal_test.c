#include <stdint.h>
#define UART_BASE 0x10000000
static void put(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20));
    *(volatile uint8_t*)UART_BASE = c;
}
extern unsigned char _binary_test_local_bin_start[];
int main(void) {
    put('A');  // Before call
    typedef int64_t (*f_t)(void);
    f_t func = (f_t)(_binary_test_local_bin_start);
    put('B');  // About to call
    int64_t result = func();
    put('C');  // After call
    put('=');
    put('0' + (result / 10));
    put('0' + (result % 10));
    put('\n');
    while (1) __asm__ volatile ("wfi");
}
