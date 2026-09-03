# Getting files off a running guest

Operator recipes for **guest → host** export from a live TempleOS / HolyC RISC-V
session (UART REPL, bootloader+REPL, bare QEMU / FPGA serial). Product language is
boards / `MEM_*` / HolyC; QEMU lines below are the usual CI harness recipes operators
use today.

There is **no guest `tar`**. Virtio-9p is a **client**: QEMU’s virtfs backend is the
server, so the guest can both **import** host files and **export** memfs bytes onto
the share (`NineExport` / `Virtio9pWritePath`). UART framed base64 / ZMODEM remain
the path when virtfs is unavailable.

## Quick chooser

| Goal | Use | Status |
|------|-----|--------|
| Copy a memfs file (or RAM window) to the Mac/Linux host | **`DumpFile` / `DumpMem` + `tools/uart_recv_dump.py`** | **Working** (full UART REPL and `repl-holyc`) |
| Binary-safe ZMODEM (`sz`/`rz` / `trzsz --zmodem`) | **`ZmodemSend` / `tools/uart_recv_zmodem.py`** | **Working** (full UART REPL only; **waived** on thin `repl-holyc` — G11) |
| Native trzsz (`tsz` / stock `trzsz`, no `--zmodem`) | **`TrzszSend` / `tools/uart_recv_trzsz.py`** | **Working** (full UART REPL send-only; **waived** on thin image — G11) |
| Batch “what changed this session” | **`DumpChanges`** (UART) / **`ZmodemSendChanges`** / **`TrzszSendChanges`** | **Working** — `DumpChanges`/`FsChanges` on full UART REPL **and** `repl-holyc` (product path); ZMODEM/trzsz batch full UART REPL only |
| Pull host files *into* the guest | Virtio-9p **client** (`Mount9p` / `Virtio9p`) | Working import |
| Push guest memfs *onto* host share | Virtio-9p **client write** (`NineExport` / `Virtio9pWritePath`) | Working (nested `Tmkdir` + overwrite; needs virtfs) |
| Kernel plat / RedSea image as a host file | Build tree / OpenOCD / gdb — not a guest dump API | See [limitations](#what-is-not-implemented) |

## Image matrix (what actually has `DumpFile`)

| Guest image | Build | `DumpFile` / `DumpMem` |
|-------------|-------|------------------------|
| Legacy full UART REPL | `make repl-blob` then `make -C bootstrap -f Makefile.repl` → `bootstrap/repl.elf` | **Yes** — `files.hc` is in the boot blob |
| Baremetal install of that REPL | `make baremetal` → `build/baremetal/repl.{elf,bin}` | **Yes** (same legacy guest) |
| Product HolyC AOT REPL | `make repl-holyc` → `build/repl-holyc.elf` | **Yes** — AOT `#include`s `seed/files.hc` |
| Bootloader + HolyC REPL blob | `make bootloader-repl` | **Yes** (same AOT blob) |
| Kernel plat / phase3 smokes | `make kernels` / kernel-*-smoke | **No** `DumpFile`; UART is print/oracle only |

`Help;` on the full REPL advertises `ZmodemSend` / `FsChanges` (and `DumpFile`).
On `repl-holyc` / bootloader-repl, `DumpFile` / `DumpMem` / `DumpB64` / `DumpChanges` /
`FsChanges` / `FsReplay` / `FsRecover` (`Recover;`) work (journal via seed `fs.hc`
include + `fs_dump_changes.hc`). `ZmodemSend` / `ZmodemSendChanges` / `TrzszSend` /
`TrzszSendChanges` stay full-REPL-only — **G11 waived** (not embedded in the AOT image).

**Practical rule:** framed base64 export and session `DumpChanges` work on the product
HolyC image (`build/repl-holyc.elf` / bootloader-repl) — that is the **A3 operate-through**
path. **G11 waived:** do **not** AOT-embed `zmodem.hc` / `trzsz.hc` on thin images
(~28 KiB combined, binary protocol + XON/XOFF — size/JIT risk). Prefer `DumpFile` /
`DumpChanges`, or virtio-9p `NineExport` when virtfs is available ([NINEP.md](NINEP.md)).
Legacy full REPL (`bootstrap/repl.elf`) keeps ZMODEM/trzsz until A3 deletes `worry_dream`.

---

## Method 1 — UART framed base64 (`DumpFile` / `DumpMem`)

### When to use

Default way to get memfs edits, seed copies, trap snapshots, or a framebuffer dump
off a **running** UART console without corrupting the terminal (unlike raw `Cat` of
binary).

### Prerequisites

- Guest with `DumpFile` / `DumpMem` compiled in (see [image matrix](#image-matrix-what-actually-has-dumpfile)).
- Host can see guest UART as a byte stream (QEMU `-nographic` / `-serial stdio`, or
  board USB-serial / OpenOCD UART).
- Python 3 on the host (`tools/uart_recv_dump.py`).

Do **not** use `-serial mon:stdio` for automated receive if monitor escape sequences
will interleave with the dump; plain `-nographic` (or a dedicated serial PTY) is safer.
Interactive FB hold often uses `-serial mon:stdio` ([BOARD_FB.md](../templeos-riscv/BOARD_FB.md))
— pipe dumps on a clean serial attach instead.

### Guest

```holyc
DumpFile("boot.hc");                 // memfs file → UART frames
DumpFile("Home/hello.hc");           // hierarchical path OK if unique basename in header
DumpChanges;                         // $HC_CHANGES$ manifest + DumpFile each dirty file
DumpMem(MEM_FB, 640*480*4, "fb.raw");
DumpMem(MEM_TRAP_SNAP, 136, "trap_snap");
```

API lives in `bootstrap/seed/files.hc` (`DumpB64`, `DumpFile`, `DumpMem`);
`DumpChanges` in `bootstrap/seed/zmodem.hc` (full UART REPL) and
`bootstrap/hc_repl/fs_dump_changes.hc` (product AOT). Markers
(Print collapses `$$` → `$`):

```
$HC_DUMP name=boot.hc size=1234$
…base64…
$HC_END$
```

`DumpChanges` reuses those dump frames after a manifest (Print collapses `$$`):

```
$HC_CHANGES epoch=0..1 count=2 dumps=1$
  W  Home/foo.hc
  D  Tmp/old.hc
$HC_END$
$HC_DUMP name=Home/foo.hc size=…$
…
$HC_END$
```

Deleted / directory ops stay in the manifest; only still-existing files get `$HC_DUMP$`.

### Host

```bash
# Interactive: start receiver, then type DumpFile at the guest prompt
make -C bootstrap -f Makefile.repl   # or: make baremetal
qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \
  2>&1 | python3 tools/uart_recv_dump.py -o /tmp/dumps

# One-shot (pipe command after boot chatter; --once exits after first $HC_END$)
( sleep 12; printf 'DumpFile("boot.hc");\n' ) | \
  qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \
  2>&1 | python3 tools/uart_recv_dump.py --once -o /tmp/dumps

# One-shot DumpChanges (manifest + bodies; --once waits for dumps=N)
( sleep 12; printf 'FileWrite("Home/t.hc","x",1); DumpChanges;\n' ) | \
  qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \
  2>&1 | python3 tools/uart_recv_dump.py --once --keep-path -o /tmp/dumps
# → /tmp/dumps/CHANGES  and  /tmp/dumps/Home/t.hc

make dump-changes-smoke
```

Baremetal / FPGA: same guest calls; point the serial device (or `qemu-baremetal.sh`
stdio) at the receiver instead of a bare terminal:

```bash
make baremetal
# QEMU RAM load (see BAREMETAL.md)
qemu-system-riscv64 -M virt -m 128M -bios none \
  -kernel build/baremetal/repl.bin -nographic \
  2>&1 | python3 tools/uart_recv_dump.py -o /tmp/dumps
```

Product path: `make repl-holyc` then the same `DumpFile` + `uart_recv_dump.py` recipe
with `-kernel build/repl-holyc.elf` (or `make bootloader-repl` + that payload).

More detail: [tools/README.md](../tools/README.md).

### Limitations / failure modes

| Issue | Detail |
|-------|--------|
| Memfs size | Per-file cap **65535** bytes (`MEMFS_CAP` in `fs.hc`); larger objects need `DumpMem` of a RAM window or host-side build artifacts |
| Slow / host overrun | Base64 expands ~4/3; use host Ctrl-S/Ctrl-Q (`UartXonXoff`, default on) — [UART.md](UART.md); RTS/CTS stub is no-op on virt. Prefer 9P for large trees ([NINEP.md](NINEP.md)) |
| Size mismatch | Receiver warns if decoded length ≠ header `size=` |
| Truncation | Missing `$HC_END$` → exit 1 / `WARN truncated dump` |
| Basename only | Default host writes `Path(name).name` — two dumps with the same basename overwrite. `DumpChanges` recipe uses `--keep-path` |
| No upload | UART path is export-only; no `RecvFile` yet |
| Multiplexed stdio | Mixing dump with heavy Print noise can confuse operators; use `--list` to dry-run headers |

### If this path is down

- Text-only: `Cat("file.hc");` and capture the terminal log (**unsafe for binary** —
  ESC / Ctrl-C / NUL can break the line).
- Hardware: OpenOCD / gdb `dump` of `MEM_FS` (`0x87800000` on default virt map) — raw
  memfs arena, not individual files.
- Prefer rebuilding from the host tree when the guest only mirrored upstream seeds.

---

## Method 2 — Virtio 9p (host share) — import and export

Pedagogy (why 9P, message sequence, fid/qid, MMIO vs PCI): [NINEP.md](NINEP.md).

### When to use

- **Import:** bring host files into the guest (virtfs → memfs / kernel read), e.g.
  drop a test file for `NinepSmoke` / `Virtio9pSelfTest`.
- **Export:** push a guest memfs (or buffer) file onto the host share when UART
  dump is painful — `NineExport` / `NineExportAs` / `Virtio9pWritePath`.

### Prerequisites

- Board / Kconfig with `CONFIG_HAS_VIRTIO_9P` (virt default).
- QEMU (or equivalent) virtio-9p device + host directory (`security_model=none`
  so the guest can create/write).
- Guest: REPL `Run("ninep.hc");` then `Mount9p` / `NineExport` / `NinepSmoke`, or
  kernel `Virtio9p.HC` (`make kernel-virtio-9p-smoke`).

### Host attach (QEMU harness)

```bash
mkdir -p /tmp/tos-share
echo 'hello from 9p' >/tmp/tos-share/test.txt

qemu-system-riscv64 -M virt -m 256M -bios none -kernel bootstrap/repl.elf -nographic \
  -fsdev local,id=fsdev0,path=/tmp/tos-share,security_model=none \
  -device virtio-9p-device,fsdev=fsdev0,mount_tag=hostshare
```

### Guest — import

```holyc
Run("ninep.hc");
NinepSmoke();                    // expect 0 — reads test.txt + writes export.txt
Mount9p("host/", "hostshare");   // import share root regular files into memfs
```

### Guest — export (guest → host)

```holyc
Run("ninep.hc");
FileWrite("Home/a/b.hc", "hi from guest\n", 14);
NineExport("Home/a/b.hc");            // → /tmp/tos-share/Home/a/b.hc (Tmkdir)
NineExportAs("Home/a/b.hc", "n.hc");  // → /tmp/tos-share/n.hc
FileCopy9p("boot.hc", "boot.hc");     // alias of NineExportAs
```

Kernel (buffer path; no memfs required for the write itself):

```holyc
Virtio9pInit;
Virtio9pWritePath("Home/nest/out.hc", buf, len);  // parents created
NineExport("A:/Some.TXT");   // FileRead local → share Some.TXT (drive stripped)
```

Host check after guest write:

```bash
cat /tmp/tos-share/Home/a/b.hc
# or CI: make kernel-virtio-9p-smoke / make repl-9p-smoke
```

Kernel: `Man("Virtio9p");` / `Virtio9pInit;` / `Mount9p;` / `NineExport;` — see
[PLATFORM.md](../templeos-riscv/PLATFORM.md) § 9p / virtfs.

### Limitations

- **Nested create (REPL):** `NinepWritePath` / `NineExport` walk path components and
  `Tmkdir` missing parents (mode `0755`, depth ≤ 8). `NineExport("Home/a/b.hc")`
  writes that relative path on the share (drive prefixes like `A:` are stripped).
- **Overwrite (REPL / kernel smoke):** existing share files are removed (`Tremove`)
  then recreated with `Tlcreate`/`Twrite`.
- **Kernel include path:** `Virtio9pWritePath` under `Kernel_RV.PRJ` stays create-only
  (HolyC AOT); nested + overwrite are covered by the primary-TU smoke helpers and by
  REPL `NineExport`.
- **Not a 9p server:** the guest does not serve memfs/RedSea to the host; QEMU
  virtfs remains the server.
- REPL `Mount9p` imports **regular files at share root** (skips directories);
  kernel `Virtio9pImportFile` reads into a 4 KiB buffer.
- Write chunk size is 4 KiB (virtqueue req/rsp buffers are 8 KiB apart).
- PCI 9p transport: queues + SendRecv (`NinePVirtioPci.HC`); prefer MMIO when both present.
- Needs virtfs attached — bare serial / FPGA without 9p still uses Method 1 / 3.

### Circumvention (no virtfs)

Use [Method 1](#method-1--uart-framed-base64-dumpfile--dumpmem) or
[Method 3](#method-3--zmodem--session-changes).

---

## Method 3 — ZMODEM / native trzsz / session changes

`UartPut` writes raw 16550 bytes (no CRLF mangling).

### ZMODEM (`sz` subset)

Guest `bootstrap/seed/zmodem.hc` speaks a minimal **sz** subset (ZRQINIT / ZFILE /
ZDATA / ZEOF / ZFIN) so host **`rz`** works. Use `trzsz --zmodem` (wraps lrzsz) or
`tools/uart_recv_zmodem.py`.

### Native trzsz (`tsz`)

Guest `bootstrap/seed/trzsz.hc` speaks the real trzsz wire protocol (`::TRZSZ:TRANSFER:S`
trigger, `#ACT`/`#CFG` JSON, zlib+base64 `#DATA`, MD5). Stock **`trzsz`** / terminal
integrations that auto-detect the trigger work **without** `--zmodem`. CI / QEMU PTY
recipe: `tools/uart_recv_trzsz.py` (`make trzsz-smoke`). Guest **send only** (no `trz`
upload into memfs yet). Compression uses zlib **stored** blocks (compatible decompress).

### Guest

```holyc
ZmodemSend("boot.hc");        // ZFILE name is Boot/boot.hc (canonical memfs path)
ZmodemSendDir("Tutorials");
TrzszSend("boot.hc");         // native trzsz (tsz), not ZMODEM
TrzszSendDir("Tutorials");
ExportFs("Tmp");              // file or directory (ZMODEM)
FsChanges;                    // journal since boot (W/C/D/R/…); see MEMFS_LOG.md
DumpChanges;                  // UART $HC_CHANGES$ + DumpFile bodies
ZmodemSendChanges;            // dirty files only (bit set on FileWrite/Del)
TrzszSendChanges;             // same dirty set over native trzsz
SendChanges;                  // alias of ZmodemSendChanges
```

`boot.hc` calls `FsEpochSeal(FS_EPOCH_BOOT);` after `Help` so later HolyC
`FileWrite`/`Del`/`DirMk` append journal records (and set dirty bits for ZMODEM/trzsz).
`FsSnap;` remains an alias of the boot seal.

### Host

```bash
# ZMODEM encoder/decoder unit test (no QEMU)
python3 tools/uart_recv_zmodem.py --selftest

# ZMODEM PTY round-trip
python3 tools/uart_recv_zmodem.py --qemu bootstrap/repl.elf -o /tmp/out \
  --cmd 'ZmodemSend("boot.hc");'
# → /tmp/out/Boot/boot.hc (ZFILE uses the memfs path, not the lookup name)

make zmodem-smoke

# Native trzsz
python3 tools/uart_recv_trzsz.py --selftest
python3 tools/uart_recv_trzsz.py --qemu bootstrap/repl.elf -o /tmp/out \
  --cmd 'TrzszSend("boot.hc");'
# → /tmp/out/boot.hc (basename)

make trzsz-smoke
# Host selftest (no QEMU): python3 tools/uart_recv_trzsz.py --selftest
# Note: needs a booting full UART REPL (boot seal). If Wave 1 trap/uart WIP
# aborts boot, fix that first; the smoke target is local (not yet in
# qemu-integration).

# Dedicated serial PTY + lrzsz (ZMODEM)
qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf \
  -display none -serial pty
# QEMU: char device redirected to /dev/pts/N
rz -yee < /dev/pts/N > /dev/pts/N
# then at the guest prompt: ZmodemSend("boot.hc");
```

Workflow: session edits → `FsChanges;` → `ZmodemSendChanges;` or `TrzszSendChanges;` →
files on host → `git diff`. Unified text diffs stay on the host (no guest `diff -u` yet).

`Help;` advertises `ZmodemSend` / `FsChanges`. `Man("Zmodem");` / `Man("Trzsz");`

---

## Kernel / plat / graphics sessions

| Situation | How to get bits off |
|-----------|---------------------|
| UART oracle smokes | Capture QEMU stdout (already how CI asserts) — text only |
| Framebuffer | Prefer `DumpMem(MEM_FB, …)` on a REPL that has `DumpMem`; kernel WinMgr demos are not a file-export API ([BOARD_FB.md](../templeos-riscv/BOARD_FB.md)) |
| RedSea / blk images | Host build outputs under `build/`; guest FS write-back to virtio-blk for export is not an operator recipe here |
| JTAG FPGA | OpenOCD `dump_image` / gdb of DRAM — last resort for memfs arena |

---

## What is not implemented

- Guest **9p server** (serve memfs / RedSea *to* the host as a 9p filesystem —
  client write/export to an existing QEMU virtfs share **is** implemented)
- UART **upload** (`RecvFile`) into memfs
- **`ZmodemSend` / `ZmodemSendChanges` / `TrzszSend` / `TrzszSendChanges` on `repl-holyc` / bootloader-repl**
  — **intentional waive (G11)**, not a missing feature for A3. Product substitutes:
  `DumpFile`/`DumpMem`/`DumpChanges`/`FsChanges`/`FsReplay`/`FsRecover` on the thin
  image + virtio-9p `NineExport` when virtfs exists. ZMODEM/trzsz remain on full UART
  REPL (`bootstrap/repl.elf`) until A3 deletes legacy.
- Guest **`tar`** / UART **trz** upload (native trzsz **send** / `tsz` is implemented)
- Unified **text** diff (`git diff` on the host). Guest `FsDiff;` is size/hash vs boot snap; `FsDiff(a,b)` is epoch-range journal ops.

Canonical short note in tools: [tools/README.md](../tools/README.md). Platform 9p
honesty: [PLATFORM.md](../templeos-riscv/PLATFORM.md).

## Related

- [UART.md](UART.md) — serial primer; [FLOW_CONTROL.md](FLOW_CONTROL.md) — Ctrl-S/Ctrl-Q ops
- [NINEP.md](NINEP.md) — virtio-9p; prefer over terminal bulk copy
- [MEMFS_LOG.md](MEMFS_LOG.md) — change journal / epochs design (`FsChanges`, boot baseline)
- [REPL.md](REPL.md) — how to run the UART REPL
- [BAREMETAL.md](BAREMETAL.md) — FPGA / pflash / bootloader-repl launch
- [SELF_HOST.md](SELF_HOST.md) — guest rebuild direction (export is orthogonal)
- [../templeos-riscv/PLATFORM.md](../templeos-riscv/PLATFORM.md) — virtio-9p import
- [../tools/README.md](../tools/README.md) — `uart_recv_dump.py` / `uart_recv_zmodem.py` / `uart_recv_trzsz.py`
