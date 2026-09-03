# Memfs change journal / epochs

**Status: P0–P6 done** (journal + boot seal + checkpoint/diff + `DumpChanges` UART
+ in-place `Rename` + ring wrap/`FS_OP_WRAP` + `FsReplay` / soft `Recover` reseal).
**P3** `SendChanges` is `ZmodemSendChanges` (dirty-bit send; same mutators as the
journal). Honest leftover: no guest ROM reinstall of pristine seed bodies (power-cycle
/ rebuild image). Product `repl-holyc` shares seed journal via `#include` (+ `DumpChanges`,
`FsReplay` / `FsRecover`); ZMODEM/trzsz on thin image **waived** (G11 — DumpFile + 9P;
legacy full UART REPL keeps `ZmodemSendChanges` until A3).

Pairs with the ops “session truth leaves the box” idea (dirty memfs → export → host
`git diff`). Does **not** replace host git, RedSea, or VirtioBlk.

Related: [SELF_HOST.md](SELF_HOST.md), [REPL.md](REPL.md), [PLATFORM.md](../templeos-riscv/PLATFORM.md)
(9p client), prior ops backlog (dirty bits + `FsChanges` + `SendChanges`).

---

## Inventory (current tree)

| Piece | Where | Status |
|-------|--------|--------|
| Hierarchical slot memfs | `bootstrap/seed/fs.hc`, `bootstrap/hc_repl/fs.hc` | **Done** — paths `Lib/print.hc`, `.dir` markers, `Cd`/`DirMk`/`DirDel` |
| Seed install map | `bootstrap/seed_layout.py`, `gen_seeds.py` | **Done** — `/Home` `/Boot` `/Lib` … `/Tutorials` |
| Boot load of seeds | `gen_boot_blob.py` / C `memfs_seed_files[]` / HolyC blob | **Done** — arena filled before interactive use |
| Mutators | `FileWrite` / `FsCreate` / `Del` / `DirMk` / `DirDel`; `Copy`/`Move`/`Rename` in `fs.hc` | **Done** — journal + dirty bit; **P4** in-place `Rename` |
| UART export | `DumpFile` / `DumpMem` / `DumpChanges` + `tools/uart_recv_dump.py` | **Done** — per-file + batch manifest (`--keep-path`) |
| ZMODEM / `ZmodemSendChanges` | `bootstrap/seed/zmodem.hc`, `tools/uart_recv_zmodem.py` | **Done** — sz subset; dirty bits (**P3**) |
| Change journal / epochs | `fs.hc` side ring @ `MEMFS_CWD+FS_LOG_OFF`; `boot.hc` seals | **P0–P6 done** — seal / checkpoint / `DumpChanges` / `Rename` / wrap / `FsReplay` / `Recover` |
| 9p | `bootstrap/seed/ninep.hc`, `Kernel/Drv/Virtio9p.HC` | Client import + share-root export (`NineExport`) |
| Editor dirty | `VDirty` in `vim.hc` / Edit spill | **Buffer-local** — not FS journal |
| Content hashes / boot baseline table | FNV-1a in snap + journal `hash` field | **P1 done** |
| Quiet spill / tooling flag | `FS_FLAG_QUIET` on `.dirlist` / `.funlist` / `.es*` / `.vs*` / `*.spill` | **P1 done** |
| ZMODEM / `SendChanges` | `zmodem.hc` | **P3 done** — `ZmodemSendChanges` / `SendChanges`; dirty bits (C+HolyC `FsOnWrite`) |
| RedSea / VirtioBlk LFS | `Kernel/BlkDev/*` | **Out of scope** for this design |
| `hc_repl` journal APIs | `bootstrap/hc_repl/fs.hc` → `#include` seed `fs.hc` + `FsInit`; `fs_dump_changes.hc` | **Done** — `FsChanges` / `DumpChanges` / `FsReplay` / `FsRecover` / seal; ZMODEM still full REPL only |

