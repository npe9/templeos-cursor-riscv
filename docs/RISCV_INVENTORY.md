# RISC-V support inventory

A survey of *all* RISC-V knowledge in this TempleOS→RISC-V port, with the one
distinction the rest of the document is organized around:

> **"What compiles" ≠ "what can be assembled."**
> The HolyC compiler backend (`Compiler/*_RV.HC`) lowers HolyC to RISC-V machine
> code and can emit instructions from **I + M + A + F/D**. The inline `asm{}`
> assembler (`Compiler/Asm_RV.HC`) is a *separate, much smaller* hand-written
> parser that now accepts the **entire non-compressed rv64imafdc ISA** —
> I + M + A + F + D + FMA + Zicsr + privileged, with branches/jumps taking a
> numeric PC-relative offset *or* a label (either direction). It also assembles
> the **entire compressed (RVC) 16-bit** set — register/immediate forms, the
> immediate-scrambled jumps/branches (`c.j c.beqz c.bnez`, incl. label
> resolution), loads/stores (`c.ld c.sd c.lw c.sw`), CB-arith (`c.andi c.srli
> c.srai`), `c.addiw`, `c.lui`, sp-relative loads/stores + frame-adjust (`c.lwsp
> c.ldsp c.swsp c.sdsp c.addi16sp c.addi4spn`), and the float doublewords
> (`c.fld c.fsd c.fldsp c.fsdsp`) — all byte-verified vs GNU `-march=rv64imafdc`.
> `call` now assembles in both host and guest, but differently: the guest emits a
> PC-relative `auipc+jalr` pair to a **block-local label or numeric offset**, while the
> host resolves an **external function symbol** via `IC_CALL`. Every mnemonic is now
> assemblable; external-symbol `call` remains host-only.

