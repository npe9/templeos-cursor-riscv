# Misaligned class members across the port — survey via `HOLYC_WARN_ALIGN`

`crvdc_alignment_note.md` proposed "a cheaper long-term option: have the compiler warn
when a class places an 8-byte member at a non-8-aligned offset." That is now
implemented, and running it corrects one of that note's assumptions.

## The flag

`HOLYC_WARN_ALIGN=1` (`host/parser.c`, next to `HOLYC_DUMP_CLASS`, same `#ifndef
BARE_METAL` block). For every class parsed it reports non-array members of size 2, 4 or
8 whose offset is not a multiple of their size:

```
[align] CRVDC.thick off=44 size=8 (off % 8 == 4)
```

Off by default; changes no layout, so it cannot disturb a render hash. Arrays are
skipped because `size` there is the whole array, not the element, so its alignment
requirement is not `size`.

Why this is a portability signal and not a style nit: the RV backend emits a **real
full-width `ld`/`sd`** at whatever offset the member lands on — verified by
disassembly, see `crvdc_alignment_note.md` addendum 2. There is no width-splitting
anywhere to save it.

## Result: 156 members, and stock TempleOS is *not* clean

The earlier note predicted "TempleOS's own headers would pass it silently." **They do
not.** Sweep over the full kernel + Adam tree (via `kernel_vt_present.hc`):

| Defining file | Misaligned members | Worst classes |
|---|---|---|
| `Kernel/RVWinMgr.HC` | 72 | `CRVWinMgrGlbls`(59), `CRVWin`(13) |
| `Kernel/KernelA.HH` | 45 | `CTSS`(12), `CBlkDev`(9), `CAsmIns`(5), `CScrnCastGlbls`(5), `CFAT32Boot`(4), `CInsReg`(3) |
| `Adam/Gr/Gr.HH` | 23 | `CSpritePtMeshU8s`(5), `CSpriteNumPtU8s`(3), `CSprite*`(rest) |
| `Kernel/RVGr.HC` | 13 | `CRVDC`(13) |
| `Kernel/NineP/NineP.HH` | 3 | `CNinePClient`(3) |

**88 port-authored, 68 stock.** They need opposite treatment.

## The port-authored 88: one byte causes 59 of them

`CRVWinMgrGlbls` starts with a single `Bool`:

```
[ 0] ready      off=0   size=1
[ 1] cols       off=1   size=8   <- and everything from here on is odd
[ 2] rows       off=9   size=8
[ 3] text_base  off=17  size=8   (pointer)
```

Every one of the 59 follows from that one leading byte. `CRVDC` has the same shape
(`Bool is_scrn` mid-struct, plus three `U32`s leaving the cursor at 44). So the
port-authored half is not 88 separate mistakes — it is a handful of stray `Bool`/`U32`
placements, each cascading.

The TempleOS-idiomatic fix is the one Terry used in `CDC`: keep member order, insert an
explicit `pad`, and assert the total. Not `U8 pad[7]` guessed by hand — `CDC` closes
with `#assert !($$&7)`, which is the pattern to copy.

**Not done here.** A pure reorder or repad is source-transparent (members are accessed
by name; `MemSet(&rv_winmgr, 0, sizeof …)` is by size) — but it **changes offsets**, and
`kernel-gr` / `kernel-demo-blot` / `kernel-cdc` / `kernel-win` render pins are all
currently stale against in-flight `RVGr.HC` edits. There is no green baseline to
validate against, which is exactly the trap `crvdc_alignment_note.md` flagged. Settle
the pins first.

## The stock 68: mostly must NOT be fixed

These are not accidents. Most are structures whose byte layout is dictated by something
outside the compiler, where the packing *is* the contract:

- `CTSS` — x86 Task State Segment. Layout fixed by Intel. Almost certainly never
  touched at runtime on RV; worth confirming before spending any thought on it.
- `CFAT32Boot` — on-disk FAT32 boot sector.
- `CSprite*` (`Adam/Gr/Gr.HH`) — TempleOS sprite serialization; the structs overlay a
  byte stream stored in DolDoc.
- `CAsmIns` / `CInsReg` — assembler instruction tables.
- `CScrnCastGlbls` — screencast record format.

Reordering any of these breaks the format. If a strict-alignment target ever traps on
them, the fix is byte-wise accessors (or a compiler that splits wide accesses for
structs marked packed), **not** a layout change.

`CBlkDev`(9) and `CKernel`/`CSysLimitBase` are the stock entries that do *not* obviously
have an external-format excuse. Those are worth an actual look.

## Still open

Whether any of this matters on real silicon is **step 2 of `crvdc_alignment_note.md`
and still unanswered**: does the JH7110 (U74) handle misaligned access in hardware, or
trap to OpenSBI? Not answerable from this machine, and not safe to assume from memory.
QEMU emulates misalignment transparently, so no smoke will ever show it.

If it does fire on a board, the harness now names it: `mcause` 4 / 6 are
`load-misaligned` / `store-misaligned` in the exec harness's trap table
(`vt_smoke_hang_note.md`).