Honest gap: operators can dump **named** files, list **journaled** mutations
(`FsChanges`), UART-batch them (`DumpChanges`), verify with `FsReplay`, soft-reseal
with `FsRecover`/`Recover`, or ZMODEM the dirty set (`ZmodemSendChanges` on the full
UART REPL only). Product `repl-holyc` has the journal + UART export + Replay/Recover.

---

## Recommended model

**Append-only change journal on top of the existing slot memfs — not a full log-structured filesystem.**

| Choice | Meaning |
|--------|---------|
| **What we build** | Mutation log + epochs + “current dirty set” views |
| **What we do not build** | Relocating file bodies into log segments; GC of data blocks; disk LFS |
| **Why** | Ops need *history of names and ops*, not a new on-media format. Slot memfs already holds bodies; journaling mutations is cheap and honest |

Think “SQLite WAL / git index for memfs,” not “nilfs / F2FS.”

### Epochs

An **epoch** is a monotonic marker in the journal, not a CoW snapshot of all bytes.

| Epoch | When sealed | Purpose |
|-------|-------------|---------|
| **boot (0)** | After seed load finishes, before interactive REPL | “Since boot” baseline |
| **named checkpoint** | `FsCheckpoint("pre-cmp")` | Operator pin before risky work |
| **Recover** | Soft recovery that wipes or reseeds session FS | New session baseline |
| **BIN reload** | After `Load` / host inject of Compiler/Kernel artifacts that rewrite trees | Optional stamp so Cmp noise is separable |
| **wrap / compact** | When the ring drops old records | Synthetic epoch; dirty-set rebuilt from scan |

`FsEpoch()` returns the **current** epoch id (last sealed marker). Mutations after that
belong to “since `FsEpoch()`.”

Boot rule: **seed / blob install must not emit `WRITE` records.** Fill slots, then
`FsEpochSeal(FS_EPOCH_BOOT)`. That definition of “since boot” is stable across
`make repl-blob` rebuilds of the seed set.

---

## Record types

Compact fixed records (HolyC-friendly). Suggested layout (~96–128 bytes each):

| Field | Type | Notes |
|-------|------|--------|
| `seq` | `U32` | Global monotonic; never reused in one power cycle |
| `epoch` | `U16` | Epoch id active when mutation committed |
| `op` | `U8` | See below |
| `flags` | `U8` | e.g. `quiet` (editor spill / `.dirlist`), `baseline` |
| `size` | `I32` | New length for write/truncate; 0 for unlink |
| `hash` | `U32` | Optional FNV-1a / CRC32 of new body (0 = not computed) |
| `path` | `U8[64]` | Resolved memfs path (same 63+NUL cap as slots) |
| `path2` | `U8[64]` | Rename/move destination only |

| `op` | Emitted by |
|------|------------|
| `FS_OP_CREATE` | First `FsCreate` that allocates a free slot |
| `FS_OP_WRITE` | `FileWrite` (incl. overwrite); also `Copy` destination |
| `FS_OP_UNLINK` | `Del` |
| `FS_OP_RENAME` | `FsRename` / `Move` / `Rename` (in-place slot name; dest unlinked if present) |
| `FS_OP_TRUNC` | Explicit truncate / zero-len write if distinguished |
| `FS_OP_DIRMK` / `FS_OP_DIRDEL` | `DirMk` / `DirDel` |
| `FS_OP_EPOCH` | Checkpoint / boot / recover seal (`path` = name) |
| `FS_OP_WRAP` | Ring wrapped; consumers must not assume full history |

Optional later: `FS_OP_NOTE` for operator annotations (`FsNote("tried Cmp")`).

**Quiet paths:** editor spill (`*.spill` / nested Src spills), `.dirlist`, `.funlist`,
and similar tooling files should set `flags.quiet` so default `FsChanges` hides them;
`FsChanges(since, FS_CH_ALL)` includes them.

---

## API surface (HolyC)

