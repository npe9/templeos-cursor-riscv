# Getting to 1:1 framebuffer parity with x86 TempleOS

## The three claims, kept apart

"Parity" is three different promises, and a plan that mixes them will be read as promising the
screen while it delivers a bitmap.

| | claim | reachable by |
|---|---|---|
| **A** | **DC-bitmap parity** — the same HolyC program drawing into an offscreen `CDC` produces a BYTE-IDENTICAL 8-bit bitmap on both machines | phases 1–5 |
| **B** | **Source parity** — the port runs stock `Adam/Gr/*` unmodified, so there is one implementation rather than two that resemble each other | phases 2–5; it is what makes A hold for code nobody has tested yet |
| **C** | **Scanout parity** — what is on the screen matches, pixel for pixel | phase 6, and it needs A plus the palette→pixel step plus WinMgr composition |

A is the one worth chasing first: it is checkable without a display, without the window manager, and
without timing.

## Phase 0 — what is already measured (2026-09-25)

Four facts, each from one command, that decide the shape of everything below.

**Stock `CDC` compiles today, with x86 packing.** `Kernel/KernelA.HH:3627` is the stock class, and
this compiler lays it out as the declaration dictates:

```
sizeof(CDC)=408   cdt=0  x0=8  width=16  height=24  flags=28  palette=32  color=160
ls=172  dither=184  brush=192  r=200  x=216  thick=228  transform=232  sym=248
cur_x=288  collision_cnt=304  nearest_dist=312  dc_signature=352  mem_task=360
alias=376  body=384  depth_buf=392  db_z=400        CBGR48=8   COLORS_NUM=16
```

Every `I32` pair packs into 8 bytes, every pointer is 8-aligned, and stock's own
`#assert !($$&7)` passes. **So parity is a port-the-files job, not a compiler-layout job.** (The
offsets are what the declaration forces under x86 packing rules; they have not yet been diffed
against a running x86 TempleOS. Phase 1 is how that gets checked rather than asserted.)

**Stock `Adam/Gr` is 16 errors away from compiling against this kernel.** The whole chain, 27 files
in `MakeGr.HC` order:

| error | count | what it really is |
|---|---|---|
| `No member 'c0' in class 'U32'` | 5 | the port made `dc->color` a plain `U32`; stock's is `CColorROPU32`, a union of `c0`/`c1` — and that union is ALREADY in `KernelA.HH:2944` |
| `Global 'gr' redefined with a different type (was CGrMsGlbls/90 bytes, now CGrGlbls/10507)` | 2 | the whole divergence in one line |
| `No member 'palette'` / `'dc_signature'` in `CRVDC` | 3 | fields stock `CDC` has and `CRVDC` does not |
| `PopUpColorDither`, `PopUpColorLighting`, `ClipDel`, `CFFRay.x`, `DocHighlightCursor` | 6 | five unrelated stragglers |

**Not one of them is a graphics primitive.** `GrPlot`, `GrLine`, `GrFillPoly3`, `Sprite3`,
`DCTransform`, `GrFloodFill`, the DC machinery and the sprite machinery all compile. The blockers
are two TYPES and five symbols.

**The port's substitute is 2,057 lines.** `Kernel/RVGr.HC` reimplements 28 stock entry points
(`GrPlot GrLine GrLine3 GrCircle GrFillCircle GrFillTri0 GrFloodFill GrBlot GrPrint DCSave DCLoad
DCAlias DCCopy …`) against `CRVDC`, plus `#define CDC CRVDC` at line 24. Every one of those is a
place where the two systems can disagree silently.

**`gr` is 90 bytes here and 10,507 bytes in stock.** That is the largest single piece of work.

## Phase 1 — build the oracle FIRST, and pin it before changing anything

Nothing below is worth doing without a way to tell whether it broke something, and "parity" needs a
reference. Both come from the same artifact.

**A scene is a HolyC program that draws a fixed picture into an OFFSCREEN DC and reports a hash of
the bitmap.** No screen, no window manager, no palette conversion, no timing — just
`DCNew(w,h)`, a deterministic drawing sequence, and a hash of `dc->body` over `width_internal*height`
bytes. One scene per primitive, then compositions:

