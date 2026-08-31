// RISCVRegs.HH -- RV64 register numbers + TempleOS REG_*/REGG_* remaps.
// Include once, AFTER KernelA.HH, BEFORE OptPass3 / Back*_RV in Compiler_RV.PRJ.
// Leaves x86 Compiler.PRJ untouched.

#ifndef RISCV_REGS_HH
#define RISCV_REGS_HH

#ifndef RV_REG_ZERO
#define RV_REG_ZERO  0
#define RV_REG_RA    1
#define RV_REG_SP    2
#define RV_REG_GP    3
#define RV_REG_TP    4
#define RV_REG_T0    5
#define RV_REG_T1    6
#define RV_REG_T2    7
#define RV_REG_S0    8
#define RV_REG_S1    9
#define RV_REG_A0    10
#define RV_REG_A1    11
#define RV_REG_A2    12
#define RV_REG_A3    13
#define RV_REG_A4    14
#define RV_REG_A5    15
#define RV_REG_A6    16
#define RV_REG_A7    17
#define RV_REG_S2    18
#define RV_REG_S3    19
#define RV_REG_S4    20
#define RV_REG_S5    21
#define RV_REG_S6    22
#define RV_REG_S7    23
#define RV_REG_S8    24
#define RV_REG_S9    25
#define RV_REG_S10   26
#define RV_REG_S11   27
#define RV_REG_T3    28
#define RV_REG_T4    29
#define RV_REG_T5    30
#define RV_REG_T6    31
#define RV_REG_FP    RV_REG_S0
#define RV_REG_NONE  0xFF
#endif

#undef REG_RAX
#undef REG_RCX
#undef REG_RDX
#undef REG_RBX
#undef REG_RSP
#undef REG_RBP
#undef REG_RSI
#undef REG_RDI
#undef REG_R8
#undef REG_REGS_NUM
#undef REG_RIP
#undef REG_NONE
#undef REG_ALLOC
#undef REGG_CLOBBERED
#undef REGG_SAVED
#undef REGG_STK_TMP
#undef REGG_LOCAL_VARS
#undef REGG_LOCAL_NON_PTR_VARS

// OptPass3–6 treat REG_RAX as primary result / scratch (x86 heritage).
#define REG_RAX		RV_REG_A0
#define REG_RCX		RV_REG_A1
#define REG_RDX		RV_REG_A2
#define REG_RBX		RV_REG_A3
#define REG_RSP		RV_REG_SP
#define REG_RBP		RV_REG_FP
#define REG_RSI		RV_REG_S1
#define REG_RDI		RV_REG_S2
#define REG_R8		RV_REG_A4
#define REG_REGS_NUM	32
// x86: REG_RIP==REG_REGS_NUM (past real regs). KernelA left REG_RIP=16, which is
// RV a6 — OptPass4 RIP-disp paths must not alias a real allocatable register.
#define REG_RIP		REG_REGS_NUM
#define REG_NONE	(REG_REGS_NUM+16)	// 48; noreg (was 32==REGS_NUM on RV)
#define REG_ALLOC	(REG_REGS_NUM+17)	// 49; "please allocate"

#define REGG_CLOBBERED	((1<<RV_REG_A0)|(1<<RV_REG_A1)|(1<<RV_REG_A2)|(1<<RV_REG_A3)| \
	(1<<RV_REG_A4)|(1<<RV_REG_A5)|(1<<RV_REG_A6)|(1<<RV_REG_A7)| \
	(1<<RV_REG_T0)|(1<<RV_REG_T1)|(1<<RV_REG_T2)|(1<<RV_REG_T3)| \
	(1<<RV_REG_T4)|(1<<RV_REG_T5)|(1<<RV_REG_T6))
#define REGG_SAVED	((1<<RV_REG_FP)|(1<<RV_REG_SP)|(1<<RV_REG_RA)|(1<<RV_REG_S1))
#define REGG_STK_TMP	(1<<RV_REG_T4)
#define REGG_LOCAL_VARS	((1<<RV_REG_S1)|(1<<RV_REG_S2)|(1<<RV_REG_S3)|(1<<RV_REG_S4)| \
	(1<<RV_REG_S5)|(1<<RV_REG_S6)|(1<<RV_REG_S7)|(1<<RV_REG_S8)| \
	(1<<RV_REG_S9)|(1<<RV_REG_S10)|(1<<RV_REG_S11))
#define REGG_LOCAL_NON_PTR_VARS	((1<<RV_REG_S3)|(1<<RV_REG_S4))

#endif