The same instruction knowledge is duplicated across **three** places that do not
agree: the assembler (a parser), the disassembler (`Kernel/RVDisasm.HC`, a
formatter), and the documentation catalog (`bootstrap/seed/asm_doc.hc` +
`Kernel/RVExplore.HC`). The drift between them is catalogued in
[§7](#7-three-way-duplication--drift) and [Gaps & drift](#gaps--drift).

Originally a read-only survey; since updated alongside the 2026-09-15 assembler work
(guest branches/jumps, narrow ld/st, RV64D float, base pseudos; A-ext disasm decode;
the `RvAsmMergeDotSuffix` overflow fix). Evidence is cited as `file:line`.

---

## Headline findings

- The platform target is declared **`rv64imafdc` / `lp64d`** (`Kernel/RVAutoConf.HH:6-7`),
  and both the disassembler and the guest `asm{}` assembler (`Compiler/Asm_RV.HC`, used
  by the REPL / `make tos`) now cover **all of it plus the entire integer RVC set** — I + M + A + F +
  D + FMA + Zicsr + privileged, and the compressed 16-bit integer instructions (reg/imm,
  `c.j/c.beqz/c.bnez`, `c.ld/c.sd/c.lw/c.sw`, `c.andi/c.srli/c.srai`, `c.addiw`, `c.lui`,
  and sp-relative `c.lwsp/c.ldsp/c.swsp/c.sdsp` + `c.addi16sp/c.addi4spn`), via `AOTStoreCodeU16`. Guest
  branches/jumps take **either** a numeric even PC-relative byte offset (`beq a0,a1,8`)
  **or a label** in either direction (`loop: … bnez t0,loop`; `beq a0,a1,skip … skip:`).
  Backward labels resolve inline (`label_rip - aotc->rip`); forward labels emit a
  placeholder and are patched at block end (`RvAsmFixupResolve` in `PrsAsmBlk`, via
  `AOTStoreCodeU8At`) — a **block-local** fixup list, deliberately *not* the x86
  `asm_undef_hash` path (which writes contiguous displacements and can't express
  B/J-type's split immediate fields). The host `asm{}` parser (`host/parser.c`) is
  label-only and rejects numeric offsets; the guest accepting both is the remaining
  divergence. The guest now has `j` (= `jal x0,label`, numeric or label) and `call`
  (= `auipc ra,%pcrel_hi + jalr ra,%pcrel_lo`, block-local label or numeric offset,
  ±2GiB, its only 8-byte fixup); external-symbol `call` (host `IC_CALL`) stays host-only.
- **The assembler now covers the entire non-compressed rv64imafdc ISA.** Added since
  the 136-mnemonic survey, in five gated increments (commits `2c36f2f f8aac34 194eeb8
  d733cc3 a12253a` + F32 part 2): OP-32/word ops (`addiw slliw srliw sraiw addw subw
  sllw srlw sraw mulw divw divuw remw remuw`); base-I/M leftovers (`sltiu`, `mulh
  mulhsu mulhu`, full `fence pred,succ`, `sfence.vma`); D-ext completeness (`fsgnj.d`
  family, `fmin/fmax.d`, `fclass.d`, the full `fcvt` matrix incl. F32↔F64); FMA
  (`fmadd/fmsub/fnmsub/fnmadd`, `.d` and `.s`, the first R4-type); and the whole F
  single-precision extension (`flw/fsw`, arith, sign, min/max, compares, `fclass.s`,
  `fmv.x.w/fmv.w.x`, full single `fcvt` matrix). Every encoding is GNU byte-verified
  via `make asm-gnu-diff` (209 match cases) and functionally exercised in the guest
  REPL with a Disasm round-trip.
- **Naming:** new float ops use the real dotted RISC-V spellings (`fadd.d`, `fcvt.w.s`,
  `fmadd.s`); the 14 legacy dot-free names (`faddd fsubd fmuld fdivd fsqrtd fled fltd
  feqd fmvdx fmvxd fcvtld_{rtz,rdn,rmm} fcvtdl`) stay accepted. Two-dot mnemonics
  (`fcvt.<int>.<fmt>`) fold both suffixes via a looped dot-merge in each assembler.
- **The `AsmDoc`/`AsmList` catalog is 244 entries** (was 137), documenting every
  assemblable mnemonic with template + semantics. `call` now assembles in the guest for
  block-local targets (auipc+jalr); the only catalog entry the guest cannot assemble is
  host-only `lifp`.
- **RVC assembler — COMPLETE (increments 1-4):** the guest
  `asm{}` assembles every RVC instruction (integer + float), emitting real 16-bit words via
  `AOTStoreCodeU16` (aotc->rip advances by 2, so mixed 2/4-byte blocks stay
  byte-correct). Inc 1: reg/imm (`c.nop/c.ebreak/c.mv/c.add/c.li/c.addi/c.slli/c.jr/
  c.jalr/c.sub/c.and/c.or/c.xor`). Inc 2: immediate-scrambled `c.j/c.beqz/c.bnez` (numeric
  offset **or label** — backward inline, forward via a 2-byte CJ/CB fixup in
  `RvAsmFixupResolve`) and subset `c.ld/c.sd`. Inc 3: `c.lw/c.sw`, CB-arith
  (`c.andi/c.srli/c.srai`), `c.addiw`, `c.lui`, and sp-relative `c.lwsp/c.ldsp/c.swsp/
  c.sdsp` + `c.addi16sp/c.addi4spn`. Inc 4: float doublewords `c.fld/c.fsd` (f8-f15
  subset) and `c.fldsp/c.fsdsp` (full float reg). Every scrambled field-map was
  mechanically derived from GNU and validated over full operand ranges (15000+ checks),
  then byte-read-back in `repl-cmp.elf`; gated by `make rvc-asm-smoke`. RVC is complete;
  the disassembler decodes the same set.
- **A extension round-trips:** the assembler is the only hand-writing path for atomics,
  and the disassembler now decodes opcode `0x2F` (`lr/sc/amo*`, `.d`/`.w`) — so `U`/`Uf`
  round-trips the atomics you assemble (verified assemble→`Disasm` in the win REPL).
- **Fixed:** the `RvAsmMergeDotSuffix` dotted-suffix heap overflow — `PrsAsmRVIns` now
  allocates the mnemonic in a fixed 32-byte buffer (`RvAsmMnDup`) instead of
  `StrNew(StrLen+1)`, so appending `.d`/`.w` can no longer overrun (see
  [Gaps & drift](#gaps--drift)).
- The REPL exploration commands (`AsmList AsmDoc MemMap Mstatus Mcause Csr Uptime`) live
  in **`Kernel/RVExplore.HC`**, wired by `Compiler/RVExePubs.HC` — committed on `archive`
  (`51f19cf`, `409155d`, `abe75ab`).

---

## Extension coverage at a glance (the three-way answer)

| Extension | `asm{}` assembles | Codegen emits ("compiles") | Disassembler decodes |
|---|---|---|---|
| **RV64 I** (base) | **yes** — full OP/OP-IMM incl. `sltiu`, B-type branches + `jal`/`jr` (guest: numeric offset *or* label; host: label-only), all loads/stores `lb/lh/lbu/lhu/lwu/sb/sh`, full `fence pred,succ` + `fence.i`; guest has `j` + block-local `call` | yes | yes |
| **I OP-32 / word** (`addiw slliw srliw sraiw addw subw sllw srlw sraw`) | **yes** (`0x1B`/`0x3B`) | partial | **yes** (`0x1B` and `0x3B`) |
| **M** (`mul mulh mulhsu mulhu div divu rem remu` + `mulw divw divuw remw remuw`) | **yes** | yes | **yes** (incl. mul-high + word) |
| **A** (`lr/sc/amo*`, `.d` and `.w`) | **yes** | yes — `amo{or,and,xor}.d` (`BackB_RV.HC:142,145`) | **yes** (`0x2F` decoded, `RVDisasm.HC`) |
| **F** (single float) | **yes** — `flw/fsw`, arith/`fsqrt.s`, sign, `fmin/fmax.s`, compares, `fclass.s`, `fmv.x.w/fmv.w.x`, full `fcvt` matrix | via D path | **yes** (`0x53` .s f7 arms, `0x07`/`0x27` f3=2) |
| **D** (double float) | **yes** — arith/sqrt/sign/`fmin/fmax`/compares/`fclass.d`/moves + full `fcvt` matrix (int↔double, F32↔F64) + `fld/fsd` | **yes** — 29 emitters (`BackF_RV.HC:59-227`) | yes (`0x53`, `0x07`/`0x27`) |
| **Fused FMA** (`fmadd/fmsub/fnmsub/fnmadd`, `.d` and `.s`) | **yes** (R4-type, `0x43/0x47/0x4B/0x4F`) | no | **yes** |
| **Privileged** (`sfence.vma`, `mret/sret/wfi/…`) | **yes** (`sfence.vma [rs1[,rs2]]`) | n/a | **yes** |
| **Zicsr** (`csr*`) | yes (12 forms + 28 named CSRs) | no (only via `asm{}`) | yes (`0x73`) |
| **C** (compressed) | **yes — the ENTIRE RVC set** (integer reg/imm, `c.j/c.beqz/c.bnez` incl. labels, `c.ld/c.sd/c.lw/c.sw`, `c.andi/c.srli/c.srai`, `c.addiw`, `c.lui`, sp-relative `c.lwsp/c.ldsp/c.swsp/c.sdsp` + `c.addi16sp/c.addi4spn`, and float `c.fld/c.fsd/c.fldsp/c.fsdsp`), all GNU-verified | no | **yes** (`op & 3 != 3`) |
| **V** (vector) | no | no | no |

The whole non-compressed **rv64imafdc** ISA now assembles, disassembles, and is
documented in the `AsmDoc`/`AsmList` catalog — the three answers have converged.
New float ops use the real dotted RISC-V names (`fadd.d`, `fcvt.w.s`, `fmadd.s`, …);
the 14 legacy dot-free names (`faddd`, `fcvtld_rtz`, `fcvtdl`, …) remain accepted for
back-compat. Compressed (RVC) now assembles in full (integer + float); everything else in
rv64imafdc is hand-writable in `asm{}`.

---

## 1. Assembler — what `asm{}` accepts

Entry point `PrsAsmRVIns` (`Compiler/Asm_RV.HC:373`), reached from `Asm.HC:1067,1074`.
Each native RISC-V opcode is assembled directly (not translated from x86). Recognition
is a gate `RvAsmIsMn` (`Asm_RV.HC:22`) followed by a long `if`-chain of
`RvAsmStrEqI(mn,"…")` dispatch. `OpCodes.DD` (x86 tables) is **not** loaded;
`AsmHashLoad` soft-loads the HolyC keywords (`AsmInit.HC:103-108`).

Helper encoders: `RvAsmI/R/Load/Store/Jalr/U/A` (`Asm_RV.HC:258-292`), `RvAsmEmitLi`
(materializes wide immediates), `RvAsmMergeDotSuffix` (folds a following `.d`/`.w`/`.i`
token into the mnemonic). Register names via `RvAsmRegNum` (`Asm_RV.HC:34`: `x0-x31`,
ABI names `zero ra sp gp tp t0-t6 s0-s11 a0-a7 fp`). CSR *names* via `RvAsmCsrNum`
(`Asm_RV.HC:146`, 28 names → numbers; also usable as an immediate).

### 1a. Real (non-pseudo) encodings

| Group | Mnemonics | Notes |
|---|---|---|
| System (fixed word) | `ret nop wfi mret sret ecall ebreak` | `ret`=`jalr x0,ra,0`; `nop`=`addi x0,x0,0` |
| Fence | `fence pred,succ` (bare = iorw,iorw) + `fence.i`/`fencei` | i/o/r/w masks; host uses lookahead, guest the `;`/`}` boundary |
| U-type | `lui auipc` | 20-bit field, gas-compatible |
| OP-IMM (I) | `addi addiw andi ori xori slti sltiu slli srli srai slliw srliw sraiw` | word-imm shifts take 5-bit shamt |
| OP (R) | `add sub and or xor sll srl sra slt sltu` + word `addw subw sllw srlw sraw` | pure R-type; passing an immediate to `add`/`sub` raises a helpful `LexExcept` |
| M ext (R) | `mul mulh mulhsu mulhu div rem divu remu` + word `mulw divw divuw remw remuw` | funct7=1 (OP `0x33`) / OP-32 (`0x3B`) |
| Load (I) | `ld lw lwu lh lhu lb lbu` | f3 lb=0 lh=1 lw=2 ld=3 lbu=4 lhu=5 lwu=6 |
| Store (S) | `sd sw sh sb` | f3 sb=0 sh=1 sw=2 sd=3 |
| Jump (I) | `jalr` | short form `jalr rs` → `jalr ra,0(rs)` |
| Jump (J) | `jal jr j call` | `jal rd,off\|label` / `jal off\|label`(→ra) / `j off\|label`(→`jal x0`) / `jr rs`(→`jalr x0`) / `call target`(→`auipc ra + jalr ra`, block-local); target numeric or label |
| Branch (B) | `beq bne blt bge bltu bgeu beqz bnez` | numeric even byte offset (`beq a0,a1,8`) **or a label**, either direction (`loop: … bnez t0,loop`) |
| Zicsr | `csrr csrw csrs csrc csrrw csrrs csrrc csrrwi csrrsi csrrci csrwi csrsi csrci` | + `rdtime` (`csrrs rd,time,x0`) |
| A: LR/SC | `lr.d lr.w lrd lrw sc.d sc.w scd scw` | dotted + no-dot aliases |
| A: AMO `.d` | `amoswap.d amoadd.d amoxor.d amoand.d amoor.d amomin.d amomax.d amominu.d amomaxu.d` (+ no-dot `amoswapd`…`amomaxud`) | funct5 per op |
| A: AMO `.w` | `amoswap.w amoadd.w amoxor.w amoand.w amoor.w amomin.w amomax.w amominu.w amomaxu.w` (+ no-dot `amoswapw`…`amomaxuw`) | |
| D: arith | `faddd fsubd fmuld fdivd fsqrtd` (all FPR) | dot-free; rm=dyn (rne). `fsqrtd fd,fs` |
| D: compare | `fled fltd feqd` (rd GPR, fs1/fs2 FPR) | result 0/1 in a GPR |
| D: move | `fmvdx fd,rs` (int bits→FPR), `fmvxd rd,fs` (FPR bits→int) | raw bit moves, no convert |
| D: convert | `fcvtdl fd,rs` (i64→f64), `fcvtld_{rtz,rdn,rmm} rd,fs` (f64→i64) | rounding baked into the name |
| D: load/store | `fld frd, imm(rs1)` / `fsd frs2, imm(rs1)` | float value reg, integer base (opcode 0x07/0x27, f3=3); not in the doc catalog |

### 1b. Pseudo-ops (expanded by the assembler)

| Pseudo | Expansion | Site |
|---|---|---|
| `mv rd,rs` | `addi rd,rs,0` | `Asm_RV.HC:537` |
| `not rd,rs` | `xori rd,rs,-1` | `Asm_RV.HC:539` |
| `neg rd,rs` | `sub rd,zero,rs` | `Asm_RV.HC:541` |
| `seqz rd,rs` | `sltiu rd,rs,1` | |
| `snez rd,rs` | `sltu rd,zero,rs` | |
| `beqz/bnez rs,off` | `beq/bne rs,zero,off` (numeric offset) | |
| `jr rs` | `jalr zero,0(rs)` | |
| `csrc csr,rs` | `csrrc zero,csr,rs` | |
| `rdtime rd` | `csrrs rd,time,zero` | |
| `li rd,imm` | `addi` when ±2047, else lui+addi(w) materialize sequence | `RvAsmEmitLi`, `Asm_RV.HC:293` |
| `ret` `nop` | fixed words (also listed above) | |

**Pseudo-ops with host/guest divergence:** external-symbol `call` (function-symbol
linkage via `IC_CALL`) is host-only; the guest `call` handles block-local targets.
Host-only: `lifp` (label form).

### 1c. Gate-only tokens (recognized, then rejected at encode)

`RvAsmIsMn` returns TRUE for the bare atomic **stems** `lr sc amoswap amoadd amoxor
amoand amoor amomin amomax amominu amomaxu` and for `subi`, but the encoder in
`PrsAsmRVIns` has no case for a bare stem — written without a `.d`/`.w` suffix they
fall through to `LexExcept("Unsupported RISC-V asm mnemonic")` (`Asm_RV.HC:966`).
`subi` unconditionally raises `LexExcept` with a "use addi rd,rs1,-imm" hint
(`Asm_RV.HC:428`). These are **not** accepted mnemonics.

**Assembler total: the full non-compressed rv64imafdc mnemonic set** (~215
encoder-reachable forms incl. dotted/dot-free float aliases; `AsmList()` is the live
list). `subi` and unhandled gate stems raise `LexExcept("Unsupported…")` at encode time.

---

## 2. Disassembler — what `U`/`Uf`/`UA`/`Disasm` decode

`Kernel/RVDisasm.HC` (1648 lines), planted into the REPL as `Disasm U UA Uf FnAddr`
(`RVExePubs.HC`, `RVExePubsWireDbg`). It is a **formatter** decoding a 32-bit word by
opcode `w & 0x7F`, plus a compressed path for `op & 3 != 3`. It is the **richest** of
the three knowledge sets — it decodes extensions the assembler cannot produce.

Decoded opcode families (`RVDisasm.HC`):

| Opcode | Family | Examples |
|---|---|---|
| `0x37` / `0x17` | LUI / AUIPC | `lui auipc` |
| `0x6F` / `0x67` | JAL / JALR (target resolved from PC) | jump + link |
| `0x13` | OP-IMM | `addi slti sltiu xori ori andi slli srli srai` |
| `0x1B` | OP-IMM-32 | `addiw slliw srliw` (labeled "W-ops limited in asm{}"; `sraiw` mis-shown as `srliw`) |
| `0x33` | OP + M | `add sub sll slt sltu xor srl sra or and`, `mul div* rem*` |
| `0x03` | Loads | `lb lh lw ld lbu lhu lwu` |
| `0x23` | Stores | `sb sh sw sd` |
| `0x63` | Branches | `beq bne blt bge bltu bgeu` |
| `0x73` | SYSTEM | `ecall ebreak wfi mret`, `csrrw csrrs csrrc`, CSR name resolution |
| `0x07`/`0x27` (f3=3) | FLD / FSD | double load/store |
| `0x53` | FP-OP (D) | `fadd.d fsub.d fmul.d fdiv.d fsqrt.d fmv.d fsgnj{,n,x}.d fmin.d fmax.d fle.d flt.d feq.d fmv.x.d fmv.d.x fclass.d fabs.d fneg.d fcvt.{l,lu,w,wu}.d fcvt.d.{l,lu,w,wu}` |
| `op & 3 != 3` | **RVC compressed** | `c.nop c.and c.or c.xor c.sub c.addw c.subw c.ebreak` + c.addi/c.lw/c.sw/c.j/c.beqz families |

**Decoded:**
- **Atomics — opcode `0x2F` (A extension):** `lr/sc/amo*` in `.d`/`.w` (`RVDisasm.HC`,
  funct5 lookup). Rounds-trips with what the assembler encodes.

**Now decoded (previously `.word`):**
- **OP-IMM-32 / OP-32 `0x1B`/`0x3B`** — word ops `addiw slliw srliw sraiw addw subw
  sllw srlw sraw mulw divw divuw remw remuw` all decode (mul-high `0x33` f7=1 f3=1/2/3
  fixed too).
- **Fused multiply-add `0x43/0x47/0x4B/0x4F`** — `fmadd/fmsub/fnmsub/fnmadd` in `.d`
  and `.s`, one combined R4 arm printing all four operands.
- **F single-precision `0x53` .s f7 arms** + `flw/fsw` (`0x07`/`0x27` f3=2), and
  `sfence.vma` (`0x73` f7=0x09), plain `fence` (`0x0F` f3=0). The whole non-compressed
  rv64imafdc now round-trips assemble→Disasm.

The disassembler emits both dotted (`fadd.d`) and no-dot (`faddd`) forms, several
annotated `; (no asm{} form)` or `; (limited asm{} fcvt)` (e.g. `RVDisasm.HC` float
block) — it openly documents that the assembler can't reproduce what it just decoded.

---

## 3. Compiler backend — what HolyC compiles to (codegen)

This is **"what compiles."** The x86 intermediate-code (IC) stream is lowered to RISC-V
by `ICToRISCV` — a switch on `ic->ic_code` at `Compiler/OptPass_RV.HC:303` (switch at
:323). Helper emit libraries: `BackA_RV.HC` (ALU/mov/lea), `BackB_RV.HC` (bit ops /
Bsf/Bsr / atomic bit ops), `BackC_RV.HC` (enter/leave/label/imm), `BackF_RV.HC` (F64),
`BackLib_RV.HC` (body sizing). See `docs/STOCK_PARITY.md` for the line-by-line audit of
what was stubbed and is now real.

**172 `IC_*` opcodes are handled** in the `ICToRISCV` switch. Highlights:

- **Arithmetic/logic:** `IC_ADD IC_SUB IC_MUL IC_DIV IC_MOD IC_AND IC_OR IC_XOR IC_SHL
  IC_SHR IC_COM IC_UNARY_MINUS` and their `*_EQU`/`*_CONST` forms.
- **Compare/branch/control:** `IC_JMP IC_LABEL IC_CALL* IC_RET IC_SWITCH
  IC_NOBOUND_SWITCH`, the full `IC_BR_*` family (`IC_BR_ZERO/NOT_ZERO/EQU_EQU/GREATER*
  /LESS*`, `IC_BR_BT*`, `IC_BR_AND_ZERO`, `IC_BR_MM_ZERO`), `IC_EQU_EQU IC_GREATER
  IC_LESS …`, `IC_AND_AND IC_OR_OR`.
- **Memory/addressing:** `IC_MOV IC_LEA IC_DEREF{,_PP,_MM} IC_ASSIGN{,_PP,_MM}
  IC_PUSH/POP{,_REGS} IC_ADDR IC_ABS_ADDR IC_HEAP_GLBL IC_STR_CONST IC_GET_LABEL`.
- **Bit ops (A-extension hardware):** `IC_BT IC_BTS IC_BTR IC_BTC IC_LBTS IC_LBTR
  IC_LBTC IC_BSF IC_BSR`. The **locked** `LBt*` emit real `amo{or,and,xor}.d`
  (opcode `0x2F`) — `BackB_RV.HC:142,145`.
- **Float (D-extension hardware):** `IC_TO_F64 IC_TO_I64 IC_IMM_F64 IC_SQRT IC_SQR
  IC_POWER IC_SIN IC_COS IC_TAN IC_ATAN`. Arithmetic uses hardware double ops (see §3a);
  transcendentals (`Sin/Cos/Tan/ATan/Pow`) route to **soft runtime helper calls**
  (`rv_f64_rt[]`, filled by `RVCmpSetF64Rt`, `BackF_RV.HC:9-16,420-443`).
- **Intrinsics:** `IC_MIN/MAX_I64/U64 IC_ABS IC_SIGN_I64 IC_SWAP_* IC_MOD_U64
  IC_TOUPPER IC_STRLEN IC_QUE_INIT/INS/INS_REV/REM`.

### 3a. F64 emitter library (`BackF_RV.HC`) — hardware D used by codegen

29 emitters at `BackF_RV.HC:59-227`: `RVFld RVFsd RVFaddD RVFsubD RVFmulD RVFdivD
RVFsqrtD RVFsgnjD RVFsgnjnD RVFsgnjxD RVFminD RVFmaxD RVFcvtDL RVFcvtDLu RVFcvtLD
RVFcvtLuD RVFcvtDW RVFcvtDWu RVFcvtWD RVFcvtWuD RVFmvDX RVFmvXD RVFeqD RVFltD RVFleD
RVFclassD RVFmvD RVFabsD RVFnegD`. F64 values otherwise travel as **raw bits in integer
registers** (per `STOCK_PARITY.md`); `ICFLoad`/`ICFStore` are the only FP-register
transitions.

### 3b. Deliberately unimplemented (x86-only) ICs

Handled as warnings/no-ops or remaps, not planted in the REPL hash (`STOCK_PARITY.md`,
"Deliberately different"):

- `IC_IN_U8/U16/U32`, `IC_OUT_U8/U16/U32` → `PrintWarn("Port I/O not supported on
  RISC-V (use MMIO)")` (`OptPass_RV.HC:1150-1159`).
- `IC_CLFLUSH` → `FENCE iorw,iorw` (`OptPass_RV.HC:1140-1143`).
- `IC_INVLPG` → `SFENCE.VMA` (`OptPass_RV.HC:1145-1148`).
- `IC_RDTSC` → `rdcycle`.
- `IC_FS/GS`, `IC_MOV_FS/GS` → load Compiler Fs/Gs slots (not x86 segment regs).
- **Fallthrough default:** any IC with no case →
  `PrintWarn("IC opcode %d (%s) not implemented for RISC-V")` (`OptPass_RV.HC:1469`),
  and the Soft-Call path takes the return-0 branch (`OptPass_RV.HC:605`).

---

## 4. ISA extensions — end-to-end verdict

See the [glance table](#extension-coverage-at-a-glance-the-three-way-answer). Summary:

- **RV64I** — base fully assembles (OP/OP-IMM incl. `sltiu`, word ops, branches,
  `jal`/`jr`/`j`, all loads/stores, full `fence pred,succ`); guest `call` handles
  block-local targets (external-symbol `call` is host-only). Codegen + disasm complete.
- **M** — fully supported in all three, incl. mul-high (`mulh/mulhsu/mulhu`) and the
  word ops (`mulw divw divuw remw remuw`).
- **A** — assembled, emitted, and **decoded** (`0x2F` round-trips).
- **F/D** — the full single- and double-precision extensions assemble: loads/stores,
  arith/sqrt, sign-inject, `fmin/fmax`, compares, `fclass`, moves, the complete `fcvt`
  matrix (int↔float both widths, F32↔F64), and fused FMA (`.d`/`.s`). Codegen uses
  hardware double; disasm decodes all of it. Transcendentals are soft.
- **C (compressed)** — fully assembled AND decoded. The guest `asm{}` assembles every
  RVC instruction: integer reg/imm; `c.j/c.beqz/c.bnez` incl. labels; `c.ld/c.sd/c.lw/
  c.sw`; `c.andi/c.srli/c.srai`; `c.addiw`; `c.lui`; sp-relative `c.lwsp/c.ldsp/c.swsp/
  c.sdsp` + `c.addi16sp/c.addi4spn`; and float `c.fld/c.fsd/c.fldsp/c.fsdsp` — 16-bit via
  `AOTStoreCodeU16`, all GNU-verified, `make rvc-asm-smoke`.
- **Zicsr** — assembler + disassembler; codegen only reaches CSRs through `asm{}`.
- **Not supported anywhere:** vector (V), half-precision/quad float. Every base mnemonic
  now assembles in the guest; the only host/guest gap is external-symbol `call`
  (host-only, via `IC_CALL`) vs the guest's block-local `call`. RVC, FMA and OP-32 word
  ops are fully assembled and decoded.

Platform build declares `CONFIG_ISA_RV64IMAFDC` / `CONFIG_RISCV_ABI "lp64d"`
(`RVAutoConf.HH:6-9`).

---

## 5. CSRs

### 5a. Assembler CSR name→number map (`RvAsmCsrNum`, `Asm_RV.HC:146`) — 28 names

| Name | # | Name | # | Name | # |
|---|---|---|---|---|---|
| sstatus | 0x100 | mstatus | 0x300 | mscratch | 0x340 |
| sie | 0x104 | misa | 0x301 | mepc | 0x341 |
| stvec | 0x105 | medeleg | 0x302 | mcause | 0x342 |
| sscratch | 0x140 | mideleg | 0x303 | mtval | 0x343 |
| sepc | 0x141 | mie | 0x304 | mip | 0x344 |
| scause | 0x142 | mtvec | 0x305 | mcycle | 0xB00 |
| stval | 0x143 | mcounteren | 0x306 | minstret | 0xB02 |
| sip | 0x144 | cycle | 0xC00 | instret | 0xC02 |
| satp | 0x180 | time | 0xC01 | mhartid | 0xF14 |

### 5b. Kernel CSR readers (`Kernel/RVWinSerial.HC`) — 24 `RVWinCsrr*` accessors

Each is a one-instruction `csrr a0, <num>` (`RVWinSerial.HC:43-113`):
`Mstatus(0x300) Mie(0x304) Mip(0x344) Mepc(0x341) Mcause(0x342) Mtval(0x343)
Mtvec(0x305) Mscratch(0x340) Misa(0x301) Mhartid(0xF14) Medeleg(0x302)
Mideleg(0x303) Mcounteren(0x306) Sstatus(0x100) Sie(0x104) Sip(0x144)
Stvec(0x105) Sepc(0x141) Scause(0x142) Stval(0x143) Satp(0x180) Cycle(0xC00)
Time(0xC01) Instret(0xC02)`.

### 5c. CSR field decoders

- **`Kernel/RVExplore.HC`** (new, REPL-callable): `RVCsrDecodeMstatus` decodes
  MIE/SIE/MPIE/SPIE/SPP/MPP/FS/XS/VS/MPRV/SUM/MXR/TW/SD; `RVMcauseName` decodes the
  full trap-cause table — interrupts 1/3/5/7/9/11 (soft/timer/external × S/M) and
  exceptions 0–15 (misaligned/access-fault/illegal/breakpoint/page-fault/ecall).
  Exposed as `Mstatus()` and `Mcause()` (`RVExplore.HC:271,279`).
- **`bootstrap/seed/csr.hc`** (1900 lines, **retired** thin-JIT seed — the source
  `RVExplore.HC` was ported from): `CSRGet`/`CSRSet` (`csr.hc:646,719`) read/write 28
  M- and S-mode CSRs by symbolic `CSR_*`; decoders `CsrDecodeMstatus/Misa/Mie/Mip/
  Mtvec/Mepc/Mcause/Mtval/Mscratch/Mhartid/Mtime`, `McauseCauseName`, and
  `CsrExplain`/`CsrDecodeVal` (name-driven).
- **Trap seed:** `bootstrap/seed/trap.hc` (trap CSR handling) — part of the retired
  seed toolchain.

---

## 6. Memory map / platform (`Kernel/RVAutoConf.HH`)

Generated by `scripts/kconfig.py` for QEMU `virt` (RV64), `-bios none`. Surfaced at the
REPL by `MemMap()` (`RVExplore.HC:157`).

### 6a. MMIO devices

| Region | Base | Notes |
|---|---|---|
| SiFive test finisher | `0x00100000` | `MEM_TEST` / power-off |
| Goldfish RTC | `0x00101000` | `CONFIG_RTC_BASE` |
| CLINT | `0x02000000` | mtime +`0xBFF8`, mtimecmp +`0x4000` |
| PLIC | `0x0C000000` | enable +`0x2000`, threshold +`0x200000`, claim +`0x200004` |
| UART 16550 | `0x10000000` | IRQ 10, reg-shift 0 |
| fw_cfg | `0x10100000` | |
| virtio-mmio | `0x10001000` | stride `0x1000`, 8 slots |
| PCI ECAM | `0x30000000` | MMIO assign base `0x48000000` |

Timebase 10 MHz. Buses present: virtio net/input/9p/console/balloon/scsi, virtio-pci,
ramfb, fw_cfg, goldfish-rtc.

### 6b. DRAM image layout (`0x80000000` base, 128 MiB `0x08000000`)

| Region | Addr | Region | Addr |
|---|---|---|---|
| Entry / kernel link | `0x80000000` | Heap base | `0x86000000` |
| Guest blob | `0x80100000` | FB (soft) | `0x86100000` |
| Compiler slot | `0x80200000` | Sys fixed area | `0x87000000` |
| TOS API | `0x80300000` | Host slots | `0x87001000` |
| SMP mailbox | `0x87001E00` | MemFS base | `0x87800000` |
| Stack base | `0x87F00000` | DRAM top | `0x88000000` |
| virtio driver RAM | `0x88000000` | | |

---

## 7. Three-way duplication & drift

The same mnemonic knowledge lives in three shapes:

1. **Assembler** — `Compiler/Asm_RV.HC` (a *parser*/encoder). Covers all of
   non-compressed rv64imafdc.
2. **Disassembler** — `Kernel/RVDisasm.HC` (a *formatter*/decoder). Decodes
   I/M/A/F/D/C + branches + OP-32 + FMA — the full non-vector set.
3. **Doc catalog** — `Kernel/RVExplore.HC` (`rv_asm_doc_raw`), 244 entries, consumed by
   `AsmList()` / `AsmDoc()`. The separate bootstrap seed `bootstrap/seed/asm_doc.hc`
   (`AsmDocRaw`) is an **older, independently-maintained copy** (~138 entries) that has
   drifted and is **not** kept in sync by the ISA-completion work — the live REPL uses
   `rv_asm_doc_raw`.

### Where they agree / disagree

| Comparison | Agree | Disagree |
|---|---|---|
| doc catalog `asm_doc.hc` ↔ `rv_asm_doc_raw` | core overlap | **drifted** — asm_doc.hc is the stale seed (~138), rv_asm_doc_raw is live (244, +35 RVC — all RVC) |
| assembler ↔ doc catalog `rv_asm_doc_raw` | full rv64imafdc both sides | all catalog entries assemble in the guest except host-only `lifp` (below) |
| assembler ↔ disassembler | I/M base + **branches/`jal`** + **A** + **narrow ld/st** + **D (ALU + `fld`/`fsd`)** overlap | disasm still uniquely has **RVC, OP-IMM-32**, and the F/D forms asm lacks (`fsgnj`, `fmin/fmax`, FMA, F32) |
| disassembler ↔ doc catalog | branches, F/D forms overlap | disasm adds RVC + OP-IMM-32; doc adds A + Zicsr detail the disasm can't decode |

The doc catalog is the **broadest advertisement and the least accurate** relative to
what `asm{}` actually accepts.

---

## 8. REPL exploration commands (`make tos`)

Planted by `Compiler/RVExePubs.HC` via `RVExePubFunNew(name, addr, ret, arg_cnt)`
(`RVExePubs.HC:44`) into the guest `Compiler_RV` hash, so they are real HolyC functions
at the prompt (not crash-shell barewords). ~56 functions are planted; the RISC-V /
debug-relevant ones:

- **Disassembly / debug** (`RVExePubsWireDbg`): `Disasm U UA Uf DisasmAt FnAddr Bp BpClr
  Reg Regs PassTrace`.
- **New RISC-V exploration — slots 41–45** (`RVExePubs.HC:928-948,1028-1032`, backed by
  `Kernel/RVExplore.HC`):
  - `AsmList()` — lists the 244 documented `asm{}` mnemonics + templates.
  - `AsmDoc("mn")` — structured doc for one mnemonic (template/encoding/imm/GNU/note).
  - `MemMap()` — prints the platform memory map (§6).
  - `Mstatus()` — reads + field-decodes `mstatus`.
  - `Mcause()` — reads + names the current trap cause.
- **Files / editor / desktop:** `Cat Dir Cd Ls Pwd Find Ed FileRead FileWrite FileMgr
  FilesFind Tasks Man Help` and DolDoc helpers (`Doc*`, `MStrPrint`, `ScanFlags`, date
  helpers).

> **Provenance:** `AsmList/AsmDoc/MemMap/Mstatus/Mcause/Csr/Uptime` and their file
> `Kernel/RVExplore.HC` are committed on `archive` (`51f19cf`, `409155d`, `abe75ab`),
> wired via `Compiler/RVExePubs.HC` + `Kernel/Kernel_RV.PRJ`.

---

## Gaps & drift

### A. Documented but NOT assemblable (1 mnemonic)

`AsmList()`/`AsmDoc()` advertise it; the guest `asm{}` raises "Unsupported mnemonic":

- **Host-only:** `lifp` (label form).

`call` was here; it now assembles in the guest as an `auipc ra + jalr ra` PC-relative
pair (±2GiB, its only 8-byte forward fixup) to a **block-local label or numeric offset**
— GNU-verified, `make call-asm-smoke`. What stays host-only is external-symbol `call`
(resolving a global HolyC function through `IC_CALL`), which needs post-placement
relocation the raw-word guest path does not have.

(`sfence.vma` is now assemblable — bare, one-, or two-operand — as of the base-I/M
increment.)

(Branches, `jal`/`jr`, narrow loads/stores, the 14 float forms `faddd`…`fcvtld_*`, and
the `seqz/snez/csrc/rdtime` pseudos all moved OUT of this list — they now assemble in
the guest with the same names the catalog documents.)

### B. Assembler gate accepts, encoder rejects (12 + 1)

`RvAsmIsMn` returns TRUE for bare stems `lr sc amoswap amoadd amoxor amoand amoor
amomin amomax amominu amomaxu` and `subi`, but `PrsAsmRVIns` has no encoder case →
`LexExcept("Unsupported RISC-V asm mnemonic")` (bare stem, wrong error text — it should
say "needs `.d`/`.w`") or the explicit `subi` hint. Usability bug, not doc drift.

### C. Assembler ↔ disassembler asymmetry

- The assembler is the **only** hand-writing path for the **A extension**, and the
  disassembler now decodes opcode `0x2F`, so atomics you assemble round-trip through
  `U`/`Uf` (verified: `asm{amoadd.d/lr.d/sc.d/amomaxu.w …}` → `Disasm` in the win REPL).
- The disassembler decodes **narrow loads/stores, F/D, RVC, OP-IMM-32** that the
  assembler cannot produce. (Branches and `jal` now round-trip: the guest assembles them
  numeric, the disassembler decodes them.)

### D. FIXED — dotted-suffix heap overflow

`PrsAsmRVIns` used `mn = StrNew(cc->cur_str)`, and `StrNew` allocates exactly
`StrLen+1` bytes (`bootstrap/seed/str.hc:132`). `RvAsmMergeDotSuffix` then writes
`mn[n++]='.'` plus the suffix chars into that buffer, overrunning the allocation by up
to ~2 bytes (e.g. `amomaxu` alloc=8, becomes `amomaxu.w`\0 = 10). Bounded (`n < 31`) so
it couldn't run away, and TempleOS `MAlloc` chunk granularity absorbed it in practice —
but a genuine out-of-bounds heap write. **Fixed:** `PrsAsmRVIns` now allocates via
`RvAsmMnDup`, a fixed 32-byte buffer with a bounded copy (`Asm_RV.HC`), so every
mnemonic + suffix fits (max index written is 31).

### E. Disassembler decode gaps (rendered `.word`/`illegal`)

- Opcode `0x3B` — **OP-32 word ALU** (`addw subw sllw srlw sraw mulw divw remw`).
- Opcodes `0x43/0x47/0x4B/0x4F` — **fused multiply-add** (`fmadd.d`…).
- `sraiw` (opcode `0x1B`, f3=5, f7 bit 0x20) is mis-rendered as `srliw`.

### F. Codegen (what compiles) — never emitted

- No OP-32 word ALU (`0x3B`), no FMA (`0x43…`), no compressed (C), no vector (V).
- x86-only ICs are deliberately stubbed (§3b): `IC_IN_*`, `IC_OUT_*`; `IC_INVLPG`→
  `sfence.vma`, `IC_CLFLUSH`→`fence`, `IC_RDTSC`→`rdcycle`. Any unhandled IC hits the
  `OptPass_RV.HC:1469` warn-and-return-0 default.

---

*Survey generated read-only. Primary sources: `Compiler/Asm_RV.HC`,
`Compiler/AsmInit.HC`/`AsmLib.HC`/`AsmResolve.HC`, `Kernel/RVDisasm.HC`,
`Compiler/OptPass_RV.HC`, `Compiler/BackA_RV.HC`/`BackB_RV.HC`/`BackC_RV.HC`/
`BackF_RV.HC`/`BackLib_RV.HC`, `bootstrap/seed/asm_doc.hc`, `bootstrap/seed/csr.hc`,
`Kernel/RVExplore.HC`, `Kernel/RVWinSerial.HC`, `Kernel/RVAutoConf.HH`,
`Compiler/RVExePubs.HC`, `docs/STOCK_PARITY.md`.*
