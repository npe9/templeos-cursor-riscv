// Worry Dream Machine - Interactive HolyC REPL over UART
// Minimal, clean, functional

#include <stdint.h>

#define UART_BASE 0x10000000
#define MAX_LINE 256

// UART primitives
static void uart_putc(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20));
    *(volatile uint8_t*)UART_BASE = c;
}

static char uart_getc(void) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x01));
    return *(volatile uint8_t*)UART_BASE;
}

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static void uart_print_hex(uint64_t val) {
    uart_puts("0x");
    for (int i = 15; i >= 0; i--) {
        int digit = (val >> (i * 4)) & 0xF;
        uart_putc(digit < 10 ? '0' + digit : 'a' + digit - 10);
    }
}

// Simple line editor
static int readline(char *buf, int max) {
    int pos = 0;
    while (1) {
        char c = uart_getc();
        
        if (c == '\r' || c == '\n') {
            buf[pos] = '\0';
            uart_puts("\n");
            return pos;
        }
        
        if (c == 127 || c == 8) {  // Backspace
            if (pos > 0) {
                pos--;
                uart_puts("\b \b");
            }
            continue;
        }
        
        if (c == 3) {  // Ctrl-C
            uart_puts("^C\n");
            buf[0] = '\0';
            return 0;
        }
        
        if (pos < max - 1 && c >= 32 && c < 127) {
            buf[pos++] = c;
            uart_putc(c);
        }
    }
}

// Compiler integration (stubbed for now)
extern void *CompileHolyC(const char *source);
extern int64_t ExecuteCode(void *code);

// REPL
void repl(void) {
    char line[MAX_LINE];
    char code_buffer[4096];
    int code_len = 0;
    
    uart_puts("\n");
    uart_puts("═══════════════════════════════════════════════════════\n");
    uart_puts("  WORRY DREAM MACHINE\n");
    uart_puts("  Interactive HolyC on RISC-V\n");
    uart_puts("═══════════════════════════════════════════════════════\n\n");
    uart_puts("Commands:\n");
    uart_puts("  <code>  - Execute HolyC code\n");
    uart_puts("  .clear  - Clear buffer\n");
    uart_puts("  .run    - Compile and run\n");
    uart_puts("  .help   - Show help\n\n");
    
    while (1) {
        uart_puts("> ");
        int len = readline(line, MAX_LINE);
        
        if (len == 0) continue;
        
        // Commands
        if (line[0] == '.') {
            if (line[1] == 'h') {
                uart_puts("Worry Dream Machine - HolyC REPL\n");
                uart_puts("Type code and press Enter to execute\n");
                continue;
            }
            if (line[1] == 'c') {
                code_len = 0;
                uart_puts("Buffer cleared\n");
                continue;
            }
            if (line[1] == 'r') {
                if (code_len > 0) {
                    code_buffer[code_len] = '\0';
                    uart_puts("Compiling...\n");
                    void *code = CompileHolyC(code_buffer);
                    if (code) {
                        uart_puts("Executing...\n");
                        int64_t result = ExecuteCode(code);
                        uart_puts("Result: ");
                        uart_print_hex(result);
                        uart_puts("\n");
                    } else {
                        uart_puts("Compilation failed\n");
                    }
                    code_len = 0;
                }
                continue;
            }
        }
        
        // Accumulate code
        for (int i = 0; i < len && code_len < 4095; i++) {
            code_buffer[code_len++] = line[i];
        }
        code_buffer[code_len++] = '\n';
        
        // Auto-execute simple expressions
        if (line[len-1] == ';') {
            code_buffer[code_len] = '\0';
            void *code = CompileHolyC(code_buffer);
            if (code) {
                int64_t result = ExecuteCode(code);
                uart_print_hex(result);
                uart_puts("\n");
            }
            code_len = 0;
        }
    }
}

int main(void) {
    repl();
    while (1) __asm__ volatile ("wfi");
}


