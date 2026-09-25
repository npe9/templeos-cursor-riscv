# The framebuffer-parity oracle

`tests/exec/cases/kernel_gr_scenes.hc` draws a fixed picture into an **offscreen 8-bit DC** for each
graphics primitive and hashes the bitmap. `tests/gr_scene_hashes.tsv` holds the hashes.
`make kernel-gr-scenes-smoke` diffs; `GR_SCENE_PIN=1 make kernel-gr-scenes-smoke` re-pins.

This is phase 1 of `docs/FB_PARITY_PLAN.md`, and it comes before any porting on purpose: every later
phase replaces part of `Kernel/RVGr.HC` with stock `Adam/Gr` code, and without this the only way to
notice a changed pixel is to look at a screenshot.

## Why an offscreen DC and not the screen

Hashing the framebuffer would fold in three things that have nothing to do with whether `GrCircle`
is right: the palette→pixel conversion, the window manager's composition, and when the present
happened. An offscreen DC has none of them. What is hashed is the same 8-bit body shape stock
TempleOS draws into — `COLORS_NUM` is 16 and `CDC.body` is `U8 *` at `width_internal` stride — so
**the same source file runs on x86 TempleOS and produces the reference column.**

Three properties were designed in:

* **The hash covers the row padding** (`width_internal * height`, not `width * height`), so a stride
  change is a hash change rather than a silent reinterpretation.
* **A scene fails locally.** A wrong `GrCircle` is one line of output, not a picture to eyeball.
* **No timing, no `Rand`, no screen size.** Every coordinate is a literal, so a hash cannot move
  because the machine was busy — which also means the full suite can run concurrently with it.

`SCENE_DC_NEW` is one line on purpose. Today the stock-CDC-shaped DC is `DCNew8`; after parity
phase 2 adopts stock `CDC`, plain `DCNew` *is* that shape and only that define changes.

## The scenes

| scene | what it pins |
|---|---|
| `plot` | `GrPlot` at 64 positions across 16 colours |
| `hline` | `GrHLine` spans |
| `line` | `GrLine` at eight slopes, both signs of dx/dy |
| `line_thick` | `dc->thick` 1..4 — the pen, not just the path |
| `rect` | `GrRect` nested, so an off-by-one edge shows |
| `circle` | `GrCircle` at six radii |
| `fill_circle` | `GrFillCircle`, overlapping, drawn largest-first |
| `flood_fill` | `GrFloodFill` inside a `GrRect` boundary |
| `tri` | `GrFillTri0` — three `CD3I32` points, as stock takes them |
| `blot` | `GrBlot` of a 16×16 DC twice, at two offsets |
| `print` | `GrPrint` — the font and the glyph blit |
| `fill` | `DCFill` — the whole body, padding included |
| `peek_write` | a ROUND TRIP: plot a pattern, `GrPeek` it back, re-plot. A read/write asymmetry cannot pass |

## The rule about re-pinning

**The hashes are expected to move when a parity phase lands.** Re-pin with `GR_SCENE_PIN=1` and say
in the commit *which scenes moved and why*. A scene moving that the change does not explain is the
finding — chase it, do not re-pin it.

That rule exists because `kernel-demo-blot-smoke` pins a framebuffer hash which has already been
re-pinned twice for layout reasons nobody wrote down. Naming the primitive is what makes the
difference between a re-pin and an investigation.

## The oracle's first find was a bug in the oracle

On its first run the case trapped: `mcause=5 load-fault mtval=0xa`, and `tools/traploc.sh` named
`GrFillTri0+0x168`. Stock is `GrFillTri0(CDC *dc=gr.dc, CD3I32 *p1, CD3I32 *p2, CD3I32 *p4)` — three
POINTS — and the scene had passed six coordinates, so `p1->x` loaded from address 10, which is
exactly the `mtval`. The port matched stock all along.

Worth recording for two reasons: a scene that mis-calls the API would otherwise have pinned a *trap*
as the reference, and it is the reason the gate prints the last scenes that did report and says the
next one is the culprit.

## The gate was proven, four ways

A check that prints FAIL and exits 0 is worse than no check, because it looks like coverage. So each
way this can go wrong was made to happen on purpose:

| | |
|---|---|
| plain run | `PASS — 13 scenes match the pinned table` |
| one pinned hash perturbed | `FAIL — circle: pinned 0000000000000000 got 9E5015D620BB8225` |
| a pinned row deleted | `FAIL — scene 'peek_write' is not in the pinned table` |
| a scene dropped from the CASE | `FAIL — pinned scene 'peek_write' did not run` |

The fourth one is why the check is a `comm -23` of sorted name lists rather than a loop. It had been
a `while read` inside a pipeline, and that subshell **cannot set `fail` in the parent** — it would
have printed the complaint and exited 0. A primitive that quietly stopped being exercised would have
looked like a pass.

## Filling the x86 column

No GUI driving is needed. Stock TempleOS runs under `qemu-system-x86_64`; put the scene program in
the boot chain (`~/MakeHome.HC`), have it `FileWrite` the table to the RedSea drive, and halt. The
host reads that file out of the disk image — this repo already reads RedSea (`make tos` boots from
one). Boot, write, halt, diff.

A TempleOS ISO is the only external dependency in the whole parity plan, and it is needed only here.
