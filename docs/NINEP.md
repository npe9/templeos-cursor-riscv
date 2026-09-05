# 9P / remote filesystem (pedagogy)

How **filesystem-over-the-wire** works, why this tree prefers it over UART dump
protocols when a share exists, and how the HolyC **9P2000.L client** talks to
QEMU’s virtfs server.

**Operator recipes** (QEMU flags, `DumpFile` / ZMODEM chooser) stay in
[FILE_EXPORT.md](FILE_EXPORT.md). This page teaches the model.

Related: [UART.md](UART.md) (console primer — not a file protocol),
[FLOW_CONTROL.md](FLOW_CONTROL.md) (XON/XOFF is a safety net, not xfer),
[CONSOLE.md](CONSOLE.md) (wishlist / ch1 UART 9P later), [DRIVERS.md](DRIVERS.md),
[PLATFORM.md](../templeos-riscv/PLATFORM.md) § 9p / virtfs, [GAPS.md](GAPS.md),
`Man("Virtio9p")` / `Man("Mount9p")`.

Sources: `Kernel/NineP/*`, `Kernel/Drv/Virtio9p.HC`, `NinePVirtioMmio.HC`,
`NinePVirtioPci.HC`, `bootstrap/seed/ninep.hc`.

---

## Why not just ZMODEM? (or terminal mode)

**Rule of thumb** (paired with [UART.md](UART.md)): the UART is a **console**
(text, readline, short dumps). For filesystem work — import/export trees,
overwrite, nested dirs — use **virtio-9p** here. Do **not** treat the PTY as a
mount: raw `Cat` / endless `Print`, or growing ZMODEM on every board, fights
the same byte pipe as the REPL and debugger.

| | Local disk | UART dump / ZMODEM / trzsz | Remote FS (9P) |
|--|------------|----------------------------|----------------|
| **Abstraction** | path → bytes in one address space | framed byte stream on a console | **RPC messages**: walk / open / read / write |
| **Direction** | bidirectional by nature | usually **send-only** guest→host here | import **and** export on one share |
| **Structure** | directories, create, remove | one file (or batch of files) per session | tree ops (`Tmkdir`, create, clunk) |
| **Needs** | block/flash | working UART + host receiver | virtio-9p + host directory (virtfs) |
| **Contends with** | — | readline / `Print` / soft dbg ([UART.md](UART.md)) | Separate virtio channel (no console mux) |

UART framed base64 / ZMODEM remain the path when there is **no** virtfs (bare
serial, many FPGAs). They move blobs; they are not a filesystem. XON/XOFF
([FLOW_CONTROL.md](FLOW_CONTROL.md)) only keeps console dumps from overrunning
a slow host — it is **not** a file-transfer protocol. Prefer 9P when the
board/harness has a share — see CONSOLE wishlist item **#6**.

---

## Concepts

### Local FS vs network/remote FS

A local FS is “name → inode → blocks” inside one machine. A **remote** FS is the
same *idea* (paths, open, read) implemented as **messages** between a client and
a server. There is no magic `mount` syscall that invents coherence: the client
sends a request, the server answers, and both keep small pieces of state (file
handles, offsets).

In this project:

- **Server** = QEMU virtfs (`-fsdev` + `virtio-9p-*`) on the Mac/Linux host.
- **Client** = guest HolyC (`NinePClient` / seed `ninep.hc`).
- The guest is **not** a 9p server. Export means the client **writes** onto the
  host share.

### Stateless-ish RPC: fid and qid

9P is request/response (T* → R*). Two names matter:

| Term | Role |
|------|------|
| **fid** | Client-chosen **handle** (like an fd). Allocated, walked, opened, clunked. |
| **qid** | Server’s stable id for a file/dir (type/version/path). Returned on attach/walk. |
| **tag** | Matches each T-message to its R-reply (pipelining). |

Typical verbs this tree uses:

