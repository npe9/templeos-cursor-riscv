# Assembler stress — known gaps

Host path: `host/parser.c` `TryAssembleRiscV`. Guest destination assembler is `Compiler/Asm_RV.HC` (not exercised by this suite).

**Property tests** (`make asm-prop`): random RV64I/M encode + OOR reject checks vs `tests/asm/riscv_oracle.py`. Same host path; complements curated goldens — does not cover wide `li`, CSR, A-ext, float, or guest asm.

| Area | Status | Notes |
|------|--------|-------|
| **RVC (C)** | Unsupported | `c.*` mnemonics soft-skip / fail stress negatives. No compressed emit. |
| **`%hi` / `%lo` / `la`** | Unsupported | No reloc pseudo; use `lui`/`auipc`+`addi` with numeric imms. |
| **`li` wide** | OK | Host expands outside ±2047 to `lui`+`addi` (+ `slli`/`srli` 32 when U32 bit31 set), matching `EmitLoadImm64` / guest `RVLi` / `RvAsmEmitLi`. Gas uses a different multi-insn sequence (`addiw`); wide cases use `"gas": false` / `asm-gnu-diff` `host_only`. |
| **`lui` imm** | 20-bit field | Like gas: `lui a0, 0x81397` → bits[31:12]. Full address `0x81397000` is **hard-fail** (prefer `li`). Accepts unsigned `0..0xFFFFF` or signed `-0x80000..-1`. |
| **Imm range checks** | Hard-fail | I/S `simm12`, shift `0..63`, U-type 20-bit, CSR `0..0xFFF`, zimm `0..31` reject with error (no silent mask). Negatives: `addi_oor`, `ld_oor`, `slli_oor`, `lui_oor_addr`, … |
| **Branch / `j` range** | Soft | Offsets from label indices (`±4` per insn). Block max 256 insns ⇒ offsets stay inside ±4KiB branch / ±1MiB `jal` windows; no relax / multi-insn expand. OOR branch/j not hard-checked (stay in-block). |
| **`call` / `jal` label** | Special | `call Sym` becomes `IC_CALL` (HolyC linkage), **not** raw `jal`. Bare `jal` is unsupported (negative). Use `j` for PC-rel jump. |
| **RV64 W-ops** | Unsupported | `addiw`, `slliw`, `sext.w`, … — gap (negative `addiw`). |
| **Zba/Zbb/…** | Unsupported | Bitmanip not in host asm. |
| **A-ext aq/rl** | Partial | Encodes `.aq`/`.rl` not exposed; base A forms only. |
| **Dotted vs joined** | Host style | Prefer `fencei`, `sfencevma`, or lexer-joined `lr.d` / `amoswap.d`. Spaced `fence . i` fails. |
| **Peephole vs dump** | N/A for stress | AOT `RVU32` may drop `nop`; `--asm-dump` reads `IC_RAW_RV` before peephole — intentional for semantics. |

When closing a gap, add positives (and drop the matching negative / row here).
