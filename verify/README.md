# Optional verification artifacts

Machine-checked / model-checked slices for this repo. **Not required for `make ci`.**

See [docs/VERIFICATION.md](../docs/VERIFICATION.md) for goals, tool matrix, and roadmap.

| Path | Phase | Needs |
|------|-------|-------|
| [p0_rv_i/](p0_rv_i/) | P0 | `python3` + C compiler (`cc`) |

```bash
make verify-p0
```