| Message | Meaning |
|---------|---------|
| `Tversion` / `Rversion` | Negotiate dialect + `msize` |
| `Tattach` / `Rattach` | Bind root fid to aname (mount tag) |
| `Twalk` / `Rwalk` | Resolve path components → new fid |
| `Tlopen` / `Rlopen` | Open (9P2000.**L** Linux flags) |
| `Tread` / `Twrite` | Byte I/O at offset |
| `Tclunk` | Drop a fid |
| `Tlcreate` / `Tmkdir` / `Tremove` | Create file / mkdir / remove |

“Stateless-ish”: the server does not remember your whole session the way NFS
v2/v3 sometimes did with magic cookies alone — you still hold **fids** until
`Tclunk`. Lose the connection and fids die.

### Plan 9 heritage; 9P2000 vs 9P2000.L

Plan 9 made “everything is a file” and **9P** the single FS protocol. **9P2000**
is the classic dialect (`Topen`/`Tcreate` with Plan 9 modes). **9P2000.L** is the
Linux/QEMU dialect: `Tlopen` / `Tlcreate` / `Treaddir` / `Tmkdir` with Linux open
flags and POSIX-ish modes. QEMU virtfs speaks **.L**; this repo’s opcodes match
`hw/9pfs/9p.h` (e.g. `Tlopen=12`, `Tmkdir=72`, `Tread=116`).

### Comparison: when each fits

| Protocol | Fit | Weakness for this OS |
|----------|-----|----------------------|
| **TFTP** | Boot ROM pulls one image | No real tree R/W; UDP/IP stack |
| **NFS-lite** | Unix hosts, heavy VFS | Complex; not what QEMU virtfs speaks |
| **SMB** | Windows shares | Huge; irrelevant to virt |
| **UART dump / ZMODEM** | No virtio; console-only boards | No mount, no import; shares the console pipe ([UART.md](UART.md)) |
| **9P over virtio** | Guest↔host directory on virt | Needs virtio-9p device |
| **9P over TCP** | Classic Plan 9 / some Linux | Needs IP stack — **not** in this tree |

### Virtio as transport vs raw TCP 9P

9P is the **language**. **Virtio** is one **pipe**: guest and host share a
virtqueue; each 9P message is a buffer on that queue. No IP, no sockets.

```text
  host directory (/tmp/tos-share)
        ↑
   QEMU virtfs server
        ↑
   virtio-9p (MMIO device or PCI function)
        ↑
   guest NinePTransport (SendRecv)
        ↑
   NinePClient  /  seed ninep.hc
        ↑
   HolyC NineExport / Mount9p / Virtio9pWritePath
```

TCP 9P would swap the middle for sockets; that needs a network stack. Explicit
non-goal today ([GAPS.md](GAPS.md)). UART 9P (CONSOLE ch1) is the long-term
alternative for boards without virtio.

---

## Protocol walkthrough

### Read a file (happy path)

```text
client                         server (QEMU virtfs)
  |  Tversion "9P2000.L", msize      |
  |--------------------------------->|
  |  Rversion …                      |
  |<---------------------------------|
  |  Tattach fid=root aname=hostshare|
  |--------------------------------->|
  |  Rattach qid(root)               |
  |<---------------------------------|
  |  Twalk root → fid2 "test.txt"    |
  |--------------------------------->|
  |  Rwalk qid                       |
  |<---------------------------------|
  |  Tlopen fid2 O_RDONLY            |
  |--------------------------------->|
  |  Rlopen …                        |
  |<---------------------------------|
  |  Tread fid2 off=0 count=N        |
  |--------------------------------->|
  |  Rread data                      |
  |<---------------------------------|
  |  Tclunk fid2                     |
  |--------------------------------->|
```

Seed helper: `NinepReadPath`. Kernel: `NinePClientReadPath` /
`Virtio9pReadPath`.

### Write / export (create or overwrite)

1. Walk parent directory (creating missing parents with **`Tmkdir`**).
2. **`Tlcreate`** on the leaf name, or if it exists **`Tlopen(O_RDWR|O_TRUNC)`**
   (fallback: `Tremove` + create).
