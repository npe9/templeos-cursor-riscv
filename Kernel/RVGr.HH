// Kernel/RVGr.HH — the RV graphics TYPES, split out of RVGr.HC so a unit compiled WITHOUT the
// kernel bodies can still see their layout.
//
// A demo built as its own unit (Kernel/DemoAPI.HH, the Compiler.BIN model) gets `gr` and the
// DC as imports. Without these definitions the compiler forward-declares the class as opaque
// and every `gr.field` / `dc->field` becomes "No member 'X' in class 'CGrMsGlbls'" — 11 of the
// 204 Demo programs failed exactly that way. The types belong in a header; only the storage
// and the code stay in RVGr.HC.
#ifndef RVGR_HH
#define RVGR_HH

class CRVDC
{
  //32-bpp CDC bridge by default; optional is_u8 ⇒ body is U8 palette (TempleOS CDC).
  // color is a PALETTE INDEX in color.c0.color, as stock (RVDCPenIdx); RVDCPenColor maps it
  // to XRGB for a 32-bpp body at the point of the write.
  U32 *body;
  // start/end bracket the serialisable scalar header, matching stock CDC's markers so
  // `offset(CDC.end)-offset(CDC.start)` resolves under `#define CDC CRVDC` (that is
  // what Adam/Gr/GrDC.HC's DCSave/DCLoad span uses). U0 members are zero-size — the
  // dump confirms CDC's own start/end take 0 bytes — so this does not move a field.
  // Deliberately after `body`: a pointer must not be serialised, it is re-derived.
  U0 start;
  I64 width;
  I64 height;
  I64 width_internal;
  // pixels per row (U32 elems) or byte stride when is_u8 ((width+7)&~7)
  // STOCK: CDC.color/bkcolor/color2 are CColorROPU32 — two CColorROPU16 halves of {color, rop}.
  // The pen is a PALETTE INDEX in c0.color, never a pixel. This port used to put an XRGB value
  // here and discriminate by `< COLORS_NUM`; stock cannot express that (c0.color is ONE BYTE) and
  // the overload cost the rop byte, which is where ROPF_DITHER / ROPB_MONO / ROPB_COLLISION live.
  // Same 32 bits, so no offset moves. Index → pixel now happens only at the write.
  CColorROPU32 color;
  CColorROPU32 color2;
  CColorROPU32 bkcolor;
  I64 thick;
  I64 flags;
  U0 end;
  // DCF_* subset: DONT_DRAW, RECORD_EXTENTS, NO_TRANSPARENTS, ALIAS, SCRN_BITMAP
  Bool is_scrn;
  // TRUE ⇒ body aliases rv_fb.pixels (compose); always 32-bpp
  CRVDC *brush;
  // optional stamp DC for pen (Demo/Graphics/Blot.HC)
  I64 x0;
  I64 y0;
  // origin hint (win-local draw helpers)
  I64 clip_x1;
  I64 clip_y1;
  I64 clip_x2;
  I64 clip_y2;
  // exclusive clip in body coords; clip_x2<=clip_x1 ⇒ no clip (full DC)
  I64 min_x;
  I64 max_x;
  I64 min_y;
  I64 max_y;
  // DCF_RECORD_EXTENTS
  Bool is_u8;
  // TRUE ⇒ body is U8 palette indices (offscreen + opt-in WinMgr paint DC). Trailing
  // so brush/clip offsets match pre-8bit CRVDC layout.