```
s_plot     s_hline    s_line      s_line_thick   s_rect      s_circle
s_fill_circle  s_flood_fill  s_tri   s_poly       s_blot      s_print
s_sprite   s_transform  s_depth_buf  s_dither     s_symmetry  s_collision
```

Two properties make this the right oracle:

* it runs **unchanged on both machines** — it is stock HolyC using only stock entry points;
* it fails **locally**: a wrong `GrCircle` shows up as one scene hash, not as a screenshot someone
  has to eyeball.

**Pin the RV hashes now, before any port work.** They are then a regression gate for every file
swapped in below, and the day someone boots x86 TempleOS the same scenes produce the reference
column and the diff IS the parity report. Phase 1 does not depend on obtaining an ISO.

Deliverables: `tests/exec/cases/gr_scene_*.hc`, a `gr-scene-hashes` make target, and
`docs/GR_SCENE_HASHES.md` with the table and a PNG of each scene rendered through the existing
`tools/fb_scanout_hash.py --png`.

### Getting the x86 reference, when it is wanted

No GUI driving is needed. Stock TempleOS runs under `qemu-system-x86_64`; put the scene program in
the boot chain (`~/MakeHome.HC`), have it `FileWrite` the hash table to the RedSea drive and
shut down. The host then reads that file out of the disk image — this repo already reads RedSea
(`make tos` boots from one). Boot, write, halt, diff. The one external dependency in this whole
plan is a TempleOS ISO, and it is only needed at this step.

## Phase 2 — adopt stock `CDC`

Delete `#define CDC CRVDC` and let `CDC` be the stock class. Concretely:

1. `dc->color`, `bkcolor`, `color2` become `CColorROPU32` — the union is already in `KernelA.HH`, so
   this is a declaration change, and it makes the 5 `.c0` errors go away.
2. Add `palette[COLORS_NUM]` and `dc_signature`, which stock code reads directly.
3. `CRVDC`'s extra fields (`is_scrn`, `is_u8`, `clip_x1..clip_y2`, `x0/y0` origin hint) have to go
   somewhere. Stock has `DCF_*` flags and `CDC.x0/y0`; the clip rectangle is the port's own and needs
   either a stock equivalent or an explicit note that it is an extension.
4. `CDC.body` is `U8 *` — 8-bit palette indices at `width_internal` stride. The port already has this
   mode (`CRVDC.is_u8`), so the compose path has a place to stand.

### The one thing phase 2 really costs: `dc->color` is overloaded today

Measured, not guessed. `Kernel/RVGr.HC:303` is `RVDCPenIdx`:

```
if (dc->color == COLOR_MONO || dc->color == TRANSPARENT) …
if (dc->color < COLORS_NUM) return dc->color;   // a palette INDEX
return RVColorNearestIdx(dc->color);            // else an XRGB PIXEL, mapped to the nearest index
```

So the port stores **either** a palette index **or** a 32-bpp XRGB pixel in the same field, and
`RVDCRst` puts an XRGB value there (`dc->color = RVColor(WHITE)`). Stock's field cannot do that: it
is a `CColorROPU32`, two `CColorROPU16` halves of `{colour, rop}`, and the high bits are the second
colour for dithering — `ROPF_DITHER` and `ROPF_PROBABILITY_DITHER` live in `c1.rop`.

**So adopting stock `CDC` means giving up XRGB-in-the-DC**, and the index→pixel conversion moves to
the present step. That is where phase 6 step 1 puts it anyway, so the two are coupled: you cannot
keep a 32-bpp pen and have stock `CDC`. Decide it once, at the start of phase 2, rather than halfway
through.

There are 28 `dc->color` uses in `Kernel/RVGr.HC` and 13 more across `RVWinMgr.HC`, `RVSprite.HC` and
`RVDoc.HC` — about 41 sites, each of which is asking one of two questions ("what index do I write"
or "what pixel do I write"), and the answer after phase 2 is always the first.

Gate: the phase-1 scene hashes (they WILL move — re-pin and say which and why, per
`docs/GR_SCENE_HASHES.md`), plus the eight layout targets. `sizeof` changes, so the blot hash moves
too.

## Phase 3 — adopt stock `CGrGlbls`

