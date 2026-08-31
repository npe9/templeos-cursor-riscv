#include <stdint.h>
#define UART_BASE 0x10000000
static void put(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20));
    *(volatile uint8_t*)UART_BASE = c;
}
extern unsigned char _binary_test_params_bin_start[];
int main(void) {
    put('A');  
    typedef int64_t (*f_add)(int64_t, int64_t);
    f_add add_func = (f_add)(_binary_test_params_bin_start);
    put('B');
    int64_t result = add_func(5, 7);
    put('C');
    put('=');
    put('0' + (result / 10));
    put('0' + (result % 10));
    put('\n');
    while (1) __asm__ volatile ("wfi");
}