  /* Stock CDC fields that stock code reads directly. A survey of all 204 Demo programs found
   * 16 of them failing to compile on a missing CRVDC member, the most common single cause.
   * Names and meanings follow CDC in Kernel/KernelA.HH:3620; widths are I64 here because RV
   * has no reason to pack to I32. All TRAILING, like is_u8, so no existing offset moves.
   * Storage now, behaviour as the Gr3 work lands: `r`/`r_norm` are DCMat4x4Set's matrix,
   * `depth_buf`/`db_z` are DCDepthBufAlloc's z buffer, `win_task` is what a per-cell z clip
   * in GrPlot0 tests against gr.win_z_buf. */
  I64 *r;
  I64 r_norm;
  I64 x;
  I64 y;
  I64 z;
  I64 cur_x;
  I64 cur_y;
  I64 cur_z;
  I64 collision_cnt;
  CTask *mem_task;
  CTask *win_task;
  I32 *depth_buf;
  I64 db_z;
  CD3I32 ls;
  //light source, normalized to 65536 (stock CDC.ls)
  U64 dither_probability_u16;
  //ROPF_PROBABILITY_DITHER blend (Demo/Graphics/SunMoon.HC, Shading.HC)
  I64 nearest_dist;
  CGrSym sym;
  //DCSymmetrySet / DCSymmetry3Set
  U0 (*transform)(CDC *dc, I64 *x, I64 *y, I64 *z);
  //overridable, default DCTransform
  U0 (*lighting)(CDC *dc, CD3I32 *p1, CD3I32 *p2, CD3I32 *p3, CColorROPU32 color);
  //overridable, default DCLighting
};

U32 RVDCPenColor(CRVDC *dc)
{
  //The XRGB pixel for a 32-bpp body. The pen is always a palette index (stock), so this is always
  // a palette lookup — there is no pass-through any more.
  // COLOR_MONO/TRANSPARENT (0xFF) → non-zero ink for brush templates (Adam GrInitB shape).
  U8 idx;
  if (!dc)
    return 0;
  idx = dc->color.c0.color;
  if (idx == COLOR_MONO || idx == TRANSPARENT)
    return COLOR_MONO;
  return RVColor(idx & (COLORS_NUM - 1));   //parenthesised: see RVDCPenIdx in RVGr.HC
}

I64 PressAKey()
{
  //Soft stub for Demo/*.HC on headless smokes — print prompt, do not block on GetChar.
  Print("PRESS A KEY\n");
  return '\n';
}

class CRVGrGlbls
{
  CRVDC *dc;
  // persistent screen DC (aliases 32-bpp compose)
  U0 (*fp_draw_it)(CRVDC *dc);
  // optional WinMgr-lite refresh hook
};
CRVGrGlbls rv_gr;
CRVDC rv_scrn_dc;
// Opt-in 8-bit compose present (separate I64 globals — do not grow CRVGrGlbls;
// Bool packing misaligned rv_scrn_dc and broke the 32-bpp hash pin).
CRVDC *rv_gr_dc_u8;
I64 rv_gr_u8_present;
I64 rv_gr_u8_owned;
// Stock Apps (PsalmodyDraw) call gr.fp_draw_ms — soft null cursor until AMouse.
U0 RVDrawMsNull(CDC *dc, I64 x, I64 y)
{
  no_warn dc;
  no_warn x;
  no_warn y;
}

class CGrMsGlbls
{
  U0 (*fp_draw_ms)(CDC *dc, I64 x, I64 y);
  U32 *text_base;
  //Stock gr.text_base — the TextBase Layer cell grid. RVWinMgr owns the storage and points
  //this at rv_winmgr.text_base when it comes up (RVGr is included BEFORE RVWinMgr, so it
  //cannot name it here). Stock code indexes it directly: Demo/Games/Maze.HC does
  //MemCpy(gr.text_base+TEXT_COLS,…) and Adam/Win.HC XORs a cell to draw the text cursor.

  /* The rest of stock CGrGlbls that stock code reads. 9 of the 204 Demo programs failed to
   * compile on one of these — second only to CRVDC. dc/dc2 are the screen and compose DCs
   * (RVGrInit points them at rv_gr.dc), win_z_buf is the per-cell window-owner grid the
   * WinMgr fills. */
  CDC *dc;
  CDC *dc2;
  U16 *win_z_buf;
  Bool to_8_bits;
  I64 hide_col;
  I64 pan_text_x;
  I64 pan_text_y;
  U0 (*fp_final_scrn_update)(CDC *dc);
  I64 hide_row;
  Bool to_8_colors;
  U0 (*fp_wall_paper)(CDC *dc);
};

#endif
