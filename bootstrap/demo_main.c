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

extern unsigned char _binary_demo_funcs_bin_start[];

int main(void) {
    uart_puts("\n\n");
    uart_puts("═══════════════════════════════════════════════════════════\n");
    uart_puts("      TempleOS RISC-V - HolyC Functions Running!\n");
    uart_puts("═══════════════════════════════════════════════════════════\n");
    uart_puts("\n");
    
    // Binary is 180 bytes now, Main() should be near the end
    // Let me just call offset 0 first to test
    typedef int64_t (*holyc_func_t)(int64_t, int64_t);
    
    // Call Add() directly at offset 0 with args 5, 3
    holyc_func_t add_func = (holyc_func_t)(_binary_demo_funcs_bin_start);
    
    uart_puts("Calling HolyC Add(5, 3) directly...\n");
    int64_t result = add_func(5, 3);
    
    uart_puts("Result: ");
    print_num(result);
    uart_puts("\n\n");
    
    if (result == 8) {
        uart_puts("✅ SUCCESS! HolyC functions work!\n");
    } else {
        uart_puts("❌ ERROR: Expected 8, got ");
        print_num(result);
        uart_puts("\n");
    }
    
    uart_puts("═══════════════════════════════════════════════════════════\n");
    
    while (1) __asm__ volatile ("wfi");
    return 0;
}
