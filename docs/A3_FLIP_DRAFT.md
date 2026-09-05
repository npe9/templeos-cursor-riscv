# A3 / G7 flip — draft notes (**APPLIED**)

Flip edits from this draft are applied to `Makefile` + docs (A3 **Done**).
`worry_dream_repl.c` delete remains a **follow-up** (do not delete yet).

Scaffolding: `make a3-flip-check` prints **READY**; [SELF_HOST.md](SELF_HOST.md) G7
blockers empty. ZMODEM / Fmt / Demo waived. **G2 trap/Ctrl-C** and **G3 livedrv** Done.
`REMAINING_BLOCKERS` empty. `bootloader-smoke` PASS.

G2 install note (product path): `TrapInit` must call `TrapBareMtvec` whenever
`TRAP_VEC_OFF≠0` — do **not** gate on `FnAddr("TrapBareMtvec")` (asm labels are
absent from the thin JIT table; that skip left mtvec=0 and hung `Fault`).

Related: [GAPS.md](GAPS.md) **G7 Done**, [CI.md](CI.md), [REGRESSION.md](../tests/REGRESSION.md).

---

## Intent (post-flip)

1. Honesty path = HolyC only (`repl-holyc-smoke`, `repl-holyc-regression`, `repl-cmp-smoke`, `bootloader-smoke`).
2. Drop **required** legacy dual-run (`repl-smoke` / `repl-regression`) from `qemu-integration`. **Done.**
3. Optionally delete `bootstrap/worry_dream_repl.c` (+ legacy `Makefile.repl` link path) in a follow-up once nothing else references it. **Not yet.**
4. Keep `SKIP_REPL_LEGACY` out of GitHub Actions forever (variable obsolete; dual-run branch removed).

---

## Pre-flight (was green)

```bash
make a3-flip-check          # smoke + holyc-regression + repl-cmp → READY
make bootloader-smoke       # A3 criterion 2 (not inside a3-flip-check)
make trap-smoke             # optional focused G2; also covered in holyc-regression
```

---

## Applied: `Makefile` `qemu-integration`

Removed legacy dual-run branch; removed required `zmodem-smoke` (keep `dump-changes-smoke`).
Help text demotes `repl-smoke` / `repl-regression` to local / scheduled delete.

---

## Applied: docs / AGENTS

| File | Change |
|------|--------|
| [SELF_HOST.md](SELF_HOST.md) | A3 **Done**; flip checklist checked; worry_dream delete still open |
| [GAPS.md](GAPS.md) | G7 → Done; critical-path note |
| [CI.md](CI.md) | Legacy + zmodem → optional local |
| [REGRESSION.md](../tests/REGRESSION.md) | Primary gate = `repl-holyc-regression` only |
| [AGENTS.md](../AGENTS.md) | `repl-smoke` / `repl-regression` no longer required CI |
| [REPL.md](REPL.md) | HolyC-only honesty wording |

`.github/workflows/ci.yml` needs no change (`make qemu-integration` picks up Makefile).

---

## Follow-up delete (separate commit after CI green)

- Delete or move under `bootstrap/archive/`: `worry_dream_repl.c`, legacy `startup.s` link bits used only by `Makefile.repl` guest C path.
- Retire `make repl-smoke` / `repl-regression` targets or point them at an archived recipe.
- Remove leftover `SKIP_REPL_LEGACY` mentions if any remain.

---

## Explicit non-goals of the flip

- Deleting Mac `host/*.c`
- Embedding ZMODEM into thin `repl-holyc`
- Growing `jit.hc`
- Retiring `templeos-smoke` (that is **G10** / A4)
