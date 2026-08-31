/* Shim to call HolyC Main() from C startup */

#include <stdint.h>

#define UART_BASE 0x10000000
#define UART_LSR  5
#define UART_LSR_TX_IDLE  0x20

static void uart_putc(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + UART_LSR) & UART_LSR_TX_IDLE));
    *(volatile uint8_t*)UART_BASE = c;
}

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

// HolyC binaries are linked as data
extern unsigned char _binary_compiler_bin_start[];

int main(void) {
    uart_puts("\nBOOT: Calling HolyC Main()...\n\n");
    
    // HolyC Main() is at the start of the binary
    typedef void (*holyc_main_t)(void);
    holyc_main_t holyc_main = (holyc_main_t)_binary_compiler_bin_start;
    
    // Call it
    holyc_main();
    
    uart_puts("\nBOOT: HolyC Main() returned\n");
    
    // Halt
    while (1) __asm__ volatile ("wfi");
    return 0;
}

