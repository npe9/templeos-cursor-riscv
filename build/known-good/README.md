# Known-good ELF pins

Local **last-good** hashes for recovery bisect when a rebuild starts CRASH/hanging.
Pins live here under `build/` (gitignored); this README is tracked.

See [docs/OPS.md](../../docs/OPS.md).

## What gets pinned

| Artifact | Typical path | When |
|----------|--------------|------|
| Product HolyC REPL | `build/repl-holyc.elf` (alias `build/hc_repl.elf`) | After `make repl-holyc-smoke` green |
| Legacy full UART REPL | `bootstrap/repl.elf` | After `make repl-smoke` / regression green |
| Plat kernel (CI default) | `build/kernels/virt/plat.elf` | After `make kernel-plat-smoke` green |
| Other boards | `build/kernels/<machine>/plat.elf` | After that board’s plat smoke |

Missing files are skipped with a note (pin what exists).

## Commands

```bash
make known-good-pin      # write *.sha256 (+ PIN.txt summary) for present ELFs
make known-good-check    # exit nonzero if a pinned ELF hash drifted
```

Or directly:

```bash
tests/scripts/pin_known_good.sh
tests/scripts/pin_known_good.sh --check
tests/scripts/pin_known_good.sh --pin build/kernels/sifive_u/plat.elf
```

## Files written (local only)

```
build/known-good/
  README.md                 # this file (tracked)
  PIN.txt                   # human summary: path  sha256  mtime
  repl-holyc.elf.sha256
  bootstrap-repl.elf.sha256
  virt-plat.elf.sha256
  …
```

Do **not** commit `*.sha256` / `PIN.txt` unless the team explicitly wants shared
pins in-tree. Default: local operator cache after a known-green smoke.

## Recover workflow

1. Green smoke → `make known-good-pin`
2. Later breakage → `make known-good-check` (confirms drift) and/or restore the
   pinned ELF from your backup / CI artifact / rebuild at the recorded commit
3. Guest session: export with `FsChanges` / `DumpChanges` first ([FILE_EXPORT.md](../../docs/FILE_EXPORT.md))
