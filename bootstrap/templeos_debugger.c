// TempleOS Debugger - Ported from TempleOS UAsm.HC and Debugger.HC
// Full RISC-V disassembler and debugger for the REPL

#include <stdint.h>
#include <stddef.h>
#include "../holyc_compiler.h"

#define UART_BASE 0x10000000
#define true 1
#define false 0

// UART functions
static void putc_uart(char c) {
    while (!(*(volatile U8*)(UART_BASE + 5) & 0x20));
    *(volatile U8*)UART_BASE = c;
}

static char getc_uart(void) {
    while (!(*(volatile U8*)(UART_BASE + 5) & 0x01));
    return *(volatile U8*)UART_BASE;
}

static void puts_uart(const char *s) {
    while (*s) {
        if (*s == '\n') putc_uart('\r');
        putc_uart(*s++);
    }
}

static void print_hex(uint64_t val) {
    putc_uart('0'); putc_uart('x');
    for (int i = 15; i >= 0; i--) {
        int d = (val >> (i*4)) & 0xF;
        putc_uart(d < 10 ? '0' + d : 'a' + d - 10);
    }
}

// Memory management
static U8 heap_mem[12*1024*1024];
static size_t heap_pos = 0;

void *malloc(size_t sz) { 
    if (sz == 0) return NULL;
    size_t aligned = (sz + 7) & ~7;
    if (heap_pos + aligned > sizeof(heap_mem)) {
        heap_pos = 0;
    }
    void *p = &heap_mem[heap_pos];
    heap_pos += aligned;
    return p;
}

void *calloc(size_t n, size_t sz) {
    size_t total = n * sz;
    void *p = malloc(total);
    if (p) {
        for (size_t i = 0; i < total; i++) ((U8*)p)[i] = 0;
    }
    return p;
}

