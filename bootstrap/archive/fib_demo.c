#include <stdint.h>

#define UART_BASE 0x10000000

static void uart_putc(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20));
    *(volatile uint8_t*)UART_BASE = c;
}

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static void print_num(int64_t n) {
    char buf[32];
    int i = 0;
    int neg = 0;
    
    if (n < 0) {
        neg = 1;
        n = -n;
    }
    
    if (n == 0) {
        uart_putc('0');
        return;
    }
    
    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    
    if (neg) uart_putc('-');
    while (i > 0) uart_putc(buf[--i]);
}

extern unsigned char _binary_fibonacci_bin_start[];

int main(void) {
    uart_puts("\n\n");
    uart_puts("═══════════════════════════════════════════════════════════\n");
    uart_puts("  TempleOS RISC-V - HolyC Recursive Fibonacci\n");
    uart_puts("  Compiled with HolyC, Running on RISC-V!\n");
    uart_puts("═══════════════════════════════════════════════════════════\n");
    uart_puts("\n");
    
    // Call Fib(7) - should return 13
    // Fib sequence: 0, 1, 1, 2, 3, 5, 8, 13, 21...
    typedef int64_t (*fib_func_t)(int64_t);
    fib_func_t fib = (fib_func_t)(_binary_fibonacci_bin_start);
    
    uart_puts("Computing Fibonacci(7)...\n");
    int64_t result = fib(7);
    
    uart_puts("\nResult: ");
    print_num(result);
    uart_puts("\n");
    
    if (result == 13) {
        uart_puts("\n✅ SUCCESS!\n");
        uart_puts("   Recursive HolyC function works!\n");
        uart_puts("   Proper function calls\n");
        uart_puts("   Proper recursion\n");
        uart_puts("   Proper return values\n");
    } else {
        uart_puts("\n❌ ERROR: Expected 13, got ");
        print_num(result);
        uart_puts("\n");
    }
    
    uart_puts("\n═══════════════════════════════════════════════════════════\n");
    
    while (1) __asm__ volatile ("wfi");
    return 0;
}
