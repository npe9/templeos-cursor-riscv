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
    if (n == 0) { uart_putc('0'); return; }
    if (n < 0) { uart_putc('-'); n = -n; }
    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    while (i > 0) uart_putc(buf[--i]);
}

static char uart_getc(void) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x01));
    return *(volatile uint8_t*)UART_BASE;
}

// Compiler interface
extern void* CompilerNew(const char *source, const char *filename);
extern int ParseProgram(void *cc);
extern void* CompileAOT(void *cc, int64_t *size);
extern void CompilerFree(void *cc);
extern char* compiler_error;

// Code buffer for user input
static char code_buffer[4096];
static int code_pos = 0;

int main(void) {
    uart_puts("\n\n");
    uart_puts("════════════════════════════════════════════════════════════════\n");
    uart_puts("  HolyC UART Interactive Shell (1:1 with TempleOS)\n");
    uart_puts("════════════════════════════════════════════════════════════════\n\n");
    uart_puts("Type HolyC code, end with ;; to compile and run\n");
    uart_puts("Example: I64 Add(I64 a,I64 b){return a+b;};;\n\n");
    uart_puts("> ");
    
    while (1) {
        char c = uart_getc();
        
        if (c == '\r' || c == '\n') {
            uart_puts("\n");
            
            // Check for ;; terminator
            if (code_pos >= 2 && code_buffer[code_pos-1] == ';' && 
                code_buffer[code_pos-2] == ';') {
                
                // Remove ;; and null-terminate
                code_buffer[code_pos-2] = '\0';
                
                uart_puts("\nCompiling...\n");
                
                // Compile the code
                void *cc = CompilerNew(code_buffer, "uart");
                if (!cc) {
                    uart_puts("ERROR: Compiler init failed\n\n");
                    code_pos = 0;
                    uart_puts("> ");
                    continue;
                }
                
                if (!ParseProgram(cc)) {
                    uart_puts("ERROR: Parse failed\n\n");
                    CompilerFree(cc);
                    code_pos = 0;
                    uart_puts("> ");
                    continue;
                }
                
                int64_t size = 0;
                void *code = CompileAOT(cc, &size);
                
                if (!code) {
                    uart_puts("ERROR: Codegen failed\n\n");
                    CompilerFree(cc);
                    code_pos = 0;
                    uart_puts("> ");
                    continue;
                }
                
                uart_puts("✓ Compiled ");
                print_num(size);
                uart_puts(" bytes\n\n");
                
                // Try to call Main() if it exists
                uart_puts("Calling Main()...\n");
                typedef int64_t (*func_t)(void);
                
                // Assume Main is last function, try calling the code
                // This is a simplified test - real version would find Main in hash table
                func_t f = (func_t)(code);
                int64_t result = f();
                
                uart_puts("Result: ");
                print_num(result);
                uart_puts("\n\n");
                
                CompilerFree(cc);
                code_pos = 0;
            }
            
            uart_puts("> ");
        } else if (c == 127 || c == 8) {  // Backspace
            if (code_pos > 0) {
                code_pos--;
                uart_puts("\b \b");
            }
        } else if (code_pos < sizeof(code_buffer) - 1) {
            code_buffer[code_pos++] = c;
            uart_putc(c);
        }
    }
}
