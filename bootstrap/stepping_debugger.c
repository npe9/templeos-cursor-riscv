// TempleOS RISC-V Debugger with Stepping - Single-step execution
// Based on TempleOS Debugger.HC with RISC-V stepping support

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
        puts_uart("[FATAL] Out of heap memory!\n");
        return NULL;  // Don't wrap - return NULL instead
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
    U32 imm : 12;
} IType;

typedef struct {
    U32 opcode : 7;
    U32 imm_4_0 : 5;
    U32 funct3 : 3;
    U32 rs1 : 5;
    U32 rs2 : 5;
    U32 imm_11_5 : 7;
} SType;

typedef struct {
    U32 opcode : 7;
    U32 imm_11 : 1;
    U32 imm_4_1 : 4;
    U32 funct3 : 3;
    U32 rs1 : 5;
    U32 rs2 : 5;
    U32 imm_10_5 : 6;
    U32 imm_12 : 1;
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

// Debugger state
typedef struct {
    U8 *code_start;
    U8 *code_end;
    U8 *current_pc;
    U64 registers[32];
    U64 stack_pointer;
    U64 return_address;
    int step_mode;
    int breakpoint_set;
    U8 *breakpoint_addr;
} DebuggerState;

static DebuggerState debug_state = {0};

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

// Simple string formatting for UART
static int format_hex(char* buf, int pos, U64 val, int digits) {
    for (int i = digits - 1; i >= 0; i--) {
        int d = (val >> (i*4)) & 0xF;
        buf[pos++] = (d < 10) ? '0' + d : 'a' + d - 10;
    }
    return pos;
}

static int format_reg(char* buf, int pos, int reg) {
    const char* name = reg_names[reg];
    while (*name) {
        buf[pos++] = *name++;
    }
    return pos;
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
    int pos = 0;
    
    switch (r->opcode) {
        case 0x37: // LUI
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            buf[pos++] = 'l'; buf[pos++] = 'u'; buf[pos++] = 'i';
            buf[pos++] = ' '; // Add space after lui
            while (pos < 12) buf[pos++] = ' ';
            pos = format_reg(buf, pos, r->rd);
            buf[pos++] = ','; buf[pos++] = '0'; buf[pos++] = 'x';
            pos = format_hex(buf, pos, u->imm_31_12 << 12, 8);
            buf[pos] = '\0';
            break;
            
        case 0x17: // AUIPC
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            buf[pos++] = 'a'; buf[pos++] = 'u'; buf[pos++] = 'i';
            buf[pos++] = 'p'; buf[pos++] = 'c';
            buf[pos++] = ' '; // Add space after auipc
            while (pos < 12) buf[pos++] = ' ';
            pos = format_reg(buf, pos, r->rd);
            buf[pos++] = ','; buf[pos++] = '0'; buf[pos++] = 'x';
            pos = format_hex(buf, pos, u->imm_31_12 << 12, 8);
            buf[pos] = '\0';
            break;
            
        case 0x6F: // JAL
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            buf[pos++] = 'j'; buf[pos++] = 'a'; buf[pos++] = 'l';
            while (pos < 12) buf[pos++] = ' ';
            pos = format_reg(buf, pos, r->rd);
            buf[pos++] = ','; buf[pos++] = '0'; buf[pos++] = 'x';
            imm = sign_extend_21((j->imm_20 << 20) | (j->imm_19_12 << 12) | (j->imm_11 << 11) | (j->imm_10_1 << 1));
            pos = format_hex(buf, pos, (U64)(rip + imm), 16);
            buf[pos] = '\0';
            break;
            
        case 0x67: // JALR
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            buf[pos++] = 'j'; buf[pos++] = 'a'; buf[pos++] = 'l'; buf[pos++] = 'r';
            buf[pos++] = ' ';
            while (pos < 12) buf[pos++] = ' ';
            pos = format_reg(buf, pos, i->rd);
            buf[pos++] = ',';
            imm = sign_extend_12(i->imm);
            if (imm < 0) {
                buf[pos++] = '-';
                imm = -imm;
            }
            buf[pos++] = '0';
            buf[pos++] = 'x';
            if (imm == 0) {
                buf[pos++] = '0';
            } else {
                pos = format_hex(buf, pos, imm, 1);
            }
            buf[pos++] = '(';
            pos = format_reg(buf, pos, i->rs1);
            buf[pos++] = ')';
            buf[pos] = '\0';
            break;
            
        case 0x63: // Branch
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            switch (b->funct3) {
                case 0: buf[pos++] = 'b'; buf[pos++] = 'e'; buf[pos++] = 'q'; break;
                case 1: buf[pos++] = 'b'; buf[pos++] = 'n'; buf[pos++] = 'e'; break;
                case 4: buf[pos++] = 'b'; buf[pos++] = 'l'; buf[pos++] = 't'; break;
                case 5: buf[pos++] = 'b'; buf[pos++] = 'g'; buf[pos++] = 'e'; break;
                case 6: buf[pos++] = 'b'; buf[pos++] = 'l'; buf[pos++] = 't'; buf[pos++] = 'u'; break;
                case 7: buf[pos++] = 'b'; buf[pos++] = 'g'; buf[pos++] = 'e'; buf[pos++] = 'u'; break;
                default: buf[pos++] = 'b'; buf[pos++] = '?'; buf[pos++] = '?'; break;
            }
            while (pos < 12) buf[pos++] = ' ';
            pos = format_reg(buf, pos, b->rs1);
            buf[pos++] = ',';
            pos = format_reg(buf, pos, b->rs2);
            buf[pos++] = ',';
            buf[pos++] = '0'; buf[pos++] = 'x';
            imm = sign_extend_13((b->imm_12 << 12) | (b->imm_11 << 11) | (b->imm_10_5 << 5) | (b->imm_4_1 << 1));
            format_hex(buf, pos, (U64)(rip + imm), 16);
            pos += 16;
            buf[pos] = '\0';
            break;
            
        case 0x03: // Load
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            switch (i->funct3) {
                case 0: buf[pos++] = 'l'; buf[pos++] = 'b'; break;
                case 1: buf[pos++] = 'l'; buf[pos++] = 'h'; break;
                case 2: buf[pos++] = 'l'; buf[pos++] = 'w'; break;
                case 3: buf[pos++] = 'l'; buf[pos++] = 'd'; break;
                case 4: buf[pos++] = 'l'; buf[pos++] = 'b'; buf[pos++] = 'u'; break;
                case 5: buf[pos++] = 'l'; buf[pos++] = 'h'; buf[pos++] = 'u'; break;
                case 6: buf[pos++] = 'l'; buf[pos++] = 'w'; buf[pos++] = 'u'; break;
                default: buf[pos++] = 'l'; buf[pos++] = '?'; break;
            }
            while (pos < 12) buf[pos++] = ' ';
            pos = format_reg(buf, pos, r->rd);
            buf[pos++] = ',';
            imm = sign_extend_12(i->imm);
            if (imm < 0) {
                buf[pos++] = '-';
                imm = -imm;
            }
            buf[pos++] = '0'; buf[pos++] = 'x';
            pos = format_hex(buf, pos, imm, 3);
            buf[pos++] = '(';
            pos = format_reg(buf, pos, i->rs1);
            buf[pos++] = ')';
            buf[pos] = '\0';
            break;
            
        case 0x23: // Store
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            switch (s->funct3) {
                case 0: buf[pos++] = 's'; buf[pos++] = 'd'; break;
                case 1: buf[pos++] = 's'; buf[pos++] = 'h'; break;
                case 2: buf[pos++] = 's'; buf[pos++] = 'w'; break;
                case 3: buf[pos++] = 's'; buf[pos++] = 'd'; break;
                default: buf[pos++] = 's'; buf[pos++] = '?'; break;
            }
            while (pos < 12) buf[pos++] = ' ';
            pos = format_reg(buf, pos, s->rs2);
            buf[pos++] = ',';
            // Extract 12-bit immediate from S-type instruction using struct fields
            U32 imm_s = (s->imm_11_5 << 5) | s->imm_4_0;
            imm = sign_extend_12(imm_s);
            if (imm < 0) {
                buf[pos++] = '-';
                imm = -imm;
            }
            buf[pos++] = '0';
            buf[pos++] = 'x';
            if (imm == 0) {
                buf[pos++] = '0';
            } else {
                pos = format_hex(buf, pos, imm, 3);
            }
            buf[pos++] = '(';
            pos = format_reg(buf, pos, s->rs1);
            buf[pos++] = ')';
            buf[pos] = '\0';
            break;
            
        case 0x13: // Immediate
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            switch (i->funct3) {
                case 0: buf[pos++] = 'a'; buf[pos++] = 'd'; buf[pos++] = 'd'; buf[pos++] = 'i'; buf[pos++] = ' '; break;
                case 1: buf[pos++] = 's'; buf[pos++] = 'l'; buf[pos++] = 'l'; buf[pos++] = 'i'; buf[pos++] = ' '; break;
                case 2: buf[pos++] = 's'; buf[pos++] = 'l'; buf[pos++] = 't'; buf[pos++] = 'i'; buf[pos++] = ' '; break;
                case 3: buf[pos++] = 's'; buf[pos++] = 'l'; buf[pos++] = 't'; buf[pos++] = 'i'; buf[pos++] = 'u'; buf[pos++] = ' '; break;
                case 4: buf[pos++] = 'x'; buf[pos++] = 'o'; buf[pos++] = 'r'; buf[pos++] = 'i'; buf[pos++] = ' '; break;
                case 5: 
                    if (i->imm & 0x400) { buf[pos++] = 's'; buf[pos++] = 'r'; buf[pos++] = 'a'; buf[pos++] = 'i'; buf[pos++] = ' '; }
                    else { buf[pos++] = 's'; buf[pos++] = 'r'; buf[pos++] = 'l'; buf[pos++] = 'i'; buf[pos++] = ' '; }
                    break;
                case 6: buf[pos++] = 'o'; buf[pos++] = 'r'; buf[pos++] = 'i'; buf[pos++] = ' '; break;
                case 7: buf[pos++] = 'a'; buf[pos++] = 'n'; buf[pos++] = 'd'; buf[pos++] = 'i'; buf[pos++] = ' '; break;
                default: buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = 'i'; break;
            }
            while (pos < 12) buf[pos++] = ' ';
            pos = format_reg(buf, pos, i->rd);
            buf[pos++] = ',';
            pos = format_reg(buf, pos, i->rs1);
            buf[pos++] = ',';
            // Extract 12-bit immediate from I-type instruction
            U32 imm_i = (inst >> 20) & 0xFFF;
            imm = sign_extend_12(imm_i);
            
            
            if (imm < 0) {
                buf[pos++] = '-';
                imm = -imm;
            }
            buf[pos++] = '0';
            buf[pos++] = 'x';
            if (imm == 0) {
                buf[pos++] = '0';
            } else {
                pos = format_hex(buf, pos, imm, 3); // Use 3 digits for immediate values
            }
            buf[pos] = '\0';
            break;
            
        case 0x33: // Register
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            switch (r->funct3) {
                case 0:
                    if (r->funct7 == 0) { buf[pos++] = 'a'; buf[pos++] = 'd'; buf[pos++] = 'd'; }
                    else if (r->funct7 == 32) { buf[pos++] = 's'; buf[pos++] = 'u'; buf[pos++] = 'b'; }
                    else if (r->funct7 == 1) { buf[pos++] = 'm'; buf[pos++] = 'u'; buf[pos++] = 'l'; }
                    else { buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; }
                    break;
                case 1:
                    if (r->funct7 == 0) { buf[pos++] = 's'; buf[pos++] = 'l'; buf[pos++] = 'l'; }
                    else if (r->funct7 == 1) { buf[pos++] = 'm'; buf[pos++] = 'u'; buf[pos++] = 'l'; buf[pos++] = 'h'; }
                    else { buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; }
                    break;
                case 2:
                    if (r->funct7 == 0) { buf[pos++] = 's'; buf[pos++] = 'l'; buf[pos++] = 't'; }
                    else if (r->funct7 == 1) { buf[pos++] = 'm'; buf[pos++] = 'u'; buf[pos++] = 'l'; buf[pos++] = 'h'; buf[pos++] = 's'; buf[pos++] = 'u'; }
                    else { buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; }
                    break;
                case 3:
                    if (r->funct7 == 0) { buf[pos++] = 's'; buf[pos++] = 'l'; buf[pos++] = 't'; buf[pos++] = 'u'; }
                    else if (r->funct7 == 1) { buf[pos++] = 'm'; buf[pos++] = 'u'; buf[pos++] = 'l'; buf[pos++] = 'h'; buf[pos++] = 'u'; }
                    else { buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; }
                    break;
                case 4:
                    if (r->funct7 == 0) { buf[pos++] = 'x'; buf[pos++] = 'o'; buf[pos++] = 'r'; }
                    else if (r->funct7 == 1) { buf[pos++] = 'd'; buf[pos++] = 'i'; buf[pos++] = 'v'; }
                    else { buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; }
                    break;
                case 5:
                    if (r->funct7 == 0) { buf[pos++] = 's'; buf[pos++] = 'r'; buf[pos++] = 'l'; }
                    else if (r->funct7 == 32) { buf[pos++] = 's'; buf[pos++] = 'r'; buf[pos++] = 'a'; }
                    else if (r->funct7 == 1) { buf[pos++] = 'd'; buf[pos++] = 'i'; buf[pos++] = 'v'; buf[pos++] = 'u'; }
                    else { buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; }
                    break;
                case 6:
                    if (r->funct7 == 0) { buf[pos++] = 'o'; buf[pos++] = 'r'; }
                    else if (r->funct7 == 1) { buf[pos++] = 'r'; buf[pos++] = 'e'; buf[pos++] = 'm'; }
                    else { buf[pos++] = '?'; buf[pos++] = '?'; }
                    break;
                case 7:
                    if (r->funct7 == 0) { buf[pos++] = 'a'; buf[pos++] = 'n'; buf[pos++] = 'd'; }
                    else if (r->funct7 == 1) { buf[pos++] = 'r'; buf[pos++] = 'e'; buf[pos++] = 'm'; buf[pos++] = 'u'; }
                    else { buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; }
                    break;
                default: buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; break;
            }
            while (pos < 12) buf[pos++] = ' ';
            pos = format_reg(buf, pos, r->rd);
            buf[pos++] = ',';
            pos = format_reg(buf, pos, r->rs1);
            buf[pos++] = ',';
            pos = format_reg(buf, pos, r->rs2);
            buf[pos] = '\0';
            break;
            
        case 0x0F: // Fence
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            if (r->funct3 == 0) {
                buf[pos++] = 'f'; buf[pos++] = 'e'; buf[pos++] = 'n'; buf[pos++] = 'c'; buf[pos++] = 'e';
            } else if (r->funct3 == 1) {
                buf[pos++] = 'f'; buf[pos++] = 'e'; buf[pos++] = 'n'; buf[pos++] = 'c'; buf[pos++] = 'e'; buf[pos++] = '.'; buf[pos++] = 'i';
            } else {
                buf[pos++] = 'f'; buf[pos++] = 'e'; buf[pos++] = 'n'; buf[pos++] = 'c'; buf[pos++] = 'e'; buf[pos++] = '?';
            }
            buf[pos] = '\0';
            break;
            
        case 0x73: // System
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            if (r->funct3 == 0) {
                if (r->funct7 == 0) { buf[pos++] = 'e'; buf[pos++] = 'c'; buf[pos++] = 'a'; buf[pos++] = 'l'; buf[pos++] = 'l'; }
                else if (r->funct7 == 8) { buf[pos++] = 'e'; buf[pos++] = 'b'; buf[pos++] = 'r'; buf[pos++] = 'e'; buf[pos++] = 'a'; buf[pos++] = 'k'; }
                else { buf[pos++] = 'e'; buf[pos++] = 'c'; buf[pos++] = 'a'; buf[pos++] = 'l'; buf[pos++] = 'l'; buf[pos++] = '?'; }
            } else {
                buf[pos++] = 'e'; buf[pos++] = 'c'; buf[pos++] = 'a'; buf[pos++] = 'l'; buf[pos++] = 'l'; buf[pos++] = '?';
            }
            buf[pos] = '\0';
            break;
            
        default:
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            buf[pos++] = 'u'; buf[pos++] = 'n'; buf[pos++] = 'k'; buf[pos++] = 'n'; buf[pos++] = 'o'; buf[pos++] = 'w'; buf[pos++] = 'n';
            buf[pos++] = ' ';
            buf[pos++] = '0'; buf[pos++] = 'x';
            format_hex(buf, pos, inst, 8);
            pos += 8;
            buf[pos] = '\0';
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
        U32 inst = *(U32*)rip;
        print_hex((U64)rip);
        puts_uart(": ");
        print_hex((U64)inst);
        puts_uart(" ");
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
    for (int i = 0; i < 32; i++) {
        puts_uart("  ");
        puts_uart(reg_names[i]);
        puts_uart(": 0x");
        print_hex(debug_state.registers[i]);
        puts_uart("\n");
    }
}

// Step execution - execute one instruction
static int step_instruction(void) {
    if (debug_state.current_pc >= debug_state.code_end) {
        puts_uart("End of code reached\n");
        return 0;
    }
    
    char buf[256];
    U8* next_pc = disasm_instruction(debug_state.current_pc, buf, sizeof(buf));
    
    // Show current instruction
    print_hex((U64)debug_state.current_pc);
    puts_uart(": ");
    puts_uart(buf);
    puts_uart("\n");
    
    // Simple instruction execution simulation
    U32 inst = *(U32*)debug_state.current_pc;
    RType* r = (RType*)&inst;
    IType* i = (IType*)&inst;
    UType* u = (UType*)&inst;
    JType* j = (JType*)&inst;
    
    // Simulate basic instruction effects
    switch (r->opcode) {
        case 0x13: // ADDI
            if (i->rd != 0) { // Don't write to zero register
                I64 imm = sign_extend_12(i->imm);
                debug_state.registers[i->rd] = debug_state.registers[i->rs1] + imm;
            }
            break;
        case 0x37: // LUI
            if (r->rd != 0) {
                debug_state.registers[r->rd] = (U64)(u->imm_31_12 << 12);
            }
            break;
        case 0x6F: // JAL
            if (r->rd != 0) {
                debug_state.registers[r->rd] = (U64)(debug_state.current_pc + 4);
            }
            {
                I64 imm = sign_extend_21((j->imm_20 << 20) | (j->imm_19_12 << 12) | (j->imm_11 << 11) | (j->imm_10_1 << 1));
                debug_state.current_pc = debug_state.current_pc + imm;
                return 1; // Jump taken
            }
        case 0x67: // JALR
            if (r->rd != 0) {
                debug_state.registers[r->rd] = (U64)(debug_state.current_pc + 4);
            }
            {
                I64 imm = sign_extend_12(i->imm);
                debug_state.current_pc = (U8*)(debug_state.registers[i->rs1] + imm);
                return 1; // Jump taken
            }
        case 0x73: // ECALL/EBREAK
            if (r->funct7 == 8) { // EBREAK
                puts_uart("Breakpoint hit!\n");
                return 0;
            }
            break;
    }
    
    // Normal instruction - advance PC
    debug_state.current_pc = next_pc;
    return 1;
}

// Stepping debugger commands
static void step_commands(const char* input) {
    if (strcmp(input, "s") == 0 || strcmp(input, "step") == 0) {
        if (debug_state.step_mode) {
            if (step_instruction()) {
                puts_uart("Step completed\n");
            } else {
                puts_uart("Step failed or breakpoint hit\n");
                debug_state.step_mode = 0;
            }
        } else {
            puts_uart("Not in step mode. Use 'start' to begin stepping.\n");
        }
    } else if (strcmp(input, "start") == 0) {
        if (debug_state.code_start) {
            debug_state.current_pc = debug_state.code_start;
            debug_state.step_mode = 1;
            puts_uart("Started stepping mode\n");
            puts_uart("Use 's' or 'step' to step through instructions\n");
            puts_uart("Use 'run' to execute until breakpoint\n");
            puts_uart("Use 'stop' to exit step mode\n");
        } else {
            puts_uart("No code loaded. Compile a function first.\n");
        }
    } else if (strcmp(input, "run") == 0) {
        if (debug_state.step_mode) {
            puts_uart("Running until breakpoint or end...\n");
            while (step_instruction()) {
                // Continue stepping
            }
            debug_state.step_mode = 0;
        } else {
            puts_uart("Not in step mode. Use 'start' to begin stepping.\n");
        }
    } else if (strcmp(input, "stop") == 0) {
        debug_state.step_mode = 0;
        puts_uart("Stopped stepping mode\n");
    } else if (strcmp(input, "pc") == 0) {
        puts_uart("PC: 0x");
        print_hex((U64)debug_state.current_pc);
        puts_uart("\n");
    } else if (strcmp(input, "break") == 0) {
        if (debug_state.current_pc) {
            debug_state.breakpoint_set = 1;
            debug_state.breakpoint_addr = debug_state.current_pc;
            puts_uart("Breakpoint set at 0x");
            print_hex((U64)debug_state.current_pc);
            puts_uart("\n");
        } else {
            puts_uart("No current PC. Set breakpoint with 'break <addr>'\n");
        }
    } else if (strcmp(input, "clear") == 0) {
        debug_state.breakpoint_set = 0;
        debug_state.breakpoint_addr = NULL;
        puts_uart("Breakpoint cleared\n");
    } else if (strcmp(input, "help") == 0) {
        puts_uart("Stepping Debugger Commands:\n");
        puts_uart("  start     - Start stepping mode\n");
        puts_uart("  s/step    - Step one instruction\n");
        puts_uart("  run       - Run until breakpoint\n");
        puts_uart("  stop      - Stop stepping mode\n");
        puts_uart("  pc        - Show current PC\n");
        puts_uart("  break     - Set breakpoint at current PC\n");
        puts_uart("  clear     - Clear breakpoint\n");
        puts_uart("  Dr()      - Show registers\n");
        puts_uart("  U(addr,n) - Disassemble n instructions\n");
        puts_uart("  D(addr,n) - Dump n bytes of memory\n");
    }
}

// Stepping debugger REPL
void stepping_debug_repl(void) {
    char input[512];
    int pos;
    char c;
    
    puts_uart("TempleOS RISC-V Stepping Debugger\n");
    puts_uart("Commands: start, s/step, run, stop, pc, break, clear, help\n");
    puts_uart("Debugger: U(addr,count) D(addr,count) Dr()\n");
    
    // Create compiler
    Compiler *cc = CompilerNew("", "stepping_debugger");
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
        
        // Check for stepping commands
        if (strcmp(input, "s") == 0 || strcmp(input, "step") == 0 ||
            strcmp(input, "start") == 0 || strcmp(input, "run") == 0 ||
            strcmp(input, "stop") == 0 || strcmp(input, "pc") == 0 ||
            strcmp(input, "break") == 0 || strcmp(input, "clear") == 0 ||
            strcmp(input, "help") == 0) {
            step_commands(input);
            continue;
        }
        
        // Check for debugger commands
        if (input[0] == 'U' && input[1] == '(') {
            U8 *addr = (U8*)0x80400000;
            I64 count = 10;
            U(addr, count, 0);
            continue;
        }
        
        if (input[0] == 'D' && input[1] == '(') {
            U8 *addr = (U8*)0x80400000;
            I64 count = 64;
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
        
        // Debug: Check if hash table has entries
        if (cc->hash_table && cc->hash_table->body) {
            puts_uart("[DEBUG] Hash table exists, checking for TestFunc\n");
            CHashEntry *test_entry = HashFind("TestFunc", cc->hash_table, HTT_FUN);
            if (test_entry && (test_entry->type & HTT_FUN)) {
                CHashFun *test_func = (CHashFun*)test_entry;
                puts_uart("[DEBUG] TestFunc found in hash table!\n");
                puts_uart("[DEBUG] exe_addr field address: 0x");
                print_hex((U64)&test_func->exe_addr);
                puts_uart("\n[DEBUG] exe_addr value: 0x");
                print_hex((U64)test_func->exe_addr);
                puts_uart("\n");
            } else {
                puts_uart("[DEBUG] TestFunc NOT found in hash table\n");
            }
        }
        
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
                
                // Set up for stepping
                debug_state.code_start = machine_code;
                debug_state.code_end = machine_code + code_size;
                debug_state.current_pc = machine_code;
                
                // Show disassembly
                U(machine_code, code_size/4, 0);
                
                // Update exe_addr
                if (cc->last_compiled_func) {
                    cc->last_compiled_func->exe_addr = (I64)machine_code;
                    // Debug: print the function address
                    puts_uart("Function address stored: 0x");
                    print_hex((U64)machine_code);
                    puts_uart("\n");
                    puts_uart("Hash table entry address: 0x");
                    print_hex((U64)cc->last_compiled_func);
                    puts_uart("\n");
                    puts_uart("exe_addr field address: 0x");
                    print_hex((U64)&cc->last_compiled_func->exe_addr);
                    puts_uart("\n");
                    // Verify the value was written
                    puts_uart("exe_addr value after write: 0x");
                    print_hex((U64)cc->last_compiled_func->exe_addr);
                    puts_uart("\n");
                    // Check what's actually in memory at that address
                    puts_uart("Memory at exe_addr field: 0x");
                    print_hex(*(U64*)&cc->last_compiled_func->exe_addr);
                    puts_uart("\n");
                }
                
                // __asm__ volatile("fence.i" ::: "memory"); // Not supported in this RISC-V implementation
                // Use fence instruction to ensure memory writes are visible
                __asm__ volatile("fence rw,rw" ::: "memory");
                puts_uart("Function compiled successfully\n");
                puts_uart("Use 'start' to begin stepping through this function\n");
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
                    
                    // Set up for stepping
                    debug_state.code_start = machine_code;
                    debug_state.code_end = machine_code + code_size;
                    debug_state.current_pc = machine_code;
                    
                    // Show disassembly
                    U(machine_code, code_size/4, 0);
                    
                    // __asm__ volatile("fence.i" ::: "memory"); // Not supported in this RISC-V implementation
                    // Ensure all memory writes are visible before execution
                    __asm__ volatile("fence rw,rw" ::: "memory");
                    
                    // Debug: Check hash table one more time before execution
                    CHashEntry *final_check = HashFind("Answer", cc->hash_table, HTT_FUN);
                    if (final_check && (final_check->type & HTT_FUN)) {
                        CHashFun *final_func = (CHashFun*)final_check;
                        puts_uart("[FINAL CHECK] exe_addr before execution: 0x");
                        print_hex((U64)final_func->exe_addr);
                        puts_uart("\n");
                        puts_uart("[FINAL CHECK] Memory at 0x80412700: 0x");
                        print_hex(*(U64*)0x80412700);
                        puts_uart("\n");
                    }
                    
                    // Execute normally for now
                    typedef I64 (*FuncPtr)();
                    FuncPtr func_ptr = (FuncPtr)machine_code;
                    I64 result = func_ptr();
                    
                    print_hex(result);
                    puts_uart("\n");
                    
                    puts_uart("Use 'start' to begin stepping through this expression\n");
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
    stepping_debug_repl();
    while (1) __asm__ volatile ("wfi");
}
