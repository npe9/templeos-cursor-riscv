# RISC-V support inventory

A survey of *all* RISC-V knowledge in this TempleOS→RISC-V port, with the one
distinction the rest of the document is organized around:

> **"What compiles" ≠ "what can be assembled."**
> The HolyC compiler backend (`Compiler/*_RV.HC`) lowers HolyC to RISC-V machine
> code and can emit instructions from **I + M + A + F/D**. The inline `asm{}`
> assembler (`Compiler/Asm_RV.HC`) is a *separate, much smaller* hand-written
> parser that accepts only **I(partial) + M + A + Zicsr** — no floating point,
> no compressed, and **no control flow at all**.

The same instruction knowledge is duplicated across **three** places that do not
agree: the assembler (a parser), the disassembler (`Kernel/RVDisasm.HC`, a
formatter), and the documentation catalog (`bootstrap/seed/asm_doc.hc` +
`Kernel/RVExplore.HC`). The drift between them is catalogued in
[§7](#7-three-way-duplication--drift) and [Gaps & drift](#gaps--drift).

Read-only survey — no code was changed. Evidence is cited as `file:line`.

---

## Headline findings

- The platform target is declared **`rv64imafdc` / `lp64d`** (`Kernel/RVAutoConf.HH:6-7`),
  and the disassembler decodes nearly all of it, but the guest `asm{}` assembler
  (`Compiler/Asm_RV.HC`, used by the REPL / `make tos`) implements only **I(partial) +
  M + A + Zicsr + B-type branches + `jal`/`jr`**. It has **no floating point and no
  compressed**. Guest branches/jumps take a **numeric PC-relative byte offset**
  (`beq a0,a1,8`, `jal x0,-8`), *not* a label — the host `asm{}` parser
  (`host/parser.c`, used to build the images and by `--asm-dump`) uses **label**
  operands (`beq a0,a1,L`) and rejects numeric ones. That form split is a deliberate
  host/guest divergence: the guest's single-pass emit path has no place to buffer a
  block for label indexing, and the x86 forward-reference fixup machinery
  (`asm_undef_hash`) cannot express B/J-type's *split* immediate fields. The guest
  still has no `j` (host reserves that spelling for the label form) and no `call`.
- **Assembler accepts 109 encoder-reachable mnemonics** (dotted and undotted amo/lr/sc
  aliases counted separately; includes the 10 new guest branch/jump forms `beq bne blt
  bge bltu bgeu beqz bnez jal jr`). It recognizes an additional 12 "stem" tokens
  (`lr sc amoswap amoadd amoxor amoand amoor amomin amomax amominu amomaxu`) plus
  `subi` that pass the `RvAsmIsMn` gate but then hit `LexExcept("Unsupported…")` at
  encode time — accepted by the gate, rejected by the encoder.
- **Sharpest "compiles ≠ assembles" instance:** the compiler backend emits **29
  distinct D-extension instructions** (`Compiler/BackF_RV.HC:59-227`) that `asm{}`
  cannot express at all — yet the doc catalog advertises float mnemonics as if they
  were assemblable.
- **The doc catalog (137 entries) documents 29 mnemonics the guest assembler rejects**
  (`j/call/seqz/snez/csrc/rdtime/sfencevma`, byte/half loads+stores, and every float
  form). The **14 float forms are now the largest single category.** (Previously 38 —
  the six B-type branches, `beqz/bnez`, and `jr` became assemblable when guest
  numeric-offset branches were added; `jal` too.)
- **Assembler↔disassembler asymmetry:** the assembler is the *only* place the **A
  extension** is uniquely supported for hand-writing, yet the disassembler does **not**
  decode atomics (opcode `0x2F` is absent) — so `U`/`Uf` cannot round-trip the atomics
  you assemble.
- **Latent bug:** `RvAsmMergeDotSuffix` appends `.d`/`.w` into a buffer allocated by
  `StrNew` at exactly `StrLen+1` bytes (`bootstrap/seed/str.hc:132`), a small
  out-of-bounds heap write (see [Gaps & drift](#gaps--drift)).
- The REPL exploration commands (`AsmList AsmDoc MemMap Mstatus Mcause Csr Uptime`) live
  in **`Kernel/RVExplore.HC`**, wired by `Compiler/RVExePubs.HC` — committed on `archive`
  (`51f19cf`, `409155d`, `abe75ab`).

---

## Extension coverage at a glance (the three-way answer)

| Extension | `asm{}` assembles | Codegen emits ("compiles") | Disassembler decodes |
|---|---|---|---|
| **RV64 I** (base) | **partial** — B-type branches + `jal`/`jr` (guest: numeric offset; host: label), no `j`/`call`, no `lb/lh/lbu/lhu/lwu/sb/sh`, no full `fence` (only `fence.i`), no `sltiu` | yes | yes |
| **I 32-bit ops** (`addiw`/`slliw`/`srliw`) | no | no | yes (opcode `0x1B`) |
| **I OP-32** (`addw`/`subw`/`mulw`…) | no | no | **no** (`0x3B` absent) |
| **M** (`mul div divu rem remu`) | yes | yes | yes |
| **A** (`lr/sc/amo*`, `.d` and `.w`) | **yes** | yes — `amo{or,and,xor}.d` (`BackB_RV.HC:142,145`) | **no** (`0x2F` absent) |
| **F/D** (double float) | **no** | **yes** — 29 emitters (`BackF_RV.HC:59-227`) | yes (`0x53`, `0x07`/`0x27`) |
| **C** (compressed) | no | no | yes (`op & 3 != 3`) |
| **Zicsr** (`csr*`) | yes (12 forms + 28 named CSRs) | no (only via `asm{}`) | yes (`0x73`) |
| **Fused FMA** (`fmadd.d`…) | no | no | **no** (`0x43/0x47/0x4B/0x4F` absent) |
| **V** (vector) | no | no | no |

Note the F/D row: the compiler uses hardware double instructions for arithmetic, but
`asm{}` has no float forms and the disassembler *can* read them back — three different
answers for one extension.

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
| Instruction fence | `fence.i` / `fencei` | alias pair; **no full `fence`** |
| U-type | `lui auipc` | 20-bit field, gas-compatible |
| OP-IMM (I) | `addi andi ori xori slti slli srli srai` | shifts take 6-bit shamt; **no `sltiu`, no `addiw`** |
| OP (R) | `add sub and or xor sll srl sra slt sltu` | pure R-type; passing an immediate to `add`/`sub` raises a helpful `LexExcept` |
| M ext (R) | `mul div rem divu remu` | funct7=1; **no `mulh*`, no `mulw/divw`** |
| Load (I) | `ld lw` | **only** doubleword/word; no `lb/lh/lbu/lhu/lwu` |
| Store (S) | `sd sw` | **only** doubleword/word; no `sb/sh` |
| Jump (I) | `jalr` | short form `jalr rs` → `jalr ra,0(rs)` |
| Jump (J) | `jal jr` | guest only, **numeric** offset: `jal rd,off` / `jal off`(→ra) / `jr rs`(→`jalr x0`); **no `j`**, **no `call`** |
| Branch (B) | `beq bne blt bge bltu bgeu beqz bnez` | guest only, **numeric** PC-relative even byte offset (`beq a0,a1,8`); host wants a label |
| Zicsr | `csrr csrw csrs csrrw csrrs csrrc csrrwi csrrsi csrrci csrwi csrsi csrci` | **no `csrc`** |
| A: LR/SC | `lr.d lr.w lrd lrw sc.d sc.w scd scw` | dotted + no-dot aliases |
| A: AMO `.d` | `amoswap.d amoadd.d amoxor.d amoand.d amoor.d amomin.d amomax.d amominu.d amomaxu.d` (+ no-dot `amoswapd`…`amomaxud`) | funct5 per op |
| A: AMO `.w` | `amoswap.w amoadd.w amoxor.w amoand.w amoor.w amomin.w amomax.w amominu.w amomaxu.w` (+ no-dot `amoswapw`…`amomaxuw`) | |

### 1b. Pseudo-ops (expanded by the assembler)

| Pseudo | Expansion | Site |
|---|---|---|
| `mv rd,rs` | `addi rd,rs,0` | `Asm_RV.HC:537` |
| `not rd,rs` | `xori rd,rs,-1` | `Asm_RV.HC:539` |
| `neg rd,rs` | `sub rd,zero,rs` | `Asm_RV.HC:541` |
| `li rd,imm` | `addi` when ±2047, else lui+addi(w) materialize sequence | `RvAsmEmitLi`, `Asm_RV.HC:293` |
| `ret` `nop` | fixed words (also listed above) | |

**Pseudo-ops the assembler does NOT provide** (despite the doc catalog listing them):
`j jr call seqz snez beqz bnez rdtime`.

### 1c. Gate-only tokens (recognized, then rejected at encode)

`RvAsmIsMn` returns TRUE for the bare atomic **stems** `lr sc amoswap amoadd amoxor
amoand amoor amomin amomax amominu amomaxu` and for `subi`, but the encoder in
`PrsAsmRVIns` has no case for a bare stem — written without a `.d`/`.w` suffix they
fall through to `LexExcept("Unsupported RISC-V asm mnemonic")` (`Asm_RV.HC:966`).
`subi` unconditionally raises `LexExcept` with a "use addi rd,rs1,-imm" hint
(`Asm_RV.HC:428`). These are **not** accepted mnemonics.

**Assembler total: 109 encoder-reachable mnemonics** (+12 gate-only stems + `subi`).

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

**Not decoded (rendered `.word` / `illegal`):**
- **Atomics — opcode `0x2F` (A extension)** is absent, even though the assembler
  *encodes* it. (`Print(".word …")` fallback, `RVDisasm.HC:767`; `illegal` at 1072.)
- **OP-32 `0x3B`** (`addw subw sllw srlw sraw mulw divw remw`) — absent.
- **Fused multiply-add `0x43/0x47/0x4B/0x4F`** (`fmadd.d fmsub.d fnmadd.d fnmsub.d`) — absent.

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

- **RV64I** — base, but the assembler covers it only partially (no control flow, no
  narrow load/store, no `sltiu`/`fence`). Codegen + disasm are complete for what the
  compiler needs.
- **M** — fully supported in all three (assembler, codegen, disasm).
- **A** — assembled and emitted (codegen `amo*.d` for locked bit ops); **not decoded**
  by the disassembler.
- **F/D** — emitted by codegen (hardware double) and decoded by disasm; **not
  assemblable**. Transcendentals are soft.
- **C (compressed)** — decoded by the disassembler only; never assembled or emitted.
- **Zicsr** — assembler + disassembler; codegen only reaches CSRs through `asm{}`.
- **Not supported anywhere:** vector (V), fused multiply-add (FMA), OP-32 word ALU ops
  in assembler/codegen, half-precision/quad float.

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

1. **Assembler** — `Compiler/Asm_RV.HC` (a *parser*/encoder). 99 accepted mnemonics.
2. **Disassembler** — `Kernel/RVDisasm.HC` (a *formatter*/decoder). Richest set;
   decodes I/M/F/D/C + branches but **not** A (atomics) or OP-32/FMA.
3. **Doc catalog** — `bootstrap/seed/asm_doc.hc` (`AsmDocRaw`) and the ported
   `Kernel/RVExplore.HC` (`rv_asm_doc_raw`). 137 documented entries. These two catalog
   strings are **byte-identical** to each other (the RVExplore header even says so,
   `RVExplore.HC:4-8`), and are consumed by `AsmList()` / `AsmDoc()`.

### Where they agree / disagree

| Comparison | Agree | Disagree |
|---|---|---|
| doc catalog `asm_doc.hc` ↔ `rv_asm_doc_raw` | **identical** (137 ≡ 137) | none |
| assembler ↔ doc catalog | 109 accepted ⊂ 137 documented | **29 documented mnemonics are not assemblable** (below) |
| assembler ↔ disassembler | I/M base + **branches/`jal`** overlap | asm has **A** (disasm can't decode `0x2F`); disasm has **narrow loads/stores, F/D, RVC, OP-IMM-32** the asm lacks |
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
  - `AsmList()` — lists the 137 documented `asm{}` mnemonics + templates.
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

### A. Documented but NOT assemblable (29 mnemonics)

`AsmList()`/`AsmDoc()` advertise these; the guest `asm{}` raises "Unsupported mnemonic":

- **Jump pseudo-ops:** `j call`. (`jr` and `jal` **are** now assemblable in the guest;
  `j` is deliberately left out because the host defines it as the label-only form —
  use `jal x0,off`.)
- **Set-if-zero pseudo:** `seqz snez`.
- **Zicsr:** `csrc`.
- **Narrow load/store:** `lb lbu lh lhu lwu sb sh`.
- **Misc pseudo/priv:** `rdtime sfencevma` (`sfence.vma`), `lifp` (host-only label form).
- **All floating point:** `faddd fsubd fmuld fdivd fsqrtd feqd fled fltd fmvdx fmvxd
  fcvtdl fcvtld_rtz fcvtld_rdn fcvtld_rmm`.

### B. Assembler gate accepts, encoder rejects (12 + 1)

`RvAsmIsMn` returns TRUE for bare stems `lr sc amoswap amoadd amoxor amoand amoor
amomin amomax amominu amomaxu` and `subi`, but `PrsAsmRVIns` has no encoder case →
`LexExcept("Unsupported RISC-V asm mnemonic")` (bare stem, wrong error text — it should
say "needs `.d`/`.w`") or the explicit `subi` hint. Usability bug, not doc drift.

### C. Assembler ↔ disassembler asymmetry

- The assembler is the **only** hand-writing path for the **A extension**, but the
  disassembler does **not** decode opcode `0x2F` — atomics you assemble disassemble as
  `.word`. `U`/`Uf` cannot round-trip them.
- The disassembler decodes **narrow loads/stores, F/D, RVC, OP-IMM-32** that the
  assembler cannot produce. (Branches and `jal` now round-trip: the guest assembles them
  numeric, the disassembler decodes them.)

### D. Latent bug — dotted-suffix heap overflow

`PrsAsmRVIns` does `mn = StrNew(cc->cur_str)` (`Asm_RV.HC:385`), and `StrNew` allocates
exactly `StrLen+1` bytes (`bootstrap/seed/str.hc:132`). `RvAsmMergeDotSuffix` then
writes `mn[n++]='.'` plus the suffix chars into that buffer (`Asm_RV.HC:347-370`),
overrunning the allocation by up to ~2 bytes (e.g. `amomaxu` alloc=8, becomes
`amomaxu.w`\0 = 10). Bounded (`n < 31`) so it can't run away, and TempleOS `MAlloc`
chunk granularity likely absorbs it in practice — but it is a genuine out-of-bounds
heap write and should be fixed by allocating a fixed 32-byte scratch buffer.

### E. Disassembler decode gaps (rendered `.word`/`illegal`)

- Opcode `0x2F` — **A extension atomics** (see C).
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
