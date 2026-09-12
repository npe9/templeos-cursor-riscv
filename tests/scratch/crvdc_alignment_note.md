# Port-authored classes are misaligned; TempleOS's own are not

Found while dumping class layouts to diagnose the `CDC`/`CRVDC` alias bug. Not
caused by that work, not urgent on QEMU, and **potentially a real fault on the board
targets**. Untested on hardware — flagged, not fixed.

## The mechanism

HolyC packs class members with no alignment padding. `host/parser.c`
`ParseClassMembers`:

```c
else { m->offset = cur; cur += m->size; }
```

That is correct TempleOS semantics — x86 tolerates misaligned loads and stores, so
Terry hand-padded structs instead. The evidence that he did is right there in the
source: `Kernel/KernelA.HH` `CDC` carries explicit `pad` members and closes with
`#assert !($$&7)`, asserting the total is 8-byte aligned.

RISC-V does not make the same promise. A misaligned `ld`/`sd` may be handled in
hardware, may trap to firmware for slow emulation, or may raise a fault, depending on
the implementation.

## The evidence

`HOLYC_DUMP_CLASS=CDC` — stock TempleOS, every 8-byte member naturally aligned:

```
[14] dither_probability_u16   off=184  size=8     184 % 8 == 0
[15] brush                    off=192  size=8     192 % 8 == 0
[29] collision_cnt            off=304  size=8     304 % 8 == 0
[37] mem_task                 off=360  size=8     360 % 8 == 0
```

`HOLYC_DUMP_CLASS=CRVDC` — port-authored, in `Kernel/RVGr.HC`:

```
[ 5] color     off=32  size=4
[ 6] color2    off=36  size=4
[ 7] bkcolor   off=40  size=4
[ 8] thick     off=44  size=8    <-- I64 at 44,  44 % 8 == 4
[ 9] flags     off=52  size=8    <-- I64 at 52,  52 % 8 == 4
[11] is_scrn   off=60  size=1
[12] brush     off=61  size=8    <-- pointer at 61, 61 % 8 == 5
[13] x0        off=69  size=8    <-- I64 at 69
[14] y0        off=77  size=8    <-- I64 at 77
```

Two causes, both ordinary authoring accidents:

1. Three `U32`s (`color`, `color2`, `bkcolor`) leave the cursor at 44, so the next
   `I64` is 4-aligned rather than 8.
2. `Bool is_scrn` mid-struct leaves everything after it odd-aligned.

Note `is_u8` at the tail already carries a comment explaining it was placed there
deliberately to preserve `brush`/clip offsets — so layout was being reasoned about,
just not alignment.

## Why it has not bitten

QEMU `virt` emulates misaligned access transparently, and every smoke runs there. The
board matrix, though, includes real silicon — VisionFive 2 and Milk-V Mars (JH7110).
On a core that traps misaligned access, every `dc->thick` / `dc->flags` / `dc->brush`
touch becomes a firmware round trip at best.

## What to check before acting

1. Whether the RV backend actually emits `ld`/`sd` for these members or byte-assembles
   them. If it byte-assembles, this is a performance note only.
2. Whether the JH7110 (U74 cores) handles misaligned access in hardware. If it does,
   this is a non-issue for the current matrix and only matters for future targets.
3. Only then consider reordering `CRVDC` — group the `U32`s and move `is_scrn` to the
   tail beside `is_u8`. **That changes offsets**, so it needs the `kernel-gr-smoke` /
   `kernel-demo-blot-smoke` render hashes re-pinned, and those two are already red for
   an unrelated reason (a stale pin from in-flight `RVGr.HC` edits) — untangle that
   first or the change cannot be validated.

A cheaper long-term option: have the compiler warn when a class places an 8-byte
member at a non-8-aligned offset. That surfaces the whole class of accident across the
port without changing any layout, and TempleOS's own headers would pass it silently.

> **Done — `HOLYC_WARN_ALIGN=1`.** See `align_survey.md`. The last clause of that
> sentence turned out to be **wrong**: stock TempleOS headers are *not* clean
> (`KernelA.HH` 45 members, `Adam/Gr/Gr.HH` 23), though most of those are
> format-dictated layouts that must not be changed. The survey splits them.

---

## Addendum (2026-09-08): step 3's blocker is smaller than it looked

Step 3 above parks the reordering on "`kernel-gr-smoke` / `kernel-demo-blot-smoke` are
already red for an unrelated reason." That is still true of those two — both run and
disagree with their pin (`gr` want `0x6EF34074` got `0x2C881662`; `blot` want
`0xA3B0362C` got `0x43186381`), so they are ordinary stale pins.

But `kernel-cdc-smoke`, which is the smoke that actually exercises `CRVDC`, was not
red for that reason at all — it was **hanging**, producing no output, on the
`ChkOnStk` null-stack fault described in `vt_smoke_hang_note.md`. With that fixed it
runs to completion and reports `hash=0x95A09C04` against a pin of `0xEFB2D715`.

So the layout question now has a smoke that can actually answer it, once the pins are
re-established against a settled `RVGr.HC`. The alignment finding itself is unchanged
and still untested on hardware.

---

## Addendum 2 (2026-09-09): step 1 answered — the backend emits real `ld`/`sd`

"What to check before acting" step 1 was whether the RV backend actually emits `ld`/`sd`
for these members or byte-assembles them. **It emits real full-width accesses.** Probe
(`dc->thick = 7; dc->x0 = 9;` on a `CRVDC *`), disassembled out of the blob:

```
li   a0,44           # thick, 44 % 8 == 4
add  a0,t0,t1
sd   a0,0(t0)        # <- full 8-byte store at a 4-aligned address

li   a0,69           # x0, 69 % 8 == 5
add  a0,t0,t1
sd   a0,0(t0)        # <- full 8-byte store at a 5-aligned address
```

Reads are the matching `ld a0,0(a0)`. The stack-machine codegen folds the member offset
into the address register and then issues one unconditional `sd`/`ld`, so there is no
width-splitting anywhere to save it.

**So this is not a performance note. It is a real misaligned access**, and on a core
that does not handle misalignment in hardware every `dc->thick` / `dc->flags` /
`dc->brush` touch is a trap.

Still open, and not answerable from this machine:

- **Step 2 — does the JH7110 (U74) handle misaligned access in hardware?** Needs the
  SiFive U74 core complex manual or a board run. Do not assume either way from memory.
  If it traps to OpenSBI for emulation, the cost is a firmware round trip per access on
  the hot drawing path.
- **Step 3 — reordering `CRVDC`** still changes offsets and still needs settled render
  pins first.

The trap vector added in `vt_smoke_hang_note.md` will now *name* this if it ever fires:
`mcause` 4 and 6 are `load-misaligned` / `store-misaligned` in the harness's cause
table. On QEMU they will never fire — QEMU emulates misalignment transparently — but on
a board target that traps, the harness will say so instead of hanging.