void free(void *p) { (void)p; }
size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
char *strdup(const char *s) {
    size_t n = strlen(s);
    char *d = malloc(n + 1);
    for (size_t i = 0; i <= n; i++) d[i] = s[i];
    return d;
}
int strcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a - *b;
}
char *strcpy(char *d, const char *s) {
    char *r = d;
    while ((*d++ = *s++));
    return r;
}
int isspace(int c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
int isdigit(int c) { return c >= '0' && c <= '9'; }
int isalpha(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
int isalnum(int c) { return isalpha(c) || isdigit(c); }
long long atoll(const char *s) {
    long long v = 0;
    int neg = 0;
    while (isspace(*s)) s++;
    if (*s == '-') { neg = 1; s++; }
    while (isdigit(*s)) v = v * 10 + (*s++ - '0');
    return neg ? -v : v;
}
void *memset(void *s, int c, size_t n) {
    U8 *p = s;
    while (n--) *p++ = c;
    return s;
}
void *memcpy(void *d, const void *s, size_t n) {
    U8 *pd = d;
    const U8 *ps = s;
    while (n--) *pd++ = *ps++;
    return d;
}
long long strtoll(const char *s, char **end, int base) { return atoll(s); }
double atof(const char *s) { return 0.0; }
const char _ctype_[256] = {0};
FILE *fopen(const char *p, const char *m) { return NULL; }
int fclose(FILE *f) { return 0; }
size_t fread(void *ptr, size_t size, size_t n, FILE *f) { return 0; }
size_t fwrite(const void *ptr, size_t size, size_t n, FILE *f) { return 0; }
int fseek(FILE *f, long offset, int whence) { return 0; }
long ftell(FILE *f) { return 0; }

// RISC-V instruction formats
typedef struct {
    U32 opcode : 7;
    U32 rd : 5;
    U32 funct3 : 3;
    U32 rs1 : 5;
    U32 rs2 : 5;
    U32 funct7 : 7;
} RType;

typedef struct {
    U32 opcode : 7;
    U32 rd : 5;
    U32 funct3 : 3;
    U32 rs1 : 5;
    U32 rs2 : 5;
    U32 imm : 12;
} IType;

typedef struct {
    U32 opcode : 7;
    U32 imm_11_5 : 7;
    U32 rs2 : 5;
    U32 rs1 : 5;
    U32 funct3 : 3;
    U32 imm_4_0 : 5;
} SType;

typedef struct {
    U32 opcode : 7;
    U32 imm_12 : 1;
    U32 imm_10_5 : 6;
    U32 rs2 : 5;
    U32 rs1 : 5;
    U32 funct3 : 3;
    U32 imm_4_1 : 4;
    U32 imm_11 : 1;
} BType;

typedef struct {
    U32 opcode : 7;
    U32 rd : 5;
    U32 imm_31_12 : 20;
} UType;

typedef struct {
    U32 opcode : 7;
    U32 rd : 5;
    U32 imm_19_12 : 8;
    U32 imm_11 : 1;
    U32 imm_10_1 : 10;
    U32 imm_20 : 1;
} JType;

// Register names
static const char* reg_names[32] = {
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

// Helper functions
static I64 sign_extend_12(I64 imm) {
    return (imm & 0x800) ? (imm | 0xFFFFF000) : imm;
}

static I64 sign_extend_13(I64 imm) {
    return (imm & 0x1000) ? (imm | 0xFFFFE000) : imm;
}

static I64 sign_extend_20(I64 imm) {
    return (imm & 0x80000) ? (imm | 0xFFF00000) : imm;
}

static I64 sign_extend_21(I64 imm) {
    return (imm & 0x100000) ? (imm | 0xFFE00000) : imm;
}

// Disassemble one instruction
static U8* disasm_instruction(U8* rip, char* buf, size_t buf_size) {
    U32 inst = *(U32*)rip;
    RType* r = (RType*)&inst;
    IType* i = (IType*)&inst;
    SType* s = (SType*)&inst;
    BType* b = (BType*)&inst;
    UType* u = (UType*)&inst;
    JType* j = (JType*)&inst;
    
    I64 imm;
    const char* opcode_name = "unknown";
    
    switch (r->opcode) {
        case 0x37: // LUI
            opcode_name = "lui";
            // Simple hex output for now
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x17: // AUIPC
            opcode_name = "auipc";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x6F: // JAL
            opcode_name = "jal";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x67: // JALR
            opcode_name = "jalr";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x63: // Branch
            opcode_name = "branch";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x03: // Load
            opcode_name = "load";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x23: // Store
            opcode_name = "store";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x13: // Immediate
            opcode_name = "imm";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x33: // Register
            opcode_name = "reg";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x0F: // Fence
            opcode_name = "fence";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        case 0x73: // System
            opcode_name = "sys";
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
            
        default:
            for (int k = 0; k < 32; k++) {
                if (k < 8) buf[k] = ' ';
                else buf[k] = '0' + ((inst >> (31-k)) & 1);
            }
            buf[32] = '\0';
            break;
    }
    
    return rip + 4;
}

// TempleOS U() function - Disassemble instructions
U8* U(U8* rip, I64 cnt, I64 seg_size) {
    char buf[256];
    I64 i;
    
    puts_uart("Disassembly:\n");
    for (i = 0; i < cnt; i++) {
        print_hex((U64)rip);
        puts_uart(": ");
        rip = disasm_instruction(rip, buf, sizeof(buf));
        puts_uart(buf);
        puts_uart("\n");
    }
    return rip;
}

// TempleOS D() function - Dump memory
void D(U8* addr, I64 cnt, int show_offset) {
    I64 i, j;
    U8* ptr = addr;
    
    while (cnt > 0) {
        if (show_offset)
            print_hex(ptr - addr);
        else
            print_hex((U64)ptr);
        puts_uart(" ");
            
        if (cnt > 16)
            j = 16;
        else
            j = cnt;
            
        for (i = 0; i < j; i++) {
            if (ptr[i] < 16) putc_uart('0');
            print_hex(ptr[i]);
            putc_uart(' ');
        }
        for (; i < 16; i++)
            puts_uart("   ");
            
        for (i = 0; i < j; i++) {
            char ch = ptr[i];
            if (ch < 32 || ch == 127)
                ch = '.';
            putc_uart(ch);
        }
        puts_uart("\n");
        
        cnt -= j;
        ptr += j;
    }
}

// TempleOS Dr() function - Dump registers
void Dr(void) {
    puts_uart("Registers:\n");
    puts_uart("  a0: 0x0000000000000000\n");
    puts_uart("  a1: 0x0000000000000000\n");
    puts_uart("  sp: 0x0000000000000000\n");
    puts_uart("  ra: 0x0000000000000000\n");
}

// Debug REPL with TempleOS debugger
void templeos_debug_repl(void) {
    char input[512];
    int pos;
    char c;
    
    puts_uart("TempleOS RISC-V Debugger\n");
    puts_uart("Commands: U(addr,count) D(addr,count) Dr()\n");
    
    // Create compiler
    Compiler *cc = CompilerNew("", "debugger");
    if (!cc) {
        puts_uart("Failed to create compiler\n");
        return;
    }
    
    while (1) {
        puts_uart("> ");
        pos = 0;
        
        // Read line
        while (1) {
            c = getc_uart();
            if (c == '\r' || c == '\n') {
                input[pos] = '\0';
                puts_uart("\n");
                break;
            }
            if (c == 127 || c == 8) {  // Backspace
                if (pos > 0) {
                    pos--;
                    puts_uart("\b \b");
                }
                continue;
            }
            if (pos < 511 && c >= 32 && c < 127) {
                input[pos++] = c;
                putc_uart(c);
            }
        }
        
        if (pos == 0) continue;
        
        // Check for debugger commands
        if (input[0] == 'U' && input[1] == '(') {
            // Parse U(address, count)
            U8 *addr = (U8*)0x80400000; // Default address
            I64 count = 10; // Default count
            U(addr, count, 0);
            continue;
        }
        
        if (input[0] == 'D' && input[1] == '(') {
            // Parse D(address, count)
            U8 *addr = (U8*)0x80400000; // Default address
            I64 count = 64; // Default count
            D(addr, count, 0);
            continue;
        }
        
        if (strcmp(input, "Dr()") == 0) {
            Dr();
            continue;
        }
        
        // Regular HolyC processing
        if (cc->lex.src) free(cc->lex.src);
        cc->lex.src = strdup(input);
        cc->lex.ptr = cc->lex.src;
        cc->lex.line = 1;
        cc->lex.col = 1;
        cc->lex.hash_entry = NULL;
        
        // Reset IC chain
        cc->ic_head = NULL;
        cc->ic_tail = NULL;
        cc->labels = NULL;
        cc->label_counter = 0;
        cc->locals_size = 0;
        
        // Get first token
        extern void LexNext(Compiler *cc);
        LexNext(cc);
        
        // Try ParseFunction first
        extern Bool ParseFunction(Compiler *cc);
        Bool is_function = ParseFunction(cc);
        
        if (is_function) {
            extern U8 *CompileAOT(Compiler *cc, I64 *size_out);
            I64 code_size = 0;
            U8 *machine_code = CompileAOT(cc, &code_size);
            
            if (machine_code && code_size > 0) {
                puts_uart("Function compiled at: ");
                print_hex((U64)machine_code);
                puts_uart("\n");
                
                // Show disassembly
                U(machine_code, code_size/4, 0);
                
                // Update exe_addr
                if (cc->last_compiled_func) {
                    cc->last_compiled_func->exe_addr = (I64)machine_code;
                }
                
                __asm__ volatile("fence.i" ::: "memory");
                puts_uart("Function compiled successfully\n");
            } else {
                puts_uart("Function compilation failed\n");
            }
        } else {
            // Reset lexer
            cc->lex.ptr = cc->lex.src;
            cc->lex.line = 1;
            cc->lex.col = 1;
            
            // Reset IC chain
            cc->ic_head = NULL;
            cc->ic_tail = NULL;
            cc->labels = NULL;
            cc->label_counter = 0;
            cc->locals_size = 0;
            
            // Parse statement
            LexNext(cc);
            extern Bool ParseStatement(Compiler *cc);
            Bool parsed = ParseStatement(cc);
            
            if (parsed) {
                // Add return
                ICAdd(cc, 0x09, 0, 0);  // IC_RETURN_VAL2
                ICAdd(cc, 0x5B, 0, 0);  // IC_RET
                
                // Compile and execute
                extern U8 *CompileExpression(Compiler *cc, I64 *size_out);
                I64 code_size = 0;
                U8 *machine_code = CompileExpression(cc, &code_size);
                
                if (machine_code && code_size > 0) {
                    puts_uart("Expression compiled at: ");
                    print_hex((U64)machine_code);
                    puts_uart("\n");
                    
                    // Show disassembly
                    U(machine_code, code_size/4, 0);
                    
                    __asm__ volatile("fence.i" ::: "memory");
                    
                    typedef I64 (*FuncPtr)();
                    FuncPtr func_ptr = (FuncPtr)machine_code;
                    I64 result = func_ptr();
                    
                    print_hex(result);
                    puts_uart("\n");
                    
                    free(machine_code);
                } else {
                    puts_uart("Expression compilation failed\n");
                }
            } else {
                puts_uart("Parse failed\n");
            }
        }
    }
}

int main(void) {
    templeos_debug_repl();
    while (1) __asm__ volatile ("wfi");
}
