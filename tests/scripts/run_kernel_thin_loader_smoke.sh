#!/usr/bin/env bash
# Thin loader smoke (G9): embed Kernel.BIN @0x81000000 → export-only LoadBufLite
# → HashAdd → HashFind("KernelEntry") → Call (Jump-hint still planted for SoftCall).
# SoftCall owns virtio remount + FS/Load ENTER + JumpSoft (→'KL') + ExeSoft
# (RedSea Load→HashFind→Call →'KB') + MakeSoft (product Tiny.BIN→MakeOSProbe=42 →'KN')
# + SeedSoft (product Seed.BIN→RuntimeSeedInit=42 →'KR') + SvcSoft (product
# Svc.BIN→RuntimeSvcProbe=42 →'KC') + KernSoft (product Kern.BIN→KernInit=42 →'KK')
# + StartSoft (Seed→Svc→Kern multi-BIN →'KU') + AdamSoft (product StartOS.BIN→
# StartOSProbe=1 →'KA') + DateSoft (KDate+RTC Now →'KG') + QSortSoft (QSortI64 →'KO')
# + KeyDevSoft (PutKey/PutS+CtrlAlt →'KW') + ExceptSoft (SysTry/throw/PutExcept →'KZ')
# + MemSoft (HeapCtrl+MAlloc/Free/MSize →'KH') + StrUtilSoft (StrUtil/MStrUtil →'SU')
# + FifoSoft (FifoU8/I64 ring →'SF') + QueVectSoft (QueVectU8 New/Put/Get →'QV')
# + RandSoft (Seed+LCG RandI64 →'RN') + ScanFlagsSoft (LstMatch+ScanFlags+/- →'SC')
# + CompressSoft (CompressBuf/ExpandBuf →'CM') + KLoadSoft (LoadPass1 import+ABS →'LD')
# + MakeMemSoft (MemPag FREE_PAG=0x100 →'MM') + PhysMemSoft (BlkPoolsInit+MemPageTable+Mem32Dev
# →'PM') + LoadMainSoft (CODE_HEAP+MAIN+FileRead →'LM') + Hash2Soft (free_pag_hash2 stock 55
# SoftCall-lite →'H2') + DataHeapSoft (DATA_HEAP+ZEROED+ExtDft.Z →'DH') + LoadAbsSoft
# (FileNameAbs+module_align →'LA') + DirAbsSoft (DirNameAbs parents+Z+ExtDft →'DN')
# + StartOSSoft (DirAbs+Adam+StartSoft no phase3 Cmp →'SO')
# + ExePutSSoft (CmpCtrl+ExePutS 40+2 →'EP') + CmpSoft (CmpWrite SoftCmp.BIN →'CC')
# + LexStmtSoft (LexStmt2Bin emit+Call 40+2 →'LB') + PrsOptSoft (Prs/Opt emit+Call
# 6*7 / 2+5*8 →'PO') + ParenSoft (paren+IC emit (2+5)*8 →'PN')
# + IdentSoft (local/ident IC x+2 / x+y →'ID')
# + AssignSoft (PrsStmt assign x=40;x+2 →'AS')
# + FunDefSoft (I64 F(){return 40+2;}F() →'FD')
# + FunBodySoft (I64 F(){x=40;return x+2;}F() + I64 arg →'FB')
# + FunCallSoft (I64 F(I64 a,I64 b){return a+b;}F(40,2) + call-Expr →'FC')
# + AbiSoft (I64 F(I64 a){return a+2;}F(40) a0 frame →'AB')
# + CocSoft (I64 F(){x=40;return x+2;}F() COC ASSIGN →'CO')
# + BrSoft (I64 F(){x=0;if(1)x=42;return x;}F() + while →'BR')
# + ElseSoft (I64 F(){x=0;if(1)x=42;else x=0;return x;}F() →'EL')
# + ForSoft (I64 F(){for(x=40;x-42;x=x+1)y=0;return x;}F() →'FR')
# + CmpBrSoft (I64 F(){x=0;if(x<1)x=42;return x;}F() + while/for < →'CB')
# + CmpSrcSoft (Load SoftCmpSrc.BIN SoftCmpSrcProbe multi-fun slice →'CS')
# + PrsSrcSoft (Load SoftPrsSrc.BIN SoftPrsSrcProbe Prs glbl+fold →'PR')
# + LexSrcSoft (Load SoftLexSrc.BIN SoftLexSrcProbe LexStmt2Bin peel →'LX')
# + IcSrcSoft (Load SoftIcSrc.BIN SoftIcSrcProbe IC plant+emit →'IC')
# + MulSrcSoft (Load SoftMulSrc.BIN SoftMulSrcProbe MUL IC emit →'MU')
# + SubSrcSoft (Load SoftSubSrc.BIN SoftSubSrcProbe SUB IC emit →'SB')
# + OptSrcSoft (Load SoftOptSrc.BIN SoftOptSrcProbe OptPass fold →'OP')
# + CocSrcSoft (Load SoftCocSrc.BIN SoftCocSrcProbe COC ASSIGN →'OC')
# + BrSrcSoft (Load SoftBrSrc.BIN SoftBrSrcProbe BR SoftCall Load →'BS')
# + ElseSrcSoft (Load SoftElseSrc.BIN SoftElseSrcProbe if/else JMP →'ES')
# + ForSrcSoft (Load SoftForSrc.BIN SoftForSrcProbe for-loop 40→42 →'FS')
# + CallIcSoft (I64 G(){return 40;}I64 F(){return G()+2;}F() inter-fun jal ra →'CL')
# + GlblMemSoft (I64 g;I64 F(){g=40;return g+2;}F() lui/addi abs + ld/sd →'GM')
# + GuestCmpSoft (RedSea A:/Compiler/SoftGlbl.HC read multi-blk, Cmp'd by the
#   in-BIN lite Prs, Called →42 →'GC'). First real guest Cmp: the source is a
#   Compiler_RV-shaped .HC that lives only on the disk image. Gated three ways —
#   the board prints sz + a rolling *31 sum over the bytes it consumed and both
#   are recomputed here from the seed file, and Kernel.BIN is checked to contain
#   no guest ident (so it cannot be an in-BIN literal).
# + GuestLocalSoft (RedSea A:/Compiler/SoftLocal.HC — same three gates — proving
#   frame locals inside a glbl-fun body: `I64 l;` is an sp slot at 8.. above the
#   saved ra, and a callee's same-named local sits on its own frame →'GL')
# + GuestFlowSoft (RedSea A:/Compiler/SoftFlow.HC — same three gates — proving
#   if / while / for inside that same merged body. The fragment is OptPass_RV
#   shaped: a for sweeping g_rv_opt_ic_n IC slots (5*7=35), a while draining 7
#   down to 1, an if/else classifying the residue, summed to 42 across two jal ra.
#   Branches are proven real by disassembling what the lite Cmp planted — beq is
#   the only opcode-0x63 form it emits and bit 31 is imm[12], so the board counts
#   three beqz a0 conds, two backward beq x0,x0 back edges and one forward join
#   →'GF')
# + GuestPtrSoft (RedSea A:/Compiler/SoftPtr.HC — same three gates — proving the
#   first non-I64 typed values: a `U8 b[N];` file-scope byte buffer whose name
#   decays to an address, a `U8 *p;` cursor, and byte-width `*p` / `*p = Expr`.
#   The fragment is Lex.HC shaped: Seed writes 20,22,0 through the cursor and
#   Walk runs `for (p = buf; *p; p = p + 1) n = n + *p;` back to 42. Byte width
#   is proven by disassembling what the lite Cmp planted — two lbu, three sb and
#   sixteen srli x,x,32 (one per lui/addi/slli/srli absolute-address materialize)
#   →'GP')
# + GuestArgSoft (RedSea A:/Compiler/SoftArg.HC — same three gates — proving fun
#   arguments and calls that pass them: `I64 name(I64 a, I64 b)` spills a0/a1 into
#   its own frame at 8(sp)/16(sp), and a call site hands the arg Exprs over in the
#   real RISC-V argument registers through a real jal ra. The fragment is
#   OptPass_RV shaped: one cost helper called with (2,1) and (8,0), so a fixed-arg
#   or folded callee gives 30 or 38 instead of 34. Register passing is proven by
#   disassembling what the lite Cmp planted — three jal ra, one
#   sd ra/sd a0,8(sp)/sd a1,16(sp) spill prologue and two
#   addi a0/addi a1/jal ra call setups (sequences, because a lone sd shares its
#   encoding with an ordinary frame store) →'GA')
# + GuestTypeSoft (RedSea A:/Compiler/SoftType.HC — same three gates — proving
#   non-I64 return and argument widths plus arity 4. A signature is now
#   RType name(AType a,...,AType d) with RType = I64|U0|Bool|U32|U8 *|C8 *. Widths
#   are the callee's business at both ends: a Bool/U32 arg is narrowed in the
#   prologue before its spill, a Bool/U32 return after the body. U0 has no value at
#   all, so it is reached by a statement call whose IC_CALL_U0 leaves the lite RPN
#   stack empty. The fragment is BackLib_RV shaped: a four-argument U0 field packer
#   whose arg registers each carry a distinct weight, a Bool predicate, a U32
#   straddling bit 31 and 2^32, and a U8 * handing a buffer address back. Widths are
#   proven by disassembling six exact three-word sequences — the Bool and U32 return
#   narrowings in the epilogue, the U0 no-value tail, the a1/a2/a3 spill run, the
#   a2/a3 call setup, and the U32 arg narrowing ahead of its spill (three words each
#   because `sltu a0,x0,a0` is also how `!=` ends and `slli/srli a0,a0,32` is also
#   how an absolute address materialize ends) →'GT')
# then HLT.
# No thin RVThinVirtioBlk/RVRedSeaRaw chicken-egg (RV_THIN_EMBED_BIN).
# RedSea img still attached for SoftCall LoadProbe + MakeOS/Tiny + Runtime/{Seed,Svc,Kern}
# + Adam/StartOS.
# See COMPILER_RV.md § P3.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_thin_loader_demo.hc"
EXPECT_DEFER="RVKMain: thin embed Kernel.BIN; SoftCall owns virtio."
EXPECT_EMBED="RVThinLoader: thin embed+LoadBuf; Kernel.BIN @0x81000000..."
EXPECT_SZ="RVThinLoader: embed OK sz="
EXPECT_FIND="RVThinLoader: embed OK; LoadBuf..."
EXPECT_JUMP="RVThinLoader: LoadBuf OK; Jump KernelEntry via HashFind (non-return)..."
EXPECT_INIT="Kernel.BIN: KernelInitLite (UART+freelist64K+magic)..."
EXPECT_TRAP="Kernel.BIN: InitLite TrapCtx (GPR+IRQ+ecall)..."
EXPECT_HAND="Kernel.BIN: KernelEntry handoff OK (InitLite)."
EXPECT_MOUNT="Kernel.BIN: SoftCall first RVMountVirtioDisk..."
EXPECT_SOFT="Kernel.BIN: SoftCall OK (BIN ENTER+VBlkInit+mount/FS/Call=0x4B53)."
EXPECT_STAY="Kernel.BIN: stay (non-return)."
EXPECT_BLK="Kernel.BIN: SoftCall VirtioBlk Capacity/Read + RedSeaValidate..."
EXPECT_OWN="Kernel.BIN: SoftCall TrapOwn (TrapCtx stay)..."
EXPECT_IRQ="Kernel.BIN: SoftCall TrapIRQ (CLINT MSIP)..."
EXPECT_TIMER="Kernel.BIN: SoftCall TrapTimer (CLINT mtimecmp)..."
EXPECT_DISP="Kernel.BIN: SoftCall TrapDisp (HolyC hook)..."
EXPECT_TASK="Kernel.BIN: SoftCall TaskSoft (Init+Spawn+JobRunOne)..."
EXPECT_HASH="Kernel.BIN: SoftCall HashSoft (TableNew+Add+Find)..."
EXPECT_PRINT="Kernel.BIN: SoftCall PrintSoft (StrPrintJoin %s/%d/%X)..."
EXPECT_YIELD="Kernel.BIN: SoftCall YieldSoft (CtxSw+next_task)..."
EXPECT_JUMP_SOFT="Kernel.BIN: SoftCall JumpSoft (LoadBuf+HashFind Entry/Probe)..."
EXPECT_EXE_SOFT="Kernel.BIN: SoftCall ExeSoft (Load+HashFind LoadProbe)..."
EXPECT_MAKE_SOFT="Kernel.BIN: SoftCall MakeSoft (Load+HashFind MakeOSProbe)..."
EXPECT_SEED_SOFT="Kernel.BIN: SoftCall SeedSoft (Load+HashFind RuntimeSeedInit)..."
EXPECT_SVC_SOFT="Kernel.BIN: SoftCall SvcSoft (Load+HashFind RuntimeSvcProbe)..."
EXPECT_KERN_SOFT="Kernel.BIN: SoftCall KernSoft (Load+HashFind KernInit)..."
EXPECT_START_SOFT="Kernel.BIN: SoftCall StartSoft (Seed→Svc→Kern)..."
EXPECT_ADAM_SOFT="Kernel.BIN: SoftCall AdamSoft (Load+HashFind StartOSProbe)..."
EXPECT_DATE_SOFT="Kernel.BIN: SoftCall DateSoft (KDate+RTC Now)..."
EXPECT_QSORT_SOFT="Kernel.BIN: SoftCall QSortSoft (QSortI64 asc)..."
EXPECT_KEYDEV_SOFT="Kernel.BIN: SoftCall KeyDevSoft (PutKey/PutS+CtrlAlt)..."
EXPECT_EXCEPT_SOFT="Kernel.BIN: SoftCall ExceptSoft (SysTry/throw/PutExcept)..."
EXPECT_MEM_SOFT="Kernel.BIN: SoftCall MemSoft (HeapCtrl+MAlloc/Free/MSize)..."
EXPECT_STRUTIL_SOFT="Kernel.BIN: SoftCall StrUtilSoft (StrUtil/MStrUtil path)..."
EXPECT_FIFO_SOFT="Kernel.BIN: SoftCall FifoSoft (FifoU8/I64 ring)..."
EXPECT_QUEVECT_SOFT="Kernel.BIN: SoftCall QueVectSoft (QueVectU8 New/Put/Get)..."
EXPECT_RAND_SOFT="Kernel.BIN: SoftCall RandSoft (Seed+LCG RandI64)..."
EXPECT_SCANFLAGS_SOFT="Kernel.BIN: SoftCall ScanFlagsSoft (LstMatch+ScanFlags+/-)..."
EXPECT_COMPRESS_SOFT="Kernel.BIN: SoftCall CompressSoft (CompressBuf/ExpandBuf)..."
EXPECT_KLOAD_SOFT="Kernel.BIN: SoftCall KLoadSoft (LoadPass1 import+ABS)..."
EXPECT_MAKEMEM_SOFT="Kernel.BIN: SoftCall MakeMemSoft (MemPag FREE_PAG=0x100)..."
EXPECT_PHYSMEM_SOFT="Kernel.BIN: SoftCall PhysMemSoft (BlkPoolsInit+MemPageTable+Mem32Dev)..."
EXPECT_LOADMAIN_SOFT="Kernel.BIN: SoftCall LoadMainSoft (CODE_HEAP+MAIN+FileRead)..."
EXPECT_HASH2_SOFT="Kernel.BIN: SoftCall Hash2Soft (free_pag_hash2 stock 55)..."
EXPECT_DATAHEAP_SOFT="Kernel.BIN: SoftCall DataHeapSoft (DATA_HEAP+ZEROED+ExtDft.Z)..."
EXPECT_LOADABS_SOFT="Kernel.BIN: SoftCall LoadAbsSoft (FileNameAbs+module_align)..."
EXPECT_DIRABS_SOFT="Kernel.BIN: SoftCall DirAbsSoft (DirNameAbs parents+Z+ExtDft)..."
EXPECT_STARTOS_SOFT="Kernel.BIN: SoftCall StartOSSoft (DirAbs+Adam+StartSoft no phase3 Cmp)..."
EXPECT_EXEPUTS_SOFT="Kernel.BIN: SoftCall ExePutSSoft (CmpCtrl+ExePutS 40+2)..."
EXPECT_CMP_SOFT="Kernel.BIN: SoftCall CmpSoft (CmpWrite SoftCmp.BIN Load+Call)..."
EXPECT_LEXSTMT_SOFT="Kernel.BIN: SoftCall LexStmtSoft (LexStmt2Bin emit+Call 40+2)..."
EXPECT_PRSOPT_SOFT="Kernel.BIN: SoftCall PrsOptSoft (Prs/Opt emit+Call 6*7)..."
EXPECT_PAREN_SOFT="Kernel.BIN: SoftCall ParenSoft (paren+IC emit (2+5)*8)..."
EXPECT_IDENT_SOFT="Kernel.BIN: SoftCall IdentSoft (local/ident IC x+2)..."
EXPECT_ASSIGN_SOFT="Kernel.BIN: SoftCall AssignSoft (PrsStmt assign x=40;x+2)..."
EXPECT_FUNDEF_SOFT="Kernel.BIN: SoftCall FunDefSoft (I64 F(){return 40+2;}F())..."
EXPECT_FUNBODY_SOFT="Kernel.BIN: SoftCall FunBodySoft (I64 F(){x=40;return x+2;}F())..."
EXPECT_FUNCALL_SOFT="Kernel.BIN: SoftCall FunCallSoft (I64 F(I64 a,I64 b){return a+b;}F(40,2))..."
EXPECT_ABI_SOFT="Kernel.BIN: SoftCall AbiSoft (I64 F(I64 a){return a+2;}F(40) a0 frame)..."
EXPECT_COC_SOFT="Kernel.BIN: SoftCall CocSoft (I64 F(){x=40;return x+2;}F() COC ASSIGN)..."
EXPECT_BR_SOFT="Kernel.BIN: SoftCall BrSoft (I64 F(){x=0;if(1)x=42;return x;}F() BR)..."
EXPECT_ELSE_SOFT="Kernel.BIN: SoftCall ElseSoft (I64 F(){x=0;if(1)x=42;else x=0;return x;}F() EL)..."
EXPECT_FOR_SOFT="Kernel.BIN: SoftCall ForSoft (I64 F(){for(x=40;x-42;x=x+1)y=0;return x;}F() FR)..."
EXPECT_CMPBR_SOFT="Kernel.BIN: SoftCall CmpBrSoft (I64 F(){x=0;if(x<1)x=42;return x;}F() CB)..."
EXPECT_CMPSRC_SOFT="Kernel.BIN: SoftCall CmpSrcSoft (Load SoftCmpSrc.BIN SoftCmpSrcProbe CS)..."
EXPECT_PRSSRC_SOFT="Kernel.BIN: SoftCall PrsSrcSoft (Load SoftPrsSrc.BIN SoftPrsSrcProbe PR)..."
EXPECT_LEXSRC_SOFT="Kernel.BIN: SoftCall LexSrcSoft (Load SoftLexSrc.BIN SoftLexSrcProbe LX)..."
EXPECT_ICSRC_SOFT="Kernel.BIN: SoftCall IcSrcSoft (Load SoftIcSrc.BIN SoftIcSrcProbe IC)..."
EXPECT_MULSRC_SOFT="Kernel.BIN: SoftCall MulSrcSoft (Load SoftMulSrc.BIN SoftMulSrcProbe MU)..."
EXPECT_SUBSRC_SOFT="Kernel.BIN: SoftCall SubSrcSoft (Load SoftSubSrc.BIN SoftSubSrcProbe SB)..."
EXPECT_OPTSRC_SOFT="Kernel.BIN: SoftCall OptSrcSoft (Load SoftOptSrc.BIN SoftOptSrcProbe OP)..."
EXPECT_COCSRC_SOFT="Kernel.BIN: SoftCall CocSrcSoft (Load SoftCocSrc.BIN SoftCocSrcProbe OC)..."
EXPECT_BRSRC_SOFT="Kernel.BIN: SoftCall BrSrcSoft (Load SoftBrSrc.BIN SoftBrSrcProbe BS)..."
EXPECT_ELSESRC_SOFT="Kernel.BIN: SoftCall ElseSrcSoft (Load SoftElseSrc.BIN SoftElseSrcProbe ES)..."
EXPECT_FORSRC_SOFT="Kernel.BIN: SoftCall ForSrcSoft (Load SoftForSrc.BIN SoftForSrcProbe FS)..."
EXPECT_CALLIC_SOFT="Kernel.BIN: SoftCall CallIcSoft (I64 G(){return 40;}I64 F(){return G()+2;}F() CL)..."
EXPECT_GLBLMEM_SOFT="Kernel.BIN: SoftCall GlblMemSoft (I64 g;I64 F(){g=40;return g+2;}F() GM)..."
EXPECT_GUESTCMP_SOFT="Kernel.BIN: SoftCall GuestCmpSoft (RedSea A:/Compiler/SoftGlbl.HC Cmp+Call GC)..."
EXPECT_GUESTLOCAL_SOFT="Kernel.BIN: SoftCall GuestLocalSoft (RedSea A:/Compiler/SoftLocal.HC I64 l; frame GL)..."
# Byte-level frame proof: the entry body really emits addi sp,sp,-32 plus sd/ld at
# 8(sp) and 16(sp). Counts are packed as sd8*10+sd16 / ld8*10+ld16 (2,1 and 2,1).
EXPECT_GUESTLOCAL_DIS="Kernel.BIN: GuestLocal disasm pro=1 sd8_16=21 ld8_16=21"
EXPECT_GUESTFLOW_SOFT="Kernel.BIN: SoftCall GuestFlowSoft (RedSea A:/Compiler/SoftFlow.HC if/while/for GF)..."
# Byte-level branch proof: three beqz a0 conds (for/while/if), two backward
# beq x0,x0 back edges (for/while) and one forward beq x0,x0 (the else join).
# A plant-time fold of any of them would emit no branch at all.
EXPECT_GUESTFLOW_DIS="Kernel.BIN: GuestFlow disasm br=3 jb=2 jf=1"
# Measured headroom the board prints against the caps.
EXPECT_GUESTFLOW_CAP="Kernel.BIN: GuestFlow code=308/1024 ic=25/32 lb=4/8"
EXPECT_GUESTPTR_SOFT="Kernel.BIN: SoftCall GuestPtrSoft (RedSea A:/Compiler/SoftPtr.HC U8 * lbu/sb GP)..."
# Byte-level typed-value proof: two lbu rd,0(rs1) (the for cond and the accumulate),
# three sb rs2,0(rs1) (the seeded bytes) and sixteen srli x,x,32 — one per
# lui/addi/slli/srli absolute-address materialize. A plant-time fold of the walk
# would emit no byte access at all, and an I64 cell read would emit ld, not lbu.
EXPECT_GUESTPTR_DIS="Kernel.BIN: GuestPtr disasm lbu=2 sb=3 abs=16"
EXPECT_GUESTPTR_CAP="Kernel.BIN: GuestPtr code=496/1024 ic=22/32 lb=2/8"
EXPECT_GUESTARG_SOFT="Kernel.BIN: SoftCall GuestArgSoft (RedSea A:/Compiler/SoftArg.HC I64 a,I64 b a0/a1 GA)..."
# Byte-level argument-passing proof: three jal ra (two Cost calls plus the Sum call),
# one sd ra,0(sp)/sd a0,8(sp)/sd a1,16(sp) spill prologue — matched as a sequence
# because a lone `sd a0,8(sp)` is also what an ordinary frame-local store looks like —
# and two addi a0,x0,imm/addi a1,x0,imm/jal ra call setups. A folded or fixed-arg
# callee would emit no jal and no argument-register setup at all.
EXPECT_GUESTARG_DIS="Kernel.BIN: GuestArg disasm jal=3 pro=1 set=2"
# Measured headroom the board prints against the caps.
EXPECT_GUESTARG_CAP="Kernel.BIN: GuestArg code=200/1024 ic=15/32 lb=1/8"
EXPECT_GUESTTYPE_SOFT="Kernel.BIN: SoftCall GuestTypeSoft (RedSea A:/Compiler/SoftType.HC U0/Bool/U32 a2/a3 GT)..."
# Byte-level width proof, one exact three-word sequence per type. Every single
# instruction involved is ambiguous on its own — `sltu a0,x0,a0` is also how `!=`
# ends, `slli/srli a0,a0,32` is also how an absolute address materialize ends, and a
# lone `sd` is an ordinary frame store — so each gate pins what must follow.
#   bool  sltu a0,x0,a0; ld ra,0(sp); addi sp,sp,frame  (Bool return narrowing)
#   u32   slli a0,a0,32; srli a0,a0,32; ld ra,0(sp)     (4 bytes, zero-extended)
#   nov   sd a0,0(t0); ld ra,0(sp); addi sp,sp,frame    (U0 tail: no value in a0)
EXPECT_GUESTTYPE_DIS="Kernel.BIN: GuestType disasm bool=1 u32=1 nov=1"
#   arg4  sd a1,16(sp); sd a2,24(sp); sd a3,32(sp)      (four-arg spill prologue)
#   set4  addi a2,x0,imm; addi a3,x0,imm; jal ra        (a2/a3 loaded before the call)
#   u32a  slli a0,a0,32; srli a0,a0,32; sd a0,8(sp)     (U32 arg narrowing on the way in)
EXPECT_GUESTTYPE_DIS2="Kernel.BIN: GuestType disasm arg4=1 set4=1 u32a=1"
# Measured headroom the board prints against the caps — including the frame-local
# count, which is what arity 4 actually squeezes (four args plus two working locals).
EXPECT_GUESTTYPE_CAP="Kernel.BIN: GuestType code=692/1024 ic=25/32 lb=2/8"
EXPECT_GUESTTYPE_CAP2="Kernel.BIN: GuestType caps lc=6/8 fun=7/8 glbl=4/4"
EXPECT_CALL="Kernel.BIN: SoftCall Load+Call LoadProbe..."

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT="gtimeout"
elif ! command -v timeout >/dev/null 2>&1; then
  echo "SKIP kernel-thin-loader smoke — missing timeout/gtimeout" >&2
  exit 0
