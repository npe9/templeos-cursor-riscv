# HolyC AOT REPL (Mac-built guest) — temporary bridge

> **Transitional.** Lives under `bootstrap/hc_repl/` on purpose. Language destination is
> `Compiler/Compiler_RV.PRJ` + `ExePutS` — not a third REPL architecture. See
> [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md).

## Mandate

- **Host:** Mac/`holyc-riscv` AOT-compiles HolyC → RISC-V ELF.
- **Guest:** UART, memfs, Print, MAlloc, Dir, Src, thin HolyC `jit.hc`, `asm{_start}`.
- **No** `0x87001xxx` host slots, **no** C guest runtime, **no** `crt0.S`.

## Convergence (do not grow `jit.hc` as the language)

Interactive compile on the real OS path is TempleOS **`ExePutS` / `COCCompile`** with **`Compiler/Compiler_RV.PRJ`** (Lex/Prs → IC → Opt → RV `OptPass789A`). See [`templeos-riscv/COMPILER_RV.md`](../../templeos-riscv/COMPILER_RV.md).

`hc_repl` stays a **bootstrap/demo** of Mac-AOT HolyC with zero C guest runtime until the kernel loads Compiler_RV. Prefer kernel+Compiler+Adam+WinMgr for graphics boot — not a third REPL architecture.

## Build / run

```bash
make hc-repl && make hc-repl-smoke
qemu-system-riscv64 -M virt -bios none -kernel build/hc_repl.elf -nographic
```

## Remaining non-HolyC

| Bytes | What |
|------:|------|
| **0** | crt0 / C runtime / host slots in the guest image |
| Host only | `holyc-riscv`, `ld`/`objcopy` to wrap the blob as a QEMU ELF |