90 bytes → 10,507. `gr` carries the palette, the sprite hash, the pen brushes, the zoom state and the
draw callbacks, and `Adam/Gr/GrGlbls.HC` already compiles clean on its own. This is the phase where
`CGrMsGlbls.text_base` and the other port-specific fields have to be reconciled with the stock
members that mean the same thing.

Do it AFTER phase 2: `CGrGlbls` contains `CDC *` members, so its layout depends on nothing about
`CDC` but its own code does.

## Phase 4 — swap `Adam/Gr` in, file by file, in `MakeGr.HC` order

`GrInitA Gr.HH GrExt GrGlbls GrTextBase GrAsm GrPalette GrDC GrInitB GrMath GrScrn GrBitMap
GrPrimatives GrComposites ScrnCast`, then the Sprite chain. `GrMath` and `GrPalette` are already in
(`c405e5ce`). For each file: run `tools/check_prj_collisions.py` first, add it, delete the matching
substitute from `Kernel/RVGr.HC`, re-run the scene hashes.

**`Adam/Gr/GrAsm.HC` must NOT be added on the strength of a clean compile.** It is 410 lines
containing 121 x86 mnemonics in one `asm{}` block (`PUSH RBP`, `MOV RBP,RSP`, `LODSQ`,
`SF_ARG2[RBP]`, `@@05:` labels) — VGA plane writing. It compiles with exit 0 and no diagnostic,
adds **40 bytes** to the blob, and defines **no symbols**: `_GR_UPDATE_LINE64` is absent from
`HOLYC_MAP`. `host/parser.c:5229` soft-skips an `asm{}` block it cannot assemble, deliberately, so
that the port can compile stock files full of x86 (`CallExtStr`, `PCIBIOS`) — and it counts them in
`cc->asm_blocks_skipped`.

**A plain `Kernel_RV.PRJ` build already drops 17 such blocks.** That count was only ever printed in
`!quiet`, and every script runs quiet, so nobody has seen it. `HOLYC_ASM_SKIPS=1` now prints it to
stderr:

```sh
HOLYC_ASM_SKIPS=1 ./holyc-riscv case.hc -o /dev/null
note: 17 x86 asm block(s) skipped — that code is NOT in the image
```

Use it whenever a stock file "compiles clean": for anything containing assembly, a clean compile
cannot distinguish *ported* from *silently empty*. `GrAsm` needs a RISC-V rewrite, and the pixel path
it serves (`GrUpdateVGAGraphics`) belongs to phase 6 anyway.

## Phase 5 — the five stragglers

`PopUpColorDither`, `PopUpColorLighting` (`Adam/Opt/…` pop-ups), `ClipDel`
(`Adam/DolDoc/DocClipBoard.HC`, in the tree), `CFFRay.x`, and `DocHighlightCursor`'s default
argument.

## Phase 6 — scanout parity (claim C)

Only now does the screen enter it. Two steps, each its own hash:

1. **Palette → pixel.** x86 writes 4-plane VGA at `0xA0000` with a 16-entry `CBGR48` palette; this
   port writes a linear 32-bpp buffer. Parity means the same index becomes the same visible colour,
   which is a table, and `tools/fb_scanout_hash.py` already hashes the result.
2. **WinMgr composition.** Borders, z-order, the text layer over the graphics layer. This is where
   the port diverges most and where "1:1" is most likely to stay approximate.

## What could make this not work

* **`sizeof(CGrGlbls)` is 10,507** — not 8-aligned, and stock has `#assert`s of its own. Phase 3 may
  surface a packing difference the way phase 0 could have and did not.
* **8-bit body vs 32-bpp present.** Every present becomes a palette lookup per pixel. That is a
  performance question, not a correctness one, but the port chose 32-bpp for a reason and that reason
  should be written down before it is reversed.
* **The blot hash will move at least twice** (phase 2 and phase 3). It has been re-pinned twice
  already for layout reasons that were never fully explained; if it moves without a visible PNG
  difference, that is the old mystery resurfacing and it should be chased, not re-pinned a third time.
* **`GrAsm.HC`** is x86 assembly by name. Budget for rewriting it, not porting it.
* **Phase 1 is the only phase that produces evidence.** If it slips, everything after it is
  unmeasured, and this document's whole point is that the port has repeatedly believed things that
  measurement then contradicted.