fi

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-thin-loader smoke — missing $t" >&2; exit 0; }
done

make -C "$ROOT" holyc-riscv tools/pack_tosb >/dev/null

# Host-pack Kernel.BIN seed: Probe/Entry/InitLite + import-free SoftCall (mount/FS in BIN).
KERNEL_PROBE_SRC="$ROOT/tests/exec/cases/kernel_bin_probe.hc"
KERNEL_BLOB="$OUTDIR/kernel_bin_probe.blob.bin"
KERNEL_MAP="$OUTDIR/kernel_bin_probe.map"
LOAD_PROBE_SRC="$ROOT/tests/exec/cases/kernel_load_probe.hc"
LOAD_PROBE_BLOB="$OUTDIR/kernel_load_probe.blob.bin"
LOAD_PROBE_MAP="$OUTDIR/kernel_load_probe.map"
mkdir -p "$OUTDIR"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$KERNEL_MAP" \
   "$COMPILER" "$KERNEL_PROBE_SRC" -o "$KERNEL_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — Kernel.BIN probe compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$KERNEL_PROBE_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
KP_OFF=$(awk '/ KernelProbe$/{print $1; exit}' "$KERNEL_MAP")
KE_OFF=$(awk '/ KernelEntry$/{print $1; exit}' "$KERNEL_MAP")
KI_OFF=$(awk '/ KernelInitLite$/{print $1; exit}' "$KERNEL_MAP")
KH_OFF=$(awk '/ KernelHeapProbe$/{print $1; exit}' "$KERNEL_MAP")
KS_OFF=$(awk '/ KernelSoftCall$/{print $1; exit}' "$KERNEL_MAP")
KT_OFF=$(awk '/ KernelTrapProbe$/{print $1; exit}' "$KERNEL_MAP")
KV_OFF=$(awk '/ KernelVirtioProbe$/{print $1; exit}' "$KERNEL_MAP")
if [ -z "$KP_OFF" ] || [ -z "$KE_OFF" ] || [ -z "$KI_OFF" ] || [ -z "$KH_OFF" ] || [ -z "$KS_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — KernelProbe/Entry/InitLite/HeapProbe/SoftCall missing from map" >&2
  exit 1
fi
PACK_E=(-e "KernelProbe:0x${KP_OFF}" -e "KernelEntry:0x${KE_OFF}" \
  -e "KernelInitLite:0x${KI_OFF}" -e "KernelHeapProbe:0x${KH_OFF}" \
  -e "KernelSoftCall:0x${KS_OFF}")
if [ -n "$KT_OFF" ]; then
  PACK_E+=(-e "KernelTrapProbe:0x${KT_OFF}")
fi
if [ -n "$KV_OFF" ]; then
  PACK_E+=(-e "KernelVirtioProbe:0x${KV_OFF}")
fi
"$ROOT/tools/pack_tosb" -v "${PACK_E[@]}" \
  "$KERNEL_BLOB" "$ROOT/build/Kernel.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack Kernel.BIN" >&2; exit 1; }

