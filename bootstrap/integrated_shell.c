/* Integrated Shell with Real HolyC Compiler */

#include "holyc_compiler_bare.h"

#define UART_BASE 0x10000000
#define UART_LSR  5
#define UART_LSR_RX_READY 0x01
#define UART_LSR_TX_IDLE  0x20

extern void uart_putc(char c);
extern char uart_getc(void);
extern void uart_puts(const char *s);
extern void uart_print_i64(int64_t val);

// Function registry
#define MAX_FUNCS 16
static struct {
    char name[64];
    uint8_t *code;
    int64_t size;
} functions[MAX_FUNCS];
static int func_count = 0;

void read_line(char *buf, int max) {
    int pos = 0;
    uart_puts("> ");
    
    while (1) {
        char ch = uart_getc();
        
        if (ch == '\r' || ch == '\n') {
            uart_puts("\n");
            buf[pos] = '\0';
            return;
        } else if (ch == 127 || ch == 8) {
            if (pos > 0) {
                pos--;
                uart_putc('\b');
                uart_putc(' ');
                uart_putc('\b');
            }
        } else if (ch >= 32 && ch < 127 && pos < max - 1) {
            buf[pos++] = ch;
            uart_putc(ch);
        }
    }
}

int main(void) {
    uart_puts("\n\n");
    uart_puts("═══════════════════════════════════════════════════════════\n");
    uart_puts("    TempleOS RISC-V - REAL HolyC Compiler Integrated\n");
    uart_puts("═══════════════════════════════════════════════════════════\n");
    uart_puts("\n");
    uart_puts("Define functions, then call them!\n");
    uart_puts("\n");
    uart_puts("Example:\n");
    uart_puts("  I64 Double() { return 84; }\n");
    uart_puts("  END\n");
    uart_puts("  Double\n");
    uart_puts("\n");
    
    char input[256];
    char code_buffer[8192];
    int code_len = 0;
    
    while (1) {
        read_line(input, sizeof(input));
        
        if (input[0] == '\0') continue;
        
        // Check for END command
        if (StrCmp(input, "END") == 0) {
            if (code_len == 0) continue;
            
            code_buffer[code_len] = '\0';
            
            uart_puts("\n>>> Compiling with REAL HolyC compiler...\n");
            
            // Create compiler instance
            uart_puts(">>> Creating compiler...\n");
            Compiler *cc = CompilerNew(code_buffer, "repl.hc");
            if (!cc) {
                uart_puts("ERROR: Compiler init failed\n\n");
                code_len = 0;
                continue;
            }
            uart_puts(">>> Compiler created\n");
            
            // Parse
            uart_puts(">>> Parsing program...\n");
            bool parse_ok = ParseProgram(cc);
            uart_puts(">>> Parse returned\n");
            
            if (!parse_ok) {
                uart_puts("ERROR: Parse failed\n\n");
                CompilerFree(cc);
                code_len = 0;
                continue;
            }
            
            // Get generated code
            uint8_t *binary = cc->code_buffer;
            int64_t size = cc->code_size;
            
            if (binary && size > 0) {
                uart_puts("✓ Compiled ");
                uart_print_i64(size);
                uart_puts(" bytes\n");
                
                // Extract function name (simplified)
                char *p = code_buffer;
                while (*p && *p != ' ') p++;
                while (*p == ' ') p++;
                
                int i = 0;
                while (*p && *p != '(' && i < 63) {
                    functions[func_count].name[i++] = *p++;
                }
                functions[func_count].name[i] = '\0';
                
                functions[func_count].code = binary;
                functions[func_count].size = size;
                func_count++;
                
                uart_puts("✓ Function '");
                uart_puts(functions[func_count-1].name);
                uart_puts("' loaded\n");
                uart_puts("✓ Type '");
                uart_puts(functions[func_count-1].name);
                uart_puts("' to call it\n\n");
            } else {
                uart_puts("ERROR: Code generation failed\n\n");
                CompilerFree(cc);
            }
            
            code_len = 0;
            continue;
        }
        
        // Check if calling a function
        bool is_call = false;
        for (int i = 0; i < func_count; i++) {
            if (StrCmp(input, functions[i].name) == 0) {
                uart_puts("\n>>> Calling ");
                uart_puts(functions[i].name);
                uart_puts("()...\n");
                
                typedef int64_t (*func_t)(void);
                func_t f = (func_t)functions[i].code;
                int64_t result = f();
                
                uart_puts(">>> Returned: ");
                uart_print_i64(result);
                uart_puts("\n\n");
                
                is_call = true;
                break;
            }
        }
        
        if (is_call) continue;
        
        // Commands
        if (input[0] == ':') {
            if (StrCmp(input + 1, "quit") == 0) {
                uart_puts("Goodbye!\n");
                break;
            }
            continue;
        }
        
        // Add line to code buffer
        int len = StrLen(input);
        if (code_len + len + 2 < 8192) {
            StrCpy(&code_buffer[code_len], input);
            code_len += len;
            code_buffer[code_len++] = '\n';
            code_buffer[code_len] = '\0';
        }
    }
    
    while (1) __asm__ volatile ("wfi");
    return 0;
}