Canonical home: extend `bootstrap/seed/fs.hc`. Product `hc_repl` `#include`s that
file (plus AOT `FsInit` / `fs_dump_changes.hc`) so journal semantics stay single-sourced.

| API | Behavior |
|-----|----------|
| `I64 FsEpoch()` | Current epoch id |
| `I64 FsSeq()` | Next seq (or last committed) |
| `I64 FsCheckpoint(U8 *name)` | Append `FS_OP_EPOCH`; bump epoch; return new id |
| `U0 FsChanges(I64 since_epoch=−1, I64 flags=0)` | Print unique paths / ops since epoch (`−1` → boot) |
| `I64 FsChangeCount(I64 since_epoch=−1)` | Count for scripts / export loops |
| `U8 *FsChangePath(I64 i, I64 since_epoch=−1)` | Indexed path in collapsed dirty set |
| `U0 FsDiff(I64 a=−1, I64 b=−1)` | `FsDiff;` = session + size/hash vs boot snap (ZMODEM). `FsDiff(a,b)` = journal `epoch ∈ (a, b]` |
| `U0 FsLog(I64 n=32)` | Tail of raw journal (debug) |
| `I64 FsReplay(I64 since_epoch=−1)` | **P6 done** — verify tree vs journal (OK/MISS/DRIFT); no body rewrite |
| `I64 FsRecover()` / `Recover;` | **P6 done** — drop non-snap slots + `FsEpochSealNamed(…,"RECOVER")` |
| `U0 DumpChanges(I64 since_epoch=−1)` | **Done** — in `zmodem.hc` (after `DumpFile`; C JIT has no forward calls) |
| `U0 SendChanges(...)` | **P3 done** — alias of `ZmodemSendChanges` (dirty bits; see FILE_EXPORT.md) |

Integration rule: **all** mutators go through `fs.hc` hooks. `Copy` uses `FileWrite`.
`Move`/`Rename` call `FsRename` (in-place; not copy+del). Direct slot poke is forbidden.
C `FileWrite`/`EdC` call the same `FsJournal` / `FsOnWrite` / `FsOnDel` via HashFind
(do not rename those symbols).

Suggested print shape:

```
epoch=3 seq=142 since=0
W  Lib/print.hc  size=4201  hash=0xA1B2C3D4
C  Home/note.hc  size=12
D  Tmp/old.hc
```

---

## Storage

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A. Side ring after memfs** | No slot pressure; fixed phys addr | Needs map doc + bounds vs stack | **Preferred** |
| B. Memfs file `/sys/changelog` | `DumpFile` works | Burns a slot; recursive journal risk | Optional **mirror** of compacted text |
| C. Per-slot dirty bit only | Tiny | No order, no unlink/rename history, no epochs | Insufficient alone |

**Preferred layout (implemented P0):**

```
MEM_FS ……………… slot[0..95] + cwd + dirty/snap meta   (existing)
MEM_FS_LOG ……… record[0..FS_LOG_MAX-1] @ cwd+FS_LOG_OFF
FsLogSeq/Epoch/Head/Count/Gen/Ready …… HolyC globals (header)
```

| Bound | Default | Notes |
|-------|---------|--------|
| `FS_LOG_MAX` | 512 records | 144-byte records ≈ 72 KiB side RAM |
| `FS_LOG_OFF` | 9216 | After snap names+FNV hashes; still `< MEM_STACK` |
| Wrap policy | Compact unique paths, emit `FS_OP_WRAP`, bump `FsLogGen` | **P5 done** |
| Boot baseline table | Snap names+sizes+FNV-1a | **P1 done** |

Kconfig/board note: document the phys range next to `MEMFS_BASE` in
`MemMapSelected.hc` / PLATFORM memory tables when implemented — do not collide with
`MEM_STACK` / host slots / virtio RAM.

---

## Boot baseline

```
power-on → zero arena → install seeds (.dir + files) → FsEpochSeal(BOOT) → REPL
```

