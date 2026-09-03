# HolyC AOT REPL (Mac-built guest) — temporary bridge

> **Transitional.** Lives under `bootstrap/hc_repl/` on purpose. Language destination is
> `Compiler/Compiler_RV.PRJ` + `ExePutS` — not a third REPL architecture. See
> [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md) and [docs/SELF_HOST.md](../../docs/SELF_HOST.md).

## Mandate

- **Host:** Mac/`holyc-riscv` AOT-compiles HolyC → RISC-V ELF.
- **Guest:** UART, memfs, Print, MAlloc, Dir, Src, `DumpFile`/`DumpMem`, thin HolyC `jit.hc`, `asm{_start}`.
- **No** `0x87001xxx` host slots, **no** C guest runtime, **no** `crt0.S`.

## Convergence (do not grow `jit.hc` as the language)

Interactive compile on the real OS path is TempleOS **`ExePutS` / `COCCompile`** with
**`Compiler/Compiler_RV.PRJ`** (Lex/Prs → IC → Opt → RV `OptPass789A`). See
[`templeos-riscv/COMPILER_RV.md`](../../templeos-riscv/COMPILER_RV.md).

**A2 Done** via converge image: **`make repl-cmp`** → `build/repl-cmp.elf`
(Kernel_RV + `Compiler_RV_Body`, ~1.9 MB). Smoke: `make repl-cmp-smoke` (needles
`A2: Compiler_RV owns ExePutS`, `A2: Cmp compiled 40+2`). Embedding full Cmp into this
thin memfs REPL (~288 KB) is not feasible — keep ExePutS→`JitTry` here for Dir/Src honesty
only; **do not grow `jit.hc`**.

```bash
make repl-cmp-smoke
qemu-system-riscv64 -M virt -m 128M -bios none -kernel build/repl-cmp.elf -nographic
```

## Build / run (this bridge)

```bash
make repl-holyc && make repl-holyc-smoke
# → build/repl-holyc.elf (alias: build/hc_repl.elf)
qemu-system-riscv64 -M virt -bios none -kernel build/repl-holyc.elf -nographic
```

Self-host plan: [docs/SELF_HOST.md](../../docs/SELF_HOST.md).

## Remaining non-HolyC

| Bytes | What |
|------:|------|
| **0** | crt0 / C runtime / host slots in the guest image |
| Host only | `holyc-riscv`, `ld`/`objcopy` to wrap the blob as a QEMU ELF |
