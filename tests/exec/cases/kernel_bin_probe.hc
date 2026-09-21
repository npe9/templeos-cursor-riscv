// Host-packed RedSea Kernel.BIN seed (G9) — growing toward Kernel_RV TOSB.
// Not full Kernel_RV. Thin path embeds this BIN @0x81000000 (RV_THIN_EMBED_BIN)
// — no RVThinVirtioBlk+RVRedSeaRaw chicken-egg; SoftCall re-Inits virtio.
// Smoke: holyc-riscv → pack_tosb → embed+RedSea LoadProbe img → thin Jump.
//
// InitLite stays import-free (UART TX/RX + 64 KiB product freelist heap @
// HEAP_BASE + magic + CSR jalr). Thin path: embed LoadBuf @0x81000000 before SoftCall.
// SoftCall is import-free: StrLen/arena/MemCpy + full VirtioBlkInit (reset+VQ)
// + Cap/Read/Write + RedSea mount/FileWrite/FileFind/Load + export-table Call
// (LoadProbe→7) + Validate. CSR via writable U32[] jalr stubs — not `_extern`
// (host AOT turns `_extern` into null __imp_*).
//
// KernelProbe      — phase3 seed needle (→42).
// KernelHeapProbe  — product freelist @ CONFIG_HEAP_BASE (64 KiB; →64).
// KernelTrapProbe  — in-BIN CSR mhartid/mstatus/misa via jalr stubs (→0x4B54 'KT').
// KernelTrapSoft   — TrapCtx GPR frame + IRQ fast-path + mcause-gated ecall
//                    (cause==11→mscratch; IRQ bltz→SoftCall HolyC+restore;
//                    hang else); proves t0 survives ecall (→0x4B58 'KX').
//                    InitLite only — mid-SoftCall ecall previously broke Cap/Read.
// KernelTrapOwn    — SoftCall post-Cap: leave TrapCtx mtvec installed.
// KernelTrapIrq    — SoftCall live CLINT MSIP → TrapCtx SoftCall HolyC clear
//                    MSIP → mscratch cause==0x8000000000000003 (→0x4B51 'KQ').
// KernelTrapTimer  — SoftCall live CLINT timer → HolyC clear mtimecmp=-1 →
//                    mscratch cause==0x8000000000000007 (→0x4B4D 'KM').
// KernelTrapDisp   — SoftCall live MSIP → TrapCtx SoftCalls HolyC
//                    KernelTrapDispatch (hook @0x8700E018; CLINT clear in HolyC)
//                    → HIT 'KH' (→0x4B44 'KD').
// KernelTrapPlic   — WIP (unwired): host-fed UART RX→PLIC SoftCall hung
//                    (before armed needle; THRE×2 + virtio×2 + asm EXT clear also hung).
//                    Dispatch claim/complete+IER clear+#10/virtio enable-drop ready.
// KernelTaskSoft   — SoftCall TaskInit+Spawn ring + JobQue JOBT_CALL + JobRunOne
//                    (no Yield/ctxsw; import-free CKernelTask) →0x4B4A 'KJ'.
//                    Path past thin KThinTaskStubs/KThinJobStubs wall.
// KernelHashSoft   — SoftCall HashStr+TableNew+Add+Find (import-free CKernelHash;
//                    index body stores like KHashRV) →0x4B46 'KF'.
//                    SoftCall re-proves hash shape; thin Jump uses lite KThinHashStubs.
// KernelPrintSoft  — SoftCall StrPrintJoin lite (%s/%d/%X/%c) →0x4B50 'KP'.
//                    Path past thin KThinStrPrintStubs wall (no full StrPrint.HC).
// KernelYieldSoft  — SoftCall Yield+HolyRVCtxSw on CKernelTask.rsp (next_task walk,
//                    skip KILL; import-free U32[] ctxsw stub) →0x4B59 'KY'.
//                    Path past thin KThinSchedStubs / host _YIELD wall.
// KernelJumpSoft   — SoftCall LoadBuf→HashAdd→HashFind Jump path (embed BIN @
//                    0x81000000): export walk + Find KernelEntry (==hint+&Entry)
//                    + Call KernelProbe via HashFind→42 →0x4B4C 'KL'.
//                    No embed → -1 (phase3 SoftCall skips; thin always embeds).
//                    Mirrors thin Jump (lite HashFind→Call); SoftCall re-proves in BIN.
// KernelExeSoft    — SoftCall ExeFile-shaped Load ownership (no Cmp): RedSea
//                    LoadProbe.BIN → HashAdd exports → HashFind→Call →7 →0x4B42
//                    'KB'. Past linear CallExport; same HashFind shape as JumpSoft
//                    but on virtio RedSea Load (phase3 StartOS Load→Call needle).
// KernelMakeSoft   — SoftCall product MakeOS Load (no Cmp): RedSea Tiny.BIN →
//                    HashAdd → HashFind→Call MakeOSProbe→42 →0x4B4E 'KN'.
//                    StartOS-shaped product path past LoadProbe companion.
// KernelSeedSoft   — SoftCall product Runtime Seed Load (no Cmp): RedSea
//                    Seed.BIN → HashAdd → HashFind→Call RuntimeSeedInit→42
//                    →0x4B52 'KR'. StartOS Seed→Svc→Kern chain tip (F()+imm).
// KernelSvcSoft    — SoftCall product Runtime Svc Load (no Cmp): RedSea
//                    Svc.BIN → HashAdd → HashFind→Call RuntimeSvcProbe→42
//                    →0x4B43 'KC'. StartOS Svc tip (F()→F()).
// KernelKernSoft   — SoftCall product Runtime Kern Load (no Cmp): RedSea
//                    Kern.BIN → HashAdd → HashFind→Call KernInit→42
//                    →0x4B4B 'KK'. StartOS Kern tip (arg+call+add).
// KernelStartSoft  — SoftCall StartOS-shaped multi-BIN sequence (no Cmp):
//                    Seed→Svc→Kern Softs in order →0x4B55 'KU'. Proves one
//                    SoftCall owns the Runtime Load chain (past single-BIN tips).
// KernelAdamSoft   — SoftCall product Adam StartOS Load (no Cmp): RedSea
//                    StartOS.BIN → HashAdd → HashFind→Call StartOSProbe→1
//                    →0x4B41 'KA'. Phase3 StartOS Load→Call needle (no DocTerm).
// KernelStartOSSoft— SoftCall full StartOS Load chain without Mac phase3.elf
//                    Cmp scaffold: DirAbs-resolve A:/Kernel/../Adam/StartOS.BIN
//                    → AdamSoft (StartOSProbe=1) → StartSoft (Seed→Svc→Kern)
//                    →0x534F 'SO'. Proves phase3 StartOS Load ownership on thin
//                    SoftCall (product BINs; no guest Cmp / no phase3 ELF).
// KernelExePutSSoft— SoftCall-lite CmpCtrl+ExePutS ownership (no imports):
//                    CmpCtrl New/buf_ptr + LexGetChar + I64 +/- expr ExePutS
//                    ("40+2;"→42) past StartOSSoft; SoftCall-lite — no
//                    LexStmt2Bin/Prs/Opt/emit/fun-def; full Compiler.BIN ~1.1 MiB
//                    +97 imports won't fit SoftCall 64 KiB arena / Load 2 KiB cap
//                    →0x4550 'EP'. Packs Compiler CMain ExePutS + Lex CmpCtrl
//                    HolyC shape SoftCall-lite into RedSea Kernel.BIN.
// KernelCmpSoft    — SoftCall-lite MakeOS CmpWrite ownership (no imports):
//                    SoftCall-compose TOSB (li a0,42;ret + REL64 export) →
//                    FileWrite A:/MakeOS/SoftCmp.BIN → Load+HashFind+Call
//                    CmpSoftProbe→42 →0x4343 'CC'. Past ExePutSSoft; SoftCall-
//                    lite hand-emit only — no Compiler_RV LexStmt2Bin; shrinks
//                    phase3 MakeOS Cmp scaffold toward thin SoftCall.
// KernelLexStmtSoft— SoftCall-lite LexStmt2Bin/emit ownership (no imports):
//                    CmpCtrl Lex I64 +/- → emit RV addi a0 + ret into BSS →
//                    FenceI → Call ("40+2;"→42) past CmpSoft; SoftCall-lite —
//                    no PrsStmt/OptPass/COC/fun-def; full Compiler.BIN still
//                    phase3 (64 KiB arena / 2 KiB Load) →0x4C42 'LB'.
// KernelPrsOptSoft — SoftCall-lite Prs/Opt stub ownership (no imports):
//                    PrsExpr I64 +-* RPN IC → OptPass constant-fold → emit RV
//                    addi a0 + ret → FenceI → Call ("6*7;"→42, "2+5*8;"→42)
//                    past LexStmtSoft; SoftCall-lite — no PrsStmt/OptPass012/
//                    COC/fun-def; paren+IC-beyond-fold owned by ParenSoft
//                    →0x504F 'PO'. Full Compiler.BIN still phase3
//                    (64 KiB arena / 2 KiB Load; ~1.1 MiB +97 imports).
// KernelParenSoft  — SoftCall-lite PrsFactor paren + IC emit beyond fold
//                    (no imports): "(2+5)*8;"→56 fold+addi AND RPN→RV
//                    addi/add/mul emit (no OptPass) past PrsOptSoft; keeps
//                    PrsOptSoft/LexStmtSoft/ExePutSSoft green; SoftCall-lite —
//                    no fun-def/PrsStmt/COC/full Compiler.BIN Load →0x504E 'PN'.
// KernelIdentSoft  — SoftCall-lite local/ident IC past ParenSoft (no imports):
//                    LexIdent + soft local plant + IC_LOCAL in PrsFactor →
//                    OptPass fold + EmitIC addi; "x+2;"/"x+y;"→42 with
//                    x=40,y=2 planted; keeps ParenSoft/PrsOptSoft green;
//                    SoftCall-lite — no fun-def/PrsStmt/COC/full Compiler.BIN
//                    Load →0x4944 'ID'. AssignSoft owns PrsStmt assign tip.
// KernelAssignSoft — SoftCall-lite PrsStmt assign fragment past IdentSoft
//                    (no imports): ident=expr; … expr; plants locals from
//                    source ("x=40;x+2;"/"x=40;y=2;x+y;"→42) fold+IC emit;
//                    keeps IdentSoft/ParenSoft/PrsOptSoft green; SoftCall-lite —
//                    no fun-def/COC/full Compiler.BIN Load →0x4153 'AS'.
// KernelFunDefSoft — SoftCall-lite fun-def past AssignSoft (no imports):
//                    I64 F(){return Expr;} F(); parse+emit body+Call
//                    ("I64 F(){return 40+2;}F();"→42) fold+IC emit; keeps
//                    AssignSoft/IdentSoft/ParenSoft green; SoftCall-lite —
//                    FunBodySoft owns args/locals-in-fun/multi-stmt; no COC/
//                    full Compiler.BIN Load →0x4644 'FD'.
// KernelFunBodySoft— SoftCall-lite fun body past FunDefSoft (no imports):
//                    multi-stmt + locals-in-fun + SoftCall-lite single I64
//                    arg plant-at-call (LexI64; no ABI/a0):
//                    "I64 F(){x=40;return x+2;}F();" /
//                    "I64 F(I64 a){return a+2;}F(40);"→42 fold+IC emit; keeps
//                    FunDefSoft/AssignSoft green; SoftCall-lite — FunCallSoft
//                    owns multi-arg/call-Expr; no ABI/COC/full Compiler.BIN
//                    Load →0x4642 'FB'.
// KernelFunCallSoft— SoftCall-lite multi-arg + call-Expr past FunBodySoft
//                    (no imports): I64 a,I64 b + call-site PrsExpr fold plant
//                    (temp IC; body IC preserved): "I64 F(I64 a,I64 b){return a+b;}F(40,2);" /
//                    "I64 F(I64 a){return a+2;}F(38+2);"→42 fold+IC emit; keeps
//                    FunBodySoft/FunDefSoft green; SoftCall-lite — AbiSoft owns
//                    ABI/a0 frame; CocSoft owns COC; no full Compiler.BIN Load →0x4643 'FC'.
// KernelAbiSoft    — SoftCall-lite ABI / runtime local stores (a0 frame) past
//                    FunCallSoft (no imports): prologue sd a0/a1→sp + body ld
//                    from frame + HolyC fp(arg) Call (real a0 ABI; no plant-
//                    at-call): "I64 F(I64 a){return a+2;}F(40);" /
//                    "I64 F(I64 a,I64 b){return a+b;}F(38+2,6-4);"→42 IC emit;
//                    keeps FunCallSoft/FunBodySoft green; SoftCall-lite — CocSoft
//                    owns COC multi-stmt emit; no full Compiler.BIN Load →0x4142 'AB'.
// KernelCocSoft    — SoftCall-lite COC multi-stmt emit past AbiSoft (no imports):
//                    ASSIGN IC → runtime sd + LOCAL ld from frame (not SoftCall
//                    plant-fold): "I64 F(){x=40;return x+2;}F();" /
//                    "I64 F(){x=40;x=x+2;return x;}F();" /
//                    "I64 F(I64 a){x=a+2;return x;}F(40);"→42 COC emit;
//                    keeps AbiSoft/FunCallSoft/FunBodySoft green; SoftCall-lite —
//                    BrSoft owns if/while BR; no full Compiler.BIN Load →0x434F 'CO'.
// KernelBrSoft     — SoftCall-lite if/while BR emit past CocSoft (no imports):
//                    BR_ZERO/JMP/LABEL ICs → runtime taken/not-taken (not SoftCall
//                    plant-fold of body): "I64 F(){x=0;if(1)x=42;return x;}F();" /
//                    "I64 F(){x=42;if(0)x=0;return x;}F();" /
//                    "I64 F(){x=40;while(x-42)x=x+1;return x;}F();"→42 BR emit;
//                    keeps CocSoft/AbiSoft/FunCallSoft/FunBodySoft green; SoftCall-
//                    lite — ElseSoft owns else; no full Compiler.BIN Load →0x4252 'BR'.
// KernelElseSoft   — SoftCall-lite if/else emit past BrSoft (no imports):
//                    then JMP join + else LABEL/ASSIGN + join LABEL (runtime
//                    taken then vs else, not SoftCall plant-fold):
//                    "I64 F(){x=0;if(1)x=42;else x=0;return x;}F();" /
//                    "I64 F(){x=0;if(0)x=0;else x=42;return x;}F();"→42 →0x454C 'EL'.
//                    keeps BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft green;
//                    SoftCall-lite — ForSoft owns for; no full Compiler.BIN Load.
// KernelForSoft    — SoftCall-lite for emit past ElseSoft (no imports):
//                    init/cond/step + body ASSIGN → LABEL/BR_ZERO/JMP (runtime
//                    loop, not SoftCall plant-fold):
//                    "I64 F(){for(x=40;x-42;x=x+1)y=0;return x;}F();"→42 →0x4652 'FR'.
//                    keeps ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft
//                    green; SoftCall-lite — CmpBrSoft owns relational cmp-BR; no full
//                    Compiler.BIN Load.
// KernelCmpBrSoft   — SoftCall-lite relational cmp → BR past ForSoft (no imports):
//                    < > <= >= == != → IC cmp + BR_ZERO (runtime taken/not-taken,
//                    not SoftCall plant-fold):
//                    "I64 F(){x=0;if(x<1)x=42;return x;}F();" /
//                    "I64 F(){x=42;if(x<1)x=0;return x;}F();" /
//                    "I64 F(){for(x=0;x<6;x=x+1)y=0;return x*7;}F();"→42 →0x4342 'CB'.
//                    keeps ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/
//                    FunBodySoft green; SoftCall-lite — CmpSrcSoft owns multi-fun
//                    slice Load past cmp-BR; no SoftCall-lite multi-fun Lex
//                    (that hung ExePutSSoft); no full Compiler.BIN Load.
//                    Full Compiler_RV COC + Compiler.BIN Load remain SoftCall
//                    ceiling (64KiB arena / 2KiB Load; ~1.1MiB BIN).
// KernelCmpSrcSoft  — SoftCall Load of host-AOT multi-fun compound slice past
//                    CmpBrSoft (no SoftCall-lite Lex growth): RedSea SoftCmpSrc.BIN
//                    SoftCmpSrcF+SoftCmpSrcG → SoftCmpSrcProbe→42 →0x4353 'CS'.
//                    SoftCall Load ≤2KiB (not SoftCall-lite PrsCmpSrc; that tip
//                    broke ExePutSSoft via host AOT 32 B entry thunk). keeps
//                    CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/
//                    FunBodySoft green; SoftCall-lite — PrsSrcSoft owns larger
//                    Prs-shaped SoftCall Load past SoftCmpSrc.
// KernelPrsSrcSoft  — SoftCall Load of host-AOT Prs-shaped glbl+multi-fun fold
//                    past CmpSrcSoft: RedSea SoftPrsSrc.BIN SoftPrsAdd/SoftPrsMul
//                    + soft_prs_x → SoftPrsSrcProbe→42 →0x5052 'PR'. SoftCall Load
//                    ≤2KiB (Lex digit SoftCall Load ~2.7KiB over cap; SoftCall-lite
//                    PrsCmpSrc hung ExePutSSoft). keeps CmpSrcSoft + 'FB'/'FC'/
//                    'AB'/'CO'/'BR'/'EL'/'FR'/'CB'/'CS' green; SoftCall-lite —
//                    LexSrcSoft owns LexStmt2Bin SoftCall Load past SoftPrsSrc.
// KernelLexSrcSoft  — SoftCall Load of host-AOT LexStmt2Bin-shaped digit+op peel
//                    past PrsSrcSoft: RedSea SoftLexSrc.BIN SoftLexStmt2Bin +
//                    SoftLexStmt2BinCall → SoftLexSrcProbe→42 →0x4C58 'LX'. SoftCall
//                    Load ≤2KiB (while digit SoftCall Load ~2.7KiB over cap; shrunk
//                    fixed peel). keeps PrsSrcSoft + 'FB'/'FC'/'AB'/'CO'/'BR'/'EL'/
//                    'FR'/'CB'/'CS'/'PR' green; SoftCall-lite — IcSrcSoft owns IC
//                    plant+emit SoftCall Load past SoftLexSrc.
// KernelIcSrcSoft   — SoftCall Load of host-AOT IC plant+emit beyond Lex peel
//                    past LexSrcSoft: RedSea SoftIcSrc.BIN SoftIcEmit (IMM/ADD
//                    plant → RV addi/add+ret+FenceI+Call) → SoftIcSrcProbe→42
//                    →0x4943 'IC'. SoftCall Load ≤2KiB (host AOT <<20 bit-pack
//                    SoftCall Load over cap; SoftCall tip fixed encodings). keeps
//                    LexSrcSoft + 'FB'/'FC'/'AB'/'CO'/'BR'/'EL'/'FR'/'CB'/'CS'/
//                    'PR'/'LX' green; SoftCall-lite — MulSrcSoft owns MUL IC
//                    SoftCall Load past IcSrcSoft.
// KernelMulSrcSoft  — SoftCall Load of host-AOT MUL IC plant+emit beyond
//                    IMM/ADD SoftIcSrc: RedSea SoftMulSrc.BIN SoftMulEmit
//                    (IMM/MUL → RV mul+ret+FenceI+Call) → SoftMulSrcProbe→42
//                    →0x4D55 'MU'. SoftCall Load ≤2KiB (MUL+SUB SoftCall Load
//                    over cap; SoftCall tip fixed encodings; SUB own Load).
//                    keeps IcSrcSoft + 'FB'/'FC'/'AB'/'CO'/'BR'/'EL'/'FR'/
//                    'CB'/'CS'/'PR'/'LX'/'IC' green; SoftCall-lite — SubSrcSoft
//                    owns SUB IC SoftCall Load past MulSrcSoft.
// KernelSubSrcSoft  — SoftCall Load of host-AOT SUB IC plant+emit beyond
//                    IMM/MUL SoftMulSrc: RedSea SoftSubSrc.BIN SoftSubEmit
//                    (IMM/SUB → RV sub+ret+FenceI+Call) → SoftSubSrcProbe→42
//                    →0x5342 'SB'. SoftCall Load ≤2KiB (MUL+SUB one BIN SoftCall
//                    Load over cap; SoftCall tip fixed encodings). keeps
//                    MulSrcSoft + 'FB'/'FC'/'AB'/'CO'/'BR'/'EL'/'FR'/'CB'/
//                    'CS'/'PR'/'LX'/'IC'/'MU' green; SoftCall-lite — OptSrcSoft
//                    owns OptPass fold SoftCall Load past SoftSubSrc.
// KernelOptSrcSoft  — SoftCall Load of host-AOT OptPass fold beyond IMM/SUB
//                    SoftSubSrc: RedSea SoftOptSrc.BIN SoftOptFoldEmit
//                    (IMM/MUL plant → fold IMM42 → RV addi+ret+FenceI+Call)
//                    → SoftOptSrcProbe→42 →0x4F50 'OP'. SoftCall Load ≤2KiB
//                    (SoftCall tip fixed encodings; not SoftMulSrc mul emit).
//                    keeps SubSrcSoft + 'FB'/'FC'/'AB'/'CO'/'BR'/'EL'/'FR'/
//                    'CB'/'CS'/'PR'/'LX'/'IC'/'MU'/'SB' green; SoftCall-lite —
//                    CocSrcSoft owns COC SoftCall Load past SoftOptSrc.
// KernelCocSrcSoft  — SoftCall Load of host-AOT COC multi-stmt ASSIGN beyond
//                    OptPass fold SoftOptSrc: RedSea SoftCocSrc.BIN SoftCocEmit
//                    (ASSIGN/LOCAL/ADD plant → RV frame sd/ld+addi+ret+FenceI+Call)
//                    → SoftCocSrcProbe→42 →0x4F43 'OC'. SoftCall Load ≤2KiB
//                    (SoftCall tip fixed encodings; not SoftOptSrc fold-to-imm).
//                    keeps OptSrcSoft + 'FB'/'FC'/'AB'/'CO'/'BR'/'EL'/'FR'/
//                    'CB'/'CS'/'PR'/'LX'/'IC'/'MU'/'SB'/'OP' green; SoftCall-lite —
//                    BrSrcSoft owns BR SoftCall Load past SoftCocSrc.
// KernelBrSrcSoft   — SoftCall Load of host-AOT BR SoftCall Load beyond COC
//                    ASSIGN SoftCocSrc: RedSea SoftBrSrc.BIN SoftBrEmit
//                    (IMM/BR_ZERO plant → RV addi+beqz+addi+ret+FenceI+Call)
//                    → SoftBrSrcProbe→42 →0x4253 'BS'. SoftCall Load ≤2KiB
//                    (SoftCall tip fixed encodings + tip +2; SoftCall-lite 'BR'
//                    remains BrSoft). keeps CocSrcSoft + 'FB'/'FC'/'AB'/'CO'/
//                    'BR'/'EL'/'FR'/'CB'/'CS'/'PR'/'LX'/'IC'/'MU'/'SB'/'OP'/'OC'
//                    green; SoftCall-lite — ElseSrcSoft owns if/else JMP SoftCall
//                    Load past SoftBrSrc.
// KernelElseSrcSoft — SoftCall Load of host-AOT if/else JMP join SoftCall Load
//                    beyond BR SoftBrSrc: RedSea SoftElseSrc.BIN SoftElseEmit
//                    (IMM/BR_ZERO/JMP plant → RV addi+beqz+JMP+addi+ret+FenceI+Call)
//                    → SoftElseSrcProbe→42 →0x4553 'ES'. SoftCall Load ≤2KiB
//                    (SoftCocSrc tip wrap SoftOptSrc addi42; SoftCall-lite 'EL'
//                    remains ElseSoft). keeps BrSrcSoft + 'FB'/'FC'/'AB'/'CO'/
//                    'BR'/'EL'/'FR'/'CB'/'CS'/'PR'/'LX'/'IC'/'MU'/'SB'/'OP'/'OC'/
//                    'BS' green; SoftCall-lite — ForSrcSoft owns for-loop
//                    SoftCall Load past SoftElseSrc.
// KernelForSrcSoft  — SoftCall Load of host-AOT for-loop SoftCall Load beyond
//                    if/else SoftElseSrc: RedSea SoftForSrc.BIN SoftForEmit
//                    (IMM/COND/BR_ZERO/STEP/JMP-back slots → RV addi+addi+beqz+
//                    addi+JMP+ret+FenceI+Call, runtime count 40→42)
//                    → SoftForSrcProbe→42 →0x4653 'FS'. SoftCall Load ≤2KiB
//                    (const-folded IC slot indices keep tip budget; SoftCall-lite
//                    'FR' remains ForSoft). keeps ElseSrcSoft + 'FB'/'FC'/'AB'/
//                    'CO'/'BR'/'EL'/'FR'/'CB'/'CS'/'PR'/'LX'/'IC'/'MU'/'SB'/
//                    'OP'/'OC'/'BS'/'ES' green; SoftCall-lite — CallIcSoft owns
//                    inter-fun CALL IC past SoftForSrc.
// KernelCallIcSoft  — SoftCall-lite inter-fun CALL IC past ForSrcSoft 'FS' (no
//                    Load slice): (I64 name(){return Expr;})+ name(); plants each
//                    def before the next parses, so a later body naming an earlier
//                    one emits a real RV jal ra under a ra frame (addi sp,-16/sd ra/
//                    jal/ld ra/addi sp,16/ret) — not a plant-time fold.
//                    "I64 G(){return 40;}I64 F(){return G()+2;}F();" →42 →0x434C 'CL'.
//                    Thunk-safe: host-AOT entry-thunk budget held at 456960 B, so
//                    ExePutSSoft 'EP' stays green (SoftCall-lite PrsCmpSrc hung it).
//                    IC_CALL is leftmost-only (jal clobbers a0..a7). keeps ForSrcSoft
//                    + 'FB'/'FC'/'AB'/'CO'/'BR'/'EL'/'FR'/'CB'/'CS'/'PR'/'LX'/'IC'/
//                    'MU'/'SB'/'OP'/'OC'/'BS'/'ES'/'FS' green; SoftCall-lite — glbl
//                    memory (lui/addi abs + ld/sd) owns next.
// KernelGlblMemSoft — SoftCall-lite glbl memory past CallIcSoft 'CL' (no Load
//                    slice): (I64 g;)* (I64 name(){ (g=Expr;)* return Expr; })+
//                    name(); plants real Kernel.BIN storage per decl, and emitted
//                    bodies reach it by absolute address — lui/addi, plus slli/srli
//                    32 to drop the lui sign fill on 0x8xxxxxxx RAM — then ld/sd
//                    through t0/a-reg. Not a frame local and not a plant-time value:
//                    a store in G outlives its frame and is loaded by F after the
//                    jal ra returns, and HolyC reads the same storage back.
//                    OptPass refuses IC_GLBL so it can never be folded.
//                    "I64 g;I64 F(){g=40;return g+2;}F();" →42 →0x474D 'GM'.
//                    keeps CallIcSoft + 'FB'/'FC'/'AB'/'CO'/'BR'/'EL'/'FR'/'CB'/
//                    'CS'/'PR'/'LX'/'IC'/'MU'/'SB'/'OP'/'OC'/'BS'/'ES'/'FS'/'CL'
//                    green; last lite-Cmp primitive — glbl+fun both real now.
// KernelGuestCmpSoft — first real guest Cmp: the source is read off RedSea, not an
//                    in-BIN literal. A:/Compiler/SoftGlbl.HC is Compiler_RV-shaped
//                    HolyC (doc header, three `I64 g_rv_asm_*;` decls, three fun
//                    defs and a trailing `RvAsmExportsSum();`) that exists only on
//                    the disk image. KernelSrcRead walks its clus run multi-blk
//                    (851 B, two sectors — past the 512 B KernelFileRead ceiling),
//                    the lite Lex skips its '//' header, KernelPrsGlblFunDefSoft
//                    Cmps it and the emitted code is Called →42. Sum→Add→Init is a
//                    three-deep jal ra chain whose glbl stores cross both returns.
//                    Proof it came off the disk: the board prints sz + a rolling *31
//                    sum over the bytes it consumed and the smoke recomputes both
//                    host-side over the seed file, plus a gate that no guest ident
//                    appears in Kernel.BIN.
//                    Caps this tip raised: IDENT_MAX 8→24 (real Compiler_RV names),
//                    FUN_MAX 2→4, GLBL_MAX 2→4, FUN_CODE 192→512 (248 B emitted).
//                    PRS_IC_MAX stays 32 — the deepest guest body is 7 IC.
//                    Headroom measured, not assumed: a throwaway 8/8/4096/64 build
//                    (Kernel.BIN 478832 B) also ran the whole chain green, so the
//                    host-AOT entry-thunk budget is not what bounds this tip — the
//                    grammar is. The 456960 B watermark noted on CallIcSoft is stale.
//                    →0x4743 'GC'. keeps GlblMemSoft + the whole lite chain green.
// KernelGuestLocalSoft — frame locals inside a glbl-fun body: the COC statement loop
//                    folded into the glbl grammar, so a body is now
//                    (I64 l[,l]*; | g=Expr; | l=Expr;)* return Expr;. Each `I64 l;`
//                    plants an sp slot at 8.. via KernelLocalPlantAbiSoft and every
//                    use is IC_ASSIGN sd / IC_LOCAL ld — KernelLocalValSoft poisons
//                    abi locals, so no plant-time fold path exists. Emission moves to
//                    KernelEmitGlblICSoft: addi sp,-frame; sd ra,0(sp); body; ld ra;
//                    addi sp,frame; ret, with frame from KernelSoftFrameSizeSoft
//                    (unchanged) clamped to 16 so no-local bodies stay byte-identical
//                    to the CallIC layout. Locals reset per body, so the callee's
//                    slot 0 is a different address from the caller's — proven by
//                    G(){I64 t;t=1;...} not disturbing F's t=41 across the jal ra.
//                    A:/Compiler/SoftLocal.HC carries the same shape off RedSea
//                    (two funs, one glbl, two frame locals), gated on the same
//                    sz + rolling *31 sum + no-guest-ident-in-BIN trio as 'GC'.
//                    Caps unchanged (IDENT_MAX 24, FUN_MAX 4, GLBL_MAX 4,
//                    LOCAL_MAX 4, FUN_CODE 512, PRS_IC_MAX 32) — the board prints
//                    the emitted code bytes (104/512) so the headroom is measured,
//                    not assumed. It also disassembles what it planted and gates on
//                    the encodings: one addi sp,sp,-32 plus sd/ld at 8(sp) and
//                    16(sp) — a frame slot claim checked against real instructions.
//                    →0x474C 'GL'. keeps GuestCmpSoft + the whole lite chain green.
// KernelGuestFlowSoft — if / while / for inside the merged glbl-fun body, so a body
//                    is now Stmt* return Expr; with
//                    Stmt = I64 l[,l]*; | Asg; | if(Expr)Asg;[else Asg;]
//                         | while(Expr)Asg; | for(Asg;Expr;Asg)Asg;.
//                    Control flow reuses the IC_BR_ZERO / IC_JMP / IC_LABEL machinery
//                    the COC path proved; labels are body scoped (KernelEmitICBodySoft
//                    resolves per emit), so the budget is per fun, not per file. Every
//                    init / step / branch body goes through the one shared
//                    KernelPrsGlblAsgSoft an ordinary statement uses, so a branch
//                    stores through IC_ASSIGN / IC_GLBL_ASSIGN and an undeclared
//                    target inside an if still errors -10.
//                    A:/Compiler/SoftFlow.HC carries an OptPass_RV-shaped sweep off
//                    RedSea — a for over g_rv_opt_ic_n slots (5*7=35), a while that
//                    drains 7 down to 1, an if/else that classifies the residue, and
//                    a Fold that sums 35+7=42 across two jal ra — gated on the same
//                    sz + rolling *31 sum + no-guest-ident-in-BIN trio as 'GC'/'GL'.
//                    The branches are proven real by disassembling what was planted:
//                    beq is the only opcode-0x63 form the lite Cmp emits and bit 31
//                    is imm[12], so the board counts three beqz a0 conds, two
//                    backward beq x0,x0 (the for and while back edges) and one
//                    forward one (the else join). A folded branch would emit none.
//                    Caps unchanged (IDENT_MAX 24, FUN_MAX 4, GLBL_MAX 4,
//                    LOCAL_MAX 4, FUN_CODE 512, PRS_IC_MAX 32, LABEL_MAX 8) — the
//                    board prints emitted bytes / deepest IC / deepest label per body
//                    so the headroom is measured, not assumed.
//                    →0x4746 'GF'. keeps GuestLocalSoft + the whole lite chain green.
// KernelGuestPtrSoft — first non-I64 typed values: a `U8 b[N];` file-scope buffer, a
//                    `U8 *p;` cursor, and byte-width deref. A file scope is now
//                    (I64 g; | U8 *p; | U8 b[N];)* and an assign target is now
//                    (l|g|p) = Expr | *Factor = Expr. An array name decays to its
//                    buffer address (IC_GLBL_ADDR — abs materialize, no ld, so the
//                    lite RPN stack carries a pointer instead of a cell read), `*p`
//                    is IC_LOAD_U8 (lbu rd,0(rd)) and `*p = Expr;` is IC_STORE_U8
//                    (sb rs2,0(rs1)). Deref goes through the one shared
//                    KernelPrsGlblAsgSoft, so a `*p = ...` inside an if / for body is
//                    the same store a top-level statement emits. KernelOptPassSoft
//                    has no arm for any of the three, so it poisons on sight exactly
//                    as it does for IC_GLBL — no plant-time fold path exists. Byte
//                    width is load-bearing: 298 stored through `*p` reads back 42.
//                    A:/Compiler/SoftPtr.HC carries a Lex.HC-shaped char walk off
//                    RedSea — Seed writes 20,22,0 through the cursor and Walk runs
//                    `for (p = buf; *p; p = p + 1) n = n + *p;` back to 42 — gated on
//                    the same sz + rolling *31 sum + no-guest-ident-in-BIN trio as
//                    'GC'/'GL'/'GF', plus a disassembly of the encodings planted:
//                    two lbu, three sb, sixteen srli x,x,32 (one per absolute address
//                    materialize). A folded walk would emit none of them.
//                    Cap raised this tip: FUN_CODE 512→1024 — the walk pays 16 B per
//                    glbl touch on a 0x8xxxxxxx address. PRS_IC_MAX stays 32 (the
//                    deepest body is 22 IC) and IDENT_MAX/FUN_MAX/GLBL_MAX/LOCAL_MAX/
//                    LABEL_MAX are unchanged; the board prints the watermarks.
//                    →0x4750 'GP'. keeps GuestFlowSoft + the whole lite chain green.
// KernelGuestTypeSoft — non-I64 return / arg widths plus arity 4, the survey's top
//                    two blockers (212 of 225 Compiler_RV functions return U0, Bool,
//                    U32 or a pointer; fun-args-blocked only falls 162→63 at four
//                    args). A signature is now RType name(AType a[,...×4]) with
//                    RType = I64|U0|Bool|U32|U8 *|C8 * and AType the same minus U0.
//                    Widths are the callee's business at both ends and no call site
//                    knows them: a Bool / U32 arg is narrowed in the prologue before
//                    its spill, and a Bool / U32 return after the body. Bool is a
//                    real snez (298 comes back as 1, not 298 and not the 42 a byte
//                    narrowing would give); U32 is slli/srli 32, so it is 4 bytes
//                    wide *and* unsigned (2^32+42 truncates to 42, 2^31+42 stays
//                    positive where srai would give -2147483606).
//                    U0 is the one type with no value: it cannot appear in an Expr,
//                    so it is reached by a statement call, and IC_CALL_U0 puts the
//                    lite RPN stack back to empty where IC_CALL leaves it at depth 1.
//                    A U0 body may `return;` or simply run out of statements, and an
//                    I64 body that runs out is an error rather than a garbage a0.
//                    Args 3 and 4 ride a2 / a3 through the same jal ra, spilled to
//                    24(sp) / 32(sp) by the same prologue; nargs==0 with an I64
//                    return still emits nothing extra at either end, so every shape
//                    from the tips before 'GA' stays byte-identical.
//                    A:/Compiler/SoftType.HC carries a BackLib_RV-shaped field packer
//                    off RedSea — a four-argument U0 whose arg registers each carry a
//                    distinct weight (26 for (1,2,3,4), 49 for (4,3,2,1)), a Bool
//                    predicate, a U32 straddling bit 31 and 2^32, and a U8 * handing
//                    a buffer address back — gated on the same sz + rolling *31 sum +
//                    no-guest-ident-in-BIN trio as 'GC'/'GL'/'GF'/'GP'/'GA', plus six
//                    exact instruction sequences: the Bool and U32 return narrowings
//                    in the epilogue, the U0 no-value tail, the a1/a2/a3 spill run,
//                    the a2/a3 call setup, and the U32 arg narrowing ahead of its
//                    spill. Each is a three-word sequence because every one of those
//                    instructions is ambiguous on its own — `sltu a0,x0,a0` is also
//                    how `!=` ends and `slli/srli a0,a0,32` is also how an absolute
//                    address materialize ends.
//                    Caps raised this tip: ARG_MAX 2→4, LOCAL_MAX 4→8 (four args plus
//                    two working locals is six slots) and FUN_MAX 4→8 (one fun per
//                    return type plus an entry is seven). FUN_CODE stays 1024 (692 B
//                    emitted), PRS_IC_MAX stays 32 (25 IC), LABEL_MAX stays 8 and
//                    GLBL_MAX stays 4; the board prints every watermark, including
//                    the frame-local count arity 4 actually squeezes.
//                    →0x4754 'GT'. keeps GuestArgSoft + the whole lite chain green.
// KernelDateSoft   — SoftCall KDate ownership (no imports): YearStartDate +
//                    Struct2Date↔Date2Struct + DayOfWeek + Goldfish RTC Now
//                    (past thin KThinDateStubs) →0x4B47 'KG'. Packs Kernel_RV
//                    KDate.HC calendar shape into RedSea Kernel.BIN.
// KernelQSortSoft  — SoftCall QSort ownership (no imports): QSortI64 ascending
//                    + already-sorted + singleton (past thin KThinQSortStubs)
//                    →0x4B4F 'KO'. Packs Kernel_RV QSort.HC I64 shape into
//                    RedSea Kernel.BIN (DirEntry sort path; 'KQ' is TrapIRQ).
// KernelKeyDevSoft — SoftCall KeyDev ownership (no imports): PutKey/PutS chain +
//                    KeyDevAdd priority + KeyDevRem + CtrlAltCBSet lite (past
//                    thin KThinKeyDevStubs; no SCROLL Yield / KDRaw / Msg)
//                    →0x4B57 'KW'. Packs Kernel_RV KeyDev.HC StdOut shape into
//                    RedSea Kernel.BIN.
// KernelExceptSoft — SoftCall KExcept ownership (no imports): SysTry/SysUntry
//                    queue + throw walk + PutExcept catch flag (past thin
//                    KThinMapFatStubs PutExcept; no x86 TestExcept/TakeExcept
//                    asm unwind) →0x4B5A 'KZ'. Packs Kernel_RV KExcept.HC
//                    try/throw/catch HolyC shape into RedSea Kernel.BIN.
// KernelMemSoft    — SoftCall HeapCtrl+MAlloc ownership (no imports): HeapCtrl
//                    hash-bucket Free→reuse + MSize + CAlloc + StrNew (past
//                    thin KThinMemStubs linear arena; no MemPag/PageTables/
//                    BlkPool) →0x4B48 'KH'. Packs Kernel_RV HeapCtrl/MAllocFree
//                    HolyC shape into RedSea Kernel.BIN (HIT magic also 'KH').
// KernelStrUtilSoft— SoftCall StrUtil/MStrUtil ownership (no imports): path
//                    normalize SUF_REM_LEADING|TRAILING|CTRL_CHARS + TO_UPPER/
//                    TO_LOWER/REM_SPACES/SINGLE_SPACE (past thin
//                    KThinStrUtilStubs; no Spaces2Tabs/T2S/ScaleIndent/char_bmp)
//                    →0x5355 'SU'. Packs Kernel_RV StrA/StrB HolyC shape into
//                    RedSea Kernel.BIN (path normalize used by MakeBlkDev).
// KernelFifoSoft   — SoftCall SerialDev Fifo ownership (no imports): FifoU8 +
//                    FifoI64 New/Ins/Rem/Peek/Flush/Cnt/Del (past thin
//                    KThinMapFatStubs Fifo*; Serial MakeSerialDev gated —
//                    InputFilterTask stays thin stub wall; prefer Fifo SoftCall)
//                    →0x5346 'SF'. Packs Kernel_RV KDataTypes.HC Fifo HolyC
//                    shape into RedSea Kernel.BIN (no x86 PUSHFD/CLI).
// KernelQueVectSoft— SoftCall QueVectU8 ownership (no imports): New/Put/Get/Del
//                    + multi-node grow + min_idx (past thin KThinMapFatStubs
//                    QueVect*; SoftCall-local CNT=8, stock algorithm/shape)
//                    →0x5156 'QV'. Packs Kernel_RV KDataTypes.HC QueVect HolyC
//                    shape into RedSea Kernel.BIN (Lex needs QueVect).
// KernelRandSoft   — SoftCall KMathB Rand/Seed ownership (no imports): LCG
//                    Seed(n) nontimer + RandI16/U16/I32/U32/I64/U64 repeat
//                    (past thin KThinMapFatStubs Rand*; SoftCall-local seed —
//                    no Fs/GetTSC; Seed(0) clears nontimer + soft-tick xor)
//                    →0x524E 'RN'. Packs Kernel_RV KMathB.HC Rand HolyC shape
//                    into RedSea Kernel.BIN; F64 Rand() deferred.
// KernelScanFlagsSoft— SoftCall ScanFlags/LstMatch ownership (no imports):
//                    SoftCall-lite LstMatch exact + ScanFlags +/- bit set/clear
//                    + StrPrintFlags reverse (past thin KThinMapFatStubs
//                    ScanFlags/StrPrintFlags; stack buf — no MAlloc; unknown
//                    flag returns FALSE — no throw; LMF_IGNORE_CASE/ambiguous
//                    deferred) →0x5343 'SC'. Packs Kernel_RV StrA/StrB
//                    ScanFlags HolyC shape into RedSea Kernel.BIN.
// KernelCompressSoft— SoftCall Compress/Expand ownership (no imports):
//                    SoftCall-lite ArcCompressBuf/ExpandBuf + CompressBuf/
//                    ExpandBuf roundtrip (past thin Compress gate; SoftCall-
//                    local ARC_BITS=9 — stock 12 ~96 KiB BSS won't fit;
//                    HolyC BFieldOr/Ext — no asm; no throw) →0x434D 'CM'.
//                    Packs Kernel_RV Compress.HC Arc HolyC shape into Kernel.BIN.
// KernelKLoadSoft  — SoftCall KLoad ownership (no imports): SoftCall-lite
//                    LoadPass1 past JumpSoft/ExeSoft export-only — IMM32_EXPORT
//                    + IET_IMM_I64 LoadOneImport resolve + IET_ABS_ADDR U64
//                    +=module_base (synthetic patch table; SoftCall-lite import
//                    group stops before ABS/MAIN — stock uses END/named; no
//                    FileRead/ExtDft/CODE_HEAP/DATA_HEAP/MAIN Call; no throw)
//                    →0x4C44 'LD'. Packs Kernel_RV KLoad.HC LoadPass1 HolyC
//                    shape into RedSea Kernel.BIN. (BlkDev SoftCall skipped:
//                    RedSea+virtio ENTER already SoftCalled; full MakeBlkDev
//                    ~177 KiB won't fit SoftCall seed.)
// KernelLoadMainSoft— SoftCall KLoad MAIN/CODE_HEAP/FileRead ownership (no
//                    imports): SoftCall-lite IET_CODE_HEAP ArenaAlloc+I32 patch
//                    + HashAdd export + LoadPass2 IET_MAIN Call + FileRead of
//                    planted SOFTFW.OK feeding CODE_HEAP LoadPass1 (past
//                    KLoadSoft import+ABS; SoftCall-lite — DataHeapSoft owns
//                    ExtDft.Z / DATA_HEAP / ZEROED_*; A:/Kernel/ CDir full so no
//                    new FileWrite; ExeSoft already owns RedSea export Call)
//                    →0x4C4D 'LM'. Packs Kernel_RV KLoad.HC LoadPass1 CODE_HEAP
//                    + LoadPass2 MAIN + Load FileRead HolyC shape into RedSea
//                    Kernel.BIN.
// KernelDataHeapSoft— SoftCall KLoad DATA_HEAP/ZEROED_*/ExtDft.Z ownership (no
//                    imports): SoftCall-lite IET_DATA_HEAP ArenaAlloc+I64 patch
//                    + HashAdd + ZEROED_CODE/DATA_HEAP CAlloc MemSet + ExtDft
//                    ("SOFTFW"→"SOFTFW.BIN.Z"; identity ExtDft of SOFTFW.OK→
//                    FileRead Load shape; past LoadMainSoft CODE_HEAP+MAIN;
//                    SoftCall-lite stack ExtDft — no MAlloc/CatPrint; A:/Kernel/
//                    CDir full so no new FileWrite; no throw; LoadAbsSoft owns
//                    full Load() FileNameAbs+align) →0x4448 'DH'. Packs
//                    Kernel_RV KLoad.HC DATA_HEAP + ZEROED_* + DskStrA ExtDft
//                    HolyC shape into RedSea Kernel.BIN.
// KernelLoadAbsSoft— SoftCall full Load() FileNameAbs+module_align ownership
//                    (no imports): SoftCall-lite FileNameAbs drive-abs identity
//                    + cur_dir join; FileExtRem; HTT_MODULE HashGenericAdd;
//                    MAllocAligned from module_align_bits (min 16; misalignment
//                    stock shape); LoadPass copy→Pass1; ExtDft+FileNameAbs+
//                    FileRead LoadProbe→aligned LoadPass+MODULE+export Find
//                    (past DataHeapSoft ExtDft.Z; SoftCall-lite — no throw;
//                    DirAbsSoft owns FUF_Z_OR_NOT_Z/DirNameAbs parents/MAlloc
//                    ExtDft; A:/Kernel/ CDir full)
//                    →0x4C41 'LA'. Packs Kernel_RV KLoad.HC Load()+LoadPass
//                    FileNameAbs/align/MODULE + DskStrA FileNameAbs HolyC shape
//                    into RedSea Kernel.BIN.
// KernelDirAbsSoft — SoftCall DirNameAbs parents + FUF_Z_OR_NOT_Z + MAlloc
//                    ExtDft ownership (no imports): SoftCall-lite DirNameAbs
//                    `..`/`.` resolve + FileNameAbs-via-DirNameAbs; ToggleZorNotZ
//                    + FileFind Z-or-not-Z alt; ArenaAlloc ExtDft (stock MAlloc
//                    shape; past LoadAbsSoft stack ExtDft/no-parents; no throw;
//                    no ~ home / FUF_SCAN_PARENTS Cd walk) →0x444E 'DN'. Packs
//                    Kernel_RV DskStrA DirNameAbs/FileNameAbs/ExtDft + DskFind
//                    ToggleZ HolyC shape into RedSea Kernel.BIN.
// KernelMakeMemSoft— SoftCall MakeMem ownership (no imports): SoftCall-lite
//                    BlkPoolInit/Add + MemPagAlloc/Free + MemPagTaskAlloc/Free
//                    (past thin KThinMemStubs MemPag/BlkPool NULLs; MemSoft
//                    already owns HeapCtrl hash-bucket; FREE_PAG_HASH=0x100
//                    stock-sized free_pag_hash + mid-slot prove; Hash2Soft owns
//                    free_pag_hash2 SoftCall-lite; no CLI/LBts; PhysMemSoft owns
//                    PageTables/MemPhysical/BlkPoolsInit lite; no FB/WinMgr —
//                    RVWinMgr ~120 KiB src) →0x4D4D 'MM'. Packs Kernel_RV
//                    MemPag/BlkPool HolyC shape into RedSea Kernel.BIN.
// KernelPhysMemSoft— SoftCall PageTables/MemPhysical/BlkPoolsInit ownership
//                    (no imports): SoftCall-lite MemPageTable PTE slot +
//                    BlkPoolsInit (synthetic E820 → extend code_bp + data_bp) +
//                    Mem32DevIns/Init/Alloc/Free + BIOSTotalMem + Scale2Mem
//                    (past MakeMemSoft MemPag/BlkPool; SoftCall-local PTE[16] —
//                    no x86 SYS_INIT_PAGE_TABLES asm / Sv39; no Mem64Dev/
//                    UncachedAlias/InvlPg; no real BIOS E820; no CLI/LBts)
//                    →0x504D 'PM'. Packs Kernel_RV BlkPoolsInit+MemPageTable+
//                    MemPhysical HolyC shape into RedSea Kernel.BIN.
// KernelHash2Soft  — SoftCall MemPag free_pag_hash2 ownership (no imports):
//                    FREE_PAG_HASH2=55 (stock 64-MEM_PAG_BITS) + EXTRA_HASH2_PAGS=2
//                    + Bsr round power-of-two Free→hash2→Alloc reuse (past
//                    MakeMemSoft stock FREE_PAG_HASH=0x100; SoftCall-local
//                    HASH2_FREE_PAG_HASH=8 threshold — stock 0x100 hash2 trigger
//                    needs ≥130-pag arena, deferred; SoftCall-local arena 32
//                    pags; no CLI/LBts) →0x4832 'H2'. Packs Kernel_RV MemPag.HC
//                    free_pag_hash2 HolyC shape into RedSea Kernel.BIN.
//                    Compress ARC_BITS=12 SoftCall deferred (~96 KiB BSS).
// KernelVirtioProbe— in-BIN virtio-mmio magic+blk DeviceID scan (→0x4B56 'KV').
// KernelInitLite   — UART + probes + TrapSoft + RAM magic @ KERNEL_BIN_MAGIC_ADDR (→0x4B49).
// KernelSoftCall   — BIN ENTER: driver Init + mount/FS/Load/Call + TaskSoft +
//                    TrapOwn + TrapIrq + TrapTimer + TrapDisp + HashSoft +
//                    PrintSoft + YieldSoft + JumpSoft + ExeSoft + MakeSoft +
//                    SeedSoft + SvcSoft + KernSoft + StartSoft + AdamSoft +
//                    DateSoft + QSortSoft + KeyDevSoft + ExceptSoft + MemSoft +
//                    StrUtilSoft + FifoSoft + QueVectSoft + RandSoft +
//                    ScanFlagsSoft + CompressSoft + KLoadSoft + MakeMemSoft +
//                    PhysMemSoft + LoadMainSoft + Hash2Soft + DataHeapSoft +
//                    LoadAbsSoft + DirAbsSoft + StartOSSoft + ExePutSSoft +
//                    CmpSoft + LexStmtSoft + PrsOptSoft + ParenSoft + IdentSoft +
//                    AssignSoft + FunDefSoft + FunBodySoft + FunCallSoft +
//                    AbiSoft + CocSoft + BrSoft + ElseSoft + ForSoft +
//                    CmpBrSoft + CmpSrcSoft + PrsSrcSoft + LexSrcSoft + IcSrcSoft
//                    + MulSrcSoft + SubSrcSoft + OptSrcSoft + CocSrcSoft
//                    (→0x4B53); plants SOFTFW.OK + BLKIO.OK + CALL.OK.
//                    TrapPlic SoftCall deferred (host-fed hangs).
// KernelEntry      — handoff: Probe+InitLite →0x4B45 when called (phase3). If
//                    KERNEL_BIN_STAY_ADDR==STAY, SoftCall then halt (thin Jump).
#ifndef CONFIG_UART_BASE
#define CONFIG_UART_BASE 0x10000000
#endif
#ifndef CONFIG_RTC_BASE
#define CONFIG_RTC_BASE 0x00101000
#endif
#define KERNEL_MBR_PT_REDSEA 0x88
#define KERNEL_RS_ATTR_DIR 0x10
#define KERNEL_RS_ATTR_DELETED 0x100
#define KERNEL_RS_ATTR_CONTIGUOUS 0x800
#define KERNEL_CDIR_SIZE 64
#define KERNEL_BIN_SIGNATURE_VAL 'TOSB'
#define KERNEL_CBIN_HDR 32
#define KERNEL_IET_END 0
#define KERNEL_IET_REL_I0 2
#define KERNEL_IET_IMM_I64 11
#define KERNEL_IET_REL32_EXPORT 16
#define KERNEL_IET_IMM32_EXPORT 17
#define KERNEL_IET_REL64_EXPORT 18
#define KERNEL_IET_IMM64_EXPORT 19
#define KERNEL_IET_ABS_ADDR 20
#define KERNEL_IET_CODE_HEAP 21
#define KERNEL_IET_ZEROED_CODE_HEAP 22
#define KERNEL_IET_DATA_HEAP 23
#define KERNEL_IET_ZEROED_DATA_HEAP 24
#define KERNEL_IET_MAIN 25
// Scratch under SYS_FIXED_AREA host-slots band; thin loader reads after Call.
#ifndef KERNEL_BIN_MAGIC_ADDR
#define KERNEL_BIN_MAGIC_ADDR 0x8700E000
#endif
#define KERNEL_BIN_MAGIC_VAL 0x4B494E49
// 'KINI'
#ifndef KERNEL_BIN_STAY_ADDR
#define KERNEL_BIN_STAY_ADDR 0x8700E008
#endif
#define KERNEL_BIN_STAY_VAL 0x53544159
// 'STAY'
#ifndef KERNEL_BIN_ENTRY_ADDR
#define KERNEL_BIN_ENTRY_ADDR 0x8700E010
#endif
#ifndef KERNEL_EMBED_ADDR
#define KERNEL_EMBED_ADDR 0x81000000
#endif
// TrapCtx SoftCall hook slot + HIT (trap.hc-style; thin/Entry scratch band).
#ifndef KERNEL_TRAP_HOOK_ADDR
#define KERNEL_TRAP_HOOK_ADDR 0x8700E018
#endif
#ifndef KERNEL_TRAP_HIT_ADDR
#define KERNEL_TRAP_HIT_ADDR 0x8700E020
#endif
#ifndef KERNEL_TRAP_CLAIM_ADDR
#define KERNEL_TRAP_CLAIM_ADDR 0x8700E028
#endif
#define KERNEL_TRAP_HIT_MAGIC 0x4B48
// 'KH' — HolyC KernelTrapDispatch ran
// Claimed PLIC IRQ id planted by KernelTrapDispatch on EXT (0 = none).
// Product heap window (RVAutoConf CONFIG_HEAP_BASE) — not in-BIN BSS.
// Thin bootstrap bump ends at 0x86000000; SoftCall owns this region after Jump.
#ifndef KERNEL_HEAP_BASE
#define KERNEL_HEAP_BASE 0x86000000
#endif
#define KERNEL_ARENA_SIZE 65536
// 64 KiB product heap (first-fit freelist + bump; was LIFO-only)
#define KERNEL_FHDR 16
// chunk hdr: size + next (16 B aligned)
#define KERNEL_MCAUSE_ECALL_M 11
#define KERNEL_MCAUSE_IRQ_M_SOFT 0x8000000000000003
// interrupt|3 — machine software IRQ (CLINT MSIP)
#define KERNEL_MCAUSE_IRQ_M_TIMER 0x8000000000000007
// interrupt|7 — machine timer IRQ (CLINT mtimecmp)
#define KERNEL_MCAUSE_IRQ_M_EXT 0x800000000000000B
// interrupt|11 — machine external IRQ (PLIC)
#define KERNEL_TRAP_GPR_MAGIC 0x47505246
// 'GPRF' — t0 marker; handler clobbers t0 without save/restore
#ifndef KERNEL_CLINT_MSIP
#define KERNEL_CLINT_MSIP 0x02000000
#endif
#ifndef KERNEL_CLINT_MTIMECMP
#define KERNEL_CLINT_MTIMECMP 0x02004000
#endif
#ifndef KERNEL_CLINT_MTIME
#define KERNEL_CLINT_MTIME 0x0200BFF8
#endif
#ifndef KERNEL_PLIC_BASE
#define KERNEL_PLIC_BASE 0x0C000000
#endif
#ifndef KERNEL_PLIC_ENABLE_OFF
#define KERNEL_PLIC_ENABLE_OFF 0x2000
#endif
#ifndef KERNEL_PLIC_THRESHOLD_OFF
#define KERNEL_PLIC_THRESHOLD_OFF 0x200000
#endif
#ifndef KERNEL_PLIC_CLAIM
#define KERNEL_PLIC_CLAIM 0x0C200004
#endif
// QEMU virt hart0 M-mode claim/complete (MEM_PLIC+MEM_PLIC_CLAIM_OFF)
#ifndef KERNEL_UART_IRQ
#define KERNEL_UART_IRQ 10
#endif
// QEMU virt 16550 → PLIC IRQ 10 (CONFIG_UART_IRQ)
#ifndef CONFIG_VIRTIO_MMIO_IRQ_BASE
#define CONFIG_VIRTIO_MMIO_IRQ_BASE 0x10000000
#endif
#ifndef CONFIG_VIRTIO_MMIO_STRIDE
#define CONFIG_VIRTIO_MMIO_STRIDE 0x1000
#endif
#define KERNEL_VMR_INTERRUPT_STATUS 0x60
#define KERNEL_VMR_INTERRUPT_ACK 0x64
// virtio-mmio: IRQ = (base - IRQ_BASE) >> 12 → PLIC 1..8; ACK or storm
class CKernelFree
{
  I64 size;
  CKernelFree *next;
};
U8 *kernel_bin_arena = KERNEL_HEAP_BASE;
I64 kernel_bin_arena_next = 0;
CKernelFree *kernel_bin_freelist = NULL;
// Import-free trap CSR probe: plant csrr+ret in writable U32[] and jalr.
U32 kernel_csr_stub[2];
public I64 KernelProbe()
{
  return 42;
}

U0 KernelUart(U8 *msg)
{
  U8 *uart = CONFIG_UART_BASE;
  if (!msg)
    return;
  while (*msg)
    *uart = *msg++;
}
// 16550 LSR @ +5: DR bit0. Soft RX ownership (non-blocking poll only).
Bool KernelUartRxReady()
{
  U8 *lsr = CONFIG_UART_BASE + 5;
  return (*lsr & 1) != 0;
}

I64 KernelUartGetC()
{
  U8 *uart = CONFIG_UART_BASE;
  if (!KernelUartRxReady)
    return -1;
  return *uart & 0xFF;
}
// In-BIN ports of KUtilsRV mem surface (pack Kernel_RV-shaped code, no imports).
I64 KernelStrLen(U8 *s)
{
  I64 n = 0;
  if (!s)
    return 0;
  while (*s++)
    n++;
  return n;
}

U0 KernelMemSet(U8 *dst, U8 val, I64 n)
{
  I64 i;
  if (!dst || n <= 0)
    return;
  for (i = 0; i < n; i++)
    dst[i] = val;
}

U0 KernelMemCpy(U8 *dst, U8 *src, I64 n)
{
  I64 i;
  if (!dst || !src || n <= 0)
    return;
  for (i = 0; i < n; i++)
    dst[i] = src[i];
}

I64 KernelArenaNeed(I64 size)
{
  return (size + KERNEL_FHDR + 15) & ~15;
}

U8 *KernelArenaAlloc(I64 size)
{
  I64 need;
  U8 *p;
  CKernelFree *f, *prev;
  if (size <= 0 || !kernel_bin_arena)
    return NULL;
  need = KernelArenaNeed(size);
  // First-fit freelist (non-LIFO hole reuse — Kernel_RV-shaped).
  f = kernel_bin_freelist;
  prev = NULL;
  while (f) {
    if (f->size >= need) {
      if (prev)
        prev->next = f->next;
      else
        kernel_bin_freelist = f->next;
      f->next = NULL;
      return f(U8 *) + KERNEL_FHDR;
    }
    prev = f;
    f = f->next;
  }
  // Fresh bump from product window.
  if (kernel_bin_arena_next + need > KERNEL_ARENA_SIZE)
    return NULL;
  p = kernel_bin_arena + kernel_bin_arena_next;
  kernel_bin_arena_next += need;
  f = p(CKernelFree *);
  f->size = need;
  f->next = NULL;
  return p + KERNEL_FHDR;
}
// Freelist free: tip coalesces into bump; else push first-fit list.
// size arg is caller payload size (hdr size wins if mismatch).
U0 KernelArenaFree(U8 *p, I64 size)
{
  CKernelFree *f;
  I64 need;
  if (!p || size <= 0 || !kernel_bin_arena)
    return;
  f = (p - KERNEL_FHDR)(CKernelFree *);
  need = KernelArenaNeed(size);
  if (f->size < KERNEL_FHDR || (f->size != need && f->size < need))
    f->size = need;
  if (f(U8 *) + f->size == kernel_bin_arena + kernel_bin_arena_next) {
    kernel_bin_arena_next -= f->size;
    return;
  }
  f->next = kernel_bin_freelist;
  kernel_bin_freelist = f;
}

U0 KernelArenaReset()
{
  kernel_bin_arena = KERNEL_HEAP_BASE;
  kernel_bin_arena_next = 0;
  kernel_bin_freelist = NULL;
  // Touch first page only — full 64 KiB MemSet is unnecessary for probe/SoftCall.
  KernelMemSet(kernel_bin_arena, 0, 4096);
}

public I64 KernelHeapProbe()
{
  U8 *p, *q, *r, *s, *a, *b, *c, *d;
  U8 tmp[64];
  KernelArenaReset;
  p = KernelArenaAlloc(64);
  if (!p)
    return -1;
  KernelMemSet(p, 0xA5, 64);
  KernelMemCpy(tmp, p, 64);
  if (tmp[0] != 0xA5 || tmp[63] != 0xA5)
    return -2;
  q = KernelArenaAlloc(32);
  if (!q)
    return -3;
  if (KernelStrLen("KE") != 2)
    return -4;
  // Prove product heap beyond prior 4 KiB in-BIN bump: 16 KiB chunk @ HEAP_BASE.
  r = KernelArenaAlloc(16384);
  if (!r)
    return -5;
  if (r <= q)
    return -6;
  KernelMemSet(r, 0x5A, 16384);
  if (r[0] != 0x5A || r[16383] != 0x5A)
    return -7;
  // User payload starts after 16 B hdr (was bare bump @ HEAP_BASE).
  if (p != KERNEL_HEAP_BASE + KERNEL_FHDR)
    return -8;
  // Tip coalesce + second large alloc within 64 KiB window.
  KernelArenaFree(r, 16384);
  s = KernelArenaAlloc(32768);
  if (!s)
    return -9;
  if (s != r)
    return -10;
  KernelMemSet(s, 0xC3, 32768);
  if (s[0] != 0xC3 || s[32767] != 0xC3)
    return -11;
  KernelArenaFree(s, 32768);
  // Freelist hole reuse (non-LIFO): free middle while tip live.
  a = KernelArenaAlloc(64);
  b = KernelArenaAlloc(128);
  c = KernelArenaAlloc(64);
  if (!a || !b || !c)
    return -12;
  if (c <= b || b <= a)
    return -13;
  KernelArenaFree(b, 128);
  d = KernelArenaAlloc(128);
  if (!d)
    return -14;
  if (d != b)
    return -15;
  KernelMemSet(d, 0xE1, 128);
  if (d[0] != 0xE1 || d[127] != 0xE1)
    return -16;
  if (a[0] == 0xE1 || c[0] == 0xE1)
    return -17;
  return 64;
}

I64 KernelCsrRead(I64 csr_insn)
{
  I64 (*fp)();
  kernel_csr_stub[0] = csr_insn;
  kernel_csr_stub[1] = 0x00008067;
  // ret
  fp = &kernel_csr_stub;
  return fp();
}

public I64 KernelTrapProbe()
{
  I64 hart, st, isa;
  // csrr a0, mhartid / mstatus / misa
  hart = KernelCsrRead(0xF1402573);
  st = KernelCsrRead(0x30002573);
  isa = KernelCsrRead(0x30102573);
  // QEMU virt M-mode: mhartid==0; misa nonzero; mstatus read must complete.
  if (hart != 0)
    return -1;
  if (!isa)
    return -2;
  if (st == -1 && isa == -1)
    return -3;
  return 0x4B54;
}
// Soft trap ownership (InitLite only): TrapCtx GPR frame (trap.hc layout) +
// IRQ fast-path (mcause<0 → SoftCall HolyC KernelTrapDispatch + restore/mret) +
// M-ecall gate (cause==11→mscratch, mepc+=4). CLINT MSIP/mtimecmp clear and
// PLIC claim/complete live in HolyC (asm does not clear before SoftCall).
// Prior mid-SoftCall ecall broke Cap/Read — keep away from VBlk. SoftCall
// TrapIrq/TrapTimer/TrapDisp live-fire IRQs. Pattern mirrors trap.hc
// TrapBareMtvec: clear MIE/mie, csrw mtvec, fence.i. SoftCall encodings
// gas-checked (riscv64-unknown-elf-as).
U32 kernel_trap_vec[64];
U32 kernel_csr_wstub[8];
U32 kernel_ecall_stub[6];
U0 KernelCsrWrite(I64 csr_insn, I64 val)
{
  I64 (*fp)(I64);
  // a0=val; csr_insn uses a0 as src (e.g. csrw mtvec,a0 = 0x30551073)
  kernel_csr_wstub[0] = csr_insn;
  kernel_csr_wstub[1] = 0x00008067;
  // ret
  fp = &kernel_csr_wstub;
  fp(val);
}

U0 KernelFenceI()
{
  I64 (*fp)();
  // fence.i then ret — separate from CSR stubs
  kernel_csr_wstub[0] = 0x0000100F;
  kernel_csr_wstub[1] = 0x00008067;
  fp = &kernel_csr_wstub;
  fp();
}

U32 KernelInU32(I64 addr)
{
  return *(addr(U32 *));
}

U0 KernelOutU32(I64 addr, U32 val)
{
  *(addr(U32 *)) = val;
}
// HolyC TrapDispatch — TrapCtx IRQ SoftCalls via KERNEL_TRAP_HOOK_ADDR.
// Owns CLINT MSIP/timer clear + PLIC claim/complete (+ UART IER clear +
// virtio-mmio InterruptACK on #1..8 + #10 enable-drop). Live SoftCall PLIC
// raise still unwired (host-fed RX + asm EXT clear hung).
I64 KernelTrapDispatch(I64 cause)
{
  I64 *hit, *mtimecmp, *claim_slot;
  U32 *msip, *claim, *en;
  U8 *ier;
  I64 irq, vbase, st;
  if (cause == KERNEL_MCAUSE_IRQ_M_SOFT) {
    msip = KERNEL_CLINT_MSIP;
    *msip = 0;
  } else if (cause == KERNEL_MCAUSE_IRQ_M_TIMER) {
    mtimecmp = KERNEL_CLINT_MTIMECMP;
    *mtimecmp = -1;
  } else if (cause == KERNEL_MCAUSE_IRQ_M_EXT) {
    // Kill UART source first — claim==0 + IER still on storms MEI forever.
    ier = CONFIG_UART_BASE + 1;
    *ier = 0;
    claim = KERNEL_PLIC_CLAIM;
    irq = *claim;
    claim_slot = KERNEL_TRAP_CLAIM_ADDR;
    *claim_slot = irq;
    en = KERNEL_PLIC_BASE + KERNEL_PLIC_ENABLE_OFF;
    if (irq >= 1 && irq <= 8) {
      vbase = CONFIG_VIRTIO_MMIO_IRQ_BASE + irq *CONFIG_VIRTIO_MMIO_STRIDE;
      st = KernelInU32(vbase + KERNEL_VMR_INTERRUPT_STATUS);
      KernelOutU32(vbase + KERNEL_VMR_INTERRUPT_ACK, st);
      *en = *en & ~(1 << irq);
    } else if (irq == KERNEL_UART_IRQ) {
      *en = *en & ~(1 << KERNEL_UART_IRQ);
    }
    if (irq)
      *claim = irq;
  }
  hit = KERNEL_TRAP_HIT_ADDR;
  *hit = KERNEL_TRAP_HIT_MAGIC;
  return cause;
}

U0 KernelTrapHookPlant()
{
  I64 *hook, *hit;
  hook = KERNEL_TRAP_HOOK_ADDR;
  hit = KERNEL_TRAP_HIT_ADDR;
  *hook = &KernelTrapDispatch;
  *hit = 0;
}
// Plant TrapCtx: save 17 GPRs, mcause→mscratch, IRQ SoftCall/ecall/hang, restore, mret.
U0 KernelTrapVecPlant()
{
  // addi sp,sp,-144
  kernel_trap_vec[0] = 0xF7010113;
  // sd ra/t0-t6/a0-a7/s0 (trap.hc offsets)
  kernel_trap_vec[1] = 0x00113023;
  kernel_trap_vec[2] = 0x00513423;
  kernel_trap_vec[3] = 0x00613823;
  kernel_trap_vec[4] = 0x00713C23;
  kernel_trap_vec[5] = 0x03C13023;
  kernel_trap_vec[6] = 0x03D13423;
  kernel_trap_vec[7] = 0x03E13823;
  kernel_trap_vec[8] = 0x03F13C23;
  kernel_trap_vec[9] = 0x04A13023;
  kernel_trap_vec[10] = 0x04B13423;
  kernel_trap_vec[11] = 0x04C13823;
  kernel_trap_vec[12] = 0x04D13C23;
  kernel_trap_vec[13] = 0x06E13023;
  kernel_trap_vec[14] = 0x06F13423;
  kernel_trap_vec[15] = 0x07013823;
  kernel_trap_vec[16] = 0x07113C23;
  kernel_trap_vec[17] = 0x08813023;
  // csrr t0,mcause; csrw mscratch,t0
  kernel_trap_vec[18] = 0x342022F3;
  kernel_trap_vec[19] = 0x34029073;
  // blt t0,zero,+100 → IRQ (SoftCall HolyC + j restore; no asm CLINT/PLIC clear)
  kernel_trap_vec[20] = 0x0602C263;
  // addi t1,zero,11; bne t0,t1,+124 → hang
  kernel_trap_vec[21] = 0x00B00313;
  kernel_trap_vec[22] = 0x06629E63;
  // csrr t0,mepc; addi t0,t0,4; csrw mepc,t0
  kernel_trap_vec[23] = 0x341022F3;
  kernel_trap_vec[24] = 0x00428293;
  kernel_trap_vec[25] = 0x34129073;
  // restore + mret
  kernel_trap_vec[26] = 0x00013083;
  kernel_trap_vec[27] = 0x00813283;
  kernel_trap_vec[28] = 0x01013303;
  kernel_trap_vec[29] = 0x01813383;
  kernel_trap_vec[30] = 0x02013E03;
  kernel_trap_vec[31] = 0x02813E83;
  kernel_trap_vec[32] = 0x03013F03;
  kernel_trap_vec[33] = 0x03813F83;
  kernel_trap_vec[34] = 0x04013503;
  kernel_trap_vec[35] = 0x04813583;
  kernel_trap_vec[36] = 0x05013603;
  kernel_trap_vec[37] = 0x05813683;
  kernel_trap_vec[38] = 0x06013703;
  kernel_trap_vec[39] = 0x06813783;
  kernel_trap_vec[40] = 0x07013803;
  kernel_trap_vec[41] = 0x07813883;
  kernel_trap_vec[42] = 0x08013403;
  kernel_trap_vec[43] = 0x09010113;
  kernel_trap_vec[44] = 0x30200073;
  // IRQ: SoftCall HolyC (CLINT/PLIC clear in KernelTrapDispatch)
  // a0=mscratch; jalr *KERNEL_TRAP_HOOK_ADDR (0x8700E018)
  // lui sign-extends — zero-extend like HolyC before ld (else fault→hang).
  kernel_trap_vec[45] = 0x34002573;
  // csrr a0,mscratch
  kernel_trap_vec[46] = 0x8700EFB7;
  // lui t6,0x8700E
  kernel_trap_vec[47] = 0x018F8F93;
  // addi t6,t6,0x018
  kernel_trap_vec[48] = 0x020F9F93;
  // slli t6,t6,32
  kernel_trap_vec[49] = 0x020FDF93;
  // srli t6,t6,32
  kernel_trap_vec[50] = 0x000FBF83;
  // ld t6,0(t6)
  kernel_trap_vec[51] = 0x000F80E7;
  // jalr ra,0(t6)
  kernel_trap_vec[52] = 0xF99FF06F;
  // j restore (−104)
  // hang: j hang
  kernel_trap_vec[53] = 0x0000006F;
  KernelFenceI;
}

I64 KernelTrapSoft()
{
  I64 (*ecall_fp)();
  I64 old_mtvec, got, vec, cause, gpr;
  KernelTrapVecPlant;
  old_mtvec = KernelCsrRead(0x30502573);
  // csrr a0, mtvec
  // Disable IRQs while swapping mtvec (TrapBareMtvec).
  // addi t0,zero,8; csrc mstatus,t0; csrw mie,zero — via wstub chain.
  kernel_csr_wstub[0] = 0x00800293;
  // addi t0, zero, 8
  kernel_csr_wstub[1] = 0x3002B073;
  // csrc mstatus, t0
  kernel_csr_wstub[2] = 0x30401073;
  // csrw mie, zero (csrrw x0,mie,x0)
  kernel_csr_wstub[3] = 0x00008067;
  // ret
  ecall_fp = &kernel_csr_wstub;
  ecall_fp();
  vec = &kernel_trap_vec;
  vec = vec & ~3;
  // direct mode, 4-byte align
  KernelCsrWrite(0x30551073, vec);
  // csrw mtvec, a0
  KernelFenceI;
  got = KernelCsrRead(0x30502573);
  if ((got & ~3) != vec)
    return -1;
  // Clear mscratch so post-ecall cause==11 is unambiguous.
  KernelCsrWrite(0x34051073, 0);
  // csrw mscratch, a0
  // Stub: li t0,'GPRF'; ecall; mv a0,t0; ret — GPR frame must restore t0.
  kernel_ecall_stub[0] = 0x475052B7;
  // lui t0, 0x47505
  kernel_ecall_stub[1] = 0x24628293;
  // addi t0, t0, 0x246
  kernel_ecall_stub[2] = 0x00000073;
  // ecall
  kernel_ecall_stub[3] = 0x00028513;
  // mv a0, t0
  kernel_ecall_stub[4] = 0x00008067;
  // ret
  KernelFenceI;
  ecall_fp = &kernel_ecall_stub;
  gpr = ecall_fp();
  // Returned ⇒ handler skipped ecall and mret'd (hang = fail).
  cause = KernelCsrRead(0x34002573);
  // csrr a0, mscratch
  if (cause != KERNEL_MCAUSE_ECALL_M)
    return -3;
  if (gpr != KERNEL_TRAP_GPR_MAGIC)
    return -4;
  KernelCsrWrite(0x30551073, old_mtvec);
  KernelFenceI;
  got = KernelCsrRead(0x30502573);
  if (got != old_mtvec)
    return -2;
  return 0x4B58;
  // 'KX'
}
// Leave TrapCtx mtvec installed (boot ownership). Call only after SoftCall Cap/Read.
I64 KernelTrapOwn()
{
  I64 (*ie_fp)();
  I64 got, vec;
  KernelTrapVecPlant;
  KernelTrapHookPlant;
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3002B073;
  kernel_csr_wstub[2] = 0x30401073;
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp = &kernel_csr_wstub;
  ie_fp();
  vec = &kernel_trap_vec;
  vec = vec & ~3;
  KernelCsrWrite(0x30551073, vec);
  KernelFenceI;
  got = KernelCsrRead(0x30502573);
  if ((got & ~3) != vec)
    return -1;
  return 0x4B4F;
  // 'KO'
}
// Live CLINT MSIP → TrapCtx SoftCall HolyC (clear MSIP)+mret. Call after TrapOwn.
I64 KernelTrapIrq()
{
  I64 (*ie_fp)();
  I64 cause, i, got, vec;
  U32 *msip;
  I64 *mtimecmp;
  KernelTrapVecPlant;
  KernelTrapHookPlant;
  // Ensure TrapCtx mtvec (TrapOwn already did; re-install is idempotent).
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3002B073;
  kernel_csr_wstub[2] = 0x30401073;
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp = &kernel_csr_wstub;
  ie_fp();
  vec = &kernel_trap_vec;
  vec = vec & ~3;
  KernelCsrWrite(0x30551073, vec);
  KernelFenceI;
  got = KernelCsrRead(0x30502573);
  if ((got & ~3) != vec)
    return -1;
  msip = KERNEL_CLINT_MSIP;
  mtimecmp = KERNEL_CLINT_MTIMECMP;
  *msip = 0;
  *mtimecmp = -1;
  KernelCsrWrite(0x34051073, 0);
  // csrw mscratch,0
  // Enable MSIE (mie bit3) then MIE (mstatus bit3); MSIP already clear.
  kernel_csr_wstub[0] = 0x00800293;
  // addi t0,zero,8
  kernel_csr_wstub[1] = 0x3042A073;
  // csrs mie,t0 (MSIE)
  kernel_csr_wstub[2] = 0x3002A073;
  // csrs mstatus,t0 (MIE)
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp();
  // Raise soft IRQ — TrapCtx SoftCalls HolyC (clears MSIP), mrets.
  *msip = 1;
  cause = 0;
  for (i = 0; i < 1000000; i++) {
    cause = KernelCsrRead(0x34002573);
    // csrr a0,mscratch
    if (cause < 0)
      break;
  }
  // Mask IRQs again (leave TrapCtx mtvec).
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3002B073;
  // csrc mstatus,t0
  kernel_csr_wstub[2] = 0x30401073;
  // csrw mie,zero
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp();
  *msip = 0;
  *mtimecmp = -1;
  if (cause != KERNEL_MCAUSE_IRQ_M_SOFT)
    return -3;
  return 0x4B51;
  // 'KQ'
}
// Live CLINT timer → TrapCtx SoftCall HolyC (clear mtimecmp=-1)+mret.
// Call after TrapOwn (and preferably after TrapIrq). Arms mtimecmp near
// mtime, enables MTIE+MIE, proves mscratch==timer cause.
I64 KernelTrapTimer()
{
  I64 (*ie_fp)();
  I64 cause, i, got, vec, now;
  U32 *msip;
  I64 *mtimecmp, *mtime;
  KernelTrapVecPlant;
  KernelTrapHookPlant;
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3002B073;
  kernel_csr_wstub[2] = 0x30401073;
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp = &kernel_csr_wstub;
  ie_fp();
  vec = &kernel_trap_vec;
  vec = vec & ~3;
  KernelCsrWrite(0x30551073, vec);
  KernelFenceI;
  got = KernelCsrRead(0x30502573);
  if ((got & ~3) != vec)
    return -1;
  msip = KERNEL_CLINT_MSIP;
  mtimecmp = KERNEL_CLINT_MTIMECMP;
  mtime = KERNEL_CLINT_MTIME;
  *msip = 0;
  *mtimecmp = -1;
  KernelCsrWrite(0x34051073, 0);
  // csrw mscratch,0
  // Enable MTIE (mie bit7=128) then MIE (mstatus bit3=8).
  kernel_csr_wstub[0] = 0x08000293;
  // addi t0,zero,128
  kernel_csr_wstub[1] = 0x3042A073;
  // csrs mie,t0 (MTIE)
  kernel_csr_wstub[2] = 0x00800293;
  // addi t0,zero,8
  kernel_csr_wstub[3] = 0x3002A073;
  // csrs mstatus,t0 (MIE)
  kernel_csr_wstub[4] = 0x00008067;
  // ret
  ie_fp();
  // Arm soon — TrapCtx SoftCalls HolyC (clears mtimecmp), mrets.
  now = *mtime;
  *mtimecmp = now + 8;
  cause = 0;
  for (i = 0; i < 1000000; i++) {
    cause = KernelCsrRead(0x34002573);
    // csrr a0,mscratch
    if (cause < 0)
      break;
  }
  // Mask IRQs again (leave TrapCtx mtvec).
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3002B073;
  // csrc mstatus,t0
  kernel_csr_wstub[2] = 0x30401073;
  // csrw mie,zero
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp();
  *msip = 0;
  *mtimecmp = -1;
  if (cause != KERNEL_MCAUSE_IRQ_M_TIMER)
    return -3;
  return 0x4B4D;
  // 'KM'
}
// SoftCall HolyC TrapDispatch via TrapCtx IRQ SoftCall (hook→HIT 'KH').
// Call after TrapTimer. Re-fires MSIP; proves KernelTrapDispatch ran.
I64 KernelTrapDisp()
{
  I64 (*ie_fp)();
  I64 cause, i, got, vec, hitv;
  U32 *msip;
  I64 *mtimecmp, *hit;
  KernelTrapVecPlant;
  KernelTrapHookPlant;
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3002B073;
  kernel_csr_wstub[2] = 0x30401073;
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp = &kernel_csr_wstub;
  ie_fp();
  vec = &kernel_trap_vec;
  vec = vec & ~3;
  KernelCsrWrite(0x30551073, vec);
  KernelFenceI;
  got = KernelCsrRead(0x30502573);
  if ((got & ~3) != vec)
    return -1;
  msip = KERNEL_CLINT_MSIP;
  mtimecmp = KERNEL_CLINT_MTIMECMP;
  hit = KERNEL_TRAP_HIT_ADDR;
  *msip = 0;
  *mtimecmp = -1;
  *hit = 0;
  KernelCsrWrite(0x34051073, 0);
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3042A073;
  kernel_csr_wstub[2] = 0x3002A073;
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp();
  *msip = 1;
  cause = 0;
  for (i = 0; i < 1000000; i++) {
    cause = KernelCsrRead(0x34002573);
    if (cause < 0)
      break;
  }
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3002B073;
  kernel_csr_wstub[2] = 0x30401073;
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp();
  *msip = 0;
  *mtimecmp = -1;
  hitv = *hit;
  if (cause != KERNEL_MCAUSE_IRQ_M_SOFT)
    return -3;
  if (hitv != KERNEL_TRAP_HIT_MAGIC)
    return -4;
  return 0x4B44;
  // 'KD'
}
// Import-free virtio-mmio scan (pack virtio surface into BIN; no driver).
#ifndef CONFIG_VIRTIO_MMIO_BASE
#define CONFIG_VIRTIO_MMIO_BASE 0x10001000
#endif
#ifndef CONFIG_VIRTIO_MMIO_SIZE
#define CONFIG_VIRTIO_MMIO_SIZE 0x1000
#endif
#ifndef CONFIG_VIRTIO_MMIO_COUNT
#define CONFIG_VIRTIO_MMIO_COUNT 8
#endif
#define KERNEL_VIRTIO_MAGIC 0x74726976
#define KERNEL_VIRTIO_ID_BLK 2
public I64 KernelVirtioProbe()
{
  I64 i, base, stride, count, slot;
  U8 *r;
  U32 magic, id;
  base = CONFIG_VIRTIO_MMIO_BASE;
  stride = CONFIG_VIRTIO_MMIO_SIZE;
  count = CONFIG_VIRTIO_MMIO_COUNT;
  for (i = 0; i < count; i++) {
    slot = base + i *stride;
    r = slot;
    magic = *r(U32 *);
    id = *(r + 8)(U32 *);
    if (magic == KERNEL_VIRTIO_MAGIC && id == KERNEL_VIRTIO_ID_BLK)
      return 0x4B56;
  }
  return -1;
}

public I64 KernelInitLite()
{
  I64 h, t, v, ts, *slot, rx;
  KernelUart("Kernel.BIN: KernelInitLite (UART+freelist64K+magic)...\n");
  // Soft UART RX ownership: non-blocking poll must complete (no data expected).
  rx = KernelUartGetC();
  if (rx != -1 && (rx < 0 || rx > 255))
    return -7;
  h = KernelHeapProbe();
  if (h != 64)
    return -3;
  t = KernelTrapProbe();
  if (t != 0x4B54)
    return -5;
  // Real mtvec before SoftCall virtio (prior mid-SoftCall ecall broke Cap/Read).
  KernelUart("Kernel.BIN: InitLite TrapCtx (GPR+IRQ+ecall)...\n");
  ts = KernelTrapSoft();
  if (ts != 0x4B58)
    return -8;
  v = KernelVirtioProbe();
  if (v != 0x4B56)
    return -6;
  slot = KERNEL_BIN_MAGIC_ADDR;
  *slot = KERNEL_BIN_MAGIC_VAL;
  if (*slot != KERNEL_BIN_MAGIC_VAL)
    return -4;
  return 0x4B49;
}
// In-BIN MMIO virtio-blk Init + Cap/Read/Write + minimal RedSea (SoftCall ENTER).
// SoftCall owns full legacy handshake (reset+VQ) after thin Jump — thin embed
// path needs no VirtioBlkInit for Kernel.BIN fetch (RV_THIN_EMBED_BIN).
#ifndef KERNEL_VBLK_VQ
#define KERNEL_VBLK_VQ 0x88000000
#endif
#define KERNEL_VBLK_HDR (KERNEL_VBLK_VQ + 0x20000)
#define KERNEL_VBLK_STAT (KERNEL_VBLK_VQ + 0x21000)
#define KERNEL_VBLK_QSZ 8
#define KERNEL_VMR_DRIVER_FEAT 0x20
#define KERNEL_VMR_DRIVER_FEATSEL 0x24
#define KERNEL_VMR_GUEST_PGSZ 0x28
#define KERNEL_VMR_QUEUE_SEL 0x30
#define KERNEL_VMR_QUEUE_NUM 0x38
#define KERNEL_VMR_QUEUE_ALIGN 0x3c
#define KERNEL_VMR_QUEUE_PFN 0x40
#define KERNEL_VMR_QUEUE_NOTIFY 0x50
#define KERNEL_VMR_STATUS 0x70
#define KERNEL_VSTAT_ACK 1
#define KERNEL_VSTAT_DRIVER 2
#define KERNEL_VSTAT_DRIVER_OK 4
#define KERNEL_VDESC_F_NEXT 1
#define KERNEL_VDESC_F_WRITE 2
#define KERNEL_VBLK_T_IN 0
#define KERNEL_VBLK_T_OUT 1
I64 kernel_vblk_base = 0;
// 4 KiB, raised from 2 KiB: eleven SoftCall probes share this buffer and they had crowded the
// old limit -- SoftPrsSrc sat at 2016/2048 and SoftLexSrc tipped over at 2128 when codegen grew,
// though none of the probe SOURCES had changed. Shrinking one probe only buys time until the
// next one goes over. This is the harness's own buffer, not a product limit.
U8 kernel_load_buf[4096];
// SoftCall-lite LexStmt2Bin emit buf (ExePutS JIT shape; BSS in embed BIN).
U8 kernel_lex_stmt_code[64];
I64 KernelVBlkFind()
{
  I64 i, slot, base, stride, count;
  U8 *r;
  base = CONFIG_VIRTIO_MMIO_BASE;
  stride = CONFIG_VIRTIO_MMIO_SIZE;
  count = CONFIG_VIRTIO_MMIO_COUNT;
  for (i = 0; i < count; i++) {
    slot = base + i *stride;
    r = slot;
    if (*(r(U32 *)) == KERNEL_VIRTIO_MAGIC && *(r + 8)(U32 *) == KERNEL_VIRTIO_ID_BLK)
      return slot;
  }
  return 0;
}
// Full legacy virtio-mmio blk handshake (reset+VQ) — SoftCall driver ownership.
I64 KernelVBlkInit()
{
  U8 *r;
  kernel_vblk_base = KernelVBlkFind();
  if (!kernel_vblk_base)
    return -1;
  r = kernel_vblk_base;
  KernelMemSet(KERNEL_VBLK_VQ, 0, 8192);
  KernelOutU32(r + KERNEL_VMR_STATUS, 0);
  // reset
  KernelOutU32(r + KERNEL_VMR_STATUS, KERNEL_VSTAT_ACK);
  KernelOutU32(r + KERNEL_VMR_STATUS, KERNEL_VSTAT_ACK | KERNEL_VSTAT_DRIVER);
  KernelOutU32(r + KERNEL_VMR_DRIVER_FEATSEL, 0);
  KernelOutU32(r + KERNEL_VMR_DRIVER_FEAT, 0);
  KernelOutU32(r + KERNEL_VMR_GUEST_PGSZ, 4096);
  KernelOutU32(r + KERNEL_VMR_QUEUE_SEL, 0);
  KernelOutU32(r + KERNEL_VMR_QUEUE_NUM, KERNEL_VBLK_QSZ);
  KernelOutU32(r + KERNEL_VMR_QUEUE_ALIGN, 4096);
  KernelOutU32(r + KERNEL_VMR_QUEUE_PFN, KERNEL_VBLK_VQ >> 12);
  KernelOutU32(r + KERNEL_VMR_STATUS, KERNEL_VSTAT_ACK | KERNEL_VSTAT_DRIVER | KERNEL_VSTAT_DRIVER_OK);
  return 0;
}

I64 KernelVBlkCapacity()
{
  U8 *r = kernel_vblk_base;
  U64 lo, hi;
  if (!kernel_vblk_base)
    return 0;
  lo = KernelInU32(r + 0x100);
  hi = KernelInU32(r + 0x104);
  return lo | (hi << 32);
}

class CKernelVioDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};

class CKernelVioAvail
{
  U16 flags;
  U16 idx;
  U16 ring[KERNEL_VBLK_QSZ];
  U16 used_ev;
};

class CKernelVioUsedElem
{
  U32 id;
  U32 len;
};

class CKernelVioUsed
{
  U16 flags;
  U16 idx;
  CKernelVioUsedElem ring[KERNEL_VBLK_QSZ];
  U16 avail_ev;
};

class CKernelVioBlkReq
{
  U32 type;
  U32 rsvd;
  U64 sector;
};

I64 KernelVBlkReq(I64 type, I64 sector, U8 *buf)
{
  U8 *r = kernel_vblk_base;
  CKernelVioDesc *desc = KERNEL_VBLK_VQ;
  CKernelVioAvail *avail = KERNEL_VBLK_VQ + 128;
  CKernelVioUsed *used = KERNEL_VBLK_VQ + 4096;
  CKernelVioBlkReq *hdr = KERNEL_VBLK_HDR;
  U8 *statp = KERNEL_VBLK_STAT;
  U16 uidx0;
  I64 spin;
  if (!kernel_vblk_base || !buf)
    return -1;
  hdr->type = type;
  hdr->rsvd = 0;
  hdr->sector = sector;
  *statp = 0xFF;
  desc[0].addr = KERNEL_VBLK_HDR;
  desc[0].len = 16;
  desc[0].flags = KERNEL_VDESC_F_NEXT;
  desc[0].next = 1;
  desc[1].addr = buf;
  desc[1].len = 512;
  if (type == KERNEL_VBLK_T_IN)
    desc[1].flags = KERNEL_VDESC_F_NEXT | KERNEL_VDESC_F_WRITE;
  else
    desc[1].flags = KERNEL_VDESC_F_NEXT;
  desc[1].next = 2;
  desc[2].addr = KERNEL_VBLK_STAT;
  desc[2].len = 1;
  desc[2].flags = KERNEL_VDESC_F_WRITE;
  desc[2].next = 0;
  uidx0 = used->idx;
  avail->ring[0] = 0;
  avail->idx = avail->idx + 1;
  KernelOutU32(r + KERNEL_VMR_QUEUE_NOTIFY, 0);
  for (spin = 0; spin < 200000000; spin++)
    if (used->idx != uidx0)
      break;
  return *statp;
}

I64 KernelVBlkRead(I64 sector, U8 *buf)
{
  return KernelVBlkReq(KERNEL_VBLK_T_IN, sector, buf);
}

I64 KernelVBlkWrite(I64 sector, U8 *buf)
{
  return KernelVBlkReq(KERNEL_VBLK_T_OUT, sector, buf);
}
// Live host-fed UART RX → PLIC #10 → TrapCtx SoftCall HolyC claim/complete.
// WIP unwired: SoftCall hung before armed needle (host-fed); THRE×2 + virtio×2
// + asm EXT clear-before-SoftCall also hung. Keep for next PLIC lever.
I64 KernelTrapPlic()
{
  I64 (*ie_fp)();
  I64 cause, got, vec, hitv, claimed, i;
  U32 *msip, *prio, *en, *thr;
  U8 *ier;
  I64 *mtimecmp, *hit, *claim_slot;
  KernelTrapVecPlant;
  KernelTrapHookPlant;
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3002B073;
  kernel_csr_wstub[2] = 0x30401073;
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp = &kernel_csr_wstub;
  ie_fp();
  vec = &kernel_trap_vec;
  vec = vec & ~3;
  KernelCsrWrite(0x30551073, vec);
  KernelFenceI;
  got = KernelCsrRead(0x30502573);
  if ((got & ~3) != vec)
    return -1;
  msip = KERNEL_CLINT_MSIP;
  mtimecmp = KERNEL_CLINT_MTIMECMP;
  hit = KERNEL_TRAP_HIT_ADDR;
  claim_slot = KERNEL_TRAP_CLAIM_ADDR;
  ier = CONFIG_UART_BASE + 1;
  *msip = 0;
  *mtimecmp = -1;
  *hit = 0;
  *claim_slot = 0;
  *ier = 0;
  // Do not drain here — host may already have fed after the needle; RDA
  // pending + IER.RDA arm must raise EXT (drain would drop the byte).
  // PLIC: priority[10]=1, enable bit, threshold=0.
  prio = KERNEL_PLIC_BASE + KERNEL_UART_IRQ * 4;
  *prio = 1;
  en = KERNEL_PLIC_BASE + KERNEL_PLIC_ENABLE_OFF;
  *en = *en | (1 << KERNEL_UART_IRQ);
  thr = KERNEL_PLIC_BASE + KERNEL_PLIC_THRESHOLD_OFF;
  *thr = 0;
  KernelCsrWrite(0x34051073, 0);
  // csrw mscratch,0
  // Arm IER.RDA then MEIE+MIE — host byte (or FIFO pending) raises EXT.
  *ier = 1;
  kernel_csr_wstub[0] = 0x00100293;
  // addi t0,zero,1
  kernel_csr_wstub[1] = 0x00B29293;
  // slli t0,t0,11
  kernel_csr_wstub[2] = 0x3042A073;
  // csrs mie,t0 (MEIE)
  kernel_csr_wstub[3] = 0x00800293;
  // addi t0,zero,8
  kernel_csr_wstub[4] = 0x3002A073;
  // csrs mstatus,t0 (MIE)
  kernel_csr_wstub[5] = 0x00008067;
  // ret
  ie_fp();
  KernelUart("Kernel.BIN: SoftCall TrapPlic armed (feed RX)...\n");
  cause = 0;
  for (i = 0; i < 500000; i++) {
    cause = KernelCsrRead(0x34002573);
    // csrr a0,mscratch
    if (cause < 0)
      break;
  }
  // Mask IRQs again (leave TrapCtx mtvec).
  kernel_csr_wstub[0] = 0x00800293;
  kernel_csr_wstub[1] = 0x3002B073;
  // csrc mstatus,t0
  kernel_csr_wstub[2] = 0x30401073;
  // csrw mie,zero
  kernel_csr_wstub[3] = 0x00008067;
  ie_fp();
  *ier = 0;
  *msip = 0;
  *mtimecmp = -1;
  hitv = *hit;
  claimed = *claim_slot;
  if (cause != KERNEL_MCAUSE_IRQ_M_EXT)
    return -3;
  if (hitv != KERNEL_TRAP_HIT_MAGIC)
    return -4;
  if (claimed != KERNEL_UART_IRQ)
    return -5;
  return 0x4B50;
  // 'KP'
}

I64 KernelStrCmp(U8 *a, U8 *b)
{
  if (!a || !b)
    return -1;
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return *a - *b;
}

I64 KernelReadI64(U8 *p)
{
  I64 v;
  KernelMemCpy(&v, p, 8);
  return v;
}

U0 KernelWriteI64(U8 *p, I64 v)
{
  KernelMemCpy(p, &v, 8);
}

U0 KernelWriteU16(U8 *p, U16 v)
{
  KernelMemCpy(p, &v, 2);
}

U0 KernelPathSplit(U8 *path, U8 *dirname, U8 *filename)
{
  U8 *p = path;
  I64 i;
  dirname[0] = 0;
  filename[0] = 0;
  if (!p)
    return;
  if (p[0] && p[1] == ':')
    p += 2;
  if (*p == '/')
    p++;
  i = 0;
  while (*p && *p != '/' && i < 37)
    dirname[i++] = *p++;
  dirname[i] = 0;
  if (*p == '/')
    p++;
  i = 0;
  while (*p && i < 37)
    filename[i++] = *p++;
  filename[i] = 0;
}

Bool KernelRedSeaBootOk(U8 *sec)
{
  if (!sec)
    return FALSE;
  return sec[3] == KERNEL_MBR_PT_REDSEA && sec[510] == 0x55 && sec[511] == 0xAA;
}

Bool KernelRedSeaValidate()
{
  U8 sec[512];
  if (!kernel_vblk_base)
    return FALSE;
  if (KernelVBlkRead(0, sec))
    return FALSE;
  return KernelRedSeaBootOk(sec);
}
// SoftCall first mount: full VirtioBlkInit + RedSea boot (not attach-only).
I64 KernelMountVirtioDisk()
{
  if (KernelVBlkInit())
    return -1;
  if (KernelVBlkCapacity() <= 0)
    return -2;
  if (!KernelRedSeaValidate())
    return -3;
  return 0x4B4D;
}

I64 KernelDirFindClus(U8 *dirname)
{
  U8 sec[512], *ent;
  I64 root, i, attr;
  U8 name[40];
  if (KernelVBlkRead(0, sec))
    return -1;
  root = KernelReadI64(sec + 24);
  if (KernelVBlkRead(root, sec))
    return -1;
  for (i = 0; i < 512 / KERNEL_CDIR_SIZE; i++) {
    ent = sec + i *KERNEL_CDIR_SIZE;
    attr = ent[0] | (ent[1] << 8);
    if (!ent[2] || (attr & KERNEL_RS_ATTR_DELETED))
      continue;
    if (!(attr & KERNEL_RS_ATTR_DIR))
      continue;
    KernelMemCpy(name, ent + 2, 38);
    name[38] = 0;
    if (!KernelStrCmp(name, dirname))
      return KernelReadI64(ent + 40);
  }
  return -1;
}
// SoftCall RedSea: find file in contiguous multi-blk dir (`.` size @+48).
// SoftCall-lite single-sect FileFind broke once MakeOS grew past 6 Soft*.BIN+Tiny
// (SoftSubSrc tip); SoftCall FileWrite SoftCmp.BIN also needs multi-blk free slot.
Bool KernelDirFindFile(I64 dclus, U8 *filename, I64 *fclus_out, I64 *fsz_out)
{
  U8 sec[512], *ent, name[40];
  I64 i, attr, dsz, nblk, blk;
  if (dclus < 0 || !filename || !filename[0])
    return FALSE;
  if (KernelVBlkRead(dclus, sec))
    return FALSE;
  dsz = KernelReadI64(sec + 48);
  if (dsz < 512)
    dsz = 512;
  nblk = (dsz + 511) / 512;
  // SoftCall-lite: cap multi-blk walk (MakeOS spare is a few blks).
  if (nblk > 8)
    nblk = 8;
  for (blk = 0; blk < nblk; blk++) {
    if (blk && KernelVBlkRead(dclus + blk, sec))
      return FALSE;
    for (i = 0; i < 512 / KERNEL_CDIR_SIZE; i++) {
      ent = sec + i *KERNEL_CDIR_SIZE;
      attr = ent[0] | (ent[1] << 8);
      if (!ent[2] || (attr & KERNEL_RS_ATTR_DELETED) || (attr & KERNEL_RS_ATTR_DIR))
        continue;
      KernelMemCpy(name, ent + 2, 38);
      name[38] = 0;
      if (!KernelStrCmp(name, filename)) {
        if (fclus_out)
          *fclus_out = KernelReadI64(ent + 40);
        if (fsz_out)
          *fsz_out = KernelReadI64(ent + 48);
        return TRUE;
      }
    }
  }
  return FALSE;
}

Bool KernelFileFind(U8 *path)
{
  U8 dirname[40], filename[40];
  I64 dclus, fclus, fsz;
  KernelPathSplit(path, dirname, filename);
  if (!filename[0])
    return FALSE;
  dclus = KernelDirFindClus(dirname);
  if (dclus < 0)
    return FALSE;
  return KernelDirFindFile(dclus, filename, &fclus, &fsz);
}

I64 KernelAllocClus()
{
  U8 boot[512], bm[512];
  I64 bm_sects, data_area, sects, bit, max_bits, bsec, boff, byte_i, mask;
  if (KernelVBlkRead(0, boot))
    return -1;
  sects = KernelReadI64(boot + 16);
  bm_sects = KernelReadI64(boot + 32);
  data_area = bm_sects;
  max_bits = sects - data_area;
  for (bit = 0; bit < max_bits; bit++) {
    bsec = 1 + (bit >> 12);
    // 4096 bits/sector
    if (bsec > bm_sects)
      break;
    if (KernelVBlkRead(bsec, bm))
      return -1;
    boff = bit & 4095;
    byte_i = boff >> 3;
    mask = 1 << (boff & 7);
    if (!(bm[byte_i] & mask)) {
      bm[byte_i] |= mask;
      if (KernelVBlkWrite(bsec, bm))
        return -1;
      return data_area + bit;
    }
  }
  return -1;
}

I64 KernelFileWrite(U8 *path, U8 *fbuf, I64 size)
{
  U8 dirname[40], filename[40], name[40], sec[512], data[512], *ent;
  I64 dclus, i, attr, slot, fclus, n, dsz, nblk, blk, slot_blk;
  if (!path || !fbuf || size < 0 || size > 512)
    return -1;
  KernelPathSplit(path, dirname, filename);
  if (!filename[0])
    return -2;
  dclus = KernelDirFindClus(dirname);
  if (dclus < 0)
    return -3;
  if (KernelVBlkRead(dclus, sec))
    return -4;
  dsz = KernelReadI64(sec + 48);
  if (dsz < 512)
    dsz = 512;
  nblk = (dsz + 511) / 512;
  if (nblk > 8)
    nblk = 8;
  slot = -1;
  slot_blk = -1;
  fclus = -1;
  for (blk = 0; blk < nblk; blk++) {
    if (blk && KernelVBlkRead(dclus + blk, sec))
      return -4;
    for (i = 0; i < 512 / KERNEL_CDIR_SIZE; i++) {
      ent = sec + i *KERNEL_CDIR_SIZE;
      attr = ent[0] | (ent[1] << 8);
      if (!ent[2] || (attr & KERNEL_RS_ATTR_DELETED)) {
        if (slot < 0) {
          slot = i;
          slot_blk = blk;
        }
        continue;
      }
      if (attr & KERNEL_RS_ATTR_DIR)
        continue;
      KernelMemCpy(name, ent + 2, 38);
      name[38] = 0;
      if (!KernelStrCmp(name, filename)) {
        slot = i;
        slot_blk = blk;
        fclus = KernelReadI64(ent + 40);
        blk = nblk;
        break;
      }
    }
  }
  if (slot < 0 || slot_blk < 0)
    return -5;
  if (fclus < 0) {
    fclus = KernelAllocClus();
    if (fclus < 0)
      return -6;
  }
  KernelMemSet(data, 0, 512);
  n = size;
  if (n > 512)
    n = 512;
  KernelMemCpy(data, fbuf, n);
  if (KernelVBlkWrite(fclus, data))
    return -7;
  if (KernelVBlkRead(dclus + slot_blk, sec))
    return -4;
  ent = sec + slot *KERNEL_CDIR_SIZE;
  KernelMemSet(ent, 0, KERNEL_CDIR_SIZE);
  KernelWriteU16(ent, KERNEL_RS_ATTR_CONTIGUOUS);
  KernelMemCpy(ent + 2, filename, KernelStrLen(filename) + 1);
  KernelWriteI64(ent + 40, fclus);
  KernelWriteI64(ent + 48, size);
  if (KernelVBlkWrite(dclus + slot_blk, sec))
    return -8;
  return size;
}

I64 KernelFileRead(U8 *path, U8 *obuf, I64 max)
{
  U8 dirname[40], filename[40], sec[512];
  I64 dclus, fclus, fsz, n;
  if (!path || !obuf || max <= 0)
    return -1;
  KernelPathSplit(path, dirname, filename);
  if (!filename[0])
    return -2;
  dclus = KernelDirFindClus(dirname);
  if (dclus < 0)
    return -3;
  fclus = -1;
  fsz = 0;
  if (!KernelDirFindFile(dclus, filename, &fclus, &fsz))
    return -5;
  if (fclus < 0 || fsz <= 0)
    return -5;
  if (KernelVBlkRead(fclus, sec))
    return -6;
  n = fsz;
  if (n > max)
    n = max;
  if (n > 512)
    n = 512;
  KernelMemCpy(obuf, sec, n);
  return n;
}
// Raw multi-blk text read (guest source off RedSea) — same clus walk as
// KernelLoad but no CBinFile signature gate, and NUL-terminates so the lite Lex
// can walk it. Capped by the SoftCall Load 2KiB budget.
I64 KernelSrcRead(U8 *path, U8 *obuf, I64 max)
{
  U8 dirname[40], filename[40], sec[512];
  I64 dclus, fclus, fsz, nblk, i, take;
  if (!path || !obuf || max <= 1)
    return -1;
  KernelPathSplit(path, dirname, filename);
  if (!filename[0])
    return -2;
  dclus = KernelDirFindClus(dirname);
  if (dclus < 0)
    return -3;
  fclus = -1;
  fsz = 0;
  if (!KernelDirFindFile(dclus, filename, &fclus, &fsz))
    return -4;
  if (fclus < 0 || fsz <= 0)
    return -5;
  if (fsz > max - 1)
    return -6;
  nblk = (fsz + 511) / 512;
  for (i = 0; i < nblk; i++) {
    if (KernelVBlkRead(fclus + i, sec))
      return -7;
    take = fsz - i * 512;
    if (take > 512)
      take = 512;
    KernelMemCpy(obuf + i * 512, sec, take);
  }
  obuf[fsz] = 0;
  return fsz;
}

I64 KernelLoad(U8 *path)
{
  U8 dirname[40], filename[40], sec[512];
  I64 dclus, i, fclus, fsz, nblk, take;
  KernelPathSplit(path, dirname, filename);
  if (!filename[0])
    return 0;
  dclus = KernelDirFindClus(dirname);
  if (dclus < 0)
    return 0;
  fclus = -1;
  fsz = 0;
  if (!KernelDirFindFile(dclus, filename, &fclus, &fsz))
    return 0;
  if (fclus < 0 || fsz <= 0 || fsz > 4096)
    return 0;
  nblk = (fsz + 511) / 512;
  for (i = 0; i < nblk; i++) {
    if (KernelVBlkRead(fclus + i, sec))
      return 0;
    take = fsz - i * 512;
    if (take > 512)
      take = 512;
    KernelMemCpy(kernel_load_buf + i * 512, sec, take);
  }
  // CBinFile: U16 jmp + U8 align + U8 pad, then U32 bin_signature @4.
  if (*(kernel_load_buf(U8 *) + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return 0;
  return kernel_load_buf(I64);
}
// Import-free export walk + Call (Hash-lite in BIN — path to drop thin Hash later).
I64 KernelCallExport(U8 *bfh, U8 *name)
{
  U8 *pt, *st, *module_base;
  I64 ptoff, etype, i;
  I64 (*fp)();
  if (!bfh || !name)
    return -1;
  if (*(bfh + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -2;
  ptoff = KernelReadI64(bfh + 16);
  if (ptoff <= 0)
    return -3;
  module_base = bfh + KERNEL_CBIN_HDR;
  pt = bfh + ptoff;
  while (TRUE) {
    etype = *pt++;
    if (etype == KERNEL_IET_END)
      break;
    i = *(pt(U32 *));
    pt += 4;
    st = pt;
    while (*pt)
      pt++;
    pt++;
    if (!*st)
      return -4;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      if (!KernelStrCmp(st, name)) {
        if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
          fp = i;
        else
          fp = module_base + i;
        return fp();
      }
    } else {
      return -5;
    }
  }
  return -6;
}

I64 KernelLoadCall(U8 *path, U8 *export_name)
{
  I64 bfh;
  bfh = KernelLoad(path);
  if (!bfh)
    return -1;
  return KernelCallExport(bfh(U8 *), export_name);
}
// SoftCall Task/Job/Spawn slice (G9): import-free stand-in for KTask+Job past the
// thin KThinTaskStubs/KThinJobStubs wall. YieldSoft adds HolyRVCtxSw on rsp.
#define KERNEL_TASK_SIG 'TskS'
#define KERNEL_JOBT_CALL 3
#define KERNEL_JOB_CONT 1
#define KERNEL_JOB_DONE 0
#define KERNEL_TASKf_KILL 1
// TASKf_KILL_TASK bit index
#define KERNEL_YIELD_STK 4096
I64 kernel_spawn_num = 0;
I64 kernel_yield_hits = 0;
U32 kernel_ctxsw_stub[32];
class CKernelJob
{
  CKernelJob *next, *last;
  I64 job_code;
  I64 (*addr)(U8 *fun_arg);
  U8 *fun_arg;
  I64 res;
};

class CKernelJobCtrl
{
  CKernelJob waiting;
  // CQue head (next/last self-ring when empty)
  I64 flags;
};

class CKernelTask
{
  CKernelTask *addr;
  I64 task_signature;
  CKernelTask *next_task, *last_task;
  CKernelTask *parent_task;
  CKernelJobCtrl srv_ctrl;
  I64 (*rip)(U8 *data);
  I64 task_num;
  I64 rsp;
  // HolyRVCtxSw slot (Sched.HC / holy_rt CTask.rsp shape)
  I64 task_flags;
};
CKernelTask *kernel_fs = NULL;
U0 KernelQueInitJob(CKernelJob *head)
{
  head->next = head->last = head;
}

U0 KernelQueInsJob(CKernelJob *item, CKernelJob *pred)
{
  item->next = pred->next;
  item->last = pred;
  pred->next->last = item;
  pred->next = item;
}

U0 KernelQueRemJob(CKernelJob *item)
{
  item->next->last = item->last;
  item->last->next = item->next;
  item->next = item->last = item;
}

Bool KernelTaskValidate(CKernelTask *task)
{
  if (!task || task->addr != task || task->task_signature != KERNEL_TASK_SIG)
    return FALSE;
  return TRUE;
}

U0 KernelJobCtrlInit(CKernelJobCtrl *ctrl)
{
  if (!ctrl)
    return;
  KernelQueInitJob(&ctrl->waiting);
  ctrl->flags = 0;
}

I64 KernelTaskInit(CKernelTask *task)
{
  if (!task)
    return 0;
  task->task_signature = KERNEL_TASK_SIG;
  task->addr = task->next_task = task->last_task = task;
  task->parent_task = NULL;
  task->rip = NULL;
  task->task_num = kernel_spawn_num++;
  task->rsp = 0;
  task->task_flags = 0;
  KernelJobCtrlInit(&task->srv_ctrl);
  return task(I64);
}

I64 KernelSpawnEntry(U8 *data)
{
  no_warn data;
  return 0x5350;
  // 'SP'
}

CKernelTask *KernelSpawn(CKernelTask *parent, I64 (*fp)(U8 *data), U8 *data)
{
  CKernelTask *task;
  if (!KernelTaskValidate(parent) || !fp)
    return NULL;
  task = KernelArenaAlloc(sizeof(CKernelTask));
  if (!task)
    return NULL;
  KernelMemSet(task(U8 *), 0, sizeof(CKernelTask));
  KernelTaskInit(task);
  task->parent_task = parent;
  task->rip = fp;
  // Insert into parent ring (TempleOS TaskQueIns shape, single-core).
  task->next_task = parent;
  task->last_task = parent->last_task;
  parent->last_task->next_task = task;
  parent->last_task = task;
  // Prove entry is callable without ctxsw (Spawn rip ownership).
  if ((*fp)(data) != 0x5350)
    return NULL;
  return task;
}

CKernelJob *KernelJobQue(CKernelTask *srv, I64 (*fp)(U8 *fun_arg), U8 *fun_arg)
{
  CKernelJob *job;
  if (!KernelTaskValidate(srv) || !fp)
    return NULL;
  job = KernelArenaAlloc(sizeof(CKernelJob));
  if (!job)
    return NULL;
  KernelMemSet(job(U8 *), 0, sizeof(CKernelJob));
  job->job_code = KERNEL_JOBT_CALL;
  job->addr = fp;
  job->fun_arg = fun_arg;
  job->res = 0;
  // QueIns at end: after last (== head when empty).
  KernelQueInsJob(job, srv->srv_ctrl.waiting.last);
  return job;
}

I64 KernelJobRunOne(CKernelJobCtrl *ctrl)
{
  CKernelJob *job, *head;
  if (!ctrl)
    return KERNEL_JOB_DONE;
  head = &ctrl->waiting;
  job = head->next;
  if (job == head)
    return KERNEL_JOB_DONE;
  if (job->job_code != KERNEL_JOBT_CALL)
    return KERNEL_JOB_DONE;
  KernelQueRemJob(job);
  if (job->addr)
    job->res = (*job->addr)(job->fun_arg);
  return KERNEL_JOB_CONT;
}

I64 KernelJobCallEntry(U8 *fun_arg)
{
  no_warn fun_arg;
  return 0x4A43;
  // 'JC'
}
// SoftCall prove: TaskInit Adam → Spawn child (ring+rip call) → JobQue CALL → RunOne.
public I64 KernelTaskSoft()
{
  CKernelTask *adam, *child;
  CKernelJob *job;
  I64 r;
  adam = KernelArenaAlloc(sizeof(CKernelTask));
  if (!adam)
    return -1;
  KernelMemSet(adam(U8 *), 0, sizeof(CKernelTask));
  if (!KernelTaskInit(adam))
    return -2;
  if (!KernelTaskValidate(adam))
    return -3;
  child = KernelSpawn(adam, &KernelSpawnEntry, NULL);
  if (!child || !KernelTaskValidate(child))
    return -4;
  if (child->parent_task != adam)
    return -5;
  if (adam->next_task != child || child->next_task != adam)
    return -6;
  if (adam->last_task != child || child->last_task != adam)
    return -7;
  job = KernelJobQue(adam, &KernelJobCallEntry, NULL);
  if (!job)
    return -8;
  r = KernelJobRunOne(&adam->srv_ctrl);
  if (r != KERNEL_JOB_CONT)
    return -9;
  if (job->res != 0x4A43)
    return -10;
  if (KernelJobRunOne(&adam->srv_ctrl) != KERNEL_JOB_DONE)
    return -11;
  return 0x4B4A;
  // 'KJ'
}
// SoftCall Hash find/add slice (G9): import-free stand-in for KHashRV past the
// thin KThinHashStubs wall. TableNew + Add + Find (+ miss); no Define/Load Hash.
#define KERNEL_HASH_BUCKETS 16
#define KERNEL_HTT_EXPORT 0x00001
// lite HTT_EXPORT_SYS_SYM
#define KERNEL_HTT_MODULE 0x04000
// stock HTT_MODULE
#define KERNEL_INVALID_PTR 0x7FFFFFFFFFFFFFFF
// I64_MAX — CBinFile.org don't-care
class CKernelHash
{
  CKernelHash *next;
  U8 *str;
  I64 type;
  I64 use_cnt;
  I64 val;
};

class CKernelHashTable
{
  CKernelHashTable *next;
  I64 mask;
  I64 *body;
  // CKernelHash* slots as I64 — index stores only (KHashRV RV AOT note)
};

I64 KernelHashStr(U8 *st)
{
  // TempleOS SYS_HASH_STR / KHashRV.
  U64 h = 0, c, carry;
  if (!st)
    return 0;
  while (c = *st++) {
    carry = h >> 63;
    h = (h << 1) + c + carry;
  }
  carry = (h >> 15) & 1;
  return h + (h >> 16) + carry;
}

CKernelHashTable *KernelHashTableNew(I64 size)
{
  CKernelHashTable *table;
  I64 i, nbytes;
  if (size < 2)
    size = 2;
  table = KernelArenaAlloc(sizeof(CKernelHashTable));
  if (!table)
    return NULL;
  KernelMemSet(table(U8 *), 0, sizeof(CKernelHashTable));
  nbytes = size << 3;
  table->body = KernelArenaAlloc(nbytes);
  if (!table->body)
    return NULL;
  KernelMemSet(table->body(U8 *), 0, nbytes);
  table->mask = size - 1;
  table->next = NULL;
  // Touch every slot via index (prove body[] stores).
  for (i = 0; i <= table->mask; i++)
    table->body[i] = 0;
  return table;
}

U0 KernelHashAdd(CKernelHash *tmph, CKernelHashTable *table)
{
  I64 i;
  if (!tmph || !table || !table->body)
    return;
  i = KernelHashStr(tmph->str) & table->mask;
  tmph->next = table->body[i](CKernelHash *);
  table->body[i] = tmph(I64);
}

CKernelHash *KernelHashFind(U8 *needle_str, CKernelHashTable *haystack_table, I64 mask, I64 instance)
{
  CKernelHash *tmph;
  U8 *a, *b;
  I64 i;
  if (!needle_str || !haystack_table || !haystack_table->body || instance <= 0)
    return NULL;
  while (haystack_table) {
    i = KernelHashStr(needle_str) & haystack_table->mask;
    tmph = haystack_table->body[i](CKernelHash *);
    while (tmph) {
      if ((tmph->type & mask) && tmph->str) {
        a = tmph->str;
        b = needle_str;
        while (*a && *a == *b) {
          a++;
          b++;
        }
        if (!*a && !*b) {
          if (--instance == 0) {
            tmph->use_cnt++;
            return tmph;
          }
        }
      }
      tmph = tmph->next;
    }
    haystack_table = haystack_table->next;
  }
  return NULL;
}
// SoftCall prove: TableNew → Add EXPORT → Find hit (+use_cnt) → miss.
public I64 KernelHashSoft()
{
  CKernelHashTable *table;
  CKernelHash *ent, *hit;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -1;
  if (table->mask != KERNEL_HASH_BUCKETS - 1)
    return -2;
  ent = KernelArenaAlloc(sizeof(CKernelHash));
  if (!ent)
    return -3;
  KernelMemSet(ent(U8 *), 0, sizeof(CKernelHash));
  ent->str = "LoadProbe";
  ent->type = KERNEL_HTT_EXPORT;
  ent->val = 7;
  KernelHashAdd(ent, table);
  hit = KernelHashFind("LoadProbe", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || hit != ent)
    return -4;
  if (hit->use_cnt != 1 || hit->val != 7)
    return -5;
  if (KernelHashFind("missing", table, KERNEL_HTT_EXPORT, 1))
    return -6;
  // Wrong type mask must miss.
  if (KernelHashFind("LoadProbe", table, 0x00002, 1))
    return -7;
  // Second Find bumps use_cnt.
  hit = KernelHashFind("LoadProbe", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || hit->use_cnt != 2)
    return -8;
  if (KernelHashStr("LoadProbe") == 0)
    return -9;
  return 0x4B46;
  // 'KF'
}
// SoftCall StrPrintJoin lite (G9): import-free stand-in for StrPrint.HC past the
// thin KThinStrPrintStubs wall. %s/%d/%X/%c only — no %f/Q/q/Define/%z.
#define KERNEL_SPRINT_CAP 128
U0 KernelPutI64(U8 *dst, I64 *pos, I64 cap, I64 v, I64 radix, Bool upper)
{
  U8 tmp[72];
  I64 n = 0, i, dig, neg = 0;
  U64 u;
  if (radix < 2)
    radix = 10;
  if (v < 0 && radix == 10) {
    neg = 1;
    u = -v;
  } else
    u = v;
  if (!u) {
    tmp[n++] = '0';
  } else {
    while (u) {
      dig = u % radix;
      u /= radix;
      if (dig < 10)
        tmp[n++] = '0' + dig;
      else if (upper)
        tmp[n++] = 'A' + dig - 10;
      else
        tmp[n++] = 'a' + dig - 10;
    }
  }
  if (neg && *pos < cap - 1)
    dst[(*pos)++] = '-';
  for (i = n - 1; i >= 0 && *pos < cap - 1; i--)
    dst[(*pos)++] = tmp[i];
}

U8 *KernelStrPrintJoin(U8 *dst, U8 *fmt, I64 argc, I64 *argv)
{
  U8 *out, *s;
  I64 pos = 0, ai = 0, ch;
  if (!fmt)
    fmt = "";
  if (!dst)
    return NULL;
  out = dst;
  while (ch = *fmt++) {
    if (ch != '%' || !*fmt) {
      if (pos < KERNEL_SPRINT_CAP - 1)
        out[pos++] = ch;
      continue;
    }
    ch = *fmt++;
    while (ch == '-' || ch == '+' || ch == ' ' || ch == '#' || ch == '0')
      ch = *fmt++;
    while (ch >= '0' && ch <= '9')
      ch = *fmt++;
    if (ch == '.') {
      ch = *fmt++;
      while (ch >= '0' && ch <= '9')
        ch = *fmt++;
    }
    if (ch == 'l' || ch == 'L' || ch == 'h')
      ch = *fmt++;
    switch (ch) {
      case '%' :
      if (pos < KERNEL_SPRINT_CAP - 1)
        out[pos++] = '%';
      break;
      case 's' :
      s = 0;
      if (ai < argc)
        s = argv[ai++];
      if (!s)
        s = "";
      while (*s && pos < KERNEL_SPRINT_CAP - 1)
        out[pos++] = *s++;
      break;
      case 'c' :
      if (ai < argc && pos < KERNEL_SPRINT_CAP - 1)
        out[pos++] = argv[ai++];
      break;
      case 'd' :
      case 'i' :
      if (ai < argc)
        KernelPutI64(out, &pos, KERNEL_SPRINT_CAP, argv[ai++], 10, FALSE);
      break;
      case 'u' :
      if (ai < argc)
        KernelPutI64(out, &pos, KERNEL_SPRINT_CAP, argv[ai++], 10, FALSE);
      break;
      case 'x' :
      if (ai < argc)
        KernelPutI64(out, &pos, KERNEL_SPRINT_CAP, argv[ai++], 16, FALSE);
      break;
      case 'X' :
      case 'p' :
      case 'P' :
      if (ai < argc)
        KernelPutI64(out, &pos, KERNEL_SPRINT_CAP, argv[ai++], 16, TRUE);
      break;
      default:
      if (ai < argc)
        ai++;
      break;
    }
  }
  out[pos] = 0;
  return out;
}

Bool KernelStrEq(U8 *a, U8 *b)
{
  if (!a || !b)
    return FALSE;
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return !*a && !*b;
}
// SoftCall prove: %s/%d/%X/%c join into fixed buf (past thin StrPrint stubs).
public I64 KernelPrintSoft()
{
  U8 buf[KERNEL_SPRINT_CAP];
  I64 args[4];
  KernelMemSet(buf, 0, KERNEL_SPRINT_CAP);
  args[0] = 42;
  KernelStrPrintJoin(buf, "n=%d", 1, args);
  if (!KernelStrEq(buf, "n=42"))
    return -1;
  args[0] = "KE";
  KernelStrPrintJoin(buf, "%s", 1, args);
  if (!KernelStrEq(buf, "KE"))
    return -2;
  args[0] = 0x4B50;
  KernelStrPrintJoin(buf, "%X", 1, args);
  if (!KernelStrEq(buf, "4B50"))
    return -3;
  args[0] = "KP";
  args[1] = -7;
  args[2] = 0xAB;
  args[3] = 'Z';
  KernelStrPrintJoin(buf, "%s/%d/%X/%c", 4, args);
  if (!KernelStrEq(buf, "KP/-7/AB/Z"))
    return -4;
  // Literal %% and empty %s.
  args[0] = 0;
  KernelStrPrintJoin(buf, "%% %s.", 1, args);
  if (!KernelStrEq(buf, "% ."))
    return -5;
  return 0x4B50;
  // 'KP'
}
// SoftCall Yield + HolyRVCtxSw (G9): import-free stand-in for Sched.HC _YIELD /
// holy_rt HolyYield past thin KThinSchedStubs (host _extern _YIELD). Walk
// next_task, skip KILL, switch on CKernelTask.rsp via planted U32[] stub
// (gas-checked HolyRVCtxSw encodings — not `_extern` RVCtxSw).
U0 KernelCtxSwPlant()
{
  // addi sp,sp,-104
  kernel_ctxsw_stub[0] = 0xF9810113;
  kernel_ctxsw_stub[1] = 0x00813023;
  // sd s0,0(sp)
  kernel_ctxsw_stub[2] = 0x00913423;
  kernel_ctxsw_stub[3] = 0x01213823;
  kernel_ctxsw_stub[4] = 0x01313C23;
  kernel_ctxsw_stub[5] = 0x03413023;
  kernel_ctxsw_stub[6] = 0x03513423;
  kernel_ctxsw_stub[7] = 0x03613823;
  kernel_ctxsw_stub[8] = 0x03713C23;
  kernel_ctxsw_stub[9] = 0x05813023;
  kernel_ctxsw_stub[10] = 0x05913423;
  kernel_ctxsw_stub[11] = 0x05A13823;
  kernel_ctxsw_stub[12] = 0x05B13C23;
  kernel_ctxsw_stub[13] = 0x06113023;
  // sd ra,96(sp)
  kernel_ctxsw_stub[14] = 0x00253023;
  // sd sp,0(a0)
  kernel_ctxsw_stub[15] = 0x0005B103;
  // ld sp,0(a1)
  kernel_ctxsw_stub[16] = 0x00013403;
  kernel_ctxsw_stub[17] = 0x00813483;
  kernel_ctxsw_stub[18] = 0x01013903;
  kernel_ctxsw_stub[19] = 0x01813983;
  kernel_ctxsw_stub[20] = 0x02013A03;
  kernel_ctxsw_stub[21] = 0x02813A83;
  kernel_ctxsw_stub[22] = 0x03013B03;
  kernel_ctxsw_stub[23] = 0x03813B83;
  kernel_ctxsw_stub[24] = 0x04013C03;
  kernel_ctxsw_stub[25] = 0x04813C83;
  kernel_ctxsw_stub[26] = 0x05013D03;
  kernel_ctxsw_stub[27] = 0x05813D83;
  kernel_ctxsw_stub[28] = 0x06013083;
  // ld ra,96(sp)
  kernel_ctxsw_stub[29] = 0x06810113;
  // addi sp,sp,104
  kernel_ctxsw_stub[30] = 0x00008067;
  // ret
  KernelFenceI;
}

U0 KernelCtxSw(I64 *from_rsp, I64 *to_rsp)
{
  I64 (*fp)(I64, I64);
  fp = &kernel_ctxsw_stub;
  fp(from_rsp, to_rsp);
}

Bool KernelTaskRunnable(CKernelTask *t)
{
  if (!t)
    return FALSE;
  if (t->task_flags & (1 << KERNEL_TASKf_KILL))
    return FALSE;
  return TRUE;
}

U0 KernelYield()
{
  CKernelTask *cur, *nxt;
  if (!kernel_fs)
    return;
  cur = kernel_fs;
  nxt = cur->next_task;
  while (nxt != cur && !KernelTaskRunnable(nxt))
    nxt = nxt->next_task;
  if (nxt == cur)
    return;
  kernel_fs = nxt;
  KernelCtxSw(&cur->rsp, &nxt->rsp);
}

U0 KernelYieldEntry()
{
  kernel_yield_hits++;
  if (kernel_fs)
    kernel_fs->task_flags = kernel_fs->task_flags | (1 << KERNEL_TASKf_KILL);
  KernelYield;
}

CKernelTask *KernelYieldSpawn(CKernelTask *parent, U0 (*fp)())
{
  CKernelTask *task;
  U8 *stk;
  I64 top, i;
  I64 *frame;
  if (!KernelTaskValidate(parent) || !fp)
    return NULL;
  task = KernelArenaAlloc(sizeof(CKernelTask));
  if (!task)
    return NULL;
  KernelMemSet(task(U8 *), 0, sizeof(CKernelTask));
  KernelTaskInit(task);
  task->parent_task = parent;
  task->rip = NULL;
  stk = KernelArenaAlloc(KERNEL_YIELD_STK);
  if (!stk)
    return NULL;
  top = (stk + KERNEL_YIELD_STK) & (~15);
  frame = (top - 104)(I64 *);
  for (i = 0; i < 12; i++)
    frame[i] = 0;
  frame[12] = fp;
  task->rsp = frame;
  // Insert into parent next_task ring (single-core Sched shape).
  task->next_task = parent->next_task;
  task->last_task = parent;
  parent->next_task->last_task = task;
  parent->next_task = task;
  return task;
}
// SoftCall prove: Adam Yield → child HolyRVCtxSw entry → KILL+Yield back;
// adam local survives; second Yield skips killed child.
public I64 KernelYieldSoft()
{
  CKernelTask *adam, *child;
  I64 marker;
  KernelCtxSwPlant;
  adam = KernelArenaAlloc(sizeof(CKernelTask));
  if (!adam)
    return -1;
  KernelMemSet(adam(U8 *), 0, sizeof(CKernelTask));
  if (!KernelTaskInit(adam))
    return -2;
  kernel_fs = adam;
  kernel_yield_hits = 0;
  child = KernelYieldSpawn(adam, &KernelYieldEntry);
  if (!child || !KernelTaskValidate(child))
    return -3;
  if (adam->next_task != child || child->next_task != adam)
    return -4;
  if (!child->rsp)
    return -5;
  marker = 0x594C;
  // 'YL' — must survive callee-saved/stack ctxsw
  KernelYield;
  if (marker != 0x594C)
    return -6;
  if (kernel_yield_hits != 1)
    return -7;
  if (kernel_fs != adam)
    return -8;
  if (!(child->task_flags & (1 << KERNEL_TASKf_KILL)))
    return -9;
  // Only adam runnable — Yield is a no-op (skip killed child).
  KernelYield;
  if (kernel_fs != adam || kernel_yield_hits != 1)
    return -10;
  return 0x4B59;
  // 'KY'
}
// SoftCall Jump (G9): LoadBuf-shaped export walk of embed BIN → HashAdd →
// HashFind KernelEntry (must match Jump-hint + &KernelEntry) → Call KernelProbe
// via HashFind val →42. Thin Jump also HashFind→Call (lite KThinHashStubs);
// SoftCall re-proves the same shape inside BIN.
public I64 KernelJumpSoft()
{
  U8 *bfh, *pt, *st, *module_base;
  I64 ptoff, etype, i, addr, nexp, r;
  I64 *eslot;
  CKernelHashTable *table;
  CKernelHash *ent, *hit;
  I64 (*fp)();
  bfh = KERNEL_EMBED_ADDR;
  if (!bfh || *(bfh + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -1;
  ptoff = KernelReadI64(bfh + 16);
  if (ptoff <= 0)
    return -2;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -3;
  module_base = bfh + KERNEL_CBIN_HDR;
  pt = bfh + ptoff;
  nexp = 0;
  while (TRUE) {
    etype = *pt++;
    if (etype == KERNEL_IET_END)
      break;
    i = *(pt(U32 *));
    pt += 4;
    st = pt;
    while (*pt)
      pt++;
    pt++;
    if (!*st)
      return -4;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
        addr = i;
      else
        addr = module_base + i;
      ent = KernelArenaAlloc(sizeof(CKernelHash));
      if (!ent)
        return -5;
      KernelMemSet(ent(U8 *), 0, sizeof(CKernelHash));
      ent->str = st;
      ent->type = KERNEL_HTT_EXPORT;
      ent->val = addr;
      KernelHashAdd(ent, table);
      nexp++;
    } else {
      return -6;
    }
  }
  if (nexp < 2)
    return -7;
  hit = KernelHashFind("KernelEntry", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -8;
  // HashFind must match Jump-hint (Entry planted &KernelEntry before SoftCall).
  eslot = KERNEL_BIN_ENTRY_ADDR;
  if (!eslot || !*eslot || *eslot != hit->val)
    return -9;
  hit = KernelHashFind("KernelProbe", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -10;
  fp = hit->val;
  r = fp();
  if (r != 42)
    return -11;
  // Miss must stay miss.
  if (KernelHashFind("NoSuchExport", table, KERNEL_HTT_EXPORT, 1))
    return -12;
  return 0x4B4C;
  // 'KL'
}
// SoftCall ExeFile-shaped Load (G9): RedSea FileFind+Load → HashAdd exports →
// HashFind→Call LoadProbe→7. Same HashFind ownership as JumpSoft/thin Jump, but
// on virtio-loaded companion BIN (not embed @0x81000000). No Cmp — Load→Call only.
// Advances Kernel.BIN past linear CallExport toward StartOS Load ownership.
public I64 KernelExeSoft()
{
  U8 *pt, *st, *module_base;
  I64 bfh, ptoff, etype, i, addr, nexp, r;
  CKernelHashTable *table;
  CKernelHash *ent, *hit;
  I64 (*fp)();
  bfh = KernelLoad("A:/Kernel/LoadProbe.BIN");
  if (!bfh || *(bfh(U8 *) + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -1;
  ptoff = KernelReadI64(bfh(U8 *) + 16);
  if (ptoff <= 0)
    return -2;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -3;
  module_base = bfh(U8 *) + KERNEL_CBIN_HDR;
  pt = bfh(U8 *) + ptoff;
  nexp = 0;
  while (TRUE) {
    etype = *pt++;
    if (etype == KERNEL_IET_END)
      break;
    i = *(pt(U32 *));
    pt += 4;
    st = pt;
    while (*pt)
      pt++;
    pt++;
    if (!*st)
      return -4;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
        addr = i;
      else
        addr = module_base + i;
      ent = KernelArenaAlloc(sizeof(CKernelHash));
      if (!ent)
        return -5;
      KernelMemSet(ent(U8 *), 0, sizeof(CKernelHash));
      ent->str = st;
      ent->type = KERNEL_HTT_EXPORT;
      ent->val = addr;
      KernelHashAdd(ent, table);
      nexp++;
    } else {
      return -6;
    }
  }
  if (nexp < 1)
    return -7;
  hit = KernelHashFind("LoadProbe", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -8;
  fp = hit->val;
  r = fp();
  if (r != 7)
    return -9;
  if (KernelHashFind("NoSuchExport", table, KERNEL_HTT_EXPORT, 1))
    return -10;
  return 0x4B42;
  // 'KB'
}
// SoftCall product MakeOS Load (G9): RedSea FileFind+Load Tiny.BIN → HashAdd →
// HashFind→Call MakeOSProbe→42. Same HashFind ownership as ExeSoft/JumpSoft, but
// on product A:/MakeOS/ path (StartOS-shaped; no Cmp).
public I64 KernelMakeSoft()
{
  U8 *pt, *st, *module_base;
  I64 bfh, ptoff, etype, i, addr, nexp, r;
  CKernelHashTable *table;
  CKernelHash *ent, *hit;
  I64 (*fp)();
  bfh = KernelLoad("A:/MakeOS/Tiny.BIN");
  if (!bfh || *(bfh(U8 *) + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -1;
  ptoff = KernelReadI64(bfh(U8 *) + 16);
  if (ptoff <= 0)
    return -2;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -3;
  module_base = bfh(U8 *) + KERNEL_CBIN_HDR;
  pt = bfh(U8 *) + ptoff;
  nexp = 0;
  while (TRUE) {
    etype = *pt++;
    if (etype == KERNEL_IET_END)
      break;
    i = *(pt(U32 *));
    pt += 4;
    st = pt;
    while (*pt)
      pt++;
    pt++;
    if (!*st)
      return -4;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
        addr = i;
      else
        addr = module_base + i;
      ent = KernelArenaAlloc(sizeof(CKernelHash));
      if (!ent)
        return -5;
      KernelMemSet(ent(U8 *), 0, sizeof(CKernelHash));
      ent->str = st;
      ent->type = KERNEL_HTT_EXPORT;
      ent->val = addr;
      KernelHashAdd(ent, table);
      nexp++;
    } else {
      return -6;
    }
  }
  if (nexp < 1)
    return -7;
  hit = KernelHashFind("MakeOSProbe", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -8;
  fp = hit->val;
  r = fp();
  if (r != 42)
    return -9;
  if (KernelHashFind("NoSuchExport", table, KERNEL_HTT_EXPORT, 1))
    return -10;
  return 0x4B4E;
  // 'KN'
}
// SoftCall product Runtime Seed Load (G9): RedSea FileFind+Load Seed.BIN → HashAdd →
// HashFind→Call RuntimeSeedInit→42. StartOS Seed→Svc→Kern chain tip (F()+imm;
// no Cmp). Same HashFind ownership as MakeSoft/ExeSoft on product A:/Runtime/.
public I64 KernelSeedSoft()
{
  U8 *pt, *st, *module_base;
  I64 bfh, ptoff, etype, i, addr, nexp, r;
  CKernelHashTable *table;
  CKernelHash *ent, *hit;
  I64 (*fp)();
  bfh = KernelLoad("A:/Runtime/Seed.BIN");
  if (!bfh || *(bfh(U8 *) + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -1;
  ptoff = KernelReadI64(bfh(U8 *) + 16);
  if (ptoff <= 0)
    return -2;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -3;
  module_base = bfh(U8 *) + KERNEL_CBIN_HDR;
  pt = bfh(U8 *) + ptoff;
  nexp = 0;
  while (TRUE) {
    etype = *pt++;
    if (etype == KERNEL_IET_END)
      break;
    i = *(pt(U32 *));
    pt += 4;
    st = pt;
    while (*pt)
      pt++;
    pt++;
    if (!*st)
      return -4;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
        addr = i;
      else
        addr = module_base + i;
      ent = KernelArenaAlloc(sizeof(CKernelHash));
      if (!ent)
        return -5;
      KernelMemSet(ent(U8 *), 0, sizeof(CKernelHash));
      ent->str = st;
      ent->type = KERNEL_HTT_EXPORT;
      ent->val = addr;
      KernelHashAdd(ent, table);
      nexp++;
    } else {
      return -6;
    }
  }
  if (nexp < 1)
    return -7;
  hit = KernelHashFind("RuntimeSeedInit", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -8;
  fp = hit->val;
  r = fp();
  if (r != 42)
    return -9;
  if (KernelHashFind("NoSuchExport", table, KERNEL_HTT_EXPORT, 1))
    return -10;
  return 0x4B52;
  // 'KR'
}
// SoftCall product Runtime Svc Load (G9): RedSea FileFind+Load Svc.BIN → HashAdd →
// HashFind→Call RuntimeSvcProbe→42. StartOS Seed→Svc→Kern chain tip (F()→F();
// no Cmp). Same HashFind ownership as SeedSoft/MakeSoft on product A:/Runtime/.
public I64 KernelSvcSoft()
{
  U8 *pt, *st, *module_base;
  I64 bfh, ptoff, etype, i, addr, nexp, r;
  CKernelHashTable *table;
  CKernelHash *ent, *hit;
  I64 (*fp)();
  bfh = KernelLoad("A:/Runtime/Svc.BIN");
  if (!bfh || *(bfh(U8 *) + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -1;
  ptoff = KernelReadI64(bfh(U8 *) + 16);
  if (ptoff <= 0)
    return -2;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -3;
  module_base = bfh(U8 *) + KERNEL_CBIN_HDR;
  pt = bfh(U8 *) + ptoff;
  nexp = 0;
  while (TRUE) {
    etype = *pt++;
    if (etype == KERNEL_IET_END)
      break;
    i = *(pt(U32 *));
    pt += 4;
    st = pt;
    while (*pt)
      pt++;
    pt++;
    if (!*st)
      return -4;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
        addr = i;
      else
        addr = module_base + i;
      ent = KernelArenaAlloc(sizeof(CKernelHash));
      if (!ent)
        return -5;
      KernelMemSet(ent(U8 *), 0, sizeof(CKernelHash));
      ent->str = st;
      ent->type = KERNEL_HTT_EXPORT;
      ent->val = addr;
      KernelHashAdd(ent, table);
      nexp++;
    } else {
      return -6;
    }
  }
  if (nexp < 1)
    return -7;
  hit = KernelHashFind("RuntimeSvcProbe", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -8;
  fp = hit->val;
  r = fp();
  if (r != 42)
    return -9;
  if (KernelHashFind("NoSuchExport", table, KERNEL_HTT_EXPORT, 1))
    return -10;
  return 0x4B43;
  // 'KC'
}
// SoftCall product Runtime Kern Load (G9): RedSea FileFind+Load Kern.BIN → HashAdd →
// HashFind→Call KernInit→42. StartOS Seed→Svc→Kern chain tip (arg+call+add;
// no Cmp). Same HashFind ownership as SeedSoft/SvcSoft on product A:/Runtime/.
public I64 KernelKernSoft()
{
  U8 *pt, *st, *module_base;
  I64 bfh, ptoff, etype, i, addr, nexp, r;
  CKernelHashTable *table;
  CKernelHash *ent, *hit;
  I64 (*fp)();
  bfh = KernelLoad("A:/Runtime/Kern.BIN");
  if (!bfh || *(bfh(U8 *) + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -1;
  ptoff = KernelReadI64(bfh(U8 *) + 16);
  if (ptoff <= 0)
    return -2;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -3;
  module_base = bfh(U8 *) + KERNEL_CBIN_HDR;
  pt = bfh(U8 *) + ptoff;
  nexp = 0;
  while (TRUE) {
    etype = *pt++;
    if (etype == KERNEL_IET_END)
      break;
    i = *(pt(U32 *));
    pt += 4;
    st = pt;
    while (*pt)
      pt++;
    pt++;
    if (!*st)
      return -4;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
        addr = i;
      else
        addr = module_base + i;
      ent = KernelArenaAlloc(sizeof(CKernelHash));
      if (!ent)
        return -5;
      KernelMemSet(ent(U8 *), 0, sizeof(CKernelHash));
      ent->str = st;
      ent->type = KERNEL_HTT_EXPORT;
      ent->val = addr;
      KernelHashAdd(ent, table);
      nexp++;
    } else {
      return -6;
    }
  }
  if (nexp < 1)
    return -7;
  hit = KernelHashFind("KernInit", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -8;
  fp = hit->val;
  r = fp();
  if (r != 42)
    return -9;
  if (KernelHashFind("NoSuchExport", table, KERNEL_HTT_EXPORT, 1))
    return -10;
  return 0x4B4B;
  // 'KK'
}
// SoftCall StartOS-shaped multi-BIN sequence (G9): Seed→Svc→Kern Softs in order.
// One SoftCall owns the Runtime Load chain (phase3 StartOS Loads Seed/Svc/Kern;
// no Cmp). Keeps single-BIN Softs; this tip is sequential Load ownership.
public I64 KernelStartSoft()
{
  I64 r;
  if (!KernelFileFind("A:/Runtime/Seed.BIN"))
    return -1;
  if (!KernelFileFind("A:/Runtime/Svc.BIN"))
    return -2;
  if (!KernelFileFind("A:/Runtime/Kern.BIN"))
    return -3;
  r = KernelSeedSoft();
  if (r != 0x4B52)
    return -4;
  r = KernelSvcSoft();
  if (r != 0x4B43)
    return -5;
  r = KernelKernSoft();
  if (r != 0x4B4B)
    return -6;
  return 0x4B55;
  // 'KU'
}
// SoftCall product Adam StartOS Load (G9): RedSea FileFind+Load StartOS.BIN →
// HashAdd → HashFind→Call StartOSProbe→1. Phase3 StartOS Load→Call needle
// (no Cmp; no DocTerm/Menu). Same HashFind ownership as MakeSoft on A:/Adam/.
public I64 KernelAdamSoft()
{
  U8 *pt, *st, *module_base;
  I64 bfh, ptoff, etype, i, addr, nexp, r;
  CKernelHashTable *table;
  CKernelHash *ent, *hit;
  I64 (*fp)();
  bfh = KernelLoad("A:/Adam/StartOS.BIN");
  if (!bfh || *(bfh(U8 *) + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -1;
  ptoff = KernelReadI64(bfh(U8 *) + 16);
  if (ptoff <= 0)
    return -2;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -3;
  module_base = bfh(U8 *) + KERNEL_CBIN_HDR;
  pt = bfh(U8 *) + ptoff;
  nexp = 0;
  while (TRUE) {
    etype = *pt++;
    if (etype == KERNEL_IET_END)
      break;
    i = *(pt(U32 *));
    pt += 4;
    st = pt;
    while (*pt)
      pt++;
    pt++;
    if (!*st)
      return -4;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
        addr = i;
      else
        addr = module_base + i;
      ent = KernelArenaAlloc(sizeof(CKernelHash));
      if (!ent)
        return -5;
      KernelMemSet(ent(U8 *), 0, sizeof(CKernelHash));
      ent->str = st;
      ent->type = KERNEL_HTT_EXPORT;
      ent->val = addr;
      KernelHashAdd(ent, table);
      nexp++;
    } else {
      return -6;
    }
  }
  if (nexp < 1)
    return -7;
  hit = KernelHashFind("StartOSProbe", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -8;
  fp = hit->val;
  r = fp();
  if (r != 1)
    return -9;
  if (KernelHashFind("NoSuchExport", table, KERNEL_HTT_EXPORT, 1))
    return -10;
  return 0x4B41;
  // 'KA'
}
// SoftCall KDate (G9): import-free Kernel_RV KDate.HC calendar + Goldfish RTC Now.
// Past thin KThinDateStubs (Jump never stamps dates; SoftCall owns real time).
#define KERNEL_CDATE_YEAR_DAYS_INT 36524225
#define KERNEL_CDATE_BASE_DOW 0
U16 kernel_mon_start_days1[12] = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334};
U16 kernel_mon_start_days2[12] = {0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335};
class CKernelDate
{
  U32 time;
  I32 date;
};

class CKernelDateStruct
{
  U8 sec10000, sec100, sec, min, hour, day_of_week, day_of_mon, mon;
  I32 year;
};

I64 KernelYearStartDate(I64 year)
{
  I64 y1 = year - 1, yd4000 = y1 / 4000, yd400 = y1 / 400, yd100 = y1 / 100, yd4 = y1 / 4;
  return year * 365 + yd4 - yd100 + yd400 - yd4000;
}

CKernelDate KernelStruct2Date(CKernelDateStruct *_ds)
{
  CKernelDate cdt;
  I64 i1, i2;
  cdt.time = 0;
  cdt.date = 0;
  if (!_ds)
    return cdt;
  i1 = KernelYearStartDate(_ds->year);
  i2 = KernelYearStartDate(_ds->year + 1);
  if (i2 - i1 == 365)
    i1 += kernel_mon_start_days1[_ds->mon - 1];
  else
    i1 += kernel_mon_start_days2[_ds->mon - 1];
  cdt.date = i1 + _ds->day_of_mon - 1;
  cdt.time = (_ds->sec10000 + 100 * (_ds->sec100 + 100 * (_ds->sec + 60 * (_ds->min + 60 * _ds->hour)))) << 21 / (15 * 15 * 3 * 625);
  return cdt;
}

I64 KernelDayOfWeek(I64 i)
{
  i += KERNEL_CDATE_BASE_DOW;
  if (i >= 0)
    return i % 7;
  return 6 - (6 - i) % 7;
}

U0 KernelDate2Struct(CKernelDateStruct *_ds, CKernelDate cdt)
{
  I64 i, k, date = cdt.date, rem;
  if (!_ds)
    return;
  KernelMemSet(_ds(U8 *), 0, sizeof(CKernelDateStruct));
  _ds->day_of_week = KernelDayOfWeek(date);
  _ds->year = (date + 1) * 100000 / KERNEL_CDATE_YEAR_DAYS_INT;
  i = KernelYearStartDate(_ds->year);
  while (i > date) {
    _ds->year--;
    i = KernelYearStartDate(_ds->year);
  }
  date -= i;
  if (KernelYearStartDate(_ds->year + 1) - i == 365) {
    k = 0;
    while (date >= kernel_mon_start_days1[k + 1] && k < 11)
      k++;
    date -= kernel_mon_start_days1[k];
  } else {
    k = 0;
    while (date >= kernel_mon_start_days2[k + 1] && k < 11)
      k++;
    date -= kernel_mon_start_days2[k];
  }
  _ds->mon = k + 1;
  _ds->day_of_mon = date + 1;
  rem = ((625 * 15 * 15 * 3 * cdt.time) >> 21) + 1;
  _ds->sec10000 = rem % 100;
  rem = rem / 100;
  _ds->sec100 = rem % 100;
  rem = rem / 100;
  _ds->sec = rem % 60;
  rem = rem / 60;
  _ds->min = rem % 60;
  _ds->hour = rem / 60;
}

I64 KernelRtcReadNs()
{
  U32 *rtc = CONFIG_RTC_BASE;
  U64 lo, hi;
  lo = rtc[0];
  hi = rtc[1];
  return lo | (hi << 32);
}

U0 KernelNowDateTimeStruct(CKernelDateStruct *_ds)
{
  U64 ns, secs;
  I64 days, sod;
  CKernelDate cdt;
  if (!_ds)
    return;
  KernelMemSet(_ds(U8 *), 0, sizeof(CKernelDateStruct));
  ns = KernelRtcReadNs;
  secs = ns / 1000000000;
  days = secs / 86400;
  sod = secs % 86400;
  cdt.date = KernelYearStartDate(1970) + days;
  cdt.time = 0;
  KernelDate2Struct(_ds, cdt);
  _ds->hour = sod / 3600;
  _ds->min = sod % 3600 / 60;
  _ds->sec = sod % 60;
}
// SoftCall prove: Struct2Date↔Date2Struct + DayOfWeek + RTC Now (year in range).
public I64 KernelDateSoft()
{
  CKernelDateStruct ds, ds2, now;
  CKernelDate cdt;
  I64 y1970, dow;
  KernelMemSet(&ds, 0, sizeof(CKernelDateStruct));
  ds.year = 2024;
  ds.mon = 3;
  ds.day_of_mon = 15;
  ds.hour = 12;
  ds.min = 30;
  ds.sec = 45;
  cdt = KernelStruct2Date(&ds);
  if (cdt.date <= 0)
    return -1;
  KernelDate2Struct(&ds2, cdt);
  if (ds2.year != 2024 || ds2.mon != 3 || ds2.day_of_mon != 15)
    return -2;
  if (ds2.hour != 12 || ds2.min != 30 || ds2.sec != 45)
    return -3;
  y1970 = KernelYearStartDate(1970);
  if (y1970 != KernelYearStartDate(1969) + 365)
    return -4;
  // 2024-03-15 is Friday → DOW 5 when BASE=0 and day0=Sun (TempleOS CDATE_BASE=0).
  dow = KernelDayOfWeek(cdt.date);
  if (dow < 0 || dow > 6)
    return -5;
  if (dow != ds2.day_of_week)
    return -6;
  KernelNowDateTimeStruct(&now);
  if (now.year < 2020 || now.year > 2099)
    return -7;
  if (now.mon < 1 || now.mon > 12)
    return -8;
  if (now.day_of_mon < 1 || now.day_of_mon > 31)
    return -9;
  if (now.hour > 23 || now.min > 59 || now.sec > 59)
    return -10;
  return 0x4B47;
  // 'KG'
}
// SoftCall QSort (G9): import-free Kernel_RV QSort.HC QSortI64 (DirEntry path).
// Past thin KThinQSortStubs (Jump never sorts; SoftCall owns real quicksort).
I64 KernelQSortCmpAsc(I64 e1, I64 e2)
{
  return e1 - e2;
}

U0 KernelSwapI64(I64 *a, I64 *b)
{
  I64 t;
  if (!a || !b)
    return;
  t = *a;
  *a = *b;
  *b = t;
}

U0 KernelQSortI64(I64 *base, I64 num, I64 (*fp_compare)(I64 e1, I64 e2))
{
  I64 i, *left, *right, pivot;
  if (!base || !fp_compare || num <= 1)
    return;
  left = base;
  right = base + num - 1;
  pivot = base[num / 2];
  do {
    while ((*fp_compare)(*left, pivot) < 0)
      left++;
    while ((*fp_compare)(*right, pivot) > 0)
      right--;
    if (left <= right) {
      KernelSwapI64(left, right);
      left++;
      right--;
    }
  } while (left <= right);
  i = right + 1 - base;
  if (1 < i && i < num)
    KernelQSortI64(base, i, fp_compare);
  i = base + num - left;
  if (1 < i && i < num)
    KernelQSortI64(left, i, fp_compare);
}
// SoftCall prove: unsorted→ascending, already-sorted stable, singleton no-op.
public I64 KernelQSortSoft()
{
  I64 a[8], b[4], c[1], i;
  a[0] = 5;
  a[1] = 1;
  a[2] = 4;
  a[3] = 2;
  a[4] = 3;
  a[5] = 8;
  a[6] = 0;
  a[7] = 7;
  KernelQSortI64(a, 8, &KernelQSortCmpAsc);
  for (i = 0; i < 7; i++)
    if (a[i] > a[i + 1])
      return -1;
  if (a[0] != 0 || a[1] != 1 || a[2] != 2 || a[3] != 3)
    return -2;
  if (a[4] != 4 || a[5] != 5 || a[6] != 7 || a[7] != 8)
    return -3;
  b[0] = 1;
  b[1] = 2;
  b[2] = 3;
  b[3] = 4;
  KernelQSortI64(b, 4, &KernelQSortCmpAsc);
  if (b[0] != 1 || b[1] != 2 || b[2] != 3 || b[3] != 4)
    return -4;
  c[0] = 42;
  KernelQSortI64(c, 1, &KernelQSortCmpAsc);
  if (c[0] != 42)
    return -5;
  KernelQSortI64(NULL, 0, &KernelQSortCmpAsc);
  return 0x4B4F;
  // 'KO'
}
// SoftCall KeyDev (G9): import-free Kernel_RV KeyDev.HC StdOut chain + Ctrl-Alt CB
// table (past thin KThinKeyDevStubs — Jump keeps UART PutS/KeyDevAdd only; SoftCall
// owns priority PutKey/PutS + Rem + CtrlAltCBSet shape; no SCROLL Yield/KDRaw/Msg).
#define KERNEL_KDF_HAS_DESCS 1
class CKernelKeyDevEntry
{
  CKernelKeyDevEntry *next, *last;
  I64 priority, flags;
  // I64 slots (not Bool (*)()) — host SoftCall seed avoids fp-member parse fights.
  I64 put_key;
  I64 put_s;
};

class CKernelKeyDevGlbls
{
  CKernelKeyDevEntry put_key_head;
  I64 fp_ctrl_alt_cbs;
  I64 ctrl_alt_in_irq_flags;
};
CKernelKeyDevGlbls kernel_keydev;
U8 kernel_kd_cap[16];
I64 kernel_kd_cap_n;
I64 kernel_kd_alt_hits;
CKernelKeyDevEntry kernel_kd_e_lo, kernel_kd_e_hi, kernel_kd_e_s;
I64 kernel_kd_alt_cbs[26];
U0 KernelKeyDevQueInit(CKernelKeyDevEntry *head)
{
  head->next = head->last = head;
  head->priority = 0;
  head->flags = 0;
  head->put_key = 0;
  head->put_s = 0;
}

U0 KernelKeyDevQueIns(CKernelKeyDevEntry *item, CKernelKeyDevEntry *pred)
{
  item->next = pred->next;
  item->last = pred;
  pred->next->last = item;
  pred->next = item;
}

U0 KernelKeyDevQueRem(CKernelKeyDevEntry *item)
{
  item->next->last = item->last;
  item->last->next = item->next;
  item->next = item->last = item;
}

U0 KernelKeyDevRem(CKernelKeyDevEntry *tmpk)
{
  if (!tmpk)
    return;
  KernelKeyDevQueRem(tmpk);
  tmpk->put_key = 0;
  tmpk->put_s = 0;
}

CKernelKeyDevEntry *KernelKeyDevAdd(CKernelKeyDevEntry *ent, I64 fp_put_key, I64 fp_puts, I64 priority, Bool key_descs)
{
  CKernelKeyDevEntry *tmpk;
  if (!ent)
    return NULL;
  ent->put_key = fp_put_key;
  ent->put_s = fp_puts;
  ent->priority = priority;
  ent->flags = 0;
  if (key_descs)
    ent->flags = KERNEL_KDF_HAS_DESCS;
  tmpk = kernel_keydev.put_key_head.last;
  while (tmpk != &kernel_keydev.put_key_head && tmpk->priority > priority)
    tmpk = tmpk->last;
  KernelKeyDevQueIns(ent, tmpk);
  return ent;
}

U0 KernelPutKey(I64 ch, I64 sc)
{
  CKernelKeyDevEntry *tmpk;
  Bool (*fp)(I64, I64);
  if (!(ch || sc))
    return;
  tmpk = kernel_keydev.put_key_head.next;
  while (tmpk != &kernel_keydev.put_key_head) {
    if (tmpk->put_key) {
      fp = tmpk->put_key;
      if ((*fp)(ch, sc))
        break;
    }
    tmpk = tmpk->next;
  }
}

U0 KernelPutS(U8 *st)
{
  I64 ch;
  U8 *ptr;
  Bool cont = TRUE;
  CKernelKeyDevEntry *tmpk;
  Bool (*fp_s)(U8 *);
  Bool (*fp_k)(I64, I64);
  if (!st)
    return;
  tmpk = kernel_keydev.put_key_head.next;
  while (cont && tmpk != &kernel_keydev.put_key_head) {
    if (tmpk->put_s) {
      fp_s = tmpk->put_s;
      if ((*fp_s)(st))
        break;
    } else if (tmpk->put_key) {
      fp_k = tmpk->put_key;
      ptr = st;
      while (ch = *ptr++)
        if ((*fp_k)(ch, 0))
          cont = FALSE;
    }
    tmpk = tmpk->next;
  }
}

U0 KernelCtrlAltCBSet(U8 ch, I64 fp_hndlr, Bool in_irq)
{
  I64 i;
  if (ch >= 'a' && ch <= 'z')
    ch = ch - 'a' + 'A';
  i = ch - 'A';
  if (i < 0 || i >= 26)
    return;
  kernel_kd_alt_cbs[i] = fp_hndlr;
  if (in_irq)
    kernel_keydev.ctrl_alt_in_irq_flags = kernel_keydev.ctrl_alt_in_irq_flags | (1 << i);
  else
    kernel_keydev.ctrl_alt_in_irq_flags = kernel_keydev.ctrl_alt_in_irq_flags & ~(1 << i);
  kernel_keydev.fp_ctrl_alt_cbs = &kernel_kd_alt_cbs;
}

Bool KernelKDPutKeyLo(I64 ch, I64 sc)
{
  no_warn sc;
  if (kernel_kd_cap_n < 15) {
    kernel_kd_cap[kernel_kd_cap_n] = ch;
    kernel_kd_cap_n++;
    kernel_kd_cap[kernel_kd_cap_n] = 0;
  }
  return FALSE;
}

Bool KernelKDPutKeyHi(I64 ch, I64 sc)
{
  no_warn sc;
  if (ch == 'X')
    return TRUE;
  return FALSE;
}

Bool KernelKDPutS(U8 *st)
{
  I64 i;
  if (!st)
    return FALSE;
  // Consume whole string into cap (priority mid); proves put_s short-circuit.
  i = 0;
  while (st[i] && kernel_kd_cap_n < 15) {
    kernel_kd_cap[kernel_kd_cap_n] = st[i];
    kernel_kd_cap_n++;
    i++;
  }
  kernel_kd_cap[kernel_kd_cap_n] = 0;
  return TRUE;
}

U0 KernelKDAltC(I64 sc)
{
  no_warn sc;
  kernel_kd_alt_hits++;
}
// SoftCall prove: priority PutKey eat + PutS put_s + Rem fallthrough + CtrlAltCB.
public I64 KernelKeyDevSoft()
{
  I64 i;
  U0 (*fp_alt)(I64);
  KernelMemSet(&kernel_keydev, 0, sizeof(CKernelKeyDevGlbls));
  KernelMemSet(&kernel_kd_e_lo, 0, sizeof(CKernelKeyDevEntry));
  KernelMemSet(&kernel_kd_e_hi, 0, sizeof(CKernelKeyDevEntry));
  KernelMemSet(&kernel_kd_e_s, 0, sizeof(CKernelKeyDevEntry));
  KernelMemSet(kernel_kd_cap, 0, 16);
  kernel_kd_cap_n = 0;
  kernel_kd_alt_hits = 0;
  for (i = 0; i < 26; i++)
    kernel_kd_alt_cbs[i] = 0;
  KernelKeyDevQueInit(&kernel_keydev.put_key_head);
  // KeyDevAdd: lower priority number sits earlier in forward walk (Init: IF then Raw).
  // e_hi = early eater (0x1000); e_s = mid put_s (0x40000000); e_lo = late record (0x60000000).
  KernelKeyDevAdd(&kernel_kd_e_hi, &KernelKDPutKeyHi, 0, 0x1000, FALSE);
  KernelKeyDevAdd(&kernel_kd_e_lo, &KernelKDPutKeyLo, 0, 0x60000000, FALSE);
  KernelKeyDevAdd(&kernel_kd_e_s, 0, &KernelKDPutS, 0x40000000, FALSE);
  // Forward walk: eater → put_s → recorder.
  if (kernel_keydev.put_key_head.next != &kernel_kd_e_hi)
    return -1;
  if (kernel_kd_e_hi.next != &kernel_kd_e_s)
    return -2;
  if (kernel_kd_e_s.next != &kernel_kd_e_lo)
    return -3;
  KernelPutKey('A', 0);
  if (kernel_kd_cap_n != 1 || kernel_kd_cap[0] != 'A')
    return -4;
  KernelPutKey('X', 0);
  if (kernel_kd_cap_n != 1)
    return -5;
  KernelPutS("KW");
  if (kernel_kd_cap_n != 3 || kernel_kd_cap[1] != 'K' || kernel_kd_cap[2] != 'W')
    return -6;
  // Rem put_s → PutS falls through put_key eater (miss) then recorder.
  KernelKeyDevRem(&kernel_kd_e_s);
  kernel_kd_cap_n = 0;
  kernel_kd_cap[0] = 0;
  KernelPutS("Z");
  if (kernel_kd_cap_n != 1 || kernel_kd_cap[0] != 'Z')
    return -7;
  KernelCtrlAltCBSet('C', &KernelKDAltC, TRUE);
  if (!kernel_keydev.fp_ctrl_alt_cbs || !kernel_kd_alt_cbs[2])
    return -8;
  if (!(kernel_keydev.ctrl_alt_in_irq_flags & (1 << 2)))
    return -9;
  fp_alt = kernel_kd_alt_cbs[2];
  (*fp_alt)(0);
  if (kernel_kd_alt_hits != 1)
    return -10;
  return 0x4B57;
  // 'KW'
}
// SoftCall Except (G9): import-free Kernel_RV KExcept.HC try/throw/catch queue
// (past thin PutExcept stub; SoftCall owns SysTry/SysUntry/throw/PutExcept HolyC
// shape — no x86 TestExcept/TakeExcept/SaveExceptRegs asm unwind).
class CKernelExcept
{
  CKernelExcept *next, *last;
  I64 hndlr_catch;
  I64 hndlr_untry;
  I64 rsp, rbp, rflags;
  I64 tag;
};

class CKernelExceptTask
{
  CKernelExcept next_except;
  I64 except_ch;
  Bool catch_except;
  I64 catch_hits;
  I64 untry_hits;
  I64 throw_walks;
};
CKernelExceptTask kernel_ex;
CKernelExcept kernel_ex_a, kernel_ex_b;
U0 KernelExceptQueInit(CKernelExcept *head)
{
  head->next = head->last = head;
  head->hndlr_catch = 0;
  head->hndlr_untry = 0;
  head->rsp = 0;
  head->rbp = 0;
  head->rflags = 0;
  head->tag = 0;
}

U0 KernelExceptQueIns(CKernelExcept *item, CKernelExcept *pred)
{
  item->next = pred->next;
  item->last = pred;
  pred->next->last = item;
  pred->next = item;
}

U0 KernelExceptQueRem(CKernelExcept *item)
{
  item->next->last = item->last;
  item->last->next = item->next;
  item->next = item->last = item;
}

U0 KernelSysTry(CKernelExcept *tmpt, I64 fp_catch, I64 fp_untry, I64 tag)
{
  if (!tmpt)
    return;
  tmpt->hndlr_catch = fp_catch;
  tmpt->hndlr_untry = fp_untry;
  tmpt->rsp = 0;
  tmpt->rbp = 0;
  tmpt->rflags = 0;
  tmpt->tag = tag;
  // Fs shape: QueIns(tmpt, Fs->last_except) — last is head->last.
  KernelExceptQueIns(tmpt, kernel_ex.next_except.last);
}

U0 KernelSysUntry()
{
  CKernelExcept *tmpt = kernel_ex.next_except.last;
  if (tmpt == &kernel_ex.next_except)
    return;
  KernelExceptQueRem(tmpt);
  tmpt->hndlr_catch = 0;
  tmpt->hndlr_untry = 0;
  tmpt->tag = 0;
}

U0 KernelPutExcept(Bool catch_it)
{
  kernel_ex.catch_except = catch_it;
}

U0 KernelExCatchOk()
{
  kernel_ex.catch_hits++;
  KernelPutExcept(TRUE);
}

U0 KernelExCatchPass()
{
  kernel_ex.catch_hits++;
  KernelPutExcept(FALSE);
}

U0 KernelExUntry()
{
  kernel_ex.untry_hits++;
}

U0 KernelThrow(I64 ch)
{
  CKernelExcept *tmpt;
  U0 (*fp_c)();
  U0 (*fp_u)();
  kernel_ex.except_ch = ch;
  kernel_ex.catch_except = FALSE;
  while (kernel_ex.next_except.next != &kernel_ex.next_except) {
    kernel_ex.throw_walks++;
    tmpt = kernel_ex.next_except.last;
    if (tmpt->hndlr_catch) {
      fp_c = tmpt->hndlr_catch;
      (*fp_c)();
    }
    if (kernel_ex.catch_except) {
      if (tmpt->hndlr_untry) {
        fp_u = tmpt->hndlr_untry;
        (*fp_u)();
      }
      KernelExceptQueRem(tmpt);
      tmpt->hndlr_catch = 0;
      tmpt->hndlr_untry = 0;
      tmpt->tag = 0;
      return;
    }
    KernelExceptQueRem(tmpt);
    tmpt->hndlr_catch = 0;
    tmpt->hndlr_untry = 0;
    tmpt->tag = 0;
  }
}
// SoftCall prove: try→throw→catch+untry; nested inner catch; outer after pass.
public I64 KernelExceptSoft()
{
  KernelMemSet(&kernel_ex, 0, sizeof(CKernelExceptTask));
  KernelMemSet(&kernel_ex_a, 0, sizeof(CKernelExcept));
  KernelMemSet(&kernel_ex_b, 0, sizeof(CKernelExcept));
  KernelExceptQueInit(&kernel_ex.next_except);
  // Single try: catch sets PutExcept(TRUE) → throw walks → untry → stack empty.
  KernelSysTry(&kernel_ex_a, &KernelExCatchOk, &KernelExUntry, 1);
  if (kernel_ex.next_except.last != &kernel_ex_a)
    return -1;
  KernelThrow('X');
  if (kernel_ex.except_ch != 'X')
    return -2;
  if (kernel_ex.catch_hits != 1 || kernel_ex.untry_hits != 1)
    return -3;
  if (kernel_ex.throw_walks != 1)
    return -4;
  if (kernel_ex.next_except.next != &kernel_ex.next_except)
    return -5;
  // Nested: outer pass + inner catch — throw stops at inner (last).
  kernel_ex.catch_hits = 0;
  kernel_ex.untry_hits = 0;
  kernel_ex.throw_walks = 0;
  kernel_ex.except_ch = 0;
  KernelSysTry(&kernel_ex_a, &KernelExCatchPass, &KernelExUntry, 10);
  KernelSysTry(&kernel_ex_b, &KernelExCatchOk, &KernelExUntry, 20);
  if (kernel_ex.next_except.last != &kernel_ex_b)
    return -6;
  if (kernel_ex_b.last != &kernel_ex_a)
    return -7;
  KernelThrow('Z');
  if (kernel_ex.except_ch != 'Z')
    return -8;
  // Inner catch+untry only; outer frame still on stack.
  if (kernel_ex.catch_hits != 1 || kernel_ex.untry_hits != 1)
    return -9;
  if (kernel_ex.throw_walks != 1)
    return -10;
  if (kernel_ex.next_except.last != &kernel_ex_a)
    return -11;
  if (kernel_ex_a.tag != 10)
    return -12;
  // Outer SysUntry (normal try exit) empties stack.
  KernelSysUntry();
  if (kernel_ex.next_except.next != &kernel_ex.next_except)
    return -13;
  // Uncaught: throw with empty stack leaves except_ch; PutExcept shape.
  kernel_ex.catch_hits = 0;
  kernel_ex.throw_walks = 0;
  KernelThrow('E');
  if (kernel_ex.except_ch != 'E' || kernel_ex.throw_walks != 0)
    return -14;
  KernelPutExcept(TRUE);
  if (!kernel_ex.catch_except)
    return -15;
  KernelPutExcept(FALSE);
  if (kernel_ex.catch_except)
    return -16;
  return 0x4B5A;
  // 'KZ'
}
// SoftCall Mem (G9): import-free Kernel_RV HeapCtrl+MAllocFree HolyC shape (past
// thin KThinMemStubs linear arena; SoftCall owns hash-bucket Free→reuse + MSize +
// CAlloc + StrNew — no MemPag/PageTables/BlkPool/x86 _MALLOC asm).
#define KERNEL_MEM_SOFT_ARENA 4096
#define KERNEL_MEM_HASH_SLOTS 16
#define KERNEL_MEM_HDR 16
#define KERNEL_MEM_HC_SIG 0x48635356
// 'HcSV'
class CKernelMemUnused
{
  CKernelMemUnused *next;
  I64 size;
};

class CKernelMemUsed
{
  I64 hc_sig;
  I64 size;
};
I64 kernel_mem_used_u8s;
I64 kernel_mem_alloced_u8s;
I64 kernel_mem_arena_next;
CKernelMemUnused *kernel_mem_hash[KERNEL_MEM_HASH_SLOTS];
U8 kernel_mem_soft_arena[KERNEL_MEM_SOFT_ARENA];
I64 KernelMemRound(I64 size)
{
  I64 n = (size + 7) & ~7;
  if (n < 8)
    n = 8;
  return n;
}

I64 KernelMemHashIdx(I64 size)
{
  I64 n = KernelMemRound(size);
  if (n >= KERNEL_MEM_HASH_SLOTS * 8)
    n = (KERNEL_MEM_HASH_SLOTS - 1) * 8;
  return n >> 3;
}

U0 KernelHeapCtrlInitSoft()
{
  I64 i;
  kernel_mem_used_u8s = 0;
  kernel_mem_alloced_u8s = 0;
  kernel_mem_arena_next = 0;
  for (i = 0; i < KERNEL_MEM_HASH_SLOTS; i++)
    kernel_mem_hash[i] = NULL;
  KernelMemSet(kernel_mem_soft_arena, 0, KERNEL_MEM_SOFT_ARENA);
}

U8 *KernelMAllocSoft(I64 size)
{
  I64 need, idx;
  CKernelMemUnused *f;
  CKernelMemUsed *u;
  U8 *p;
  if (size <= 0)
    return NULL;
  need = KernelMemRound(size);
  idx = KernelMemHashIdx(need);
  // Product shape: heap_hash[rounded size] free-list pop.
  f = kernel_mem_hash[idx];
  if (f && f->size >= need) {
    kernel_mem_hash[idx] = f->next;
    u = f(CKernelMemUsed *);
    u->hc_sig = KERNEL_MEM_HC_SIG;
    u->size = need;
    kernel_mem_used_u8s += need;
    return u(U8 *) + KERNEL_MEM_HDR;
  }
  // Fresh bump from SoftCall-owned arena (not thin linear MAlloc).
  if (kernel_mem_arena_next + KERNEL_MEM_HDR + need > KERNEL_MEM_SOFT_ARENA)
    return NULL;
  p = kernel_mem_soft_arena + kernel_mem_arena_next;
  kernel_mem_arena_next += KERNEL_MEM_HDR + need;
  kernel_mem_alloced_u8s += KERNEL_MEM_HDR + need;
  u = p(CKernelMemUsed *);
  u->hc_sig = KERNEL_MEM_HC_SIG;
  u->size = need;
  kernel_mem_used_u8s += need;
  return p + KERNEL_MEM_HDR;
}

U0 KernelFreeSoft(U8 *p)
{
  CKernelMemUsed *u;
  CKernelMemUnused *f;
  I64 idx, sz;
  if (!p)
    return;
  u = (p - KERNEL_MEM_HDR)(CKernelMemUsed *);
  if (u->hc_sig != KERNEL_MEM_HC_SIG || u->size < 8)
    return;
  sz = u->size;
  idx = KernelMemHashIdx(sz);
  if (kernel_mem_used_u8s >= sz)
    kernel_mem_used_u8s -= sz;
  f = u(CKernelMemUnused *);
  f->size = sz;
  f->next = kernel_mem_hash[idx];
  kernel_mem_hash[idx] = f;
}

I64 KernelMSizeSoft(U8 *p)
{
  CKernelMemUsed *u;
  if (!p)
    return 0;
  u = (p - KERNEL_MEM_HDR)(CKernelMemUsed *);
  if (u->hc_sig != KERNEL_MEM_HC_SIG)
    return 0;
  return u->size;
}

U8 *KernelCAllocSoft(I64 size)
{
  U8 *res = KernelMAllocSoft(size);
  if (res)
    KernelMemSet(res, 0, size);
  return res;
}

U8 *KernelStrNewSoft(U8 *buf)
{
  U8 *res;
  I64 n;
  if (!buf)
    return KernelCAllocSoft(1);
  n = KernelStrLen(buf) + 1;
  res = KernelMAllocSoft(n);
  if (res)
    KernelMemCpy(res, buf, n);
  return res;
}
// SoftCall prove: HeapCtrlInit + MAlloc/MSize + Free→hash reuse + CAlloc + StrNew.
public I64 KernelMemSoft()
{
  U8 *a, *b, *c, *s;
  KernelHeapCtrlInitSoft;
  a = KernelMAllocSoft(24);
  if (!a)
    return -2;
  if (KernelMSizeSoft(a) < 24)
    return -3;
  a[0] = 'K';
  a[1] = 'H';
  a[2] = 0;
  if (KernelStrLen(a) != 2)
    return -4;
  // Free→hash bucket; next same-size MAlloc must reuse.
  KernelFreeSoft(a);
  b = KernelMAllocSoft(24);
  if (!b)
    return -15;
  if (b != a)
    return -5;
  if (b[0] != 'K')
    return -6;
  // CAlloc zeros reused payload.
  KernelFreeSoft(b);
  c = KernelCAllocSoft(24);
  if (!c || c != a)
    return -7;
  if (c[0] || c[1] || c[23])
    return -8;
  KernelFreeSoft(c);
  s = KernelStrNewSoft("KH");
  if (!s || KernelStrLen(s) != 2 || s[0] != 'K' || s[1] != 'H')
    return -9;
  if (KernelMSizeSoft(s) < 3)
    return -10;
  // Distinct size-class: no steal from 24-bucket.
  a = KernelMAllocSoft(64);
  if (!a || a == s)
    return -11;
  if (KernelMSizeSoft(a) < 64)
    return -12;
  KernelFreeSoft(a);
  KernelFreeSoft(s);
  if (kernel_mem_used_u8s)
    return -13;
  if (!kernel_mem_alloced_u8s)
    return -14;
  return 0x4B48;
  // 'KH'
}
// SoftCall StrUtil (G9): import-free Kernel_RV StrA/StrB HolyC shape (past thin
// KThinStrUtilStubs identity/StrNew stubs; SoftCall owns path-normalize flags +
// case/space transforms — no Spaces2Tabs/T2S/ScaleIndent/full char_bmp tables).
#define KERNEL_SUF_REM_CTRL_CHARS 0x001
#define KERNEL_SUF_REM_LEADING 0x002
#define KERNEL_SUF_REM_TRAILING 0x004
#define KERNEL_SUF_REM_SPACES 0x008
#define KERNEL_SUF_SINGLE_SPACE 0x010
#define KERNEL_SUF_TO_UPPER 0x020
#define KERNEL_SUF_TO_LOWER 0x040
#define KERNEL_CH_SHIFT_SPACE 0x1F
#define KERNEL_CH_SPACE 0x20
#define KERNEL_STRUTIL_SOFT_BUF 128
U8 kernel_strutil_soft_buf[KERNEL_STRUTIL_SOFT_BUF];
Bool KernelIsWhite(U8 ch)
{
  return ch == KERNEL_CH_SPACE || ch == '\t' || ch == '\r' || ch == '\n';
}

Bool KernelStrEq(U8 *a, U8 *b)
{
  if (!a || !b)
    return a == b;
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return *a == *b;
}

U8 *KernelStrUtilDo(U8 *_src, I64 flags)
{
  U8 *src = _src, *dst = _src;
  I64 ch;
  if (!_src)
    return NULL;
  if (flags & KERNEL_SUF_REM_LEADING)
    while (KernelIsWhite (*src))
      src++;
  while (ch = *src++) {
    if (KernelIsWhite(ch)) {
      if (!(flags & KERNEL_SUF_REM_SPACES)) {
        if (flags & KERNEL_SUF_SINGLE_SPACE) {
          *dst++ = KERNEL_CH_SPACE;
          while ((ch = *src++) && KernelIsWhite(ch))
            ;
          src--;
        } else
          *dst++ = ch;
      }
    } else if (!(flags & KERNEL_SUF_REM_CTRL_CHARS) || ch >= KERNEL_CH_SHIFT_SPACE)
      *dst++ = ch;
  }
  *dst = 0;
  if (flags & KERNEL_SUF_REM_TRAILING)
    while (dst != _src && (!*dst || KernelIsWhite (*dst)))
      *dst-- = 0;
  if (flags & KERNEL_SUF_TO_UPPER)
    for (dst = _src; *dst; dst++) {
      ch = *dst;
      if ('a' <= ch <= 'z')
        *dst = ch - 0x20;
    }
  if (flags & KERNEL_SUF_TO_LOWER)
    for (dst = _src; *dst; dst++) {
      ch = *dst;
      if ('A' <= ch <= 'Z')
        *dst = ch + 0x20;
    }
  return _src;
}

U8 *KernelMStrUtilDo(U8 *src, I64 flags)
{
  I64 n;
  if (!src)
    src = "";
  n = KernelStrLen(src);
  if (n + 1 > KERNEL_STRUTIL_SOFT_BUF)
    return NULL;
  KernelMemCpy(kernel_strutil_soft_buf, src, n + 1);
  return KernelStrUtilDo(kernel_strutil_soft_buf, flags);
}
// SoftCall prove: path normalize + case/space flags (MakeBlkDev MStrUtil shape).
public I64 KernelStrUtilSoft()
{
  U8 buf[64];
  U8 *p;
  // Path normalize (DskStrA/DskDrv shape).
  KernelMemCpy(buf, "  /A/B  \t", 10);
  KernelStrUtilDo(buf, KERNEL_SUF_REM_LEADING | KERNEL_SUF_REM_TRAILING | KERNEL_SUF_REM_CTRL_CHARS);
  if (!KernelStrEq(buf, "/A/B"))
    return -1;
  // Ctrl chars below CH_SHIFT_SPACE dropped.
  buf[0] = 1;
  buf[1] = 'h';
  buf[2] = 'i';
  buf[3] = 2;
  buf[4] = 0;
  KernelStrUtilDo(buf, KERNEL_SUF_REM_CTRL_CHARS);
  if (!KernelStrEq(buf, "hi"))
    return -2;
  // SINGLE_SPACE collapses runs.
  KernelMemCpy(buf, "a  \tb", 6);
  KernelStrUtilDo(buf, KERNEL_SUF_SINGLE_SPACE);
  if (!KernelStrEq(buf, "a b"))
    return -3;
  // REM_SPACES strips all white.
  KernelMemCpy(buf, "a b\tc", 6);
  KernelStrUtilDo(buf, KERNEL_SUF_REM_SPACES);
  if (!KernelStrEq(buf, "abc"))
    return -4;
  // TO_UPPER / TO_LOWER.
  KernelMemCpy(buf, "AbC", 4);
  KernelStrUtilDo(buf, KERNEL_SUF_TO_UPPER);
  if (!KernelStrEq(buf, "ABC"))
    return -5;
  KernelMemCpy(buf, "AbC", 4);
  KernelStrUtilDo(buf, KERNEL_SUF_TO_LOWER);
  if (!KernelStrEq(buf, "abc"))
    return -6;
  // MStrUtil: copy-out + StrUtil (past thin StrNew identity stub).
  p = KernelMStrUtilDo("  x/y  ", KERNEL_SUF_REM_LEADING | KERNEL_SUF_REM_TRAILING);
  if (!p || !KernelStrEq(p, "x/y"))
    return -7;
  if (p != kernel_strutil_soft_buf)
    return -8;
  return 0x5355;
  // 'SU'
}
// SoftCall Fifo (G9): import-free Kernel_RV KDataTypes Fifo HolyC shape (past thin
// KThinMapFatStubs Fifo*; Serial MakeSerialDev gated empty — InputFilterTask wall;
// SoftCall owns power-of-two ring New/Ins/Rem/Peek/Flush/Cnt/Del — no x86 PUSHFD/CLI).
class CKernelFifoU8
{
  U8 *buf;
  I64 mask, in_ptr, out_ptr;
};

class CKernelFifoI64
{
  I64 *buf;
  I64 mask, in_ptr, out_ptr;
};

CKernelFifoU8 *KernelFifoU8New(I64 size)
{
  CKernelFifoU8 *f;
  if (size < 2 || (size & (size - 1)))
    return NULL;
  f = KernelMAllocSoft(sizeof(CKernelFifoU8));
  if (!f)
    return NULL;
  f->buf = KernelMAllocSoft(size);
  if (!f->buf) {
    KernelFreeSoft(f(U8 *));
    return NULL;
  }
  f->mask = size - 1;
  f->in_ptr = 0;
  f->out_ptr = 0;
  return f;
}

U0 KernelFifoU8Del(CKernelFifoU8 *f)
{
  if (!f)
    return;
  KernelFreeSoft(f->buf);
  KernelFreeSoft(f(U8 *));
}

Bool KernelFifoU8Ins(CKernelFifoU8 *f, U8 b)
{
  I64 new_in;
  if (!f || !f->buf)
    return FALSE;
  new_in = (f->in_ptr + 1) & f->mask;
  if (new_in == f->out_ptr)
    return FALSE;
  f->buf[f->in_ptr] = b;
  f->in_ptr = new_in;
  return TRUE;
}

Bool KernelFifoU8Rem(CKernelFifoU8 *f, U8 *_b)
{
  if (!f || !f->buf || !_b)
    return FALSE;
  if (f->in_ptr == f->out_ptr)
    return FALSE;
  *_b = f->buf[f->out_ptr];
  f->out_ptr = (f->out_ptr + 1) & f->mask;
  return TRUE;
}

Bool KernelFifoU8Peek(CKernelFifoU8 *f, U8 *_b)
{
  if (!f || !f->buf || !_b)
    return FALSE;
  if (f->in_ptr == f->out_ptr)
    return FALSE;
  *_b = f->buf[f->out_ptr];
  return TRUE;
}

U0 KernelFifoU8Flush(CKernelFifoU8 *f)
{
  if (!f)
    return;
  f->out_ptr = f->in_ptr;
}

I64 KernelFifoU8Cnt(CKernelFifoU8 *f)
{
  if (!f)
    return 0;
  if (f->out_ptr > f->in_ptr)
    return f->mask + 1 - (f->out_ptr - f->in_ptr);
  return f->in_ptr - f->out_ptr;
}

CKernelFifoI64 *KernelFifoI64New(I64 size)
{
  CKernelFifoI64 *f;
  if (size < 2 || (size & (size - 1)))
    return NULL;
  f = KernelMAllocSoft(sizeof(CKernelFifoI64));
  if (!f)
    return NULL;
  f->buf = KernelMAllocSoft(size *sizeof(I64));
  if (!f->buf) {
    KernelFreeSoft(f(U8 *));
    return NULL;
  }
  f->mask = size - 1;
  f->in_ptr = 0;
  f->out_ptr = 0;
  return f;
}

U0 KernelFifoI64Del(CKernelFifoI64 *f)
{
  if (!f)
    return;
  KernelFreeSoft(f->buf(U8 *));
  KernelFreeSoft(f(U8 *));
}

Bool KernelFifoI64Ins(CKernelFifoI64 *f, I64 q)
{
  I64 new_in;
  if (!f || !f->buf)
    return FALSE;
  new_in = (f->in_ptr + 1) & f->mask;
  if (new_in == f->out_ptr)
    return FALSE;
  f->buf[f->in_ptr] = q;
  f->in_ptr = new_in;
  return TRUE;
}

Bool KernelFifoI64Rem(CKernelFifoI64 *f, I64 *_q)
{
  if (!f || !f->buf || !_q)
    return FALSE;
  if (f->in_ptr == f->out_ptr)
    return FALSE;
  *_q = f->buf[f->out_ptr];
  f->out_ptr = (f->out_ptr + 1) & f->mask;
  return TRUE;
}

Bool KernelFifoI64Peek(CKernelFifoI64 *f, I64 *_q)
{
  if (!f || !f->buf || !_q)
    return FALSE;
  if (f->in_ptr == f->out_ptr)
    return FALSE;
  *_q = f->buf[f->out_ptr];
  return TRUE;
}

U0 KernelFifoI64Flush(CKernelFifoI64 *f)
{
  if (!f)
    return;
  f->out_ptr = f->in_ptr;
}

I64 KernelFifoI64Cnt(CKernelFifoI64 *f)
{
  if (!f)
    return 0;
  if (f->out_ptr > f->in_ptr)
    return f->mask + 1 - (f->out_ptr - f->in_ptr);
  return f->in_ptr - f->out_ptr;
}
// SoftCall prove: FifoU8 + FifoI64 ring (SerialDev shape; past MapFat stubs).
public I64 KernelFifoSoft()
{
  CKernelFifoU8 *fu;
  CKernelFifoI64 *fi;
  U8 b;
  I64 q, i;
  KernelHeapCtrlInitSoft;
  // Non-power-of-two rejected.
  if (KernelFifoU8New(6))
    return -1;
  fu = KernelFifoU8New(8);
  if (!fu || !fu->buf || fu->mask != 7)
    return -2;
  if (KernelFifoU8Cnt(fu) || KernelFifoU8Rem(fu, &b) || KernelFifoU8Peek(fu, &b))
    return -3;
  if (!KernelFifoU8Ins(fu, 'S') || !KernelFifoU8Ins(fu, 'F'))
    return -4;
  if (KernelFifoU8Cnt(fu) != 2)
    return -5;
  if (!KernelFifoU8Peek(fu, &b) || b != 'S')
    return -6;
  if (!KernelFifoU8Rem(fu, &b) || b != 'S')
    return -7;
  if (!KernelFifoU8Rem(fu, &b) || b != 'F')
    return -8;
  if (KernelFifoU8Cnt(fu) || KernelFifoU8Rem(fu, &b))
    return -9;
  // Fill to capacity (size-1); next Ins fails.
  for (i = 0; i < 7; i++)
    if (!KernelFifoU8Ins(fu, '0' + i))
      return -10;
  if (KernelFifoU8Cnt(fu) != 7 || KernelFifoU8Ins(fu, 'X'))
    return -11;
  if (!KernelFifoU8Peek(fu, &b) || b != '0')
    return -12;
  KernelFifoU8Flush(fu);
  if (KernelFifoU8Cnt(fu) || KernelFifoU8Peek(fu, &b))
    return -13;
  KernelFifoU8Del(fu);
  // FifoI64: Ins/Rem/Peek/full + Flush.
  fi = KernelFifoI64New(4);
  if (!fi || !fi->buf || fi->mask != 3)
    return -14;
  if (!KernelFifoI64Ins(fi, 0x5346) || !KernelFifoI64Ins(fi, 42))
    return -15;
  if (KernelFifoI64Cnt(fi) != 2)
    return -16;
  if (!KernelFifoI64Peek(fi, &q) || q != 0x5346)
    return -17;
  if (!KernelFifoI64Rem(fi, &q) || q != 0x5346)
    return -18;
  if (!KernelFifoI64Rem(fi, &q) || q != 42)
    return -19;
  if (!KernelFifoI64Ins(fi, 1) || !KernelFifoI64Ins(fi, 2) || !KernelFifoI64Ins(fi, 3))
    return -20;
  if (KernelFifoI64Cnt(fi) != 3 || KernelFifoI64Ins(fi, 4))
    return -21;
  KernelFifoI64Flush(fi);
  if (KernelFifoI64Cnt(fi))
    return -22;
  KernelFifoI64Del(fi);
  if (kernel_mem_used_u8s)
    return -23;
  return 0x5346;
  // 'SF'
}
// SoftCall QueVectU8 (G9): import-free Kernel_RV KDataTypes QueVect HolyC shape
// (past thin MapFat QueVect stubs). SoftCall-local CNT=8 (stock 512) — same
// QueInit/QueIns/QueDel + Put pad/grow + Get/min_idx algorithm Lex needs.
#define KERNEL_QUE_VECT_U8_CNT 8
class CKernelQueVectU8
{
  CKernelQueVectU8 *next, *last;
  I64 total_cnt, node_cnt, min_idx;
  U8 body[KERNEL_QUE_VECT_U8_CNT];
};

U0 KernelQueVectQueInit(CKernelQueVectU8 *head)
{
  head->next = head;
  head->last = head;
}

U0 KernelQueVectQueIns(CKernelQueVectU8 *item, CKernelQueVectU8 *pred)
{
  CKernelQueVectU8 *succ;
  succ = pred->next;
  pred->next = item;
  item->last = pred;
  item->next = succ;
  succ->last = item;
}

U0 KernelQueVectQueDel(CKernelQueVectU8 *head)
{
  CKernelQueVectU8 *tmpq, *tmpq1;
  if (!head)
    return;
  tmpq = head->next;
  while (tmpq != head) {
    tmpq1 = tmpq->next;
    KernelFreeSoft(tmpq(U8 *));
    tmpq = tmpq1;
  }
  head->next = head;
  head->last = head;
}

CKernelQueVectU8 *KernelQueVectU8New(I64 min_idx)
{
  CKernelQueVectU8 *res;
  res = KernelMAllocSoft(sizeof(CKernelQueVectU8));
  if (!res)
    return NULL;
  KernelQueVectQueInit(res);
  res->total_cnt = 0;
  res->node_cnt = 0;
  res->min_idx = min_idx;
  return res;
}

U0 KernelQueVectU8Put(CKernelQueVectU8 *v, I64 idx, U8 ch)
{
  CKernelQueVectU8 *tmpv;
  if (!v)
    return;
  idx -= v->min_idx;
  if (idx < 0)
    return;
  if (idx < v->total_cnt) {
    tmpv = v;
    do {
      idx -= tmpv->node_cnt;
      if (idx < 0) {
        tmpv->body[idx + tmpv->node_cnt] = ch;
        return;
      }
      tmpv = tmpv->next;
    } while (tmpv != v);
  } else
    idx -= v->total_cnt;
  while (TRUE) {
    tmpv = v->last;
    if (tmpv->node_cnt >= KERNEL_QUE_VECT_U8_CNT) {
      tmpv = KernelMAllocSoft(sizeof(CKernelQueVectU8));
      if (!tmpv)
        return;
      tmpv->node_cnt = 0;
      KernelQueVectQueIns(tmpv, v->last);
    }
    if (idx--) {
      tmpv->body[tmpv->node_cnt++] = 0;
      v->total_cnt++;
    } else {
      tmpv->body[tmpv->node_cnt++] = ch;
      v->total_cnt++;
      break;
    }
  }
}

U0 KernelQueVectU8Del(CKernelQueVectU8 *v)
{
  if (!v)
    return;
  KernelQueVectQueDel(v);
  KernelFreeSoft(v(U8 *));
}

I64 KernelQueVectU8Get(CKernelQueVectU8 *v, I64 idx)
{
  CKernelQueVectU8 *tmpv;
  if (!v)
    return 0;
  idx -= v->min_idx;
  if (!(0 <= idx < v->total_cnt))
    return 0;
  tmpv = v;
  do {
    idx -= tmpv->node_cnt;
    if (idx < 0)
      return tmpv->body[idx + tmpv->node_cnt];
    tmpv = tmpv->next;
  } while (tmpv != v);
  return 0;
}
// SoftCall prove: QueVectU8 New/Put/Get/Del + multi-node grow + min_idx.
public I64 KernelQueVectSoft()
{
  CKernelQueVectU8 *v, *v2;
  I64 i;
  KernelHeapCtrlInitSoft;
  v = KernelQueVectU8New(0);
  if (!v || v->next != v || v->last != v || v->total_cnt || v->node_cnt)
    return -1;
  if (KernelQueVectU8Get(v, 0))
    return -2;
  KernelQueVectU8Put(v, 0, 'Q');
  KernelQueVectU8Put(v, 1, 'V');
  if (v->total_cnt != 2 || KernelQueVectU8Get(v, 0) != 'Q' || KernelQueVectU8Get(v, 1) != 'V')
    return -3;
  // Fill first node; Put past CNT allocates second node (stock grow shape).
  for (i = 2; i < KERNEL_QUE_VECT_U8_CNT; i++)
    KernelQueVectU8Put(v, i, 'a' + i);
  if (v->total_cnt != KERNEL_QUE_VECT_U8_CNT || v->next != v)
    return -4;
  KernelQueVectU8Put(v, KERNEL_QUE_VECT_U8_CNT, 'X');
  if (v->total_cnt != KERNEL_QUE_VECT_U8_CNT + 1 || v->next == v || v->next->node_cnt != 1)
    return -5;
  if (KernelQueVectU8Get(v, 0) != 'Q' || KernelQueVectU8Get(v, KERNEL_QUE_VECT_U8_CNT) != 'X')
    return -6;
  // Overwrite in first node.
  KernelQueVectU8Put(v, 0, 'q');
  if (KernelQueVectU8Get(v, 0) != 'q')
    return -7;
  KernelQueVectU8Del(v);
  // min_idx: Put/Get offset; below-min ignored; pad gap zeros.
  v2 = KernelQueVectU8New(10);
  if (!v2 || v2->min_idx != 10)
    return -8;
  KernelQueVectU8Put(v2, 9, 'Z');
  if (v2->total_cnt)
    return -9;
  KernelQueVectU8Put(v2, 10, 'A');
  KernelQueVectU8Put(v2, 12, 'C');
  if (v2->total_cnt != 3 || KernelQueVectU8Get(v2, 10) != 'A' || KernelQueVectU8Get(v2, 11) || KernelQueVectU8Get(v2, 12) != 'C')
    return -10;
  if (KernelQueVectU8Get(v2, 9))
    return -11;
  KernelQueVectU8Del(v2);
  if (kernel_mem_used_u8s)
    return -12;
  return 0x5156;
  // 'QV'
}
// SoftCall Rand/Seed (G9): import-free Kernel_RV KMathB LCG HolyC shape (past
// thin MapFat Rand* stubs). SoftCall-local seed + nontimer flag — no Fs /
// GetTSC; Seed(0) clears nontimer and xors a soft tick (timer-ish path).
// Stock widths via mask (no I64.i16[] subint). F64 Rand() deferred.
#define KERNEL_LIN_CONGRUE_A 6364136223846793005
#define KERNEL_LIN_CONGRUE_C 1442695040888963407
#define KERNEL_RANDf_NONTIMER 0
I64 kernel_rand_seed = 0;
I64 kernel_rand_flags = 0;
I64 kernel_rand_soft_tick = 1;
I64 KernelRandStep()
{
  I64 res;
  res = kernel_rand_seed;
  // HolyC precedence: ((A*res) ^ ((res&mask)>>16)) + C
  res = KERNEL_LIN_CONGRUE_A *res ^ (res & 0xFFFFFFFF0000) >> 16 + KERNEL_LIN_CONGRUE_C;
  if (!(kernel_rand_flags & 1 << KERNEL_RANDf_NONTIMER))
    res ^= kernel_rand_soft_tick;
  kernel_rand_seed = res;
  return res;
}

I64 KernelRandSeed(I64 seed)
{
  if (seed) {
    kernel_rand_flags |= 1 << KERNEL_RANDf_NONTIMER;
    return kernel_rand_seed = seed;
  }
  kernel_rand_flags &= ~(1 << KERNEL_RANDf_NONTIMER);
  kernel_rand_soft_tick++;
  return kernel_rand_seed ^= kernel_rand_soft_tick;
}

I16 KernelRandI16()
{
  I64 res;
  res = KernelRandStep;
  return res & 0xFFFF;
}

U16 KernelRandU16()
{
  I64 res;
  res = KernelRandStep;
  return res & 0xFFFF;
}

I32 KernelRandI32()
{
  I64 res;
  res = KernelRandStep;
  return res & 0xFFFFFFFF;
}

U32 KernelRandU32()
{
  I64 res;
  res = KernelRandStep;
  return res & 0xFFFFFFFF;
}

I64 KernelRandI64()
{
  return KernelRandStep;
}

U64 KernelRandU64()
{
  return KernelRandStep;
}
// SoftCall prove: Seed(n) nontimer LCG repeat + width masks + Seed(0) tick.
public I64 KernelRandSoft()
{
  I64 a, a2, b, c, u64a, u64b;
  I16 i16a, i16b;
  U16 u16a;
  I32 i32a, i32b;
  U32 u32a;
  // Seed(1): deterministic nontimer sequence (RandDemo shape).
  KernelRandSeed(1);
  a = KernelRandI64;
  b = KernelRandI64;
  if (!a || a == b)
    return -1;
  KernelRandSeed(1);
  a2 = KernelRandI64;
  if (a2 != a)
    return -2;
  // Seed(2): different stream from Seed(1).
  KernelRandSeed(2);
  c = KernelRandI64;
  if (c == a)
    return -3;
  // Width helpers share step; Seed(1) I16/U16/I32/U32/U64 first draw.
  KernelRandSeed(1);
  i16a = KernelRandI16;
  KernelRandSeed(1);
  i16b = KernelRandI16;
  if (i16a != i16b)
    return -4;
  KernelRandSeed(1);
  u16a = KernelRandU16;
  if (u16a != (i16a & 0xFFFF))
    return -5;
  KernelRandSeed(1);
  i32a = KernelRandI32;
  KernelRandSeed(1);
  i32b = KernelRandI32;
  if (i32a != i32b)
    return -6;
  KernelRandSeed(1);
  u32a = KernelRandU32;
  if (u32a != (i32a & 0xFFFFFFFF))
    return -7;
  KernelRandSeed(1);
  u64a = KernelRandU64;
  KernelRandSeed(1);
  u64b = KernelRandU64;
  if (u64a != u64b || u64a != a)
    return -8;
  // Seed(0): clears nontimer; soft-tick xor changes next draw vs nontimer.
  KernelRandSeed(1);
  a = KernelRandI64;
  KernelRandSeed(0);
  kernel_rand_seed = 1;
  b = KernelRandI64;
  if (b == a)
    return -9;
  // Re-Seed(1) still deterministic after Seed(0).
  KernelRandSeed(1);
  if (KernelRandI64 != a)
    return -10;
  return 0x524E;
  // 'RN'
}
// SoftCall ScanFlags/LstMatch/StrPrintFlags (G9): import-free Kernel_RV StrA/StrB
// HolyC shape (past thin MapFat ScanFlags stubs). SoftCall-lite: exact LstMatch
// only; stack flag-name buf (no MAlloc); unknown name returns FALSE (no throw).
// StrPrintFlags reverse via LstSub + Bsf (no CatPrint/%z).
U0 KernelLBts(U8 *bits, I64 bit)
{
  bits[bit >> 3] |= 1 << (bit & 7);
}

U0 KernelLBtr(U8 *bits, I64 bit)
{
  bits[bit >> 3] &= ~(1 << (bit & 7));
}

Bool KernelBt(U8 *bits, I64 bit)
{
  return !!(bits[bit >> 3] & (1 << (bit & 7)));
}

I64 KernelBsf(I64 flags)
{
  I64 i;
  for (i = 0; i < 64; i++)
    if (flags & (1 << i))
      return i;
  return -1;
}

I64 KernelLstMatch(U8 *needle, U8 *haystack_lst)
{
  I64 sub = 0;
  U8 *ptr;
  if (!haystack_lst || !needle)
    return -1;
  while (*haystack_lst) {
    if (*haystack_lst == '@') {
      sub--;
      haystack_lst++;
    }
    ptr = needle;
    while (*ptr && *ptr == *haystack_lst) {
      ptr++;
      haystack_lst++;
    }
    if (!*ptr && !*haystack_lst)
      return sub;
    while (*haystack_lst)
      haystack_lst++;
    haystack_lst++;
    sub++;
  }
  return -1;
}

U8 *KernelLstSub(U8 *lst, I64 sub)
{
  if (!lst)
    return NULL;
  while (*lst && sub > 0) {
    while (*lst)
      lst++;
    lst++;
    if (*lst == '@')
      lst++;
    else
      sub--;
  }
  if (sub || !*lst)
    return NULL;
  return lst;
}

Bool KernelScanFlagsDo(U8 *_dst_flags, U8 *lst, U8 *src)
{
  I64 i;
  U8 buf[64];
  U8 *ptr;
  if (!src)
    return TRUE;
  while (*src) {
    while (*src && *src != '+' && *src != '-')
      src++;
    if (*src == '+') {
      src++;
      if (*src) {
        ptr = buf;
        while (*src && *src != '+' && *src != '-' && *src != KERNEL_CH_SPACE && *src != KERNEL_CH_SHIFT_SPACE)
          *ptr++ = *src++;
        *ptr = 0;
        i = KernelLstMatch(buf, lst);
        if (i >= 0)
          KernelLBts(_dst_flags, i);
        else
          return FALSE;
      }
    } else if (*src == '-') {
      src++;
      if (*src) {
        ptr = buf;
        while (*src && *src != '+' && *src != '-' && *src != KERNEL_CH_SPACE && *src != KERNEL_CH_SHIFT_SPACE)
          *ptr++ = *src++;
        *ptr = 0;
        i = KernelLstMatch(buf, lst);
        if (i >= 0)
          KernelLBtr(_dst_flags, i);
        else
          return FALSE;
      }
    }
  }
  return TRUE;
}

U8 *KernelStrPrintFlagsDo(U8 *dst, U8 *lst, I64 flags)
{
  I64 i;
  U8 *p = dst, *s;
  if (!dst)
    return NULL;
  *dst = 0;
  while (flags) {
    i = KernelBsf(flags);
    if (i < 0)
      break;
    flags &= ~(1 << i);
    s = KernelLstSub(lst, i);
    if (!s)
      continue;
    *p++ = '+';
    while (*s)
      *p++ = *s++;
  }
  *p = 0;
  return dst;
}
// SoftCall prove: stock ScanFlags example + LstMatch + StrPrintFlags reverse.
public I64 KernelScanFlagsSoft()
{
  I64 flags;
  U8 lst[16];
  U8 out[32];
  // R\0L\0Dump\0Scan\0 (stock StrB ScanFlags example list).
  lst[0] = 'R';
  lst[1] = 0;
  lst[2] = 'L';
  lst[3] = 0;
  lst[4] = 'D';
  lst[5] = 'u';
  lst[6] = 'm';
  lst[7] = 'p';
  lst[8] = 0;
  lst[9] = 'S';
  lst[10] = 'c';
  lst[11] = 'a';
  lst[12] = 'n';
  lst[13] = 0;
  lst[14] = 0;
  if (KernelLstMatch("R", lst) != 0 || KernelLstMatch("Dump", lst) != 2 || KernelLstMatch("Scan", lst) != 3)
    return -1;
  if (KernelLstMatch("Nope", lst) != -1)
    return -2;
  // Stock example: +Dump-R sets bit#2, clears bit#0.
  flags = 1;
  if (!KernelScanFlagsDo(&flags, lst, "+Dump-R") || flags != 4 || !KernelBt(&flags, 2) || KernelBt(&flags, 0))
    return -3;
  flags = 0;
  if (!KernelScanFlagsDo(&flags, lst, "+R+L") || flags != 3)
    return -4;
  if (KernelScanFlagsDo(&flags, lst, "+Nope"))
    return -5;
  // StrPrintFlags reverse (lowest bit first).
  KernelStrPrintFlagsDo(out, lst, 4);
  if (!KernelStrEq(out, "+Dump"))
    return -6;
  KernelStrPrintFlagsDo(out, lst, 5);
  if (!KernelStrEq(out, "+R+Dump"))
    return -7;
  return 0x5343;
  // 'SC'
}
// SoftCall Compress/Expand (G9): import-free Kernel_RV Compress.HC Arc HolyC shape
// (past thin Compress gate). SoftCall-local ARC_BITS=9 (stock 12 ~96 KiB won't
// fit SoftCall BSS); HolyC BFieldOr/Ext (no asm); no throw — bad expand →NULL.
// Stock ArcEntryGet/CompressBuf/ExpandBuf algorithm; CT_7_BIT roundtrip tip.
#define KERNEL_ARC_BITS_MAX 9
#define KERNEL_CT_NONE 1
#define KERNEL_CT_7_BIT 2
#define KERNEL_CT_8_BIT 3
#define KERNEL_ARC_U32_MAX 0xFFFFFFFF
class CKernelArcEntry
{
  CKernelArcEntry *next;
  U16 basecode;
  U8 ch, pad;
  U32 pad2;
};

class CKernelArcCtrl
{
  I64 src_pos, src_size, dst_pos, dst_size;
  U8 *src_buf, *dst_buf;
  I64 min_bits, min_table_entry;
  CKernelArcEntry *cur_entry, *next_entry;
  I64 cur_bits_in_use, next_bits_in_use;
  U8 *stk_ptr, *stk_base;
  I64 free_idx, free_limit, saved_basecode, entry_used, last_ch;
  CKernelArcEntry compress[1 << KERNEL_ARC_BITS_MAX];
  CKernelArcEntry *hash[1 << KERNEL_ARC_BITS_MAX];
};

class CKernelArcCompress
{
  I64 compressed_size, expanded_size;
  U8 compression_type;
};
CKernelArcCtrl kernel_arc_soft;
U8 kernel_arc_stk[1 << KERNEL_ARC_BITS_MAX];
U8 kernel_arc_dst[512];
U32 KernelBFieldExtU32(U8 *bf, I64 bit, I64 size)
{
  I64 i;
  U32 res = 0;
  if (!bf || size <= 0)
    return 0;
  for (i = 0; i < size; i++)
    if (bf[(bit + i) >> 3] & 1 << ((bit + i) & 7))
      res |= 1 << i;
  return res;
}

U0 KernelBFieldOrU32(U8 *bf, I64 bit, U32 pattern)
{
  I64 i;
  if (!bf)
    return;
  for (i = 0; i < 32; i++)
    if (pattern & 1 << i)
      bf[(bit + i) >> 3] |= 1 << ((bit + i) & 7);
}

U0 KernelArcEntryGet(CKernelArcCtrl *c)
{
  I64 i;
  CKernelArcEntry *tmp, *tmp1;
  if (!c->entry_used)
    return;
  i = c->free_idx;
  c->entry_used = FALSE;
  c->cur_entry = c->next_entry;
  c->cur_bits_in_use = c->next_bits_in_use;
  if (c->next_bits_in_use < KERNEL_ARC_BITS_MAX) {
    c->next_entry = &c->compress[i++];
    if (i == c->free_limit) {
      c->next_bits_in_use++;
      c->free_limit = 1 << c->next_bits_in_use;
    }
  } else {
    do {
      if (++i == c->free_limit)
        i = c->min_table_entry;
    } while (c->hash[i]);
    tmp = &c->compress[i];
    c->next_entry = tmp;
    tmp1 = &c->hash[tmp->basecode];
    while (tmp1) {
      if (tmp1->next == tmp) {
        tmp1->next = tmp->next;
        break;
      } else
        tmp1 = tmp1->next;
    }
  }
  c->free_idx = i;
}

I64 KernelArcDetermineCompressionType(U8 *src, I64 size)
{
  while (size--)
    if (*src++ & 0x80)
      return KERNEL_CT_8_BIT;
  return KERNEL_CT_7_BIT;
}

U0 KernelArcCompressBuf(CKernelArcCtrl *c)
{
  CKernelArcEntry *tmp, *tmp1;
  I64 ch, basecode;
  U8 *src_ptr, *src_limit;
  src_ptr = c->src_buf + c->src_pos;
  src_limit = c->src_buf + c->src_size;
  if (c->saved_basecode == KERNEL_ARC_U32_MAX)
    basecode = *src_ptr++;
  else
    basecode = c->saved_basecode;
  while (src_ptr < src_limit && c->dst_pos + c->cur_bits_in_use <= c->dst_size) {
    KernelArcEntryGet(c);
    ac_start:
    if (src_ptr >= src_limit)
      goto ac_done;
    ch = *src_ptr++;
    if (tmp = c->hash[basecode])
      do {
        if (tmp->ch == ch) {
          basecode = tmp - &c->compress[0];
          goto ac_start;
        }
      } while (tmp = tmp->next);
    KernelBFieldOrU32(c->dst_buf, c->dst_pos, basecode);
    c->dst_pos += c->cur_bits_in_use;
    c->entry_used = TRUE;
    tmp = c->cur_entry;
    tmp->basecode = basecode;
    tmp->ch = ch;
    tmp1 = &c->hash[basecode];
    tmp->next = tmp1->next;
    tmp1->next = tmp;
    basecode = ch;
  }
  ac_done:
  c->saved_basecode = basecode;
  c->src_pos = src_ptr - c->src_buf;
}

Bool KernelArcFinishCompression(CKernelArcCtrl *c)
{
  if (c->dst_pos + c->cur_bits_in_use <= c->dst_size) {
    KernelBFieldOrU32(c->dst_buf, c->dst_pos, c->saved_basecode);
    c->dst_pos += c->next_bits_in_use;
    return TRUE;
  }
  return FALSE;
}

U0 KernelArcExpandBuf(CKernelArcCtrl *c)
{
  U8 *dst_ptr, *dst_limit;
  I64 basecode, lastcode, code;
  CKernelArcEntry *tmp, *tmp1;
  dst_ptr = c->dst_buf + c->dst_pos;
  dst_limit = c->dst_buf + c->dst_size;
  while (dst_ptr < dst_limit && c->stk_ptr != c->stk_base)
    *dst_ptr++ = *--c->stk_ptr;
  if (c->stk_ptr == c->stk_base && dst_ptr < dst_limit) {
    if (c->saved_basecode == KERNEL_ARC_U32_MAX) {
      lastcode = KernelBFieldExtU32(c->src_buf, c->src_pos, c->next_bits_in_use);
      c->src_pos += c->next_bits_in_use;
      *dst_ptr++ = lastcode;
      KernelArcEntryGet(c);
      c->last_ch = lastcode;
    } else
      lastcode = c->saved_basecode;
    while (dst_ptr < dst_limit && c->src_pos + c->next_bits_in_use <= c->src_size) {
      basecode = KernelBFieldExtU32(c->src_buf, c->src_pos, c->next_bits_in_use);
      c->src_pos += c->next_bits_in_use;
      if (c->cur_entry == &c->compress[basecode]) {
        *c->stk_ptr++ = c->last_ch;
        code = lastcode;
      } else
        code = basecode;
      while (code >= c->min_table_entry) {
        *c->stk_ptr++ = c->compress[code].ch;
        code = c->compress[code].basecode;
      }
      *c->stk_ptr++ = code;
      c->last_ch = code;
      c->entry_used = TRUE;
      tmp = c->cur_entry;
      tmp->basecode = lastcode;
      tmp->ch = c->last_ch;
      tmp1 = &c->hash[lastcode];
      tmp->next = tmp1->next;
      tmp1->next = tmp;
      KernelArcEntryGet(c);
      while (dst_ptr < dst_limit && c->stk_ptr != c->stk_base)
        *dst_ptr++ = *--c->stk_ptr;
      lastcode = basecode;
    }
    c->saved_basecode = lastcode;
  }
  c->dst_pos = dst_ptr - c->dst_buf;
}

CKernelArcCtrl *KernelArcCtrlNew(Bool expand, I64 compression_type)
{
  CKernelArcCtrl *c = &kernel_arc_soft;
  KernelMemSet(c(U8 *), 0, sizeof(CKernelArcCtrl));
  if (expand) {
    c->stk_base = kernel_arc_stk;
    c->stk_ptr = c->stk_base;
  }
  if (compression_type == KERNEL_CT_7_BIT)
    c->min_bits = 7;
  else
    c->min_bits = 8;
  c->min_table_entry = 1 << c->min_bits;
  c->free_idx = c->min_table_entry;
  c->next_bits_in_use = c->min_bits + 1;
  c->free_limit = 1 << c->next_bits_in_use;
  c->saved_basecode = KERNEL_ARC_U32_MAX;
  c->entry_used = TRUE;
  KernelArcEntryGet(c);
  c->entry_used = TRUE;
  return c;
}

U8 *KernelExpandBufSoft(CKernelArcCompress *arc, U8 *res)
{
  CKernelArcCtrl *c;
  if (!arc || !res)
    return NULL;
  if (!(KERNEL_CT_NONE <= arc->compression_type <= KERNEL_CT_8_BIT))
    return NULL;
  if (arc->compression_type == KERNEL_CT_NONE) {
    KernelMemCpy(res, arc(U8 *) + sizeof(CKernelArcCompress), arc->expanded_size);
    res[arc->expanded_size] = 0;
    return res;
  }
  c = KernelArcCtrlNew(TRUE, arc->compression_type);
  c->src_size = arc->compressed_size << 3;
  c->src_pos = sizeof(CKernelArcCompress) << 3;
  c->src_buf = arc(U8 *);
  c->dst_size = arc->expanded_size;
  c->dst_buf = res;
  c->dst_pos = 0;
  KernelArcExpandBuf(c);
  res[arc->expanded_size] = 0;
  return res;
}

CKernelArcCompress *KernelCompressBufSoft(U8 *src, I64 size, U8 *dst_work, I64 dst_work_size)
{
  CKernelArcCompress *arc;
  I64 size_out, compression_type;
  CKernelArcCtrl *c;
  if (!src || size <= 0 || !dst_work || dst_work_size < sizeof(CKernelArcCompress) + size)
    return NULL;
  compression_type = KernelArcDetermineCompressionType(src, size);
  c = KernelArcCtrlNew(FALSE, compression_type);
  c->src_size = size;
  c->src_buf = src;
  c->dst_size = dst_work_size << 3;
  KernelMemSet(dst_work, 0, dst_work_size);
  c->dst_buf = dst_work;
  c->dst_pos = sizeof(CKernelArcCompress) << 3;
  KernelArcCompressBuf(c);
  if (KernelArcFinishCompression(c) && c->src_pos == c->src_size) {
    size_out = (c->dst_pos + 7) >> 3;
    arc = dst_work(CKernelArcCompress *);
    arc->compression_type = compression_type;
    arc->compressed_size = size_out;
    arc->expanded_size = size;
    return arc;
  }
  // CT_NONE fallback (stock shape when dictionary can't finish).
  arc = dst_work(CKernelArcCompress *);
  KernelMemCpy(arc(U8 *) + sizeof(CKernelArcCompress), src, size);
  arc->compression_type = KERNEL_CT_NONE;
  arc->compressed_size = size + sizeof(CKernelArcCompress);
  arc->expanded_size = size;
  return arc;
}
// SoftCall prove: CompressBuf→ExpandBuf roundtrip (CT_7_BIT preferred) + CT_NONE.
public I64 KernelCompressSoft()
{
  U8 src[64];
  U8 exp[65];
  CKernelArcCompress *arc;
  I64 i;
  for (i = 0; i < 64; i++)
    src[i] = 'A' + (i & 15);
  arc = KernelCompressBufSoft(src, 64, kernel_arc_dst, sizeof(kernel_arc_dst));
  if (!arc || arc->expanded_size != 64)
    return -1;
  // Require real CT_7_BIT (7-bit ASCII repeating) — SoftCall Arc dictionary ownership.
  if (arc->compression_type != KERNEL_CT_7_BIT || arc->compressed_size >= 64 + sizeof(CKernelArcCompress))
    return -2;
  if (!KernelExpandBufSoft(arc, exp))
    return -3;
  for (i = 0; i < 64; i++)
    if (exp[i] != src[i])
      return -4;
  // Force CT_NONE path: high-bit byte → still roundtrips.
  src[0] = 0xC0;
  for (i = 1; i < 16; i++)
    src[i] = i;
  arc = KernelCompressBufSoft(src, 16, kernel_arc_dst, sizeof(kernel_arc_dst));
  if (!arc || arc->expanded_size != 16)
    return -5;
  if (!KernelExpandBufSoft(arc, exp))
    return -6;
  for (i = 0; i < 16; i++)
    if (exp[i] != src[i])
      return -7;
  // Explicit CT_NONE body copy via ExpandBufSoft.
  arc = kernel_arc_dst(CKernelArcCompress *);
  arc->compression_type = KERNEL_CT_NONE;
  arc->expanded_size = 8;
  arc->compressed_size = sizeof(CKernelArcCompress) + 8;
  for (i = 0; i < 8; i++)
    (arc(U8 *) + sizeof(CKernelArcCompress))[i] = 'C' + i;
  if (!KernelExpandBufSoft(arc, exp))
    return -8;
  for (i = 0; i < 8; i++)
    if (exp[i] != 'C' + i)
      return -9;
  return 0x434D;
  // 'CM'
}
// SoftCall KLoad (G9): import-free Kernel_RV KLoad.HC LoadPass1 HolyC shape past
// JumpSoft/ExeSoft export-only. SoftCall-lite: synthetic module + patch table —
// IMM32_EXPORT HashAdd + IET_IMM_I64 LoadOneImport resolve + IET_ABS_ADDR U64
// +=module_base. Import group stops before ABS/MAIN (stock uses END/named next);
// no FileRead/ExtDft/CODE_HEAP/DATA_HEAP/MAIN Call; no throw.
U32 KernelLoadU32Soft(U8 **_src)
{
  U32 v;
  KernelMemCpy(&v, *_src, 4);
  *_src += 4;
  return v;
}

I64 KernelLoadI64Soft(U8 **_src)
{
  I64 v;
  KernelMemCpy(&v, *_src, 8);
  *_src += 8;
  return v;
}

U0 KernelLoadOneImportSoft(U8 **_src, U8 *module_base, CKernelHashTable *table)
{
  U8 *src = *_src, *ptr2, *st_ptr;
  I64 i, etype, val;
  CKernelHash *tmpex = NULL;
  Bool first = TRUE;
  while (etype = *src++) {
    if (etype < KERNEL_IET_REL_I0 || etype > KERNEL_IET_IMM_I64) {
      // SoftCall-lite: leave ABS_ADDR/MAIN/EXPORT for LoadPass1Soft.
      *_src = src - 1;
      return;
    }
    i = KernelLoadU32Soft(&src);
    st_ptr = src;
    while (*src)
      src++;
    src++;
    if (*st_ptr) {
      if (!first) {
        *_src = st_ptr - 5;
        return;
      }
      first = FALSE;
      tmpex = KernelHashFind(st_ptr, table, KERNEL_HTT_EXPORT, 1);
    }
    if (tmpex) {
      ptr2 = module_base + i;
      val = tmpex->val;
      // SoftCall-lite tip: IET_IMM_I64 only (other widths deferred).
      if (etype == KERNEL_IET_IMM_I64)
        *ptr2(I64 *) = val;
    }
  }
  *_src = src - 1;
}

U0 KernelLoadPass1Soft(U8 *src, U8 *module_base, CKernelHashTable *table)
{
  U8 *st_ptr, *ptr2, *ptr3;
  I64 i, j, cnt, etype, abs_val, mb, sz, add32, add64, p3i;
  CKernelHash *tmpex;
  while (etype = *src++) {
    if (etype == KERNEL_IET_END)
      break;
    i = KernelLoadU32Soft(&src);
    st_ptr = src;
    while (*src)
      src++;
    src++;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      tmpex = KernelArenaAlloc(sizeof(CKernelHash));
      if (!tmpex)
        return;
      KernelMemSet(tmpex(U8 *), 0, sizeof(CKernelHash));
      tmpex->str = st_ptr;
      tmpex->type = KERNEL_HTT_EXPORT;
      if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
        tmpex->val = i;
      else
        tmpex->val = i + module_base(I64);
      KernelHashAdd(tmpex, table);
    } else if (etype >= KERNEL_IET_REL_I0 && etype <= KERNEL_IET_IMM_I64) {
      src = st_ptr - 5;
      KernelLoadOneImportSoft(&src, module_base, table);
    } else if (etype == KERNEL_IET_ABS_ADDR) {
      cnt = i;
      for (j = 0; j < cnt; j++) {
        ptr2 = module_base + KernelLoadU32Soft(&src);
        abs_val = 0;
        KernelMemCpy(&abs_val, ptr2, 8);
        mb = 0;
        KernelMemCpy(&mb, &module_base, 8);
        abs_val += mb;
        KernelMemCpy(ptr2, &abs_val, 8);
      }
    } else if (etype == KERNEL_IET_CODE_HEAP || etype == KERNEL_IET_ZEROED_CODE_HEAP) {
      // SoftCall-lite: ArenaAlloc stand-in for MAlloc/CAlloc(..., code_heap); I32 +=heap.
      sz = KernelLoadU32Soft(&src);
      ptr3 = KernelArenaAlloc(sz);
      if (!ptr3)
        return;
      if (etype == KERNEL_IET_ZEROED_CODE_HEAP)
        KernelMemSet(ptr3, 0, sz);
      if (*st_ptr) {
        tmpex = KernelArenaAlloc(sizeof(CKernelHash));
        if (!tmpex)
          return;
        KernelMemSet(tmpex(U8 *), 0, sizeof(CKernelHash));
        tmpex->str = st_ptr;
        tmpex->type = KERNEL_HTT_EXPORT;
        tmpex->val = ptr3(I64);
        KernelHashAdd(tmpex, table);
      }
      cnt = i;
      p3i = 0;
      KernelMemCpy(&p3i, &ptr3, 8);
      for (j = 0; j < cnt; j++) {
        ptr2 = module_base + KernelLoadU32Soft(&src);
        add32 = 0;
        KernelMemCpy(&add32, ptr2, 4);
        add32 += p3i;
        KernelMemCpy(ptr2, &add32, 4);
      }
    } else if (etype == KERNEL_IET_DATA_HEAP || etype == KERNEL_IET_ZEROED_DATA_HEAP) {
      // SoftCall-lite: ArenaAlloc stand-in for MAlloc/CAlloc data_heap; I64 +=heap.
      sz = KernelLoadI64Soft(&src);
      ptr3 = KernelArenaAlloc(sz);
      if (!ptr3)
        return;
      if (etype == KERNEL_IET_ZEROED_DATA_HEAP)
        KernelMemSet(ptr3, 0, sz);
      if (*st_ptr) {
        tmpex = KernelArenaAlloc(sizeof(CKernelHash));
        if (!tmpex)
          return;
        KernelMemSet(tmpex(U8 *), 0, sizeof(CKernelHash));
        tmpex->str = st_ptr;
        tmpex->type = KERNEL_HTT_EXPORT;
        tmpex->val = ptr3(I64);
        KernelHashAdd(tmpex, table);
      }
      cnt = i;
      p3i = 0;
      KernelMemCpy(&p3i, &ptr3, 8);
      for (j = 0; j < cnt; j++) {
        ptr2 = module_base + KernelLoadU32Soft(&src);
        add64 = 0;
        KernelMemCpy(&add64, ptr2, 8);
        add64 += p3i;
        KernelMemCpy(ptr2, &add64, 8);
      }
    }
  }
}

U0 KernelLoadPass2Soft(U8 *src, U8 *module_base)
{
  U8 *st_ptr;
  I64 i, etype;
  I64 (*fp)();
  while (etype = *src++) {
    if (etype == KERNEL_IET_END)
      break;
    i = KernelLoadU32Soft(&src);
    st_ptr = src;
    while (*src)
      src++;
    src++;
    if (etype == KERNEL_IET_MAIN) {
      fp = module_base + i;
      fp();
    } else if (etype == KERNEL_IET_ABS_ADDR)
      src += 4 * i;
    else if (etype == KERNEL_IET_CODE_HEAP || etype == KERNEL_IET_ZEROED_CODE_HEAP)
      src += 4 + 4 * i;
    else if (etype == KERNEL_IET_DATA_HEAP || etype == KERNEL_IET_ZEROED_DATA_HEAP)
      src += 8 + 4 * i;
  }
}
// SoftCall prove: IMM32_EXPORT→IMM_I64 import resolve + ABS_ADDR +=module_base.
public I64 KernelKLoadSoft()
{
  U8 mod[32];
  U8 pt[64];
  U8 *p, *module_base;
  CKernelHashTable *table;
  I64 expect;
  KernelMemSet(mod, 0, sizeof(mod));
  // slot0 @0: import IMM_I64 target; slot1 @8: ABS_ADDR U64 starts 0x100.
  *mod(I64 *) = 0;
  *(mod(U8 *) + 8)(I64 *) = 0x100;
  module_base = mod;
  // Patch table: IMM32_EXPORT KLoadSym=0x12345678; IMM_I64@0; ABS_ADDR cnt=1 off=8; END.
  p = pt;
  *p++ = KERNEL_IET_IMM32_EXPORT;
  *p(U32 *) = 0x12345678;
  p += 4;
  *p++ = 'K';
  *p++ = 'L';
  *p++ = 'o';
  *p++ = 'a';
  *p++ = 'd';
  *p++ = 'S';
  *p++ = 'y';
  *p++ = 'm';
  *p++ = 0;
  *p++ = KERNEL_IET_IMM_I64;
  *p(U32 *) = 0;
  p += 4;
  *p++ = 'K';
  *p++ = 'L';
  *p++ = 'o';
  *p++ = 'a';
  *p++ = 'd';
  *p++ = 'S';
  *p++ = 'y';
  *p++ = 'm';
  *p++ = 0;
  *p++ = KERNEL_IET_ABS_ADDR;
  *p(U32 *) = 1;
  p += 4;
  *p++ = 0;
  // empty name
  *p(U32 *) = 8;
  p += 4;
  *p++ = KERNEL_IET_END;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -1;
  KernelLoadPass1Soft(pt, module_base, table);
  if (*mod(I64 *) != 0x12345678)
    return -2;
  expect = 0x100 + module_base(I64);
  if (*(mod(U8 *) + 8)(I64 *) != expect)
    return -3;
  // Miss: unresolved import must leave slot unchanged on empty table.
  *mod(I64 *) = 0x55;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -4;
  p = pt;
  *p++ = KERNEL_IET_IMM_I64;
  *p(U32 *) = 0;
  p += 4;
  *p++ = 'N';
  *p++ = 'o';
  *p++ = 'S';
  *p++ = 'y';
  *p++ = 'm';
  *p++ = 0;
  *p++ = KERNEL_IET_END;
  KernelLoadPass1Soft(pt, module_base, table);
  if (*mod(I64 *) != 0x55)
    return -5;
  return 0x4C44;
  // 'LD'
}
// SoftCall KLoad MAIN/CODE_HEAP/FileRead (G9): past KLoadSoft import+ABS.
// SoftCall-lite: IET_CODE_HEAP ArenaAlloc + I32+=heap + HashAdd export;
// LoadPass2 IET_MAIN Call(module_base+i); FileWrite/FileRead body feeds
// LoadPass1+2 (stock Load FileRead shape; DataHeapSoft owns ExtDft.Z /
// DATA_HEAP / ZEROED_*).
I64 kernel_load_main_hit;
public I64 KernelLoadMainFn()
{
  kernel_load_main_hit = 0x4D41;
  // 'MA'
  return 0x4D41;
}

public I64 KernelLoadMainSoft()
{
  U8 mod[32];
  U8 pt[96];
  U8 fr_mod[32];
  U8 fr_pt[96];
  U8 *p, *module_base, *heap;
  CKernelHashTable *table;
  CKernelHash *tmpex;
  I64 add0, expect, rn;
  // Reclaim SoftCall arena — prior SoftCalls leave Hash/Load debris (~64 KiB).
  KernelArenaReset;
  // CODE_HEAP: slot0 I32 addend 0x10 → += ArenaAlloc(32); export "CodeHeap".
  KernelMemSet(mod, 0, sizeof(mod));
  *mod(I32 *) = 0x10;
  module_base = mod;
  p = pt;
  *p++ = KERNEL_IET_CODE_HEAP;
  *p(U32 *) = 1;
  // patch count
  p += 4;
  *p++ = 'C';
  *p++ = 'o';
  *p++ = 'd';
  *p++ = 'e';
  *p++ = 'H';
  *p++ = 'e';
  *p++ = 'a';
  *p++ = 'p';
  *p++ = 0;
  *p(U32 *) = 32;
  // MAlloc size
  p += 4;
  *p(U32 *) = 0;
  // patch offset 0
  p += 4;
  *p++ = KERNEL_IET_END;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -1;
  KernelLoadPass1Soft(pt, module_base, table);
  tmpex = KernelHashFind("CodeHeap", table, KERNEL_HTT_EXPORT, 1);
  if (!tmpex || !tmpex->val)
    return -2;
  heap = tmpex->val(U8 *);
  add0 = 0;
  KernelMemCpy(&add0, mod, 4);
  expect = 0x10 + (heap(I64) & 0xFFFFFFFF);
  if (add0 != expect)
    return -3;
  // MAIN: Call(&KernelLoadMainFn) via module_base=fn, i=0.
  kernel_load_main_hit = 0;
  p = pt;
  *p++ = KERNEL_IET_MAIN;
  *p(U32 *) = 0;
  p += 4;
  *p++ = 0;
  // empty name
  *p++ = KERNEL_IET_END;
  KernelLoadPass2Soft(pt, &KernelLoadMainFn);
  if (kernel_load_main_hit != 0x4D41)
    return -4;
  // SoftCall-lite FileRead→LoadPass: reuse SOFTFW.OK (A:/Kernel/ dir full — 8
  // CDir slots; DataHeapSoft owns ExtDft.Z). FileRead body + CODE_HEAP LoadPass1.
  KernelMemSet(fr_mod, 0, sizeof(fr_mod));
  rn = KernelFileRead("A:/Kernel/SOFTFW.OK", fr_mod, 8);
  if (rn != 2 || fr_mod[0] != 'F' || fr_mod[1] != 'W')
    return -5;
  // Plant addend in fr_mod[0..3] for CODE_HEAP I32 patch (FileRead proved above).
  KernelMemSet(fr_mod, 0, sizeof(fr_mod));
  *fr_mod(I32 *) = 0x20;
  p = fr_pt;
  *p++ = KERNEL_IET_CODE_HEAP;
  *p(U32 *) = 1;
  p += 4;
  *p++ = 'F';
  *p++ = 'R';
  *p++ = 'H';
  *p++ = 'e';
  *p++ = 'a';
  *p++ = 'p';
  *p++ = 0;
  *p(U32 *) = 16;
  p += 4;
  *p(U32 *) = 0;
  p += 4;
  *p++ = KERNEL_IET_END;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -6;
  KernelLoadPass1Soft(fr_pt, fr_mod, table);
  tmpex = KernelHashFind("FRHeap", table, KERNEL_HTT_EXPORT, 1);
  if (!tmpex || !tmpex->val)
    return -7;
  heap = tmpex->val(U8 *);
  add0 = 0;
  KernelMemCpy(&add0, fr_mod, 4);
  expect = 0x20 + (heap(I64) & 0xFFFFFFFF);
  if (add0 != expect)
    return -8;
  return 0x4C4D;
  // 'LM'
}
// SoftCall MakeMem (G9): import-free Kernel_RV MemPag/BlkPool HolyC shape past
// thin KThinMemStubs MemPag/BlkPool NULLs. MemSoft already owns HeapCtrl
// hash-bucket; this tip owns page freelist + BlkPoolInit carve. SoftCall-lite:
// FREE_PAG_HASH=0x100 (stock MEM_FREE_PAG_HASH_SIZE); Hash2Soft owns
// free_pag_hash2 SoftCall-lite; no CLI/LBts locks; PhysMemSoft owns
// PageTables/MemPhysical/BlkPoolsInit lite. ARC_BITS=12 Compress SoftCall
// deferred (~96 KiB BSS on SoftCall seed).
#define KERNEL_MEM_PAG_BITS 9
#define KERNEL_MEM_PAG_SIZE (1 << KERNEL_MEM_PAG_BITS)
#define KERNEL_MEM_FREE_PAG_HASH 0x100
#define KERNEL_MEM_SOFT_PAGS 48
#define KERNEL_MBS_USED 0x4D425573
// 'MBUs'
#define KERNEL_MBS_UNUSED 0x4D42556E
// 'MBUn'
class CKernelMemBlk
{
  CKernelMemBlk *next, *last;
  U32 mb_signature, pags;
};

class CKernelBlkPool
{
  I64 locked_flags, alloced_u8s, used_u8s;
  CKernelMemBlk *mem_free_lst;
  CKernelMemBlk *free_pag_hash[KERNEL_MEM_FREE_PAG_HASH];
};

class CKernelMemHcSoft
{
  CKernelBlkPool *bp;
  I64 alloced_u8s;
  CKernelMemBlk mem_blk_head;
};
U8 kernel_makemem_arena[KERNEL_MEM_SOFT_PAGS *KERNEL_MEM_PAG_SIZE];
U0 KernelMemBlkQueInit(CKernelMemBlk *head)
{
  head->next = head->last = head;
}

U0 KernelMemBlkQueIns(CKernelMemBlk *item, CKernelMemBlk *pred)
{
  CKernelMemBlk *succ = pred->next;
  item->next = succ;
  item->last = pred;
  pred->next = item;
  succ->last = item;
}

U0 KernelMemBlkQueRem(CKernelMemBlk *item)
{
  item->next->last = item->last;
  item->last->next = item->next;
}

U0 KernelBlkPoolAddSoft(CKernelBlkPool *bp, CKernelMemBlk *m, I64 pags)
{
  m->next = bp->mem_free_lst;
  m->pags = pags;
  m->mb_signature = KERNEL_MBS_UNUSED;
  bp->alloced_u8s += pags << KERNEL_MEM_PAG_BITS;
  bp->mem_free_lst = m;
}

U0 KernelBlkPoolInitSoft(CKernelBlkPool *bp, I64 pags)
{
  I64 num, i;
  CKernelMemBlk *m;
  U8 *base = bp(U8 *);
  KernelMemSet(bp(U8 *), 0, sizeof(CKernelBlkPool));
  for (i = 0; i < KERNEL_MEM_FREE_PAG_HASH; i++)
    bp->free_pag_hash[i] = NULL;
  bp->mem_free_lst = NULL;
  m = (base + sizeof(CKernelBlkPool) + KERNEL_MEM_PAG_SIZE - 1) & ~(KERNEL_MEM_PAG_SIZE - 1);
  num = (base + (pags << KERNEL_MEM_PAG_BITS) - m(U8 *)) >> KERNEL_MEM_PAG_BITS;
  bp->alloced_u8s = (pags - num) << KERNEL_MEM_PAG_BITS;
  KernelBlkPoolAddSoft(bp, m, num);
}

U8 *KernelMemPagAllocSoft(I64 pags, CKernelBlkPool *bp)
{
  CKernelMemBlk *res, *prev, *cur;
  if (!bp || pags <= 0 || pags >= KERNEL_MEM_FREE_PAG_HASH)
    return NULL;
  // Exact free-pag hash pop (stock MemPagAlloc small path).
  if (res = bp->free_pag_hash[pags]) {
    bp->free_pag_hash[pags] = res->next;
    bp->used_u8s += res->pags << KERNEL_MEM_PAG_BITS;
    return res(U8 *);
  }
  // Walk mem_free_lst: exact or split larger (stock algorithm; no hash2).
  prev = NULL;
  cur = bp->mem_free_lst;
  while (cur) {
    if (cur->pags < pags) {
      prev = cur;
      cur = cur->next;
    } else if (cur->pags == pags) {
      if (prev)
        prev->next = cur->next;
      else
        bp->mem_free_lst = cur->next;
      bp->used_u8s += cur->pags << KERNEL_MEM_PAG_BITS;
      return cur(U8 *);
    } else {
      // Split: shrink cur, carve requested pags from high end.
      cur->pags -= pags;
      res = (cur(U8 *) + (cur->pags << KERNEL_MEM_PAG_BITS))(CKernelMemBlk *);
      res->pags = pags;
      res->mb_signature = KERNEL_MBS_UNUSED;
      bp->used_u8s += res->pags << KERNEL_MEM_PAG_BITS;
      return res(U8 *);
    }
  }
  return NULL;
}

U0 KernelMemPagFreeSoft(CKernelMemBlk *m, CKernelBlkPool *bp)
{
  I64 pags;
  if (!m || !bp)
    return;
  pags = m->pags;
  if (pags <= 0 || pags >= KERNEL_MEM_FREE_PAG_HASH)
    return;
  m->mb_signature = KERNEL_MBS_UNUSED;
  if (bp->used_u8s >= (pags << KERNEL_MEM_PAG_BITS))
    bp->used_u8s -= pags << KERNEL_MEM_PAG_BITS;
  m->next = bp->free_pag_hash[pags];
  bp->free_pag_hash[pags] = m;
}

CKernelMemBlk *KernelMemPagTaskAllocSoft(I64 pags, CKernelMemHcSoft *hc)
{
  CKernelMemBlk *res;
  if (!hc || !hc->bp)
    return NULL;
  res = KernelMemPagAllocSoft(pags, hc->bp)(CKernelMemBlk *);
  if (res) {
    KernelMemBlkQueIns(res, hc->mem_blk_head.last);
    res->mb_signature = KERNEL_MBS_USED;
    hc->alloced_u8s += res->pags << KERNEL_MEM_PAG_BITS;
  }
  return res;
}

U0 KernelMemPagTaskFreeSoft(CKernelMemBlk *m, CKernelMemHcSoft *hc)
{
  if (!m || !hc || !hc->bp)
    return;
  if (m->mb_signature != KERNEL_MBS_USED)
    return;
  KernelMemBlkQueRem(m);
  if (hc->alloced_u8s >= (m->pags << KERNEL_MEM_PAG_BITS))
    hc->alloced_u8s -= m->pags << KERNEL_MEM_PAG_BITS;
  KernelMemPagFreeSoft(m, hc->bp);
}
// SoftCall prove: BlkPoolInit carve + MemPagAlloc/Free hash reuse + TaskAlloc/Free.
public I64 KernelMakeMemSoft()
{
  CKernelBlkPool *bp;
  CKernelMemHcSoft hc;
  CKernelMemBlk *a, *b, *t1, *t2;
  I64 used0;
  bp = kernel_makemem_arena(CKernelBlkPool *);
  KernelBlkPoolInitSoft(bp, KERNEL_MEM_SOFT_PAGS);
  if (!bp->mem_free_lst || bp->mem_free_lst->pags < 8)
    return -1;
  if (!bp->alloced_u8s)
    return -2;
  used0 = bp->used_u8s;
  a = KernelMemPagAllocSoft(1, bp)(CKernelMemBlk *);
  if (!a || a->pags != 1)
    return -3;
  if (bp->used_u8s != used0 + KERNEL_MEM_PAG_SIZE)
    return -4;
  // Free→hash[1]; next 1-pag Alloc must reuse.
  KernelMemPagFreeSoft(a, bp);
  if (!bp->free_pag_hash[1] || bp->free_pag_hash[1] != a)
    return -5;
  b = KernelMemPagAllocSoft(1, bp)(CKernelMemBlk *);
  if (!b || b != a)
    return -6;
  if (bp->free_pag_hash[1])
    return -7;
  // 2-pag split from free list (not hash).
  KernelMemPagFreeSoft(b, bp);
  a = KernelMemPagAllocSoft(2, bp)(CKernelMemBlk *);
  if (!a || a->pags != 2)
    return -8;
  KernelMemPagFreeSoft(a, bp);
  if (!bp->free_pag_hash[2] || bp->free_pag_hash[2] != a)
    return -9;
  // MemPagTaskAlloc/Free: QueIns + USED sig + QueRem + Free hash.
  KernelMemSet(&hc(U8 *), 0, sizeof(CKernelMemHcSoft));
  hc.bp = bp;
  KernelMemBlkQueInit(&hc.mem_blk_head);
  t1 = KernelMemPagTaskAllocSoft(1, &hc);
  if (!t1 || t1->mb_signature != KERNEL_MBS_USED)
    return -10;
  if (hc.mem_blk_head.next != t1 || hc.alloced_u8s != KERNEL_MEM_PAG_SIZE)
    return -11;
  t2 = KernelMemPagTaskAllocSoft(1, &hc);
  if (!t2 || t2 == t1 || hc.alloced_u8s != 2 * KERNEL_MEM_PAG_SIZE)
    return -12;
  KernelMemPagTaskFreeSoft(t1, &hc);
  if (hc.alloced_u8s != KERNEL_MEM_PAG_SIZE || hc.mem_blk_head.next != t2)
    return -13;
  if (!bp->free_pag_hash[1] || bp->free_pag_hash[1] != t1)
    return -14;
  KernelMemPagTaskFreeSoft(t2, &hc);
  if (hc.alloced_u8s || hc.mem_blk_head.next != &hc.mem_blk_head)
    return -15;
  // Mid-slot stock FREE_PAG_HASH=0x100: Free→hash[16]→Alloc reuse.
  a = KernelMemPagAllocSoft(16, bp)(CKernelMemBlk *);
  if (!a || a->pags != 16)
    return -16;
  KernelMemPagFreeSoft(a, bp);
  if (!bp->free_pag_hash[16] || bp->free_pag_hash[16] != a)
    return -17;
  b = KernelMemPagAllocSoft(16, bp)(CKernelMemBlk *);
  if (!b || b != a || bp->free_pag_hash[16])
    return -18;
  KernelMemPagFreeSoft(b, bp);
  // SoftCall-lite MakeMem rejects oversized (Hash2Soft owns free_pag_hash2).
  if (KernelMemPagAllocSoft(KERNEL_MEM_FREE_PAG_HASH, bp))
    return -19;
  // High slot exists (stock table); leave NULL until used.
  if (bp->free_pag_hash[0xFF])
    return -20;
  return 0x4D4D;
  // 'MM'
}
// SoftCall PhysMem (G9): import-free Kernel_RV BlkPoolsInit + MemPageTable +
// MemPhysical HolyC shape past MakeMemSoft (MemPag/BlkPool). SoftCall-lite:
// synthetic E820 (no BIOS); SoftCall-local PTE[16] (no x86 SYS_INIT_PAGE_TABLES
// / Sv39); Mem32Dev queue on static pool (no Mem64Dev/UncachedAlias/InvlPg);
// no CLI/LBts.
#define KERNEL_PHYS_PTE_N 16
#define KERNEL_PHYS_CODE_PAGS 16
#define KERNEL_PHYS_HI_PAGS 4
#define KERNEL_PHYS_DATA_PAGS 8
#define KERNEL_PHYS_MR_POOL 8
#define KERNEL_PHYS_MRT_UNUSED 0
#define KERNEL_PHYS_MRT_RAM 1
#define KERNEL_PHYS_MRT_DEV 2
#define KERNEL_PHYS_MR_FREE 0x46524545
// 'FREE'
#define KERNEL_PHYS_MR_USED 0x55534544
// 'USED'
#define KERNEL_PHYS_PTE_PRESENT 0x1
class CKernelMemE820Soft
{
  I64 base, len, type;
};

class CKernelMemRangeSoft
{
  CKernelMemRangeSoft *next, *last;
  I64 type, flags, base, size, pool_sig;
};

class CKernelPhysDevSoft
{
  CKernelMemRangeSoft mem32_head;
};
U8 kernel_phys_code_arena[KERNEL_PHYS_CODE_PAGS *KERNEL_MEM_PAG_SIZE];
U8 kernel_phys_hi_arena[KERNEL_PHYS_HI_PAGS *KERNEL_MEM_PAG_SIZE];
U8 kernel_phys_data_arena[KERNEL_PHYS_DATA_PAGS *KERNEL_MEM_PAG_SIZE];
I64 kernel_phys_pte[KERNEL_PHYS_PTE_N];
CKernelMemRangeSoft kernel_phys_mr_pool[KERNEL_PHYS_MR_POOL];
CKernelMemE820Soft kernel_phys_e820[4];
CKernelPhysDevSoft kernel_phys_dev;
I64 kernel_phys_full_heaps;
I64 *KernelMemPageTableSoft(U8 *a)
{
  // SoftCall-lite: small PTE table indexed by >>21 (2MiB pages), not x86 PML*.
  I64 idx;
  if (!a)
    return NULL;
  idx = (a(I64) >> 21) & (KERNEL_PHYS_PTE_N - 1);
  return &kernel_phys_pte[idx];
}

U0 KernelPhysMrQueInit(CKernelMemRangeSoft *head)
{
  head->next = head->last = head;
}

U0 KernelPhysMrQueIns(CKernelMemRangeSoft *item, CKernelMemRangeSoft *pred)
{
  CKernelMemRangeSoft *succ = pred->next;
  item->next = succ;
  item->last = pred;
  pred->next = item;
  succ->last = item;
}

U0 KernelPhysMrQueInsRev(CKernelMemRangeSoft *item, CKernelMemRangeSoft *succ)
{
  KernelPhysMrQueIns(item, succ->last);
}

U0 KernelPhysMrQueRem(CKernelMemRangeSoft *item)
{
  item->next->last = item->last;
  item->last->next = item->next;
}

CKernelMemRangeSoft *KernelPhysMrPoolAlloc()
{
  I64 i;
  for (i = 0; i < KERNEL_PHYS_MR_POOL; i++) {
    if (kernel_phys_mr_pool[i].pool_sig != KERNEL_PHYS_MR_USED) {
      KernelMemSet(&kernel_phys_mr_pool[i](U8 *), 0, sizeof(CKernelMemRangeSoft));
      kernel_phys_mr_pool[i].pool_sig = KERNEL_PHYS_MR_USED;
      return &kernel_phys_mr_pool[i];
    }
  }
  return NULL;
}

U0 KernelPhysMrPoolFree(CKernelMemRangeSoft *mr)
{
  if (!mr)
    return;
  mr->pool_sig = KERNEL_PHYS_MR_FREE;
}

Bool KernelMem32DevInsSoft(CKernelMemRangeSoft *tmpmr)
{
  CKernelMemRangeSoft *tmpmr1 = kernel_phys_dev.mem32_head.next, *tmpmr2;
  while (tmpmr1 != &kernel_phys_dev.mem32_head) {
    if (!tmpmr1->type && tmpmr->base >= tmpmr1->base && tmpmr->base + tmpmr->size <= tmpmr1->base + tmpmr1->size) {
      if (tmpmr->base > tmpmr1->base) {
        tmpmr2 = KernelPhysMrPoolAlloc();
        if (!tmpmr2)
          return FALSE;
        tmpmr2->type = KERNEL_PHYS_MRT_UNUSED;
        tmpmr2->flags = 0;
        tmpmr2->base = tmpmr1->base;
        tmpmr2->size = tmpmr->base - tmpmr1->base;
        KernelPhysMrQueInsRev(tmpmr2, tmpmr1);
      }
      KernelPhysMrQueInsRev(tmpmr, tmpmr1);
      tmpmr1->size = tmpmr1->base + tmpmr1->size - (tmpmr->base + tmpmr->size);
      tmpmr1->base = tmpmr->base + tmpmr->size;
      if (!tmpmr1->size) {
        KernelPhysMrQueRem(tmpmr1);
        KernelPhysMrPoolFree(tmpmr1);
      }
      return TRUE;
    }
    tmpmr1 = tmpmr1->next;
  }
  return FALSE;
}

U0 KernelMem32DevInitSoft()
{
  CKernelMemRangeSoft *tmpmr;
  CKernelMemE820Soft *m20 = kernel_phys_e820;
  I64 i;
  for (i = 0; i < KERNEL_PHYS_MR_POOL; i++)
    kernel_phys_mr_pool[i].pool_sig = KERNEL_PHYS_MR_FREE;
  KernelPhysMrQueInit(&kernel_phys_dev.mem32_head);
  tmpmr = KernelPhysMrPoolAlloc();
  if (!tmpmr)
    return;
  tmpmr->type = KERNEL_PHYS_MRT_UNUSED;
  tmpmr->flags = 0;
  // SoftCall-lite MMIO window (stock 0xE0000000..+0x10000000).
  tmpmr->base = 0xE0000000;
  tmpmr->size = 0x10000000;
  KernelPhysMrQueIns(tmpmr, kernel_phys_dev.mem32_head.last);
  if (m20->type) {
    while (m20->type) {
      tmpmr = KernelPhysMrPoolAlloc();
      if (!tmpmr)
        break;
      tmpmr->type = m20->type;
      tmpmr->flags = 0;
      tmpmr->base = m20->base;
      tmpmr->size = m20->len;
      if (!KernelMem32DevInsSoft(tmpmr))
        KernelPhysMrPoolFree(tmpmr);
      m20++;
    }
  }
}

U8 *KernelMem32DevAllocSoft(I64 size, I64 alignment)
{
  U8 *base, *limit;
  CKernelMemRangeSoft *tmpmr, *tmpmr1;
  if (size <= 0 || alignment <= 0)
    return NULL;
  tmpmr1 = kernel_phys_dev.mem32_head.next;
  while (tmpmr1 != &kernel_phys_dev.mem32_head) {
    base = (tmpmr1->base + alignment - 1) & ~(alignment - 1);
    limit = base + size - 1;
    if (!tmpmr1->type && limit < tmpmr1->base + tmpmr1->size) {
      tmpmr = KernelPhysMrPoolAlloc();
      if (!tmpmr)
        return NULL;
      tmpmr->type = KERNEL_PHYS_MRT_DEV;
      tmpmr->flags = 0;
      tmpmr->base = base;
      tmpmr->size = size;
      if (!KernelMem32DevInsSoft(tmpmr)) {
        KernelPhysMrPoolFree(tmpmr);
        return NULL;
      }
      return tmpmr->base(U8 *);
    }
    tmpmr1 = tmpmr1->next;
  }
  return NULL;
}

U0 KernelMem32DevFreeSoft(U8 *base)
{
  CKernelMemRangeSoft *tmpmr;
  if (!base)
    return;
  tmpmr = kernel_phys_dev.mem32_head.next;
  while (tmpmr != &kernel_phys_dev.mem32_head) {
    if (tmpmr->base == base) {
      tmpmr->type = KERNEL_PHYS_MRT_UNUSED;
      break;
    }
    tmpmr = tmpmr->next;
  }
}

I64 KernelBIOSTotalMemSoft()
{
  CKernelMemE820Soft *m20 = kernel_phys_e820;
  I64 r20 = 0;
  if (m20->type) {
    while (m20->type) {
      if (m20->type == KERNEL_PHYS_MRT_RAM)
        r20 += m20->len;
      m20++;
    }
  }
  return r20;
}

I64 KernelScale2MemSoft(I64 min, I64 max, I64 limit, I64 alloced_u8s)
{
  if (alloced_u8s >= limit)
    return max;
  return min + (max - min) * alloced_u8s / limit;
}

U0 KernelBlkPoolsInitSoft(CKernelBlkPool *code_bp, CKernelBlkPool **data_bp_out, I64 total)
{
  I64 code_heap_limit, lo, hi;
  CKernelMemE820Soft *m20 = kernel_phys_e820;
  Bool first = TRUE;
  CKernelBlkPool *data_bp = NULL;
  CKernelMemBlk *hi_m;
  if (!code_bp || !data_bp_out)
    return;
  *data_bp_out = NULL;
  if (total <= 0x80000000)
    code_heap_limit = total;
  else if (total <= 0x100000000)
    code_heap_limit = total / 4;
  else
    code_heap_limit = 0x80000000;
  // SoftCall-lite: hi_arena stands in for SYS_16MEG_AREA_LIMIT physical pages.
  hi_m = kernel_phys_hi_arena(CKernelMemBlk *);
  KernelBlkPoolAddSoft(code_bp, hi_m, KERNEL_PHYS_HI_PAGS);
  if (code_heap_limit < total) {
    while (m20->type) {
      if (m20->type == KERNEL_PHYS_MRT_RAM) {
        lo = m20->base;
        hi = m20->base + m20->len;
        if (lo < code_heap_limit) {
          if (hi > code_heap_limit)
            lo = code_heap_limit;
          else
            hi = lo;
        }
        if (lo >= code_heap_limit && lo < hi) {
          if (first) {
            data_bp = kernel_phys_data_arena(CKernelBlkPool *);
            KernelBlkPoolInitSoft(data_bp, KERNEL_PHYS_DATA_PAGS);
            *data_bp_out = data_bp;
            first = FALSE;
          } else if (data_bp) {
            // SoftCall-lite: second high range already covered by Init carve.
            no_warn hi;
          }
        }
      }
      m20++;
    }
  }
  kernel_phys_full_heaps = 1;
}
// SoftCall prove: BlkPoolsInit + MemPageTable + Mem32Dev + BIOSTotalMem/Scale2Mem.
public I64 KernelPhysMemSoft()
{
  CKernelBlkPool *code_bp, *data_bp;
  I64 *pte, total, scaled, used0;
  U8 *dev_base;
  // Synthetic E820: total >2GiB so code_heap_limit=total/4 and high RAM
  // seeds data_bp (stock BlkPoolsInit shape). SoftCall arenas stand in for
  // physical pages — bases are prove markers only.
  KernelMemSet(kernel_phys_e820(U8 *), 0, sizeof(kernel_phys_e820));
  kernel_phys_e820[0].base = 0;
  kernel_phys_e820[0].len = 0x28000000;
  kernel_phys_e820[0].type = KERNEL_PHYS_MRT_RAM;
  kernel_phys_e820[1].base = 0x28000000;
  kernel_phys_e820[1].len = 0x78000000;
  kernel_phys_e820[1].type = KERNEL_PHYS_MRT_RAM;
  total = KernelBIOSTotalMemSoft();
  if (total != 0xA0000000)
    return -1;
  code_bp = kernel_phys_code_arena(CKernelBlkPool *);
  KernelBlkPoolInitSoft(code_bp, KERNEL_PHYS_CODE_PAGS);
  used0 = code_bp->alloced_u8s;
  if (!code_bp->mem_free_lst)
    return -2;
  data_bp = NULL;
  KernelBlkPoolsInitSoft(code_bp, &data_bp, total);
  if (!kernel_phys_full_heaps)
    return -3;
  if (code_bp->alloced_u8s < used0 + (KERNEL_PHYS_HI_PAGS << KERNEL_MEM_PAG_BITS))
    return -4;
  if (!data_bp || !data_bp->mem_free_lst)
    return -5;
  // MemPageTable SoftCall-lite: present bit roundtrip.
  KernelMemSet(kernel_phys_pte(U8 *), 0, sizeof(kernel_phys_pte));
  pte = KernelMemPageTableSoft(0x00400000(U8 *));
  if (!pte)
    return -6;
  *pte = KERNEL_PHYS_PTE_PRESENT | 0x00400000;
  if (KernelMemPageTableSoft(0x00400000(U8 *)) != pte || !(*pte & KERNEL_PHYS_PTE_PRESENT))
    return -7;
  // Distinct 2MiB index lands in another slot.
  if (KernelMemPageTableSoft(0x00600000(U8 *)) == pte)
    return -8;
  KernelMem32DevInitSoft();
  if (kernel_phys_dev.mem32_head.next == &kernel_phys_dev.mem32_head)
    return -9;
  dev_base = KernelMem32DevAllocSoft(0x1000, 0x1000);
  if (!dev_base || (dev_base(I64) & 0xFFF))
    return -10;
  KernelMem32DevFreeSoft(dev_base);
  scaled = KernelScale2MemSoft(10, 100, 0x40000000, code_bp->alloced_u8s);
  if (scaled < 10 || scaled > 100)
    return -11;
  scaled = KernelScale2MemSoft(10, 100, 8, 0x100);
  if (scaled != 100)
    return -12;
  return 0x504D;
  // 'PM'
}
// SoftCall Hash2 (G9): import-free Kernel_RV MemPag free_pag_hash2 HolyC shape
// past MakeMemSoft (stock FREE_PAG_HASH=0x100). SoftCall-lite: FREE_PAG_HASH2=55
// (stock 64-MEM_PAG_BITS); SoftCall-local HASH2_FREE_PAG_HASH=8 threshold+small
// hash — stock 0x100 hash2 trigger needs ≥130-pag arena (~65 KiB) deferred with
// ARC_BITS=12; EXTRA_HASH2_PAGS=2; SoftCall Bsr; no CLI/LBts.
#define KERNEL_HASH2_SOFT_PAGS 32
#define KERNEL_HASH2_FREE_PAG_HASH 8
#define KERNEL_MEM_FREE_PAG_HASH2 55
#define KERNEL_MEM_EXTRA_HASH2_PAGS 2
class CKernelHash2BlkPool
{
  I64 locked_flags, alloced_u8s, used_u8s;
  CKernelMemBlk *mem_free_lst;
  CKernelMemBlk *free_pag_hash[KERNEL_HASH2_FREE_PAG_HASH];
  CKernelMemBlk *free_pag_hash2[KERNEL_MEM_FREE_PAG_HASH2];
};
U8 kernel_hash2_arena[KERNEL_HASH2_SOFT_PAGS *KERNEL_MEM_PAG_SIZE];
I64 KernelBsrSoft(I64 n)
{
  I64 i;
  if (n <= 0)
    return -1;
  for (i = 63; i >= 0; i--)
    if (n & (1 << i))
      return i;
  return -1;
}

U0 KernelHash2BlkPoolInitSoft(CKernelHash2BlkPool *bp, I64 pags)
{
  I64 num, i;
  CKernelMemBlk *m;
  U8 *base = bp(U8 *);
  KernelMemSet(bp(U8 *), 0, sizeof(CKernelHash2BlkPool));
  for (i = 0; i < KERNEL_HASH2_FREE_PAG_HASH; i++)
    bp->free_pag_hash[i] = NULL;
  for (i = 0; i < KERNEL_MEM_FREE_PAG_HASH2; i++)
    bp->free_pag_hash2[i] = NULL;
  bp->mem_free_lst = NULL;
  m = (base + sizeof(CKernelHash2BlkPool) + KERNEL_MEM_PAG_SIZE - 1) & ~(KERNEL_MEM_PAG_SIZE - 1);
  num = (base + (pags << KERNEL_MEM_PAG_BITS) - m(U8 *)) >> KERNEL_MEM_PAG_BITS;
  bp->alloced_u8s = (pags - num) << KERNEL_MEM_PAG_BITS;
  m->next = bp->mem_free_lst;
  m->pags = num;
  m->mb_signature = KERNEL_MBS_UNUSED;
  bp->alloced_u8s += num << KERNEL_MEM_PAG_BITS;
  bp->mem_free_lst = m;
}

U8 *KernelMemPagAllocHash2Soft(I64 pags, CKernelHash2BlkPool *bp)
{
  CKernelMemBlk *res, *prev, *cur;
  I64 i, req;
  if (!bp || pags <= 0)
    return NULL;
  if (pags < KERNEL_HASH2_FREE_PAG_HASH) {
    if (res = bp->free_pag_hash[pags]) {
      bp->free_pag_hash[pags] = res->next;
      bp->used_u8s += res->pags << KERNEL_MEM_PAG_BITS;
      return res(U8 *);
    }
    i = KernelBsrSoft(KERNEL_HASH2_FREE_PAG_HASH) + 1;
  } else {
    // Stock MemPagAlloc hash2: round to power-of-two + EXTRA.
    pags -= KERNEL_MEM_EXTRA_HASH2_PAGS;
    i = KernelBsrSoft(pags) + 1;
    pags = (1 << i) + KERNEL_MEM_EXTRA_HASH2_PAGS;
    if (i < 0 || i >= KERNEL_MEM_FREE_PAG_HASH2)
      return NULL;
    if (res = bp->free_pag_hash2[i]) {
      bp->free_pag_hash2[i] = res->next;
      bp->used_u8s += res->pags << KERNEL_MEM_PAG_BITS;
      return res(U8 *);
    }
  }
  req = pags;
  prev = NULL;
  cur = bp->mem_free_lst;
  while (cur) {
    if (cur->pags < req) {
      prev = cur;
      cur = cur->next;
    } else if (cur->pags == req) {
      if (prev)
        prev->next = cur->next;
      else
        bp->mem_free_lst = cur->next;
      bp->used_u8s += cur->pags << KERNEL_MEM_PAG_BITS;
      return cur(U8 *);
    } else {
      cur->pags -= req;
      res = (cur(U8 *) + (cur->pags << KERNEL_MEM_PAG_BITS))(CKernelMemBlk *);
      res->pags = req;
      res->mb_signature = KERNEL_MBS_UNUSED;
      bp->used_u8s += res->pags << KERNEL_MEM_PAG_BITS;
      return res(U8 *);
    }
  }
  // SoftCall-lite: search larger hash2 buckets (stock screw-it path).
  while (i + 1 < KERNEL_MEM_FREE_PAG_HASH2) {
    i++;
    if (res = bp->free_pag_hash2[i]) {
      bp->free_pag_hash2[i] = res->next;
      bp->used_u8s += res->pags << KERNEL_MEM_PAG_BITS;
      return res(U8 *);
    }
  }
  return NULL;
}

U0 KernelMemPagFreeHash2Soft(CKernelMemBlk *m, CKernelHash2BlkPool *bp)
{
  I64 i, pags;
  if (!m || !bp)
    return;
  pags = m->pags;
  if (pags <= 0)
    return;
  m->mb_signature = KERNEL_MBS_UNUSED;
  if (bp->used_u8s >= (pags << KERNEL_MEM_PAG_BITS))
    bp->used_u8s -= pags << KERNEL_MEM_PAG_BITS;
  if (pags < KERNEL_HASH2_FREE_PAG_HASH) {
    m->next = bp->free_pag_hash[pags];
    bp->free_pag_hash[pags] = m;
  } else {
    pags -= KERNEL_MEM_EXTRA_HASH2_PAGS;
    i = KernelBsrSoft(pags);
    if (i < 0 || i >= KERNEL_MEM_FREE_PAG_HASH2)
      return;
    m->next = bp->free_pag_hash2[i];
    bp->free_pag_hash2[i] = m;
  }
}
// SoftCall prove: pags>=FREE_PAG_HASH → round → Free hash2 → Alloc reuse.
public I64 KernelHash2Soft()
{
  CKernelHash2BlkPool *bp;
  CKernelMemBlk *a, *b, *c;
  I64 used0, idx;
  bp = kernel_hash2_arena(CKernelHash2BlkPool *);
  KernelHash2BlkPoolInitSoft(bp, KERNEL_HASH2_SOFT_PAGS);
  if (!bp->mem_free_lst || bp->mem_free_lst->pags < 12)
    return -1;
  used0 = bp->used_u8s;
  // Request 8 (≥ HASH2_FREE_PAG_HASH=8) → rounds to 1<<3+2=10; splits free list.
  a = KernelMemPagAllocHash2Soft(KERNEL_HASH2_FREE_PAG_HASH, bp)(CKernelMemBlk *);
  if (!a || a->pags != (1 << 3) + KERNEL_MEM_EXTRA_HASH2_PAGS)
    return -2;
  if (bp->used_u8s != used0 + (a->pags << KERNEL_MEM_PAG_BITS))
    return -3;
  // Free → free_pag_hash2[Bsr(10-2)] = hash2[3].
  idx = KernelBsrSoft(a->pags - KERNEL_MEM_EXTRA_HASH2_PAGS);
  if (idx != 3)
    return -4;
  KernelMemPagFreeHash2Soft(a, bp);
  if (!bp->free_pag_hash2[3] || bp->free_pag_hash2[3] != a)
    return -5;
  // Next ≥hash Alloc must reuse hash2[3] (stock Free→hash2→Alloc).
  b = KernelMemPagAllocHash2Soft(KERNEL_HASH2_FREE_PAG_HASH, bp)(CKernelMemBlk *);
  if (!b || b != a || b->pags != 10)
    return -6;
  if (bp->free_pag_hash2[3])
    return -7;
  KernelMemPagFreeHash2Soft(b, bp);
  // Small free_pag_hash path still works alongside hash2.
  c = KernelMemPagAllocHash2Soft(1, bp)(CKernelMemBlk *);
  if (!c || c->pags != 1)
    return -8;
  KernelMemPagFreeHash2Soft(c, bp);
  if (!bp->free_pag_hash[1] || bp->free_pag_hash[1] != c)
    return -9;
  // Stock FREE_PAG_HASH2=55: high slot exists and stays NULL until used.
  if (bp->free_pag_hash2[54])
    return -10;
  return 0x4832;
  // 'H2'
}
// SoftCall ExtDft (G9): SoftCall-lite stack buf — no MAlloc/CatPrint.
Bool KernelFileExtDotSoft(U8 *src)
{
  I64 ch;
  if (!src)
    return FALSE;
  while (ch = *src++)
    if (ch == '.' && *src != '/' && *src != '.')
      return TRUE;
  return FALSE;
}

U0 KernelExtDftSoft(U8 *dst, U8 *filename, U8 *extension)
{
  I64 i, n, m;
  n = KernelStrLen(filename);
  for (i = 0; i < n; i++)
    dst[i] = filename[i];
  dst[n] = 0;
  if (!KernelFileExtDotSoft(filename)) {
    dst[n++] = '.';
    m = KernelStrLen(extension);
    for (i = 0; i < m; i++)
      dst[n++] = extension[i];
    dst[n] = 0;
  }
}
// SoftCall KLoad DATA_HEAP/ZEROED_*/ExtDft.Z (G9): past LoadMainSoft CODE_HEAP+MAIN.
// SoftCall-lite: IET_DATA_HEAP ArenaAlloc+I64+=heap + HashAdd; ZEROED_* CAlloc
// MemSet; ExtDft default .BIN.Z + identity ExtDft→FileRead (stock Load shape;
// A:/Kernel/ CDir full — no new FileWrite; no throw; LoadAbsSoft owns full Load()).
public I64 KernelDataHeapSoft()
{
  U8 mod[32];
  U8 pt[96];
  U8 ed[48];
  U8 fr_mod[8];
  U8 *p, *module_base, *heap, *poison;
  CKernelHashTable *table;
  CKernelHash *tmpex;
  I64 add0, expect, rn, i;
  KernelArenaReset;
  // ExtDft: no-dot → append .BIN.Z (stock Load ExtDft(filename,"BIN.Z")).
  KernelExtDftSoft(ed, "SOFTFW", "BIN.Z");
  if (KernelStrLen(ed) != 12)
    return -1;
  if (ed[0] != 'S' || ed[6] != '.' || ed[7] != 'B' || ed[11] != 'Z')
    return -2;
  // ExtDft identity + FileRead Load shape (has dot → unchanged path).
  KernelExtDftSoft(ed, "A:/Kernel/SOFTFW.OK", "BIN.Z");
  if (KernelStrLen(ed) != 19)
    return -3;
  rn = KernelFileRead(ed, fr_mod, 8);
  if (rn != 2 || fr_mod[0] != 'F' || fr_mod[1] != 'W')
    return -4;
  // DATA_HEAP: slot0 I64 addend 0x30 → += ArenaAlloc(24); export "DataHeap".
  KernelMemSet(mod, 0, sizeof(mod));
  *mod(I64 *) = 0x30;
  module_base = mod;
  p = pt;
  *p++ = KERNEL_IET_DATA_HEAP;
  *p(U32 *) = 1;
  p += 4;
  *p++ = 'D';
  *p++ = 'a';
  *p++ = 't';
  *p++ = 'a';
  *p++ = 'H';
  *p++ = 'e';
  *p++ = 'a';
  *p++ = 'p';
  *p++ = 0;
  expect = 24;
  KernelMemCpy(p, &expect, 8);
  p += 8;
  *p(U32 *) = 0;
  p += 4;
  *p++ = KERNEL_IET_END;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -5;
  KernelLoadPass1Soft(pt, module_base, table);
  tmpex = KernelHashFind("DataHeap", table, KERNEL_HTT_EXPORT, 1);
  if (!tmpex || !tmpex->val)
    return -6;
  heap = tmpex->val(U8 *);
  add0 = 0;
  KernelMemCpy(&add0, mod, 8);
  expect = 0x30 + heap(I64);
  if (add0 != expect)
    return -7;
  // ZEROED_DATA_HEAP: freelist reuse of poisoned blk → MemSet clears (CAlloc).
  poison = KernelArenaAlloc(32);
  if (!poison)
    return -8;
  KernelMemSet(poison, 0xCD, 32);
  KernelArenaFree(poison, 32);
  KernelMemSet(mod, 0, sizeof(mod));
  *mod(I64 *) = 0x40;
  p = pt;
  *p++ = KERNEL_IET_ZEROED_DATA_HEAP;
  *p(U32 *) = 1;
  p += 4;
  *p++ = 'Z';
  *p++ = 'D';
  *p++ = 'H';
  *p++ = 'e';
  *p++ = 'a';
  *p++ = 'p';
  *p++ = 0;
  expect = 32;
  KernelMemCpy(p, &expect, 8);
  p += 8;
  *p(U32 *) = 0;
  p += 4;
  *p++ = KERNEL_IET_END;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -9;
  KernelLoadPass1Soft(pt, module_base, table);
  tmpex = KernelHashFind("ZDHeap", table, KERNEL_HTT_EXPORT, 1);
  if (!tmpex || !tmpex->val)
    return -10;
  heap = tmpex->val(U8 *);
  for (i = 0; i < 32; i++)
    if (heap[i])
      return -11;
  add0 = 0;
  KernelMemCpy(&add0, mod, 8);
  expect = 0x40 + heap(I64);
  if (add0 != expect)
    return -12;
  // ZEROED_CODE_HEAP: poison reuse + I32 +=heap (LoadPass2 skip size also).
  poison = KernelArenaAlloc(16);
  if (!poison)
    return -13;
  KernelMemSet(poison, 0xAB, 16);
  KernelArenaFree(poison, 16);
  KernelMemSet(mod, 0, sizeof(mod));
  *mod(I32 *) = 0x50;
  p = pt;
  *p++ = KERNEL_IET_ZEROED_CODE_HEAP;
  *p(U32 *) = 1;
  p += 4;
  *p++ = 'Z';
  *p++ = 'C';
  *p++ = 'H';
  *p++ = 'e';
  *p++ = 'a';
  *p++ = 'p';
  *p++ = 0;
  *p(U32 *) = 16;
  p += 4;
  *p(U32 *) = 0;
  p += 4;
  *p++ = KERNEL_IET_END;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -14;
  KernelLoadPass1Soft(pt, module_base, table);
  tmpex = KernelHashFind("ZCHeap", table, KERNEL_HTT_EXPORT, 1);
  if (!tmpex || !tmpex->val)
    return -15;
  heap = tmpex->val(U8 *);
  for (i = 0; i < 16; i++)
    if (heap[i])
      return -16;
  add0 = 0;
  KernelMemCpy(&add0, mod, 4);
  expect = 0x50 + (heap(I64) & 0xFFFFFFFF);
  if (add0 != expect)
    return -17;
  // LoadPass2 skip: DATA_HEAP size+patches then MAIN Call (MAIN already LoadMainSoft).
  kernel_load_main_hit = 0;
  p = pt;
  *p++ = KERNEL_IET_DATA_HEAP;
  *p(U32 *) = 1;
  p += 4;
  *p++ = 0;
  expect = 8;
  KernelMemCpy(p, &expect, 8);
  p += 8;
  *p(U32 *) = 0;
  p += 4;
  *p++ = KERNEL_IET_MAIN;
  *p(U32 *) = 0;
  p += 4;
  *p++ = 0;
  *p++ = KERNEL_IET_END;
  KernelLoadPass2Soft(pt, &KernelLoadMainFn);
  if (kernel_load_main_hit != 0x4D41)
    return -18;
  return 0x4448;
  // 'DH'
}
// SoftCall full Load() FileNameAbs+module_align (G9): past DataHeapSoft ExtDft.Z.
// SoftCall-lite: FileNameAbs drive-abs + cur_dir join; FileExtRem; HTT_MODULE
// HashGenericAdd; MAllocAligned(module_align_bits); LoadPass copy+Pass1;
// ExtDft+FileNameAbs+FileRead LoadProbe→aligned LoadPass+MODULE+export Find.
U0 KernelStrCpySoft(U8 *dst, U8 *src)
{
  if (!dst)
    return;
  if (!src) {
    *dst = 0;
    return;
  }
  while (*src)
    *dst++ = *src++;
  *dst = 0;
}

U0 KernelFileExtRemSoft(U8 *src)
{
  U8 *p = src;
  I64 ch;
  if (!src)
    return;
  while (ch = *p++)
    if (ch == '.' && *p != '/' && *p != '.') {
      p[-1] = 0;
      return;
    }
}

U0 KernelFileNameAbsSoft(U8 *dst, U8 *filename, U8 *cur_dir)
{
  I64 i, n, m;
  if (!dst || !filename)
    return;
  // SoftCall-lite: drive-abs identity (stock FileNameAbs after DirNameAbs).
  if (filename[0] && filename[1] == ':') {
    KernelStrCpySoft(dst, filename);
    return;
  }
  // Relative: join cur_dir + '/' + filename (no DirNameAbs parents).
  n = 0;
  if (cur_dir) {
    n = KernelStrLen(cur_dir);
    for (i = 0; i < n; i++)
      dst[i] = cur_dir[i];
  }
  if (n > 0 && dst[n - 1] != '/')
    dst[n++] = '/';
  m = KernelStrLen(filename);
  for (i = 0; i < m; i++)
    dst[n++] = filename[i];
  dst[n] = 0;
}

U8 *KernelMAllocAlignedSoft(I64 size, I64 alignment, I64 misalignment)
{
  // SoftCall-lite stock MAllocAligned shape (powers of two). No back-ptr at
  // res[-1] — ArenaAlloc has no CMemUsed header; writing before ptr corrupts
  // the SoftCall freelist (stock MAlloc owns that slot).
  I64 mask, base;
  U8 *ptr, *res;
  if (size <= 0 || alignment <= 0)
    return NULL;
  mask = alignment - 1;
  if (misalignment < 0)
    misalignment = 0;
  ptr = KernelArenaAlloc(size + mask + 8 + misalignment);
  if (!ptr)
    return NULL;
  base = (ptr(I64) + 8 + mask) & ~mask;
  res = (base + misalignment)(U8 *);
  return res;
}
I64 kernel_load_abs_mod_added;
U8 *KernelLoadPassAlignSoft(U8 *bfh, I64 size, U8 *absname, CKernelHashTable *table)
{
  // SoftCall-lite LoadPass: module_align + MAllocAligned + MODULE hash + Pass1.
  U8 *bfh_addr, *module_base, *pt, *mod_str, fbuf[64];
  I64 module_align, misalignment, bits, sig, org, ptoff, i, n;
  CKernelHash *tmph;
  kernel_load_abs_mod_added = 0;
  if (!bfh || size < KERNEL_CBIN_HDR || !table)
    return NULL;
  bits = bfh[2];
  module_align = 1 << bits;
  sig = 0;
  KernelMemCpy(&sig, bfh + 4, 4);
  if (!module_align || sig != KERNEL_BIN_SIGNATURE_VAL)
    return NULL;
  KernelMemCpy(&org, bfh + 8, 8);
  misalignment = module_align - KERNEL_CBIN_HDR;
  if (misalignment < 0)
    misalignment &= module_align - 1;
  // SoftCall-lite: always separate heaps → bump align min 16 (stock code_heap path).
  if (module_align < 16)
    module_align = 16;
  if (org != KERNEL_INVALID_PTR && org) {
    bfh_addr = org(U8 *);
  } else {
    bfh_addr = KernelMAllocAlignedSoft(size, module_align, misalignment);
    if (!bfh_addr)
      return NULL;
    if ((bfh_addr(I64) & (module_align - 1)) != (misalignment & (module_align - 1)))
      return NULL;
    KernelMemCpy(bfh_addr, bfh, size);
  }
  if (absname) {
    n = KernelStrLen(absname);
    if (n >= 64)
      n = 63;
    for (i = 0; i < n; i++)
      fbuf[i] = absname[i];
    fbuf[n] = 0;
    KernelFileExtRemSoft(fbuf);
    // Stock LoadPass: fbuf+2 keeps leading '/' after drive (A:/x → /x).
    if (fbuf[0] && fbuf[1] == ':' && KernelStrLen(fbuf) > 2 && fbuf[2] == '/') {
      n = KernelStrLen(fbuf + 2);
      mod_str = KernelArenaAlloc(n + 1);
      tmph = KernelArenaAlloc(sizeof(CKernelHash));
      if (mod_str && tmph) {
        KernelStrCpySoft(mod_str, fbuf + 2);
        KernelMemSet(tmph(U8 *), 0, sizeof(CKernelHash));
        tmph->str = mod_str;
        tmph->type = KERNEL_HTT_MODULE;
        tmph->val = bfh_addr(I64);
        KernelHashAdd(tmph, table);
        kernel_load_abs_mod_added = 1;
      }
    }
  }
  KernelMemCpy(&ptoff, bfh_addr + 16, 8);
  if (ptoff > 0) {
    module_base = bfh_addr + KERNEL_CBIN_HDR;
    pt = bfh_addr + ptoff;
    KernelLoadPass1Soft(pt, module_base, table);
  }
  return bfh_addr;
}
// SoftCall prove: FileNameAbs + module_align MAllocAligned + MODULE hash +
// ExtDft+FileNameAbs+FileRead LoadProbe → aligned LoadPass + export Find.
public I64 KernelLoadAbsSoft()
{
  U8 abs[64];
  U8 ed[48];
  U8 syn[96];
  U8 *bfh_addr, *bfh;
  CKernelHashTable *table;
  CKernelHash *hit;
  I64 expect, org, ptoff, sz;
  KernelArenaReset;
  // FileNameAbs drive-abs identity.
  KernelFileNameAbsSoft(abs, "A:/Kernel/SOFTFW.OK", "A:/");
  if (KernelStrLen(abs) != 19)
    return -1;
  // A:/Kernel/SOFTFW.OK — '/'@9, 'S'@10, 'K'@18.
  if (abs[0] != 'A' || abs[9] != '/' || abs[10] != 'S' || abs[18] != 'K')
    return -2;
  // FileNameAbs relative join (SoftCall-lite cur_dir).
  KernelFileNameAbsSoft(abs, "SOFTFW.OK", "A:/Kernel");
  if (KernelStrLen(abs) != 19)
    return -3;
  if (abs[9] != '/' || abs[10] != 'S')
    return -4;
  // FileExtRem + MODULE HashGenericAdd shape.
  KernelStrCpySoft(abs, "A:/Kernel/LoadProbe.BIN");
  KernelFileExtRemSoft(abs);
  if (KernelStrLen(abs) != 19)
    return -5;
  if (abs[18] != 'e')
    return -6;
  // Synthetic CBinFile: align_bits=6 → align 64, misalignment=32.
  KernelMemSet(syn, 0, sizeof(syn));
  syn[2] = 6;
  expect = KERNEL_BIN_SIGNATURE_VAL;
  KernelMemCpy(syn + 4, &expect, 4);
  org = KERNEL_INVALID_PTR;
  KernelMemCpy(syn + 8, &org, 8);
  ptoff = KERNEL_CBIN_HDR;
  KernelMemCpy(syn + 16, &ptoff, 8);
  sz = sizeof(syn);
  KernelMemCpy(syn + 24, &sz, 8);
  syn[KERNEL_CBIN_HDR] = KERNEL_IET_END;
  // Prove HTT_MODULE HashAdd/Find before LoadPass (isolate Find mask).
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -7;
  hit = KernelArenaAlloc(sizeof(CKernelHash));
  if (!hit)
    return -21;
  KernelMemSet(hit(U8 *), 0, sizeof(CKernelHash));
  hit->str = "/Kernel/SynAlign";
  hit->type = KERNEL_HTT_MODULE;
  hit->val = 0x55;
  KernelHashAdd(hit, table);
  hit = KernelHashFind("/Kernel/SynAlign", table, KERNEL_HTT_MODULE, 1);
  if (!hit || hit->val != 0x55)
    return -22;
  // Build SynAlign.BIN without '.' in any path literal (host AOT can drop '.' —
  // measured "A:/Kernel/SynAlign.BIN" as 21 not 22). Compose pieces + content-check
  // (avoid brittle single-literal StrLen magic that returned SoftCall code=-30).
  KernelStrCpySoft(abs, "A:/Kernel/");
  sz = KernelStrLen(abs);
  if (sz != 10 || abs[0] != 'A' || abs[9] != '/')
    return -30;
  KernelStrCpySoft(abs + sz, "SynAlign");
  sz = KernelStrLen(abs);
  // A:/Kernel/SynAlign — 'S'@10, ends with 'n'.
  if (sz != 18 || abs[10] != 'S' || abs[17] != 'n')
    return -30;
  abs[sz] = '.';
  abs[sz + 1] = 'B';
  abs[sz + 2] = 'I';
  abs[sz + 3] = 'N';
  abs[sz + 4] = 0;
  if (KernelStrLen(abs) != 22 || abs[18] != '.')
    return -30;
  // Prove FileExtRem MODULE key before LoadPass (stock fbuf+2 keeps leading '/').
  KernelStrCpySoft(ed, abs);
  KernelFileExtRemSoft(ed);
  if (KernelStrLen(ed) != 18 || ed[18])
    return -31;
  if (KernelStrCmp(ed + 2, "/Kernel/SynAlign"))
    return -32;
  bfh_addr = KernelLoadPassAlignSoft(syn, sizeof(syn), abs, table);
  if (!bfh_addr)
    return -8;
  if ((bfh_addr(I64) & 63) != 32)
    return -9;
  if (!kernel_load_abs_mod_added)
    return -24;
  // HashAdd inserts at head: instance1=LoadPass (bfh_addr), instance2=hand (0x55).
  hit = KernelHashFind("/Kernel/SynAlign", table, KERNEL_HTT_MODULE, 1);
  if (!hit || hit->val != bfh_addr(I64))
    return -10;
  if (!(hit->type & KERNEL_HTT_MODULE))
    return -20;
  hit = KernelHashFind("/Kernel/SynAlign", table, KERNEL_HTT_MODULE, 2);
  if (!hit || hit->val != 0x55)
    return -23;
  // Stock Load shape: ExtDft + FileNameAbs + FileRead → LoadPass align+MODULE.
  KernelExtDftSoft(ed, "A:/Kernel/LoadProbe.BIN", "BIN.Z");
  if (KernelStrLen(ed) != 23)
    return -11;
  KernelFileNameAbsSoft(abs, ed, "A:/Kernel");
  if (KernelStrCmp(abs, "A:/Kernel/LoadProbe.BIN"))
    return -12;
  bfh = KernelLoad(abs)(U8 *);
  if (!bfh || *(bfh + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -13;
  KernelMemCpy(&sz, bfh + 24, 8);
  if (sz < KERNEL_CBIN_HDR || sz > 4096)
    return -14;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -15;
  bfh_addr = KernelLoadPassAlignSoft(bfh, sz, abs, table);
  if (!bfh_addr)
    return -16;
  hit = KernelHashFind("/Kernel/LoadProbe", table, KERNEL_HTT_MODULE, 1);
  if (!hit || hit->val != bfh_addr(I64))
    return -17;
  hit = KernelHashFind("LoadProbe", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -18;
  return 0x4C41;
  // 'LA'
}
// SoftCall DirNameAbs parents + FUF_Z_OR_NOT_Z + MAlloc ExtDft (G9): past LoadAbsSoft.
// SoftCall-lite: stack DirNameAbs `..`/`.` (no ~ / MAlloc); FileNameAbs via DirNameAbs;
// ToggleZorNotZ + FileFind Z-alt; ArenaAlloc ExtDft (stock MAlloc return shape).
U0 KernelStrFirstRemSoft(U8 *src, U8 marker, U8 *dst)
{
  I64 ch;
  U8 *ptr = src;
  if (!src)
    return;
  if (dst) {
    while ((ch = *ptr++) && ch != marker)
      *dst++ = ch;
    *dst = 0;
  } else
    while ((ch = *ptr++) && ch != marker)
      ;
  if (ch)
    KernelStrCpySoft(src, ptr);
  else
    *src = 0;
}

U0 KernelStrLastRemSoft(U8 *src, U8 marker, U8 *dst)
{
  U8 *p = src, *last = NULL;
  I64 ch;
  if (!src)
    return;
  while (ch = *p++)
    if (ch == marker)
      last = p - 1;
  if (last) {
    if (dst)
      KernelStrCpySoft(dst, last + 1);
    *last = 0;
  } else {
    if (dst)
      KernelStrCpySoft(dst, src);
    *src = 0;
  }
}

U0 KernelDirNameAbsSoft(U8 *dst, U8 *dirname, U8 *cur_dir, U8 drv_let)
{
  // SoftCall-lite stock DirNameAbs: drive letter + `..`/`.` path (no ~ / MAlloc).
  U8 buf[64], buf2[64], buf3[64], buf4[64];
  U8 *d = dirname;
  I64 i, n, m;
  U8 drv0 = drv_let;
  if (!dst)
    return;
  if (d && d[0] && d[1] == ':') {
    drv0 = d[0];
    d += 2;
    KernelStrCpySoft(buf, "/");
  } else if (cur_dir && cur_dir[0] && cur_dir[1] == ':') {
    drv0 = cur_dir[0];
    KernelStrCpySoft(buf, cur_dir + 2);
    if (!buf[0])
      KernelStrCpySoft(buf, "/");
  } else if (cur_dir && *cur_dir) {
    KernelStrCpySoft(buf, cur_dir);
  } else
    KernelStrCpySoft(buf, "/");
  if (d && *d == '/') {
    KernelStrCpySoft(buf, "/");
    d++;
  }
  if (d)
    KernelStrCpySoft(buf2, d);
  else
    buf2[0] = 0;
  KernelStrCpySoft(buf3, buf);
  while (*buf2) {
    KernelStrFirstRemSoft(buf2, '/', buf4);
    if (!*buf4)
      KernelStrCpySoft(buf3, "/");
    else if (!KernelStrCmp(buf4, "..")) {
      KernelStrLastRemSoft(buf3, '/', NULL);
      if (!*buf3)
        KernelStrCpySoft(buf3, "/");
    } else if (!KernelStrCmp(buf4, "."))
      ;
    else if (*buf4) {
      if (KernelStrCmp(buf3, "/")) {
        n = KernelStrLen(buf3);
        buf3[n++] = '/';
        buf3[n] = 0;
      }
      n = KernelStrLen(buf3);
      m = KernelStrLen(buf4);
      for (i = 0; i < m; i++)
        buf3[n++] = buf4[i];
      buf3[n] = 0;
    }
  }
  dst[0] = drv0;
  dst[1] = ':';
  KernelStrCpySoft(dst + 2, buf3);
}

U0 KernelFileNameAbsViaDirSoft(U8 *dst, U8 *filename, U8 *cur_dir, U8 drv_let)
{
  // SoftCall-lite FileNameAbs: DirNameAbs(dir) + '/' + file (parents via DirNameAbs).
  U8 work[64], file[40], dir_abs[64];
  I64 n, m, i;
  if (!dst || !filename)
    return;
  KernelStrCpySoft(work, filename);
  if (work[0] && work[1] == ':') {
    KernelStrLastRemSoft(work + 2, '/', file);
    if (!work[2])
      KernelStrCpySoft(work + 2, "/");
    KernelDirNameAbsSoft(dir_abs, work, cur_dir, drv_let);
  } else {
    KernelStrLastRemSoft(work, '/', file);
    if (!work[0])
      KernelDirNameAbsSoft(dir_abs, "", cur_dir, drv_let);
    else
      KernelDirNameAbsSoft(dir_abs, work, cur_dir, drv_let);
  }
  KernelStrCpySoft(dst, dir_abs);
  n = KernelStrLen(dst);
  if (n > 0 && dst[n - 1] != '/')
    dst[n++] = '/';
  m = KernelStrLen(file);
  for (i = 0; i < m; i++)
    dst[n++] = file[i];
  dst[n] = 0;
}

Bool KernelIsDotZSoft(U8 *filename)
{
  I64 i, dots = 0;
  U8 *p = filename;
  if (!filename)
    return FALSE;
  i = KernelStrLen(filename);
  if (i < 2)
    return FALSE;
  while (*p)
    if (*p++ == '.')
      dots++;
  return dots > 1 && filename[i - 1] == 'Z' && filename[i - 2] == '.';
}

U0 KernelToggleZSoft(U8 *dst, U8 *name)
{
  I64 n;
  if (!dst || !name)
    return;
  if (KernelIsDotZSoft(name)) {
    KernelStrCpySoft(dst, name);
    n = KernelStrLen(dst);
    dst[n - 2] = 0;
  } else {
    KernelStrCpySoft(dst, name);
    n = KernelStrLen(dst);
    dst[n++] = '.';
    dst[n++] = 'Z';
    dst[n] = 0;
  }
}

Bool KernelFileFindZOrNotSoft(U8 *path)
{
  // SoftCall-lite FUF_Z_OR_NOT_Z: try path then ToggleZ alt (no throw / DirContext).
  U8 alt[64];
  if (KernelFileFind(path))
    return TRUE;
  KernelToggleZSoft(alt, path);
  return KernelFileFind(alt);
}

U8 *KernelExtDftMallocSoft(U8 *filename, U8 *extension)
{
  // SoftCall-lite stock ExtDft MAlloc shape — ArenaAlloc return (no CatPrint).
  I64 n, m, need;
  U8 *res;
  if (!filename || !extension)
    return NULL;
  n = KernelStrLen(filename);
  m = KernelStrLen(extension);
  need = n + 1 + m + 1;
  res = KernelArenaAlloc(need);
  if (!res)
    return NULL;
  KernelExtDftSoft(res, filename, extension);
  return res;
}

public I64 KernelDirAbsSoft()
{
  U8 abs[64], alt[64], ed[64], *heap;
  I64 n;
  KernelArenaReset;
  // DirNameAbs parents: A:/Kernel/../Adam → A:/Adam.
  KernelDirNameAbsSoft(abs, "A:/Kernel/../Adam", "A:/", 'A');
  if (KernelStrCmp(abs, "A:/Adam"))
    return -1;
  // Relative parents against cur_dir A:/Kernel.
  KernelDirNameAbsSoft(abs, "foo/../bar", "A:/Kernel", 'A');
  if (KernelStrCmp(abs, "A:/Kernel/bar"))
    return -2;
  // "." no-op segment.
  KernelDirNameAbsSoft(abs, "A:/Kernel/./Sub", "A:/", 'A');
  if (KernelStrCmp(abs, "A:/Kernel/Sub"))
    return -3;
  // FileNameAbs via DirNameAbs parents.
  KernelFileNameAbsViaDirSoft(abs, "A:/Kernel/../Adam/X.BIN", "A:/", 'A');
  if (KernelStrCmp(abs, "A:/Adam/X.BIN"))
    return -4;
  // Relative FileNameAbs (LoadAbsSoft join shape via DirNameAbs).
  KernelFileNameAbsViaDirSoft(abs, "SOFTFW.OK", "A:/Kernel", 'A');
  if (KernelStrCmp(abs, "A:/Kernel/SOFTFW.OK"))
    return -5;
  // ToggleZorNotZ: append .Z / strip .Z.
  KernelToggleZSoft(alt, "A:/Kernel/LoadProbe.BIN");
  if (KernelStrCmp(alt, "A:/Kernel/LoadProbe.BIN.Z"))
    return -6;
  KernelToggleZSoft(ed, alt);
  if (KernelStrCmp(ed, "A:/Kernel/LoadProbe.BIN"))
    return -7;
  // FUF_Z_OR_NOT_Z FileFind: exact + missing .Z alt → existing .BIN.
  if (!KernelFileFindZOrNotSoft("A:/Kernel/LoadProbe.BIN"))
    return -8;
  if (!KernelFileFindZOrNotSoft("A:/Kernel/LoadProbe.BIN.Z"))
    return -9;
  // Stock MAlloc ExtDft shape (ArenaAlloc return).
  heap = KernelExtDftMallocSoft("SOFTFW", "BIN.Z");
  if (!heap || KernelStrCmp(heap, "SOFTFW.BIN.Z"))
    return -10;
  n = KernelStrLen(heap) + 1;
  KernelArenaFree(heap, n);
  heap = KernelExtDftMallocSoft("A:/Kernel/SOFTFW.OK", "BIN.Z");
  if (!heap || KernelStrCmp(heap, "A:/Kernel/SOFTFW.OK"))
    return -11;
  return 0x444E;
  // 'DN'
}
// SoftCall full StartOS Load chain without Mac phase3.elf Cmp (G9): DirAbs-resolve
// StartOS path → AdamSoft → StartSoft. Past DirAbsSoft; product BINs only (no Cmp).
public I64 KernelStartOSSoft()
{
  U8 abs[64];
  I64 r;
  // Stock FileNameAbs parents shape (DirAbsSoft) → A:/Adam/StartOS.BIN.
  KernelFileNameAbsViaDirSoft(abs, "A:/Kernel/../Adam/StartOS.BIN", "A:/", 'A');
  if (KernelStrCmp(abs, "A:/Adam/StartOS.BIN"))
    return -1;
  if (!KernelFileFind(abs))
    return -2;
  // Phase3 StartOS Load order: StartOS.BIN then Seed→Svc→Kern (no Cmp / DocTerm).
  r = KernelAdamSoft();
  if (r != 0x4B41)
    return -3;
  r = KernelStartSoft();
  if (r != 0x4B55)
    return -4;
  return 0x534F;
  // 'SO'
}
// SoftCall-lite CmpCtrl (G9): buf_ptr + put-back U16 — stock Lex CmpCtrlNew shape
// without Fs/Que/hash_table/char_bmp (SoftCall-lite ceiling).
#define KERNEL_CCF_USE_LAST_U16 1
class CKernelCmpCtrlSoft
{
  U8 *cur_buf_ptr;
  I64 last_U16, flags, cur_i64;
};

I64 KernelLexGetCharSoft(CKernelCmpCtrlSoft *cc)
{
  U8 *src;
  I64 ch;
  if (!cc)
    return 0;
  if (cc->flags & KERNEL_CCF_USE_LAST_U16) {
    cc->flags &= ~KERNEL_CCF_USE_LAST_U16;
    return cc->last_U16;
  }
  src = cc->cur_buf_ptr;
  if (!src || !*src) {
    cc->last_U16 = 0;
    return 0;
  }
  ch = *src;
  cc->cur_buf_ptr = src + 1;
  cc->last_U16 = ch;
  return ch;
}

U0 KernelLexPutBackSoft(CKernelCmpCtrlSoft *cc)
{
  if (cc)
    cc->flags |= KERNEL_CCF_USE_LAST_U16;
}
// Skips whitespace and stock '//' to-EOL comments. Guest source read off RedSea
// carries a real doc header; '/' is not an operator anywhere in the lite Prs, so
// a lone '/' still falls through to the caller's error path.
I64 KernelLexSkipSpaceSoft(CKernelCmpCtrlSoft *cc)
{
  I64 ch;
  while (TRUE) {
    ch = KernelLexGetCharSoft(cc);
    if (!ch)
      return 0;
    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r')
      continue;
    if (ch == '/' && cc && cc->cur_buf_ptr && *cc->cur_buf_ptr == '/') {
      while (TRUE) {
        ch = KernelLexGetCharSoft(cc);
        if (!ch)
          return 0;
        if (ch == '\n')
          break;
      }
      continue;
    }
    KernelLexPutBackSoft(cc);
    return ch;
  }
}
// Lex I64 digit run → cc->cur_i64; 0 OK, -1 fail (stock Lex number tip SoftCall-lite).
I64 KernelLexI64Soft(CKernelCmpCtrlSoft *cc)
{
  I64 ch, n;
  ch = KernelLexSkipSpaceSoft(cc);
  if (ch < '0' || ch > '9')
    return -1;
  n = 0;
  while (TRUE) {
    ch = KernelLexGetCharSoft(cc);
    if (ch < '0' || ch > '9') {
      if (ch)
        KernelLexPutBackSoft(cc);
      break;
    }
    n = n * 10 + ch - '0';
  }
  cc->cur_i64 = n;
  return 0;
}
// SoftCall-lite ExePutS expr: CmpCtrlNew-shaped + Lex I64 +/- → res (phase3
// ExePutS("40+2;")→42 needle). No LexStmt2Bin / Prs / Opt / emit.
I64 KernelExePutSExprSoft(U8 *buf)
{
  CKernelCmpCtrlSoft cc;
  I64 a, b, ch, op;
  if (!buf)
    return -100;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  if (KernelLexI64Soft(&cc))
    return -101;
  a = cc.cur_i64;
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch == ';')
    return a;
  if (ch != '+' && ch != '-')
    return -102;
  op = ch;
  KernelLexGetCharSoft(&cc);
  if (KernelLexI64Soft(&cc))
    return -103;
  b = cc.cur_i64;
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != ';')
    return -104;
  if (op == '+')
    return a + b;
  return a - b;
}
// SoftCall prove: CmpCtrl+ExePutS SoftCall-lite ("40+2;"→42) past StartOSSoft.
public I64 KernelExePutSSoft()
{
  CKernelCmpCtrlSoft cc_stk;
  I64 r;
  r = KernelExePutSExprSoft("40+2;");
  if (r != 42)
    return -1;
  r = KernelExePutSExprSoft("7;");
  if (r != 7)
    return -2;
  r = KernelExePutSExprSoft("10-3;");
  if (r != 7)
    return -3;
  // CmpCtrl New SoftCall-lite: stack ctrl + buf_ptr (stock New shape; no Arena).
  KernelMemSet(&cc_stk(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc_stk.cur_buf_ptr = "1+2;";
  if (KernelLexI64Soft(&cc_stk) || cc_stk.cur_i64 != 1)
    return -4;
  return 0x4550;
  // 'EP'
}
// SoftCall-lite MakeOS CmpWrite (G9): hand-emit RV ret-imm TOSB → FileWrite →
// Load+HashFind+Call. Past ExePutSSoft; SoftCall-lite — no Compiler_RV.
public I64 KernelCmpSoft()
{
  U8 bin[128];
  U8 *p, *pt, *st, *module_base;
  I64 ptoff, file_sz, w, bfh, etype, i, addr, nexp, r;
  CKernelHashTable *table;
  CKernelHash *ent, *hit;
  I64 (*fp)();
  // SoftCall-lite ExePutS must stay green (CmpCtrl tip before CmpWrite).
  if (KernelExePutSExprSoft("40+2;") != 42)
    return -1;
  // Reclaim SoftCall arena — prior SoftCalls leave Hash/Load debris (~64 KiB).
  KernelArenaReset;
  KernelMemSet(bin, 0, sizeof(bin));
  // CBinFile hdr: signature @4; code @32; patch table after 8 B code.
  *(bin + 4)(U32 *) = KERNEL_BIN_SIGNATURE_VAL;
  // addi a0,x0,42 ; ret  (SoftCall-lite emit — not LexStmt2Bin)
  *(bin + KERNEL_CBIN_HDR)(U32 *) = 0x02A00513;
  *(bin + KERNEL_CBIN_HDR + 4)(U32 *) = 0x00008067;
  ptoff = KERNEL_CBIN_HDR + 8;
  p = bin + ptoff;
  *p++ = KERNEL_IET_REL64_EXPORT;
  *p(U32 *) = 0;
  p += 4;
  *p++ = 'C';
  *p++ = 'm';
  *p++ = 'p';
  *p++ = 'S';
  *p++ = 'o';
  *p++ = 'f';
  *p++ = 't';
  *p++ = 'P';
  *p++ = 'r';
  *p++ = 'o';
  *p++ = 'b';
  *p++ = 'e';
  *p++ = 0;
  *p++ = KERNEL_IET_END;
  file_sz = p - bin;
  if (file_sz <= 0 || file_sz > 512)
    return -2;
  KernelWriteI64(bin + 16, ptoff);
  KernelWriteI64(bin + 24, file_sz);
  w = KernelFileWrite("A:/MakeOS/SoftCmp.BIN", bin, file_sz);
  if (w < file_sz)
    return -3;
  if (!KernelFileFind("A:/MakeOS/SoftCmp.BIN"))
    return -4;
  // Load+HashFind+Call — same ownership as MakeSoft product Tiny.BIN path.
  bfh = KernelLoad("A:/MakeOS/SoftCmp.BIN");
  if (!bfh || *(bfh(U8 *) + 4)(U32 *) != KERNEL_BIN_SIGNATURE_VAL)
    return -5;
  ptoff = KernelReadI64(bfh(U8 *) + 16);
  if (ptoff <= 0)
    return -6;
  table = KernelHashTableNew(KERNEL_HASH_BUCKETS);
  if (!table || !table->body)
    return -7;
  module_base = bfh(U8 *) + KERNEL_CBIN_HDR;
  pt = bfh(U8 *) + ptoff;
  nexp = 0;
  while (TRUE) {
    etype = *pt++;
    if (etype == KERNEL_IET_END)
      break;
    i = *(pt(U32 *));
    pt += 4;
    st = pt;
    while (*pt)
      pt++;
    pt++;
    if (!*st)
      return -8;
    if (etype == KERNEL_IET_REL32_EXPORT || etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_REL64_EXPORT || etype == KERNEL_IET_IMM64_EXPORT) {
      if (etype == KERNEL_IET_IMM32_EXPORT || etype == KERNEL_IET_IMM64_EXPORT)
        addr = i;
      else
        addr = module_base + i;
      ent = KernelArenaAlloc(sizeof(CKernelHash));
      if (!ent)
        return -9;
      KernelMemSet(ent(U8 *), 0, sizeof(CKernelHash));
      ent->str = st;
      ent->type = KERNEL_HTT_EXPORT;
      ent->val = addr;
      KernelHashAdd(ent, table);
      nexp++;
    } else {
      return -10;
    }
  }
  if (nexp < 1)
    return -11;
  hit = KernelHashFind("CmpSoftProbe", table, KERNEL_HTT_EXPORT, 1);
  if (!hit || !hit->val)
    return -12;
  fp = hit->val;
  r = fp();
  if (r != 42)
    return -13;
  return 0x4343;
  // 'CC'
}
// SoftCall-lite LexStmt2Bin emit: addi rd,rs1,imm12 → 4 B (stock IC→RV tip).
I64 KernelEmitAddiSoft(U8 *dst, I64 rd, I64 rs1, I64 imm)
{
  I64 enc;
  if (!dst)
    return -1;
  if (imm < -2048 || imm > 2047)
    return -2;
  enc = ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((rd & 0x1F) << 7) | 0x13;
  *(dst(U32 *)) = enc;
  return 4;
}
// SoftCall-lite I-type OP-IMM (xori/sltiu for cmp seqz / invert).
I64 KernelEmitITypeSoft(U8 *dst, I64 rd, I64 rs1, I64 imm, I64 funct3)
{
  I64 enc;
  if (!dst)
    return -1;
  if (imm < -2048 || imm > 2047)
    return -2;
  enc = ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 7) << 12) | ((rd & 0x1F) << 7) | 0x13;
  *(dst(U32 *)) = enc;
  return 4;
}
// SoftCall-lite store: sd rs2, imm12(rs1) — a0 frame prologue.
I64 KernelEmitSdSoft(U8 *dst, I64 rs2, I64 rs1, I64 imm)
{
  I64 enc, imm11_5, imm4_0;
  if (!dst)
    return -1;
  if (imm < -2048 || imm > 2047)
    return -2;
  imm11_5 = (imm >> 5) & 0x7F;
  imm4_0 = imm & 0x1F;
  enc = (imm11_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (3 << 12) | (imm4_0 << 7) | 0x23;
  *(dst(U32 *)) = enc;
  return 4;
}
// SoftCall-lite load: ld rd, imm12(rs1) — a0 frame body local.
I64 KernelEmitLdSoft(U8 *dst, I64 rd, I64 rs1, I64 imm)
{
  I64 enc;
  if (!dst)
    return -1;
  if (imm < -2048 || imm > 2047)
    return -2;
  enc = ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | (3 << 12) | ((rd & 0x1F) << 7) | 0x03;
  *(dst(U32 *)) = enc;
  return 4;
}
// SoftCall-lite byte load: lbu rd, imm12(rs1) — U8 * deref (zero-extended).
I64 KernelEmitLbuSoft(U8 *dst, I64 rd, I64 rs1, I64 imm)
{
  I64 enc;
  if (!dst)
    return -1;
  if (imm < -2048 || imm > 2047)
    return -2;
  enc = ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | (4 << 12) | ((rd & 0x1F) << 7) | 0x03;
  *(dst(U32 *)) = enc;
  return 4;
}
// SoftCall-lite byte store: sb rs2, imm12(rs1) — U8 * deref target.
I64 KernelEmitSbSoft(U8 *dst, I64 rs2, I64 rs1, I64 imm)
{
  I64 enc, imm11_5, imm4_0;
  if (!dst)
    return -1;
  if (imm < -2048 || imm > 2047)
    return -2;
  imm11_5 = (imm >> 5) & 0x7F;
  imm4_0 = imm & 0x1F;
  enc = (imm11_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (imm4_0 << 7) | 0x23;
  *(dst(U32 *)) = enc;
  return 4;
}
// SoftCall-lite BEQ (B-type): byte imm from PC; SoftCall BR_ZERO/JMP tip.
I64 KernelEmitBeqSoft(U8 *dst, I64 rs1, I64 rs2, I64 imm)
{
  I64 enc;
  if (!dst)
    return -1;
  if (imm & 1)
    return -2;
  if (imm < -4096 || imm > 4094)
    return -3;
  enc = ((imm & 0x1000) << 19) | ((imm & 0x7E0) << 20) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (((imm >> 1) & 0xF) << 8) | ((imm & 0x800) >> 4) | 0x63;
  *(dst(U32 *)) = enc;
  return 4;
}

I64 KernelEmitBeqzSoft(U8 *dst, I64 rs1, I64 imm)
{
  return KernelEmitBeqSoft(dst, rs1, 0, imm);
}

I64 KernelEmitJmpSoft(U8 *dst, I64 imm)
{
  // beq x0,x0,imm — SoftCall-lite short uncond (±4KiB).
  return KernelEmitBeqSoft(dst, 0, 0, imm);
}
// SoftCall-lite JAL (J-type): imm[20|10:1|11|19:12] scramble; inter-fun CALL (rd=ra).
I64 KernelEmitJalSoft(U8 *dst, I64 rd, I64 imm)
{
  I64 enc;
  if (!dst)
    return -1;
  if (imm & 1)
    return -2;
  if (imm < -1048576 || imm > 1048574)
    return -3;
  enc = ((imm & 0x100000) << 11) | ((imm & 0x7FE) << 20) | ((imm & 0x800) << 9) | (imm & 0xFF000) | ((rd & 0x1F) << 7) | 0x6F;
  *(dst(U32 *)) = enc;
  return 4;
}
// SoftCall-lite absolute address materialize (glbl memory tip).
// lui sign-extends imm20<<12 on RV64, so a RAM address like 0x8xxxxxxx needs a
// slli/srli 32 zero-extend after the addi. Size is address-determined and must be
// known before emit — EmitICBody pass 0 sizes labels with this.
I64 KernelAbsAddrSizeSoft(I64 addr)
{
  I64 hi, lo, v;
  hi = (addr + 0x800) >> 12;
  lo = addr - (hi << 12);
  if (lo < -2048 || lo > 2047)
    return -1;
  v = (hi & 0xFFFFF) << 12;
  if (v & 0x80000000)
    v = v - 0x100000000;
  if (v + lo == addr)
    return 8;
  if (addr < 0 || addr > 0xFFFFFFFF)
    return -1;
  return 16;
}

I64 KernelEmitAbsAddrSoft(U8 *dst, I64 rd, I64 addr)
{
  I64 hi, lo, sz, enc;
  if (!dst)
    return -1;
  sz = KernelAbsAddrSizeSoft(addr);
  if (sz < 0)
    return -2;
  hi = (addr + 0x800) >> 12;
  lo = addr - (hi << 12);
  // lui rd,hi20
  enc = ((hi & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | 0x37;
  *(dst(U32 *)) = enc;
  if (KernelEmitAddiSoft(dst + 4, rd, rd, lo) < 0)
    return -3;
  if (sz == 8)
    return 8;
  // slli rd,rd,32; srli rd,rd,32 — keep the low 32 bits, drop the lui sign fill.
  if (KernelEmitITypeSoft(dst + 8, rd, rd, 32, 1) < 0)
    return -4;
  if (KernelEmitITypeSoft(dst + 12, rd, rd, 32, 5) < 0)
    return -5;
  return 16;
}
// SoftCall-lite LexStmt2Bin (G9): Lex I64 +/- → RV addi a0 + ret into dst.
// Stock LexStmt2Bin/ExePutS JIT shape SoftCall-lite — no Prs/Opt/COC.
I64 KernelLexStmt2BinSoft(U8 *buf, U8 *dst, I64 max)
{
  CKernelCmpCtrlSoft cc;
  I64 a, b, ch, op, n;
  if (!buf || !dst || max < 8)
    return -1;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  if (KernelLexI64Soft(&cc))
    return -2;
  a = cc.cur_i64;
  ch = KernelLexSkipSpaceSoft(&cc);
  n = 0;
  if (ch == ';') {
    if (KernelEmitAddiSoft(dst + n, 10, 0, a) < 0)
      return -3;
    n += 4;
  } else if (ch == '+' || ch == '-') {
    op = ch;
    KernelLexGetCharSoft(&cc);
    if (KernelLexI64Soft(&cc))
      return -4;
    b = cc.cur_i64;
    ch = KernelLexSkipSpaceSoft(&cc);
    if (ch != ';')
      return -5;
    if (max < 12)
      return -6;
    if (KernelEmitAddiSoft(dst + n, 10, 0, a) < 0)
      return -7;
    n += 4;
    if (op == '-')
      b = -b;
    if (KernelEmitAddiSoft(dst + n, 10, 10, b) < 0)
      return -8;
    n += 4;
  } else
    return -9;
  *(dst + n)(U32 *) = 0x00008067;
  // ret
  n += 4;
  return n;
}
// Emit + FenceI + Call — SoftCall-lite LexStmt2Bin JIT (past ExePutS interpret).
I64 KernelLexStmt2BinCallSoft(U8 *buf)
{
  I64 sz;
  I64 (*fp)();
  sz = KernelLexStmt2BinSoft(buf, kernel_lex_stmt_code, sizeof(kernel_lex_stmt_code));
  if (sz < 8)
    return -100;
  KernelFenceI;
  fp = &kernel_lex_stmt_code;
  return fp();
}
// SoftCall prove: LexStmt2Bin SoftCall-lite emit+Call ("40+2;"→42) past CmpSoft.
public I64 KernelLexStmtSoft()
{
  I64 r;
  // SoftCall-lite ExePutS interpret must stay green (CmpCtrl tip before emit).
  if (KernelExePutSExprSoft("40+2;") != 42)
    return -1;
  r = KernelLexStmt2BinCallSoft("40+2;");
  if (r != 42)
    return -2;
  r = KernelLexStmt2BinCallSoft("7;");
  if (r != 7)
    return -3;
  r = KernelLexStmt2BinCallSoft("10-3;");
  if (r != 7)
    return -4;
  // Distinct from CmpSoft hand-compose: Lex→emit→Call without FileWrite TOSB.
  return 0x4C42;
  // 'LB'
}
// SoftCall-lite IC tip (stock IntermediateCode shape SoftCall-lite — no COC).
#define KERNEL_IC_END 0
#define KERNEL_IC_IMM 1
#define KERNEL_IC_ADD 2
#define KERNEL_IC_SUB 3
#define KERNEL_IC_MUL 4
#define KERNEL_IC_LOCAL 5
#define KERNEL_IC_ASSIGN 6
// SoftCall-lite BR: branch if TOS==0 / uncond jmp / label (ic_data=label id).
#define KERNEL_IC_BR_ZERO 7
#define KERNEL_IC_JMP 8
#define KERNEL_IC_LABEL 9
// SoftCall-lite cmp: relational → 0/1 on stack (feeds BR_ZERO; not truthy-only).
#define KERNEL_IC_LESS 10
#define KERNEL_IC_GREATER 11
#define KERNEL_IC_LESS_EQU 12
#define KERNEL_IC_GREATER_EQU 13
#define KERNEL_IC_EQU_EQU 14
#define KERNEL_IC_NOT_EQU 15
// SoftCall-lite inter-fun CALL: ic_data = planted fun slot → RV jal ra (leftmost).
#define KERNEL_IC_CALL 16
// SoftCall-lite glbl memory: ic_data = planted glbl slot. Emitted code materializes
// the glbl's absolute address (lui/addi [+slli/srli]) and ld/sd through it — real
// BIN data, not a frame local and not a plant-time value.
#define KERNEL_IC_GLBL 17
#define KERNEL_IC_GLBL_ASSIGN 18
// SoftCall-lite typed values: the address of a `U8 name[N];` glbl (array decay), and
// byte-width deref through whatever address is on top of the lite RPN stack.
// IC_GLBL_ADDR pushes the address itself — no ld — so it is the one IC that yields a
// pointer rather than an I64 read out of storage.
#define KERNEL_IC_GLBL_ADDR 19
#define KERNEL_IC_LOAD_U8 20
#define KERNEL_IC_STORE_U8 21
// SoftCall-lite `U0 name(...);` statement call: the same jal ra IC_CALL emits, but the
// callee leaves no value, so the lite RPN stack goes back to empty instead of depth 1.
// A separate code (rather than a flag on IC_CALL) keeps KernelOptPassSoft's refusal
// total — it has no arm for either, so a U0 call can never be plant-time folded.
#define KERNEL_IC_CALL_U0 22
// SoftCall-lite COC: Expr then store to frame local (pop; multi-stmt sequencing).
#define KERNEL_PRS_IC_MAX 32
// Wide enough for real Compiler_RV names read off RedSea (g_rv_asm_exports,
// RvAsmExportsInit) instead of the 7-char in-BIN seed idents.
#define KERNEL_SOFT_IDENT_MAX 24
// Four args at 8..32(sp) plus body locals: the survey's fun-arg blocker only falls
// off a cliff at arity 4 (162 blocked -> 63), and a 4-arg body that also declares
// working locals is what needs the 8 slots.
#define KERNEL_SOFT_LOCAL_MAX 8
#define KERNEL_SOFT_ARG_MAX 4
// Every SoftCall-lite tip before the glbl-fun path (AbiSoft 'AB' / CocSoft 'CO' /
// FunBodySoft 'FB' / FunCallSoft 'FC') hand-emits a two-slot a0/a1 frame, so those
// keep their own bound — raising KERNEL_SOFT_ARG_MAX must not let them accept a
// third arg they have no spill for.
#define KERNEL_SOFT_ABI_ARG_MAX 2
#define KERNEL_SOFT_ABI_FRAME 16
#define KERNEL_SOFT_LABEL_MAX 8
// SoftCall-lite value types. I64 is the whole of every tip up to 'GA'; the rest are
// what 212 of the 225 Compiler_RV functions actually return:
//   U0   — no value at all. `return;` or falling off the end, and the caller may not
//          read a0, so a U0 call is a statement and never an Expr.
//   Bool — 1 if nonzero, 0 if zero. A real narrowing (snez), not "any nonzero".
//   U32  — the low 4 bytes, zero-extended. RISC-V `lw` sign-extends and `lwu` does
//          not, and U32 is unsigned, so the emitted narrowing must be srli-based.
//   PTR  — a machine-width address (`U8 *` / `C8 *`). No narrowing.
//   U8   — a 1-byte base name (`U8` / `C8`). Only legal with a `*` or a `[N]`; there
//          is no 1-byte return or arg narrowing, so a bare `U8 F()` is refused.
#define KERNEL_SOFT_TYPE_I64 0
#define KERNEL_SOFT_TYPE_U0 1
#define KERNEL_SOFT_TYPE_BOOL 2
#define KERNEL_SOFT_TYPE_U32 3
#define KERNEL_SOFT_TYPE_PTR 4
#define KERNEL_SOFT_TYPE_U8 5
class CKernelICSoft
{
  I64 ic_code, ic_data;
};

class CKernelLocalSoft
{
  U8 name[KERNEL_SOFT_IDENT_MAX];
  I64 val;
  I64 abi_off;
  // -1 = plant val; >=0 = frame offset (a0/a1 SoftCall-lite ABI).
};
CKernelICSoft kernel_prs_ic[KERNEL_PRS_IC_MAX];
U8 kernel_lex_ident[KERNEL_SOFT_IDENT_MAX];
CKernelLocalSoft kernel_soft_locals[KERNEL_SOFT_LOCAL_MAX];
I64 kernel_soft_local_n;
I64 KernelPrsICPushSoft(CKernelICSoft *ic, I64 *n, I64 max, I64 code, I64 data)
{
  if (!ic || !n || *n < 0 || *n >= max)
    return -1;
  ic[*n].ic_code = code;
  ic[*n].ic_data = data;
  *n = *n + 1;
  return 0;
}

I64 KernelStrEqSoft(U8 *a, U8 *b)
{
  if (!a || !b)
    return 0;
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return !*a && !*b;
}

I64 KernelLocalFindSoft(U8 *name)
{
  I64 i;
  if (!name)
    return -1;
  for (i = 0; i < kernel_soft_local_n; i++) {
    if (KernelStrEqSoft(kernel_soft_locals[i].name, name))
      return i;
  }
  return -1;
}

I64 KernelLocalPlantSoft(U8 *name, I64 val)
{
  I64 i, n;
  if (!name || !*name)
    return -1;
  i = KernelLocalFindSoft(name);
  if (i >= 0) {
    kernel_soft_locals[i].val = val;
    kernel_soft_locals[i].abi_off = -1;
    return i;
  }
  if (kernel_soft_local_n >= KERNEL_SOFT_LOCAL_MAX)
    return -2;
  i = kernel_soft_local_n;
  kernel_soft_local_n = i + 1;
  n = 0;
  while (name[n] && n < KERNEL_SOFT_IDENT_MAX - 1) {
    kernel_soft_locals[i].name[n] = name[n];
    n++;
  }
  kernel_soft_locals[i].name[n] = 0;
  kernel_soft_locals[i].val = val;
  kernel_soft_locals[i].abi_off = -1;
  return i;
}
// SoftCall-lite ABI arg local: body loads from frame offset (no plant-at-call val).
I64 KernelLocalPlantAbiSoft(U8 *name, I64 frame_off)
{
  I64 i, n;
  if (!name || !*name)
    return -1;
  i = KernelLocalFindSoft(name);
  if (i >= 0) {
    kernel_soft_locals[i].val = 0;
    kernel_soft_locals[i].abi_off = frame_off;
    return i;
  }
  if (kernel_soft_local_n >= KERNEL_SOFT_LOCAL_MAX)
    return -2;
  i = kernel_soft_local_n;
  kernel_soft_local_n = i + 1;
  n = 0;
  while (name[n] && n < KERNEL_SOFT_IDENT_MAX - 1) {
    kernel_soft_locals[i].name[n] = name[n];
    n++;
  }
  kernel_soft_locals[i].name[n] = 0;
  kernel_soft_locals[i].val = 0;
  kernel_soft_locals[i].abi_off = frame_off;
  return i;
}

I64 KernelLocalValSoft(I64 slot)
{
  if (slot < 0 || slot >= kernel_soft_local_n)
    return 0x8000000000000000;
  if (kernel_soft_locals[slot].abi_off >= 0)
    return 0x8000000000000000;
  // ABI locals are not foldable plant vals.
  return kernel_soft_locals[slot].val;
}

I64 KernelLocalAbiOffSoft(I64 slot)
{
  if (slot < 0 || slot >= kernel_soft_local_n)
    return -1;
  return kernel_soft_locals[slot].abi_off;
}
// SoftCall-lite COC frame: cover highest abi_off, 16-byte aligned (addi imm).
I64 KernelSoftFrameSizeSoft()
{
  I64 i, max_off, frame;
  max_off = -1;
  for (i = 0; i < kernel_soft_local_n; i++) {
    if (kernel_soft_locals[i].abi_off > max_off)
      max_off = kernel_soft_locals[i].abi_off;
  }
  if (max_off < 0)
    return 0;
  frame = max_off + 8;
  frame = (frame + 15) & ~15;
  if (frame < 16)
    frame = 16;
  if (frame > 2047)
    return -1;
  return frame;
}
// Lex ident run → kernel_lex_ident; 0 OK, -1 fail (stock TK_IDENT tip SoftCall-lite).
I64 KernelLexIdentSoft(CKernelCmpCtrlSoft *cc)
{
  I64 ch, n;
  ch = KernelLexSkipSpaceSoft(cc);
  if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'))
    return -1;
  n = 0;
  while (TRUE) {
    ch = KernelLexGetCharSoft(cc);
    if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_')) {
      if (ch)
        KernelLexPutBackSoft(cc);
      break;
    }
    if (n >= KERNEL_SOFT_IDENT_MAX - 1)
      return -2;
    kernel_lex_ident[n++] = ch;
  }
  if (!n)
    return -3;
  kernel_lex_ident[n] = 0;
  return 0;
}
// SoftCall-lite OptPass012 tip: RPN constant-fold → single IMM (no IC mutations).
I64 KernelOptPassSoft(CKernelICSoft *ic, I64 n)
{
  I64 stk[KERNEL_PRS_IC_MAX];
  I64 sp, i, a, b, code, slot, val;
  if (!ic || n <= 0 || n > KERNEL_PRS_IC_MAX)
    return 0x8000000000000000;
  sp = 0;
  for (i = 0; i < n; i++) {
    code = ic[i].ic_code;
    if (code == KERNEL_IC_IMM) {
      if (sp >= KERNEL_PRS_IC_MAX)
        return 0x8000000000000000;
      stk[sp++] = ic[i].ic_data;
    } else if (code == KERNEL_IC_LOCAL) {
      if (sp >= KERNEL_PRS_IC_MAX)
        return 0x8000000000000000;
      slot = ic[i].ic_data;
      val = KernelLocalValSoft(slot);
      if (val == 0x8000000000000000)
        return 0x8000000000000000;
      stk[sp++] = val;
    } else if (code == KERNEL_IC_ADD || code == KERNEL_IC_SUB || code == KERNEL_IC_MUL || code == KERNEL_IC_LESS || code == KERNEL_IC_GREATER || code == KERNEL_IC_LESS_EQU || code == KERNEL_IC_GREATER_EQU || code == KERNEL_IC_EQU_EQU || code == KERNEL_IC_NOT_EQU) {
      if (sp < 2)
        return 0x8000000000000000;
      b = stk[--sp];
      a = stk[--sp];
      if (code == KERNEL_IC_ADD)
        stk[sp++] = a + b;
      else if (code == KERNEL_IC_SUB)
        stk[sp++] = a - b;
      else if (code == KERNEL_IC_MUL)
        stk[sp++] = a *b;
      else if (code == KERNEL_IC_LESS)
        stk[sp++] = a < b;
      else if (code == KERNEL_IC_GREATER)
        stk[sp++] = a > b;
      else if (code == KERNEL_IC_LESS_EQU)
        stk[sp++] = a <= b;
      else if (code == KERNEL_IC_GREATER_EQU)
        stk[sp++] = a >= b;
      else if (code == KERNEL_IC_EQU_EQU)
        stk[sp++] = a == b;
      else
        stk[sp++] = a != b;
    } else
      return 0x8000000000000000;
  }
  if (sp != 1)
    return 0x8000000000000000;
  return stk[0];
}
// SoftCall-lite HashFun tip: name → emitted body entry (no COC / CHashFun).
// Declared before PrsFactor/EmitIC so the inter-fun CALL IC can resolve a
// planted callee entry (IC_CALL → RV jal ra) without a Compiler.BIN hash.
// 4 funs / 1 KiB of emitted code: the guest slice read off RedSea is a three-deep
// call chain whose glbl stores alone need 248 B, and the U8 * walk pays 16 B per
// absolute address (lui/addi/slli/srli on a 0x8xxxxxxx RAM cell). The board prints
// the deepest emitted byte count so the headroom stays measured, not assumed.
// Eight funs / 1 KiB of emitted code: the typed guest slice read off RedSea declares
// one fun per return type plus an entry, which is seven funs and 692 B of code. The
// board prints the deepest emitted byte count so the headroom stays measured, not
// assumed — FUN_CODE did not have to move for this tip, only FUN_MAX.
#define KERNEL_SOFT_FUN_MAX 8
#define KERNEL_SOFT_FUN_CODE 1024
class CKernelFunSoft
{
  U8 name[KERNEL_SOFT_IDENT_MAX];
  U8 *code;
  // Declared arg count: the call site must supply exactly this many, and the
  // emitter uses it to know how deep the lite RPN stack may legally be at the jal.
  I64 nargs;
  // Declared return type (KERNEL_SOFT_TYPE_*). A U0 fun may only be Called as a
  // statement, and every other kind narrows a0 in its own epilogue, so the call site
  // never has to know the width.
  I64 rtype;
  // Declared arg types, 4 bits each (arg k in bits 4k..4k+3). The callee prologue
  // narrows each Bool / U32 arg before spilling it, so a body reference to an arg is
  // an ordinary IC_LOCAL ld of an already-correct value.
  I64 argt;
};
U8 kernel_fun_code[KERNEL_SOFT_FUN_CODE];
I64 kernel_fun_code_off;
CKernelFunSoft kernel_soft_funs[KERNEL_SOFT_FUN_MAX];
I64 kernel_soft_fun_n;
// SoftCall-lite glbl table (stock CHashGlblVar tip SoftCall-lite — no Compiler.BIN
// hash). Each slot's val is real Kernel.BIN data; emitted code reaches it by
// absolute address, so a store in one fun is visible to a later fun's load and to
// HolyC readback. Declared before PrsFactor/EmitIC so IC_GLBL can resolve a slot.
#define KERNEL_SOFT_GLBL_MAX 4
// Byte storage behind a `U8 name[N];` file-scope decl — the buffer a U8 * walks.
#define KERNEL_SOFT_GLBL_ARR 16
// Glbl kinds: an I64 cell, a U8 * cell (still 8 bytes of storage, deref-able), and a
// U8 array whose name decays to its address instead of loading a value.
#define KERNEL_GLBL_KIND_I64 0
#define KERNEL_GLBL_KIND_PTR 1
#define KERNEL_GLBL_KIND_ARR 2
class CKernelGlblSoft
{
  U8 name[KERNEL_SOFT_IDENT_MAX];
  I64 val;
  I64 kind;
  I64 arr_sz;
  U8 arr[KERNEL_SOFT_GLBL_ARR];
};
CKernelGlblSoft kernel_soft_glbls[KERNEL_SOFT_GLBL_MAX];
I64 kernel_soft_glbl_n;
I64 KernelGlblFindSoft(U8 *name)
{
  I64 i;
  if (!name)
    return -1;
  for (i = 0; i < kernel_soft_glbl_n; i++) {
    if (KernelStrEqSoft(kernel_soft_glbls[i].name, name))
      return i;
  }
  return -1;
}
// Typed plant: kind picks which storage the slot's address names — the I64/U8 * cell
// or the byte array. arr_sz is only meaningful for KERNEL_GLBL_KIND_ARR.
I64 KernelGlblPlantTypedSoft(U8 *name, I64 kind, I64 arr_sz)
{
  I64 i, n;
  if (!name || !*name)
    return -1;
  if (kind == KERNEL_GLBL_KIND_ARR && (arr_sz < 1 || arr_sz > KERNEL_SOFT_GLBL_ARR))
    return -3;
  i = KernelGlblFindSoft(name);
  if (i < 0) {
    if (kernel_soft_glbl_n >= KERNEL_SOFT_GLBL_MAX)
      return -2;
    i = kernel_soft_glbl_n;
    kernel_soft_glbl_n = i + 1;
    n = 0;
    while (name[n] && n < KERNEL_SOFT_IDENT_MAX - 1) {
      kernel_soft_glbls[i].name[n] = name[n];
      n++;
    }
    kernel_soft_glbls[i].name[n] = 0;
  }
  kernel_soft_glbls[i].val = 0;
  kernel_soft_glbls[i].kind = kind;
  kernel_soft_glbls[i].arr_sz = arr_sz;
  KernelMemSet(kernel_soft_glbls[i].arr, 0, KERNEL_SOFT_GLBL_ARR);
  return i;
}

I64 KernelGlblPlantSoft(U8 *name)
{
  return KernelGlblPlantTypedSoft(name, KERNEL_GLBL_KIND_I64, 0);
}

I64 KernelGlblKindSoft(I64 slot)
{
  if (slot < 0 || slot >= kernel_soft_glbl_n)
    return -1;
  return kernel_soft_glbls[slot].kind;
}
// Absolute address of a planted glbl's storage (0 = no slot). An array names its
// byte buffer; an I64 / U8 * cell names its 8-byte val.
I64 KernelGlblAddrSoft(I64 slot)
{
  I64 *p;
  U8 *b;
  if (slot < 0 || slot >= kernel_soft_glbl_n)
    return 0;
  if (kernel_soft_glbls[slot].kind == KERNEL_GLBL_KIND_ARR) {
    b = kernel_soft_glbls[slot].arr;
    return b(I64);
  }
  p = &kernel_soft_glbls[slot].val;
  return p(I64);
}
I64 KernelFunFindSoft(U8 *name);
// Declared arity of a planted fun — both the call-site Prs and the emitter need it
// before KernelFunPlantArgSoft is defined.
I64 KernelFunNArgsSoft(I64 slot);
// Declared return type of a planted fun — the call site needs it to refuse a U0
// callee as an Expr, and to accept one as a statement.
I64 KernelFunRTypeSoft(I64 slot);
// SoftCall-lite type keyword → KERNEL_SOFT_TYPE_*, or -1 for "not a type name".
// Only the base name is decided here; a trailing '*' is the caller's business, so
// `U8` alone is a byte and `U8 *` is a pointer.
I64 KernelTypeNameSoft(U8 *name)
{
  if (!name)
    return -1;
  if (KernelStrEqSoft(name, "I64"))
    return KERNEL_SOFT_TYPE_I64;
  if (KernelStrEqSoft(name, "U0"))
    return KERNEL_SOFT_TYPE_U0;
  if (KernelStrEqSoft(name, "Bool"))
    return KERNEL_SOFT_TYPE_BOOL;
  if (KernelStrEqSoft(name, "U32"))
    return KERNEL_SOFT_TYPE_U32;
  // `U8` / `C8` on their own are only ever a decl base (`U8 b[N];` / `C8 *p;`) — the
  // caller turns them into KERNEL_SOFT_TYPE_PTR on a `*` and refuses them bare.
  if (KernelStrEqSoft(name, "U8"))
    return KERNEL_SOFT_TYPE_U8;
  if (KernelStrEqSoft(name, "C8"))
    return KERNEL_SOFT_TYPE_U8;
  return -1;
}
// SoftCall-lite PrsExpr forward (PrsFactor '(' Expr ')' mutual recursion).
I64 KernelPrsExprSoft(CKernelCmpCtrlSoft *cc, CKernelICSoft *ic, I64 *n, I64 max);
// SoftCall-lite call tail: the ident has been lexed and '(' is next. Each arg Expr is
// appended to the same IC stream ahead of the CALL IC, so the lite RPN walk leaves
// arg 1 in a0 .. arg 4 in a3 — the real RISC-V argument registers. Arg k's own
// evaluation starts at stack depth k-1, so it only ever allocates a(k-1) upward and
// can never clobber an earlier arg. Shared by the Expr call in PrsFactor and by the
// `U0 name(...);` statement call, so both go through one arity check.
I64 KernelPrsCallTailSoft(CKernelCmpCtrlSoft *cc, CKernelICSoft *ic, I64 *n, I64 max, I64 slot, I64 code)
{
  I64 nargs, ai;
  if (!cc)
    return -1;
  nargs = KernelFunNArgsSoft(slot);
  if (nargs < 0)
    return -7;
  if (KernelLexSkipSpaceSoft(cc) != '(')
    return -8;
  KernelLexGetCharSoft(cc);
  if (nargs) {
    ai = 0;
    while (TRUE) {
      if (KernelPrsExprSoft(cc, ic, n, max))
        return -37;
      ai++;
      if (KernelLexSkipSpaceSoft(cc) != ',')
        break;
      // Too many actuals: the callee's frame has nowhere to spill them.
      if (ai >= nargs)
        return -38;
      KernelLexGetCharSoft(cc);
    }
    // Too few actuals — a(k) would hold whatever the caller left there.
    if (ai != nargs)
      return -38;
  }
  if (KernelLexSkipSpaceSoft(cc) != ')')
    return -8;
  KernelLexGetCharSoft(cc);
  return KernelPrsICPushSoft(ic, n, max, code, slot);
}
// SoftCall-lite PrsFactor: '(' Expr ')' | ident→IC_LOCAL | I64 → IC.
I64 KernelPrsFactorSoft(CKernelCmpCtrlSoft *cc, CKernelICSoft *ic, I64 *n, I64 max)
{
  I64 ch, slot;
  if (!cc)
    return -1;
  ch = KernelLexSkipSpaceSoft(cc);
  if (ch == '(') {
    KernelLexGetCharSoft(cc);
    if (KernelPrsExprSoft(cc, ic, n, max))
      return -2;
    ch = KernelLexSkipSpaceSoft(cc);
    if (ch != ')')
      return -3;
    KernelLexGetCharSoft(cc);
    return 0;
  }
  // Prefix '*' → byte deref of whatever address the inner factor yields. Additive:
  // every earlier SoftCall-lite tip fed a leading '*' to KernelLexI64Soft and failed.
  if (ch == '*') {
    KernelLexGetCharSoft(cc);
    if (KernelPrsFactorSoft(cc, ic, n, max))
      return -9;
    return KernelPrsICPushSoft(ic, n, max, KERNEL_IC_LOAD_U8, 0);
  }
  if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_') {
    if (KernelLexIdentSoft(cc))
      return -5;
    // Inter-fun CALL: ident '(' [Expr (',' Expr)*] ')' → IC_CALL on a planted fun.
    // The arg walk lives in KernelPrsCallTailSoft, shared with the U0 statement call.
    if (KernelLexSkipSpaceSoft(cc) == '(') {
      slot = KernelFunFindSoft(kernel_lex_ident);
      if (slot < 0)
        return -7;
      // A U0 fun produces no value, so it may not appear in an Expr at all — the
      // caller would be reading whatever the callee happened to leave in a0.
      if (KernelFunRTypeSoft(slot) == KERNEL_SOFT_TYPE_U0)
        return -39;
      return KernelPrsCallTailSoft(cc, ic, n, max, slot, KERNEL_IC_CALL);
    }
    slot = KernelLocalFindSoft(kernel_lex_ident);
    if (slot >= 0)
      return KernelPrsICPushSoft(ic, n, max, KERNEL_IC_LOCAL, slot);
    // Glbl memory: only reachable once a decl planted a slot, so every earlier
    // SoftCall-lite tip keeps its LocalFind-miss behaviour.
    slot = KernelGlblFindSoft(kernel_lex_ident);
    if (slot < 0)
      return -6;
    // A `U8 name[N];` glbl decays to its address; an I64 / U8 * cell loads its value.
    if (KernelGlblKindSoft(slot) == KERNEL_GLBL_KIND_ARR)
      return KernelPrsICPushSoft(ic, n, max, KERNEL_IC_GLBL_ADDR, slot);
    return KernelPrsICPushSoft(ic, n, max, KERNEL_IC_GLBL, slot);
  }
  if (KernelLexI64Soft(cc))
    return -4;
  return KernelPrsICPushSoft(ic, n, max, KERNEL_IC_IMM, cc->cur_i64);
}
// SoftCall-lite PrsTerm: Factor (* Factor)* → RPN MUL (stock * precedence tip).
I64 KernelPrsTermSoft(CKernelCmpCtrlSoft *cc, CKernelICSoft *ic, I64 *n, I64 max)
{
  I64 ch;
  if (KernelPrsFactorSoft(cc, ic, n, max))
    return -1;
  while (TRUE) {
    ch = KernelLexSkipSpaceSoft(cc);
    if (ch != '*')
      return 0;
    KernelLexGetCharSoft(cc);
    if (KernelPrsFactorSoft(cc, ic, n, max))
      return -2;
    if (KernelPrsICPushSoft(ic, n, max, KERNEL_IC_MUL, 0))
      return -3;
  }
}
// SoftCall-lite PrsAddExpr: Term ((+|-) Term)* → RPN ADD/SUB (past LexStmt +/- only).
I64 KernelPrsAddExprSoft(CKernelCmpCtrlSoft *cc, CKernelICSoft *ic, I64 *n, I64 max)
{
  I64 ch, op;
  if (KernelPrsTermSoft(cc, ic, n, max))
    return -1;
  while (TRUE) {
    ch = KernelLexSkipSpaceSoft(cc);
    if (ch != '+' && ch != '-')
      return 0;
    op = ch;
    KernelLexGetCharSoft(cc);
    if (KernelPrsTermSoft(cc, ic, n, max))
      return -2;
    if (op == '+') {
      if (KernelPrsICPushSoft(ic, n, max, KERNEL_IC_ADD, 0))
        return -3;
    } else {
      if (KernelPrsICPushSoft(ic, n, max, KERNEL_IC_SUB, 0))
        return -4;
    }
  }
}
// SoftCall-lite PrsExpr: AddExpr [relop AddExpr] → RPN cmp (feeds BR_ZERO).
I64 KernelPrsExprSoft(CKernelCmpCtrlSoft *cc, CKernelICSoft *ic, I64 *n, I64 max)
{
  I64 ch, ch2, op;
  if (KernelPrsAddExprSoft(cc, ic, n, max))
    return -1;
  ch = KernelLexSkipSpaceSoft(cc);
  if (ch == '<') {
    KernelLexGetCharSoft(cc);
    ch2 = KernelLexSkipSpaceSoft(cc);
    if (ch2 == '=') {
      KernelLexGetCharSoft(cc);
      op = KERNEL_IC_LESS_EQU;
    } else
      op = KERNEL_IC_LESS;
  } else if (ch == '>') {
    KernelLexGetCharSoft(cc);
    ch2 = KernelLexSkipSpaceSoft(cc);
    if (ch2 == '=') {
      KernelLexGetCharSoft(cc);
      op = KERNEL_IC_GREATER_EQU;
    } else
      op = KERNEL_IC_GREATER;
  } else if (ch == '=') {
    KernelLexGetCharSoft(cc);
    // Peek second '=' without SkipSpace (assign is single '=').
    if (!cc->cur_buf_ptr || *cc->cur_buf_ptr != '=') {
      KernelLexPutBackSoft(cc);
      return 0;
    }
    KernelLexGetCharSoft(cc);
    op = KERNEL_IC_EQU_EQU;
  } else if (ch == '!') {
    KernelLexGetCharSoft(cc);
    ch2 = KernelLexSkipSpaceSoft(cc);
    if (ch2 != '=')
      return -5;
    KernelLexGetCharSoft(cc);
    op = KERNEL_IC_NOT_EQU;
  } else
    return 0;
  if (KernelPrsAddExprSoft(cc, ic, n, max))
    return -6;
  if (KernelPrsICPushSoft(ic, n, max, op, 0))
    return -7;
  return 0;
}
// SoftCall-lite LexStmt2Bin via Prs→Opt→emit (stock COCCompile tip SoftCall-lite).
I64 KernelPrsOpt2BinSoft(U8 *buf, U8 *dst, I64 max)
{
  CKernelCmpCtrlSoft cc;
  I64 n, ch, folded, enc;
  if (!buf || !dst || max < 8)
    return -1;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  n = 0;
  if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
    return -2;
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != ';')
    return -3;
  KernelLexGetCharSoft(&cc);
  folded = KernelOptPassSoft(kernel_prs_ic, n);
  if (folded == 0x8000000000000000)
    return -4;
  if (folded < -2048 || folded > 2047)
    return -5;
  enc = KernelEmitAddiSoft(dst, 10, 0, folded);
  if (enc < 0)
    return -6;
  *(dst + enc)(U32 *) = 0x00008067;
  // ret
  return enc + 4;
}

I64 KernelPrsOptCallSoft(U8 *buf)
{
  I64 sz;
  I64 (*fp)();
  sz = KernelPrsOpt2BinSoft(buf, kernel_lex_stmt_code, sizeof(kernel_lex_stmt_code));
  if (sz < 8)
    return -100;
  KernelFenceI;
  fp = &kernel_lex_stmt_code;
  return fp();
}
// SoftCall prove: Prs/Opt SoftCall-lite ("6*7;"→42) past LexStmtSoft.
public I64 KernelPrsOptSoft()
{
  I64 r;
  // SoftCall-lite LexStmt2Bin +/- emit must stay green (Lex tip before Prs/Opt).
  if (KernelExePutSExprSoft("40+2;") != 42)
    return -1;
  r = KernelLexStmt2BinCallSoft("40+2;");
  if (r != 42)
    return -2;
  // * + precedence past LexStmtSoft I64 +/- only.
  r = KernelPrsOptCallSoft("6*7;");
  if (r != 42)
    return -3;
  r = KernelPrsOptCallSoft("2+5*8;");
  if (r != 42)
    return -4;
  r = KernelPrsOptCallSoft("10-3;");
  if (r != 7)
    return -5;
  r = KernelPrsOptCallSoft("7;");
  if (r != 7)
    return -6;
  return 0x504F;
  // 'PO'
}
// SoftCall-lite R-type: add/sub/mul (funct7/funct3/opcode=OP).
I64 KernelEmitRTypeSoft(U8 *dst, I64 funct7, I64 rs2, I64 rs1, I64 funct3, I64 rd)
{
  I64 enc;
  if (!dst)
    return -1;
  enc = ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 7) << 12) | ((rd & 0x1F) << 7) | 0x33;
  *(dst(U32 *)) = enc;
  return 4;
}
// SoftCall-lite IC emit beyond fold: RPN → RV addi/add/sub/mul into a0..a7 (no OptPass).
// ABI locals (abi_off>=0) → ld from sp frame instead of plant-at-call addi imm.
// IC_ASSIGN → sd top-of-stack to frame local (COC multi-stmt; pop).
// IC_BR_ZERO/JMP/LABEL → SoftCall-lite control-flow (two-pass label patch).
// IC_LESS..NOT_EQU → SoftCall-lite relational cmp (slt/xor → 0/1; feeds BR_ZERO).
// IC_GLBL_ADDR → U8 array decay (abs materialize, no ld — the value is a pointer).
// IC_LOAD_U8/IC_STORE_U8 → lbu/sb through that pointer (byte-width typed access).
#define KERNEL_IC_EMIT_REGS 8
// want_sp is the lite RPN depth the stream must end at: 1 for a body whose value is
// returned in a0, 0 for a U0 body that produces no value at all.
I64 KernelEmitICBodyDepthSoft(CKernelICSoft *ic, I64 n, U8 *dst, I64 max, I64 want_sp)
{
  I64 sp, i, code, imm, off, rd, rs1, rs2, enc, slot, val, abi_off, lb;
  I64 gaddr, gsz;
  I64 label_off[KERNEL_SOFT_LABEL_MAX];
  if (!ic || !dst || n <= 0 || n > KERNEL_PRS_IC_MAX)
    return -1;
  for (i = 0; i < KERNEL_SOFT_LABEL_MAX; i++)
    label_off[i] = -1;
  // Pass 0: record LABEL offsets (insn sizes known SoftCall-lite).
  off = 0;
  for (i = 0; i < n; i++) {
    code = ic[i].ic_code;
    if (code == KERNEL_IC_LABEL) {
      lb = ic[i].ic_data;
      if (lb < 0 || lb >= KERNEL_SOFT_LABEL_MAX)
        return -17;
      if (label_off[lb] >= 0)
        return -18;
      label_off[lb] = off;
    } else if (code == KERNEL_IC_GLBL || code == KERNEL_IC_GLBL_ASSIGN) {
      // Abs materialize + ld/sd; width depends on the glbl's address.
      gsz = KernelAbsAddrSizeSoft(KernelGlblAddrSoft(ic[i].ic_data));
      if (gsz < 0)
        return -27;
      off += gsz + 4;
    } else if (code == KERNEL_IC_GLBL_ADDR) {
      // Address only — no ld/sd follows, the pointer itself is the value.
      gsz = KernelAbsAddrSizeSoft(KernelGlblAddrSoft(ic[i].ic_data));
      if (gsz < 0)
        return -27;
      off += gsz;
    } else if (code == KERNEL_IC_IMM || code == KERNEL_IC_LOCAL || code == KERNEL_IC_ADD || code == KERNEL_IC_SUB || code == KERNEL_IC_MUL || code == KERNEL_IC_ASSIGN || code == KERNEL_IC_BR_ZERO || code == KERNEL_IC_JMP || code == KERNEL_IC_CALL || code == KERNEL_IC_CALL_U0 || code == KERNEL_IC_LESS || code == KERNEL_IC_GREATER || code == KERNEL_IC_LOAD_U8 || code == KERNEL_IC_STORE_U8)
      off += 4;
    else if (code == KERNEL_IC_LESS_EQU || code == KERNEL_IC_GREATER_EQU || code == KERNEL_IC_EQU_EQU || code == KERNEL_IC_NOT_EQU)
      off += 8;
    else
      return -9;
  }
  // Pass 1: emit with resolved branch imms.
  sp = 0;
  off = 0;
  for (i = 0; i < n; i++) {
    code = ic[i].ic_code;
    if (code == KERNEL_IC_LABEL)
      continue;
    if (code == KERNEL_IC_IMM || code == KERNEL_IC_LOCAL) {
      if (sp >= KERNEL_IC_EMIT_REGS)
        return -2;
      rd = 10 + sp;
      if (code == KERNEL_IC_IMM) {
        imm = ic[i].ic_data;
        if (imm < -2048 || imm > 2047)
          return -3;
        if (off + 4 > max)
          return -4;
        enc = KernelEmitAddiSoft(dst + off, rd, 0, imm);
        if (enc < 0)
          return -5;
        off += enc;
      } else {
        slot = ic[i].ic_data;
        abi_off = KernelLocalAbiOffSoft(slot);
        if (abi_off >= 0) {
          if (off + 4 > max)
            return -4;
          enc = KernelEmitLdSoft(dst + off, rd, 2, abi_off);
          if (enc < 0)
            return -5;
          off += enc;
        } else {
          val = KernelLocalValSoft(slot);
          if (val == 0x8000000000000000)
            return -12;
          imm = val;
          if (imm < -2048 || imm > 2047)
            return -3;
          if (off + 4 > max)
            return -4;
          enc = KernelEmitAddiSoft(dst + off, rd, 0, imm);
          if (enc < 0)
            return -5;
          off += enc;
        }
      }
      sp++;
    } else if (code == KERNEL_IC_ADD || code == KERNEL_IC_SUB || code == KERNEL_IC_MUL || code == KERNEL_IC_LESS || code == KERNEL_IC_GREATER || code == KERNEL_IC_LESS_EQU || code == KERNEL_IC_GREATER_EQU || code == KERNEL_IC_EQU_EQU || code == KERNEL_IC_NOT_EQU) {
      if (sp < 2)
        return -6;
      if (code == KERNEL_IC_LESS_EQU || code == KERNEL_IC_GREATER_EQU || code == KERNEL_IC_EQU_EQU || code == KERNEL_IC_NOT_EQU) {
        if (off + 8 > max)
          return -7;
      } else if (off + 4 > max)
        return -7;
      rs2 = 10 + sp - 1;
      rs1 = 10 + sp - 2;
      rd = rs1;
      if (code == KERNEL_IC_ADD)
        enc = KernelEmitRTypeSoft(dst + off, 0, rs2, rs1, 0, rd);
      else if (code == KERNEL_IC_SUB)
        enc = KernelEmitRTypeSoft(dst + off, 0x20, rs2, rs1, 0, rd);
      else if (code == KERNEL_IC_MUL)
        enc = KernelEmitRTypeSoft(dst + off, 1, rs2, rs1, 0, rd);
      else if (code == KERNEL_IC_LESS)
        enc = KernelEmitRTypeSoft(dst + off, 0, rs2, rs1, 2, rd);
      else if (code == KERNEL_IC_GREATER)
        enc = KernelEmitRTypeSoft(dst + off, 0, rs1, rs2, 2, rd);
      else if (code == KERNEL_IC_LESS_EQU) {
        // !(b < a) → slt a,b; xori a,a,1
        enc = KernelEmitRTypeSoft(dst + off, 0, rs1, rs2, 2, rd);
        if (enc < 0)
          return -8;
        off += enc;
        enc = KernelEmitITypeSoft(dst + off, rd, rd, 1, 4);
      } else if (code == KERNEL_IC_GREATER_EQU) {
        // !(a < b) → slt a,b; xori a,a,1
        enc = KernelEmitRTypeSoft(dst + off, 0, rs2, rs1, 2, rd);
        if (enc < 0)
          return -8;
        off += enc;
        enc = KernelEmitITypeSoft(dst + off, rd, rd, 1, 4);
      } else if (code == KERNEL_IC_EQU_EQU) {
        // seqz(a^b) → xor; sltiu rd,rd,1
        enc = KernelEmitRTypeSoft(dst + off, 0, rs2, rs1, 4, rd);
        if (enc < 0)
          return -8;
        off += enc;
        enc = KernelEmitITypeSoft(dst + off, rd, rd, 1, 3);
      } else {
        // snez(a^b) → xor; sltu rd,x0,rd
        enc = KernelEmitRTypeSoft(dst + off, 0, rs2, rs1, 4, rd);
        if (enc < 0)
          return -8;
        off += enc;
        enc = KernelEmitRTypeSoft(dst + off, 0, rd, 0, 3, rd);
      }
      if (enc < 0)
        return -8;
      off += enc;
      sp--;
    } else if (code == KERNEL_IC_ASSIGN) {
      if (sp < 1)
        return -14;
      if (off + 4 > max)
        return -4;
      rs2 = 10 + sp - 1;
      slot = ic[i].ic_data;
      abi_off = KernelLocalAbiOffSoft(slot);
      if (abi_off < 0)
        return -15;
      enc = KernelEmitSdSoft(dst + off, rs2, 2, abi_off);
      if (enc < 0)
        return -16;
      off += enc;
      sp--;
    } else if (code == KERNEL_IC_BR_ZERO) {
      if (sp < 1)
        return -19;
      if (off + 4 > max)
        return -4;
      rs1 = 10 + sp - 1;
      lb = ic[i].ic_data;
      if (lb < 0 || lb >= KERNEL_SOFT_LABEL_MAX || label_off[lb] < 0)
        return -20;
      imm = label_off[lb] - off;
      enc = KernelEmitBeqzSoft(dst + off, rs1, imm);
      if (enc < 0)
        return -21;
      off += enc;
      sp--;
    } else if (code == KERNEL_IC_JMP) {
      if (off + 4 > max)
        return -4;
      lb = ic[i].ic_data;
      if (lb < 0 || lb >= KERNEL_SOFT_LABEL_MAX || label_off[lb] < 0)
        return -22;
      imm = label_off[lb] - off;
      enc = KernelEmitJmpSoft(dst + off, imm);
      if (enc < 0)
        return -23;
      off += enc;
    } else if (code == KERNEL_IC_CALL || code == KERNEL_IC_CALL_U0) {
      if (off + 4 > max)
        return -4;
      slot = ic[i].ic_data;
      if (slot < 0 || slot >= kernel_soft_fun_n)
        return -25;
      // A real jal clobbers a0..a7, so the only values allowed to be in flight are
      // this call's own arguments — and the RPN walk has already put arg k in a(k).
      // Everything else is rejected: `G(1)+2` is fine, `2+G(1)` is not, and neither
      // is `G(1,H(2))`, where H would be reached with G's first arg still live.
      if (sp != kernel_soft_funs[slot].nargs)
        return -24;
      imm = kernel_soft_funs[slot].code(I64) - (dst + off)(I64);
      enc = KernelEmitJalSoft(dst + off, 1, imm);
      if (enc < 0)
        return -26;
      off += enc;
      // Args are consumed by the callee; an I64/Bool/U32/ptr callee returns in a0, so
      // the stack is depth 1. A U0 callee returns nothing, so it goes back to empty —
      // that is the whole difference between the two codes.
      if (code == KERNEL_IC_CALL_U0)
        sp = 0;
      else
        sp = 1;
    } else if (code == KERNEL_IC_GLBL) {
      if (sp >= KERNEL_IC_EMIT_REGS)
        return -2;
      rd = 10 + sp;
      gaddr = KernelGlblAddrSoft(ic[i].ic_data);
      gsz = KernelAbsAddrSizeSoft(gaddr);
      if (gsz < 0)
        return -27;
      if (off + gsz + 4 > max)
        return -4;
      if (KernelEmitAbsAddrSoft(dst + off, rd, gaddr) != gsz)
        return -28;
      off += gsz;
      // ld rd,0(rd) — real load out of BIN data, not a plant-time value.
      enc = KernelEmitLdSoft(dst + off, rd, rd, 0);
      if (enc < 0)
        return -5;
      off += enc;
      sp++;
    } else if (code == KERNEL_IC_GLBL_ASSIGN) {
      if (sp < 1)
        return -29;
      gaddr = KernelGlblAddrSoft(ic[i].ic_data);
      gsz = KernelAbsAddrSizeSoft(gaddr);
      if (gsz < 0)
        return -27;
      if (off + gsz + 4 > max)
        return -4;
      // t0 holds the address: never part of the a0..a7 lite RPN stack.
      if (KernelEmitAbsAddrSoft(dst + off, 5, gaddr) != gsz)
        return -28;
      off += gsz;
      rs2 = 10 + sp - 1;
      enc = KernelEmitSdSoft(dst + off, rs2, 5, 0);
      if (enc < 0)
        return -16;
      off += enc;
      sp--;
    } else if (code == KERNEL_IC_GLBL_ADDR) {
      // U8 name[N] decay: materialize the buffer address and stop — the value on the
      // lite RPN stack is a pointer, not a cell read.
      if (sp >= KERNEL_IC_EMIT_REGS)
        return -2;
      rd = 10 + sp;
      gaddr = KernelGlblAddrSoft(ic[i].ic_data);
      gsz = KernelAbsAddrSizeSoft(gaddr);
      if (gsz < 0)
        return -27;
      if (off + gsz > max)
        return -4;
      if (KernelEmitAbsAddrSoft(dst + off, rd, gaddr) != gsz)
        return -28;
      off += gsz;
      sp++;
    } else if (code == KERNEL_IC_LOAD_U8) {
      // lbu rd,0(rd) — the byte the pointer names right now, never a plant value.
      if (sp < 1)
        return -30;
      if (off + 4 > max)
        return -4;
      rd = 10 + sp - 1;
      enc = KernelEmitLbuSoft(dst + off, rd, rd, 0);
      if (enc < 0)
        return -31;
      off += enc;
    } else if (code == KERNEL_IC_STORE_U8) {
      // sb rs2,0(rs1) — address pushed first, then the value; both pop.
      if (sp < 2)
        return -32;
      if (off + 4 > max)
        return -4;
      rs1 = 10 + sp - 2;
      rs2 = 10 + sp - 1;
      enc = KernelEmitSbSoft(dst + off, rs2, rs1, 0);
      if (enc < 0)
        return -33;
      off += enc;
      sp -= 2;
    } else
      return -9;
  }
  if (sp != want_sp)
    return -10;
  return off;
}
// Value-producing body (every tip through 'GA'): the stream must end at depth 1.
I64 KernelEmitICBodySoft(CKernelICSoft *ic, I64 n, U8 *dst, I64 max)
{
  return KernelEmitICBodyDepthSoft(ic, n, dst, max, 1);
}
// SoftCall-lite return narrowing, emitted between the body and the epilogue so the
// call site never has to know the callee's width.
//   Bool — sltu a0,x0,a0 (snez): 298 comes back as 1, not 298 and not 42.
//   U32  — slli a0,a0,32; srli a0,a0,32: the low 4 bytes, zero-extended. srli (not
//          srai) is what makes it unsigned, so 0x80000000 stays positive.
//   I64 / U0 / ptr — nothing at all.
I64 KernelRetNarrowSizeSoft(I64 rtype)
{
  if (rtype == KERNEL_SOFT_TYPE_BOOL)
    return 4;
  if (rtype == KERNEL_SOFT_TYPE_U32)
    return 8;
  return 0;
}

I64 KernelEmitNarrowSoft(U8 *dst, I64 rd, I64 rtype)
{
  if (!dst)
    return -1;
  if (rtype == KERNEL_SOFT_TYPE_BOOL) {
    // sltu rd,x0,rd
    if (KernelEmitRTypeSoft(dst, 0, rd, 0, 3, rd) < 0)
      return -2;
    return 4;
  }
  if (rtype == KERNEL_SOFT_TYPE_U32) {
    if (KernelEmitITypeSoft(dst, rd, rd, 32, 1) < 0)
      return -3;
    if (KernelEmitITypeSoft(dst + 4, rd, rd, 32, 5) < 0)
      return -4;
    return 8;
  }
  return 0;
}

I64 KernelEmitICSoft(CKernelICSoft *ic, I64 n, U8 *dst, I64 max)
{
  I64 off;
  if (!dst || max < 8)
    return -1;
  off = KernelEmitICBodySoft(ic, n, dst, max - 4);
  if (off < 4)
    return off;
  *(dst + off)(U32 *) = 0x00008067;
  // ret
  return off + 4;
}
// SoftCall-lite inter-fun CALL frame: addi sp,-16; sd ra; body IC (jal ra);
// ld ra; addi sp,16; ret. Callee-side defs reuse it — the frame is harmless.
I64 KernelEmitCallICSoft(CKernelICSoft *ic, I64 n, U8 *dst, I64 max)
{
  I64 off, body;
  if (!ic || !dst || max < 32)
    return -1;
  off = 0;
  if (KernelEmitAddiSoft(dst + off, 2, 2, -16) < 0)
    return -2;
  off += 4;
  if (KernelEmitSdSoft(dst + off, 1, 2, 0) < 0)
    return -3;
  off += 4;
  body = KernelEmitICBodySoft(ic, n, dst + off, max - off - 12);
  if (body < 4)
    return -4;
  off += body;
  if (KernelEmitLdSoft(dst + off, 1, 2, 0) < 0)
    return -5;
  off += 4;
  if (KernelEmitAddiSoft(dst + off, 2, 2, 16) < 0)
    return -6;
  off += 4;
  *(dst + off)(U32 *) = 0x00008067;
  // ret
  return off + 4;
}
// SoftCall-lite glbl-fun frame: addi sp,-frame; sd ra,0(sp); [narrow+spill a0..a3];
// body IC (frame-local ld/sd at 8..frame-8 plus jal ra); [return narrowing]; ld ra;
// addi sp,frame; ret. Locals start at 8 so they never alias the saved ra, and
// frame==16 reproduces the CallIC layout exactly.
// Declared args are the first frame slots (a0@8 .. a3@32), so a body reference to an
// arg is the same IC_LOCAL ld an ordinary `I64 l;` gets. A Bool / U32 arg is narrowed
// in the prologue before its spill, so the body never sees an out-of-range value.
// nargs==0 with an I64 return emits nothing extra at either end, so every shape from
// the tips before 'GA' stays byte-identical.
I64 KernelEmitGlblICSoft(CKernelICSoft *ic, I64 n, I64 frame, I64 nargs, I64 argt, I64 rtype, U8 *dst, I64 max)
{
  I64 off, body, k, at, nw, tail, want_sp;
  if (!dst || max < 32)
    return -1;
  if (frame < 16 || frame > 2047 || (frame & 15))
    return -2;
  if (nargs < 0 || nargs > KERNEL_SOFT_ARG_MAX)
    return -8;
  if (rtype < 0 || rtype > KERNEL_SOFT_TYPE_PTR)
    return -11;
  nw = KernelRetNarrowSizeSoft(rtype);
  // ld ra / addi sp / ret plus whatever the return narrowing costs.
  tail = 12 + nw;
  off = 0;
  if (KernelEmitAddiSoft(dst + off, 2, 2, -frame) < 0)
    return -3;
  off += 4;
  if (KernelEmitSdSoft(dst + off, 1, 2, 0) < 0)
    return -4;
  off += 4;
  k = 0;
  while (k < nargs) {
    at = (argt >> (k * 4)) & 15;
    // Narrow in place first: a Bool arg passed 298 is 1 inside the body, and a U32
    // arg passed 2^32+42 is 42 — the spill then stores the already-correct value.
    body = KernelEmitNarrowSoft(dst + off, 10 + k, at);
    if (body < 0)
      return -12;
    off += body;
    // sd a(k),(8+8k)(sp) — arg k's frame slot, planted by KernelLocalPlantAbiSoft.
    if (KernelEmitSdSoft(dst + off, 10 + k, 2, 8 + k * 8) < 0)
      return -9;
    off += 4;
    k++;
  }
  // A U0 body ends with the lite RPN stack empty; every other kind ends at depth 1
  // with the value in a0.
  if (rtype == KERNEL_SOFT_TYPE_U0)
    want_sp = 0;
  else
    want_sp = 1;
  if (!n) {
    // `U0 name(){}` — a real stock shape: prologue straight into epilogue.
    if (want_sp)
      return -5;
    body = 0;
  } else {
    body = KernelEmitICBodyDepthSoft(ic, n, dst + off, max - off - tail, want_sp);
    if (body < 4)
      return -5;
  }
  off += body;
  body = KernelEmitNarrowSoft(dst + off, 10, rtype);
  if (body != nw)
    return -13;
  off += nw;
  if (KernelEmitLdSoft(dst + off, 1, 2, 0) < 0)
    return -6;
  off += 4;
  if (KernelEmitAddiSoft(dst + off, 2, 2, frame) < 0)
    return -7;
  off += 4;
  *(dst + off)(U32 *) = 0x00008067;
  // ret
  return off + 4;
}
// SoftCall-lite ABI frame: addi sp,-16; sd a0/a1; body IC; addi sp,16; ret.
I64 KernelEmitAbiICSoft(CKernelICSoft *ic, I64 n, I64 nargs, U8 *dst, I64 max)
{
  I64 off, body;
  if (!ic || !dst || nargs < 1 || nargs > KERNEL_SOFT_ABI_ARG_MAX)
    return -1;
  if (max < 24)
    return -2;
  off = 0;
  // addi sp,sp,-16
  if (KernelEmitAddiSoft(dst + off, 2, 2, -16) < 0)
    return -3;
  off += 4;
  // sd a0,0(sp)
  if (KernelEmitSdSoft(dst + off, 10, 2, 0) < 0)
    return -4;
  off += 4;
  if (nargs >= 2) {
    // sd a1,8(sp)
    if (KernelEmitSdSoft(dst + off, 11, 2, 8) < 0)
      return -5;
    off += 4;
  }
  body = KernelEmitICBodySoft(ic, n, dst + off, max - off - 8);
  if (body < 4)
    return -6;
  off += body;
  // addi sp,sp,16
  if (KernelEmitAddiSoft(dst + off, 2, 2, 16) < 0)
    return -7;
  off += 4;
  *(dst + off)(U32 *) = 0x00008067;
  // ret
  return off + 4;
}
// SoftCall-lite COC frame: addi sp,-frame; sd a0/a1; body IC (ASSIGN+Expr); addi sp,frame; ret.
I64 KernelEmitCocICSoft(CKernelICSoft *ic, I64 n, I64 nargs, I64 frame, U8 *dst, I64 max)
{
  I64 off, body, epi;
  if (!ic || !dst || nargs < 0 || nargs > KERNEL_SOFT_ABI_ARG_MAX)
    return -1;
  if (frame < 0 || frame > 2047)
    return -2;
  if (frame && (frame & 15))
    return -3;
  if (max < 16)
    return -4;
  off = 0;
  epi = 4;
  // ret
  if (frame)
    epi += 4;
  // addi sp restore
  if (frame) {
    if (KernelEmitAddiSoft(dst + off, 2, 2, -frame) < 0)
      return -5;
    off += 4;
    if (nargs >= 1) {
      if (KernelEmitSdSoft(dst + off, 10, 2, 0) < 0)
        return -6;
      off += 4;
    }
    if (nargs >= 2) {
      if (KernelEmitSdSoft(dst + off, 11, 2, 8) < 0)
        return -7;
      off += 4;
    }
  }
  body = KernelEmitICBodySoft(ic, n, dst + off, max - off - epi);
  if (body < 4)
    return -8;
  off += body;
  if (frame) {
    if (KernelEmitAddiSoft(dst + off, 2, 2, frame) < 0)
      return -9;
    off += 4;
  }
  *(dst + off)(U32 *) = 0x00008067;
  // ret
  return off + 4;
}
// SoftCall-lite Prs→IC emit (skip OptPass fold) — stock COCCompile tip SoftCall-lite.
I64 KernelPrsIC2BinSoft(U8 *buf, U8 *dst, I64 max)
{
  CKernelCmpCtrlSoft cc;
  I64 n, ch;
  if (!buf || !dst || max < 8)
    return -1;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  n = 0;
  if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
    return -2;
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != ';')
    return -3;
  KernelLexGetCharSoft(&cc);
  return KernelEmitICSoft(kernel_prs_ic, n, dst, max);
}

I64 KernelPrsICCallSoft(U8 *buf)
{
  I64 sz;
  I64 (*fp)();
  sz = KernelPrsIC2BinSoft(buf, kernel_lex_stmt_code, sizeof(kernel_lex_stmt_code));
  if (sz < 8)
    return -100;
  KernelFenceI;
  fp = &kernel_lex_stmt_code;
  return fp();
}
// SoftCall prove: paren + IC emit beyond fold past PrsOptSoft (keeps 'PO' green).
public I64 KernelParenSoft()
{
  I64 r;
  // SoftCall-lite Prs/Opt fold+addi must stay green before paren/IC tip.
  if (KernelPrsOptSoft() != 0x504F)
    return -1;
  // Paren via fold path (PrsFactor '(' Expr ')').
  r = KernelPrsOptCallSoft("(6)*7;");
  if (r != 42)
    return -2;
  r = KernelPrsOptCallSoft("(2+5)*8;");
  if (r != 56)
    return -3;
  r = KernelPrsOptCallSoft("2+(5*8);");
  if (r != 42)
    return -4;
  r = KernelPrsOptCallSoft("((10)-3);");
  if (r != 7)
    return -5;
  // IC emit beyond fold: RPN → addi/add/mul (no OptPass) → Call.
  r = KernelPrsICCallSoft("6*7;");
  if (r != 42)
    return -6;
  r = KernelPrsICCallSoft("(2+5)*8;");
  if (r != 56)
    return -7;
  r = KernelPrsICCallSoft("2+5*8;");
  if (r != 42)
    return -8;
  r = KernelPrsICCallSoft("10-3;");
  if (r != 7)
    return -9;
  return 0x504E;
  // 'PN'
}
// SoftCall prove: local/ident IC past ParenSoft (keeps 'PN'/'PO' green).
// AssignSoft owns PrsStmt assign tip — SoftCall-lite plant+LexIdent here.
public I64 KernelIdentSoft()
{
  I64 r;
  // SoftCall-lite paren+IC emit must stay green before local/ident tip.
  if (KernelParenSoft() != 0x504E)
    return -1;
  kernel_soft_local_n = 0;
  if (KernelLocalPlantSoft("x", 40) < 0)
    return -2;
  if (KernelLocalPlantSoft("y", 2) < 0)
    return -3;
  // Fold path: ident→IC_LOCAL → OptPass val → addi.
  r = KernelPrsOptCallSoft("x+2;");
  if (r != 42)
    return -4;
  r = KernelPrsOptCallSoft("x+y;");
  if (r != 42)
    return -5;
  r = KernelPrsOptCallSoft("(x+1)*y;");
  if (r != 82)
    return -6;
  r = KernelPrsOptCallSoft("x*1+y;");
  if (r != 42)
    return -7;
  // IC emit beyond fold: LOCAL→addi + add/mul (no OptPass) → Call.
  r = KernelPrsICCallSoft("x+2;");
  if (r != 42)
    return -8;
  r = KernelPrsICCallSoft("x+y;");
  if (r != 42)
    return -9;
  r = KernelPrsICCallSoft("(x+y)*1;");
  if (r != 42)
    return -10;
  // Numeric paren path still green with locals planted.
  r = KernelPrsOptCallSoft("(2+5)*8;");
  if (r != 56)
    return -11;
  r = KernelPrsICCallSoft("2+5*8;");
  if (r != 42)
    return -12;
  return 0x4944;
  // 'ID'
}
// SoftCall-lite PrsStmt: (ident=Expr;)* Expr; — assign plants locals, then emit+Call.
// use_ic_emit=0 → OptPass fold+addi; use_ic_emit=1 → EmitIC (no OptPass).
I64 KernelPrsStmtCallSoft(U8 *buf, I64 use_ic_emit)
{
  CKernelCmpCtrlSoft cc;
  U8 *save_ptr;
  U8 name[KERNEL_SOFT_IDENT_MAX];
  I64 save_flags, save_last, n, ch, folded, i, sz;
  I64 (*fp)();
  if (!buf)
    return -1;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  kernel_soft_local_n = 0;
  while (TRUE) {
    ch = KernelLexSkipSpaceSoft(&cc);
    if (!ch)
      return -2;
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_') {
      save_ptr = cc.cur_buf_ptr;
      save_flags = cc.flags;
      save_last = cc.last_U16;
      if (KernelLexIdentSoft(&cc))
        return -3;
      ch = KernelLexSkipSpaceSoft(&cc);
      if (ch == '=') {
        KernelLexGetCharSoft(&cc);
        i = 0;
        while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
          name[i] = kernel_lex_ident[i];
          i++;
        }
        name[i] = 0;
        n = 0;
        if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
          return -4;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != ';')
          return -5;
        KernelLexGetCharSoft(&cc);
        folded = KernelOptPassSoft(kernel_prs_ic, n);
        if (folded == 0x8000000000000000)
          return -6;
        if (KernelLocalPlantSoft(name, folded) < 0)
          return -7;
        continue;
      }
      cc.cur_buf_ptr = save_ptr;
      cc.flags = save_flags;
      cc.last_U16 = save_last;
    }
    n = 0;
    if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
      return -8;
    ch = KernelLexSkipSpaceSoft(&cc);
    if (ch != ';')
      return -9;
    KernelLexGetCharSoft(&cc);
    if (use_ic_emit) {
      sz = KernelEmitICSoft(kernel_prs_ic, n, kernel_lex_stmt_code, sizeof(kernel_lex_stmt_code));
      if (sz < 8)
        return -100;
    } else {
      folded = KernelOptPassSoft(kernel_prs_ic, n);
      if (folded == 0x8000000000000000)
        return -10;
      if (folded < -2048 || folded > 2047)
        return -11;
      sz = KernelEmitAddiSoft(kernel_lex_stmt_code, 10, 0, folded);
      if (sz < 0)
        return -12;
      *(kernel_lex_stmt_code + sz)(U32 *) = 0x00008067;
      // ret
      sz += 4;
    }
    KernelFenceI;
    fp = &kernel_lex_stmt_code;
    return fp();
  }
}
// SoftCall prove: PrsStmt assign fragment past IdentSoft (keeps 'ID'/'PN'/'PO' green).
// Fun-def still SoftCall ceiling — SoftCall-lite assign+expr only.
public I64 KernelAssignSoft()
{
  I64 r;
  // SoftCall-lite local/ident IC must stay green before PrsStmt assign tip.
  if (KernelIdentSoft() != 0x4944)
    return -1;
  // Fold path: assign plants locals from source (no KernelLocalPlantSoft in probe).
  r = KernelPrsStmtCallSoft("x=40;x+2;", 0);
  if (r != 42)
    return -2;
  r = KernelPrsStmtCallSoft("x=40;y=2;x+y;", 0);
  if (r != 42)
    return -3;
  r = KernelPrsStmtCallSoft("x=6;x*7;", 0);
  if (r != 42)
    return -4;
  r = KernelPrsStmtCallSoft("x=40;x=x+2;x;", 0);
  if (r != 42)
    return -5;
  r = KernelPrsStmtCallSoft("x=2;y=5;(x+y)*6;", 0);
  if (r != 42)
    return -6;
  // IC emit beyond fold after assigns.
  r = KernelPrsStmtCallSoft("x=40;x+2;", 1);
  if (r != 42)
    return -7;
  r = KernelPrsStmtCallSoft("x=40;y=2;x+y;", 1);
  if (r != 42)
    return -8;
  r = KernelPrsStmtCallSoft("x=10;y=3;x-y;", 1);
  if (r != 7)
    return -9;
  // Numeric / paren path still green without assigns.
  r = KernelPrsStmtCallSoft("(2+5)*8;", 0);
  if (r != 56)
    return -10;
  r = KernelPrsStmtCallSoft("2+5*8;", 1);
  if (r != 42)
    return -11;
  return 0x4153;
  // 'AS'
}
// SoftCall ENTER scratch — was SoftCall stack (sec[512]); BSS frees SoftCall frame for CmpSrc tip.
U8 kernel_softcall_sec[512];
U8 kernel_softcall_rbuf[8];
U8 kernel_softcall_dst[8];
I64 KernelFunFindSoft(U8 *name)
{
  I64 i;
  if (!name)
    return -1;
  for (i = 0; i < kernel_soft_fun_n; i++) {
    if (KernelStrEqSoft(kernel_soft_funs[i].name, name))
      return i;
  }
  return -1;
}

I64 KernelFunPlantTypedSoft(U8 *name, U8 *code, I64 nargs, I64 argt, I64 rtype)
{
  I64 i, n;
  if (!name || !*name || !code)
    return -1;
  if (nargs < 0 || nargs > KERNEL_SOFT_ARG_MAX)
    return -3;
  if (rtype < 0 || rtype > KERNEL_SOFT_TYPE_PTR)
    return -4;
  i = KernelFunFindSoft(name);
  if (i >= 0) {
    kernel_soft_funs[i].code = code;
    kernel_soft_funs[i].nargs = nargs;
    kernel_soft_funs[i].argt = argt;
    kernel_soft_funs[i].rtype = rtype;
    return i;
  }
  if (kernel_soft_fun_n >= KERNEL_SOFT_FUN_MAX)
    return -2;
  i = kernel_soft_fun_n;
  kernel_soft_fun_n = i + 1;
  n = 0;
  while (name[n] && n < KERNEL_SOFT_IDENT_MAX - 1) {
    kernel_soft_funs[i].name[n] = name[n];
    n++;
  }
  kernel_soft_funs[i].name[n] = 0;
  kernel_soft_funs[i].code = code;
  kernel_soft_funs[i].nargs = nargs;
  kernel_soft_funs[i].argt = argt;
  kernel_soft_funs[i].rtype = rtype;
  return i;
}
// I64-return plant: every tip before the type tip declares `I64 name(...)`.
I64 KernelFunPlantArgSoft(U8 *name, U8 *code, I64 nargs)
{
  return KernelFunPlantTypedSoft(name, code, nargs, 0, KERNEL_SOFT_TYPE_I64);
}
// Arity-0 plant: every tip before the arg tip declares `name()`.
I64 KernelFunPlantSoft(U8 *name, U8 *code)
{
  return KernelFunPlantArgSoft(name, code, 0);
}

I64 KernelFunNArgsSoft(I64 slot)
{
  if (slot < 0 || slot >= kernel_soft_fun_n)
    return -1;
  return kernel_soft_funs[slot].nargs;
}

I64 KernelFunRTypeSoft(I64 slot)
{
  if (slot < 0 || slot >= kernel_soft_fun_n)
    return -1;
  return kernel_soft_funs[slot].rtype;
}
// SoftCall-lite PrsFun: I64 name([I64 arg(,I64 arg)*]){ (ident=Expr;)* [return] Expr; }
//   name([Expr(,Expr)*]);
// Multi-stmt + locals-in-fun + SoftCall-lite multi-arg + call-Expr plant-at-call (no ABI).
// use_ic_emit=0 → OptPass fold+addi; use_ic_emit=1 → EmitIC (no OptPass).
// Emit deferred until after call-site arg plant so IC_LOCAL arg resolves.
// Call-site Expr folds into a temp IC buf so body IC in kernel_prs_ic stays intact.
I64 KernelPrsFunDefCallSoft(U8 *buf, I64 use_ic_emit)
{
  CKernelCmpCtrlSoft cc;
  CKernelICSoft arg_ic[KERNEL_PRS_IC_MAX];
  U8 *save_ptr;
  U8 *ap;
  U8 fname[KERNEL_SOFT_IDENT_MAX];
  U8 anames[KERNEL_SOFT_ARG_MAX *KERNEL_SOFT_IDENT_MAX];
  U8 lname[KERNEL_SOFT_IDENT_MAX];
  I64 save_flags, save_last, n, ch, folded, i, sz, slot, nargs, ai, arg_n;
  I64 (*fp)();
  if (!buf)
    return -1;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  kernel_soft_fun_n = 0;
  kernel_soft_local_n = 0;
  kernel_fun_code_off = 0;
  nargs = 0;
  // Type: I64 (SoftCall-lite — no class hash / PrsType).
  if (KernelLexIdentSoft(&cc))
    return -2;
  if (!KernelStrEqSoft(kernel_lex_ident, "I64"))
    return -3;
  // Fun name.
  if (KernelLexIdentSoft(&cc))
    return -4;
  i = 0;
  while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
    fname[i] = kernel_lex_ident[i];
    i++;
  }
  fname[i] = 0;
  // ( [I64 arg(, I64 arg)*] )
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '(')
    return -5;
  KernelLexGetCharSoft(&cc);
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch == ')') {
    KernelLexGetCharSoft(&cc);
  } else {
    while (TRUE) {
      if (nargs >= KERNEL_SOFT_ABI_ARG_MAX)
        return -50;
      if (KernelLexIdentSoft(&cc))
        return -51;
      if (!KernelStrEqSoft(kernel_lex_ident, "I64"))
        return -52;
      if (KernelLexIdentSoft(&cc))
        return -53;
      ap = anames + nargs *KERNEL_SOFT_IDENT_MAX;
      i = 0;
      while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
        ap[i] = kernel_lex_ident[i];
        i++;
      }
      ap[i] = 0;
      // Placeholder so body IC_LOCAL resolves; call site overwrites val.
      if (KernelLocalPlantSoft(ap, 0) < 0)
        return -54;
      nargs++;
      ch = KernelLexSkipSpaceSoft(&cc);
      if (ch == ',') {
        KernelLexGetCharSoft(&cc);
        continue;
      }
      break;
    }
    if (ch != ')')
      return -6;
    KernelLexGetCharSoft(&cc);
  }
  // {
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '{')
    return -7;
  KernelLexGetCharSoft(&cc);
  // Body: (ident=Expr;)* [return] Expr; — SoftCall-lite PrsStmt tip in fun.
  n = 0;
  while (TRUE) {
    ch = KernelLexSkipSpaceSoft(&cc);
    if (!ch)
      return -70;
    if (ch == '}')
      return -71;
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_') {
      save_ptr = cc.cur_buf_ptr;
      save_flags = cc.flags;
      save_last = cc.last_U16;
      if (KernelLexIdentSoft(&cc))
        return -8;
      if (KernelStrEqSoft(kernel_lex_ident, "return")) {
        // Fall through to final Expr;
      } else {
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch == '=') {
          KernelLexGetCharSoft(&cc);
          i = 0;
          while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
            lname[i] = kernel_lex_ident[i];
            i++;
          }
          lname[i] = 0;
          n = 0;
          if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
            return -55;
          ch = KernelLexSkipSpaceSoft(&cc);
          if (ch != ';')
            return -56;
          KernelLexGetCharSoft(&cc);
          folded = KernelOptPassSoft(kernel_prs_ic, n);
          if (folded == 0x8000000000000000)
            return -57;
          if (KernelLocalPlantSoft(lname, folded) < 0)
            return -58;
          continue;
        }
        cc.cur_buf_ptr = save_ptr;
        cc.flags = save_flags;
        cc.last_U16 = save_last;
      }
    }
    // Final Expr;
    n = 0;
    if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
      return -9;
    ch = KernelLexSkipSpaceSoft(&cc);
    if (ch != ';')
      return -10;
    KernelLexGetCharSoft(&cc);
    break;
  }
  // }
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '}')
    return -11;
  KernelLexGetCharSoft(&cc);
  // Call: name([Expr(,Expr)*]); — plant SoftCall-lite args before emit.
  if (KernelLexIdentSoft(&cc))
    return -17;
  if (!KernelStrEqSoft(kernel_lex_ident, fname))
    return -18;
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '(')
    return -19;
  KernelLexGetCharSoft(&cc);
  ch = KernelLexSkipSpaceSoft(&cc);
  if (nargs) {
    ai = 0;
    while (TRUE) {
      if (ai >= nargs)
        return -59;
      arg_n = 0;
      if (KernelPrsExprSoft(&cc, arg_ic, &arg_n, KERNEL_PRS_IC_MAX))
        return -60;
      folded = KernelOptPassSoft(arg_ic, arg_n);
      if (folded == 0x8000000000000000)
        return -61;
      ap = anames + ai *KERNEL_SOFT_IDENT_MAX;
      if (KernelLocalPlantSoft(ap, folded) < 0)
        return -62;
      ai++;
      ch = KernelLexSkipSpaceSoft(&cc);
      if (ai < nargs) {
        if (ch != ',')
          return -63;
        KernelLexGetCharSoft(&cc);
        continue;
      }
      break;
    }
    if (ai != nargs)
      return -64;
  }
  if (ch != ')')
    return -20;
  KernelLexGetCharSoft(&cc);
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != ';')
    return -21;
  KernelLexGetCharSoft(&cc);
  // Emit body into fun code arena (separate from stmt scratch).
  if (use_ic_emit) {
    sz = KernelEmitICSoft(kernel_prs_ic, n, kernel_fun_code + kernel_fun_code_off, KERNEL_SOFT_FUN_CODE - kernel_fun_code_off);
    if (sz < 8)
      return -100;
  } else {
    folded = KernelOptPassSoft(kernel_prs_ic, n);
    if (folded == 0x8000000000000000)
      return -12;
    if (folded < -2048 || folded > 2047)
      return -13;
    if (kernel_fun_code_off + 8 > KERNEL_SOFT_FUN_CODE)
      return -14;
    sz = KernelEmitAddiSoft(kernel_fun_code + kernel_fun_code_off, 10, 0, folded);
    if (sz < 0)
      return -15;
    *(kernel_fun_code + kernel_fun_code_off + sz)(U32 *) = 0x00008067;
    // ret
    sz += 4;
  }
  if (KernelFunPlantSoft(fname, kernel_fun_code + kernel_fun_code_off) < 0)
    return -16;
  kernel_fun_code_off += sz;
  slot = KernelFunFindSoft(fname);
  if (slot < 0)
    return -65;
  KernelFenceI;
  fp = kernel_soft_funs[slot].code;
  return fp();
}
// SoftCall prove: fun-def + return + Call past AssignSoft (keeps 'AS'/'ID'/'PN' green).
// FunBodySoft owns multi-stmt/args; FunCallSoft owns multi-arg/call-Expr; full Compiler_RV COC + Compiler.BIN Load still ceiling.
public I64 KernelFunDefSoft()
{
  I64 r;
  // SoftCall-lite PrsStmt assign must stay green before fun-def tip.
  if (KernelAssignSoft() != 0x4153)
    return -1;
  // Fold path: I64 F(){return Expr;} F();
  r = KernelPrsFunDefCallSoft("I64 F(){return 40+2;}F();", 0);
  if (r != 42)
    return -2;
  r = KernelPrsFunDefCallSoft("I64 F(){return 6*7;}F();", 0);
  if (r != 42)
    return -3;
  r = KernelPrsFunDefCallSoft("I64 G(){return (2+5)*6;}G();", 0);
  if (r != 42)
    return -4;
  r = KernelPrsFunDefCallSoft("I64 F(){return 10-3;}F();", 0);
  if (r != 7)
    return -5;
  // Implicit return of Expr (no return keyword) SoftCall-lite.
  r = KernelPrsFunDefCallSoft("I64 F(){40+2;}F();", 0);
  if (r != 42)
    return -6;
  // IC emit beyond fold after fun-def.
  r = KernelPrsFunDefCallSoft("I64 F(){return 40+2;}F();", 1);
  if (r != 42)
    return -7;
  r = KernelPrsFunDefCallSoft("I64 F(){return (2+5)*8;}F();", 1);
  if (r != 56)
    return -8;
  r = KernelPrsFunDefCallSoft("I64 F(){return 2+5*8;}F();", 1);
  if (r != 42)
    return -9;
  // AssignSoft tip still green after fun-def plants.
  r = KernelPrsStmtCallSoft("x=40;x+2;", 0);
  if (r != 42)
    return -10;
  return 0x4644;
  // 'FD'
}
// SoftCall prove: multi-stmt + locals-in-fun + SoftCall-lite I64 arg past FunDefSoft.
// FunCallSoft owns multi-arg/call-Expr; full Compiler_RV ABI/COC + Compiler.BIN Load still SoftCall ceiling.
public I64 KernelFunBodySoft()
{
  I64 r;
  // Fun-def/return/Call SoftCall-lite must stay green before body tip.
  if (KernelFunDefSoft() != 0x4644)
    return -1;
  // Multi-stmt + locals-in-fun (fold).
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;return x+2;}F();", 0);
  if (r != 42)
    return -2;
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;y=2;return x+y;}F();", 0);
  if (r != 42)
    return -3;
  r = KernelPrsFunDefCallSoft("I64 F(){x=6;return x*7;}F();", 0);
  if (r != 42)
    return -4;
  // Implicit return after assigns (no return keyword).
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;x+2;}F();", 0);
  if (r != 42)
    return -5;
  r = KernelPrsFunDefCallSoft("I64 F(){x=2;y=5;(x+y)*6;}F();", 0);
  if (r != 42)
    return -6;
  // SoftCall-lite single I64 arg (call-Expr plant-at-call; LexI64 is Expr tip).
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){return a+2;}F(40);", 0);
  if (r != 42)
    return -7;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){return a*7;}F(6);", 0);
  if (r != 42)
    return -8;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){x=2;return a+x;}F(40);", 0);
  if (r != 42)
    return -9;
  // IC emit beyond fold: multi-stmt + arg.
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;return x+2;}F();", 1);
  if (r != 42)
    return -10;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){return a+2;}F(40);", 1);
  if (r != 42)
    return -11;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){x=5;return a*x+2;}F(8);", 1);
  if (r != 42)
    return -12;
  // FunDefSoft tip still green after body plants.
  r = KernelPrsFunDefCallSoft("I64 F(){return 40+2;}F();", 0);
  if (r != 42)
    return -13;
  // AssignSoft tip still green.
  r = KernelPrsStmtCallSoft("x=40;x+2;", 0);
  if (r != 42)
    return -14;
  return 0x4642;
  // 'FB'
}
// SoftCall prove: multi-arg + call-Expr plant-at-call past FunBodySoft.
// AbiSoft owns ABI/a0 frame; SoftCall-lite — no COC / full Compiler.BIN Load.
public I64 KernelFunCallSoft()
{
  I64 r;
  // Multi-stmt/locals/single-arg SoftCall-lite must stay green before call tip.
  if (KernelFunBodySoft() != 0x4642)
    return -1;
  // Multi-arg fold (LexI64 Expr tips).
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a+b;}F(40,2);", 0);
  if (r != 42)
    return -2;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a*b;}F(6,7);", 0);
  if (r != 42)
    return -3;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){x=2;return a+b+x;}F(20,20);", 0);
  if (r != 42)
    return -4;
  // Call-site Expr fold (temp IC; body IC preserved).
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){return a+2;}F(38+2);", 0);
  if (r != 42)
    return -5;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){return a;}F(6*7);", 0);
  if (r != 42)
    return -6;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a+b;}F(38+2,6-4);", 0);
  if (r != 42)
    return -7;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a*b;}F((2+4),7);", 0);
  if (r != 42)
    return -8;
  // IC emit beyond fold: multi-arg + call-Expr.
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a+b;}F(40,2);", 1);
  if (r != 42)
    return -9;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){return a+2;}F(38+2);", 1);
  if (r != 42)
    return -10;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){x=2;return a+b*x;}F(1+1,20);", 1);
  if (r != 42)
    return -11;
  // FunBodySoft tip still green after call plants.
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;return x+2;}F();", 0);
  if (r != 42)
    return -12;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){return a+2;}F(40);", 0);
  if (r != 42)
    return -13;
  // FunDefSoft tip still green.
  r = KernelPrsFunDefCallSoft("I64 F(){return 40+2;}F();", 0);
  if (r != 42)
    return -14;
  return 0x4643;
  // 'FC'
}
// SoftCall-lite PrsFun ABI: I64 name(I64 arg[,I64 arg]){...} name(Expr[,Expr]);
// Plant args as a0 frame locals (no plant-at-call val); emit prologue sd a0/a1;
// body ld from sp; Call via HolyC fp(arg) so a0 arrives at runtime.
I64 KernelPrsFunAbiCallSoft(U8 *buf)
{
  CKernelCmpCtrlSoft cc;
  CKernelICSoft arg_ic[KERNEL_PRS_IC_MAX];
  U8 *save_ptr;
  U8 *ap;
  U8 fname[KERNEL_SOFT_IDENT_MAX];
  U8 anames[KERNEL_SOFT_ARG_MAX *KERNEL_SOFT_IDENT_MAX];
  U8 lname[KERNEL_SOFT_IDENT_MAX];
  I64 save_flags, save_last, n, ch, folded, i, sz, slot, nargs, ai, arg_n;
  I64 argv[KERNEL_SOFT_ARG_MAX];
  I64 (*fp1)(I64);
  I64 (*fp2)(I64, I64);
  if (!buf)
    return -1;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  kernel_soft_fun_n = 0;
  kernel_soft_local_n = 0;
  kernel_fun_code_off = 0;
  nargs = 0;
  if (KernelLexIdentSoft(&cc))
    return -2;
  if (!KernelStrEqSoft(kernel_lex_ident, "I64"))
    return -3;
  if (KernelLexIdentSoft(&cc))
    return -4;
  i = 0;
  while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
    fname[i] = kernel_lex_ident[i];
    i++;
  }
  fname[i] = 0;
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '(')
    return -5;
  KernelLexGetCharSoft(&cc);
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch == ')')
    return -50;
  // SoftCall-lite ABI tip requires ≥1 arg (a0 frame).
  while (TRUE) {
    if (nargs >= KERNEL_SOFT_ABI_ARG_MAX)
      return -51;
    if (KernelLexIdentSoft(&cc))
      return -52;
    if (!KernelStrEqSoft(kernel_lex_ident, "I64"))
      return -53;
    if (KernelLexIdentSoft(&cc))
      return -54;
    ap = anames + nargs *KERNEL_SOFT_IDENT_MAX;
    i = 0;
    while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
      ap[i] = kernel_lex_ident[i];
      i++;
    }
    ap[i] = 0;
    // ABI frame slot: a0@0, a1@8 — not plant-at-call SoftCall val.
    if (KernelLocalPlantAbiSoft(ap, nargs * 8) < 0)
      return -55;
    nargs++;
    ch = KernelLexSkipSpaceSoft(&cc);
    if (ch == ',') {
      KernelLexGetCharSoft(&cc);
      continue;
    }
    break;
  }
  if (ch != ')')
    return -6;
  KernelLexGetCharSoft(&cc);
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '{')
    return -7;
  KernelLexGetCharSoft(&cc);
  n = 0;
  while (TRUE) {
    ch = KernelLexSkipSpaceSoft(&cc);
    if (!ch)
      return -70;
    if (ch == '}')
      return -71;
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_') {
      save_ptr = cc.cur_buf_ptr;
      save_flags = cc.flags;
      save_last = cc.last_U16;
      if (KernelLexIdentSoft(&cc))
        return -8;
      if (KernelStrEqSoft(kernel_lex_ident, "return")) {
        // Fall through to final Expr;
      } else {
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch == '=') {
          KernelLexGetCharSoft(&cc);
          i = 0;
          while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
            lname[i] = kernel_lex_ident[i];
            i++;
          }
          lname[i] = 0;
          n = 0;
          if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
            return -56;
          ch = KernelLexSkipSpaceSoft(&cc);
          if (ch != ';')
            return -57;
          KernelLexGetCharSoft(&cc);
          folded = KernelOptPassSoft(kernel_prs_ic, n);
          if (folded == 0x8000000000000000)
            return -58;
          if (KernelLocalPlantSoft(lname, folded) < 0)
            return -59;
          continue;
        }
        cc.cur_buf_ptr = save_ptr;
        cc.flags = save_flags;
        cc.last_U16 = save_last;
      }
    }
    n = 0;
    if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
      return -9;
    ch = KernelLexSkipSpaceSoft(&cc);
    if (ch != ';')
      return -10;
    KernelLexGetCharSoft(&cc);
    break;
  }
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '}')
    return -11;
  KernelLexGetCharSoft(&cc);
  // Call site: fold Expr args into HolyC argv — do NOT plant SoftCall locals.
  if (KernelLexIdentSoft(&cc))
    return -17;
  if (!KernelStrEqSoft(kernel_lex_ident, fname))
    return -18;
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '(')
    return -19;
  KernelLexGetCharSoft(&cc);
  ai = 0;
  while (TRUE) {
    if (ai >= nargs)
      return -60;
    arg_n = 0;
    if (KernelPrsExprSoft(&cc, arg_ic, &arg_n, KERNEL_PRS_IC_MAX))
      return -61;
    folded = KernelOptPassSoft(arg_ic, arg_n);
    if (folded == 0x8000000000000000)
      return -62;
    argv[ai] = folded;
    ai++;
    ch = KernelLexSkipSpaceSoft(&cc);
    if (ai < nargs) {
      if (ch != ',')
        return -63;
      KernelLexGetCharSoft(&cc);
      continue;
    }
    break;
  }
  if (ai != nargs)
    return -64;
  if (ch != ')')
    return -20;
  KernelLexGetCharSoft(&cc);
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != ';')
    return -21;
  KernelLexGetCharSoft(&cc);
  // Emit ABI frame body (prologue sd a0/a1 + ld locals + epilogue).
  sz = KernelEmitAbiICSoft(kernel_prs_ic, n, nargs, kernel_fun_code + kernel_fun_code_off, KERNEL_SOFT_FUN_CODE - kernel_fun_code_off);
  if (sz < 16)
    return -100;
  if (KernelFunPlantSoft(fname, kernel_fun_code + kernel_fun_code_off) < 0)
    return -16;
  kernel_fun_code_off += sz;
  slot = KernelFunFindSoft(fname);
  if (slot < 0)
    return -65;
  KernelFenceI;
  // Real RISC-V a0/a1 ABI Call — not plant-at-call SoftCall locals.
  if (nargs == 1) {
    fp1 = kernel_soft_funs[slot].code;
    return fp1(argv[0]);
  }
  fp2 = kernel_soft_funs[slot].code;
  return fp2(argv[0], argv[1]);
}
// SoftCall prove: ABI / runtime a0 frame stores past FunCallSoft.
// CocSoft owns COC multi-stmt emit; SoftCall-lite — no full Compiler.BIN Load.
public I64 KernelAbiSoft()
{
  I64 r;
  // Multi-arg/call-Expr plant-at-call must stay green before ABI tip.
  if (KernelFunCallSoft() != 0x4643)
    return -1;
  // Single-arg a0 frame: HolyC fp(40) → a0 → sd → ld → addi.
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a){return a+2;}F(40);");
  if (r != 42)
    return -2;
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a){return a*7;}F(6);");
  if (r != 42)
    return -3;
  // Multi-arg a0/a1 frame.
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a,I64 b){return a+b;}F(40,2);");
  if (r != 42)
    return -4;
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a,I64 b){return a*b;}F(6,7);");
  if (r != 42)
    return -5;
  // Call-site Expr fold into HolyC argv (body still ABI frame).
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a){return a+2;}F(38+2);");
  if (r != 42)
    return -6;
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a,I64 b){return a+b;}F(38+2,6-4);");
  if (r != 42)
    return -7;
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a,I64 b){return a*b;}F((2+4),7);");
  if (r != 42)
    return -8;
  // Body locals (plant) + ABI arg frame.
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a){x=2;return a+x;}F(40);");
  if (r != 42)
    return -9;
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a,I64 b){x=2;return a+b*x;}F(1+1,20);");
  if (r != 42)
    return -10;
  // FunCallSoft tip still green after ABI plants.
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a+b;}F(40,2);", 0);
  if (r != 42)
    return -11;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a){return a+2;}F(38+2);", 1);
  if (r != 42)
    return -12;
  // FunBodySoft tip still green.
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;return x+2;}F();", 0);
  if (r != 42)
    return -13;
  return 0x4142;
  // 'AB'
}
// SoftCall-lite COC: I64 name([I64 arg]*){ (ident=Expr;|if(Expr)ident=Expr;[else ident=Expr;]|while(Expr)ident=Expr;|for(ident=Expr;Expr;ident=Expr)ident=Expr;)* [return] Expr; } name([Expr]*);
// Accumulates ASSIGN+BR+Expr into one IC stream; emit runtime sd/ld/beq (no plant-fold).
I64 KernelPrsFunCocCallSoft(U8 *buf)
{
  CKernelCmpCtrlSoft cc;
  CKernelICSoft arg_ic[KERNEL_PRS_IC_MAX];
  U8 *save_ptr;
  U8 *ap;
  U8 fname[KERNEL_SOFT_IDENT_MAX];
  U8 anames[KERNEL_SOFT_ARG_MAX *KERNEL_SOFT_IDENT_MAX];
  U8 lname[KERNEL_SOFT_IDENT_MAX];
  I64 save_flags, save_last, n, ch, folded, i, sz, slot, nargs, ai, arg_n;
  I64 next_off, frame, next_lb, lb_done, lb_loop, lb_join, is_while, step_n, si;
  I64 argv[KERNEL_SOFT_ARG_MAX];
  I64 (*fp0)();
  I64 (*fp1)(I64);
  I64 (*fp2)(I64, I64);
  if (!buf)
    return -1;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  kernel_soft_fun_n = 0;
  kernel_soft_local_n = 0;
  kernel_fun_code_off = 0;
  nargs = 0;
  if (KernelLexIdentSoft(&cc))
    return -2;
  if (!KernelStrEqSoft(kernel_lex_ident, "I64"))
    return -3;
  if (KernelLexIdentSoft(&cc))
    return -4;
  i = 0;
  while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
    fname[i] = kernel_lex_ident[i];
    i++;
  }
  fname[i] = 0;
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '(')
    return -5;
  KernelLexGetCharSoft(&cc);
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch == ')') {
    KernelLexGetCharSoft(&cc);
  } else {
    while (TRUE) {
      if (nargs >= KERNEL_SOFT_ABI_ARG_MAX)
        return -50;
      if (KernelLexIdentSoft(&cc))
        return -51;
      if (!KernelStrEqSoft(kernel_lex_ident, "I64"))
        return -52;
      if (KernelLexIdentSoft(&cc))
        return -53;
      ap = anames + nargs *KERNEL_SOFT_IDENT_MAX;
      i = 0;
      while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
        ap[i] = kernel_lex_ident[i];
        i++;
      }
      ap[i] = 0;
      if (KernelLocalPlantAbiSoft(ap, nargs * 8) < 0)
        return -54;
      nargs++;
      ch = KernelLexSkipSpaceSoft(&cc);
      if (ch == ',') {
        KernelLexGetCharSoft(&cc);
        continue;
      }
      break;
    }
    if (ch != ')')
      return -6;
    KernelLexGetCharSoft(&cc);
  }
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '{')
    return -7;
  KernelLexGetCharSoft(&cc);
  // COC body: ASSIGN / if / while / for + final Expr into one IC stream (no plant-fold).
  n = 0;
  next_off = nargs * 8;
  next_lb = 0;
  while (TRUE) {
    ch = KernelLexSkipSpaceSoft(&cc);
    if (!ch)
      return -70;
    if (ch == '}')
      return -71;
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_') {
      save_ptr = cc.cur_buf_ptr;
      save_flags = cc.flags;
      save_last = cc.last_U16;
      if (KernelLexIdentSoft(&cc))
        return -8;
      if (KernelStrEqSoft(kernel_lex_ident, "return")) {
        // Fall through to final Expr;
      } else if (KernelStrEqSoft(kernel_lex_ident, "for")) {
        // for(ident=Expr;Expr;ident=Expr)ident=Expr; — init; loop: cond BR; body; step; JMP.
        if (next_lb + 1 >= KERNEL_SOFT_LABEL_MAX)
          return -80;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != '(')
          return -110;
        KernelLexGetCharSoft(&cc);
        // init assign
        if (KernelLexIdentSoft(&cc))
          return -111;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != '=')
          return -112;
        KernelLexGetCharSoft(&cc);
        i = 0;
        while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
          lname[i] = kernel_lex_ident[i];
          i++;
        }
        lname[i] = 0;
        slot = KernelLocalFindSoft(lname);
        if (slot < 0) {
          if (KernelLocalPlantAbiSoft(lname, next_off) < 0)
            return -113;
          next_off += 8;
          slot = KernelLocalFindSoft(lname);
          if (slot < 0)
            return -114;
        }
        if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
          return -115;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != ';')
          return -116;
        KernelLexGetCharSoft(&cc);
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_ASSIGN, slot))
          return -117;
        lb_loop = next_lb++;
        lb_done = next_lb++;
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_loop))
          return -118;
        // cond
        if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
          return -119;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != ';')
          return -120;
        KernelLexGetCharSoft(&cc);
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_BR_ZERO, lb_done))
          return -121;
        // step into arg_ic scratch (append after body; call-site reuse later).
        step_n = 0;
        if (KernelLexIdentSoft(&cc))
          return -122;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != '=')
          return -123;
        KernelLexGetCharSoft(&cc);
        i = 0;
        while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
          lname[i] = kernel_lex_ident[i];
          i++;
        }
        lname[i] = 0;
        slot = KernelLocalFindSoft(lname);
        if (slot < 0) {
          if (KernelLocalPlantAbiSoft(lname, next_off) < 0)
            return -124;
          next_off += 8;
          slot = KernelLocalFindSoft(lname);
          if (slot < 0)
            return -125;
        }
        if (KernelPrsExprSoft(&cc, arg_ic, &step_n, KERNEL_PRS_IC_MAX))
          return -126;
        if (KernelPrsICPushSoft(arg_ic, &step_n, KERNEL_PRS_IC_MAX, KERNEL_IC_ASSIGN, slot))
          return -127;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != ')')
          return -128;
        KernelLexGetCharSoft(&cc);
        // body assign
        if (KernelLexIdentSoft(&cc))
          return -129;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != '=')
          return -130;
        KernelLexGetCharSoft(&cc);
        i = 0;
        while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
          lname[i] = kernel_lex_ident[i];
          i++;
        }
        lname[i] = 0;
        slot = KernelLocalFindSoft(lname);
        if (slot < 0) {
          if (KernelLocalPlantAbiSoft(lname, next_off) < 0)
            return -131;
          next_off += 8;
          slot = KernelLocalFindSoft(lname);
          if (slot < 0)
            return -132;
        }
        if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
          return -133;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != ';')
          return -134;
        KernelLexGetCharSoft(&cc);
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_ASSIGN, slot))
          return -135;
        // append step ICs then JMP back
        si = 0;
        while (si < step_n) {
          if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, arg_ic[si].ic_code, arg_ic[si].ic_data))
            return -136;
          si++;
        }
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_JMP, lb_loop))
          return -137;
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_done))
          return -138;
        continue;
      } else if (KernelStrEqSoft(kernel_lex_ident, "if") || KernelStrEqSoft(kernel_lex_ident, "while")) {
        is_while = KernelStrEqSoft(kernel_lex_ident, "while");
        if (is_while) {
          if (next_lb + 1 >= KERNEL_SOFT_LABEL_MAX)
            return -80;
        } else if (next_lb >= KERNEL_SOFT_LABEL_MAX)
          return -80;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != '(')
          return -81;
        KernelLexGetCharSoft(&cc);
        if (is_while) {
          lb_loop = next_lb++;
          lb_done = next_lb++;
          if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_loop))
            return -82;
        } else {
          lb_done = next_lb++;
        }
        if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
          return -83;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != ')')
          return -84;
        KernelLexGetCharSoft(&cc);
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_BR_ZERO, lb_done))
          return -85;
        // SoftCall-lite BR body: single assign stmt (ident=Expr;).
        if (KernelLexIdentSoft(&cc))
          return -86;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != '=')
          return -87;
        KernelLexGetCharSoft(&cc);
        i = 0;
        while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
          lname[i] = kernel_lex_ident[i];
          i++;
        }
        lname[i] = 0;
        slot = KernelLocalFindSoft(lname);
        if (slot < 0) {
          if (KernelLocalPlantAbiSoft(lname, next_off) < 0)
            return -88;
          next_off += 8;
          slot = KernelLocalFindSoft(lname);
          if (slot < 0)
            return -89;
        }
        if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
          return -90;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch != ';')
          return -91;
        KernelLexGetCharSoft(&cc);
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_ASSIGN, slot))
          return -92;
        if (is_while) {
          if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_JMP, lb_loop))
            return -93;
          if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_done))
            return -94;
          continue;
        }
        // Optional else: JMP join; LABEL else; else-assign; LABEL join.
        save_ptr = cc.cur_buf_ptr;
        save_flags = cc.flags;
        save_last = cc.last_U16;
        ch = KernelLexSkipSpaceSoft(&cc);
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_') {
          if (KernelLexIdentSoft(&cc))
            return -95;
          if (KernelStrEqSoft(kernel_lex_ident, "else")) {
            if (next_lb >= KERNEL_SOFT_LABEL_MAX)
              return -80;
            lb_join = next_lb++;
            if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_JMP, lb_join))
              return -96;
            if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_done))
              return -97;
            if (KernelLexIdentSoft(&cc))
              return -98;
            ch = KernelLexSkipSpaceSoft(&cc);
            if (ch != '=')
              return -99;
            KernelLexGetCharSoft(&cc);
            i = 0;
            while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
              lname[i] = kernel_lex_ident[i];
              i++;
            }
            lname[i] = 0;
            slot = KernelLocalFindSoft(lname);
            if (slot < 0) {
              if (KernelLocalPlantAbiSoft(lname, next_off) < 0)
                return -101;
              next_off += 8;
              slot = KernelLocalFindSoft(lname);
              if (slot < 0)
                return -102;
            }
            if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
              return -103;
            ch = KernelLexSkipSpaceSoft(&cc);
            if (ch != ';')
              return -104;
            KernelLexGetCharSoft(&cc);
            if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_ASSIGN, slot))
              return -105;
            if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_join))
              return -106;
            continue;
          }
        }
        cc.cur_buf_ptr = save_ptr;
        cc.flags = save_flags;
        cc.last_U16 = save_last;
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_done))
          return -94;
        continue;
      } else {
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch == '=') {
          KernelLexGetCharSoft(&cc);
          i = 0;
          while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
            lname[i] = kernel_lex_ident[i];
            i++;
          }
          lname[i] = 0;
          slot = KernelLocalFindSoft(lname);
          if (slot < 0) {
            if (KernelLocalPlantAbiSoft(lname, next_off) < 0)
              return -55;
            next_off += 8;
            slot = KernelLocalFindSoft(lname);
            if (slot < 0)
              return -56;
          }
          if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
            return -57;
          ch = KernelLexSkipSpaceSoft(&cc);
          if (ch != ';')
            return -58;
          KernelLexGetCharSoft(&cc);
          if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_ASSIGN, slot))
            return -59;
          continue;
        }
        cc.cur_buf_ptr = save_ptr;
        cc.flags = save_flags;
        cc.last_U16 = save_last;
      }
    }
    if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
      return -9;
    ch = KernelLexSkipSpaceSoft(&cc);
    if (ch != ';')
      return -10;
    KernelLexGetCharSoft(&cc);
    break;
  }
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '}')
    return -11;
  KernelLexGetCharSoft(&cc);
  // Call site: fold Expr args into HolyC argv — do NOT plant SoftCall locals.
  if (KernelLexIdentSoft(&cc))
    return -17;
  if (!KernelStrEqSoft(kernel_lex_ident, fname))
    return -18;
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != '(')
    return -19;
  KernelLexGetCharSoft(&cc);
  ch = KernelLexSkipSpaceSoft(&cc);
  if (nargs) {
    ai = 0;
    while (TRUE) {
      if (ai >= nargs)
        return -60;
      arg_n = 0;
      if (KernelPrsExprSoft(&cc, arg_ic, &arg_n, KERNEL_PRS_IC_MAX))
        return -61;
      folded = KernelOptPassSoft(arg_ic, arg_n);
      if (folded == 0x8000000000000000)
        return -62;
      argv[ai] = folded;
      ai++;
      ch = KernelLexSkipSpaceSoft(&cc);
      if (ai < nargs) {
        if (ch != ',')
          return -63;
        KernelLexGetCharSoft(&cc);
        continue;
      }
      break;
    }
    if (ai != nargs)
      return -64;
  }
  if (ch != ')')
    return -20;
  KernelLexGetCharSoft(&cc);
  ch = KernelLexSkipSpaceSoft(&cc);
  if (ch != ';')
    return -21;
  KernelLexGetCharSoft(&cc);
  frame = KernelSoftFrameSizeSoft();
  if (frame < 0)
    return -65;
  sz = KernelEmitCocICSoft(kernel_prs_ic, n, nargs, frame, kernel_fun_code + kernel_fun_code_off, KERNEL_SOFT_FUN_CODE - kernel_fun_code_off);
  if (sz < 8)
    return -100;
  if (KernelFunPlantSoft(fname, kernel_fun_code + kernel_fun_code_off) < 0)
    return -16;
  kernel_fun_code_off += sz;
  slot = KernelFunFindSoft(fname);
  if (slot < 0)
    return -66;
  KernelFenceI;
  if (nargs == 0) {
    fp0 = kernel_soft_funs[slot].code;
    return fp0();
  }
  if (nargs == 1) {
    fp1 = kernel_soft_funs[slot].code;
    return fp1(argv[0]);
  }
  fp2 = kernel_soft_funs[slot].code;
  return fp2(argv[0], argv[1]);
}
// SoftCall prove: COC multi-stmt emit (runtime ASSIGN sd) past AbiSoft.
// ElseSoft owns if/else; BrSoft owns if/while BR; SoftCall-lite — no full Compiler.BIN Load.
public I64 KernelCocSoft()
{
  I64 r;
  // ABI a0 frame SoftCall-lite must stay green before COC tip.
  if (KernelAbiSoft() != 0x4142)
    return -1;
  // Zero-arg COC: plant-fold FunBody path would bake x; here x is runtime sd/ld.
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;return x+2;}F();");
  if (r != 42)
    return -2;
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;y=2;return x+y;}F();");
  if (r != 42)
    return -3;
  r = KernelPrsFunCocCallSoft("I64 F(){x=6;return x*7;}F();");
  if (r != 42)
    return -4;
  // RMW assign sequencing SoftCall-lite COC.
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;x=x+2;return x;}F();");
  if (r != 42)
    return -5;
  // ABI arg frame + COC body local stores.
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){x=2;return a+x;}F(40);");
  if (r != 42)
    return -6;
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){x=a+2;return x;}F(40);");
  if (r != 42)
    return -7;
  r = KernelPrsFunCocCallSoft("I64 F(I64 a,I64 b){x=2;return a+b*x;}F(20,11);");
  if (r != 42)
    return -8;
  // Call-site Expr fold into argv; body still COC frame.
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){x=2;return a+x;}F(38+2);");
  if (r != 42)
    return -9;
  // Implicit return after COC assigns.
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;x+2;}F();");
  if (r != 42)
    return -10;
  // AbiSoft tip still green after COC plants.
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a){return a+2;}F(40);");
  if (r != 42)
    return -11;
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a,I64 b){return a+b;}F(38+2,6-4);");
  if (r != 42)
    return -12;
  // FunCallSoft tip still green.
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a+b;}F(40,2);", 0);
  if (r != 42)
    return -13;
  // FunBodySoft tip still green.
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;return x+2;}F();", 0);
  if (r != 42)
    return -14;
  return 0x434F;
  // 'CO'
}
// SoftCall prove: if/while BR emit (runtime taken/not-taken) past CocSoft.
// ElseSoft owns else; SoftCall-lite — no full Compiler.BIN Load.
public I64 KernelBrSoft()
{
  I64 r;
  // COC multi-stmt ASSIGN SoftCall-lite must stay green before BR tip.
  if (KernelCocSoft() != 0x434F)
    return -1;
  // if taken: cond nonzero → assign body runs.
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(1)x=42;return x;}F();");
  if (r != 42)
    return -2;
  // if not-taken: cond zero → skip assign.
  r = KernelPrsFunCocCallSoft("I64 F(){x=42;if(0)x=0;return x;}F();");
  if (r != 42)
    return -3;
  // if + ABI arg cond (runtime a0; not plant-fold).
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){x=0;if(a)x=42;return x;}F(1);");
  if (r != 42)
    return -4;
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){x=42;if(a)x=0;return x;}F(0);");
  if (r != 42)
    return -5;
  // while: count up until x-42==0 (BR_ZERO exit + JMP back).
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;while(x-42)x=x+1;return x;}F();");
  if (r != 42)
    return -6;
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;while(x-6)x=x+1;return x*7;}F();");
  if (r != 42)
    return -7;
  // while already-done (cond zero first check — not-taken body).
  r = KernelPrsFunCocCallSoft("I64 F(){x=42;while(x-42)x=0;return x;}F();");
  if (r != 42)
    return -8;
  // CocSoft tip still green after BR plants.
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;return x+2;}F();");
  if (r != 42)
    return -9;
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;x=x+2;return x;}F();");
  if (r != 42)
    return -10;
  // AbiSoft / FunCallSoft / FunBodySoft stay green.
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a){return a+2;}F(40);");
  if (r != 42)
    return -11;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a+b;}F(40,2);", 0);
  if (r != 42)
    return -12;
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;return x+2;}F();", 0);
  if (r != 42)
    return -13;
  return 0x4252;
  // 'BR'
}
// SoftCall prove: if/else emit (runtime then vs else) past BrSoft.
// SoftCall-lite — ForSoft owns for; no full Compiler.BIN Load.
public I64 KernelElseSoft()
{
  I64 r;
  // if/while BR SoftCall-lite must stay green before else tip.
  if (KernelBrSoft() != 0x4252)
    return -1;
  // else not-taken: cond nonzero → then assign; skip else.
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(1)x=42;else x=0;return x;}F();");
  if (r != 42)
    return -2;
  // else taken: cond zero → skip then; else assign.
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(0)x=0;else x=42;return x;}F();");
  if (r != 42)
    return -3;
  // if/else + ABI arg cond (runtime a0; not plant-fold).
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){x=0;if(a)x=40;else x=41;return x+2;}F(1);");
  if (r != 42)
    return -4;
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){x=0;if(a)x=40;else x=41;return x+1;}F(0);");
  if (r != 42)
    return -5;
  // Different locals in then vs else.
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;y=0;if(1)x=42;else y=7;return x+y;}F();");
  if (r != 42)
    return -6;
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;y=0;if(0)x=7;else y=42;return x+y;}F();");
  if (r != 42)
    return -7;
  // Plain if (no else) still green after else plants.
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(1)x=42;return x;}F();");
  if (r != 42)
    return -8;
  // while still green.
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;while(x-42)x=x+1;return x;}F();");
  if (r != 42)
    return -9;
  // CocSoft / AbiSoft / FunCallSoft / FunBodySoft stay green.
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;x=x+2;return x;}F();");
  if (r != 42)
    return -10;
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a){return a+2;}F(40);");
  if (r != 42)
    return -11;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a+b;}F(40,2);", 0);
  if (r != 42)
    return -12;
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;return x+2;}F();", 0);
  if (r != 42)
    return -13;
  return 0x454C;
  // 'EL'
}
// SoftCall prove: for emit (runtime init/cond/step loop) past ElseSoft.
// SoftCall-lite — CmpBrSoft owns relational cmp-BR; no full Compiler.BIN Load.
public I64 KernelForSoft()
{
  I64 r;
  // if/else SoftCall-lite must stay green before for tip.
  if (KernelElseSoft() != 0x454C)
    return -1;
  // for: count up until x-42==0 (init + BR_ZERO exit + step + JMP back).
  r = KernelPrsFunCocCallSoft("I64 F(){for(x=40;x-42;x=x+1)y=0;return x;}F();");
  if (r != 42)
    return -2;
  r = KernelPrsFunCocCallSoft("I64 F(){for(x=0;x-6;x=x+1)y=0;return x*7;}F();");
  if (r != 42)
    return -3;
  // for already-done (cond zero first check — not-taken body/step).
  r = KernelPrsFunCocCallSoft("I64 F(){for(x=42;x-42;x=x+1)y=0;return x;}F();");
  if (r != 42)
    return -4;
  // for + ABI arg init (runtime a0; not plant-fold).
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){for(x=a;x-42;x=x+1)y=0;return x;}F(40);");
  if (r != 42)
    return -5;
  // Body local accumulates while step advances.
  r = KernelPrsFunCocCallSoft("I64 F(){y=0;for(x=0;x-6;x=x+1)y=y+7;return y;}F();");
  if (r != 42)
    return -6;
  // ElseSoft tip still green after for plants.
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(0)x=0;else x=42;return x;}F();");
  if (r != 42)
    return -7;
  // while / if still green.
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;while(x-42)x=x+1;return x;}F();");
  if (r != 42)
    return -8;
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(1)x=42;return x;}F();");
  if (r != 42)
    return -9;
  // CocSoft / AbiSoft / FunCallSoft / FunBodySoft stay green.
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;x=x+2;return x;}F();");
  if (r != 42)
    return -10;
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a){return a+2;}F(40);");
  if (r != 42)
    return -11;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a+b;}F(40,2);", 0);
  if (r != 42)
    return -12;
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;return x+2;}F();", 0);
  if (r != 42)
    return -13;
  return 0x4652;
  // 'FR'
}
// SoftCall prove: relational cmp → BR (runtime taken/not-taken) past ForSoft.
// SoftCall-lite — CmpSrcSoft owns multi-fun slice Load past cmp-BR; PrsSrcSoft owns
// larger Prs SoftCall Load; no full Compiler.BIN Load.
public I64 KernelCmpBrSoft()
{
  I64 r;
  // for SoftCall-lite must stay green before cmp-BR tip.
  if (KernelForSoft() != 0x4652)
    return -1;
  // < taken / not-taken (runtime local; not plant-fold).
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(x<1)x=42;return x;}F();");
  if (r != 42)
    return -2;
  r = KernelPrsFunCocCallSoft("I64 F(){x=42;if(x<1)x=0;return x;}F();");
  if (r != 42)
    return -3;
  // < + ABI arg (runtime a0).
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){x=0;if(a<2)x=42;return x;}F(1);");
  if (r != 42)
    return -4;
  r = KernelPrsFunCocCallSoft("I64 F(I64 a){x=42;if(a<2)x=0;return x;}F(2);");
  if (r != 42)
    return -5;
  // > / <= / >= / == / !=
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(x>0)x=0;else x=42;return x;}F();");
  if (r != 42)
    return -6;
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(x<=0)x=42;return x;}F();");
  if (r != 42)
    return -7;
  r = KernelPrsFunCocCallSoft("I64 F(){x=1;if(x>=1)x=42;return x;}F();");
  if (r != 42)
    return -8;
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(x==0)x=42;return x;}F();");
  if (r != 42)
    return -9;
  r = KernelPrsFunCocCallSoft("I64 F(){x=1;if(x!=0)x=42;return x;}F();");
  if (r != 42)
    return -10;
  // while / for with relational cond (not truthy x-N).
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;while(x<6)x=x+1;return x*7;}F();");
  if (r != 42)
    return -11;
  r = KernelPrsFunCocCallSoft("I64 F(){for(x=0;x<6;x=x+1)y=0;return x*7;}F();");
  if (r != 42)
    return -12;
  // ForSoft tip still green after cmp-BR plants.
  r = KernelPrsFunCocCallSoft("I64 F(){for(x=40;x-42;x=x+1)y=0;return x;}F();");
  if (r != 42)
    return -13;
  // ElseSoft / while / if still green.
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(0)x=0;else x=42;return x;}F();");
  if (r != 42)
    return -14;
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;while(x-42)x=x+1;return x;}F();");
  if (r != 42)
    return -15;
  r = KernelPrsFunCocCallSoft("I64 F(){x=0;if(1)x=42;return x;}F();");
  if (r != 42)
    return -16;
  // CocSoft / AbiSoft / FunCallSoft / FunBodySoft stay green.
  r = KernelPrsFunCocCallSoft("I64 F(){x=40;x=x+2;return x;}F();");
  if (r != 42)
    return -17;
  r = KernelPrsFunAbiCallSoft("I64 F(I64 a){return a+2;}F(40);");
  if (r != 42)
    return -18;
  r = KernelPrsFunDefCallSoft("I64 F(I64 a,I64 b){return a+b;}F(40,2);", 0);
  if (r != 42)
    return -19;
  r = KernelPrsFunDefCallSoft("I64 F(){x=40;return x+2;}F();", 0);
  if (r != 42)
    return -20;
  return 0x4342;
  // 'CB'
}
// SoftCall prove: host-AOT multi-fun compound slice Load past CmpBrSoft.
// SoftCall Load SoftCmpSrc.BIN (≤2KiB) — SoftCall-lite PrsCmpSrc hung ExePutSSoft.
public I64 KernelCmpSrcSoft()
{
  I64 r;
  if (KernelCmpBrSoft() != 0x4342)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftCmpSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftCmpSrc.BIN", "SoftCmpSrcProbe");
  if (r != 42)
    return -3;
  return 0x4353;
  // 'CS'
}
// SoftCall prove: host-AOT Prs-shaped glbl+multi-fun fold Load past CmpSrcSoft.
// SoftCall Load SoftPrsSrc.BIN (≤2KiB) — Lex digit SoftCall Load over 2KiB cap.
public I64 KernelPrsSrcSoft()
{
  I64 r;
  if (KernelCmpSrcSoft() != 0x4353)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftPrsSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftPrsSrc.BIN", "SoftPrsSrcProbe");
  if (r != 42)
    return -3;
  return 0x5052;
  // 'PR'
}
// SoftCall prove: host-AOT LexStmt2Bin-shaped digit+op peel Load past PrsSrcSoft.
// SoftCall Load SoftLexSrc.BIN (≤2KiB) — while digit SoftCall Load over 2KiB cap.
public I64 KernelLexSrcSoft()
{
  I64 r;
  if (KernelPrsSrcSoft() != 0x5052)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftLexSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftLexSrc.BIN", "SoftLexSrcProbe");
  if (r != 42)
    return -3;
  return 0x4C58;
  // 'LX'
}
// SoftCall prove: host-AOT IC plant+emit beyond Lex peel Load past LexSrcSoft.
// SoftCall Load SoftIcSrc.BIN (≤2KiB) — host AOT <<20 bit-pack SoftCall Load over cap.
public I64 KernelIcSrcSoft()
{
  I64 r;
  if (KernelLexSrcSoft() != 0x4C58)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftIcSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftIcSrc.BIN", "SoftIcSrcProbe");
  if (r != 42)
    return -3;
  return 0x4943;
  // 'IC'
}
// SoftCall prove: host-AOT MUL IC plant+emit beyond IMM/ADD SoftIcSrc.
// SoftCall Load SoftMulSrc.BIN (≤2KiB) — MUL+SUB SoftCall Load over cap; SUB own Load.
public I64 KernelMulSrcSoft()
{
  I64 r;
  if (KernelIcSrcSoft() != 0x4943)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftMulSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftMulSrc.BIN", "SoftMulSrcProbe");
  if (r != 42)
    return -3;
  return 0x4D55;
  // 'MU'
}
// SoftCall prove: host-AOT SUB IC plant+emit beyond IMM/MUL SoftMulSrc.
// SoftCall Load SoftSubSrc.BIN (≤2KiB) — MUL+SUB one BIN SoftCall Load over cap.
public I64 KernelSubSrcSoft()
{
  I64 r;
  if (KernelMulSrcSoft() != 0x4D55)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftSubSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftSubSrc.BIN", "SoftSubSrcProbe");
  if (r != 42)
    return -3;
  return 0x5342;
  // 'SB'
}
// SoftCall prove: host-AOT OptPass fold beyond IMM/SUB SoftSubSrc.
// SoftCall Load SoftOptSrc.BIN (≤2KiB) — fold IMM*IMM→IMM42 emit (not mul emit).
public I64 KernelOptSrcSoft()
{
  I64 r;
  if (KernelSubSrcSoft() != 0x5342)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftOptSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftOptSrc.BIN", "SoftOptSrcProbe");
  if (r != 42)
    return -3;
  return 0x4F50;
  // 'OP'
}
// SoftCall prove: host-AOT COC multi-stmt ASSIGN beyond OptPass fold SoftOptSrc.
// SoftCall Load SoftCocSrc.BIN (≤2KiB) — ASSIGN/LOCAL/ADD → frame sd/ld (not fold).
public I64 KernelCocSrcSoft()
{
  I64 r;
  if (KernelOptSrcSoft() != 0x4F50)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftCocSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftCocSrc.BIN", "SoftCocSrcProbe");
  if (r != 42)
    return -3;
  return 0x4F43;
  // 'OC'
}
// SoftCall prove: host-AOT BR SoftCall Load beyond COC ASSIGN SoftCocSrc.
// SoftCall Load SoftBrSrc.BIN (≤2KiB) — IMM/BR_ZERO → beqz taken path (not sd/ld).
// Needle 'BS' — SoftCall-lite BrSoft already owns 'BR'.
public I64 KernelBrSrcSoft()
{
  I64 r;
  if (KernelCocSrcSoft() != 0x4F43)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftBrSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftBrSrc.BIN", "SoftBrSrcProbe");
  if (r != 42)
    return -3;
  return 0x4253;
  // 'BS'
}
// SoftCall prove: host-AOT if/else JMP join SoftCall Load beyond BR SoftBrSrc.
// SoftCall Load SoftElseSrc.BIN (≤2KiB) — IMM/BR_ZERO/JMP → SoftCall-lite else-taken.
// Needle 'ES' — SoftCall-lite ElseSoft already owns 'EL'.
public I64 KernelElseSrcSoft()
{
  I64 r;
  if (KernelBrSrcSoft() != 0x4253)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftElseSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftElseSrc.BIN", "SoftElseSrcProbe");
  if (r != 42)
    return -3;
  return 0x4553;
  // 'ES'
}
// SoftCall prove: host-AOT for-loop SoftCall Load beyond if/else SoftElseSrc.
// SoftCall Load SoftForSrc.BIN (≤2KiB) — IMM/COND/BR_ZERO/STEP/JMP-back slots →
// runtime count 40→42 (not plant-fold). Needle 'FS' — SoftCall-lite ForSoft owns 'FR'.
public I64 KernelForSrcSoft()
{
  I64 r;
  if (KernelElseSrcSoft() != 0x4553)
    return -1;
  KernelArenaReset;
  if (!KernelFileFind("A:/MakeOS/SoftForSrc.BIN"))
    return -2;
  r = KernelLoadCall("A:/MakeOS/SoftForSrc.BIN", "SoftForSrcProbe");
  if (r != 42)
    return -3;
  return 0x4653;
  // 'FS'
}
// SoftCall-lite PrsFun chain: (I64 name(){return Expr;})+ name();
// Every def is planted before the next is parsed, so a later body can name an
// earlier one and get a real RV jal ra (IC_CALL) instead of a plant-time fold.
// Defs start at 'I' ("I64"); the trailing call must not (G/F here).
I64 KernelPrsCallFunDefSoft(U8 *buf)
{
  CKernelCmpCtrlSoft cc;
  U8 fname[KERNEL_SOFT_IDENT_MAX];
  I64 n, ch, i, sz, slot;
  I64 (*fp)();
  if (!buf)
    return -1;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  kernel_soft_fun_n = 0;
  kernel_soft_local_n = 0;
  kernel_fun_code_off = 0;
  while (TRUE) {
    ch = KernelLexSkipSpaceSoft(&cc);
    if (ch != 'I')
      break;
    if (KernelLexIdentSoft(&cc))
      return -2;
    if (!KernelStrEqSoft(kernel_lex_ident, "I64"))
      return -3;
    if (KernelLexIdentSoft(&cc))
      return -4;
    i = 0;
    while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
      fname[i] = kernel_lex_ident[i];
      i++;
    }
    fname[i] = 0;
    if (KernelLexSkipSpaceSoft(&cc) != '(')
      return -5;
    KernelLexGetCharSoft(&cc);
    if (KernelLexSkipSpaceSoft(&cc) != ')')
      return -6;
    KernelLexGetCharSoft(&cc);
    if (KernelLexSkipSpaceSoft(&cc) != '{')
      return -7;
    KernelLexGetCharSoft(&cc);
    if (KernelLexIdentSoft(&cc))
      return -8;
    if (!KernelStrEqSoft(kernel_lex_ident, "return"))
      return -9;
    n = 0;
    if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
      return -10;
    if (KernelLexSkipSpaceSoft(&cc) != ';')
      return -11;
    KernelLexGetCharSoft(&cc);
    if (KernelLexSkipSpaceSoft(&cc) != '}')
      return -12;
    KernelLexGetCharSoft(&cc);
    sz = KernelEmitCallICSoft(kernel_prs_ic, n, kernel_fun_code + kernel_fun_code_off, KERNEL_SOFT_FUN_CODE - kernel_fun_code_off);
    if (sz < 8)
      return -13;
    if (KernelFunPlantSoft(fname, kernel_fun_code + kernel_fun_code_off) < 0)
      return -14;
    kernel_fun_code_off += sz;
    KernelFenceI;
  }
  if (KernelLexIdentSoft(&cc))
    return -15;
  slot = KernelFunFindSoft(kernel_lex_ident);
  if (slot < 0)
    return -16;
  if (KernelLexSkipSpaceSoft(&cc) != '(')
    return -17;
  KernelLexGetCharSoft(&cc);
  if (KernelLexSkipSpaceSoft(&cc) != ')')
    return -18;
  KernelLexGetCharSoft(&cc);
  if (KernelLexSkipSpaceSoft(&cc) != ';')
    return -19;
  KernelLexGetCharSoft(&cc);
  KernelFenceI;
  fp = kernel_soft_funs[slot].code;
  return fp();
}
// SoftCall prove: SoftCall-lite inter-fun CALL IC past ForSrcSoft Load 'FS'.
// The caller body emits a real RV jal ra to a separately planted callee under a
// ra frame — not a plant-time fold of the callee's value.
public I64 KernelCallIcSoft()
{
  I64 r;
  if (KernelForSrcSoft() != 0x4653)
    return -1;
  r = KernelPrsCallFunDefSoft("I64 G(){return 40;}I64 F(){return G()+2;}F();");
  if (r != 42)
    return -2;
  r = KernelPrsCallFunDefSoft("I64 G(){return 6;}I64 F(){return G()*7;}F();");
  if (r != 42)
    return -3;
  r = KernelPrsCallFunDefSoft("I64 G(){return 44;}I64 F(){return G()-2;}F();");
  if (r != 42)
    return -4;
  // Single def + call stays green — IC_CALL is additive to the lite Prs tip.
  r = KernelPrsCallFunDefSoft("I64 F(){return 40+2;}F();");
  if (r != 42)
    return -5;
  return 0x434C;
  // 'CL'
}
// SoftCall-lite glbl-body assign: `ident = Expr <term>` or `*Factor = Expr <term>`,
// where ident is a declared frame local or a file-scope glbl. Shared by the plain
// statement path and by every control-flow init / step / body, so an `if` body stores
// through exactly the same IC_ASSIGN / IC_GLBL_ASSIGN / IC_STORE_U8 a top-level
// statement does — nothing branch-specific.
// Error codes match the inline path this replaced (-10 undeclared, -26 shadow).
I64 KernelPrsGlblAsgSoft(CKernelCmpCtrlSoft *cc, CKernelICSoft *ic, I64 *n, I64 term)
{
  I64 slot, is_glbl;
  // `*p = Expr;` — the address factor is pushed first, then the value, then sb.
  if (KernelLexSkipSpaceSoft(cc) == '*') {
    KernelLexGetCharSoft(cc);
    if (KernelPrsFactorSoft(cc, ic, n, KERNEL_PRS_IC_MAX))
      return -34;
    if (KernelLexSkipSpaceSoft(cc) != '=')
      return -11;
    KernelLexGetCharSoft(cc);
    if (KernelPrsExprSoft(cc, ic, n, KERNEL_PRS_IC_MAX))
      return -12;
    if (KernelLexSkipSpaceSoft(cc) != term)
      return -13;
    KernelLexGetCharSoft(cc);
    if (KernelPrsICPushSoft(ic, n, KERNEL_PRS_IC_MAX, KERNEL_IC_STORE_U8, 0))
      return -35;
    return 0;
  }
  if (KernelLexIdentSoft(cc))
    return -33;
  slot = KernelLocalFindSoft(kernel_lex_ident);
  is_glbl = 0;
  if (slot < 0) {
    slot = KernelGlblFindSoft(kernel_lex_ident);
    if (slot < 0)
      return -10;
    // An array name is an address, not a cell — there is nothing to sd into.
    if (KernelGlblKindSoft(slot) == KERNEL_GLBL_KIND_ARR)
      return -36;
    is_glbl = 1;
  }
  if (KernelLexSkipSpaceSoft(cc) != '=')
    return -11;
  KernelLexGetCharSoft(cc);
  if (KernelPrsExprSoft(cc, ic, n, KERNEL_PRS_IC_MAX))
    return -12;
  if (KernelLexSkipSpaceSoft(cc) != term)
    return -13;
  KernelLexGetCharSoft(cc);
  if (is_glbl) {
    if (KernelPrsICPushSoft(ic, n, KERNEL_PRS_IC_MAX, KERNEL_IC_GLBL_ASSIGN, slot))
      return -14;
    return 0;
  }
  if (KernelPrsICPushSoft(ic, n, KERNEL_PRS_IC_MAX, KERNEL_IC_ASSIGN, slot))
    return -30;
  return 0;
}
// Highest IC / label / frame-local watermark any one body reached — the board prints
// measured headroom against KERNEL_PRS_IC_MAX / KERNEL_SOFT_LABEL_MAX /
// KERNEL_SOFT_LOCAL_MAX instead of assuming it. The local count is the tightest thing
// arity 4 touches: four args plus the body's own working locals share one table.
I64 kernel_soft_ic_hi;
I64 kernel_soft_lb_hi;
I64 kernel_soft_lc_hi;
// SoftCall-lite glbl+fun chain:
//   (I64 g; | U8 *p; | U8 b[N];)* (RType name(Params){ Body })+ name();
//   RType  = I64 | U0 | Bool | U32 | U8 * | C8 *
//   Params = <empty> | AType a [, AType b [, AType c [, AType d]]]
//   AType  = I64 | Bool | U32 | U8 * | C8 *
//   Body   = Stmt* return Expr;         (I64 / Bool / U32 / pointer)
//          | Stmt* [return;]            (U0 — a value would be a type error)
//   Stmt = I64 l[,l]*; | Asg; | U0Name(Args); | if(Expr)Asg;[else Asg;]
//        | while(Expr)Asg; | for(Asg;Expr;Asg)Asg;
//   Asg  = (l|g|p) = Expr | *Factor = Expr
// Declared args are real RISC-V a0..a3 arguments: the caller's RPN walk leaves arg 1
// in a0 .. arg 4 in a3, the jal passes them, and the callee prologue spills them to
// its own frame at 8(sp) .. 32(sp) — from there they are ordinary IC_LOCAL slots.
// A Bool / U32 arg is narrowed before its spill, and a Bool / U32 return is narrowed
// after the body, so widths are the callee's business at both ends and no call site
// has to know them. U0 is the one type with no value: it may not appear in an Expr,
// so `U0Name(Args);` is a statement form, and IC_CALL_U0 puts the lite RPN stack back
// to empty where IC_CALL leaves it at depth 1.
// The entry `name();` still takes none, because HolyC calls it as fp(), and may not
// be U0, because HolyC reads its a0.
// Glbl decls plant real Kernel.BIN storage; bodies reach it by absolute address
// (lui/addi [+slli/srli] then ld/sd), so a store in one fun outlives the frame and
// is seen by a later fun's load. OptPass refuses IC_GLBL, so no plant-time fold.
// Body-scope `I64 l;` decls take the COC statement path instead: each is a real sp
// slot (IC_ASSIGN sd / IC_LOCAL ld) starting at 8, above the ra the frame saves, so
// a callee's same-named local sits on its own frame and cannot clobber the caller's.
// Locals reset per body, so the frame KernelSoftFrameSizeSoft returns is per fun.
// if / while / for reuse the IC_BR_ZERO / IC_JMP / IC_LABEL machinery the COC path
// proved: labels are body-scoped (KernelEmitICBodySoft resolves them per emit), so
// the merged body's budget is KERNEL_SOFT_LABEL_MAX per fun, not per file.
I64 KernelPrsGlblFunDefSoft(U8 *buf)
{
  CKernelCmpCtrlSoft cc;
  CKernelICSoft step_ic[KERNEL_PRS_IC_MAX];
  U8 *save_ptr;
  U8 fname[KERNEL_SOFT_IDENT_MAX];
  I64 save_flags, save_last, n, ch, i, sz, slot, next_off, frame, r;
  I64 next_lb, lb_loop, lb_done, lb_join, is_while, step_n, si, nargs;
  I64 tkind, is_ptr, akind, argt, rtype, saw_ret;
  I64 (*fp)();
  if (!buf)
    return -1;
  KernelMemSet(&cc(U8 *), 0, sizeof(CKernelCmpCtrlSoft));
  cc.cur_buf_ptr = buf;
  kernel_soft_fun_n = 0;
  kernel_soft_local_n = 0;
  kernel_soft_glbl_n = 0;
  kernel_fun_code_off = 0;
  kernel_soft_ic_hi = 0;
  kernel_soft_lb_hi = 0;
  kernel_soft_lc_hi = 0;
  while (TRUE) {
    save_ptr = cc.cur_buf_ptr;
    save_flags = cc.flags;
    save_last = cc.last_U16;
    ch = KernelLexSkipSpaceSoft(&cc);
    if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'))
      break;
    if (KernelLexIdentSoft(&cc))
      return -2;
    // Every file-scope item starts with a type keyword. Anything else is the trailing
    // `name();` entry call — rewind and let the entry path have it. This replaces the
    // old 'I'/'U' first-letter test, which could not tell `U0 F()` from a `Uxxx();`
    // entry, and which rejected an entry whose name began with 'I'.
    tkind = KernelTypeNameSoft(kernel_lex_ident);
    if (tkind < 0) {
      cc.cur_buf_ptr = save_ptr;
      cc.flags = save_flags;
      cc.last_U16 = save_last;
      break;
    }
    is_ptr = 0;
    if (KernelLexSkipSpaceSoft(&cc) == '*') {
      KernelLexGetCharSoft(&cc);
      is_ptr = 1;
      tkind = KERNEL_SOFT_TYPE_PTR;
    }
    if (KernelLexIdentSoft(&cc))
      return -4;
    i = 0;
    while (kernel_lex_ident[i] && i < KERNEL_SOFT_IDENT_MAX - 1) {
      fname[i] = kernel_lex_ident[i];
      i++;
    }
    fname[i] = 0;
    ch = KernelLexSkipSpaceSoft(&cc);
    if (ch == '[') {
      // `U8 b[N];` — a byte buffer whose name decays to its address.
      if (tkind != KERNEL_SOFT_TYPE_U8)
        return -64;
      KernelLexGetCharSoft(&cc);
      if (KernelLexI64Soft(&cc))
        return -65;
      i = cc.cur_i64;
      if (KernelLexSkipSpaceSoft(&cc) != ']')
        return -66;
      KernelLexGetCharSoft(&cc);
      if (KernelLexSkipSpaceSoft(&cc) != ';')
        return -67;
      KernelLexGetCharSoft(&cc);
      if (KernelGlblPlantTypedSoft(fname, KERNEL_GLBL_KIND_ARR, i) < 0)
        return -68;
      continue;
    }
    if (ch == ';') {
      // File-scope storage → zeroed BIN cell (an address, not a plant value). Only
      // the two widths the emitter can reach are declarable: an 8-byte I64 cell and
      // an 8-byte pointer cell. A `U32 g;` would need a 4-byte ld/sd nobody emits.
      KernelLexGetCharSoft(&cc);
      if (is_ptr) {
        if (KernelGlblPlantTypedSoft(fname, KERNEL_GLBL_KIND_PTR, 0) < 0)
          return -61;
        continue;
      }
      if (tkind != KERNEL_SOFT_TYPE_I64)
        return -80;
      if (KernelGlblPlantSoft(fname) < 0)
        return -5;
      continue;
    }
    if (ch != '(')
      return -6;
    // A bare `U8 name(...)` return is a 1-byte value the emitter has no narrowing
    // for; only the pointer form of that base type is accepted.
    if (tkind == KERNEL_SOFT_TYPE_U8)
      return -86;
    rtype = tkind;
    KernelLexGetCharSoft(&cc);
    // Locals are per body: slot 0 of one fun must not be slot 0 of the next.
    // Declared args are planted first, so they take the lowest frame slots and a
    // body reference to one is an ordinary IC_LOCAL.
    kernel_soft_local_n = 0;
    next_off = 8;
    nargs = 0;
    argt = 0;
    if (KernelLexSkipSpaceSoft(&cc) == ')')
      KernelLexGetCharSoft(&cc);
    else {
      while (TRUE) {
        // a0..a3 only: a fifth arg would need a4 and a wider spill prologue.
        if (nargs >= KERNEL_SOFT_ARG_MAX)
          return -72;
        if (KernelLexIdentSoft(&cc))
          return -73;
        akind = KernelTypeNameSoft(kernel_lex_ident);
        if (akind < 0)
          return -74;
        if (KernelLexSkipSpaceSoft(&cc) == '*') {
          KernelLexGetCharSoft(&cc);
          akind = KERNEL_SOFT_TYPE_PTR;
        } else if (akind == KERNEL_SOFT_TYPE_U8)
          return -74;
        // A U0 arg is not a value at all.
        if (akind == KERNEL_SOFT_TYPE_U0)
          return -74;
        argt = argt | (akind << (nargs * 4));
        if (KernelLexIdentSoft(&cc))
          return -75;
        // An arg may not shadow a glbl, same rule a body decl follows.
        if (KernelGlblFindSoft(kernel_lex_ident) >= 0)
          return -76;
        if (KernelLocalFindSoft(kernel_lex_ident) >= 0)
          return -77;
        if (KernelLocalPlantAbiSoft(kernel_lex_ident, next_off) < 0)
          return -78;
        next_off += 8;
        nargs++;
        ch = KernelLexSkipSpaceSoft(&cc);
        if (ch == ',') {
          KernelLexGetCharSoft(&cc);
          continue;
        }
        break;
      }
      if (ch != ')')
        return -7;
      KernelLexGetCharSoft(&cc);
    }
    if (KernelLexSkipSpaceSoft(&cc) != '{')
      return -8;
    KernelLexGetCharSoft(&cc);
    n = 0;
    // Labels are per body too — KernelEmitICBodySoft resolves each fun on its own.
    next_lb = 0;
    saw_ret = 0;
    // Stmt* then `return Expr;` — or, for a U0 fun, `return;` or nothing at all.
    while (TRUE) {
      // Rewind point: the plain-assign path re-lexes its target through the helper.
      save_ptr = cc.cur_buf_ptr;
      save_flags = cc.flags;
      save_last = cc.last_U16;
      ch = KernelLexSkipSpaceSoft(&cc);
      // A U0 body may simply run out of statements: `U0 F(){g=42;}` is stock shape.
      if (ch == '}')
        break;
      // `*p = Expr;` starts with no ident at all — hand it straight to the assign
      // helper, the same one every branch body uses.
      if (ch == '*') {
        r = KernelPrsGlblAsgSoft(&cc, kernel_prs_ic, &n, ';');
        if (r)
          return r;
        continue;
      }
      if (KernelLexIdentSoft(&cc))
        return -9;
      if (KernelStrEqSoft(kernel_lex_ident, "return")) {
        saw_ret = 1;
        break;
      }
      if (KernelStrEqSoft(kernel_lex_ident, "for")) {
        // for(Asg;Expr;Asg)Asg; — init; LOOP: cond BR done; body; step; JMP LOOP; DONE:
        if (next_lb + 1 >= KERNEL_SOFT_LABEL_MAX)
          return -40;
        if (KernelLexSkipSpaceSoft(&cc) != '(')
          return -41;
        KernelLexGetCharSoft(&cc);
        r = KernelPrsGlblAsgSoft(&cc, kernel_prs_ic, &n, ';');
        if (r)
          return r;
        lb_loop = next_lb++;
        lb_done = next_lb++;
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_loop))
          return -42;
        if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
          return -43;
        if (KernelLexSkipSpaceSoft(&cc) != ';')
          return -44;
        KernelLexGetCharSoft(&cc);
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_BR_ZERO, lb_done))
          return -45;
        // The step parses here but runs after the body, so it lands in scratch first.
        step_n = 0;
        r = KernelPrsGlblAsgSoft(&cc, step_ic, &step_n, ')');
        if (r)
          return r;
        r = KernelPrsGlblAsgSoft(&cc, kernel_prs_ic, &n, ';');
        if (r)
          return r;
        si = 0;
        while (si < step_n) {
          if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, step_ic[si].ic_code, step_ic[si].ic_data))
            return -46;
          si++;
        }
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_JMP, lb_loop))
          return -47;
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_done))
          return -48;
        continue;
      }
      if (KernelStrEqSoft(kernel_lex_ident, "if") || KernelStrEqSoft(kernel_lex_ident, "while")) {
        is_while = KernelStrEqSoft(kernel_lex_ident, "while");
        if (is_while) {
          if (next_lb + 1 >= KERNEL_SOFT_LABEL_MAX)
            return -40;
        } else if (next_lb >= KERNEL_SOFT_LABEL_MAX)
          return -40;
        if (KernelLexSkipSpaceSoft(&cc) != '(')
          return -49;
        KernelLexGetCharSoft(&cc);
        if (is_while) {
          lb_loop = next_lb++;
          lb_done = next_lb++;
          if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_loop))
            return -50;
        } else
          lb_done = next_lb++;
        if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
          return -51;
        if (KernelLexSkipSpaceSoft(&cc) != ')')
          return -52;
        KernelLexGetCharSoft(&cc);
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_BR_ZERO, lb_done))
          return -53;
        r = KernelPrsGlblAsgSoft(&cc, kernel_prs_ic, &n, ';');
        if (r)
          return r;
        if (is_while) {
          if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_JMP, lb_loop))
            return -54;
          if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_done))
            return -55;
          continue;
        }
        // Optional else: JMP join; LABEL else; else Asg; LABEL join.
        save_ptr = cc.cur_buf_ptr;
        save_flags = cc.flags;
        save_last = cc.last_U16;
        ch = KernelLexSkipSpaceSoft(&cc);
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_') {
          if (KernelLexIdentSoft(&cc))
            return -56;
          if (KernelStrEqSoft(kernel_lex_ident, "else")) {
            if (next_lb >= KERNEL_SOFT_LABEL_MAX)
              return -40;
            lb_join = next_lb++;
            if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_JMP, lb_join))
              return -57;
            if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_done))
              return -58;
            r = KernelPrsGlblAsgSoft(&cc, kernel_prs_ic, &n, ';');
            if (r)
              return r;
            if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_join))
              return -59;
            continue;
          }
        }
        cc.cur_buf_ptr = save_ptr;
        cc.flags = save_flags;
        cc.last_U16 = save_last;
        if (KernelPrsICPushSoft(kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, KERNEL_IC_LABEL, lb_done))
          return -55;
        continue;
      }
      if (KernelStrEqSoft(kernel_lex_ident, "I64")) {
        while (TRUE) {
          if (KernelLexIdentSoft(&cc))
            return -25;
          // A body decl may not shadow a glbl: the abs-address path would go dark.
          if (KernelGlblFindSoft(kernel_lex_ident) >= 0)
            return -26;
          if (KernelLocalFindSoft(kernel_lex_ident) >= 0)
            return -27;
          if (KernelLocalPlantAbiSoft(kernel_lex_ident, next_off) < 0)
            return -28;
          next_off += 8;
          ch = KernelLexSkipSpaceSoft(&cc);
          if (ch == ',') {
            KernelLexGetCharSoft(&cc);
            continue;
          }
          break;
        }
        if (ch != ';')
          return -29;
        KernelLexGetCharSoft(&cc);
        continue;
      }
      // `name(...);` as a statement — the only way to reach a U0 fun, since it has no
      // value to appear in an Expr. Same jal ra, same arity check; the one difference
      // is that IC_CALL_U0 leaves the lite RPN stack empty.
      slot = KernelFunFindSoft(kernel_lex_ident);
      if (slot >= 0 && KernelLexSkipSpaceSoft(&cc) == '(') {
        if (KernelFunRTypeSoft(slot) != KERNEL_SOFT_TYPE_U0)
          return -83;
        r = KernelPrsCallTailSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX, slot, KERNEL_IC_CALL_U0);
        if (r)
          return r;
        if (KernelLexSkipSpaceSoft(&cc) != ';')
          return -84;
        KernelLexGetCharSoft(&cc);
        continue;
      }
      // Declared frame local first, then file-scope glbl — undeclared idents error.
      cc.cur_buf_ptr = save_ptr;
      cc.flags = save_flags;
      cc.last_U16 = save_last;
      r = KernelPrsGlblAsgSoft(&cc, kernel_prs_ic, &n, ';');
      if (r)
        return r;
    }
    if (saw_ret) {
      if (rtype == KERNEL_SOFT_TYPE_U0) {
        // `return;` — no value. `return Expr;` in a U0 fun is a type error, not a
        // silently discarded value.
        if (KernelLexSkipSpaceSoft(&cc) != ';')
          return -81;
        KernelLexGetCharSoft(&cc);
      } else {
        if (KernelPrsExprSoft(&cc, kernel_prs_ic, &n, KERNEL_PRS_IC_MAX))
          return -15;
        if (KernelLexSkipSpaceSoft(&cc) != ';')
          return -16;
        KernelLexGetCharSoft(&cc);
      }
    } else if (rtype != KERNEL_SOFT_TYPE_U0)
      return -82;
    if (KernelLexSkipSpaceSoft(&cc) != '}')
      return -17;
    KernelLexGetCharSoft(&cc);
    // Watermarks are per body; the deepest one is what the caps must cover.
    if (n > kernel_soft_ic_hi)
      kernel_soft_ic_hi = n;
    if (next_lb > kernel_soft_lb_hi)
      kernel_soft_lb_hi = next_lb;
    if (kernel_soft_local_n > kernel_soft_lc_hi)
      kernel_soft_lc_hi = kernel_soft_local_n;
    // 16 covers the ra slot alone; locals push it out via their abi_off.
    frame = KernelSoftFrameSizeSoft();
    if (frame < 0)
      return -31;
    if (frame < 16)
      frame = 16;
    sz = KernelEmitGlblICSoft(kernel_prs_ic, n, frame, nargs, argt, rtype, kernel_fun_code + kernel_fun_code_off, KERNEL_SOFT_FUN_CODE - kernel_fun_code_off);
    if (sz < 8)
      return -18;
    // Arity and both type ends are planted with the entry, so a later body's call
    // site can check the count, refuse a U0 callee as an Expr, and trust that the
    // callee has already narrowed whatever it returns.
    if (KernelFunPlantTypedSoft(fname, kernel_fun_code + kernel_fun_code_off, nargs, argt, rtype) < 0)
      return -19;
    kernel_fun_code_off += sz;
    KernelFenceI;
  }
  if (KernelLexIdentSoft(&cc))
    return -20;
  slot = KernelFunFindSoft(kernel_lex_ident);
  if (slot < 0)
    return -21;
  // The trailing entry call is made from HolyC as fp() — it takes no args, so an
  // entry declared with args is rejected rather than called with garbage in a0.
  if (KernelFunNArgsSoft(slot))
    return -79;
  // HolyC reads the entry's a0, so a U0 entry would hand back whatever the last
  // statement left there. Rejected rather than reported as a value.
  if (KernelFunRTypeSoft(slot) == KERNEL_SOFT_TYPE_U0)
    return -85;
  if (KernelLexSkipSpaceSoft(&cc) != '(')
    return -22;
  KernelLexGetCharSoft(&cc);
  if (KernelLexSkipSpaceSoft(&cc) != ')')
    return -23;
  KernelLexGetCharSoft(&cc);
  if (KernelLexSkipSpaceSoft(&cc) != ';')
    return -24;
  KernelLexGetCharSoft(&cc);
  KernelFenceI;
  fp = kernel_soft_funs[slot].code;
  return fp();
}
// SoftCall prove: SoftCall-lite glbl memory past CallIcSoft 'CL'.
// Emitted code materializes each glbl's absolute address and ld/sd through it, so
// the value lives in Kernel.BIN data — proven twice over: a store in one fun is
// read by a later fun after the jal returns, and HolyC reads the same storage back.
public I64 KernelGlblMemSoft()
{
  I64 r;
  if (KernelCallIcSoft() != 0x434C)
    return -1;
  // sd then ld the same glbl inside one body.
  r = KernelPrsGlblFunDefSoft("I64 g;I64 F(){g=40;return g+2;}F();");
  if (r != 42)
    return -2;
  // The sd really hit BIN data — HolyC reads the glbl the emitted code wrote.
  if (KernelGlblFindSoft("g") != 0)
    return -3;
  if (kernel_soft_glbls[0].val != 40)
    return -4;
  // Cross-fun through memory: G stores, jal ra returns, then F loads g.
  r = KernelPrsGlblFunDefSoft("I64 g;I64 G(){g=40;return 0;}I64 F(){return G()+g+2;}F();");
  if (r != 42)
    return -5;
  if (kernel_soft_glbls[0].val != 40)
    return -6;
  // Two glbls → distinct addresses.
  r = KernelPrsGlblFunDefSoft("I64 g;I64 h;I64 F(){g=40;h=2;return g+h;}F();");
  if (r != 42)
    return -7;
  if (kernel_soft_glbls[0].val != 40)
    return -8;
  if (kernel_soft_glbls[1].val != 2)
    return -9;
  // Read-modify-write: the second load must see the first store (real ld, not fold).
  r = KernelPrsGlblFunDefSoft("I64 g;I64 F(){g=6;g=g*7;return g;}F();");
  if (r != 42)
    return -10;
  if (kernel_soft_glbls[0].val != 42)
    return -11;
  // No-glbl def+call stays green — glbl memory is additive to the lite Prs tip.
  r = KernelPrsGlblFunDefSoft("I64 F(){return 40+2;}F();");
  if (r != 42)
    return -12;
  // CallIcSoft shapes stay green after glbl plants.
  r = KernelPrsCallFunDefSoft("I64 G(){return 40;}I64 F(){return G()+2;}F();");
  if (r != 42)
    return -13;
  kernel_soft_glbl_n = 0;
  return 0x474D;
  // 'GM'
}
// SoftCall guest source arena: RedSea text lands here, then the lite Prs walks it.
// 2KiB matches the SoftCall Load budget; no BIN literal ever backs it.
#define KERNEL_GUEST_SRC_MAX 2048
U8 kernel_guest_src[KERNEL_GUEST_SRC_MAX];
// Rolling *31 hash over the bytes the board actually consumed. The smoke recomputes
// it host-side over the seed file, so a matching sum proves the exact disk bytes
// (not a Kernel.BIN copy) reached the Prs.
I64 KernelGuestSrcSumSoft(U8 *buf, I64 n)
{
  I64 i, sum;
  sum = 0;
  if (!buf || n < 0)
    return 0;
  for (i = 0; i < n; i++)
    sum = (sum * 31 + buf[i]) & 0xFFFFFFFF;
  return sum;
}
// SoftCall prove: first real guest Cmp. A:/Compiler/SoftGlbl.HC is Compiler_RV-shaped
// HolyC that only exists on the RedSea image — Kernel.BIN reads it multi-blk, the
// in-BIN lite Prs Cmps its glbl decls + two fun defs, and the emitted code is Called.
// No Mac phase3.elf, no in-BIN source literal.
public I64 KernelGuestCmpSoft()
{
  U8 msg[KERNEL_SPRINT_CAP];
  I64 args[2];
  I64 sz, sum, r;
  if (KernelGlblMemSoft() != 0x474D)
    return -1;
  if (!KernelFileFind("A:/Compiler/SoftGlbl.HC"))
    return -2;
  KernelMemSet(kernel_guest_src, 0, KERNEL_GUEST_SRC_MAX);
  sz = KernelSrcRead("A:/Compiler/SoftGlbl.HC", kernel_guest_src, KERNEL_GUEST_SRC_MAX);
  if (sz <= 0)
    return -3;
  // Past one sector: the seed carries a real doc header, so this is a multi-blk read.
  if (sz <= 512)
    return -4;
  sum = KernelGuestSrcSumSoft(kernel_guest_src, sz);
  args[0] = sz;
  args[1] = sum;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestCmp src sz=%d sum=%X\n", 2, args);
  KernelUart(msg);
  // The header comment only parses because the lite Lex now skips '//' to EOL.
  if (kernel_guest_src[0] != '/' || kernel_guest_src[1] != '/')
    return -5;
  r = KernelPrsGlblFunDefSoft(kernel_guest_src);
  if (r != 42)
    return -6;
  // All three file-scope glbls are real BIN storage the emitted code wrote through,
  // across two jal ra returns (Sum -> Add -> Init).
  if (kernel_soft_glbl_n != 3)
    return -7;
  if (kernel_soft_glbls[0].val != 40)
    return -8;
  if (kernel_soft_glbls[1].val != 2)
    return -9;
  if (kernel_soft_glbls[2].val)
    return -10;
  // Three fun defs planted; the entry is the trailing `name();` of the guest file.
  if (kernel_soft_fun_n != 3)
    return -11;
  kernel_soft_glbl_n = 0;
  return 0x4743;
  // 'GC'
}
// Count emitted words matching (w & mask) == want — reads the bytes the lite Cmp
// actually planted, so a frame-slot claim is checked against real encodings.
I64 KernelSoftScanInsnSoft(U8 *code, I64 n, I64 mask, I64 want)
{
  I64 i, hits;
  U32 w;
  hits = 0;
  if (!code || n < 4)
    return 0;
  for (i = 0; i + 4 <= n; i += 4) {
    w = *(code + i)(U32 *);
    if ((w(I64) & mask) == want)
      hits++;
  }
  return hits;
}
// Count positions where three consecutive emitted words match three (mask,want)
// pairs. A single encoding is not enough to prove an ABI prologue — `sd a0,8(sp)`
// is also what an ordinary frame-local store looks like — so the arg gates match a
// sequence instead: the spill pair right after `sd ra,0(sp)`, and the a0/a1 setup
// right before a `jal ra`.
I64 KernelSoftScanSeq3Soft(U8 *code, I64 n, I64 m0, I64 w0, I64 m1, I64 w1, I64 m2, I64 w2)
{
  I64 i, hits;
  U32 a, b, c;
  hits = 0;
  if (!code || n < 12)
    return 0;
  for (i = 0; i + 12 <= n; i += 4) {
    a = *(code + i)(U32 *);
    b = *(code + i + 4)(U32 *);
    c = *(code + i + 8)(U32 *);
    if ((a(I64) & m0) == w0 && (b(I64) & m1) == w1 && (c(I64) & m2) == w2)
      hits++;
  }
  return hits;
}
// SoftCall prove: frame locals inside a glbl-fun body, past GuestCmpSoft 'GC'.
// `I64 l;` in a body plants an sp slot at 8.. (above the saved ra) and every use is
// a real ld/sd through it — KernelLocalValSoft poisons abi locals, so no plant-time
// fold path exists. The frame proof is the callee: G's `t` and F's `t` share a slot
// index but sit on different frames, so F's value survives the jal ra.
// A:/Compiler/SoftLocal.HC carries the same shape off RedSea, gated on sz + sum.
public I64 KernelGuestLocalSoft()
{
  U8 msg[KERNEL_SPRINT_CAP];
  I64 args[3];
  I64 sz, sum, r, code, frame, frame_locals;
  I64 n_pro, n_sd8, n_sd16, n_ld8, n_ld16;
  if (KernelGuestCmpSoft() != 0x4743)
    return -1;
  // One declared local: 40 and 2 never meet until the ld at 8(sp) runs.
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=40;return t+2;}F();");
  if (r != 42)
    return -2;
  // Two locals → distinct slots (8 and 16), one frame.
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t,u;t=40;u=2;return t+u;}F();");
  if (r != 42)
    return -3;
  // Read-modify-write: the ld must observe the earlier sd, not a folded 6.
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=6;t=t*7;return t;}F();");
  if (r != 42)
    return -4;
  // Locals and glbls coexist: t is frame storage, g is BIN storage by abs address.
  r = KernelPrsGlblFunDefSoft("I64 g;I64 F(){I64 t;t=2;g=40;return g+t;}F();");
  if (r != 42)
    return -5;
  if (kernel_soft_glbls[0].val != 40)
    return -6;
  // Real frames, not static slots: G writes its own `t` (same slot index, lower
  // frame) between F's store and F's load. Static storage would return 1+1.
  r = KernelPrsGlblFunDefSoft("I64 g;I64 G(){I64 t;t=1;g=7;return t;}I64 F(){I64 t,u;t=41;u=G();return t+u;}F();");
  if (r != 42)
    return -7;
  if (kernel_soft_glbls[0].val != 7)
    return -8;
  // No-local bodies still emit the CallIC-shaped frame — GlblMem shapes stay green.
  r = KernelPrsGlblFunDefSoft("I64 g;I64 G(){g=40;return 0;}I64 F(){return G()+g+2;}F();");
  if (r != 42)
    return -9;
  // Undeclared idents are still an error, and a local may not shadow a glbl.
  if (KernelPrsGlblFunDefSoft("I64 F(){t=40;return t+2;}F();") != -10)
    return -10;
  if (KernelPrsGlblFunDefSoft("I64 g;I64 F(){I64 g;g=42;return g;}F();") != -26)
    return -11;
  kernel_soft_glbl_n = 0;
  // Off-disk proof: the same frame-local shape, read from RedSea at runtime.
  if (!KernelFileFind("A:/Compiler/SoftLocal.HC"))
    return -12;
  KernelMemSet(kernel_guest_src, 0, KERNEL_GUEST_SRC_MAX);
  sz = KernelSrcRead("A:/Compiler/SoftLocal.HC", kernel_guest_src, KERNEL_GUEST_SRC_MAX);
  if (sz <= 0)
    return -13;
  // Past one sector: KernelFileRead stops at a blk, so this is a multi-blk walk.
  if (sz <= 512)
    return -14;
  sum = KernelGuestSrcSumSoft(kernel_guest_src, sz);
  args[0] = sz;
  args[1] = sum;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestLocal src sz=%d sum=%X\n", 2, args);
  KernelUart(msg);
  if (kernel_guest_src[0] != '/' || kernel_guest_src[1] != '/')
    return -15;
  r = KernelPrsGlblFunDefSoft(kernel_guest_src);
  if (r != 42)
    return -16;
  code = kernel_fun_code_off;
  frame_locals = kernel_soft_local_n;
  // One file-scope glbl the leaf wrote through, two fun defs, two frame locals in
  // the entry body — the 41 it kept across the jal is the frame, not a fold.
  if (kernel_soft_glbl_n != 1)
    return -17;
  if (kernel_soft_glbls[0].val != 7)
    return -18;
  if (kernel_soft_fun_n != 2)
    return -19;
  if (frame_locals != 2)
    return -20;
  // The slots are sp offsets, not table values: 8 and 16 clear the saved ra at 0,
  // and the entry body's frame is exactly 32 (16-aligned cover of the top slot).
  if (KernelLocalAbiOffSoft(0) != 8)
    return -21;
  if (KernelLocalAbiOffSoft(1) != 16)
    return -22;
  frame = KernelSoftFrameSizeSoft();
  if (frame != 32)
    return -23;
  // Disassemble what was planted: the locals must be sp-relative ld/sd, not folds.
  n_pro = KernelSoftScanInsnSoft(kernel_fun_code, code, 0xFFFFFFFF, 0xFE010113);
  n_sd8 = KernelSoftScanInsnSoft(kernel_fun_code, code, 0xFE0FFFFF, 0x00013423);
  n_sd16 = KernelSoftScanInsnSoft(kernel_fun_code, code, 0xFE0FFFFF, 0x00013823);
  n_ld8 = KernelSoftScanInsnSoft(kernel_fun_code, code, 0xFFFFF07F, 0x00813003);
  n_ld16 = KernelSoftScanInsnSoft(kernel_fun_code, code, 0xFFFFF07F, 0x01013003);
  args[0] = n_pro;
  args[1] = n_sd8 * 10 + n_sd16;
  args[2] = n_ld8 * 10 + n_ld16;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestLocal disasm pro=%d sd8_16=%d ld8_16=%d\n", 3, args);
  KernelUart(msg);
  // addi sp,sp,-32 — the entry body's frame really moves sp.
  if (n_pro != 1)
    return -24;
  // sd rs2,8(sp) and sd rs2,16(sp) (rs2 masked out) — the two local stores.
  if (n_sd8 < 1)
    return -25;
  if (n_sd16 < 1)
    return -26;
  // ld rd,8(sp) and ld rd,16(sp) (rd masked out) — the two local loads.
  if (n_ld8 < 1)
    return -27;
  if (n_ld16 < 1)
    return -28;
  // Measured headroom, not assumed: emitted bytes vs KERNEL_SOFT_FUN_CODE.
  args[0] = code;
  args[1] = KERNEL_SOFT_FUN_CODE;
  args[2] = frame;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestLocal code=%d/%d frame=%d locals=2 slots=8,16\n", 3, args);
  KernelUart(msg);
  kernel_soft_glbl_n = 0;
  return 0x474C;
  // 'GL'
}
// SoftCall prove: if / while / for inside the merged glbl-fun body, past 'GL'.
// The body statement loop now dispatches control flow onto the same IC_BR_ZERO /
// IC_JMP / IC_LABEL machinery the COC path proved, and every init / step / body is
// the same KernelPrsGlblAsgSoft an ordinary statement uses — so a branch stores
// through IC_ASSIGN / IC_GLBL_ASSIGN, never a plant-time value. Labels are body
// scoped, so the merged body's budget is KERNEL_SOFT_LABEL_MAX per fun.
// A:/Compiler/SoftFlow.HC carries an OptPass_RV-shaped sweep off RedSea, gated on
// sz + sum + a disassembly of the branch encodings the lite Cmp actually planted.
public I64 KernelGuestFlowSoft()
{
  U8 msg[KERNEL_SPRINT_CAP];
  I64 args[3];
  I64 sz, sum, r, code, ic_hi, lb_hi;
  I64 n_br, n_jb, n_jf;
  if (KernelGuestLocalSoft() != 0x474C)
    return -1;
  // if taken / not taken on a frame local — the cond is a real beqz, not a fold.
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=0;if(1)t=42;return t;}F();");
  if (r != 42)
    return -2;
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=42;if(0)t=0;return t;}F();");
  if (r != 42)
    return -3;
  // if/else where the else arm stores to a glbl by absolute address.
  r = KernelPrsGlblFunDefSoft("I64 g;I64 F(){I64 t;t=0;if(0)t=0;else g=42;return g+t;}F();");
  if (r != 42)
    return -4;
  if (kernel_soft_glbls[0].val != 42)
    return -5;
  // while: the ld at 8(sp) must observe the previous pass's sd, so 40 walks to 42.
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=40;while(t-42)t=t+1;return t;}F();");
  if (r != 42)
    return -6;
  // while already-done (cond zero on the first check — not-taken body).
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=42;while(t-42)t=0;return t;}F();");
  if (r != 42)
    return -7;
  // for: init / cond / step over two frame locals; a dead body would return 0.
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t,u;u=0;for(t=0;t-6;t=t+1)u=u+7;return u;}F();");
  if (r != 42)
    return -8;
  // Loop bound read out of BIN data every pass (IC_GLBL inside the cond).
  r = KernelPrsGlblFunDefSoft("I64 g;I64 F(){I64 t;g=42;t=0;while(t-g)t=t+1;return t;}F();");
  if (r != 42)
    return -9;
  if (kernel_soft_glbls[0].val != 42)
    return -10;
  // Frames survive branches: G loops on its own `t` between F's store and F's load.
  r = KernelPrsGlblFunDefSoft("I64 g;I64 G(){I64 t;t=0;while(t-7)t=t+1;g=t;return t;}I64 F(){I64 t,u;t=35;u=G();return t+u;}F();");
  if (r != 42)
    return -11;
  if (kernel_soft_glbls[0].val != 7)
    return -12;
  // Branch bodies are ordinary statements: an undeclared target still errors -10.
  if (KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=0;if(1)u=42;return t;}F();") != -10)
    return -13;
  // Straight-line 'GL' / 'GM' shapes stay green after the flow plants.
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t,u;t=40;u=2;return t+u;}F();");
  if (r != 42)
    return -14;
  r = KernelPrsGlblFunDefSoft("I64 g;I64 F(){g=40;return g+2;}F();");
  if (r != 42)
    return -15;
  kernel_soft_glbl_n = 0;
  // Off-disk proof: an OptPass_RV-shaped sweep read from RedSea at runtime.
  if (!KernelFileFind("A:/Compiler/SoftFlow.HC"))
    return -16;
  KernelMemSet(kernel_guest_src, 0, KERNEL_GUEST_SRC_MAX);
  sz = KernelSrcRead("A:/Compiler/SoftFlow.HC", kernel_guest_src, KERNEL_GUEST_SRC_MAX);
  if (sz <= 0)
    return -17;
  // Past one sector: KernelFileRead stops at a blk, so this is a multi-blk walk.
  if (sz <= 512)
    return -18;
  sum = KernelGuestSrcSumSoft(kernel_guest_src, sz);
  args[0] = sz;
  args[1] = sum;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestFlow src sz=%d sum=%X\n", 2, args);
  KernelUart(msg);
  if (kernel_guest_src[0] != '/' || kernel_guest_src[1] != '/')
    return -19;
  // Scan 5*7=35 through a for, Peel 7->1 through a while then an else, Fold sums.
  r = KernelPrsGlblFunDefSoft(kernel_guest_src);
  if (r != 42)
    return -20;
  code = kernel_fun_code_off;
  ic_hi = kernel_soft_ic_hi;
  lb_hi = kernel_soft_lb_hi;
  // Two file-scope glbls, three fun defs; the sweep really wrote its hit count out.
  if (kernel_soft_glbl_n != 2)
    return -21;
  if (kernel_soft_glbls[0].val != 5)
    return -22;
  if (kernel_soft_glbls[1].val != 35)
    return -23;
  if (kernel_soft_fun_n != 3)
    return -24;
  // Disassemble what was planted. beq is the only opcode-0x63 form the lite Cmp
  // emits, and bit 31 is imm[12] — so a set sign bit is a real backward edge.
  // beqz a0,imm (rs2=x0, rs1=a0): one per if / while / for cond.
  n_br = KernelSoftScanInsnSoft(kernel_fun_code, code, 0x01FFF07F, 0x00050063);
  // beq x0,x0,imm with imm<0: the for and while back edges.
  n_jb = KernelSoftScanInsnSoft(kernel_fun_code, code, 0x81FFF07F, 0x80000063);
  // beq x0,x0,imm with imm>0: the if/else join.
  n_jf = KernelSoftScanInsnSoft(kernel_fun_code, code, 0x81FFF07F, 0x00000063);
  args[0] = n_br;
  args[1] = n_jb;
  args[2] = n_jf;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestFlow disasm br=%d jb=%d jf=%d\n", 3, args);
  KernelUart(msg);
  // Three conds (for, while, if), two backward edges (for, while), one join (else).
  if (n_br != 3)
    return -25;
  if (n_jb != 2)
    return -26;
  if (n_jf != 1)
    return -27;
  // Measured headroom, not assumed: emitted bytes / IC / labels vs the caps.
  args[0] = code;
  args[1] = ic_hi;
  args[2] = lb_hi;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestFlow code=%d/1024 ic=%d/32 lb=%d/8\n", 3, args);
  KernelUart(msg);
  kernel_soft_glbl_n = 0;
  return 0x4746;
  // 'GF'
}
// SoftCall prove: non-I64 typed values — a U8 * cursor and byte-width memory, past
// 'GF'. Three things are new and none of them can be constant-folded:
//   * a `U8 b[N];` file-scope decl plants a real byte buffer and its name decays to
//     that buffer's address (IC_GLBL_ADDR: abs materialize, no ld), so the value on
//     the lite RPN stack is a pointer rather than an I64 read out of a cell;
//   * `*p` is IC_LOAD_U8 — lbu rd,0(rd) — reading whatever byte the pointer names at
//     run time, and `*p = Expr;` is IC_STORE_U8 — sb rs2,0(rs1);
//   * KernelOptPassSoft's RPN evaluator has no arm for any of the three, so it
//     returns poison the moment one appears, exactly as it does for IC_GLBL.
// Byte width is load-bearing, not incidental: a 298 stored through `*p` reads back as
// 42, which an I64 cell could never do.
// A:/Compiler/SoftPtr.HC carries a Lex.HC-shaped char walk off RedSea, gated on the
// same sz + rolling *31 sum + no-guest-ident-in-BIN trio as 'GC'/'GL'/'GF', plus a
// disassembly of the lbu / sb / abs-materialize encodings actually planted.
public I64 KernelGuestPtrSoft()
{
  U8 msg[KERNEL_SPRINT_CAP];
  I64 args[3];
  I64 sz, sum, r, code, ic_hi, lb_hi;
  I64 n_lbu, n_sb, n_abs, buf_addr;
  if (KernelGuestFlowSoft() != 0x4746)
    return -1;
  // Store then load one byte through a pointer aimed at a U8 buffer.
  r = KernelPrsGlblFunDefSoft("U8 b[4];U8 *p;I64 F(){p=b;*p=42;return *p;}F();");
  if (r != 42)
    return -2;
  // Byte width, not I64 width: sb keeps the low 8 bits and lbu zero-extends them.
  r = KernelPrsGlblFunDefSoft("U8 b[4];U8 *p;I64 F(){p=b;*p=298;return *p;}F();");
  if (r != 42)
    return -3;
  // Distinct cells one byte apart — pointer arithmetic really moves the address.
  r = KernelPrsGlblFunDefSoft("U8 b[4];U8 *p;I64 F(){I64 s;p=b;*p=40;p=p+1;*p=2;s=*p;p=b;return s+*p;}F();");
  if (r != 42)
    return -4;
  // The buffer is real Kernel.BIN storage HolyC reads back, not a plant-time value.
  if (kernel_soft_glbls[0].arr[0] != 40)
    return -5;
  if (kernel_soft_glbls[0].arr[1] != 2)
    return -6;
  // The U8 * cell holds the buffer's absolute address, so decay is an address.
  buf_addr = KernelGlblAddrSoft(0);
  if (!buf_addr)
    return -7;
  if (kernel_soft_glbls[1].val != buf_addr)
    return -8;
  // A NUL-terminated walk: the for cond re-reads the byte the cursor names each pass.
  r = KernelPrsGlblFunDefSoft("U8 b[4];U8 *p;I64 G(){p=b;*p=20;p=p+1;*p=22;p=p+1;*p=0;return 0;}I64 F(){I64 s;s=G();for(p=b;*p;p=p+1)s=s+*p;return s;}F();");
  if (r != 42)
    return -9;
  // An array name is an address, not a cell — assigning to it is an error.
  if (KernelPrsGlblFunDefSoft("U8 b[4];I64 F(){b=1;return 0;}F();") != -36)
    return -10;
  // Deref still needs a declared target: an undeclared cursor errors like any ident.
  if (KernelPrsGlblFunDefSoft("U8 b[4];I64 F(){*q=1;return 0;}F();") != -34)
    return -11;
  // Straight-line 'GF' / 'GL' / 'GM' shapes stay green after the typed plants.
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=40;while(t-42)t=t+1;return t;}F();");
  if (r != 42)
    return -12;
  r = KernelPrsGlblFunDefSoft("I64 g;I64 F(){g=40;return g+2;}F();");
  if (r != 42)
    return -13;
  kernel_soft_glbl_n = 0;
  // Off-disk proof: a Lex.HC-shaped char walk read from RedSea at runtime.
  if (!KernelFileFind("A:/Compiler/SoftPtr.HC"))
    return -14;
  KernelMemSet(kernel_guest_src, 0, KERNEL_GUEST_SRC_MAX);
  sz = KernelSrcRead("A:/Compiler/SoftPtr.HC", kernel_guest_src, KERNEL_GUEST_SRC_MAX);
  if (sz <= 0)
    return -15;
  // Past one sector: KernelFileRead stops at a blk, so this is a multi-blk walk.
  if (sz <= 512)
    return -16;
  sum = KernelGuestSrcSumSoft(kernel_guest_src, sz);
  args[0] = sz;
  args[1] = sum;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestPtr src sz=%d sum=%X\n", 2, args);
  KernelUart(msg);
  if (kernel_guest_src[0] != '/' || kernel_guest_src[1] != '/')
    return -17;
  // Seed writes 20,22,0 through the cursor; Walk sums them back to 42.
  r = KernelPrsGlblFunDefSoft(kernel_guest_src);
  if (r != 42)
    return -18;
  code = kernel_fun_code_off;
  ic_hi = kernel_soft_ic_hi;
  lb_hi = kernel_soft_lb_hi;
  // One U8 buffer, one U8 * cursor, one I64 total; three fun defs.
  if (kernel_soft_glbl_n != 3)
    return -19;
  if (KernelGlblKindSoft(0) != KERNEL_GLBL_KIND_ARR)
    return -20;
  if (KernelGlblKindSoft(1) != KERNEL_GLBL_KIND_PTR)
    return -21;
  if (KernelGlblKindSoft(2) != KERNEL_GLBL_KIND_I64)
    return -22;
  if (kernel_soft_fun_n != 3)
    return -23;
  // The bytes the guest wrote are still in BIN storage, and the walk saw exactly
  // them: 20 + 22 = 42 with a NUL stop, so a run-on walk would over-count.
  if (kernel_soft_glbls[0].arr[0] != 20)
    return -24;
  if (kernel_soft_glbls[0].arr[1] != 22)
    return -25;
  if (kernel_soft_glbls[0].arr[2])
    return -26;
  if (kernel_soft_glbls[2].val != 42)
    return -27;
  // The cursor stopped on the NUL, one past the last text byte.
  if (kernel_soft_glbls[1].val != KernelGlblAddrSoft(0) + 2)
    return -28;
  // Disassemble what was planted. lbu rd,0(rs1) and sb rs2,0(rs1) are the only
  // byte-width forms the lite Cmp emits, and srli rd,rd,32 only ever closes an
  // absolute-address materialize — a folded walk would emit none of the three.
  n_lbu = KernelSoftScanInsnSoft(kernel_fun_code, code, 0xFFF0707F, 0x00004003);
  n_sb = KernelSoftScanInsnSoft(kernel_fun_code, code, 0xFE007FFF, 0x00000023);
  n_abs = KernelSoftScanInsnSoft(kernel_fun_code, code, 0xFFF0707F, 0x02005013);
  args[0] = n_lbu;
  args[1] = n_sb;
  args[2] = n_abs;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestPtr disasm lbu=%d sb=%d abs=%d\n", 3, args);
  KernelUart(msg);
  // Two lbu (the for cond and the accumulate), three sb (the seeded bytes).
  if (n_lbu != 2)
    return -29;
  if (n_sb != 3)
    return -30;
  // Nine abs in Seed, seven in Walk — every glbl touch pays lui/addi/slli/srli.
  if (n_abs != 16)
    return -31;
  // Measured headroom, not assumed: emitted bytes / IC / labels vs the caps.
  args[0] = code;
  args[1] = ic_hi;
  args[2] = lb_hi;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestPtr code=%d/1024 ic=%d/32 lb=%d/8\n", 3, args);
  KernelUart(msg);
  kernel_soft_glbl_n = 0;
  return 0x4750;
  // 'GP'
}
// SoftCall prove: function arguments and calls that pass them, past 'GP'. Three
// things are new and none of them can be constant-folded:
//   * `I64 name(I64 a, I64 b)` plants each arg as a frame slot at 8(sp) / 16(sp) and
//     the emitted prologue spills a0 / a1 into them, so a body reference to an arg
//     is the same IC_LOCAL ld an ordinary `I64 l;` gets;
//   * a call site `name(Expr, Expr)` appends each arg Expr to the caller's IC ahead
//     of the IC_CALL, and the lite RPN walk hands out a0 then a1 in order — the real
//     RISC-V argument registers, delivered by a real jal ra;
//   * KernelOptPassSoft poisons on IC_CALL and on abi locals alike, so neither the
//     callee body nor the call site has a plant-time fold path.
// The jal-clobber rule is now exact rather than "leftmost": at the call the lite
// stack must hold this call's arguments and nothing else.
// A:/Compiler/SoftArg.HC carries an OptPass_RV-shaped cost walk off RedSea, gated on
// the same sz + rolling *31 sum + no-guest-ident-in-BIN trio as 'GF'/'GP', plus a
// disassembly of the a0/a1 setup, the jal ra and the spill prologue actually planted.
public I64 KernelGuestArgSoft()
{
  U8 msg[KERNEL_SPRINT_CAP];
  I64 args[3];
  I64 sz, sum, r, code, ic_hi, lb_hi;
  I64 n_jal, n_pro, n_set;
  if (KernelGuestPtrSoft() != 0x4750)
    return -1;
  // One arg: HolyC never sees it — the caller's emitted code puts 40 in a0.
  r = KernelPrsGlblFunDefSoft("I64 G(I64 a){return a+2;}I64 F(){return G(40);}F();");
  if (r != 42)
    return -2;
  // Two args: a0 and a1 both carry, and * is not commutative in the wrong slot.
  r = KernelPrsGlblFunDefSoft("I64 G(I64 a,I64 b){return a-b;}I64 F(){return G(44,2);}F();");
  if (r != 42)
    return -3;
  // Two call sites, different values: a fixed-arg or folded callee cannot give 42.
  r = KernelPrsGlblFunDefSoft("I64 G(I64 a,I64 b){return a-b;}I64 F(){I64 t,u;t=G(50,10);u=G(4,2);return t+u;}F();");
  if (r != 42)
    return -4;
  // An arg reaches file-scope storage: the callee wrote what the caller passed.
  r = KernelPrsGlblFunDefSoft("I64 g;I64 G(I64 a){g=a;return 0;}I64 F(){I64 t;t=G(42);return g+t;}F();");
  if (r != 42)
    return -5;
  if (kernel_soft_glbls[0].val != 42)
    return -6;
  // A call may itself be an argument, as long as it is the one in flight: G's result
  // lands in a0, then 2 is materialized into a1, then H's jal runs.
  r = KernelPrsGlblFunDefSoft("I64 G(I64 a){return a+1;}I64 H(I64 a,I64 b){return a*b;}I64 F(){return H(G(20),2);}F();");
  if (r != 42)
    return -7;
  // An arg is a real frame slot, so the callee may reassign it like any local.
  r = KernelPrsGlblFunDefSoft("I64 G(I64 a){a=a*7;return a;}I64 F(){return G(6);}F();");
  if (r != 42)
    return -8;
  // Verbatim Compiler/Test_RV.HC AddNumbers — the first stock Compiler_RV function
  // the lite Prs can Cmp, and it only became reachable with this tip.
  r = KernelPrsGlblFunDefSoft("I64 AddNumbers(I64 x,I64 y){return x + y;}I64 F(){return AddNumbers(40,2);}F();");
  if (r != 42)
    return -30;
  // Too few actuals: a1 would hold whatever the caller happened to leave there.
  if (KernelPrsGlblFunDefSoft("I64 G(I64 a,I64 b){return a+b;}I64 F(){return G(40);}F();") != -15)
    return -9;
  // Too many actuals: the callee frame has no third slot to spill into.
  if (KernelPrsGlblFunDefSoft("I64 G(I64 a){return a;}I64 F(){return G(40,2);}F();") != -15)
    return -10;
  // Not leftmost: 2 is live in a0 when the jal would clobber it, so this is refused
  // rather than silently mis-emitted (KernelEmitICBodySoft -24 → EmitGlblIC -5).
  if (KernelPrsGlblFunDefSoft("I64 G(I64 a){return a;}I64 F(){return 2+G(40);}F();") != -18)
    return -11;
  // Nor may a call be an argument with an earlier arg still live.
  if (KernelPrsGlblFunDefSoft("I64 G(I64 a){return a;}I64 H(I64 a,I64 b){return a+b;}I64 F(){return H(40,G(2));}F();") != -18)
    return -12;
  // An arg may not shadow a glbl: the abs-address path would go dark.
  if (KernelPrsGlblFunDefSoft("I64 g;I64 G(I64 g){return g;}I64 F(){return G(42);}F();") != -76)
    return -13;
  // Args are I64-only in this tip.
  if (KernelPrsGlblFunDefSoft("I64 G(U8 a){return a;}I64 F(){return G(42);}F();") != -74)
    return -14;
  // The entry is Called from HolyC as fp(), so it may not declare args.
  if (KernelPrsGlblFunDefSoft("I64 F(I64 a){return a;}F();") != -79)
    return -15;
  // Straight-line 'GP' / 'GF' / 'GM' shapes stay green after the arg plants.
  r = KernelPrsGlblFunDefSoft("U8 b[4];U8 *p;I64 F(){p=b;*p=42;return *p;}F();");
  if (r != 42)
    return -16;
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=40;while(t-42)t=t+1;return t;}F();");
  if (r != 42)
    return -17;
  r = KernelPrsGlblFunDefSoft("I64 g;I64 G(){return 40;}I64 F(){return G()+2;}F();");
  if (r != 42)
    return -18;
  kernel_soft_glbl_n = 0;
  // Off-disk proof: an OptPass_RV-shaped cost walk read from RedSea at runtime.
  if (!KernelFileFind("A:/Compiler/SoftArg.HC"))
    return -19;
  KernelMemSet(kernel_guest_src, 0, KERNEL_GUEST_SRC_MAX);
  sz = KernelSrcRead("A:/Compiler/SoftArg.HC", kernel_guest_src, KERNEL_GUEST_SRC_MAX);
  if (sz <= 0)
    return -20;
  // Past one sector: KernelFileRead stops at a blk, so this is a multi-blk walk.
  if (sz <= 512)
    return -21;
  sum = KernelGuestSrcSumSoft(kernel_guest_src, sz);
  args[0] = sz;
  args[1] = sum;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestArg src sz=%d sum=%X\n", 2, args);
  KernelUart(msg);
  if (kernel_guest_src[0] != '/' || kernel_guest_src[1] != '/')
    return -22;
  // Cost(2,1)=10 and Cost(8,0)=24 through one helper, then 34+8.
  r = KernelPrsGlblFunDefSoft(kernel_guest_src);
  if (r != 42)
    return -23;
  code = kernel_fun_code_off;
  ic_hi = kernel_soft_ic_hi;
  lb_hi = kernel_soft_lb_hi;
  // One file-scope cell, three fun defs; the banked total is what the two differently
  // argued calls really produced, so a fixed-arg callee shows up as 30 or 38 here.
  if (kernel_soft_glbl_n != 1)
    return -24;
  if (kernel_soft_glbls[0].val != 34)
    return -25;
  if (kernel_soft_fun_n != 3)
    return -26;
  // The helper is the only fun that declared args, and it declared two.
  if (KernelFunNArgsSoft(0) != 2)
    return -27;
  if (KernelFunNArgsSoft(1))
    return -28;
  if (KernelFunNArgsSoft(2))
    return -29;
  // Disassemble what was planted.
  //   jal ra   — opcode 0x6F with rd=1: a real call, not an inlined body.
  //   pro      — sd ra,0(sp); sd a0,8(sp); sd a1,16(sp): the arg-spill prologue. A
  //              single sd would not prove it (an ordinary frame store shares the
  //              encoding), so this is matched as a three-word sequence.
  //   set      — addi a0,x0,imm; addi a1,x0,imm; jal ra: the caller really loads
  //              both argument registers immediately before the call.
  n_jal = KernelSoftScanInsnSoft(kernel_fun_code, code, 0x00000FFF, 0x000000EF);
  n_pro = KernelSoftScanSeq3Soft(kernel_fun_code, code, 0xFFFFFFFF, 0x00113023, 0xFFFFFFFF, 0x00A13423, 0xFFFFFFFF, 0x00B13823);
  n_set = KernelSoftScanSeq3Soft(kernel_fun_code, code, 0x000FFFFF, 0x00513, 0x000FFFFF, 0x00593, 0x00000FFF, 0x000000EF);
  args[0] = n_jal;
  args[1] = n_pro;
  args[2] = n_set;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestArg disasm jal=%d pro=%d set=%d\n", 3, args);
  KernelUart(msg);
  // Three jal ra: two Cost calls in Sum, one Sum call in Tally.
  if (n_jal != 3)
    return -30;
  // One arg-spill prologue: Cost is the only fun that takes args.
  if (n_pro != 1)
    return -31;
  // Two a0/a1 setups: the two differently argued Cost call sites.
  if (n_set != 2)
    return -32;
  // Measured headroom, not assumed: emitted bytes / IC / labels vs the caps.
  args[0] = code;
  args[1] = ic_hi;
  args[2] = lb_hi;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestArg code=%d/1024 ic=%d/32 lb=%d/8\n", 3, args);
  KernelUart(msg);
  kernel_soft_glbl_n = 0;
  return 0x4741;
  // 'GA'
}
// SoftCall prove: non-I64 return / arg types plus arity 4, past 'GA'. 212 of the 225
// Compiler_RV functions return U0, Bool, U32 or a pointer, and the fun-arg blocker
// only falls off a cliff at four args, so both moves are signature work on the one
// grammar. Nothing here can be constant-folded:
//   * widths are the callee's business at both ends. A Bool / U32 arg is narrowed in
//     the prologue before its spill and a Bool / U32 return is narrowed after the
//     body, so a call site never has to know the callee's type;
//   * U0 is the one type with no value. It cannot appear in an Expr, so it is reached
//     through a statement call whose IC_CALL_U0 puts the lite RPN stack back to empty
//     where IC_CALL leaves it at depth 1;
//   * args 3 and 4 ride a2 / a3 through the same real jal ra, spilled to 24(sp) /
//     32(sp) by the same prologue;
//   * KernelOptPassSoft has no arm for IC_CALL, IC_CALL_U0 or abi locals, so it
//     poisons on sight, and KernelPrsGlblFunDefSoft never calls it at all.
// The widths are load-bearing rather than decorative: Bool of 298 is 1 (not 298, and
// not the 42 a byte-wide narrowing would give), U32 of 2^32+42 is 42, and U32 of
// 2^31+42 stays positive because the narrowing is srli and not srai.
// A:/Compiler/SoftType.HC carries a BackLib_RV-shaped field packer off RedSea, gated
// on the same sz + rolling *31 sum + no-guest-ident-in-BIN trio as 'GF'/'GP'/'GA',
// plus a disassembly of every narrowing and of the a2/a3 spill and setup planted.
public I64 KernelGuestTypeSoft()
{
  U8 msg[KERNEL_SPRINT_CAP];
  I64 args[3];
  I64 sz, sum, r, code, ic_hi, lb_hi, lc_hi;
  I64 n_bool, n_u32, n_nov, n_arg4, n_set4, n_u32a;
  if (KernelGuestArgSoft() != 0x4741)
    return -1;
  // U0: no value at all. The store outlives the frame, and F reads it back after the
  // jal ra returns — HolyC never sees a0 from S.
  r = KernelPrsGlblFunDefSoft("I64 g;U0 S(){g=42;}I64 F(){S();return g;}F();");
  if (r != 42)
    return -2;
  // `return;` with no expression is the same shape as falling off the end.
  r = KernelPrsGlblFunDefSoft("I64 g;U0 S(){g=42;return;}I64 F(){S();return g;}F();");
  if (r != 42)
    return -3;
  // An empty U0 body is real stock shape: prologue straight into epilogue.
  r = KernelPrsGlblFunDefSoft("I64 g;U0 S(){}I64 F(){g=42;S();return g;}F();");
  if (r != 42)
    return -4;
  // A U0 statement call still passes arguments through the real a0/a1.
  r = KernelPrsGlblFunDefSoft("I64 g;U0 S(I64 a,I64 b){g=a+b;}I64 F(){S(40,2);return g;}F();");
  if (r != 42)
    return -5;
  // Bool return: 298 narrows to 1. Byte truncation would give 42 here and land the
  // sum on 83, and no narrowing at all would give 339.
  r = KernelPrsGlblFunDefSoft("Bool B(){return 298;}I64 F(){return B()+41;}F();");
  if (r != 42)
    return -6;
  // Both edges of the narrowing across a real jal: 500 is 1 and 0 stays 0.
  r = KernelPrsGlblFunDefSoft("Bool B(I64 a){return a;}I64 F(){I64 t,u;t=B(500);u=B(0);return t*42+u;}F();");
  if (r != 42)
    return -7;
  // Bool as an *argument*: the prologue narrows a0 before spilling it, so the body's
  // ld sees 1. Without that the glbl would bank 298 and the tally 12516.
  r = KernelPrsGlblFunDefSoft("I64 g;U0 S(Bool a){g=a;}I64 F(){S(298);return g*42;}F();");
  if (r != 42)
    return -8;
  // U32 width: 1024*1024*1024*4 is 2^32, so the low four bytes are 0 and only the
  // +42 survives. An I64 return would hand back 4294967338.
  r = KernelPrsGlblFunDefSoft("U32 W(){I64 t;t=1024;t=t*1024;t=t*1024;t=t*4;return t+42;}I64 F(){return W();}F();");
  if (r != 42)
    return -9;
  // U32 signedness: 2^31+42 has bit 31 set. srli keeps it positive; srai (or an
  // lw-shaped sign-extend) would hand back -2147483606 instead.
  r = KernelPrsGlblFunDefSoft("U32 W(){I64 t;t=1024;t=t*1024;t=t*1024;t=t*2;return t+42;}I64 F(){return W();}F();");
  if (r != 0x8000002A)
    return -10;
  // U32 as an *argument*: same narrowing, in the prologue instead of the epilogue.
  r = KernelPrsGlblFunDefSoft("I64 g;U0 S(U32 a){g=a;}I64 F(){I64 t;t=1024;t=t*1024;t=t*1024;t=t*4;S(t+42);return g;}F();");
  if (r != 42)
    return -11;
  // Pointer return: q holds what P handed back through a0, and the byte written
  // through q reads back — so the address survived the jal unnarrowed.
  r = KernelPrsGlblFunDefSoft("U8 b[4];U8 *p;U8 *q;U8 *P(){p=b;return p;}I64 F(){q=P();*q=42;return *q;}F();");
  if (r != 42)
    return -12;
  if (kernel_soft_glbls[2].val != KernelGlblAddrSoft(0))
    return -13;
  if (kernel_soft_glbls[0].arr[0] != 42)
    return -14;
  // Arity 3 — a2 carries.
  r = KernelPrsGlblFunDefSoft("I64 Q(I64 a,I64 b,I64 c){return a+b+c;}I64 F(){return Q(20,20,2);}F();");
  if (r != 42)
    return -15;
  // Arity 4 with a distinct weight per register: 4*8+1*4+2*2+2 is 42 and every one of
  // the 23 other orderings of those four values gives something else, so this can
  // only pass if a0..a3 are genuinely distinct and in order.
  r = KernelPrsGlblFunDefSoft("I64 Q(I64 a,I64 b,I64 c,I64 d){return a*8+b*4+c*2+d;}I64 F(){return Q(4,1,2,2);}F();");
  if (r != 42)
    return -16;
  // Four args plus two working locals — six frame slots at 8..56(sp), the deepest
  // thing the arity move touches.
  r = KernelPrsGlblFunDefSoft("I64 Q(I64 a,I64 b,I64 c,I64 d){I64 s,m;s=a+b;m=c+d;return s*m;}I64 F(){return Q(3,4,3,3);}F();");
  if (r != 42)
    return -17;
  lc_hi = kernel_soft_lc_hi;
  if (lc_hi != 6)
    return -18;
  // A four-argument U0 — the BackLib_RV emitter shape, weighted the same way.
  r = KernelPrsGlblFunDefSoft("I64 g;U0 S(I64 a,I64 b,I64 c,I64 d){g=a*8+b*4+c*2+d;}I64 F(){S(4,1,2,2);return g;}F();");
  if (r != 42)
    return -19;
  // A U0 fun has no value, so it may not appear in an Expr — in an assign target's
  // Expr (-12 through the shared assign helper) or in a return Expr (-15).
  if (KernelPrsGlblFunDefSoft("I64 g;U0 S(){g=1;}I64 F(){g=S();return g;}F();") != -12)
    return -20;
  if (KernelPrsGlblFunDefSoft("U0 S(){}I64 F(){return S();}F();") != -15)
    return -21;
  // Nor may a U0 fun return one.
  if (KernelPrsGlblFunDefSoft("I64 g;U0 S(){g=1;return 2;}I64 F(){S();return g;}F();") != -81)
    return -22;
  // Falling off the end is U0-only: an I64 fun that does it has nothing in a0.
  if (KernelPrsGlblFunDefSoft("I64 g;I64 F(){g=42;}F();") != -82)
    return -23;
  // HolyC reads the entry's a0, so a U0 entry is refused rather than reported.
  if (KernelPrsGlblFunDefSoft("I64 g;U0 F(){g=42;}F();") != -85)
    return -24;
  // `U8` is a 1-byte base with no narrowing — only its pointer form is a type here.
  if (KernelPrsGlblFunDefSoft("U8 F(){return 42;}F();") != -86)
    return -25;
  // A non-U0 fun may not be a bare statement: its value would be silently dropped.
  if (KernelPrsGlblFunDefSoft("I64 G(){return 1;}I64 F(){G();return 42;}F();") != -83)
    return -26;
  // Five args: a4 has no spill slot.
  if (KernelPrsGlblFunDefSoft("I64 Q(I64 a,I64 b,I64 c,I64 d,I64 e){return a;}I64 F(){return Q(1,2,3,4,5);}F();") != -72)
    return -27;
  // A U0 arg is not a value.
  if (KernelPrsGlblFunDefSoft("I64 G(U0 a){return 1;}I64 F(){return G(1);}F();") != -74)
    return -28;
  // Arity is still exact at four.
  if (KernelPrsGlblFunDefSoft("I64 Q(I64 a,I64 b,I64 c,I64 d){return a;}I64 F(){return Q(1,2,3);}F();") != -15)
    return -29;
  // File-scope storage is still I64 / U8 * / U8 [N] only — a `U32 g;` cell would need
  // a 4-byte ld/sd nobody emits.
  if (KernelPrsGlblFunDefSoft("U32 g;I64 F(){return 42;}F();") != -80)
    return -30;
  // Straight-line 'GA' / 'GP' / 'GF' / 'GM' shapes stay green after the type plants.
  r = KernelPrsGlblFunDefSoft("I64 G(I64 a,I64 b){return a-b;}I64 F(){return G(44,2);}F();");
  if (r != 42)
    return -31;
  r = KernelPrsGlblFunDefSoft("U8 b[4];U8 *p;I64 F(){p=b;*p=42;return *p;}F();");
  if (r != 42)
    return -32;
  r = KernelPrsGlblFunDefSoft("I64 F(){I64 t;t=40;while(t-42)t=t+1;return t;}F();");
  if (r != 42)
    return -33;
  r = KernelPrsGlblFunDefSoft("I64 g;I64 G(){return 40;}I64 F(){return G()+2;}F();");
  if (r != 42)
    return -34;
  kernel_soft_glbl_n = 0;
  // Off-disk proof: a BackLib_RV-shaped field packer read from RedSea at runtime.
  if (!KernelFileFind("A:/Compiler/SoftType.HC"))
    return -35;
  KernelMemSet(kernel_guest_src, 0, KERNEL_GUEST_SRC_MAX);
  sz = KernelSrcRead("A:/Compiler/SoftType.HC", kernel_guest_src, KERNEL_GUEST_SRC_MAX);
  if (sz <= 0)
    return -36;
  // Past one sector: KernelFileRead stops at a blk, so this is a multi-blk walk.
  if (sz <= 512)
    return -37;
  sum = KernelGuestSrcSumSoft(kernel_guest_src, sz);
  args[0] = sz;
  args[1] = sum;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestType src sz=%d sum=%X\n", 2, args);
  KernelUart(msg);
  if (kernel_guest_src[0] != '/' || kernel_guest_src[1] != '/')
    return -38;
  // Check 20 + Width 22, banked through the returned pointer as a byte.
  r = KernelPrsGlblFunDefSoft(kernel_guest_src);
  if (r != 42)
    return -39;
  code = kernel_fun_code_off;
  ic_hi = kernel_soft_ic_hi;
  lb_hi = kernel_soft_lb_hi;
  // One byte buffer, two cursors, one I64 cell; seven fun defs.
  if (kernel_soft_glbl_n != 4)
    return -40;
  if (kernel_soft_fun_n != 7)
    return -41;
  // The packed word really came from four differently weighted registers.
  if (kernel_soft_glbls[3].val != 26)
    return -42;
  // Both cursors hold the buffer address — the second one only through P's a0.
  if (kernel_soft_glbls[1].val != KernelGlblAddrSoft(0))
    return -43;
  if (kernel_soft_glbls[2].val != KernelGlblAddrSoft(0))
    return -44;
  // 42 was stored as a byte through the returned pointer, so a wrong tally would show
  // up in BIN storage as well as in the Call's answer.
  if (kernel_soft_glbls[0].arr[0] != 42)
    return -45;
  // Disassemble what was planted, one exact sequence per width. A single instruction
  // is not enough for any of them: `sltu a0,x0,a0` is also how `!=` ends, and
  // `slli/srli a0,a0,32` is also how an absolute address materialize ends — so each
  // gate pins the instruction that must follow.
  //   bool  sltu a0,x0,a0; ld ra,0(sp); addi sp,sp,frame — the Bool return narrowing
  //         sitting in the epilogue, where no cmp result ever is.
  //   u32   slli a0,a0,32; srli a0,a0,32; ld ra,0(sp) — 4 bytes wide and zero-
  //         extended. An I64 return emits neither word.
  //   nov   sd a0,0(t0); ld ra,0(sp); addi sp,sp,frame — a U0 tail: the epilogue
  //         directly follows a store, with no value materialize in between. Every
  //         other return type puts something in a0 first.
  n_bool = KernelSoftScanSeq3Soft(kernel_fun_code, code, 0xFFFFFFFF, 0x00A03533, 0xFFFFFFFF, 0x00013083, 0x000FFFFF, 0x00010113);
  n_u32 = KernelSoftScanSeq3Soft(kernel_fun_code, code, 0xFFFFFFFF, 0x02051513, 0xFFFFFFFF, 0x02055513, 0xFFFFFFFF, 0x00013083);
  n_nov = KernelSoftScanSeq3Soft(kernel_fun_code, code, 0xFFFFFFFF, 0x00A2B023, 0xFFFFFFFF, 0x00013083, 0x000FFFFF, 0x00010113);
  args[0] = n_bool;
  args[1] = n_u32;
  args[2] = n_nov;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestType disasm bool=%d u32=%d nov=%d\n", 3, args);
  KernelUart(msg);
  // RvEncFits is the only Bool; RvEncBit31 the only U32; RvEncIType the only U0.
  if (n_bool != 1)
    return -46;
  if (n_u32 != 1)
    return -47;
  if (n_nov != 1)
    return -48;
  //   arg4  sd a1,16(sp); sd a2,24(sp); sd a3,32(sp) — the four-arg spill prologue.
  //   set4  addi a2,x0,imm; addi a3,x0,imm; jal ra — the caller really loads the
  //         third and fourth argument registers immediately before the call.
  //   u32a  slli a0,a0,32; srli a0,a0,32; sd a0,8(sp) — the same U32 narrowing on the
  //         way *in*, ahead of the spill, so the body's ld sees an in-range value.
  n_arg4 = KernelSoftScanSeq3Soft(kernel_fun_code, code, 0xFFFFFFFF, 0x00B13823, 0xFFFFFFFF, 0x00C13C23, 0xFFFFFFFF, 0x02D13023);
  n_set4 = KernelSoftScanSeq3Soft(kernel_fun_code, code, 0x000FFFFF, 0x00613, 0x000FFFFF, 0x00693, 0x00000FFF, 0x000000EF);
  n_u32a = KernelSoftScanSeq3Soft(kernel_fun_code, code, 0xFFFFFFFF, 0x02051513, 0xFFFFFFFF, 0x02055513, 0xFFFFFFFF, 0x00A13423);
  args[0] = n_arg4;
  args[1] = n_set4;
  args[2] = n_u32a;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestType disasm arg4=%d set4=%d u32a=%d\n", 3, args);
  KernelUart(msg);
  // RvEncIType is the only four-arg fun and RvEncCheck its only call site.
  if (n_arg4 != 1)
    return -49;
  if (n_set4 != 1)
    return -50;
  // RvEncFits is the only fun with a U32 argument.
  if (n_u32a != 1)
    return -51;
  // Measured headroom, not assumed: emitted bytes / IC / labels vs the caps.
  args[0] = code;
  args[1] = ic_hi;
  args[2] = lb_hi;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestType code=%d/1024 ic=%d/32 lb=%d/8\n", 3, args);
  KernelUart(msg);
  // The frame-local table is what arity 4 actually squeezes: lc is the deepest count
  // any one body reached (four args plus two working locals).
  args[0] = lc_hi;
  args[1] = kernel_soft_fun_n;
  args[2] = kernel_soft_glbl_n;
  KernelMemSet(msg, 0, KERNEL_SPRINT_CAP);
  KernelStrPrintJoin(msg, "Kernel.BIN: GuestType caps lc=%d/8 fun=%d/8 glbl=%d/4\n", 3, args);
  KernelUart(msg);
  kernel_soft_glbl_n = 0;
  return 0x4754;
  // 'GT'
}
// Soft Call: full ENTER ownership in BIN — StrLen/64KiB heap/MemCpy + VirtioBlkInit +
// Cap/Read/Write + RedSea mount/FileWrite/FileFind/Load/Call/Validate + TaskSoft +
// HashSoft + PrintSoft + YieldSoft + JumpSoft + ExeSoft + MakeSoft + SeedSoft +
// SvcSoft + KernSoft + StartSoft + AdamSoft + DateSoft + QSortSoft + KeyDevSoft +
// ExceptSoft + MemSoft + StrUtilSoft + FifoSoft + QueVectSoft + RandSoft +
// ScanFlagsSoft + CompressSoft + KLoadSoft + MakeMemSoft + PhysMemSoft +
// LoadMainSoft + Hash2Soft + DataHeapSoft + LoadAbsSoft + DirAbsSoft + StartOSSoft +
// ExePutSSoft + CmpSoft + LexStmtSoft + PrsOptSoft + ParenSoft + IdentSoft +
// AssignSoft + FunDefSoft + FunBodySoft + FunCallSoft + AbiSoft + CocSoft + BrSoft +
// ElseSoft + ForSoft + CmpBrSoft + CmpSrcSoft + PrsSrcSoft + LexSrcSoft + IcSrcSoft +
// MulSrcSoft + SubSrcSoft + OptSrcSoft + CocSrcSoft + BrSrcSoft + ElseSrcSoft +
// ForSrcSoft + CallIcSoft + GlblMemSoft + GuestCmpSoft + GuestLocalSoft +
// GuestFlowSoft + GuestPtrSoft + GuestArgSoft + GuestTypeSoft.
public I64 KernelSoftCall()
{
  I64 n, w, cap, st, m, cr, rn, dh, la, dn, so, ep, cc, lb, po, pn, id, as, fd, fb, fc, ab, co, br, el, fr;
  U8 *p;
  I64 bfh;
  KernelUart("Kernel.BIN: KernelSoftCall (BIN ENTER StrLen/freelist64K/MemCpy+VBlkInit+mount/FS/Call)...\n");
  KernelArenaReset;
  n = KernelStrLen("KE");
  if (n != 2)
    return -1;
  p = KernelArenaAlloc(16);
  if (!p)
    return -2;
  p[0] = 'K';
  p[1] = 'S';
  p[2] = 0;
  if (KernelStrLen(p) != 2)
    return -3;
  KernelMemCpy(kernel_softcall_dst, p, 3);
  if (kernel_softcall_dst[0] != 'K' || kernel_softcall_dst[1] != 'S')
    return -5;
  // First-mount ownership: full VirtioBlkInit + RedSea boot (thin deferred BlkDevAdd).
  KernelUart("Kernel.BIN: SoftCall first RVMountVirtioDisk...\n");
  m = KernelMountVirtioDisk();
  if (m != 0x4B4D)
    return -14;
  w = KernelFileWrite("A:/Kernel/SOFTFW.OK", "FW", 2);
  if (w < 2)
    return -4;
  if (!KernelFileFind("A:/Kernel/SOFTFW.OK"))
    return -6;
  if (!KernelFileFind("A:/Kernel/LoadProbe.BIN"))
    return -7;
  bfh = KernelLoad("A:/Kernel/LoadProbe.BIN");
  if (!bfh)
    return -8;
  KernelUart("Kernel.BIN: SoftCall Load+Call LoadProbe...\n");
  cr = KernelCallExport(bfh(U8 *), "LoadProbe");
  if (cr != 7)
    return -17;
  w = KernelFileWrite("A:/Kernel/CALL.OK", "CL", 2);
  if (w < 2)
    return -18;
  // FS round-trip: FileRead back SoftCall marker.
  rn = KernelFileRead("A:/Kernel/SOFTFW.OK", kernel_softcall_rbuf, 8);
  if (rn != 2 || kernel_softcall_rbuf[0] != 'F' || kernel_softcall_rbuf[1] != 'W')
    return -19;
  w = KernelFileWrite("A:/Kernel/FSRD.OK", "RD", 2);
  if (w < 2)
    return -20;
  KernelUart("Kernel.BIN: SoftCall VirtioBlk Capacity/Read + RedSeaValidate...\n");
  cap = KernelVBlkCapacity();
  if (cap <= 0)
    return -9;
  st = KernelVBlkRead(0, kernel_softcall_sec);
  if (st)
    return -11;
  if (!KernelRedSeaBootOk(kernel_softcall_sec))
    return -12;
  if (!KernelRedSeaValidate())
    return -13;
  w = KernelFileWrite("A:/Kernel/BLKIO.OK", "BK", 2);
  if (w < 2)
    return -15;
  if (!KernelFileFind("A:/Kernel/BLKIO.OK"))
    return -16;
  // TaskInit+Spawn ring + JobQue JOBT_CALL + JobRunOne (past thin Task/Job stubs).
  // SoftCall-prove only (no TASK.OK FileWrite — post-TaskSoft FileWrite failed 2×).
  KernelUart("Kernel.BIN: SoftCall TaskSoft (Init+Spawn+JobRunOne)...\n");
  if (KernelTaskSoft() != 0x4B4A) {
    KernelUart("Kernel.BIN: SoftCall TaskSoft FAILED\n");
    return -26;
  }
  // After Cap/Read: keep TrapCtx mtvec (boot ownership; InitLite proved GPR+ecall).
  KernelUart("Kernel.BIN: SoftCall TrapOwn (TrapCtx stay)...\n");
  if (KernelTrapOwn() != 0x4B4F)
    return -21;
  // Live MSIP → SoftCall HolyC clears MSIP+mret; mscratch==soft IRQ cause.
  KernelUart("Kernel.BIN: SoftCall TrapIRQ (CLINT MSIP)...\n");
  if (KernelTrapIrq() != 0x4B51)
    return -22;
  // Live timer → SoftCall HolyC clears mtimecmp; mscratch==timer.
  KernelUart("Kernel.BIN: SoftCall TrapTimer (CLINT mtimecmp)...\n");
  if (KernelTrapTimer() != 0x4B4D)
    return -23;
  // Live MSIP → TrapCtx SoftCalls HolyC KernelTrapDispatch → HIT 'KH'.
  KernelUart("Kernel.BIN: SoftCall TrapDisp (HolyC hook)...\n");
  if (KernelTrapDisp() != 0x4B44)
    return -24;
  // HashStr+TableNew+Add+Find (past thin Hash stubs). SoftCall-prove only.
  // TrapPlic SoftCall deferred — host-fed hangs before armed (not fought here).
  KernelUart("Kernel.BIN: SoftCall HashSoft (TableNew+Add+Find)...\n");
  if (KernelHashSoft() != 0x4B46) {
    KernelUart("Kernel.BIN: SoftCall HashSoft FAILED\n");
    return -27;
  }
  // StrPrintJoin lite %s/%d/%X/%c (past thin StrPrint stubs). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall PrintSoft (StrPrintJoin %s/%d/%X)...\n");
  if (KernelPrintSoft() != 0x4B50) {
    KernelUart("Kernel.BIN: SoftCall PrintSoft FAILED\n");
    return -28;
  }
  // Yield + HolyRVCtxSw on CKernelTask.rsp (past thin Sched stubs). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall YieldSoft (CtxSw+next_task)...\n");
  if (KernelYieldSoft() != 0x4B59) {
    KernelUart("Kernel.BIN: SoftCall YieldSoft FAILED\n");
    return -29;
  }
  // LoadBuf→HashAdd→HashFind Jump path (mirrors thin Jump). SoftCall re-prove in BIN.
  // No embed @0x81000000 → JumpSoft -1 (phase3 heap Load); thin always embeds.
  KernelUart("Kernel.BIN: SoftCall JumpSoft (LoadBuf+HashFind Entry/Probe)...\n");
  
  {
    I64 jr;
    jr = KernelJumpSoft();
    if (jr == -1)
      KernelUart("Kernel.BIN: SoftCall JumpSoft skip (no embed @0x81000000).\n");
    else if (jr != 0x4B4C) {
      KernelUart("Kernel.BIN: SoftCall JumpSoft FAILED\n");
      return -30;
    }
  }
  // RedSea Load→HashFind→Call (ExeFile-shaped; no Cmp). Past linear CallExport.
  KernelUart("Kernel.BIN: SoftCall ExeSoft (Load+HashFind LoadProbe)...\n");
  if (KernelExeSoft() != 0x4B42) {
    KernelUart("Kernel.BIN: SoftCall ExeSoft FAILED\n");
    return -31;
  }
  // Product MakeOS Tiny.BIN Load→HashFind→Call (StartOS-shaped; no Cmp).
  if (!KernelFileFind("A:/MakeOS/Tiny.BIN")) {
    KernelUart("Kernel.BIN: SoftCall MakeSoft skip (no Tiny.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall MakeSoft (Load+HashFind MakeOSProbe)...\n");
    if (KernelMakeSoft() != 0x4B4E) {
      KernelUart("Kernel.BIN: SoftCall MakeSoft FAILED\n");
      return -32;
    }
  }
  // Product Runtime Seed.BIN Load→HashFind→Call (StartOS Seed chain tip; no Cmp).
  if (!KernelFileFind("A:/Runtime/Seed.BIN")) {
    KernelUart("Kernel.BIN: SoftCall SeedSoft skip (no Seed.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall SeedSoft (Load+HashFind RuntimeSeedInit)...\n");
    if (KernelSeedSoft() != 0x4B52) {
      KernelUart("Kernel.BIN: SoftCall SeedSoft FAILED\n");
      return -33;
    }
  }
  // Product Runtime Svc.BIN Load→HashFind→Call (StartOS Svc chain tip; no Cmp).
  if (!KernelFileFind("A:/Runtime/Svc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall SvcSoft skip (no Svc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall SvcSoft (Load+HashFind RuntimeSvcProbe)...\n");
    if (KernelSvcSoft() != 0x4B43) {
      KernelUart("Kernel.BIN: SoftCall SvcSoft FAILED\n");
      return -34;
    }
  }
  // Product Runtime Kern.BIN Load→HashFind→Call (StartOS Kern chain tip; no Cmp).
  if (!KernelFileFind("A:/Runtime/Kern.BIN")) {
    KernelUart("Kernel.BIN: SoftCall KernSoft skip (no Kern.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall KernSoft (Load+HashFind KernInit)...\n");
    if (KernelKernSoft() != 0x4B4B) {
      KernelUart("Kernel.BIN: SoftCall KernSoft FAILED\n");
      return -35;
    }
  }
  // StartOS-shaped multi-BIN: Seed→Svc→Kern in one SoftCall (no Cmp).
  if (!KernelFileFind("A:/Runtime/Seed.BIN") || !KernelFileFind("A:/Runtime/Svc.BIN") || !KernelFileFind("A:/Runtime/Kern.BIN")) {
    KernelUart("Kernel.BIN: SoftCall StartSoft skip (need Seed+Svc+Kern).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall StartSoft (Seed→Svc→Kern)...\n");
    if (KernelStartSoft() != 0x4B55) {
      KernelUart("Kernel.BIN: SoftCall StartSoft FAILED\n");
      return -36;
    }
  }
  // Product Adam/StartOS.BIN Load→HashFind→Call (phase3 StartOS needle; no Cmp).
  if (!KernelFileFind("A:/Adam/StartOS.BIN")) {
    KernelUart("Kernel.BIN: SoftCall AdamSoft skip (no StartOS.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall AdamSoft (Load+HashFind StartOSProbe)...\n");
    if (KernelAdamSoft() != 0x4B41) {
      KernelUart("Kernel.BIN: SoftCall AdamSoft FAILED\n");
      return -37;
    }
  }
  // KDate calendar + Goldfish RTC Now (past thin KThinDateStubs). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall DateSoft (KDate+RTC Now)...\n");
  if (KernelDateSoft() != 0x4B47) {
    KernelUart("Kernel.BIN: SoftCall DateSoft FAILED\n");
    return -38;
  }
  // QSortI64 (past thin KThinQSortStubs). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall QSortSoft (QSortI64 asc)...\n");
  if (KernelQSortSoft() != 0x4B4F) {
    KernelUart("Kernel.BIN: SoftCall QSortSoft FAILED\n");
    return -39;
  }
  // KeyDev StdOut chain + CtrlAltCB (past thin KThinKeyDevStubs). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall KeyDevSoft (PutKey/PutS+CtrlAlt)...\n");
  if (KernelKeyDevSoft() != 0x4B57) {
    KernelUart("Kernel.BIN: SoftCall KeyDevSoft FAILED\n");
    return -40;
  }
  // SysTry/throw/PutExcept queue (past thin PutExcept stub; no x86 asm). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall ExceptSoft (SysTry/throw/PutExcept)...\n");
  if (KernelExceptSoft() != 0x4B5A) {
    KernelUart("Kernel.BIN: SoftCall ExceptSoft FAILED\n");
    return -41;
  }
  // HeapCtrl+MAlloc (past thin KThinMemStubs; no MemPag/BlkPool). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall MemSoft (HeapCtrl+MAlloc/Free/MSize)...\n");
  if (KernelMemSoft() != 0x4B48) {
    KernelUart("Kernel.BIN: SoftCall MemSoft FAILED\n");
    return -42;
  }
  // StrUtil/MStrUtil (past thin KThinStrUtilStubs; path normalize). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall StrUtilSoft (StrUtil/MStrUtil path)...\n");
  if (KernelStrUtilSoft() != 0x5355) {
    KernelUart("Kernel.BIN: SoftCall StrUtilSoft FAILED\n");
    return -43;
  }
  // FifoU8/I64 (past thin MapFat Fifo stubs; Serial gated empty). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall FifoSoft (FifoU8/I64 ring)...\n");
  if (KernelFifoSoft() != 0x5346) {
    KernelUart("Kernel.BIN: SoftCall FifoSoft FAILED\n");
    return -44;
  }
  // QueVectU8 (past thin MapFat QueVect stubs; Lex shape). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall QueVectSoft (QueVectU8 New/Put/Get)...\n");
  if (KernelQueVectSoft() != 0x5156) {
    KernelUart("Kernel.BIN: SoftCall QueVectSoft FAILED\n");
    return -45;
  }
  // Rand/Seed LCG (past thin MapFat Rand* stubs; no Fs/GetTSC). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall RandSoft (Seed+LCG RandI64)...\n");
  if (KernelRandSoft() != 0x524E) {
    KernelUart("Kernel.BIN: SoftCall RandSoft FAILED\n");
    return -46;
  }
  // ScanFlags/LstMatch/StrPrintFlags (past thin MapFat ScanFlags stubs). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall ScanFlagsSoft (LstMatch+ScanFlags+/-)...\n");
  if (KernelScanFlagsSoft() != 0x5343) {
    KernelUart("Kernel.BIN: SoftCall ScanFlagsSoft FAILED\n");
    return -47;
  }
  // CompressBuf/ExpandBuf Arc (past thin Compress gate). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall CompressSoft (CompressBuf/ExpandBuf)...\n");
  if (KernelCompressSoft() != 0x434D) {
    KernelUart("Kernel.BIN: SoftCall CompressSoft FAILED\n");
    return -48;
  }
  // LoadPass1 import+ABS (past JumpSoft export-only). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall KLoadSoft (LoadPass1 import+ABS)...\n");
  if (KernelKLoadSoft() != 0x4C44) {
    KernelUart("Kernel.BIN: SoftCall KLoadSoft FAILED\n");
    return -49;
  }
  // MemPag/BlkPool stock FREE_PAG_HASH=0x100 (past thin KThinMemStubs). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall MakeMemSoft (MemPag FREE_PAG=0x100)...\n");
  if (KernelMakeMemSoft() != 0x4D4D) {
    KernelUart("Kernel.BIN: SoftCall MakeMemSoft FAILED\n");
    return -50;
  }
  // BlkPoolsInit+MemPageTable+MemPhysical lite (past MakeMemSoft). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall PhysMemSoft (BlkPoolsInit+MemPageTable+Mem32Dev)...\n");
  if (KernelPhysMemSoft() != 0x504D) {
    KernelUart("Kernel.BIN: SoftCall PhysMemSoft FAILED\n");
    return -51;
  }
  // CODE_HEAP+MAIN+FileRead LoadPass (past KLoadSoft import+ABS). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall LoadMainSoft (CODE_HEAP+MAIN+FileRead)...\n");
  if (KernelLoadMainSoft() != 0x4C4D) {
    KernelUart("Kernel.BIN: SoftCall LoadMainSoft FAILED\n");
    return -52;
  }
  // free_pag_hash2 stock 55 SoftCall-lite (past MakeMemSoft FREE_PAG=0x100). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall Hash2Soft (free_pag_hash2 stock 55)...\n");
  if (KernelHash2Soft() != 0x4832) {
    KernelUart("Kernel.BIN: SoftCall Hash2Soft FAILED\n");
    return -53;
  }
  // DATA_HEAP+ZEROED_*+ExtDft.Z (past LoadMainSoft CODE_HEAP+MAIN). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall DataHeapSoft (DATA_HEAP+ZEROED+ExtDft.Z)...\n");
  dh = KernelDataHeapSoft();
  if (dh != 0x4448) {
    KernelUart("Kernel.BIN: SoftCall DataHeapSoft FAILED\n");
    return -54;
  }
  // FileNameAbs+module_align+MODULE LoadPass (past DataHeapSoft ExtDft.Z). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall LoadAbsSoft (FileNameAbs+module_align)...\n");
  la = KernelLoadAbsSoft();
  if (la != 0x4C41) {
    // Fixed needles for UART dig (host AOT '.'-literal quirk → historical code=-30).
    if (la == -30)
      KernelUart("Kernel.BIN: SoftCall LoadAbsSoft FAILED code=-30\n");
    else if (la == -31)
      KernelUart("Kernel.BIN: SoftCall LoadAbsSoft FAILED code=-31\n");
    else if (la == -32)
      KernelUart("Kernel.BIN: SoftCall LoadAbsSoft FAILED code=-32\n");
    else
      KernelUart("Kernel.BIN: SoftCall LoadAbsSoft FAILED\n");
    return -55;
  }
  // DirNameAbs parents + FUF_Z_OR_NOT_Z + MAlloc ExtDft (past LoadAbsSoft). SoftCall-prove only.
  KernelUart("Kernel.BIN: SoftCall DirAbsSoft (DirNameAbs parents+Z+ExtDft)...\n");
  dn = KernelDirAbsSoft();
  if (dn != 0x444E) {
    KernelUart("Kernel.BIN: SoftCall DirAbsSoft FAILED\n");
    return -56;
  }
  // Full StartOS Load chain without Mac phase3.elf Cmp (DirAbs path + Adam + StartSoft).
  if (!KernelFileFind("A:/Adam/StartOS.BIN") || !KernelFileFind("A:/Runtime/Seed.BIN") || !KernelFileFind("A:/Runtime/Svc.BIN") || !KernelFileFind("A:/Runtime/Kern.BIN")) {
    KernelUart("Kernel.BIN: SoftCall StartOSSoft skip (need StartOS+Seed+Svc+Kern).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall StartOSSoft (DirAbs+Adam+StartSoft no phase3 Cmp)...\n");
    so = KernelStartOSSoft();
    if (so != 0x534F) {
      KernelUart("Kernel.BIN: SoftCall StartOSSoft FAILED\n");
      return -57;
    }
  }
  // SoftCall-lite CmpCtrl+ExePutS ("40+2;"→42) — past StartOSSoft; no full Compiler.BIN.
  KernelUart("Kernel.BIN: SoftCall ExePutSSoft (CmpCtrl+ExePutS 40+2)...\n");
  ep = KernelExePutSSoft();
  if (ep != 0x4550) {
    KernelUart("Kernel.BIN: SoftCall ExePutSSoft FAILED\n");
    return -58;
  }
  // SoftCall-lite MakeOS CmpWrite → SoftCmp.BIN → Load+Call (past ExePutSSoft).
  if (!KernelFileFind("A:/MakeOS/Tiny.BIN")) {
    KernelUart("Kernel.BIN: SoftCall CmpSoft skip (need MakeOS/).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall CmpSoft (CmpWrite SoftCmp.BIN Load+Call)...\n");
    cc = KernelCmpSoft();
    if (cc != 0x4343) {
      KernelUart("Kernel.BIN: SoftCall CmpSoft FAILED\n");
      return -59;
    }
  }
  // SoftCall-lite LexStmt2Bin emit+Call ("40+2;"→42) — past CmpSoft; no Prs/Opt.
  KernelUart("Kernel.BIN: SoftCall LexStmtSoft (LexStmt2Bin emit+Call 40+2)...\n");
  lb = KernelLexStmtSoft();
  if (lb != 0x4C42) {
    KernelUart("Kernel.BIN: SoftCall LexStmtSoft FAILED\n");
    return -60;
  }
  // SoftCall-lite Prs/Opt (* + precedence) → emit+Call — past LexStmtSoft; no Compiler.BIN.
  KernelUart("Kernel.BIN: SoftCall PrsOptSoft (Prs/Opt emit+Call 6*7)...\n");
  po = KernelPrsOptSoft();
  if (po != 0x504F) {
    KernelUart("Kernel.BIN: SoftCall PrsOptSoft FAILED\n");
    return -61;
  }
  // SoftCall-lite paren + IC emit beyond fold — past PrsOptSoft; no fun-def.
  KernelUart("Kernel.BIN: SoftCall ParenSoft (paren+IC emit (2+5)*8)...\n");
  pn = KernelParenSoft();
  if (pn != 0x504E) {
    KernelUart("Kernel.BIN: SoftCall ParenSoft FAILED\n");
    return -62;
  }
  // SoftCall-lite local/ident IC — past ParenSoft; AssignSoft owns PrsStmt assign.
  KernelUart("Kernel.BIN: SoftCall IdentSoft (local/ident IC x+2)...\n");
  id = KernelIdentSoft();
  if (id != 0x4944) {
    KernelUart("Kernel.BIN: SoftCall IdentSoft FAILED\n");
    return -63;
  }
  // SoftCall-lite PrsStmt assign — past IdentSoft; FunDefSoft owns fun-def tip.
  KernelUart("Kernel.BIN: SoftCall AssignSoft (PrsStmt assign x=40;x+2)...\n");
  as = KernelAssignSoft();
  if (as != 0x4153) {
    KernelUart("Kernel.BIN: SoftCall AssignSoft FAILED\n");
    return -64;
  }
  // SoftCall-lite fun-def + return + Call — past AssignSoft; FunBodySoft owns multi-stmt/args.
  KernelUart("Kernel.BIN: SoftCall FunDefSoft (I64 F(){return 40+2;}F())...\n");
  fd = KernelFunDefSoft();
  if (fd != 0x4644) {
    KernelUart("Kernel.BIN: SoftCall FunDefSoft FAILED\n");
    return -65;
  }
  // SoftCall-lite multi-stmt + locals-in-fun + I64 arg — past FunDefSoft; FunCallSoft owns multi-arg/call-Expr.
  KernelUart("Kernel.BIN: SoftCall FunBodySoft (I64 F(){x=40;return x+2;}F())...\n");
  fb = KernelFunBodySoft();
  if (fb != 0x4642) {
    KernelUart("Kernel.BIN: SoftCall FunBodySoft FAILED\n");
    return -66;
  }
  // SoftCall-lite multi-arg + call-Expr — past FunBodySoft; AbiSoft owns ABI/a0 frame.
  KernelUart("Kernel.BIN: SoftCall FunCallSoft (I64 F(I64 a,I64 b){return a+b;}F(40,2))...\n");
  fc = KernelFunCallSoft();
  if (fc != 0x4643) {
    KernelUart("Kernel.BIN: SoftCall FunCallSoft FAILED\n");
    return -67;
  }
  // SoftCall-lite ABI a0 frame — past FunCallSoft; CocSoft owns COC multi-stmt emit.
  KernelUart("Kernel.BIN: SoftCall AbiSoft (I64 F(I64 a){return a+2;}F(40) a0 frame)...\n");
  ab = KernelAbiSoft();
  if (ab != 0x4142) {
    KernelUart("Kernel.BIN: SoftCall AbiSoft FAILED\n");
    return -68;
  }
  // SoftCall-lite COC multi-stmt emit — past AbiSoft; BrSoft owns if/while BR.
  KernelUart("Kernel.BIN: SoftCall CocSoft (I64 F(){x=40;return x+2;}F() COC ASSIGN)...\n");
  co = KernelCocSoft();
  if (co != 0x434F) {
    KernelUart("Kernel.BIN: SoftCall CocSoft FAILED\n");
    return -69;
  }
  // SoftCall-lite if/while BR emit — past CocSoft; ElseSoft owns else.
  KernelUart("Kernel.BIN: SoftCall BrSoft (I64 F(){x=0;if(1)x=42;return x;}F() BR)...\n");
  br = KernelBrSoft();
  if (br != 0x4252) {
    KernelUart("Kernel.BIN: SoftCall BrSoft FAILED\n");
    return -70;
  }
  // SoftCall-lite if/else emit — past BrSoft; ForSoft owns for; full Compiler.BIN still ceiling.
  KernelUart("Kernel.BIN: SoftCall ElseSoft (I64 F(){x=0;if(1)x=42;else x=0;return x;}F() EL)...\n");
  el = KernelElseSoft();
  if (el != 0x454C) {
    KernelUart("Kernel.BIN: SoftCall ElseSoft FAILED\n");
    return -71;
  }
  // SoftCall-lite for emit — past ElseSoft; CmpBrSoft owns relational cmp-BR; full Compiler.BIN still ceiling.
  KernelUart("Kernel.BIN: SoftCall ForSoft (I64 F(){for(x=40;x-42;x=x+1)y=0;return x;}F() FR)...\n");
  fr = KernelForSoft();
  if (fr != 0x4652) {
    KernelUart("Kernel.BIN: SoftCall ForSoft FAILED\n");
    return -72;
  }
  // SoftCall-lite relational cmp-BR — past ForSoft; CmpSrcSoft owns multi-fun slice Load.
  KernelUart("Kernel.BIN: SoftCall CmpBrSoft (I64 F(){x=0;if(x<1)x=42;return x;}F() CB)...\n");
  fr = KernelCmpBrSoft();
  if (fr != 0x4342) {
    KernelUart("Kernel.BIN: SoftCall CmpBrSoft FAILED\n");
    return -73;
  }
  // SoftCall Load host-AOT multi-fun slice — past CmpBrSoft (no SoftCall-lite Lex growth).
  if (!KernelFileFind("A:/MakeOS/SoftCmpSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall CmpSrcSoft skip (need SoftCmpSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall CmpSrcSoft (Load SoftCmpSrc.BIN SoftCmpSrcProbe CS)...\n");
    fr = KernelCmpSrcSoft();
    if (fr != 0x4353) {
      KernelUart("Kernel.BIN: SoftCall CmpSrcSoft FAILED\n");
      return -74;
    }
  }
  // SoftCall Load host-AOT Prs-shaped glbl+multi-fun fold — past CmpSrcSoft.
  if (!KernelFileFind("A:/MakeOS/SoftPrsSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall PrsSrcSoft skip (need SoftPrsSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall PrsSrcSoft (Load SoftPrsSrc.BIN SoftPrsSrcProbe PR)...\n");
    fr = KernelPrsSrcSoft();
    if (fr != 0x5052) {
      KernelUart("Kernel.BIN: SoftCall PrsSrcSoft FAILED\n");
      return -75;
    }
  }
  // SoftCall Load host-AOT LexStmt2Bin-shaped digit+op peel — past PrsSrcSoft.
  if (!KernelFileFind("A:/MakeOS/SoftLexSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall LexSrcSoft skip (need SoftLexSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall LexSrcSoft (Load SoftLexSrc.BIN SoftLexSrcProbe LX)...\n");
    fr = KernelLexSrcSoft();
    if (fr != 0x4C58) {
      KernelUart("Kernel.BIN: SoftCall LexSrcSoft FAILED\n");
      return -76;
    }
  }
  // SoftCall Load host-AOT IC plant+emit beyond Lex peel — past LexSrcSoft.
  if (!KernelFileFind("A:/MakeOS/SoftIcSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall IcSrcSoft skip (need SoftIcSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall IcSrcSoft (Load SoftIcSrc.BIN SoftIcSrcProbe IC)...\n");
    fr = KernelIcSrcSoft();
    if (fr != 0x4943) {
      KernelUart("Kernel.BIN: SoftCall IcSrcSoft FAILED\n");
      return -77;
    }
  }
  // SoftCall Load host-AOT MUL IC plant+emit beyond IMM/ADD SoftIcSrc.
  if (!KernelFileFind("A:/MakeOS/SoftMulSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall MulSrcSoft skip (need SoftMulSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall MulSrcSoft (Load SoftMulSrc.BIN SoftMulSrcProbe MU)...\n");
    fr = KernelMulSrcSoft();
    if (fr != 0x4D55) {
      KernelUart("Kernel.BIN: SoftCall MulSrcSoft FAILED\n");
      return -78;
    }
  }
  // SoftCall Load host-AOT SUB IC plant+emit beyond IMM/MUL SoftMulSrc.
  if (!KernelFileFind("A:/MakeOS/SoftSubSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall SubSrcSoft skip (need SoftSubSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall SubSrcSoft (Load SoftSubSrc.BIN SoftSubSrcProbe SB)...\n");
    fr = KernelSubSrcSoft();
    if (fr != 0x5342) {
      KernelUart("Kernel.BIN: SoftCall SubSrcSoft FAILED\n");
      return -79;
    }
  }
  // SoftCall Load host-AOT OptPass fold beyond IMM/SUB SoftSubSrc.
  if (!KernelFileFind("A:/MakeOS/SoftOptSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall OptSrcSoft skip (need SoftOptSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall OptSrcSoft (Load SoftOptSrc.BIN SoftOptSrcProbe OP)...\n");
    fr = KernelOptSrcSoft();
    if (fr != 0x4F50) {
      KernelUart("Kernel.BIN: SoftCall OptSrcSoft FAILED\n");
      return -80;
    }
  }
  // SoftCall Load host-AOT COC multi-stmt ASSIGN beyond OptPass fold SoftOptSrc.
  if (!KernelFileFind("A:/MakeOS/SoftCocSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall CocSrcSoft skip (need SoftCocSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall CocSrcSoft (Load SoftCocSrc.BIN SoftCocSrcProbe OC)...\n");
    fr = KernelCocSrcSoft();
    if (fr != 0x4F43) {
      KernelUart("Kernel.BIN: SoftCall CocSrcSoft FAILED\n");
      return -81;
    }
  }
  // SoftCall Load host-AOT BR SoftCall Load beyond COC ASSIGN SoftCocSrc.
  if (!KernelFileFind("A:/MakeOS/SoftBrSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall BrSrcSoft skip (need SoftBrSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall BrSrcSoft (Load SoftBrSrc.BIN SoftBrSrcProbe BS)...\n");
    fr = KernelBrSrcSoft();
    if (fr != 0x4253) {
      KernelUart("Kernel.BIN: SoftCall BrSrcSoft FAILED\n");
      return -82;
    }
  }
  // SoftCall Load host-AOT if/else JMP join SoftCall Load beyond BR SoftBrSrc.
  if (!KernelFileFind("A:/MakeOS/SoftElseSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall ElseSrcSoft skip (need SoftElseSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall ElseSrcSoft (Load SoftElseSrc.BIN SoftElseSrcProbe ES)...\n");
    fr = KernelElseSrcSoft();
    if (fr != 0x4553) {
      KernelUart("Kernel.BIN: SoftCall ElseSrcSoft FAILED\n");
      return -83;
    }
  }
  // SoftCall Load host-AOT for-loop SoftCall Load beyond if/else SoftElseSrc.
  if (!KernelFileFind("A:/MakeOS/SoftForSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall ForSrcSoft skip (need SoftForSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall ForSrcSoft (Load SoftForSrc.BIN SoftForSrcProbe FS)...\n");
    fr = KernelForSrcSoft();
    if (fr != 0x4653) {
      KernelUart("Kernel.BIN: SoftCall ForSrcSoft FAILED\n");
      return -84;
    }
  }
  // SoftCall-lite inter-fun CALL IC (real RV jal ra) past ForSrcSoft Load.
  // Guarded on SoftForSrc.BIN like every probe above, because CallIcSoft's FIRST statement is
  // `if (KernelForSrcSoft() != 0x4653) return -1;` and GlblMemSoft chains through CallIcSoft in
  // turn. Without the guard both ran unconditionally after ForSrcSoft had been SKIPPED for a
  // missing file, and failed with r=-85 on a disk that simply does not carry the Soft*Src set --
  // which is every disk but the thin loader's, and that smoke runs AFTER this one.
  if (!KernelFileFind("A:/MakeOS/SoftForSrc.BIN")) {
    KernelUart("Kernel.BIN: SoftCall CallIcSoft skip (need SoftForSrc.BIN).\n");
    KernelUart("Kernel.BIN: SoftCall GlblMemSoft skip (need SoftForSrc.BIN).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall CallIcSoft (I64 G(){return 40;}I64 F(){return G()+2;}F() CL)...\n");
    fr = KernelCallIcSoft();
    if (fr != 0x434C) {
      KernelUart("Kernel.BIN: SoftCall CallIcSoft FAILED\n");
      return -85;
    }
    // SoftCall-lite glbl memory (lui/addi abs + ld/sd) past CallIcSoft.
    KernelUart("Kernel.BIN: SoftCall GlblMemSoft (I64 g;I64 F(){g=40;return g+2;}F() GM)...\n");
    fr = KernelGlblMemSoft();
    if (fr != 0x474D) {
      KernelUart("Kernel.BIN: SoftCall GlblMemSoft FAILED\n");
      return -86;
    }
  }
  // First real guest Cmp: HolyC source read off RedSea, Cmp'd in BIN, then Called.
  if (!KernelFileFind("A:/Compiler/SoftGlbl.HC")) {
    KernelUart("Kernel.BIN: SoftCall GuestCmpSoft skip (need A:/Compiler/SoftGlbl.HC).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall GuestCmpSoft (RedSea A:/Compiler/SoftGlbl.HC Cmp+Call GC)...\n");
    fr = KernelGuestCmpSoft();
    if (fr != 0x4743) {
      KernelUart("Kernel.BIN: SoftCall GuestCmpSoft FAILED\n");
      return -87;
    }
  }
  // Frame locals in a glbl-fun body, proven again off RedSea.
  if (!KernelFileFind("A:/Compiler/SoftLocal.HC")) {
    KernelUart("Kernel.BIN: SoftCall GuestLocalSoft skip (need A:/Compiler/SoftLocal.HC).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall GuestLocalSoft (RedSea A:/Compiler/SoftLocal.HC I64 l; frame GL)...\n");
    fr = KernelGuestLocalSoft();
    if (fr != 0x474C) {
      KernelUart("Kernel.BIN: SoftCall GuestLocalSoft FAILED\n");
      return -88;
    }
  }
  // if/while/for inside the merged glbl-fun body, proven again off RedSea.
  if (!KernelFileFind("A:/Compiler/SoftFlow.HC")) {
    KernelUart("Kernel.BIN: SoftCall GuestFlowSoft skip (need A:/Compiler/SoftFlow.HC).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall GuestFlowSoft (RedSea A:/Compiler/SoftFlow.HC if/while/for GF)...\n");
    fr = KernelGuestFlowSoft();
    if (fr != 0x4746) {
      KernelUart("Kernel.BIN: SoftCall GuestFlowSoft FAILED\n");
      return -89;
    }
  }
  // U8 * cursor + byte-width memory in the merged body, proven again off RedSea.
  if (!KernelFileFind("A:/Compiler/SoftPtr.HC")) {
    KernelUart("Kernel.BIN: SoftCall GuestPtrSoft skip (need A:/Compiler/SoftPtr.HC).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall GuestPtrSoft (RedSea A:/Compiler/SoftPtr.HC U8 * lbu/sb GP)...\n");
    fr = KernelGuestPtrSoft();
    if (fr != 0x4750) {
      KernelUart("Kernel.BIN: SoftCall GuestPtrSoft FAILED\n");
      return -90;
    }
  }
  // Fun args + calls that pass them (real a0/a1 + jal ra), proven again off RedSea.
  if (!KernelFileFind("A:/Compiler/SoftArg.HC")) {
    KernelUart("Kernel.BIN: SoftCall GuestArgSoft skip (need A:/Compiler/SoftArg.HC).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall GuestArgSoft (RedSea A:/Compiler/SoftArg.HC I64 a,I64 b a0/a1 GA)...\n");
    fr = KernelGuestArgSoft();
    if (fr != 0x4741) {
      KernelUart("Kernel.BIN: SoftCall GuestArgSoft FAILED\n");
      return -91;
    }
  }
  // Non-I64 return / arg widths + arity 4 (a2/a3), proven again off RedSea.
  if (!KernelFileFind("A:/Compiler/SoftType.HC")) {
    KernelUart("Kernel.BIN: SoftCall GuestTypeSoft skip (need A:/Compiler/SoftType.HC).\n");
  } else {
    KernelUart("Kernel.BIN: SoftCall GuestTypeSoft (RedSea A:/Compiler/SoftType.HC U0/Bool/U32 a2/a3 GT)...\n");
    fr = KernelGuestTypeSoft();
    if (fr != 0x4754) {
      KernelUart("Kernel.BIN: SoftCall GuestTypeSoft FAILED\n");
      return -92;
    }
  }
  return 0x4B53;
}

public I64 KernelEntry()
{
  I64 r, *stay, *eslot;
  r = KernelProbe();
  if (r != 42)
    return -1;
  r = KernelInitLite();
  if (r != 0x4B49)
    return -2;
  KernelUart("Kernel.BIN: KernelEntry handoff OK (InitLite).\n");
  // Thin loader Jump plants STAY; phase3 Call leaves slot 0 → return 0x4B45.
  stay = KERNEL_BIN_STAY_ADDR;
  if (stay && *stay == KERNEL_BIN_STAY_VAL) {
    // Publish Entry addr for thin Jump without HashFind (LoadBuf also plants).
    eslot = KERNEL_BIN_ENTRY_ADDR;
    *eslot = &KernelEntry;
    r = KernelSoftCall();
    if (r != 0x4B53) {
      KernelUart("Kernel.BIN: SoftCall FAILED in stay.\n");
      while (1)
        HLT;
    }
    KernelFileWrite("A:/Kernel/ENTRY.OK", "KE", 2);
    KernelFileWrite("A:/Kernel/THIN.OK", "OK", 2);
    KernelFileWrite("A:/Kernel/SOFT.OK", "KS", 2);
    KernelFileWrite("A:/Kernel/STAY.OK", "ST", 2);
    KernelUart("Kernel.BIN: SoftCall OK (BIN ENTER+VBlkInit+mount/FS/Call=0x4B53).\n");
    KernelUart("Kernel.BIN: stay (non-return).\n");
    while (1)
      HLT;
  }
  return 0x4B45;
}
