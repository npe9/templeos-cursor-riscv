# Tools

| Path | Role |
|------|------|
| `pack_tosb.c` / `pack_tosb` | Pack TempleOS-style blobs |
| `gen_cmp_imports.py` | Generate `Kernel/RVCmpImports.HC` |
| `gen_host_bin_embed.py` | Embed host bins for guest |
| `legacy/` | Retired root utilities (`riscv_dump`, early backends) |
| `uart_recv_dump.py` | Decode `DumpFile` / `DumpMem` base64 frames from REPL UART |

### UART binary export

The REPL has no `tar` or YMODEM stack. Export memfs files or RAM windows with
`DumpFile("name")` or `DumpMem(addr, n, "label")` (see `bootstrap/seed/files.hc`).
Output is ASCII-safe base64 between `$HC_DUMP …$` / `$HC_END$` markers
(Print emits a single `$`; source uses `$$` in format strings).

```bash
# Receive while QEMU runs (-nographic merges serial with stdout):
qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \
  2>&1 | python3 tools/uart_recv_dump.py -o /tmp/dumps
# At prompt: DumpFile("boot.hc");

# One-shot (pipe command; --once exits after first dump):
( sleep 12; printf 'DumpFile("boot.hc");\n' ) | \\
  qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \\
  2>&1 | python3 tools/uart_recv_dump.py --once -o /tmp/dumps

# Bundle on host: tar czf seeds.tgz -C /tmp/dumps .
```

Host AOT compiler sources: **`../host/`** (built by root `make`).
Layout: [docs/LAYOUT.md](../docs/LAYOUT.md).
