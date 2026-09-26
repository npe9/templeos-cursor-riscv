# The x86 assembly the backend drops, and how to make it portable

`HOLYC_ASM_SKIPS=1` prints, per compile, every construct the backend dropped instead of
translating:

```sh
$ HOLYC_ASM_SKIPS=1 ./holyc-riscv case.hc -o /dev/null
note: 17 x86 construct(s) dropped — that code is NOT in the image
  Kernel/KMathA.HC:1: asm{} block _D3_NORM_SQR
  Kernel/KUtilsRV.HC:587: asm{} block
  …
```

**A dropped construct is code that is not in the image.** `host/parser.c:5229` soft-skips an
`asm{}` block it cannot assemble — deliberately, so the host AOT can compile stock files full of
x86 — so for any file containing assembly a clean compile cannot distinguish *ported* from
*silently empty*. `Adam/Gr/GrAsm.HC` is the extreme case: 410 lines, 121 x86 mnemonics, compiles
with exit 0, adds 40 bytes, defines no symbols.

## The mechanism is one function, on purpose

There are four places a construct gets dropped — two bare-opcode paths, the `$IB` missing-bin path
and the `asm{}` path — and they all call `HolyAsmSkipNote(cc, line, what, label)`.
`asm_blocks_skipped++` appears in exactly one place. That matters for more than tidiness: a count
cannot be worked through, and four independent counters cannot be turned into a worklist.

`line` is where the construct STARTS. Reading `cc->lex.line` at note time reports the CLOSING BRACE,
which made `Kernel/KUtilsRV.HC`'s failing `Abs::` block look like the `Floor::` block below it, and
reported `KMathA.HC:648` for a block that begins on line 1 — that whole 648-line file is one `asm{}`.

## The goal is portability, not RISC-V

Each dropped block implements an *operation*. The fix is to name that operation and express it once,
so every target gets it — rv64 today, rv32/AArch64/ARM32 through the `holyc_target` seam
(`host/holyc_target.h`, whose own comment reserves "op hooks for forms that are irreducibly
different per target"). Translating x86 → RISC-V instruction by instruction would leave the next
architecture exactly where this one started.

Three outcomes, and most of the list is the first:

| | fix |
|---|---|
| **Portable HolyC** | the operation has no machine-specific content; write it in HolyC once and no target needs asm |
| **`holyc_target` op hook** | irreducibly per-arch (context switch, page tables, fault CSR); one hook, one implementation per target |
| **Not applicable** | x86-only concept with no meaning elsewhere |

## The current list — 17 in a plain `Kernel_RV.PRJ` build

| construct | operation | fix |
|---|---|---|
| `KMathA.HC:1` `_D3_NORM_SQR` | 3-vector norm² | portable HolyC (`Kernel/KMathA_RV.HC` already has HolyC `D3*`) |
| `KUtils.HC:1` `_MEMSET_U16` | fill 16-bit units | portable HolyC |
| `StrA.HC:20` `PUT_HEX_U32` | format a U32 as hex | portable HolyC |
| `Mem/MAllocFree.HC:1` `_FREE` | allocator free fast path | portable HolyC |
| `KHashA.HC:1` `SYS_HASH_SINGLE_TABLE_FIND1` | hash lookup | portable HolyC — `Kernel/KHashRV.HC` already does this |
| `SerialDev/Keyboard.HC:1` `SHIFT_KEY_SCAN_DECODE_TABLE` | **a data table written in asm** | portable data, not code |
| `Sched.HC:54` `_TASK_CONTEXT_RESTORE` | restore a task's registers | **op hook** |
| `KExcept.HC:1` `_TAKE_EXCEPT` | unwind to a handler | **op hook** |
| `Mem/PageTables.HC:1` `SYS_INIT_PAGE_TABLES` | build the initial page tables | **op hook** (x86 paging vs Sv39) |
| `KDbg.HC:628` `MOV_RAX_CR2` | the faulting address | **op hook** (x86 CR2 vs RISC-V `mtval`) |
| `KTask.HC:121`, `:141` | inline, unlabelled | read them; likely op hook |
| `KMain.HC:229` `SYS_KERNEL_END` | a link-time symbol | **op hook or linker symbol** — and `SYS_KERNEL_END` is one of the symbols `docs/DEMO_SURVEY.md` lists as missing, so this unblocks `Demo/AcctExample/TOS/TOSCfg.HC` |
| `SerialDev/Keyboard.HC:413`, `Mouse.HC:92` `CLD` | clear the x86 direction flag | **not applicable** — nothing to write |
| `PCIBIOS.HC:1` `SYS_PCIBIOS_SERVICE_DIR` | call the x86 PCI BIOS | **not applicable** |
| `KUtilsRV.HC:587` `Abs::` | absolute value | **OUR BUG, not stock** — see below |

## `KUtilsRV.HC:587` is ours

`Kernel/KUtilsRV.HC` is the port's own native-RISC-V assembly — 59 `asm{}` blocks, 58 of which
assemble. The one that does not is `Abs::`:

```
asm {
	Abs::
	fmvdx	fa0,a0
	fabsd	fa0,fa0
	fmvxd	a0,fa0
	ret
}
```

`Abs` is absent from `HOLYC_MAP` while `Floor` and `Trunc`, written the same way immediately below,
are present. So a kernel math function is silently missing from every image, and the cause is one of
these four mnemonics — `fabsd` is the one the others do not use. Fix this first: it is the smallest
item on the list, it is our own code, and it is the proof that the reporting was worth adding.

## How to work an item

1. `HOLYC_ASM_SKIPS=1` on a case that includes the file, to confirm it is still dropped.
2. Read the block and name the OPERATION, not the instructions.
3. Portable HolyC where possible. A `holyc_target` hook only when the operation genuinely differs
   per architecture — and then implement it for rv64 first, leaving the hook NULL elsewhere, which
   is the pattern `host/holyc_target.h` already describes.
4. Check the symbol actually appears in `HOLYC_MAP` afterwards. Compiling is not working: that is
   the whole reason this document exists.
