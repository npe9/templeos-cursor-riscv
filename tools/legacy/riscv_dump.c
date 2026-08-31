// RISC-V Code Dumper - Simple disassembler for debugging
// Compile with: gcc -o riscv_dump riscv_dump.c

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "holy_api.h"

typedef uint64_t U64;
typedef uint32_t U32;
typedef uint8_t U8;

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
static int64_t sign_extend_12(int64_t imm) {
    return (imm & 0x800) ? (imm | 0xFFFFF000) : imm;
}

static int64_t sign_extend_13(int64_t imm) {
    return (imm & 0x1000) ? (imm | 0xFFFFE000) : imm;
}

static int64_t sign_extend_20(int64_t imm) {
    return (imm & 0x80000) ? (imm | 0xFFF00000) : imm;
}

static int64_t sign_extend_21(int64_t imm) {
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
    
    int64_t imm;
    const char* opcode_name = "unknown";
    
    switch (r->opcode) {
        case 0x37: // LUI
            opcode_name = "lui";
            StrPrintF(buf, buf_size, "%-8s %s,0x%x", opcode_name, reg_names[r->rd], u->imm_31_12 << 12);
            break;
            
        case 0x17: // AUIPC
            opcode_name = "auipc";
            StrPrintF(buf, buf_size, "%-8s %s,0x%x", opcode_name, reg_names[r->rd], u->imm_31_12 << 12);
            break;
            
        case 0x6F: // JAL
            opcode_name = "jal";
            imm = sign_extend_21((j->imm_20 << 20) | (j->imm_19_12 << 12) | (j->imm_11 << 11) | (j->imm_10_1 << 1));
            StrPrintF(buf, buf_size, "%-8s %s,0x%lx", opcode_name, reg_names[r->rd], (U64)(rip + imm));
            break;
            
        case 0x67: // JALR
            opcode_name = "jalr";
            imm = sign_extend_12(i->imm);
            StrPrintF(buf, buf_size, "%-8s %s,%ld(%s)", opcode_name, reg_names[r->rd], imm, reg_names[i->rs1]);
            break;
            
        case 0x63: // Branch
            imm = sign_extend_13((b->imm_12 << 12) | (b->imm_11 << 11) | (b->imm_10_5 << 5) | (b->imm_4_1 << 1));
            switch (b->funct3) {
                case 0: opcode_name = "beq"; break;
                case 1: opcode_name = "bne"; break;
                case 4: opcode_name = "blt"; break;
                case 5: opcode_name = "bge"; break;
                case 6: opcode_name = "bltu"; break;
                case 7: opcode_name = "bgeu"; break;
            }
            StrPrintF(buf, buf_size, "%-8s %s,%s,0x%lx", opcode_name, reg_names[b->rs1], reg_names[b->rs2], (U64)(rip + imm));
            break;
            
        case 0x03: // Load
            imm = sign_extend_12(i->imm);
            switch (i->funct3) {
                case 0: opcode_name = "lb"; break;
                case 1: opcode_name = "lh"; break;
                case 2: opcode_name = "lw"; break;
                case 3: opcode_name = "ld"; break;
                case 4: opcode_name = "lbu"; break;
                case 5: opcode_name = "lhu"; break;
                case 6: opcode_name = "lwu"; break;
            }
            StrPrintF(buf, buf_size, "%-8s %s,%ld(%s)", opcode_name, reg_names[r->rd], imm, reg_names[i->rs1]);
            break;
            
        case 0x23: // Store
            imm = sign_extend_12((s->imm_11_5 << 5) | s->imm_4_0);
            switch (s->funct3) {
                case 0: opcode_name = "sb"; break;
                case 1: opcode_name = "sh"; break;
                case 2: opcode_name = "sw"; break;
                case 3: opcode_name = "sd"; break;
            }
            StrPrintF(buf, buf_size, "%-8s %s,%ld(%s)", opcode_name, reg_names[s->rs2], imm, reg_names[s->rs1]);
            break;
            
        case 0x13: // Immediate
            imm = sign_extend_12(i->imm);
            switch (i->funct3) {
                case 0: opcode_name = "addi"; break;
                case 1: opcode_name = "slli"; break;
                case 2: opcode_name = "slti"; break;
                case 3: opcode_name = "sltiu"; break;
                case 4: opcode_name = "xori"; break;
                case 5: 
                    if (i->imm & 0x400) opcode_name = "srai";
                    else opcode_name = "srli";
                    break;
                case 6: opcode_name = "ori"; break;
                case 7: opcode_name = "andi"; break;
            }
            StrPrintF(buf, buf_size, "%-8s %s,%s,%ld", opcode_name, reg_names[r->rd], reg_names[i->rs1], imm);
            break;
            
        case 0x33: // Register
            switch (r->funct3) {
                case 0:
                    if (r->funct7 == 0) opcode_name = "add";
                    else if (r->funct7 == 32) opcode_name = "sub";
                    else if (r->funct7 == 1) opcode_name = "mul";
                    break;
                case 1:
                    if (r->funct7 == 0) opcode_name = "sll";
                    else if (r->funct7 == 1) opcode_name = "mulh";
                    break;
                case 2:
                    if (r->funct7 == 0) opcode_name = "slt";
                    else if (r->funct7 == 1) opcode_name = "mulhsu";
                    break;
                case 3:
                    if (r->funct7 == 0) opcode_name = "sltu";
                    else if (r->funct7 == 1) opcode_name = "mulhu";
                    break;
                case 4:
                    if (r->funct7 == 0) opcode_name = "xor";
                    else if (r->funct7 == 1) opcode_name = "div";
                    break;
                case 5:
                    if (r->funct7 == 0) opcode_name = "srl";
                    else if (r->funct7 == 32) opcode_name = "sra";
                    else if (r->funct7 == 1) opcode_name = "divu";
                    break;
                case 6:
                    if (r->funct7 == 0) opcode_name = "or";
                    else if (r->funct7 == 1) opcode_name = "rem";
                    break;
                case 7:
                    if (r->funct7 == 0) opcode_name = "and";
                    else if (r->funct7 == 1) opcode_name = "remu";
                    break;
            }
            StrPrintF(buf, buf_size, "%-8s %s,%s,%s", opcode_name, reg_names[r->rd], reg_names[r->rs1], reg_names[r->rs2]);
            break;
            
        case 0x0F: // Fence
            if (r->funct3 == 0) {
                opcode_name = "fence";
                StrPrintF(buf, buf_size, "%-8s %s,%s", opcode_name, reg_names[r->rd], reg_names[r->rs1]);
            } else if (r->funct3 == 1) {
                opcode_name = "fence.i";
                StrPrintF(buf, buf_size, "%-8s", opcode_name);
            }
            break;
            
        case 0x73: // System
            if (r->funct3 == 0) {
                if (r->funct7 == 0) opcode_name = "ecall";
                else if (r->funct7 == 8) opcode_name = "ebreak";
            }
            StrPrintF(buf, buf_size, "%-8s", opcode_name);
            break;
            
        default:
            StrPrintF(buf, buf_size, "%-8s 0x%08x", opcode_name, inst);
            break;
    }
    
    return rip + 4;
}