# SoftCall Load companion (FileFind+Load from Kernel.BIN SoftCall).
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$LOAD_PROBE_MAP" \
   "$COMPILER" "$LOAD_PROBE_SRC" -o "$LOAD_PROBE_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — LoadProbe compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$LOAD_PROBE_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
LP_OFF=$(awk '/ LoadProbe$/{print $1; exit}' "$LOAD_PROBE_MAP")
if [ -z "$LP_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — LoadProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "LoadProbe:0x${LP_OFF}" \
  "$LOAD_PROBE_BLOB" "$ROOT/build/LoadProbe.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack LoadProbe.BIN" >&2; exit 1; }

# Product MakeOS Tiny.BIN (SoftCall MakeSoft Load+HashFind MakeOSProbe→42).
MAKEOS_SRC="$ROOT/tests/exec/cases/kernel_makeos_probe.hc"
MAKEOS_BLOB="$OUTDIR/kernel_makeos_probe.blob.bin"
MAKEOS_MAP="$OUTDIR/kernel_makeos_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$MAKEOS_MAP" \
   "$COMPILER" "$MAKEOS_SRC" -o "$MAKEOS_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — MakeOS Tiny compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$MAKEOS_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
MO_OFF=$(awk '/ MakeOSProbe$/{print $1; exit}' "$MAKEOS_MAP")
if [ -z "$MO_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — MakeOSProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "MakeOSProbe:0x${MO_OFF}" \
  "$MAKEOS_BLOB" "$ROOT/build/MakeOS_Tiny.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/Tiny.BIN" >&2; exit 1; }

# SoftCall CmpSrcSoft: host-AOT multi-fun compound slice (≤4KiB Load).
CMPSRC_SRC="$ROOT/tests/exec/cases/kernel_cmp_src_probe.hc"
CMPSRC_BLOB="$OUTDIR/kernel_cmp_src_probe.blob.bin"
CMPSRC_MAP="$OUTDIR/kernel_cmp_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$CMPSRC_MAP" \
   "$COMPILER" "$CMPSRC_SRC" -o "$CMPSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftCmpSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$CMPSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
CS_OFF=$(awk '/ SoftCmpSrcProbe$/{print $1; exit}' "$CMPSRC_MAP")
if [ -z "$CS_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftCmpSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftCmpSrcProbe:0x${CS_OFF}" \
  "$CMPSRC_BLOB" "$ROOT/build/MakeOS_SoftCmpSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftCmpSrc.BIN" >&2; exit 1; }
CMPSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftCmpSrc.BIN" | tr -d ' ')
if [ "$CMPSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftCmpSrc.BIN ${CMPSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall PrsSrcSoft: host-AOT Prs-shaped glbl+multi-fun fold (≤4KiB Load).
PRSSRC_SRC="$ROOT/tests/exec/cases/kernel_prs_src_probe.hc"
PRSSRC_BLOB="$OUTDIR/kernel_prs_src_probe.blob.bin"
PRSSRC_MAP="$OUTDIR/kernel_prs_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$PRSSRC_MAP" \
   "$COMPILER" "$PRSSRC_SRC" -o "$PRSSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftPrsSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$PRSSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
PR_OFF=$(awk '/ SoftPrsSrcProbe$/{print $1; exit}' "$PRSSRC_MAP")
if [ -z "$PR_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftPrsSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftPrsSrcProbe:0x${PR_OFF}" \
  "$PRSSRC_BLOB" "$ROOT/build/MakeOS_SoftPrsSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftPrsSrc.BIN" >&2; exit 1; }
PRSSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftPrsSrc.BIN" | tr -d ' ')
if [ "$PRSSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftPrsSrc.BIN ${PRSSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall LexSrcSoft: host-AOT LexStmt2Bin-shaped digit+op peel (≤4KiB Load).
LEXSRC_SRC="$ROOT/tests/exec/cases/kernel_lex_src_probe.hc"
LEXSRC_BLOB="$OUTDIR/kernel_lex_src_probe.blob.bin"
LEXSRC_MAP="$OUTDIR/kernel_lex_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$LEXSRC_MAP" \
   "$COMPILER" "$LEXSRC_SRC" -o "$LEXSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftLexSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$LEXSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
LX_OFF=$(awk '/ SoftLexSrcProbe$/{print $1; exit}' "$LEXSRC_MAP")
if [ -z "$LX_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftLexSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftLexSrcProbe:0x${LX_OFF}" \
  "$LEXSRC_BLOB" "$ROOT/build/MakeOS_SoftLexSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftLexSrc.BIN" >&2; exit 1; }
LEXSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftLexSrc.BIN" | tr -d ' ')
if [ "$LEXSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftLexSrc.BIN ${LEXSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall IcSrcSoft: host-AOT IC plant+emit beyond Lex peel (≤4KiB Load).
ICSRC_SRC="$ROOT/tests/exec/cases/kernel_ic_src_probe.hc"
ICSRC_BLOB="$OUTDIR/kernel_ic_src_probe.blob.bin"
ICSRC_MAP="$OUTDIR/kernel_ic_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$ICSRC_MAP" \
   "$COMPILER" "$ICSRC_SRC" -o "$ICSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftIcSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$ICSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
IC_OFF=$(awk '/ SoftIcSrcProbe$/{print $1; exit}' "$ICSRC_MAP")
if [ -z "$IC_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftIcSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftIcSrcProbe:0x${IC_OFF}" \
  "$ICSRC_BLOB" "$ROOT/build/MakeOS_SoftIcSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftIcSrc.BIN" >&2; exit 1; }
ICSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftIcSrc.BIN" | tr -d ' ')
if [ "$ICSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftIcSrc.BIN ${ICSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall MulSrcSoft: host-AOT MUL IC plant+emit beyond IMM/ADD (≤4KiB Load).
MULSRC_SRC="$ROOT/tests/exec/cases/kernel_mul_src_probe.hc"
MULSRC_BLOB="$OUTDIR/kernel_mul_src_probe.blob.bin"
MULSRC_MAP="$OUTDIR/kernel_mul_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$MULSRC_MAP" \
   "$COMPILER" "$MULSRC_SRC" -o "$MULSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftMulSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$MULSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
MU_OFF=$(awk '/ SoftMulSrcProbe$/{print $1; exit}' "$MULSRC_MAP")
if [ -z "$MU_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftMulSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftMulSrcProbe:0x${MU_OFF}" \
  "$MULSRC_BLOB" "$ROOT/build/MakeOS_SoftMulSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftMulSrc.BIN" >&2; exit 1; }
MULSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftMulSrc.BIN" | tr -d ' ')
if [ "$MULSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftMulSrc.BIN ${MULSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall SubSrcSoft: host-AOT SUB IC plant+emit beyond IMM/MUL (≤4KiB Load).
SUBSRC_SRC="$ROOT/tests/exec/cases/kernel_sub_src_probe.hc"
SUBSRC_BLOB="$OUTDIR/kernel_sub_src_probe.blob.bin"
SUBSRC_MAP="$OUTDIR/kernel_sub_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$SUBSRC_MAP" \
   "$COMPILER" "$SUBSRC_SRC" -o "$SUBSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftSubSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SUBSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
SB_OFF=$(awk '/ SoftSubSrcProbe$/{print $1; exit}' "$SUBSRC_MAP")
if [ -z "$SB_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftSubSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftSubSrcProbe:0x${SB_OFF}" \
  "$SUBSRC_BLOB" "$ROOT/build/MakeOS_SoftSubSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftSubSrc.BIN" >&2; exit 1; }
SUBSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftSubSrc.BIN" | tr -d ' ')
if [ "$SUBSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftSubSrc.BIN ${SUBSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall OptSrcSoft: host-AOT OptPass fold SoftCall Load beyond IMM/SUB (≤4KiB Load).
OPTSRC_SRC="$ROOT/tests/exec/cases/kernel_opt_src_probe.hc"
OPTSRC_BLOB="$OUTDIR/kernel_opt_src_probe.blob.bin"
OPTSRC_MAP="$OUTDIR/kernel_opt_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$OPTSRC_MAP" \
   "$COMPILER" "$OPTSRC_SRC" -o "$OPTSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftOptSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$OPTSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
OP_OFF=$(awk '/ SoftOptSrcProbe$/{print $1; exit}' "$OPTSRC_MAP")
if [ -z "$OP_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftOptSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftOptSrcProbe:0x${OP_OFF}" \
  "$OPTSRC_BLOB" "$ROOT/build/MakeOS_SoftOptSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftOptSrc.BIN" >&2; exit 1; }
OPTSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftOptSrc.BIN" | tr -d ' ')
if [ "$OPTSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftOptSrc.BIN ${OPTSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall CocSrcSoft: host-AOT COC multi-stmt ASSIGN SoftCall Load beyond Opt (≤4KiB Load).
COCSRC_SRC="$ROOT/tests/exec/cases/kernel_coc_src_probe.hc"
COCSRC_BLOB="$OUTDIR/kernel_coc_src_probe.blob.bin"
COCSRC_MAP="$OUTDIR/kernel_coc_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$COCSRC_MAP" \
   "$COMPILER" "$COCSRC_SRC" -o "$COCSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftCocSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$COCSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
OC_OFF=$(awk '/ SoftCocSrcProbe$/{print $1; exit}' "$COCSRC_MAP")
if [ -z "$OC_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftCocSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftCocSrcProbe:0x${OC_OFF}" \
  "$COCSRC_BLOB" "$ROOT/build/MakeOS_SoftCocSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftCocSrc.BIN" >&2; exit 1; }
COCSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftCocSrc.BIN" | tr -d ' ')
if [ "$COCSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftCocSrc.BIN ${COCSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall BrSrcSoft: host-AOT BR SoftCall Load beyond COC ASSIGN (≤4KiB Load).
BRSRC_SRC="$ROOT/tests/exec/cases/kernel_br_src_probe.hc"
BRSRC_BLOB="$OUTDIR/kernel_br_src_probe.blob.bin"
BRSRC_MAP="$OUTDIR/kernel_br_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$BRSRC_MAP" \
   "$COMPILER" "$BRSRC_SRC" -o "$BRSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftBrSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$BRSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
BS_OFF=$(awk '/ SoftBrSrcProbe$/{print $1; exit}' "$BRSRC_MAP")
if [ -z "$BS_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftBrSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftBrSrcProbe:0x${BS_OFF}" \
  "$BRSRC_BLOB" "$ROOT/build/MakeOS_SoftBrSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftBrSrc.BIN" >&2; exit 1; }
BRSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftBrSrc.BIN" | tr -d ' ')
if [ "$BRSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftBrSrc.BIN ${BRSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall ElseSrcSoft: host-AOT if/else JMP join SoftCall Load beyond BR (≤4KiB Load).
ELSESRC_SRC="$ROOT/tests/exec/cases/kernel_else_src_probe.hc"
ELSESRC_BLOB="$OUTDIR/kernel_else_src_probe.blob.bin"
ELSESRC_MAP="$OUTDIR/kernel_else_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$ELSESRC_MAP" \
   "$COMPILER" "$ELSESRC_SRC" -o "$ELSESRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftElseSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$ELSESRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
ES_OFF=$(awk '/ SoftElseSrcProbe$/{print $1; exit}' "$ELSESRC_MAP")
if [ -z "$ES_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftElseSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftElseSrcProbe:0x${ES_OFF}" \
  "$ELSESRC_BLOB" "$ROOT/build/MakeOS_SoftElseSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftElseSrc.BIN" >&2; exit 1; }
ELSESRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftElseSrc.BIN" | tr -d ' ')
if [ "$ELSESRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftElseSrc.BIN ${ELSESRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# SoftCall ForSrcSoft: host-AOT for-loop SoftCall Load beyond if/else (≤4KiB Load).
FORSRC_SRC="$ROOT/tests/exec/cases/kernel_for_src_probe.hc"
FORSRC_BLOB="$OUTDIR/kernel_for_src_probe.blob.bin"
FORSRC_MAP="$OUTDIR/kernel_for_src_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$FORSRC_MAP" \
   "$COMPILER" "$FORSRC_SRC" -o "$FORSRC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — SoftForSrc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$FORSRC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
FS_OFF=$(awk '/ SoftForSrcProbe$/{print $1; exit}' "$FORSRC_MAP")
if [ -z "$FS_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — SoftForSrcProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "SoftForSrcProbe:0x${FS_OFF}" \
  "$FORSRC_BLOB" "$ROOT/build/MakeOS_SoftForSrc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack MakeOS/SoftForSrc.BIN" >&2; exit 1; }
FORSRC_SZ=$(wc -c < "$ROOT/build/MakeOS_SoftForSrc.BIN" | tr -d ' ')
if [ "$FORSRC_SZ" -gt 4096 ]; then
  echo "FAIL kernel-thin-loader smoke — SoftForSrc.BIN ${FORSRC_SZ} > SoftCall Load 4KiB cap" >&2
  exit 1
fi

# Product Runtime Seed.BIN (SoftCall SeedSoft Load+HashFind RuntimeSeedInit→42).
SEED_SRC="$ROOT/tests/exec/cases/kernel_runtime_seed_probe.hc"
SEED_BLOB="$OUTDIR/kernel_runtime_seed_probe.blob.bin"
SEED_MAP="$OUTDIR/kernel_runtime_seed_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$SEED_MAP" \
   "$COMPILER" "$SEED_SRC" -o "$SEED_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — Runtime Seed compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SEED_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
RS_INIT_OFF=$(awk '/ RuntimeSeedInit$/{print $1; exit}' "$SEED_MAP")
RS_VAL_OFF=$(awk '/ RuntimeSeedVal$/{print $1; exit}' "$SEED_MAP")
if [ -z "$RS_INIT_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — RuntimeSeedInit missing from map" >&2
  exit 1
fi
SEED_PACK_E=(-e "RuntimeSeedInit:0x${RS_INIT_OFF}")
if [ -n "$RS_VAL_OFF" ]; then
  SEED_PACK_E+=(-e "RuntimeSeedVal:0x${RS_VAL_OFF}")
fi
"$ROOT/tools/pack_tosb" -v "${SEED_PACK_E[@]}" \
  "$SEED_BLOB" "$ROOT/build/Runtime_Seed.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack Runtime/Seed.BIN" >&2; exit 1; }

# Product Runtime Svc.BIN (SoftCall SvcSoft Load+HashFind RuntimeSvcProbe→42).
SVC_SRC="$ROOT/tests/exec/cases/kernel_runtime_svc_probe.hc"
SVC_BLOB="$OUTDIR/kernel_runtime_svc_probe.blob.bin"
SVC_MAP="$OUTDIR/kernel_runtime_svc_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$SVC_MAP" \
   "$COMPILER" "$SVC_SRC" -o "$SVC_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — Runtime Svc compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SVC_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
SVC_PROBE_OFF=$(awk '/ RuntimeSvcProbe$/{print $1; exit}' "$SVC_MAP")
SVC_VAL_OFF=$(awk '/ RuntimeSvcVal$/{print $1; exit}' "$SVC_MAP")
if [ -z "$SVC_PROBE_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — RuntimeSvcProbe missing from map" >&2
  exit 1
fi
SVC_PACK_E=(-e "RuntimeSvcProbe:0x${SVC_PROBE_OFF}")
if [ -n "$SVC_VAL_OFF" ]; then
  SVC_PACK_E+=(-e "RuntimeSvcVal:0x${SVC_VAL_OFF}")
fi
"$ROOT/tools/pack_tosb" -v "${SVC_PACK_E[@]}" \
  "$SVC_BLOB" "$ROOT/build/Runtime_Svc.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack Runtime/Svc.BIN" >&2; exit 1; }

# Product Runtime Kern.BIN (SoftCall KernSoft Load+HashFind KernInit→42).
KERN_SRC="$ROOT/tests/exec/cases/kernel_runtime_kern_probe.hc"
KERN_BLOB="$OUTDIR/kernel_runtime_kern_probe.blob.bin"
KERN_MAP="$OUTDIR/kernel_runtime_kern_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$KERN_MAP" \
   "$COMPILER" "$KERN_SRC" -o "$KERN_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — Runtime Kern compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$KERN_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
KERN_INIT_OFF=$(awk '/ KernInit$/{print $1; exit}' "$KERN_MAP")
KERN_BASE_OFF=$(awk '/ KernBase$/{print $1; exit}' "$KERN_MAP")
KERN_SCALE_OFF=$(awk '/ KernScale$/{print $1; exit}' "$KERN_MAP")
if [ -z "$KERN_INIT_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — KernInit missing from map" >&2
  exit 1
fi
KERN_PACK_E=(-e "KernInit:0x${KERN_INIT_OFF}")
if [ -n "$KERN_BASE_OFF" ]; then
  KERN_PACK_E+=(-e "KernBase:0x${KERN_BASE_OFF}")
fi
if [ -n "$KERN_SCALE_OFF" ]; then
  KERN_PACK_E+=(-e "KernScale:0x${KERN_SCALE_OFF}")
fi
"$ROOT/tools/pack_tosb" -v "${KERN_PACK_E[@]}" \
  "$KERN_BLOB" "$ROOT/build/Runtime_Kern.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack Runtime/Kern.BIN" >&2; exit 1; }

# Product Adam/StartOS.BIN (SoftCall AdamSoft Load+HashFind StartOSProbe→1).
STARTOS_SRC="$ROOT/tests/exec/cases/kernel_startos_probe.hc"
STARTOS_BLOB="$OUTDIR/kernel_startos_probe.blob.bin"
STARTOS_MAP="$OUTDIR/kernel_startos_probe.map"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$STARTOS_MAP" \
   "$COMPILER" "$STARTOS_SRC" -o "$STARTOS_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — Adam StartOS compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$STARTOS_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
STARTOS_OFF=$(awk '/ StartOSProbe$/{print $1; exit}' "$STARTOS_MAP")
if [ -z "$STARTOS_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — StartOSProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "StartOSProbe:0x${STARTOS_OFF}" \
  "$STARTOS_BLOB" "$ROOT/build/Adam_StartOS.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack Adam/StartOS.BIN" >&2; exit 1; }

# SoftCall GuestCmpSoft / GuestLocalSoft: Compiler_RV-shaped guest HolyC that lives
# only on the disk image. Kernel.BIN reads each one multi-blk at runtime and Cmps it —
# so the honesty gate per fragment is (a) Kernel.BIN must NOT carry any of its idents,
# and (b) the sz + rolling *31 sum the board prints must match the file byte-for-byte.
guest_src_sz() {
  if [ ! -f "$1" ]; then
    echo "FAIL kernel-thin-loader smoke — guest Cmp source missing: $1" >&2
    exit 1
  fi
  sz=$(wc -c < "$1" | tr -d ' ')
  if [ "$sz" -le 512 ] || [ "$sz" -gt 4096 ]; then
    echo "FAIL kernel-thin-loader smoke — guest src $1 ${sz} B outside multi-blk 513..2048 window" >&2
    exit 1
  fi
  printf '%s' "$sz"
}

guest_src_sum() {
  python3 -c '
import sys
s = 0
for c in open(sys.argv[1], "rb").read():
    s = (s * 31 + c) & 0xFFFFFFFF
print("%X" % s)
' "$1" || { echo "FAIL kernel-thin-loader smoke — guest src sum $1" >&2; exit 1; }
}

GUEST_SRC="$ROOT/tests/exec/cases/kernel_guest_src_probe.hc"
GUEST_LOCAL_SRC="$ROOT/tests/exec/cases/kernel_guest_local_probe.hc"
GUEST_FLOW_SRC="$ROOT/tests/exec/cases/kernel_guest_flow_probe.hc"
GUEST_PTR_SRC="$ROOT/tests/exec/cases/kernel_guest_ptr_probe.hc"
GUEST_ARG_SRC="$ROOT/tests/exec/cases/kernel_guest_arg_probe.hc"
GUEST_TYPE_SRC="$ROOT/tests/exec/cases/kernel_guest_type_probe.hc"
# Each helper exits its subshell non-zero on failure, so keep the `|| exit 1`.
GUEST_SZ=$(guest_src_sz "$GUEST_SRC") || exit 1
GUEST_SUM=$(guest_src_sum "$GUEST_SRC") || exit 1
GUEST_LOCAL_SZ=$(guest_src_sz "$GUEST_LOCAL_SRC") || exit 1
GUEST_LOCAL_SUM=$(guest_src_sum "$GUEST_LOCAL_SRC") || exit 1
GUEST_FLOW_SZ=$(guest_src_sz "$GUEST_FLOW_SRC") || exit 1
GUEST_FLOW_SUM=$(guest_src_sum "$GUEST_FLOW_SRC") || exit 1
GUEST_PTR_SZ=$(guest_src_sz "$GUEST_PTR_SRC") || exit 1
GUEST_PTR_SUM=$(guest_src_sum "$GUEST_PTR_SRC") || exit 1
GUEST_ARG_SZ=$(guest_src_sz "$GUEST_ARG_SRC") || exit 1
GUEST_ARG_SUM=$(guest_src_sum "$GUEST_ARG_SRC") || exit 1
GUEST_TYPE_SZ=$(guest_src_sz "$GUEST_TYPE_SRC") || exit 1
GUEST_TYPE_SUM=$(guest_src_sum "$GUEST_TYPE_SRC") || exit 1
# No in-BIN literal: none of the guest idents may appear anywhere in Kernel.BIN.
python3 -c '
import sys
blob = open(sys.argv[1], "rb").read()
for tok in (b"RvAsmExportsSum", b"RvAsmExportsInit", b"g_rv_asm_exports", b"g_rv_asm_pass",
            b"RvPrsFrameSum", b"RvPrsFrameLeaf", b"g_rv_prs_depth",
            b"RvOptPassScan", b"RvOptPassPeel", b"RvOptPassFold", b"g_rv_opt_ic_n",
            b"g_rv_opt_hits",
            b"RvLexSeedText", b"RvLexWalkText", b"RvLexTokScan", b"g_rv_lex_buf",
            b"g_rv_lex_ptr", b"g_rv_lex_sum",
            b"RvIcOpCost", b"RvIcOpSum", b"RvIcOpTally", b"g_rv_ic_cost",
            b"RvEncIType", b"RvEncFits", b"RvEncBit31", b"RvEncBuf",
            b"RvEncCheck", b"RvEncWidth", b"RvEncSum", b"g_rv_enc_buf",
            b"g_rv_enc_ptr", b"g_rv_enc_end", b"g_rv_enc_word"):
    if tok in blob:
        print("guest ident %s found in Kernel.BIN" % tok.decode(), file=sys.stderr)
        sys.exit(1)
' "$ROOT/build/Kernel.BIN" \
  || { echo "FAIL kernel-thin-loader smoke — guest Cmp source is an in-BIN literal" >&2; exit 1; }
EXPECT_GUESTCMP_SRC="Kernel.BIN: GuestCmp src sz=${GUEST_SZ} sum=${GUEST_SUM}"
EXPECT_GUESTLOCAL_SRC="Kernel.BIN: GuestLocal src sz=${GUEST_LOCAL_SZ} sum=${GUEST_LOCAL_SUM}"
EXPECT_GUESTFLOW_SRC="Kernel.BIN: GuestFlow src sz=${GUEST_FLOW_SZ} sum=${GUEST_FLOW_SUM}"
EXPECT_GUESTPTR_SRC="Kernel.BIN: GuestPtr src sz=${GUEST_PTR_SZ} sum=${GUEST_PTR_SUM}"
EXPECT_GUESTARG_SRC="Kernel.BIN: GuestArg src sz=${GUEST_ARG_SZ} sum=${GUEST_ARG_SUM}"
EXPECT_GUESTTYPE_SRC="Kernel.BIN: GuestType src sz=${GUEST_TYPE_SZ} sum=${GUEST_TYPE_SUM}"

REDSEA_IMG="$OUTDIR/thin_loader_redsea.img"
python3 "$ROOT/tools/mk_redsea_seed_img.py" "$REDSEA_IMG" \
  "Compiler/SoftGlbl.HC=$GUEST_SRC" \
  "Compiler/SoftLocal.HC=$GUEST_LOCAL_SRC" \
  "Compiler/SoftFlow.HC=$GUEST_FLOW_SRC" \
  "Compiler/SoftPtr.HC=$GUEST_PTR_SRC" \
  "Compiler/SoftArg.HC=$GUEST_ARG_SRC" \
  "Compiler/SoftType.HC=$GUEST_TYPE_SRC" \
  "Kernel/Kernel.BIN=$ROOT/build/Kernel.BIN" \
  "Kernel/LoadProbe.BIN=$ROOT/build/LoadProbe.BIN" \
  "MakeOS/Tiny.BIN=$ROOT/build/MakeOS_Tiny.BIN" \
  "MakeOS/SoftCmpSrc.BIN=$ROOT/build/MakeOS_SoftCmpSrc.BIN" \
  "MakeOS/SoftPrsSrc.BIN=$ROOT/build/MakeOS_SoftPrsSrc.BIN" \
  "MakeOS/SoftLexSrc.BIN=$ROOT/build/MakeOS_SoftLexSrc.BIN" \
  "MakeOS/SoftIcSrc.BIN=$ROOT/build/MakeOS_SoftIcSrc.BIN" \
  "MakeOS/SoftMulSrc.BIN=$ROOT/build/MakeOS_SoftMulSrc.BIN" \
  "MakeOS/SoftSubSrc.BIN=$ROOT/build/MakeOS_SoftSubSrc.BIN" \
  "MakeOS/SoftOptSrc.BIN=$ROOT/build/MakeOS_SoftOptSrc.BIN" \
  "MakeOS/SoftCocSrc.BIN=$ROOT/build/MakeOS_SoftCocSrc.BIN" \
  "MakeOS/SoftBrSrc.BIN=$ROOT/build/MakeOS_SoftBrSrc.BIN" \
  "MakeOS/SoftElseSrc.BIN=$ROOT/build/MakeOS_SoftElseSrc.BIN" \
  "MakeOS/SoftForSrc.BIN=$ROOT/build/MakeOS_SoftForSrc.BIN" \
  "Runtime/Seed.BIN=$ROOT/build/Runtime_Seed.BIN" \
  "Runtime/Svc.BIN=$ROOT/build/Runtime_Svc.BIN" \
  "Runtime/Kern.BIN=$ROOT/build/Runtime_Kern.BIN" \
  "Adam/StartOS.BIN=$ROOT/build/Adam_StartOS.BIN" \
  || { echo "FAIL kernel-thin-loader smoke — RedSea seed img" >&2; exit 1; }

if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-thin-loader smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-thin-loader smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -40 >&2
  exit 1
fi

# Embed Kernel.BIN at 0x81000000 (.compiler_bin / KERNEL_EMBED_ADDR).
"$OBJCOPY" -I binary -O elf64-littleriscv \
  --rename-section .data=.data,alloc,load,code,contents,readonly \
  "$ROOT/build/Kernel.BIN" "$T/kernel_embed.o" \
  || { echo "FAIL kernel-thin-loader smoke — kernel_embed.o" >&2; exit 1; }

( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,code,contents,readonly \
    blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch \
    -o thin.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o kernel_embed.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-thin-loader smoke — link error" >&2; exit 1; }

cp "$T/thin.elf" "$OUTDIR/thin_loader.elf"
cp "$REDSEA_IMG" "$T/thin_loader_redsea.img" \
  || { echo "FAIL kernel-thin-loader smoke — copy RedSea img" >&2; exit 1; }

# Non-return Stay parks in WFI; timeout is expected — UART needles are the gate.
# TrapPlic SoftCall stays unwired (host-fed RX + asm EXT clear hung).
# SoftCall tip chain (StartOS + SoftCall-lite through CmpBr + CmpSrc Load) needs ~60s on CI Macs.
THIN_TIMEOUT="${THIN_TIMEOUT:-90}"
out=""
out=$(LC_ALL=C $TIMEOUT "$THIN_TIMEOUT" "$QEMU" -M virt -m 256M -bios none -kernel "$T/thin.elf" -nographic \
  -drive file="$T/thin_loader_redsea.img",if=none,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 </dev/null 2>&1 | LC_ALL=C tr -d '\r') || true
printf '%s\n' "$out" > /tmp/thin_loader_uart.txt || true

if printf '%s\n' "$out" | grep -qF "$EXPECT_DEFER" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_EMBED" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SZ" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_FIND" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_JUMP" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_INIT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_TRAP" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_HAND" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_MOUNT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_CALL" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_BLK" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_OWN" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_IRQ" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_TIMER" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_DISP" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_TASK" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_HASH" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_PRINT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_YIELD" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_JUMP_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_EXE_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_MAKE_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SEED_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SVC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERN_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_START_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_ADAM_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_DATE_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_QSORT_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KEYDEV_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_EXCEPT_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_MEM_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_STRUTIL_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_FIFO_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_QUEVECT_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_RAND_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SCANFLAGS_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_COMPRESS_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KLOAD_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_MAKEMEM_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_PHYSMEM_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_LOADMAIN_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_HASH2_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_DATAHEAP_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_LOADABS_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_DIRABS_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_STARTOS_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_EXEPUTS_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_CMP_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_LEXSTMT_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_PRSOPT_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_PAREN_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_IDENT_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_ASSIGN_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_FUNDEF_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_FUNBODY_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_FUNCALL_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_ABI_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_COC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_BR_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_ELSE_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_FOR_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_CMPBR_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_CMPSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_PRSSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_LEXSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_ICSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_MULSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SUBSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_OPTSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_COCSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_BRSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_ELSESRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_FORSRC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_CALLIC_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GLBLMEM_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTCMP_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTCMP_SRC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTLOCAL_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTLOCAL_SRC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTLOCAL_DIS" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTFLOW_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTFLOW_SRC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTFLOW_DIS" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTFLOW_CAP" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTPTR_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTPTR_SRC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTPTR_DIS" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTPTR_CAP" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTARG_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTARG_SRC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTARG_DIS" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTARG_CAP" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTTYPE_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTTYPE_SRC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTTYPE_DIS" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTTYPE_DIS2" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTTYPE_CAP" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_GUESTTYPE_CAP2" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_STAY" && \
   ! printf '%s\n' "$out" | grep -qF "RVThinLoader: Jump returned (FAIL)." && \
   ! printf '%s\n' "$out" | grep -qF "RVThinLoader: HashFind KernelEntry FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall HashSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall PrintSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall YieldSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall JumpSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall ExeSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall MakeSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall SeedSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall SvcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall KernSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall StartSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall AdamSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall DateSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall QSortSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall KeyDevSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall ExceptSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall MemSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall StrUtilSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall FifoSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall QueVectSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall RandSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall ScanFlagsSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall CompressSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall KLoadSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall MakeMemSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall PhysMemSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall LoadMainSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall Hash2Soft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall DataHeapSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall LoadAbsSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall DirAbsSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall StartOSSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall ExePutSSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall CmpSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall LexStmtSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall PrsOptSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall ParenSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall IdentSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall AssignSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall FunDefSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall FunBodySoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall FunCallSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall AbiSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall CocSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall BrSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall ElseSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall ForSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall CmpBrSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall CmpSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall PrsSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall LexSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall IcSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall MulSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall SubSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall OptSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall CocSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall BrSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall ElseSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall ForSrcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall CallIcSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GlblMemSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestCmpSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestCmpSoft skip" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestLocalSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestLocalSoft skip" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestFlowSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestFlowSoft skip" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestPtrSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestPtrSoft skip" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestArgSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestArgSoft skip" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestTypeSoft FAILED" && \
   ! printf '%s\n' "$out" | grep -qF "SoftCall GuestTypeSoft skip"; then
  echo "Kernel-thin-loader smoke: OK (thin embed+LoadBuf+HashFind Jump + SoftCall stay; no MMIO+raw chicken-egg)"
  exit 0
fi
echo "FAIL kernel-thin-loader smoke — expected handoff line not found:" >&2
echo "  want: $EXPECT_DEFER / $EXPECT_EMBED / $EXPECT_SZ / $EXPECT_FIND / $EXPECT_JUMP / $EXPECT_INIT / $EXPECT_TRAP / $EXPECT_HAND / $EXPECT_MOUNT / $EXPECT_CALL / $EXPECT_BLK / $EXPECT_OWN / $EXPECT_IRQ / $EXPECT_TIMER / $EXPECT_DISP / $EXPECT_TASK / $EXPECT_HASH / $EXPECT_PRINT / $EXPECT_YIELD / $EXPECT_JUMP_SOFT / $EXPECT_EXE_SOFT / $EXPECT_MAKE_SOFT / $EXPECT_SEED_SOFT / $EXPECT_SVC_SOFT / $EXPECT_KERN_SOFT / $EXPECT_START_SOFT / $EXPECT_ADAM_SOFT / $EXPECT_DATE_SOFT / $EXPECT_QSORT_SOFT / $EXPECT_KEYDEV_SOFT / $EXPECT_EXCEPT_SOFT / $EXPECT_MEM_SOFT / $EXPECT_STRUTIL_SOFT / $EXPECT_FIFO_SOFT / $EXPECT_QUEVECT_SOFT / $EXPECT_RAND_SOFT / $EXPECT_SCANFLAGS_SOFT / $EXPECT_COMPRESS_SOFT / $EXPECT_KLOAD_SOFT / $EXPECT_MAKEMEM_SOFT / $EXPECT_PHYSMEM_SOFT / $EXPECT_LOADMAIN_SOFT / $EXPECT_HASH2_SOFT / $EXPECT_DATAHEAP_SOFT / $EXPECT_LOADABS_SOFT / $EXPECT_DIRABS_SOFT / $EXPECT_STARTOS_SOFT / $EXPECT_EXEPUTS_SOFT / $EXPECT_CMP_SOFT / $EXPECT_LEXSTMT_SOFT / $EXPECT_PRSOPT_SOFT / $EXPECT_PAREN_SOFT / $EXPECT_IDENT_SOFT / $EXPECT_ASSIGN_SOFT / $EXPECT_FUNDEF_SOFT / $EXPECT_FUNBODY_SOFT / $EXPECT_FUNCALL_SOFT / $EXPECT_ABI_SOFT / $EXPECT_COC_SOFT / $EXPECT_BR_SOFT / $EXPECT_ELSE_SOFT / $EXPECT_FOR_SOFT / $EXPECT_CMPBR_SOFT / $EXPECT_CMPSRC_SOFT / $EXPECT_PRSSRC_SOFT / $EXPECT_LEXSRC_SOFT / $EXPECT_ICSRC_SOFT / $EXPECT_MULSRC_SOFT / $EXPECT_SUBSRC_SOFT / $EXPECT_OPTSRC_SOFT / $EXPECT_COCSRC_SOFT / $EXPECT_BRSRC_SOFT / $EXPECT_ELSESRC_SOFT / $EXPECT_FORSRC_SOFT / $EXPECT_CALLIC_SOFT / $EXPECT_GLBLMEM_SOFT / $EXPECT_GUESTCMP_SOFT / $EXPECT_GUESTCMP_SRC / $EXPECT_GUESTLOCAL_SOFT / $EXPECT_GUESTLOCAL_SRC / $EXPECT_GUESTLOCAL_DIS / $EXPECT_GUESTFLOW_SOFT / $EXPECT_GUESTFLOW_SRC / $EXPECT_GUESTFLOW_DIS / $EXPECT_GUESTFLOW_CAP / $EXPECT_GUESTPTR_SOFT / $EXPECT_GUESTPTR_SRC / $EXPECT_GUESTPTR_DIS / $EXPECT_GUESTPTR_CAP / $EXPECT_GUESTARG_SOFT / $EXPECT_GUESTARG_SRC / $EXPECT_GUESTARG_DIS / $EXPECT_GUESTARG_CAP / $EXPECT_GUESTTYPE_SOFT / $EXPECT_GUESTTYPE_SRC / $EXPECT_GUESTTYPE_DIS / $EXPECT_GUESTTYPE_DIS2 / $EXPECT_GUESTTYPE_CAP / $EXPECT_GUESTTYPE_CAP2 / $EXPECT_SOFT / $EXPECT_STAY" >&2
printf '%s\n' "$out" | grep -E 'RVThin|RVKMain|Kernel|Load|FAIL|OK|Except|Error|stay|mount|Trap|embed|Task|Hash|Print|Yield|Jump|Exe|Make|Seed|Svc|Kern|Start|Adam|Date|QSort|KeyDev|MemSoft|StrUtil|FifoSoft|QueVectSoft|RandSoft|ScanFlagsSoft|CompressSoft|KLoadSoft|MakeMemSoft|PhysMemSoft|LoadMainSoft|Hash2Soft|DataHeapSoft|LoadAbsSoft|DirAbsSoft|StartOSSoft|ExePutSSoft|CmpSoft|LexStmtSoft|PrsOptSoft|ParenSoft|IdentSoft|AssignSoft|FunDefSoft|FunBodySoft|FunCallSoft|AbiSoft|CocSoft|BrSoft|ElseSoft|ForSoft|CmpBrSoft|CmpSrcSoft|PrsSrcSoft|LexSrcSoft|IcSrcSoft|MulSrcSoft|SubSrcSoft|OptSrcSoft|CocSrcSoft|BrSrcSoft|ElseSrcSoft|ForSrcSoft|CallIcSoft|GlblMemSoft|GuestCmpSoft|GuestCmp src|GuestLocalSoft|GuestLocal |GuestFlowSoft|GuestFlow |GuestPtrSoft|GuestPtr |GuestArgSoft|GuestArg |GuestTypeSoft|GuestType ' | head -50 | LC_ALL=C sed 's/^/  /' >&2
exit 1