3. **`Twrite`** in ≤4 KiB chunks (`P9_WRITE_CHUNK`).
4. **`Tclunk`** leaf (and temporary parent fids).

`NineExport("Home/a/b.hc")` → share path `Home/a/b.hc` with dirs created.
`NineExportAs(local, "n.hc")` writes basename `n.hc` at share root.
Drive prefixes (`A:`, `::`) are stripped for the share name — see [PATHS.md](PATHS.md).

### Nested dirs / remove (high level)

- **Create tree:** walk component-by-component; if walk fails, `Tmkdir` then walk
  again (`NinepEnsureParent` / `NinePClient` write-path helper).
- **Remove:** `Twalk` to fid → `Tremove` (also clunks). Used when create-on-exists
  fails and overwrite needs a clean slate.
- **Readdir:** `Tlopen` dir + `Treaddir` (kernel `Mount9p` imports **regular
  files at share root only** — skips directories).

---

## This repo

### Layers

| Layer | Path | Role |
|-------|------|------|
| Codec | `Kernel/NineP/NinePCodec.HC` | Put/get u16/u32/strings in messages |
| Client | `Kernel/NineP/NinePClient.HC` | Version/attach/walk/lopen/read/write/mkdir/… |
| Transport | `NinePTransport.HC` + `NinePVirtioMmio` / `NinePVirtioPci` | Virtqueue SendRecv + mount_tag |
| Facade | `Kernel/Drv/Virtio9p.HC` | `Virtio9pInit`, `Mount9p`, `NineExport`, … |
| REPL twin | `bootstrap/seed/ninep.hc` | Standalone MMIO client + same operator APIs |

Kconfig: `CONFIG_HAS_VIRTIO_9P` (virt default). Device ID **9**.

### MMIO vs PCI

| | MMIO (`virtio-9p-device`) | PCI (`virtio-9p-pci`) |
|--|--------------------------|------------------------|
| Discover | Scan virtio-mmio slots for magic + id 9 | ECAM find 9p + BAR4 |
| Queues | Legacy PFN queue at drv RAM | Modern virtio-pci rings |
| Bind | `NinePTransportBindMmio` | `NinePTransportBindPci` |
| Prefer | **`BindAny`**: MMIO first, else PCI | used when no mmio 9p |

REPL seed today is **MMIO-oriented**. Kernel facade prefers MMIO then PCI.
Smokes: `make kernel-virtio-9p-smoke` / `kernel-virtio-9p-pci-smoke` /
`repl-9p-smoke`.

### Operator APIs (exact)

**REPL** (`Run("ninep.hc");` on full UART REPL):

```holyc
NinepSmoke();                      // expect 0 — read test.txt, write/overwrite export.txt, nested Home/nest/out.hc
Mount9p("host/", "hostshare");     // seed: pulls test.txt into memfs (prefix optional)
NineExport("Home/a/b.hc");         // FileRead → share Home/a/b.hc (Tmkdir parents)
NineExportAs("Home/a/b.hc", "n.hc");
FileCopy9p("boot.hc", "boot.hc");  // alias of NineExportAs
```

**Kernel** (`Man("Virtio9p");`):

```holyc
Virtio9pInit;                      // Connect(0): BindAny + version + attach mount_tag
Virtio9pReadPath("test.txt", buf, cap);
Virtio9pWritePath("Home/nest/out.hc", buf, len);  // parents created
NineExport("A:/Some.TXT");         // drive stripped → share Some.TXT
NineExportAs(local, host_name);
Mount9p("host/", 0);               // readdir share root → import regular files
Virtio9pSelfTest("hello from 9p", 13);
```

Kernel smoke calls `NinePClientWritePath` from the primary TU
(`tests/exec/cases/kernel_virtio_9p_demo.hc`) because thin
`Virtio9pWritePath` wrappers under `Kernel_RV.PRJ` include paths have been
fragile under host AOT — prefer REPL `NineExport` for interactive export.