| Rule | Detail |
|------|--------|
| Seed install | Silent (no journal); builds baseline hash table |
| Interactive / `Run` / editors | Journal from first post-boot `FileWrite`/`Del`/… |
| `make repl-blob` host rebuild | New image ⇒ new boot baseline; not a guest epoch |
| Soft `Recover` that reseeds | Drop non-snap files + `FsEpochSealNamed(id,"RECOVER")`; pristine seed bodies need power-cycle |

“Exactly what changed since boot” = collapsed dirty set for ops after epoch 0, plus
optional raw `FsLog` for forensics.

---

## Export

Journal answers **which** paths; export moves **bytes**. Keep transports in one place:

| Path | Role today | Journal hook |
|------|------------|--------------|
| `DumpFile` / `DumpMem` + `uart_recv_dump.py` | Working UART framed base64 | `DumpChanges` → manifest + N× `DumpFile` |
| Virtio 9p | Import + share-root export | Nested dirs / 9p server still open |
| ZMODEM / trzsz | Not in tree yet | `SendChanges` should call the same dirty-set iterator |
| Host git | Off-box review | Decode dumps into a worktree; `git diff` vs seed checkout |

Manifest sketch (UART):

```
$HC_CHANGES epoch=0..3 count=4$
W Lib/foo.hc
C Home/x.hc
…
$HC_END$
$HC_DUMP name=Lib/foo.hc …$
…
```

Do not duplicate receive recipes here — link [FILE_EXPORT.md](FILE_EXPORT.md) /
[tools/README.md](../tools/README.md).

---

## Non-goals

- Full disk **LFS** for VirtioBlk / RedSea / FAT
- Replacing **host git** or Mac worktrees
- Rewriting TempleOS **RedSea** unless a later kernel design explicitly needs it
- Guaranteeing infinite history in RAM (ring wrap is allowed; baseline + dirty-set remain)
- Journaling Kernel `A:/` RedSea from phase3 (separate concern; optional future adapter)
- Growing `jit.hc` / new C guest APIs for this — HolyC in `fs.hc` only

---

## Alternatives considered

| Approach | Why not primary |
|----------|-----------------|
| **Dirty bitmap / per-slot bit only** | Cheap P0 slice, but loses unlink/rename order and multi-epoch; keep as **acceleration** on slots (`dirty_epoch`) derived from the log |
| **Copy-on-write tree / full snapshots** | Honest rollback, but doubles RAM under `MEMFS_MAX=96` × 64KiB and fights fixed-stride arena |
| **True LFS (bodies in log)** | Wrong problem; complicates `FileRead` hot path and seed install |
| **Host-only diff (QEMU virtfs watch)** | Fails on baremetal / no-9p boards; UART-first ops principle |

**Hybrid:** journal is source of truth; optional `dirty_epoch` on each slot speeds
`FsChanges` collapse.

---

## Phased backlog (implement when asked)

| Phase | Work | Acceptance |
|-------|------|------------|
| **P0** | Side ring + hook `FileWrite`/`FsCreate`/`Del`/`DirMk`/`DirDel`; `FsEpochSeal` after seed load; `FsEpoch`/`FsLog`/`FsChanges` (print) | **Done** — smoke/regression: `FileWrite` → `FsChanges` lists `W Home/jlog.hc` |
| **P1** | Boot baseline hashes; quiet-flag for spill/tooling; `FsCheckpoint`; `FsDiff(a,b)` | **Done** — `FsCheckpoint("p1")` then edit → `FsDiff(0)` post-checkpoint; `.p1q` hidden unless `FS_CH_ALL` |
| **P2** | `DumpChanges` UART manifest + bodies; host decode note in FILE_EXPORT / tools | **Done** — `make dump-changes-smoke` |
| **P3** | `SendChanges` via ZMODEM/trzsz **if** transport landed; else stub calling `DumpChanges` | **Done** — `ZmodemSendChanges` / `SendChanges`; dirty-bit send (`make zmodem-smoke`) |
| **P4** | In-place `Rename` (update slot name + `FS_OP_RENAME`); Move stops being copy+del when same-FS | **Done** — journal `R  from -> to`; no orphan copy |
| **P5** | Ring wrap + dirty-set compaction + `FS_OP_WRAP` honesty | **Done** — fill past `FS_LOG_MAX`; `FsLog` shows `WRAP n=`; collapse rebuilt |
| **P6** | `FsReplay` verify + soft `Recover`/`FsRecover` reseal; RedSea adapter **only if** kernel ops need it | **Done** — drop non-snap + `FsEpochSealNamed(…,"RECOVER")`; no pristine ROM reseed; no RedSea LFS |

