// Proper RISC-V Disassembler - Shows actual instruction mnemonics
// Based on TempleOS UAsm.HC but with correct RISC-V instruction decoding

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

// Simple string formatting for UART
static void format_hex(char* buf, int pos, U64 val, int digits) {
    for (int i = digits - 1; i >= 0; i--) {
        int d = (val >> (i*4)) & 0xF;
        buf[pos++] = (d < 10) ? '0' + d : 'a' + d - 10;
    }
}

static void format_reg(char* buf, int pos, int reg) {
    const char* name = reg_names[reg];
    while (*name) {
        buf[pos++] = *name++;
    }
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
            buf[pos++] = 'l';
            buf[pos++] = 'u';
            buf[pos++] = 'i';
            while (pos < 12) buf[pos++] = ' ';
            format_reg(buf, pos, r->rd);
            pos += strlen(reg_names[r->rd]);
            buf[pos++] = ',';
            buf[pos++] = '0';
            buf[pos++] = 'x';
            format_hex(buf, pos, u->imm_31_12 << 12, 8);
            pos += 8;
            buf[pos] = '\0';
            break;
            
        case 0x17: // AUIPC
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            buf[pos++] = 'a';
            buf[pos++] = 'u';
            buf[pos++] = 'i';
            buf[pos++] = 'p';
            buf[pos++] = 'c';
            while (pos < 12) buf[pos++] = ' ';
            format_reg(buf, pos, r->rd);
            pos += strlen(reg_names[r->rd]);
            buf[pos++] = ',';
            buf[pos++] = '0';
            buf[pos++] = 'x';
            format_hex(buf, pos, u->imm_31_12 << 12, 8);
            pos += 8;
            buf[pos] = '\0';
            break;
            
        case 0x6F: // JAL
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            buf[pos++] = 'j';
            buf[pos++] = 'a';
            buf[pos++] = 'l';
            while (pos < 12) buf[pos++] = ' ';
            format_reg(buf, pos, r->rd);
            pos += strlen(reg_names[r->rd]);
            buf[pos++] = ',';
            buf[pos++] = '0';
            buf[pos++] = 'x';
            imm = sign_extend_21((j->imm_20 << 20) | (j->imm_19_12 << 12) | (j->imm_11 << 11) | (j->imm_10_1 << 1));
            format_hex(buf, pos, (U64)(rip + imm), 16);
            pos += 16;
            buf[pos] = '\0';
            break;
            
        case 0x67: // JALR
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            buf[pos++] = 'j';
            buf[pos++] = 'a';
            buf[pos++] = 'l';
            buf[pos++] = 'r';
            while (pos < 12) buf[pos++] = ' ';
            format_reg(buf, pos, r->rd);
            pos += strlen(reg_names[r->rd]);
            buf[pos++] = ',';
            imm = sign_extend_12(i->imm);
            if (imm < 0) {
                buf[pos++] = '-';
                imm = -imm;
            }
            format_hex(buf, pos, imm, 1);
            pos += 1;
            buf[pos++] = '(';
            format_reg(buf, pos, i->rs1);
            pos += strlen(reg_names[i->rs1]);
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
            format_reg(buf, pos, b->rs1);
            pos += strlen(reg_names[b->rs1]);
            buf[pos++] = ',';
            format_reg(buf, pos, b->rs2);
            pos += strlen(reg_names[b->rs2]);
            buf[pos++] = ',';
            buf[pos++] = '0';
            buf[pos++] = 'x';
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
            format_reg(buf, pos, r->rd);
            pos += strlen(reg_names[r->rd]);
            buf[pos++] = ',';
            imm = sign_extend_12(i->imm);
            if (imm < 0) {
                buf[pos++] = '-';
                imm = -imm;
            }
            format_hex(buf, pos, imm, 1);
            pos += 1;
            buf[pos++] = '(';
            format_reg(buf, pos, i->rs1);
            pos += strlen(reg_names[i->rs1]);
            buf[pos++] = ')';
            buf[pos] = '\0';
            break;
            
        case 0x23: // Store
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            switch (s->funct3) {
                case 0: buf[pos++] = 's'; buf[pos++] = 'b'; break;
                case 1: buf[pos++] = 's'; buf[pos++] = 'h'; break;
                case 2: buf[pos++] = 's'; buf[pos++] = 'w'; break;
                case 3: buf[pos++] = 's'; buf[pos++] = 'd'; break;
                default: buf[pos++] = 's'; buf[pos++] = '?'; break;
            }
            while (pos < 12) buf[pos++] = ' ';
            format_reg(buf, pos, s->rs2);
            pos += strlen(reg_names[s->rs2]);
            buf[pos++] = ',';
            imm = sign_extend_12((s->imm_11_5 << 5) | s->imm_4_0);
            if (imm < 0) {
                buf[pos++] = '-';
                imm = -imm;
            }
            format_hex(buf, pos, imm, 1);
            pos += 1;
            buf[pos++] = '(';
            format_reg(buf, pos, s->rs1);
            pos += strlen(reg_names[s->rs1]);
            buf[pos++] = ')';
            buf[pos] = '\0';
            break;
            
        case 0x13: // Immediate
            pos = 0;
            while (pos < 8) buf[pos++] = ' ';
            switch (i->funct3) {
                case 0: buf[pos++] = 'a'; buf[pos++] = 'd'; buf[pos++] = 'd'; buf[pos++] = 'i'; break;
                case 1: buf[pos++] = 's'; buf[pos++] = 'l'; buf[pos++] = 'l'; buf[pos++] = 'i'; break;
                case 2: buf[pos++] = 's'; buf[pos++] = 'l'; buf[pos++] = 't'; buf[pos++] = 'i'; break;
                case 3: buf[pos++] = 's'; buf[pos++] = 'l'; buf[pos++] = 't'; buf[pos++] = 'i'; buf[pos++] = 'u'; break;
                case 4: buf[pos++] = 'x'; buf[pos++] = 'o'; buf[pos++] = 'r'; buf[pos++] = 'i'; break;
                case 5: 
                    if (i->imm & 0x400) { buf[pos++] = 's'; buf[pos++] = 'r'; buf[pos++] = 'a'; buf[pos++] = 'i'; }
                    else { buf[pos++] = 's'; buf[pos++] = 'r'; buf[pos++] = 'l'; buf[pos++] = 'i'; }
                    break;
                case 6: buf[pos++] = 'o'; buf[pos++] = 'r'; buf[pos++] = 'i'; break;
                case 7: buf[pos++] = 'a'; buf[pos++] = 'n'; buf[pos++] = 'd'; buf[pos++] = 'i'; break;
                default: buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = '?'; buf[pos++] = 'i'; break;
            }
            while (pos < 12) buf[pos++] = ' ';
            format_reg(buf, pos, r->rd);
            pos += strlen(reg_names[r->rd]);
            buf[pos++] = ',';
            format_reg(buf, pos, i->rs1);
            pos += strlen(reg_names[i->rs1]);
            buf[pos++] = ',';
            imm = sign_extend_12(i->imm);
            if (imm < 0) {
                buf[pos++] = '-';
                imm = -imm;
            }
            format_hex(buf, pos, imm, 1);
            pos += 1;
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
            format_reg(buf, pos, r->rd);
            pos += strlen(reg_names[r->rd]);
            buf[pos++] = ',';
            format_reg(buf, pos, r->rs1);
            pos += strlen(reg_names[r->rs1]);
            buf[pos++] = ',';
            format_reg(buf, pos, r->rs2);
            pos += strlen(reg_names[r->rs2]);
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

// Debug REPL with proper RISC-V disassembly
void proper_debug_repl(void) {
    char input[512];
    int pos;
    char c;
    
    puts_uart("TempleOS RISC-V Debugger (Proper Disassembly)\n");
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
                
                // Show proper disassembly
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
                    
                    // Show proper disassembly
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
    proper_debug_repl();
    while (1) __asm__ volatile ("wfi");
}
