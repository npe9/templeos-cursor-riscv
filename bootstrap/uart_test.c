/* Simple UART test for RISC-V bootstrap */

#define UART_BASE 0x10000000
#define UART_LSR  5
#define UART_LSR_TX_IDLE  0x20

typedef unsigned char uint8_t;
typedef unsigned long uint64_t;

void uart_putc(uint8_t c) {
    while (!(*(volatile uint8_t*)(UART_BASE + UART_LSR) & UART_LSR_TX_IDLE));
    *(volatile uint8_t*)UART_BASE = c;
}

void uart_puts(const char *str) {
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

int main(void) {
    uart_puts("\n\n=== TempleOS RISC-V Bootstrap ===\n");
    uart_puts("UART Test Successful!\n");
    uart_puts("\nThis proves:\n");
    uart_puts("1. Startup code works\n");
    uart_puts("2. UART I/O works\n");
    uart_puts("3. Ready for HolyC compiler integration\n");
    uart_puts("\nPress Ctrl-A X to exit QEMU\n\n");
    
    // Halt
    while (1) {
        __asm__ volatile ("wfi");
    }
    
    return 0;
}