### Host attach (QEMU)

```bash
mkdir -p /tmp/tos-share
echo 'hello from 9p' >/tmp/tos-share/test.txt

qemu-system-riscv64 -M virt -m 256M -bios none -kernel … -nographic \
  -fsdev local,id=fsdev0,path=/tmp/tos-share,security_model=none \
  -device virtio-9p-device,fsdev=fsdev0,mount_tag=hostshare
# PCI: -device virtio-9p-pci,fsdev=fsdev0,mount_tag=hostshare
```

`security_model=none` so the guest can create/write.

### Diagram (data path)

```text
 ┌─────────────────────────────────────────────────────────┐
 │  Host                                                   │
 │    /tmp/tos-share/test.txt                              │
 │    /tmp/tos-share/Home/nest/out.hc   ←── NineExport     │
 │              ▲                                          │
 │         QEMU virtfs (9P server)                         │
 └──────────────┬──────────────────────────────────────────┘
                │ virtio-9p MMIO or PCI queues
 ┌──────────────▼──────────────────────────────────────────┐
 │  Guest                                                  │
 │    NinePVirtioMmio / NinePVirtioPci  (transport)        │
 │              ▲                                          │
 │         NinePClient  (Tversion…Twrite…Tclunk)           │
 │              ▲                                          │
 │    Virtio9p.HC  /  seed ninep.hc                        │
 │              ▲                                          │
 │         NineExport / Mount9p / Virtio9pWritePath        │
 │              ▲                                          │
 │         memfs / buffer (FileRead, FileWrite)            │
 └─────────────────────────────────────────────────────────┘
```

---

## Have vs missing (honest)

| Capability | Status | Notes |
|------------|--------|-------|
| 9P2000.L client over virtio-mmio | **have** | Kernel + REPL seed |
| Virtio-pci 9p queues + SendRecv | **have** | `NinePVirtioPci`; BindAny fallback |
| Import host → guest | **have** | `Virtio9pReadPath` / `ImportFile`; kernel `Mount9p` = share-root files; seed `Mount9p` thinner (`test.txt`) |
| Export guest → host share | **have** | `NineExport` / `NineExportAs` / `WritePath` |
| Nested `Tmkdir` parents | **have** | e.g. `Home/nest/out.hc` |
| Overwrite existing share file | **have** | `Tlopen` trunc or remove+create |
| Smokes read+export+nested | **have** | `repl-9p-smoke`, `kernel-virtio-9p-smoke`, `kernel-virtio-9p-pci-smoke` |
| Guest as 9p **server** | **missing** | Non-goal; host always serves |
| TCP / UART 9P | **missing** | Need IP or CONSOLE framing ch1 |
| Recursive tree import / VFS mount | **missing** | No full memfs mirror of host tree |
| RedSea ↔ virtfs sync | **missing** | Export is explicit client write |
| Boards without virtio-9p | **N/A** | Use [FILE_EXPORT.md](FILE_EXPORT.md) UART / ZMODEM |

Limits that bite operators: write chunk **4 KiB**; import buffer **4 KiB** on
kernel `ImportFile`; needs virtfs attached; kernel AOT wrapper fragility (call
`NinePClientWritePath` from primary TU in smokes).

---

## Related

- [UART.md](UART.md) — serial console primer; use UART for TTY, not bulk FS
- [FLOW_CONTROL.md](FLOW_CONTROL.md) — Ctrl-S/Ctrl-Q ops; not a substitute for 9P
- [FILE_EXPORT.md](FILE_EXPORT.md) — Method 2 recipes + UART dump / ZMODEM when no virtfs
- [CONSOLE.md](CONSOLE.md) — wishlist #6 / UART 9P (ch1) later
- [PLATFORM.md](../templeos-riscv/PLATFORM.md) — board matrix + QEMU attach
- [MEMFS_LOG.md](MEMFS_LOG.md) — which files changed; 9P moves the bytes
- [DRIVERS.md](DRIVERS.md) — virtio driver survey
