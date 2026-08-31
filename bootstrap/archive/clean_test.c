// Minimal test to verify function call works
#include <stddef.h>

typedef long long I64;
typedef unsigned char U8;

void uart_putc(char c) {
    volatile char *uart = (volatile char *)0x10000000;
    *uart = c;
}

void puts_uart(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

// The function we'll call
I64 TestFunc() {
    return 42;
}

void test_call() {
    puts_uart("Calling TestFunc...\n");
    I64 result = TestFunc();
    puts_uart("Result: ");
    
    // Print result in decimal
    if (result == 42) {
        puts_uart("42 - CORRECT!\n");
    } else {
        puts_uart("WRONG\n");
    }
}

int main() {
    puts_uart("Test: Direct function call\n");
    test_call();
    puts_uart("SUCCESS!\n");
    
    while(1);
    return 0;
}