Suggested first smoke (HolyC REPL):

```text
FsChanges;          // empty / "no changes"
FileWrite("Home/t.hc","x",1);
FsChanges;          // W Home/t.hc
FsCheckpoint("a");
FileWrite("Home/t.hc","xy",2);
FsDiff(0, FsEpoch); // includes create+writes as designed
DumpChanges;
```

---

## Gaps that block implementation

1. ~~**No journal storage or seq/epoch globals** in `fs.hc`.~~ **P0 done** — side ring.
2. ~~**Mutators unwired**~~ **P0 done** — `FsJournal` in create/write/del/dir*.
3. ~~**No boot seal hook**~~ **P0 done** — `FsEpochSeal(FS_EPOCH_BOOT)` in `boot.hc`.
4. ~~**No content hash helper**~~ **P1 done** — `FsHashBuf` FNV-1a in snap + journal.
5. ~~**`Move`/`Rename` = Copy+Del**~~ **P4 done** — `FsRename` in-place + `FS_OP_RENAME`.
6. **Slot name width 63** — long paths truncate; journal must use same resolve rules.
7. **`MEMFS_MAX=96` pressure** — log is a side region (not a memfs file).
8. ~~**Noise writers**~~ **P1 done** — basename `.` / `*.spill` get `FS_FLAG_QUIET`.
9. **Dual trees** — `hc_repl/fs.hc` `#include`s `seed/fs.hc` (shared journal semantics);
   AOT-only `FsInit` + `fs_dump_changes.hc`. Do not fork journal logic in `hc_repl`.
10. ~~**Export half separate**~~ **P2+P3 done** — `DumpChanges` (UART) / `ZmodemSendChanges` (ZMODEM).
11. ~~**C `FileWrite` / EdC**~~ **Done** (sibling) — HashFind `FsJournal` / `FsOnWrite` / `FsOnDel`.

---

## What already partially exists

| Capability | Exists? |
|------------|---------|
| Hierarchical memfs + seed layout | **Yes** — design sits **on top**, does not replace |
| Per-file UART export | **Yes** (`DumpFile`) |
| Batch UART export | **Yes** (`DumpChanges` + `$HC_CHANGES$`) |
| FS-level journal / epoch / `FsChanges` | **Yes** (print, checkpoint, hashes, rename, wrap, replay, recover) |
| In-place rename | **Yes** (`FsRename` / `Move` / `Rename`) |
| Ring wrap honesty | **Yes** (`FS_OP_WRAP` + compact) |
| `FsReplay` / soft `Recover` | **Yes** — verify + drop non-snap + RECOVER reseal (not ROM reseed) |
| Boot content snapshot hashes | **Yes** (FNV-1a next to snap names/sizes) |
| Editor buffer dirty | **Yes** (`VDirty`) — unrelated to FS journal |
| 9p export of memfs | **Yes** (client `NineExport` → virtfs share root) |

---

## Doc ownership

| Doc | Owns |
|-----|------|
| **This file** | Epoch / journal model, APIs, storage, backlog |
| `FILE_EXPORT.md` / `OPS.md` (when present) | How bytes leave the box; recovery playbooks |
| `REPL.md` | Memfs tree UX for humans |
| `SELF_HOST.md` | Why session truth matters for remote recompile |
