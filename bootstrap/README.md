# Bootstrap: bare-metal REPL

Interactive HolyC on RISC-V (UART). Product guide: **[docs/REPL.md](../docs/REPL.md)**.
Self-host DoD: **[docs/SELF_HOST.md](../docs/SELF_HOST.md)**.
Honesty gate: **[tests/REGRESSION.md](../tests/REGRESSION.md)**. Seed `MEM_*` come from
`seed/MemMapSelected.hc` (same bases as `Kernel/RVAutoConf.HH`; rewrite with
`make -C templeos-riscv syncconfig`) — [PLATFORM.md](../templeos-riscv/PLATFORM.md).

## Two guest paths (migration)

| Output | Build | Guest runtime | CI |
|--------|-------|---------------|-----|
| `build/repl-holyc.elf` | `make repl-holyc` | **HolyC only** — AOT blob, `start.hc` entry, no host slots | **Product** — `repl-holyc-smoke`, `repl-holyc-regression`, `bootloader-smoke` |
| `repl.elf` | `make -C bootstrap -f Makefile.repl` | **C** (`worry_dream_repl.c` + `startup.s`) + host compiler in-guest | **Deprecated** dual-run — `repl-smoke`, `repl-regression` until [SELF_HOST.md](../docs/SELF_HOST.md) A3 |

**Mandate:** destination is HolyC built by the guest compiler — no second C runtime.
Do not grow `jit.hc` as a parallel language. Mac `holyc-riscv` (C) stays as bootstrap
workstation tooling — see SELF_HOST.md (not “purge all C”).

### Non-HolyC inventory (excluding `archive/`)

| Path | Kind | Category | Notes |
|------|------|----------|-------|
| `worry_dream_repl.c` | C (~3.6k LOC) | **→ HolyC** (Track A) | **Deprecated** legacy guest: readline, UART ring, compile slot, editor repair |
| `startup.s` | asm | **→ HolyC** | Replaced by `hc_repl/start.hc` `asm{_start}` on HolyC path |
| `holy_rt.h` / `holy_rt_names.h` | C headers | **Host / AOT** | Bare-metal import resolver + oracle helpers for host `holyc-riscv`; not REPL OS APIs |
| `linker.ld` | ld script | **Host link** | Legacy `repl.elf` sections/BSS |
| `kernel_linker.ld` | ld script | **Unused** | Orphan; kernel uses `tests/exec/harness/link_exec.ld` |
| `Makefile.repl` | Makefile | **Host build** | Builds legacy `repl.elf` + generates blobs |
| `gen_seeds.py` | Python | **Host tool** | `seed/*.hc` → `seed_files.h` |
| `gen_boot_blob.py` | Python | **Host tool** | Boot-order concat → `boot_blob_embed.h` (+ optional AOT validate) |
| `seed_files.h` | generated C | **Generated** | C table for `memfs_seed()` in legacy path |
| `boot_blob_embed.h` | generated C | **Generated** | Concatenated seed snapshot (legacy boot embed; per-seed `Run` still primary) |
| `boot_runtime.hc` / `.bin` | generated HC | **Generated** | Intermediate for `gen_boot_blob.py` |
| `hc_repl/gen_embed.py` | Python | **Host tool** | Curated seed slice → `seed_embed.hc` for AOT memfs |
| `hc_repl/link.ld` | ld script | **Host link** | Wraps AOT blob as `repl-holyc.elf` / `hc_repl.elf` |
| `hc_repl/Makefile` | Makefile | **Host build** | Mac AOT → `build/hc_repl.elf` + `build/repl-holyc.elf` |
| `seed/*.hc` (71 files incl. tutorials/datasheet) | HolyC | **Source of truth** | Editable memfs + boot runtime |
| `hc_repl/*.hc` | HolyC | **HolyC guest** | AOT entry, thin JIT, memfs — no C in the image |

Host compiler sources: **`../host/`** (bootstrap AOT — **keep**; linked into legacy `repl.elf` only).

### Migration status

- **Done on HolyC path:** `_start` in `start.hc`, UART MMIO, memfs @ `0x87800000`, zero `0x87001xxx` slots, seed tree slice in AOT memfs.
- **Still C on legacy path:** readline/history, IRQ UART drain, host compile slot, `HostSlotsInstall`, fmt/editor hatches, `startup.s` trap prologue.
- **`holy_rt.h`:** keep for host AOT + legacy in-guest compile until guest `Compiler_RV` owns the loop.

### Phased plan

See **[docs/SELF_HOST.md](../docs/SELF_HOST.md)** Track A (A0–A6) and Track B (B0–B3). Short form:

| Phase | Goal |
|-------|------|
| **Now** | Dual-run CI: HolyC product smokes + deprecated legacy honesty |
| **A3** | Flip honesty default to `repl-holyc`; quarantine/delete `worry_dream_repl.c` |
| **B0+** | Guest `Cmp` rebuilds Compiler/Kernel/Adam on target |

## Layout

| Path | Role |
|------|------|
| `Makefile.repl` | Legacy build → `repl.elf` |
| `worry_dream_repl.c` | C guest REPL + host slots — **deprecated** |
| `holy_rt.h` / `holy_rt_names.h` | Host + legacy-guest AOT imports |
| `startup.s` / `linker.ld` | Legacy boot + link |
| `gen_seeds.py` / `gen_boot_blob.py` | Host bake tools |
| `seed_layout.py` | Memfs dirs: `/Home` `/Lib` `/Tutorials` … (basename aliases) |
| `seed/` | Editable HolyC memfs seeds |
| `hc_repl/` | HolyC-only AOT guest → `build/repl-holyc.elf` — **do not grow `jit.hc`** |
| `archive/` | Historical demos — **not built by CI** |

## Build / run

```bash
# Host compiler (required bootstrap — stays C)
make                          # → ./holyc-riscv

# Product HolyC-only guest (no C runtime in the image)
make repl-holyc
qemu-system-riscv64 -M virt -bios none -kernel build/repl-holyc.elf -nographic

# Deprecated legacy (CI dual-run until A3)
cd bootstrap && make -f Makefile.repl
qemu-system-riscv64 -M virt -bios none -kernel repl.elf -nographic

# Gates
make repl-holyc-smoke
make repl-holyc-regression
make bootloader-smoke
make repl-smoke              # legacy
make repl-regression         # legacy honesty
```

After editing `bootstrap/seed/*.hc`: `make repl-blob` (regenerates `boot_blob_embed.h`).
