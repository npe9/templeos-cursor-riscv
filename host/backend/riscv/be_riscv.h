/* host/backend/riscv/be_riscv.h — RISC-V backend internal interface (ISA-SPECIFIC).
 *
 * Declarations shared between the RISC-V backend TU (be_riscv.c) and the parts of the codegen
 * still in host/compiler.c during the M4 extraction. As the move proceeds this grows to cover
 * the instruction encoders, branch/call primitives, prologue/epilogue, and immediate
 * materialization; compiler.c's RISC-V call sites shrink until only the neutral walker remains.
 *
 */
#ifndef HOST_BACKEND_RISCV_BE_RISCV_H
#define HOST_BACKEND_RISCV_BE_RISCV_H
#include "holyc_compiler.h"   /* U8/U32/I64 and the RT_* type enum (resolved via -Ihost) */
#include "regs.h"

/* Per-compile RISC-V doubleword load/store funct3 (3 on rv64 = ld/sd, 2 on rv32 = lw/sw).
 * Defined in host/compiler.c for now; migrates into the Em context at M4d (reentrancy). */
extern int g_wd3;

/* Instruction-field decode predicates/extractors (used by the RISC-V peephole + O1 slots). */
I64 RvImmI(U32 w);                        /* sign-extended I-type immediate                    */
I64 RvImmS(U32 w);                        /* sign-extended S-type immediate                    */
int RvIsAddi(U32 w, int rd, int rs1, int imm); /* is w exactly `addi rd, rs1, imm`?            */
int RvIsSdSp0(U32 w, int *rs2);           /* is w `sd/sw rs2, 0(sp)` (doubleword = g_wd3)?      */
int RvIsMv(U32 w, int *rd, int *rs);      /* is w `mv rd, rs` (addi rd, rs, 0)?                 */

/* Typed load/store + AMO instruction encoders (doubleword width = g_wd3). */
U32 LoadRdFromRs1(U8 pointed_to, U8 rd, U8 rs1);
U32 DerefLoadFromRs1(U8 pointed_to, U8 rs1);
U32 DerefLoadFromRs1Off(U8 p, U8 rs1, I64 off);
U32 StoreRs2ToRs1(U8 pointed_to, U8 rs1, U8 rs2);
U32 StoreA0ToRs1(U8 pointed_to, U8 rs1);
U32 StoreA0ToRs1Off(U8 p, U8 rs1, I64 off);
U32 StoreZeroToRs1(U8 pointed_to, U8 rs1);
U32 RvAmo(U32 f5, U32 aqrl, U32 f3, int rd, int rs1, int rs2);

/* O1 BB-local frame-slot forwarding (g_o1_slot_reg[i] holds the reg for slot i; RVU32 reads it). */
extern int g_o1_slot_reg[32];
void O1SlotClear(void);
int  O1SlotFind(I64 off);
void O1SlotForgetReg(int reg);
void O1SlotSet(I64 off, int reg);

#endif /* HOST_BACKEND_RISCV_BE_RISCV_H */