// Disassemble multiple instructions
void U(U8* rip, int cnt) {
    char buf[256];
    int i;
    
    printf("Disassembly:\n");
    for (i = 0; i < cnt; i++) {
        printf("%016lx: ", (U64)rip);
        rip = disasm_instruction(rip, buf, sizeof(buf));
        printf("%s\n", buf);
    }
}

// Dump memory in hex format
void D(U8* addr, int cnt, int show_offset) {
    int i, j;
    U8* ptr = addr;
    
    while (cnt > 0) {
        if (show_offset)
            printf("%08lx ", ptr - addr);
        else
            printf("%016lx ", (U64)ptr);
            
        if (cnt > 16)
            j = 16;
        else
            j = cnt;
            
        for (i = 0; i < j; i++)
            printf("%02x ", ptr[i]);
        for (; i < 16; i++)
            printf("   ");
            
        for (i = 0; i < j; i++) {
            char ch = ptr[i];
            if (ch < 32 || ch == 127)
                ch = '.';
            printf("%c", ch);
        }
        printf("\n");
        
        cnt -= j;
        ptr += j;
    }
}

// Dump memory with addresses
void Dm(U8* addr, int cnt) {
    D(addr, cnt, 0);
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Usage: %s <binary_file> [count]\n", argv[0]);
        return 1;
    }
    
    FILE* file = fopen(argv[1], "rb");
    if (!file) {
        printf("Error: Cannot open file %s\n", argv[1]);
        return 1;
    }
    
    // Read file into memory
    fseek(file, 0, SEEK_END);
    long file_size = ftell(file);
    fseek(file, 0, SEEK_SET);
    
    U8* buffer = malloc(file_size);
    fread(buffer, 1, file_size, file);
    fclose(file);
    
    int count = (argc > 2) ? atoi(argv[2]) : 20;
    
    printf("File: %s\n", argv[1]);
    printf("Size: %ld bytes\n", file_size);
    printf("Count: %d instructions\n\n", count);
    
    // Disassemble
    U(buffer, count);
    
    printf("\nMemory dump:\n");
    Dm(buffer, file_size);
    
    free(buffer);
    return 0;
}
