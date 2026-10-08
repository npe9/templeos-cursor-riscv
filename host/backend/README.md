# host/backend — code-generation backend

The portable/ISA boundary for the multi-arch HolyC backend (see `docs/MULTIARCH.md` and
the plan). The rule is **structural**, so a stray architecture assumption is visible:

- **Files directly in `host/backend/` are ARCHITECTURE-NEUTRAL.** They may know about the IC,
  the eval-stack model, register *roles*, the `AbiDesc`, the byte stream, the fixup/relaxation
  engine, and the `TargetBackend` interface — but never a specific ISA's opcodes, register
  numbers, or instruction length. A RISC-V (or x86, ARM, …) assumption in a neutral file is a bug.
- **Per-ISA backends live in `host/backend/<isa>/`** — `riscv/`, `aarch64/`, `x86/`, `arm/`.
  Each implements the `TargetBackend` primitives for its ISA and owns all of its raw opcode
  encodings, register numbers, and encoding tables.

## Contents (grows as the refactor proceeds)

| Path | Role |
|------|------|
| `target.h` | Portable target descriptor (`holyc_target`: xlen, ptr_width, endian, …) + arch enum. |
| _(M3)_ `relax.*` | Portable fixup table + monotone-growth branch relaxation. |
| _(M4)_ `target_backend.h` | The `TargetBackend` vtable, `Em` context, `RegRole`/`RegFile`, `AbiDesc`. |
| _(M4)_ `riscv/` | The RISC-V backend (extracted from `host/compiler.c`, incl. `rv32_lift`). |
| _(M6+)_ `aarch64/` `x86/` `arm/` | Added per milestone, each GNU-verified + QEMU-smoked. |

## Build

`host/backend/**` sources are added explicitly to `COMPILER_SOURCES` in the top-level
`Makefile` (the build uses an explicit file list, not a glob); `-Ihost` already resolves
`backend/...` includes. RV64 output must stay byte-identical through the neutral-core
milestones — the gate is `make codegen-bytediff`.
