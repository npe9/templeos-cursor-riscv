# Tools

| Path | Role |
|------|------|
| `pack_tosb.c` / `pack_tosb` | Pack TempleOS-style blobs |
| `mk_redsea_seed_img.py` | Pack host files into a RedSea raw image (phase3 virtio `Compiler.BIN` + `Kernel.BIN` seeds) |
| `gen_cmp_imports.py` | Generate `Kernel/RVCmpImports.HC` |
| `gen_host_bin_embed.py` | Embed host bins for guest |
| `gen_adam_lite_embed.py` | Emits `Kernel/RVAdamLiteMenuSrc.HC` from in-tree `Adam/Menu_RV_Guest.HC` (nested guest `#include`; no full Menu U8[]) |
| `legacy/` | Retired root utilities (`riscv_dump`, early backends) |
| `uart_recv_dump.py` | Decode `DumpFile` / `DumpMem` / `DumpChanges` frames (`--keep-path`, `--selftest`) |
| `uart_recv_zmodem.py` | ZMODEM receive (`rz` subset) from REPL UART; `--selftest` / `--qemu` (QEMU **PTY**, not PIPE) |
| `uart_recv_trzsz.py` | Native trzsz receive (`tsz` client) from REPL UART; `--selftest` / `--qemu` (QEMU **PTY**, not PIPE) |
| `uart_mux.py` | Demux framed multi-channel UART (`frame.hc` / CONSOLE.md); `--selftest` / `-o DIR` / `--vt-split` / `--vt-panes` / `--vt-follow` / `--vt N` / `--vt-status` |
| `uart_gdb_proxy.py` | Guest `GdbStub` RSP over UART: `--selftest` / `--qemu` smoke / `--uart`+`--listen` for gdb |

### UART binary export

Operator guide: [docs/FILE_EXPORT.md](../docs/FILE_EXPORT.md).

**ZMODEM** (binary-safe, `rz` / `trzsz --zmodem`):

```bash
python3 tools/uart_recv_zmodem.py --selftest
python3 tools/uart_recv_zmodem.py --qemu bootstrap/repl.elf -o /tmp/out \
  --cmd 'ZmodemSend("boot.hc");'
# Guest: ZmodemSend("boot.hc");  ZmodemSendDir("Tutorials");  ZmodemSendChanges;
make zmodem-smoke
# Host lrzsz on a dedicated PTY:  rz -yee < /dev/pts/N > /dev/pts/N
```

**Native trzsz** (`tsz` / stock `trzsz` without `--zmodem`):

```bash
python3 tools/uart_recv_trzsz.py --selftest
python3 tools/uart_recv_trzsz.py --qemu bootstrap/repl.elf -o /tmp/out \
  --cmd 'TrzszSend("boot.hc");'
# Guest: TrzszSend("boot.hc");  TrzszSendDir("Tutorials");  TrzszSendChanges;
make trzsz-smoke
```

**Framed base64** (`DumpFile` / `DumpMem` / `DumpChanges`).
Output is ASCII-safe between `$HC_DUMP …$` / `$HC_END$` markers
(Print emits a single `$`; source uses `$$` in format strings).
`DumpChanges` prefixes `$HC_CHANGES …$` … `$HC_END$` then N dump frames.
Works on the full UART REPL (`bootstrap/repl.elf`). Use `--keep-path` for
memfs-relative names. `python3 tools/uart_recv_dump.py --selftest`

```bash
qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \
  2>&1 | python3 tools/uart_recv_dump.py -o /tmp/dumps
# At prompt: DumpFile("boot.hc");  DumpChanges;

( sleep 12; printf 'DumpFile("boot.hc");\n' ) | \\
  qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \
  2>&1 | python3 tools/uart_recv_dump.py --once -o /tmp/dumps

make dump-changes-smoke
```

**GDB RSP** (guest `GdbStub;` — [DEBUGGER.md](../docs/DEBUGGER.md)):

```bash
python3 tools/uart_gdb_proxy.py --selftest
make gdb-uart-smoke
# Covers ?, g/G, m/M, Z0/z0 (soft Bp), c→S05, soft-step s, swbreak+
# Interactive: GdbStub; on guest, then:
#   python3 tools/uart_gdb_proxy.py --uart /dev/pts/N --listen 3334
```

Host AOT compiler sources: **`../host/`** (built by root `make`).
Layout: [docs/LAYOUT.md](../docs/LAYOUT.md).
