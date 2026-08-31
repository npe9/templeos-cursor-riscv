# Tools

| Path | Role |
|------|------|
| `pack_tosb.c` / `pack_tosb` | Pack TempleOS-style blobs |
| `gen_cmp_imports.py` | Generate `Kernel/RVCmpImports.HC` |
| `gen_host_bin_embed.py` | Embed host bins for guest |
| `legacy/` | Retired root utilities (`riscv_dump`, early backends) |

Host AOT compiler sources: **`../host/`** (built by root `make`).
Layout: [docs/LAYOUT.md](../docs/LAYOUT.md).
