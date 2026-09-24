// Thin Gr*/CDC path for native 32-bpp FB (Phase F / WinMgr P4). Not VGA, not full Adam/Gr.
//
// Draws into CRVDC bodies that are U32 XRGB8888 (same layout as rv_fb.pixels compose).
// Screen DC aliases the compose buffer; RVGrRefresh() → RVFbPresent() flips to scanout.
// Soft terminal paints 8×8 glyphs into compose and flushes with the same present path.
//
// P4 bridge: clip rect, DCF_* subset, offscreen DCNew/RVDCNew, GrBlot (32-bpp), GrCircle.
// TempleOS-named DC* aliases + Sprite3 subset in RVSprite.HC (Demo blot / SpriteRaw patterns).
// Demo stock reuse: `#define CDC CRVDC`, palette-index pen (dc->color=RED), GrLine step/start,
// soft PressAKey (no GetChar block). First proof: Demo/Graphics/NetOfDots.HC.
// FloodFill/brush/GrLine3/GrCircle3 (Adam GrPrimatives shape) for Demo/Graphics/Blot.HC.
// Libs-first widen: DCCopy/DCExt/DCDiff, 8-bit body quantize + GR-lite
// DCSave/DCLoad (CompressBuf .GR.Z when DCSF_COMPRESSED), soft ScrnCast frame (DCDiff),
// GrFillTri0/Gr3Mesh (flat, no lighting), optional offscreen 8-bit live body
// (DCNew8 + Plot/Blot/Peek/Fill/FloodFill).
// Opt-in WinMgr 8-bit compose present: rv_gr_dc_u8 + rv_gr_u8_present → GrUpdateVGAGraphics
// expands palette body into 32-bpp compose before Flip (default path stays 32-bpp).
// When full-screen U8 is bound (ComposeEnable), WinMgr text/draw_it/sprites paint into
// is_u8 then expand on present (RVGrPaintDC); small Bind-only buffers stay present-expand.
// WinMgr compose path calls ScrnCastFrame when scrncast.record && !just_audio.
// ScrnCast AU: RVSnd queues CSndData when record; soft AUWrite/.AU (just_audio OK).
// Still deferred: mesh lighting/transform/symmetry.
// TempleOS CDC* name → 32-bpp CRVDC (stock Demo/Graphics/*.HC).
#define CDC CRVDC
#include "/Adam/Gr/Gr.HH" // CMeshTri / SPT_* for Gr3Mesh + Sprite mesh elems
// TempleOS gr_palette_std indices → full 8-bit XRGB8888 (0x00RRGGBB, not 6-bit VGA 0xAA).
U32 rv_palette_std_tpl[COLORS_NUM] = {0x00000000, 0x000000FF, 0x0000FF00, 0x0000FFFF, 0x00FF0000, 0x00FF00FF, 0x00AA5500, 0x00AAAAAA, 0x00555555, 0x005555FF, 0x0055FF55, 0x0055FFFF, 0x00FF5555, 0x00FF55FF, 0x00FFFF55, 0x00FFFFFF};
U32 rv_palette_std[COLORS_NUM];
// 32-bpp transparent key for GrBlot (TempleOS 8-bit TRANSPARENT=0xFF analogue).
#define RV_TRANSPARENT 0xFFFFFFFF
U32 RV_RGB(I64 r, I64 g, I64 b)
{
  return (r & 255) << 16 | (g & 255) << 8 | (b & 255);
}

U32 RVColor(I64 idx)
{
  //Map TempleOS color index 0..15 to XRGB; pass-through if already a full pixel (dc->color / RV_RGB).
  if (idx >= 0 && idx < COLORS_NUM)
    return rv_palette_std[idx];
  return idx & 0xFFFFFFFF;
}

U0 RVPaletteSetStd()
{
  //RV stand-in for Adam PaletteSetStd — refresh index table (no VGA DAC on this path).
  MemCpy(rv_palette_std, rv_palette_std_tpl, COLORS_NUM *sizeof(U32));
}

class CRVDC
{
  //32-bpp CDC bridge by default; optional is_u8 ⇒ body is U8 palette (TempleOS CDC).
  // color may be palette index or XRGB U32 (RVDCPenColor / RVDCPenIdx).
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
  U32 color;
  U32 color2;
  U32 bkcolor;
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
};

U32 RVDCPenColor(CRVDC *dc)
{
  //Stock demos assign palette indices (dc->color=RED); RV paths may store full XRGB.
  // COLOR_MONO/TRANSPARENT (0xFF) → non-zero ink for brush templates (Adam GrInitB shape).
  if (!dc)
    return 0;
  if (dc->color == COLOR_MONO || dc->color == TRANSPARENT)
    return COLOR_MONO;
  if (dc->color < COLORS_NUM)
    return RVColor(dc->color);
  return dc->color;
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
};
CGrMsGlbls gr;
// screen DC storage (aliases rv_fb.pixels compose after RVGrInit)
class CRVTerm
{
  //Soft text terminal overlaid on the FB (cell grid in pixels).
  I64 rows;
  I64 cols;
  I64 cur_r;
  I64 cur_c;
  U32 fg;
  U32 bg;
  I64 ox;
  // pixel origin
  I64 oy;
};
CRVTerm rv_term;
U0 RVDCRst(CRVDC *dc)
{
  if (!dc)
    return;
  dc->color = RVColor(WHITE);
  dc->color2 = RVColor(BLACK);
  dc->bkcolor = RVColor(BLACK);
  dc->thick = 1;
  dc->flags = 0;
  dc->brush = NULL;
  dc->x0 = 0;
  dc->y0 = 0;
  dc->clip_x1 = 0;
  dc->clip_y1 = 0;
  dc->clip_x2 = 0;
  dc->clip_y2 = 0;
  dc->min_x = I64_MAX;
  dc->max_x = I64_MIN;
  dc->min_y = I64_MAX;
  dc->max_y = I64_MIN;
}

U0 RVDCClipRst(CRVDC *dc)
{
  if (!dc)
    return;
  dc->clip_x1 = 0;
  dc->clip_y1 = 0;
  dc->clip_x2 = 0;
  dc->clip_y2 = 0;
}

U0 RVDCClipSet(CRVDC *dc, I64 x1, I64 y1, I64 x2, I64 y2)
{
  //Exclusive clip rectangle in body coordinates (GrUpdateTaskWin analogue).
  if (!dc)
    return;
  if (x1 > x2) {
    I64 t = x1;
    x1 = x2;
    x2 = t;
  }
  if (y1 > y2) {
    I64 t = y1;
    y1 = y2;
    y2 = t;
  }
  dc->clip_x1 = x1;
  dc->clip_y1 = y1;
  dc->clip_x2 = x2;
  dc->clip_y2 = y2;
}

Bool RVDCScrnBind(CRVDC *dc)
{
  //Point dc at the compose buffer (flipped to scanout on present). Requires RVFbInit first.
  if (!dc || !rv_fb.pixels)
    return FALSE;
  dc->body = rv_fb.pixels;
  dc->width = rv_fb.width;
  dc->height = rv_fb.height;
  dc->width_internal = RVFbPixStride;
  dc->is_scrn = TRUE;
  dc->is_u8 = FALSE;
  dc->flags = DCF_SCRN_BITMAP;
  RVDCRst(dc);
  return TRUE;
}

CRVDC *RVDCNew(I64 width, I64 height)
{
  //Offscreen 32-bpp DC (TempleOS DCNew analogue; body is U32 XRGB not U8 palette).
  CRVDC *dc;
  I64 n;
  if (width < 1 || height < 1)
    return NULL;
  dc = CAlloc(sizeof(CRVDC));
  if (!dc)
    return NULL;
  dc->width = width;
  dc->width_internal = width;
  dc->height = height;
  dc->is_scrn = FALSE;
  dc->is_u8 = FALSE;
  n = width *height *sizeof(U32);
  dc->body = CAlloc(n);
  if (!dc->body) {
    Free(dc);
    return NULL;
  }
  RVDCRst(dc);
  return dc;
}

CRVDC *RVDCNew8(I64 width, I64 height)
{
  //Offscreen 8-bit palette DC (TempleOS CDC body shape). WinMgr/FB stay 32-bpp.
  CRVDC *dc;
  I64 n, wi;
  if (width < 1 || height < 1)
    return NULL;
  dc = CAlloc(sizeof(CRVDC));
  if (!dc)
    return NULL;
  wi = width + 7 & ~7;
  dc->width = width;
  dc->width_internal = wi;
  dc->height = height;
  dc->is_scrn = FALSE;
  dc->is_u8 = TRUE;
  n = wi *height;
  dc->body = CAlloc(n);
  if (!dc->body) {
    Free(dc);
    return NULL;
  }
  RVDCRst(dc);
  return dc;
}

U0 RVDCDel(CRVDC *dc)
{
  if (!dc)
    return;
  if (!(dc->flags & DCF_ALIAS) && dc->body && !dc->is_scrn)
    Free(dc->body);
  Free(dc);
}

CRVDC *DCAlias(CRVDC *dc = NULL)
{
  //TempleOS DCAlias analogue — share body, independent pen/clip. DCDel frees alias only.
  CRVDC *res;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc)
    return NULL;
  res = MAlloc(sizeof(CRVDC));
  if (!res)
    return NULL;
  MemCpy(res, dc, sizeof(CRVDC));
  res->flags |= DCF_ALIAS;
  res->is_scrn = FALSE;
  // body still aliases src (screen or offscreen); do not Free on Del
  return res;
}

U0 DCExtentsInit(CRVDC *dc = NULL)
{
  if (!dc)
    dc = rv_gr.dc;
  if (!dc)
    return;
  dc->flags |= DCF_RECORD_EXTENTS;
  dc->min_x = I64_MAX;
  dc->max_x = I64_MIN;
  dc->min_y = I64_MAX;
  dc->max_y = I64_MIN;
}
// TempleOS API names used by Demo/Graphics blot patterns (32-bpp CRVDC + optional DCNew8).
#define DCNew RVDCNew
#define DCNew8 RVDCNew8
#define DCDel RVDCDel
#define DCFill RVDCFill
#define DCClear RVDCClear
#define DCRst RVDCRst
U0 RVDCFill(CRVDC *dc = NULL, U32 val = 0)
{
  //TempleOS DCFill stores a palette index on 8-bit CDC; on 32-bpp map 0..15 via RVColor
  //(stock Apps use DCFill(WHITE) before black DrawIt staff — raw 15 is not white XRGB).
  I64 i, n;
  U32 *p, px;
  U8 *p8, v8;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body)
    return;
  n = dc->width_internal *dc->height;
  if (dc->is_u8) {
    p8 = dc->body(U8 *);
    if (val == RV_TRANSPARENT)
      v8 = TRANSPARENT;
    else if (val < COLORS_NUM || val == COLOR_MONO)
      v8 = val;
    else
      v8 = val & 0xFF;
    for (i = 0; i < n; i++)
      p8[i] = v8;
    return;
  }
  if (val == RV_TRANSPARENT)
    px = RV_TRANSPARENT;
  else if (val < COLORS_NUM)
    px = RVColor(val);
  else
    px = val;
  p = dc->body;
  for (i = 0; i < n; i++)
    p[i] = px;
}

U0 RVDCClear(CRVDC *dc = NULL)
{
  RVDCFill(dc, 0);
}

I64 RVColorNearestIdx(U32 c)
{
  //Map XRGB to TempleOS 0..15 palette index (TRANSPARENT=0xFF for keying).
  I64 i, best = 0, bestd = I64_MAX, d, r, g, b, pr, pg, pb;
  U32 p;
  if (c == RV_TRANSPARENT)
    return TRANSPARENT;
  r = c >> 16 & 255;
  g = c >> 8 & 255;
  b = c & 255;
  for (i = 0; i < COLORS_NUM; i++) {
    p = rv_palette_std[i];
    pr = p >> 16 & 255;
    pg = p >> 8 & 255;
    pb = p & 255;
    d = (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb);
    if (d < bestd) {
      bestd = d;
      best = i;
    }
  }
  return best;
}

U8 RVDCPenIdx(CRVDC *dc)
{
  //Palette index for is_u8 Plot/Fill (TempleOS CDC pen).
  if (!dc)
    return 0;
  if (dc->color == COLOR_MONO || dc->color == TRANSPARENT)
    return COLOR_MONO;
  if (dc->color < COLORS_NUM)
    return dc->color;
  return RVColorNearestIdx(dc->color);
}

U32 GrPeek(CRVDC *dc = NULL, I64 x, I64 y)
{
  U8 c8;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body || x < 0 || y < 0 || x >= dc->width || y >= dc->height)
    return RV_TRANSPARENT;
  if (dc->is_u8) {
    c8 = dc->body(U8 *)[y *dc->width_internal + x];
    if (c8 == TRANSPARENT)
      return RV_TRANSPARENT;
    return RVColor(c8);
  }
  return dc->body[y *dc->width_internal + x];
}

Bool RVGrInit(I64 width = RV_FB_W_DEFAULT, I64 height = RV_FB_H_DEFAULT, U32 *pixels = NULL)
{
  //Init FB + screen DC + soft terminal. Idempotent enough for smoke demos.
  // pixels=NULL ⇒ RV_FB_BASE_DEFAULT; boards may pass simplefb.base to draw into scanout.
  RVPaletteSetStd;
  if (!RVFbInit(width, height, pixels))
    return FALSE;
  rv_gr.dc = &rv_scrn_dc;
  if (!RVDCScrnBind(rv_gr.dc))
    return FALSE;
  rv_gr.fp_draw_it = NULL;
  rv_gr_dc_u8 = NULL;
  rv_gr_u8_present = 0;
  rv_gr_u8_owned = 0;
  gr.fp_draw_ms = &RVDrawMsNull;
  rv_term.cols = rv_fb.width / FONT_WIDTH;
  rv_term.rows = rv_fb.height / FONT_HEIGHT;
  if (rv_term.cols < 1)
    rv_term.cols = 1;
  if (rv_term.rows < 1)
    rv_term.rows = 1;
  rv_term.cur_r = 0;
  rv_term.cur_c = 0;
  rv_term.fg = RVColor(WHITE);
  rv_term.bg = RV_RGB(32, 64, 128);
  rv_term.ox = 0;
  rv_term.oy = 0;
  return TRUE;
}
// Boot graphics gate for RVSysGrInit: 0=auto (ramfb probe or bound simplefb),
// 1=force soft buffer + try present, -1=never. Auto keeps `-nographic` CI UART-only.
I64 rv_sys_gr_force = 0;
Bool RVSysGrInit()
{
  //RISC-V stand-in for x86 SysGrInit: soft term when a present backend is available.
  // Honors rv_sys_gr_force. Auto: only if ramfb is probed or simplefb is bound.
  I64 mode = rv_sys_gr_force;
  U32 *pix = NULL;
  I64 w = RV_FB_W_DEFAULT, h = RV_FB_H_DEFAULT;
  if (mode < 0)
    return FALSE;
  if (rv_simplefb.bound) {
    RVFbSetPresent(RV_FB_PRESENT_SIMPLEFB);
    pix = rv_simplefb.base;
    w = rv_simplefb.width;
    h = rv_simplefb.height;
  } else if (mode > 0 || RVFbProbeRamfb()) {
    RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  } else {
    return FALSE;
    // auto + no display backend: keep UART-only boot (CI -nographic)
  }
  if (!RVGrInit(w, h, pix))
    return FALSE;
  RVTermClear();
  RVTermPutS("Hello from TempleOS/RISC-V\n");
  RVTermPutS("RVSysGrInit soft term\n");
  RVGrRefresh();
  Print("RVSysGrInit: soft term up present=%d backend=%d %dx%d\n", rv_fb.present_ok, rv_fb.backend, rv_fb.width, rv_fb.height);
  return TRUE;
}

I64 RVBody8ExpandToFB(U8 *body, I64 width, I64 height, I64 wi, I64 dx = 0, I64 dy = 0)
{
  //GrUpdateVGAGraphics portable core: 8-bit palette → XRGB compose (no VGA planes).
  // Clips to rv_fb; returns pixels written. Default WinMgr path does not call this.
  I64 x, y, sx, sy, stride, n = 0;
  U8 c;
  U32 *pix;
  if (!body || !rv_fb.pixels || width < 1 || height < 1 || wi < width)
    return 0;
  pix = rv_fb.pixels;
  stride = RVFbPixStride;
  for (y = 0; y < height; y++) {
    sy = dy + y;
    if (sy < 0 || sy >= rv_fb.height)
      continue;
    for (x = 0; x < width; x++) {
      sx = dx + x;
      if (sx < 0 || sx >= rv_fb.width)
        continue;
      c = body[y *wi + x];
      if (c == TRANSPARENT)
        pix[sy *stride + sx] = RV_TRANSPARENT;
      else
        pix[sy *stride + sx] = RVColor(c);
      n++;
    }
  }
  return n;
}

I64 RVDCExpandU8ToFB(CRVDC *dc8, I64 dx = 0, I64 dy = 0)
{
  //Expand an is_u8 CRVDC body into compose at (dx,dy).
  if (!dc8 || !dc8->is_u8 || !dc8->body)
    return 0;
  return RVBody8ExpandToFB(dc8->body(U8 *), dc8->width, dc8->height, dc8->width_internal, dx, dy);
}

U0 GrUpdateVGAGraphics()
{
  //TempleOS name → expand optional 8-bit compose backbuffer into 32-bpp FB.
  // Stock writes VGA planes; here XR24 compose is the Flip source.
  if (!rv_gr_u8_present || !rv_gr_dc_u8)
    return;
  RVDCExpandU8ToFB(rv_gr_dc_u8, 0, 0);
}

Bool RVGrU8ComposeBind(CRVDC *dc8)
{
  //Opt-in: present expands this is_u8 DC into compose. Does not change 32-bpp draw callers.
  // Caller retains ownership (use Enable for an owned screen-sized buffer).
  if (!dc8 || !dc8->is_u8 || !dc8->body)
    return FALSE;
  if (rv_gr_u8_owned && rv_gr_dc_u8 && rv_gr_dc_u8 != dc8)
    DCDel(rv_gr_dc_u8);
  rv_gr_dc_u8 = dc8;
  rv_gr_u8_present = 1;
  rv_gr_u8_owned = 0;
  return TRUE;
}

U0 RVGrU8ComposeUnbind()
{
  //Stop present expand; leave caller-owned dc_u8 alone (owned buffers freed by Disable).
  if (rv_gr_u8_owned && rv_gr_dc_u8)
    DCDel(rv_gr_dc_u8);
  rv_gr_dc_u8 = NULL;
  rv_gr_u8_present = 0;
  rv_gr_u8_owned = 0;
}

Bool RVGrU8ComposeEnable()
{
  //Alloc screen-sized 8-bit backbuffer and bind for present expand (owned).
  CRVDC *dc8;
  if (!rv_fb.width || !rv_fb.height)
    return FALSE;
  if (rv_gr_dc_u8 && rv_gr_dc_u8->is_u8 && rv_gr_dc_u8->width == rv_fb.width && rv_gr_dc_u8->height == rv_fb.height) {
    rv_gr_u8_present = 1;
    return TRUE;
  }
  dc8 = DCNew8(rv_fb.width, rv_fb.height);
  if (!dc8)
    return FALSE;
  if (rv_gr_u8_owned && rv_gr_dc_u8)
    DCDel(rv_gr_dc_u8);
  rv_gr_dc_u8 = dc8;
  rv_gr_u8_present = 1;
  rv_gr_u8_owned = 1;
  return TRUE;
}

U0 RVGrU8ComposeDisable()
{
  //Unbind and free owned 8-bit compose buffer.
  RVGrU8ComposeUnbind;
}

Bool RVGrU8ComposeActive()
{
  //TRUE when a full-screen is_u8 backbuffer is bound for WinMgr paint + present expand.
  // Small Bind-only DCs (vgaok 16×16) expand on present but do not steal WinMgr draw.
  if (!rv_gr_u8_present || !rv_gr_dc_u8 || !rv_gr_dc_u8->is_u8 || !rv_gr_dc_u8->body)
    return FALSE;
  if (!rv_fb.width || !rv_fb.height)
    return FALSE;
  return rv_gr_dc_u8->width == rv_fb.width && rv_gr_dc_u8->height == rv_fb.height;
}

CRVDC *RVGrPaintDC()
{
  //WinMgr / draw_it paint target: full-screen U8 when active, else 32-bpp screen DC.
  if (RVGrU8ComposeActive)
    return rv_gr_dc_u8;
  return rv_gr.dc;
}

U0 RVGrRefresh()
{
  //WinMgr-lite: optional draw_it, optional 8-bit expand, then Flip+present.
  if (rv_gr.fp_draw_it && rv_gr.dc)
    (*rv_gr.fp_draw_it)(rv_gr.dc);
  if (rv_gr_u8_present)
    GrUpdateVGAGraphics;
  RVFbPresent();
}

U0 RVGrSetDrawIt(U0 (*fp)(CRVDC *dc))
{
  rv_gr.fp_draw_it = fp;
}

I64 RVGrBlotMono(CRVDC *dc, I64 x, I64 y, CRVDC *img)
{
  //ROPB_MONO analogue: non-zero / non-RV_TRANSPARENT brush pixels → dest pen color.
  // Adam GrPlot brush path (GrPrimatives) — top-left of brush at (x,y).
  I64 ix, iy, dx, dy, w, h, cnt = 0;
  U32 *dst, c, pen;
  U8 *src8, *dst8, c8, pen8;
  if (!dc || !dc->body || !img || !img->body)
    return 0;
  if (dc->flags & DCF_DONT_DRAW)
    return 0;
  w = img->width;
  h = img->height;
  pen = RVDCPenColor(dc);
  pen8 = RVDCPenIdx(dc);
  src8 = img->is_u8 ? img->body(U8 *) : NULL;
  dst8 = dc->is_u8 ? dc->body(U8 *) : NULL;
  for (iy = 0; iy < h; iy++) {
    dy = y + iy;
    if (dy < 0 || dy >= dc->height)
      continue;
    if (dc->clip_x2 > dc->clip_x1 && dc->clip_y2 > dc->clip_y1) {
      if (dy < dc->clip_y1 || dy >= dc->clip_y2)
        continue;
    }
    for (ix = 0; ix < w; ix++) {
      dx = x + ix;
      if (dx < 0 || dx >= dc->width)
        continue;
      if (dc->clip_x2 > dc->clip_x1 && dc->clip_y2 > dc->clip_y1) {
        if (dx < dc->clip_x1 || dx >= dc->clip_x2)
          continue;
      }
      if (src8) {
        c8 = src8[iy *img->width_internal + ix];
        if (!c8)
          continue;
      } else {
        c = img->body[iy *img->width_internal + ix];
        if (!c || c == RV_TRANSPARENT)
          continue;
      }
      if (dst8)
        dst8[dy *dc->width_internal + dx] = pen8;
      else {
        dst = dc->body;
        dst[dy *dc->width_internal + dx] = pen;
      }
      cnt++;
      if (dc->flags & DCF_RECORD_EXTENTS) {
        if (dx < dc->min_x)
          dc->min_x = dx;
        if (dx > dc->max_x)
          dc->max_x = dx;
        if (dy < dc->min_y)
          dc->min_y = dy;
        if (dy > dc->max_y)
          dc->max_y = dy;
      }
    }
  }
  return cnt;
}

Bool GrPlot0(CRVDC *dc = NULL, I64 x, I64 y)
{
  //Raw pixel plot — no brush (Adam GrPlot0 shape). Used by FloodFill.
  U32 *body;
  U8 *body8;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body)
    return FALSE;
  if (dc->flags & DCF_DONT_DRAW)
    return FALSE;
  if (x < 0 || y < 0 || x >= dc->width || y >= dc->height)
    return FALSE;
  if (dc->clip_x2 > dc->clip_x1 && dc->clip_y2 > dc->clip_y1) {
    if (x < dc->clip_x1 || y < dc->clip_y1 || x >= dc->clip_x2 || y >= dc->clip_y2)
      return FALSE;
  }
  if (dc->flags & DCF_RECORD_EXTENTS) {
    if (x < dc->min_x)
      dc->min_x = x;
    if (x > dc->max_x)
      dc->max_x = x;
    if (y < dc->min_y)
      dc->min_y = y;
    if (y > dc->max_y)
      dc->max_y = y;
  }
  if (dc->is_u8) {
    body8 = dc->body(U8 *);
    body8[y *dc->width_internal + x] = RVDCPenIdx(dc);
  } else {
    body = dc->body;
    body[y *dc->width_internal + x] = RVDCPenColor(dc);
  }
  return TRUE;
}

Bool GrPlot(CRVDC *dc = NULL, I64 x, I64 y)
{
  //2D plot. Honors brush (mono stamp), clip, DCF_DONT_DRAW / RECORD_EXTENTS.
  CRVDC *br;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body)
    return FALSE;
  if (dc->flags & DCF_DONT_DRAW)
    return FALSE;
  br = dc->brush;
  if (br) {
    //Adam GrPlot brush: GrBlot(dc,x,y,brush) with ROPB_MONO.
    return RVGrBlotMono(dc, x, y, br) > 0;
  }
  return GrPlot0(dc, x, y);
}

U0 GrRect(CRVDC *dc = NULL, I64 x, I64 y, I64 w, I64 h)
{
  //Axis-aligned fill. Clipped to DC + optional clip rect.
  I64 xx, yy, x2, y2;
  U32 *body, c;
  U8 *body8, c8;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body || w <= 0 || h <= 0)
    return;
  if (dc->flags & DCF_DONT_DRAW)
    return;
  x2 = x + w;
  y2 = y + h;
  if (x < 0)
    x = 0;
  if (y < 0)
    y = 0;
  if (x2 > dc->width)
    x2 = dc->width;
  if (y2 > dc->height)
    y2 = dc->height;
  if (dc->clip_x2 > dc->clip_x1 && dc->clip_y2 > dc->clip_y1) {
    if (x < dc->clip_x1)
      x = dc->clip_x1;
    if (y < dc->clip_y1)
      y = dc->clip_y1;
    if (x2 > dc->clip_x2)
      x2 = dc->clip_x2;
    if (y2 > dc->clip_y2)
      y2 = dc->clip_y2;
  }
  if (x >= x2 || y >= y2)
    return;
  if (dc->flags & DCF_RECORD_EXTENTS) {
    if (x < dc->min_x)
      dc->min_x = x;
    if (x2 - 1 > dc->max_x)
      dc->max_x = x2 - 1;
    if (y < dc->min_y)
      dc->min_y = y;
    if (y2 - 1 > dc->max_y)
      dc->max_y = y2 - 1;
  }
  if (dc->is_u8) {
    body8 = dc->body(U8 *);
    c8 = RVDCPenIdx(dc);
    for (yy = y; yy < y2; yy++)
      for (xx = x; xx < x2; xx++)
        body8[yy *dc->width_internal + xx] = c8;
    return;
  }
  body = dc->body;
  c = RVDCPenColor(dc);
  for (yy = y; yy < y2; yy++)
    for (xx = x; xx < x2; xx++)
      body[yy *dc->width_internal + xx] = c;
}

Bool GrLine(CRVDC *dc = NULL, I64 x1, I64 y1, I64 x2, I64 y2, I64 step = 1, I64 start = 0)
{
  //Bresenham. Uses dc->thick as a square brush radius (1 = single pixel).
  // step/start match TempleOS GrLine (Demo/Graphics/NetOfDots.HC uses step=3).
  // When dc->brush is set, each point stamps the brush (Adam GrPlot path) — thick ignored.
  I64 dx, dy, sx, sy, err, e2, x, y, t, i, j, n;
  Bool res = FALSE;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body)
    return FALSE;
  if (dc->flags & DCF_DONT_DRAW)
    return FALSE;
  if (step < 1)
    step = 1;
  dx = x2 - x1;
  if (dx < 0)
    dx = -dx;
  dy = y2 - y1;
  if (dy < 0)
    dy = -dy;
  sx = x1 < x2 ? 1 : -1;
  sy = y1 < y2 ? 1 : -1;
  err = dx - dy;
  x = x1;
  y = y1;
  t = dc->thick;
  if (t < 1)
    t = 1;
  n = 0;
  while (TRUE) {
    if (n >= start && !((n - start) % step)) {
      if (dc->brush || t <= 1)
        res |= GrPlot(dc, x, y);
      else {
        for (j = -(t >> 1); j <= (t >> 1); j++)
          for (i = -(t >> 1); i <= (t >> 1); i++)
            res |= GrPlot(dc, x + i, y + j);
      }
    }
    if (x == x2 && y == y2)
      break;
    e2 = err << 1;
    if (e2 > -dy) {
      err -= dy;
      x += sx;
    }
    if (e2 < dx) {
      err += dx;
      y += sy;
    }
    n++;
  }
  return res;
}

Bool GrLine3(CRVDC *dc = NULL, I64 x1, I64 y1, I64 z1, I64 x2, I64 y2, I64 z2, I64 step = 1, I64 start = 0)
{
  //2D subset of Adam GrLine3 — z ignored (no depth_buf / transform on RV bridge).
  no_warn z1;
  no_warn z2;
  return GrLine(dc, x1, y1, x2, y2, step, start);
}

U0 GrCircle(CRVDC *dc = NULL, I64 cx, I64 cy, I64 rad, I64 step = 1)
{
  //Midpoint circle (outline). thick>1 uses an annular stroke (seals FloodFill); step skips midpoint samples.
  I64 x, y, err, t, i, n, r2_lo, r2_hi, d2, xx, yy, outer;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body || rad < 0)
    return;
  if (dc->flags & DCF_DONT_DRAW)
    return;
  if (step < 1)
    step = 1;
  t = dc->thick;
  if (t < 1)
    t = 1;
  if (dc->brush)
    t = 1;
  if (t > 1 && step == 1 && !dc->brush) {
    //Filled annulus — closed boundary for GrFloodFill (Blot.HC thick=3).
    i = rad - (t >> 1);
    if (i < 0)
      i = 0;
    outer = rad + (t >> 1);
    r2_lo = i *i;
    r2_hi = outer *outer;
    for (yy = -outer; yy <= outer; yy++)
      for (xx = -outer; xx <= outer; xx++) {
        d2 = xx *xx + yy *yy;
        if (r2_lo <= d2 && d2 <= r2_hi)
          GrPlot(dc, cx + xx, cy + yy);
      }
    return;
  }
  x = -rad;
  y = 0;
  err = 2 - 2 * rad;
  n = 0;
  do {
    if (!(n % step)) {
      GrPlot(dc, cx - x, cy + y);
      GrPlot(dc, cx - y, cy - x);
      GrPlot(dc, cx + x, cy - y);
      GrPlot(dc, cx + y, cy + x);
    }
    n++;
    rad = err;
    if (rad <= y)
      err += ++y * 2 + 1;
    if (rad > x || err > y)
      err += ++x * 2 + 1;
  } while (x < 0);
}

Bool GrCircle3(CRVDC *dc = NULL, I64 cx, I64 cy, I64 cz, I64 radius, I64 step = 1)
{
  //2D subset of Adam GrCircle3 — z ignored.
  no_warn cz;
  GrCircle(dc, cx, cy, radius, step);
  return TRUE;
}

U0 GrFillCircle(CRVDC *dc = NULL, I64 cx, I64 cy, I64 rad)
{
  //Filled disk via concentric outlines (MassSpring masses; not FloodFill).
  I64 r;
  I64 saved_thick;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body || rad < 0)
    return;
  if (dc->flags & DCF_DONT_DRAW)
    return;
  saved_thick = dc->thick;
  dc->thick = 1;
  for (r = rad; r >= 0; r--)
    GrCircle(dc, cx, cy, r);
  dc->thick = saved_thick;
}

class CRVFFPt
{
  I16 x;
  I16 y;
};

I64 GrFloodFill(CRVDC *dc = NULL, I64 x, I64 y, Bool not_color = FALSE)
{
  //Adam GrFloodFill shape on 32-bpp CRVDC + optional is_u8 palette body (scanline BFS; no depth_buf).
  // not_color=TRUE: fill while pixel != pen (boundary); FALSE: fill while == seed.
  // Queue starts modest and doubles — full width*height MAlloc fails on lean smoke heaps.
  // Pixel loads can widen to I64 in HolyC compares — mask 32-bit / 8-bit as appropriate.
  // is_u8: compare/write palette indices (RVDCPenIdx); 32-bpp: XRGB (RVDCPenColor / body U32).
  I64 res = 0, old_flags, qcap, head, tail, x0, x1, xx, yy, n, new_cap, idx, wi;
  U32 seed, fill, c2, *body, old_c2, px;
  U8 *body8;
  CRVDC *old_brush;
  CRVFFPt *q, *q2;
  Bool match, u8;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body)
    return 0;
  if (dc->flags & DCF_DONT_DRAW)
    return 0;
  if (x < 0 || y < 0 || x >= dc->width || y >= dc->height)
    return 0;
  old_flags = dc->flags;
  old_brush = dc->brush;
  old_c2 = dc->color2;
  dc->brush = NULL;
  u8 = dc->is_u8;
  wi = dc->width_internal;
  body = NULL;
  body8 = NULL;
  if (u8) {
    body8 = dc->body(U8 *);
    seed = body8[y *wi + x] & 0xFF;
    fill = RVDCPenIdx(dc) & 0xFF;
  } else {
    body = dc->body;
    seed = body[y *wi + x] & 0xFFFFFFFF;
    fill = RVDCPenColor(dc);
  }
  if (not_color) {
    c2 = fill;
    dc->color2 = c2;
    dc->flags |= DCF_FILL_NOT_COLOR;
    if (seed == c2)
      goto ff_done;
  } else {
    c2 = seed;
    dc->color2 = c2;
    dc->flags &= ~DCF_FILL_NOT_COLOR;
    if (c2 == fill)
      goto ff_done;
  }
  n = dc->width *dc->height;
  if (n < 1)
    goto ff_done;
  // Guard against corrupt geometry writing past the body (OOB would inflate res).
  if (dc->width > 4096 || dc->height > 4096 || wi < dc->width)
    goto ff_done;
  qcap = dc->width << 3;
  if (qcap < 4096)
    qcap = 4096;
  if (qcap > n)
    qcap = n;
  q = MAlloc(sizeof(CRVFFPt) * qcap);
  while (!q && qcap > dc->width) {
    qcap >>= 1;
    q = MAlloc(sizeof(CRVFFPt) * qcap);
  }
  if (!q)
    goto ff_done;
  head = 0;
  tail = 0;
  q[tail].x = x;
  q[tail].y = y;
  tail++;
  while (head < tail) {
    xx = q[head].x;
    yy = q[head].y;
    head++;
    if (xx < 0 || yy < 0 || xx >= dc->width || yy >= dc->height)
      continue;
    // Already filled / not a seed match — skip (dedupe queue).
    idx = yy *wi + xx;
    if (u8)
      px = body8[idx] & 0xFF;
    else
      px = body[idx] & 0xFFFFFFFF;
    match = not_color ? px != c2 : px == c2;
    if (!match)
      continue;
    // Expand left to run start
    x0 = xx;
    while (x0 > 0) {
      idx = yy *wi + (x0 - 1);
      if (u8)
        px = body8[idx] & 0xFF;
      else
        px = body[idx] & 0xFFFFFFFF;
      match = not_color ? px != c2 : px == c2;
      if (!match)
        break;
      x0--;
    }
    x1 = xx;
    while (x1 + 1 < dc->width) {
      idx = yy *wi + (x1 + 1);
      if (u8)
        px = body8[idx] & 0xFF;
      else
        px = body[idx] & 0xFFFFFFFF;
      match = not_color ? px != c2 : px == c2;
      if (!match)
        break;
      x1++;
    }
    for (xx = x0; xx <= x1; xx++) {
      idx = yy *wi + xx;
      if (u8)
        px = body8[idx] & 0xFF;
      else
        px = body[idx] & 0xFFFFFFFF;
      match = not_color ? px != c2 : px == c2;
      if (!match)
        continue;
      if (u8)
        body8[idx] = fill;
      else
        body[idx] = fill;
      res++;
      if (res > n) {
        //Geometry/OOB guard
        res = n;
        goto ff_free;
      }
      if (dc->flags & DCF_RECORD_EXTENTS) {
        if (xx < dc->min_x)
          dc->min_x = xx;
        if (xx > dc->max_x)
          dc->max_x = xx;
        if (yy < dc->min_y)
          dc->min_y = yy;
        if (yy > dc->max_y)
          dc->max_y = yy;
      }
      if (yy > 0) {
        idx = (yy - 1) * wi + xx;
        if (u8)
          px = body8[idx] & 0xFF;
        else
          px = body[idx] & 0xFFFFFFFF;
        match = not_color ? px != c2 : px == c2;
        if (match) {
          if (tail >= qcap && qcap < n) {
            new_cap = qcap << 1;
            if (new_cap > n)
              new_cap = n;
            q2 = MAlloc(sizeof(CRVFFPt) * new_cap);
            if (q2) {
              MemCpy(q2, q, sizeof(CRVFFPt) * qcap);
              Free(q);
              q = q2;
              qcap = new_cap;
            }
          }
          if (tail < qcap) {
            q[tail].x = xx;
            q[tail].y = yy - 1;
            tail++;
          }
        }
      }
      if (yy + 1 < dc->height) {
        idx = (yy + 1) * wi + xx;
        if (u8)
          px = body8[idx] & 0xFF;
        else
          px = body[idx] & 0xFFFFFFFF;
        match = not_color ? px != c2 : px == c2;
        if (match) {
          if (tail >= qcap && qcap < n) {
            new_cap = qcap << 1;
            if (new_cap > n)
              new_cap = n;
            q2 = MAlloc(sizeof(CRVFFPt) * new_cap);
            if (q2) {
              MemCpy(q2, q, sizeof(CRVFFPt) * qcap);
              Free(q);
              q = q2;
              qcap = new_cap;
            }
          }
          if (tail < qcap) {
            q[tail].x = xx;
            q[tail].y = yy + 1;
            tail++;
          }
        }
      }
    }
  }
  ff_free:
  Free(q);
  ff_done:
  dc->brush = old_brush;
  dc->flags = old_flags;
  dc->color2 = old_c2;
  return res;
}

I64 GrFloodFill3(CRVDC *dc = NULL, I64 x1, I64 y1, I64 z1, Bool not_color = FALSE)
{
  //2D subset of Adam GrFloodFill3 — z ignored (no transform/depth on RV).
  no_warn z1;
  return GrFloodFill(dc, x1, y1, not_color);
}

U0 Refresh(I64 cnt = 1, Bool force = FALSE)
{
  //Soft WinMgr Refresh — present FB (Blot.HC loop). force/cnt mostly ignored.
  no_warn cnt;
  no_warn force;
  RVGrRefresh();
}

I64 GrBlot(CRVDC *dc = NULL, I64 x, I64 y, CRVDC *img)
{
  //Blit: 32↔32, 8→32 (palette expand), 8→8, 32→8 (quantize). Skips transparent key.
  I64 ix, iy, dx, dy, w, h, cnt = 0;
  U32 *dst, *src, c;
  U8 *src8, *dst8, c8;
  Bool skip_tr;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body || !img || !img->body)
    return 0;
  if (dc->flags & DCF_DONT_DRAW)
    return 0;
  w = img->width;
  h = img->height;
  skip_tr = !(img->flags & DCF_NO_TRANSPARENTS);
  src8 = img->is_u8 ? img->body(U8 *) : NULL;
  dst8 = dc->is_u8 ? dc->body(U8 *) : NULL;
  src = img->body;
  dst = dc->body;
  for (iy = 0; iy < h; iy++) {
    dy = y + iy;
    if (dy < 0 || dy >= dc->height)
      continue;
    if (dc->clip_x2 > dc->clip_x1 && dc->clip_y2 > dc->clip_y1) {
      if (dy < dc->clip_y1 || dy >= dc->clip_y2)
        continue;
    }
    for (ix = 0; ix < w; ix++) {
      dx = x + ix;
      if (dx < 0 || dx >= dc->width)
        continue;
      if (dc->clip_x2 > dc->clip_x1 && dc->clip_y2 > dc->clip_y1) {
        if (dx < dc->clip_x1 || dx >= dc->clip_x2)
          continue;
      }
      if (src8) {
        c8 = src8[iy *img->width_internal + ix];
        if (skip_tr && c8 == TRANSPARENT)
          continue;
        if (dst8)
          dst8[dy *dc->width_internal + dx] = c8;
        else if (c8 == TRANSPARENT)
          dst[dy *dc->width_internal + dx] = RV_TRANSPARENT;
        else
          dst[dy *dc->width_internal + dx] = RVColor(c8);
      } else {
        c = src[iy *img->width_internal + ix];
        if (skip_tr && c == RV_TRANSPARENT)
          continue;
        if (dst8)
          dst8[dy *dc->width_internal + dx] = RVColorNearestIdx(c);
        else
          dst[dy *dc->width_internal + dx] = c;
      }
      cnt++;
      if (dc->flags & DCF_RECORD_EXTENTS) {
        if (dx < dc->min_x)
          dc->min_x = dx;
        if (dx > dc->max_x)
          dc->max_x = dx;
        if (dy < dc->min_y)
          dc->min_y = dy;
        if (dy > dc->max_y)
          dc->max_y = dy;
      }
    }
  }
  return cnt;
}

U0 GrPutChar(CRVDC *dc = NULL, I64 x, I64 y, I64 ch)
{
  //8×8 glyph from sys_font_std into dc at pixel (x,y).
  U8 *glyph;
  I64 row, col;
  U32 saved;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body)
    return;
  glyph = (&sys_font_std[ch & 255])(U8 *);
  saved = dc->color;
  for (row = 0; row < FONT_HEIGHT; row++) {
    U8 bits = glyph[row];
    for (col = 0; col < FONT_WIDTH; col++)
      if (bits & (1 << col))
        GrPlot(dc, x + col, y + row);
  }
  dc->color = saved;
}

U0 GrPrint(CRVDC *dc = NULL, I64 x, I64 y, U8 *st)
{
  //Literal string (no formatting). Newline advances by FONT_HEIGHT.
  I64 cx;
  if (!st)
    return;
  if (!dc)
    dc = rv_gr.dc;
  cx = x;
  while (*st) {
    if (*st == '\n') {
      cx = x;
      y += FONT_HEIGHT;
      st++;
      continue;
    }
    GrPutChar(dc, cx, y, *st++);
    cx += FONT_WIDTH;
  }
}

U0 GrBorder(CRVDC *dc = NULL, I64 x1, I64 y1, I64 x2, I64 y2, I64 step = 1, I64 start = 0)
{
  //Adam GrComposites GrBorder — 2D rect via GrLine3 (Psalmody DrawPickTools).
  GrLine3(dc, x1, y1, 0, x2, y1, 0, step, start);
  GrLine3(dc, x2, y1, 0, x2, y2, 0, step, start);
  GrLine3(dc, x2, y2, 0, x1, y2, 0, step, start);
  GrLine3(dc, x1, y2, 0, x1, y1, 0, step, start);
}

I64 GrVPrint(CRVDC *dc = NULL, I64 x, I64 y, U8 *fmt,...)
{
  //Adam GrBitMap GrVPrint — vertical text for Tempo/Stacatto chrome.
  U8 *buf, *p;
  I64 res = 0, y0;
  if (!fmt)
    return 0;
  if (!dc)
    dc = rv_gr.dc;
  buf = StrPrintJoin(NULL, fmt, argc, argv);
  if (!buf)
    return 0;
  y0 = y;
  p = buf;
  while (*p) {
    if (*p == '\n') {
      y = y0;
      x += FONT_WIDTH;
      p++;
      continue;
    }
    GrPutChar(dc, x, y, *p++);
    y += FONT_HEIGHT;
    res++;
  }
  Free(buf);
  return res;
}

U0 RVTermClear()
{
  //Fill terminal region with bg and reset cursor.
  I64 pw, ph;
  if (!rv_gr.dc)
    return;
  pw = rv_term.cols *FONT_WIDTH;
  ph = rv_term.rows *FONT_HEIGHT;
  rv_gr.dc->color = rv_term.bg;
  GrRect(rv_gr.dc, rv_term.ox, rv_term.oy, pw, ph);
  rv_term.cur_r = 0;
  rv_term.cur_c = 0;
}

U0 RVTermScroll()
{
  //Scroll terminal pixel region up one text row.
  I64 y, x, pw, ph;
  U32 *body;
  if (!rv_fb.pixels || rv_term.rows < 2) {
    RVTermClear();
    return;
  }
  body = rv_fb.pixels;
  pw = rv_term.cols *FONT_WIDTH;
  ph = rv_term.rows *FONT_HEIGHT;
  for (y = FONT_HEIGHT; y < ph; y++) {
    I64 dy = rv_term.oy + y - FONT_HEIGHT;
    I64 sy = rv_term.oy + y;
    for (x = 0; x < pw; x++)
      body[dy *rv_fb.width + (rv_term.ox + x)] = body[sy *rv_fb.width + (rv_term.ox + x)];
  }
  rv_gr.dc->color = rv_term.bg;
  GrRect(rv_gr.dc, rv_term.ox, rv_term.oy + (rv_term.rows - 1) * FONT_HEIGHT, pw, FONT_HEIGHT);
}

U0 RVTermPutChar(I64 ch)
{
  I64 px, py;
  if (!rv_gr.dc)
    return;
  if (ch == '\n') {
    rv_term.cur_c = 0;
    rv_term.cur_r++;
    if (rv_term.cur_r >= rv_term.rows) {
      RVTermScroll;
      rv_term.cur_r = rv_term.rows - 1;
    }
    return;
  }
  if (ch == '\r') {
    rv_term.cur_c = 0;
    return;
  }
  if (rv_term.cur_c >= rv_term.cols) {
    RVTermPutChar('\n');
  }
  px = rv_term.ox + rv_term.cur_c *FONT_WIDTH;
  py = rv_term.oy + rv_term.cur_r *FONT_HEIGHT;
  // Cell background then glyph
  rv_gr.dc->color = rv_term.bg;
  GrRect(rv_gr.dc, px, py, FONT_WIDTH, FONT_HEIGHT);
  rv_gr.dc->color = rv_term.fg;
  GrPutChar(rv_gr.dc, px, py, ch);
  rv_term.cur_c++;
}

U0 RVTermPutS(U8 *st)
{
  if (!st)
    return;
  while (*st)
    RVTermPutChar (*st++);
}

U0 RVWinFill(I64 x, I64 y, I64 w, I64 h, U32 face, U32 border, U8 *title = NULL)
{
  //Minimal window chrome: border + title bar + face. Not a real WinMgr.
  CRVDC *dc = rv_gr.dc;
  if (!dc)
    return;
  dc->color = border;
  GrRect(dc, x, y, w, h);
  dc->color = face;
  if (w > 4 && h > 4)
    GrRect(dc, x + 2, y + 2, w - 4, h - 4);
  dc->color = border;
  GrRect(dc, x, y, w, FONT_HEIGHT + 4);
  if (title) {
    dc->color = RVColor(YELLOW);
    GrPrint(dc, x + 4, y + 2, title);
  }
}
// --- CDC copy/diff + 8-bit GR-lite + soft ScrnCast + flat mesh (libs-first) ---
#define RVGR_MAGIC 'RVGR'
class CRVGRHdr
{
  //GR-lite: CRVGRHdr + 8-bit body, or + CArcCompress body when DCF_COMPRESSED.
  I64 magic;
  I64 width;
  I64 height;
  I64 width_internal;
  I64 x0;
  I64 y0;
  I64 flags;
};
CRVDC *rv_scrncast_base;
Bool rv_scrncast_on;
I64 rv_scrncast_winmgr_hits;
// RVWinMgrRefresh → ScrnCastFrame count (smoke needle)
CRVDC *DCCopy(CRVDC *dc)
{
  //Alloc independent copy of CRVDC body (Adam DCCopy shape; no depth/mat).
  CRVDC *res;
  I64 n;
  if (!dc || !dc->body)
    return NULL;
  if (dc->is_u8)
    res = DCNew8(dc->width, dc->height);
  else
    res = DCNew(dc->width, dc->height);
  if (!res)
    return NULL;
  if (dc->is_u8)
    n = dc->width_internal *dc->height;
  else
    n = dc->width_internal *dc->height *sizeof(U32);
  MemCpy(res->body, dc->body, n);
  res->color = dc->color;
  res->color2 = dc->color2;
  res->bkcolor = dc->bkcolor;
  res->thick = dc->thick;
  res->flags = dc->flags & ~(DCF_ALIAS | DCF_SCRN_BITMAP);
  res->x0 = dc->x0;
  res->y0 = dc->y0;
  res->clip_x1 = dc->clip_x1;
  res->clip_y1 = dc->clip_y1;
  res->clip_x2 = dc->clip_x2;
  res->clip_y2 = dc->clip_y2;
  return res;
}

CRVDC *DCExt(CRVDC *dc, I64 x1, I64 y1, I64 x2, I64 y2)
{
  //Crop inclusive rect into a new DC (Adam DCExt; no win_task scroll).
  CRVDC *res;
  I64 x, y, w, h;
  U32 *src, *dst;
  U8 *src8, *dst8;
  if (!dc || !dc->body)
    return NULL;
  if (x1 > x2)
    SwapI64(&x1, &x2);
  if (y1 > y2)
    SwapI64(&y1, &y2);
  if (x1 < 0)
    x1 = 0;
  if (y1 < 0)
    y1 = 0;
  if (x2 >= dc->width)
    x2 = dc->width - 1;
  if (y2 >= dc->height)
    y2 = dc->height - 1;
  if (x1 > x2 || y1 > y2)
    return NULL;
  w = x2 - x1 + 1;
  h = y2 - y1 + 1;
  if (dc->is_u8)
    res = DCNew8(w, h);
  else
    res = DCNew(w, h);
  if (!res)
    return NULL;
  DCFill(res, 0);
  if (dc->is_u8) {
    src8 = dc->body(U8 *);
    dst8 = res->body(U8 *);
    for (y = 0; y < h; y++)
      for (x = 0; x < w; x++)
        dst8[y *res->width_internal + x] = src8[(y1 + y) * dc->width_internal + (x1 + x)];
  } else {
    src = dc->body;
    dst = res->body;
    for (y = 0; y < h; y++)
      for (x = 0; x < w; x++)
        dst[y *res->width_internal + x] = src[(y1 + y) * dc->width_internal + (x1 + x)];
  }
  res->x0 = x1;
  res->y0 = y1;
  return res;
}

CRVDC *DCDiff(CRVDC *base, CRVDC *update)
{
  //Trim to window of changed pixels (Adam DCDiff). Same body mode required.
  I64 x1 = 0, y1 = 0, x2, y2, x, y;
  CRVDC *res;
  U32 *b, *u;
  U8 *b8, *u8;
  if (!base || !update || !base->body || !update->body)
    return NULL;
  if (base->width != update->width || base->height != update->height)
    return NULL;
  if (base->is_u8 != update->is_u8)
    return NULL;
  x2 = update->width - 1;
  y2 = update->height - 1;
  if (base->is_u8) {
    b8 = base->body(U8 *);
    u8 = update->body(U8 *);
    while (y1 <= y2) {
      for (x = 0; x < update->width; x++)
        if (b8[y1 *base->width_internal + x] != u8[y1 *update->width_internal + x])
          goto df_y2;
      y1++;
    }
    return NULL;
    df_y2:
    while (y1 < y2) {
      for (x = 0; x < update->width; x++)
        if (b8[y2 *base->width_internal + x] != u8[y2 *update->width_internal + x])
          goto df_x1;
      y2--;
    }
    df_x1:
    while (x1 < x2) {
      for (y = y1; y <= y2; y++)
        if (b8[y *base->width_internal + x1] != u8[y *update->width_internal + x1])
          goto df_x2;
      x1++;
    }
    df_x2:
    while (x1 < x2) {
      for (y = y1; y <= y2; y++)
        if (b8[y *base->width_internal + x2] != u8[y *update->width_internal + x2])
          goto df_done;
      x2--;
    }
  } else {
    b = base->body;
    u = update->body;
    while (y1 <= y2) {
      for (x = 0; x < update->width; x++)
        if (b[y1 *base->width_internal + x] != u[y1 *update->width_internal + x])
          goto df32_y2;
      y1++;
    }
    return NULL;
    df32_y2:
    while (y1 < y2) {
      for (x = 0; x < update->width; x++)
        if (b[y2 *base->width_internal + x] != u[y2 *update->width_internal + x])
          goto df32_x1;
      y2--;
    }
    df32_x1:
    while (x1 < x2) {
      for (y = y1; y <= y2; y++)
        if (b[y *base->width_internal + x1] != u[y *update->width_internal + x1])
          goto df32_x2;
      x1++;
    }
    df32_x2:
    while (x1 < x2) {
      for (y = y1; y <= y2; y++)
        if (b[y *base->width_internal + x2] != u[y *update->width_internal + x2])
          goto df_done;
      x2--;
    }
  }
  df_done:
  res = DCExt(update, x1, y1, x2, y2);
  return res;
}

U8 *DCBody8(CRVDC *dc)
{
  //Quantize 32-bpp CRVDC → 8-bit palette indices, or identity-copy is_u8 body.
  U8 *dst;
  I64 x, y, wi, n;
  if (!dc || !dc->body)
    return NULL;
  wi = dc->width + 7 & ~7;
  n = wi *dc->height;
  dst = CAlloc(n);
  if (!dst)
    return NULL;
  if (dc->is_u8) {
    for (y = 0; y < dc->height; y++)
      for (x = 0; x < dc->width; x++)
        dst[y *wi + x] = dc->body(U8 *)[y *dc->width_internal + x];
    return dst;
  }
  for (y = 0; y < dc->height; y++)
    for (x = 0; x < dc->width; x++)
      dst[y *wi + x] = RVColorNearestIdx(dc->body[y *dc->width_internal + x]);
  return dst;
}

CRVDC *DCFromBody8(U8 *body, I64 width, I64 height)
{
  //Expand 8-bit palette body → 32-bpp CRVDC (ScrnCast/GR load path).
  CRVDC *dc;
  I64 x, y, wi;
  U8 c;
  if (!body || width < 1 || height < 1)
    return NULL;
  wi = width + 7 & ~7;
  dc = DCNew(width, height);
  if (!dc)
    return NULL;
  for (y = 0; y < height; y++)
    for (x = 0; x < width; x++) {
      c = body[y *wi + x];
      if (c == TRANSPARENT)
        dc->body[y *dc->width_internal + x] = RV_TRANSPARENT;
      else
        dc->body[y *dc->width_internal + x] = RVColor(c);
    }
  return dc;
}

U8 *DCSave(CRVDC *dc, I64 *_size = NULL, I64 dcsf_flags = 0)
{
  //GR-lite blob: CRVGRHdr + 8-bit body. DCSF_COMPRESSED → CompressBuf (CArcCompress).
  U8 *body8, *res, *ptr, *payload;
  CArcCompress *arc = NULL;
  I64 wi, body_size, payload_size, total, flags;
  CRVGRHdr *hdr;
  if (!dc || !dc->body)
    return NULL;
  body8 = DCBody8(dc);
  if (!body8)
    return NULL;
  wi = dc->width + 7 & ~7;
  body_size = wi *dc->height;
  flags = 0;
  if (dcsf_flags & DCSF_COMPRESSED) {
    arc = CompressBuf(body8, body_size);
    Free(body8);
    body8 = NULL;
    if (!arc)
      return NULL;
    payload = arc;
    payload_size = arc->compressed_size;
    flags |= DCF_COMPRESSED;
  } else {
    payload = body8;
    payload_size = body_size;
  }
  total = sizeof(CRVGRHdr) + payload_size;
  res = MAlloc(total);
  if (!res) {
    Free(body8);
    Free(arc);
    return NULL;
  }
  hdr = res(CRVGRHdr *);
  hdr->magic = RVGR_MAGIC;
  hdr->width = dc->width;
  hdr->height = dc->height;
  hdr->width_internal = wi;
  hdr->x0 = dc->x0;
  hdr->y0 = dc->y0;
  hdr->flags = flags;
  ptr = res + sizeof(CRVGRHdr);
  MemCpy(ptr, payload, payload_size);
  Free(body8);
  Free(arc);
  if (_size)
    *_size = total;
  return res;
}

CRVDC *DCLoad(U8 *src, I64 *_size = NULL)
{
  //Load GR-lite → 32-bpp CRVDC via palette expand (ExpandBuf if DCF_COMPRESSED).
  CRVGRHdr *hdr;
  CRVDC *dc;
  U8 *body, *body8 = NULL;
  CArcCompress *arc;
  I64 body_size, payload_size;
  if (!src)
    return NULL;
  hdr = src(CRVGRHdr *);
  if (hdr->magic != RVGR_MAGIC || hdr->width < 1 || hdr->height < 1)
    return NULL;
  body = src + sizeof(CRVGRHdr);
  body_size = hdr->width_internal *hdr->height;
  if (hdr->flags & DCF_COMPRESSED) {
    arc = body(CArcCompress *);
    payload_size = arc->compressed_size;
    body8 = ExpandBuf(arc);
    if (!body8)
      return NULL;
    dc = DCFromBody8(body8, hdr->width, hdr->height);
    Free(body8);
  } else {
    payload_size = body_size;
    dc = DCFromBody8(body, hdr->width, hdr->height);
  }
  if (!dc)
    return NULL;
  dc->x0 = hdr->x0;
  dc->y0 = hdr->y0;
  if (_size)
    *_size = sizeof(CRVGRHdr) + payload_size;
  return dc;
}

I64 GRWrite(U8 *filename, CRVDC *dc, I64 dcsf_flags = 0)
{
  //TempleOS GRWrite soft — FileWrite GR-lite; DCSF_COMPRESSED → .GR.Z ExtDft shape.
  I64 size = 0, wrote;
  U8 *src, *st;
  if (!filename || !dc)
    return 0;
  if (dcsf_flags & DCSF_COMPRESSED)
    st = ExtDft(filename, "GR.Z");
  else
    st = ExtDft(filename, "GR");
  src = DCSave(dc, &size, dcsf_flags);
  if (!src) {
    Free(st);
    return 0;
  }
  wrote = FileWrite(st, src, size);
  Free(st);
  Free(src);
  if (wrote)
    return size;
  return 0;
}

CRVDC *GRRead(U8 *filename)
{
  //TempleOS GRRead soft — try .GR.Z then .GR via ExtDft/FileRead.
  U8 *src, *st;
  CRVDC *dc = NULL;
  if (!filename)
    return NULL;
  st = ExtDft(filename, "GR.Z");
  src = FileRead(st);
  Free(st);
  if (!src) {
    st = ExtDft(filename, "GR");
    src = FileRead(st);
    Free(st);
  }
  if (!src)
    return NULL;
  dc = DCLoad(src);
  Free(src);
  return dc;
}

Bool GRScrnCaptureRead(U8 *filename, CRVDC *dc = NULL, I64 x = 0, I64 y = 0)
{
  //Demo/Graphics/ScrnCapture.HC — GrBlot GR file onto dc.
  CRVDC *dc2;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc)
    return FALSE;
  dc2 = GRRead(filename);
  if (!dc2)
    return FALSE;
  GrBlot(dc, x, y, dc2);
  DCDel(dc2);
  return TRUE;
}

I64 GRScrnCaptureWrite(U8 *filename, Bool include_zoom = TRUE)
{
  //Capture screen DC to GR-lite file (no zoom plane on RV).
  CRVDC *dc;
  I64 size;
  no_warn include_zoom;
  if (!filename || !rv_gr.dc)
    return 0;
  dc = DCCopy(rv_gr.dc);
  if (!dc)
    return 0;
  size = GRWrite(filename, dc, 0);
  DCDel(dc);
  return size;
}

U0 RVScrnCastSndArm()
{
  //Stock ScrnCast(ON) snd arm: empty queue + t0 for AUWrite cdt stamps.
  if (!scrncast.snd_head.next)
    QueInit(&scrncast.snd_head);
  else
    QueDel(&scrncast.snd_head, TRUE);
  scrncast.t0_now = Now;
  scrncast.snd_head.tS = scrncast.t0_tS = tS;
  scrncast.snd_head.ona = scrncast.ona;
}

U0 ScrnCastStart(CRVDC *dc = NULL, Bool just_audio = FALSE)
{
  //Soft ScrnCast — video base for DCDiff frames, or just_audio (snd queue only).
  // WinMgr Refresh hooks ScrnCastFrame when record && !just_audio.
  if (rv_scrncast_base) {
    DCDel(rv_scrncast_base);
    rv_scrncast_base = NULL;
  }
  rv_scrncast_on = FALSE;
  scrncast.just_audio = just_audio;
  if (just_audio) {
    scrncast.record = TRUE;
  } else {
    if (!dc)
      dc = rv_gr.dc;
    rv_scrncast_base = DCCopy(dc);
    rv_scrncast_on = rv_scrncast_base != NULL;
    scrncast.record = rv_scrncast_on;
  }
  if (scrncast.record)
    RVScrnCastSndArm;
}

U0 ScrnCastStop()
{
  //Leave snd_head for AUWrite (stock ScrnCast(OFF) shape); caller QueDel after.
  if (rv_scrncast_base) {
    DCDel(rv_scrncast_base);
    rv_scrncast_base = NULL;
  }
  rv_scrncast_on = FALSE;
  scrncast.record = FALSE;
  scrncast.just_audio = FALSE;
}

U0 SndShift(CSndData *head, F64 dt = 0)
{
  //Stock ScrnCast SndShift — drop nodes that go out of order after -dt.
  CSndData *tmpsd, *tmpsd1;
  if (!head || !dt)
    return;
  tmpsd = head->next;
  while (tmpsd != head) {
    tmpsd1 = tmpsd->next;
    tmpsd->tS -= dt;
    if (tmpsd->tS < tmpsd->last->tS) {
      QueRem(tmpsd);
      Free(tmpsd);
    }
    tmpsd = tmpsd1;
  }
}

I64 AUWrite(U8 *filename, CSndData *head, CDate *t0_now, F64 t0_tS)
{
  //Stock AUWrite — serialize CSndData ring to .AU (CAUData cdt+ona). filename NULL → size only.
  CSndData *tmpsd;
  CAUData *base, *dst;
  I64 size;
  U8 *st;
  CDate t0;
  if (!head)
    return 0;
  if (t0_now)
    t0 = *t0_now;
  else
    t0 = scrncast.t0_now;
  size = (1 + QueCnt(head)) * sizeof(CAUData);
  base = dst = MAlloc(size);
  if (!base)
    return 0;
  tmpsd = head;
  do {
    dst->cdt = t0(I64) + ToI64(CDATE_FREQ * (tmpsd->tS - t0_tS));
    dst->ona = tmpsd->ona;
    dst++;
    tmpsd = tmpsd->next;
  } while (tmpsd != head);
  if (filename) {
    st = ExtDft(filename, "AU");
    FileWrite(st, base, dst(U8 *) - base(U8 *));
    Free(st);
  }
  Free(base);
  return size;
}

I64 ScrnCastFrame(CRVDC *update = NULL)
{
  //One ScrnCast video frame: DCDiff vs base, then refresh base. Returns changed pix cnt.
  CRVDC *diff, *next;
  I64 n = 0;
  if (!rv_scrncast_on || !rv_scrncast_base)
    return 0;
  if (!update)
    update = rv_gr.dc;
  if (!update)
    return 0;
  diff = DCDiff(rv_scrncast_base, update);
  if (diff) {
    n = diff->width *diff->height;
    DCDel(diff);
  }
  next = DCCopy(update);
  if (next) {
    DCDel(rv_scrncast_base);
    rv_scrncast_base = next;
  }
  return n;
}

U0 RVScrnCastWinMgrHook()
{
  //Adam/WinMgr.HC post-GrUpdateScrn shape: record video frames from live compose DC.
  // First refresh while recording establishes base (stock first GRWrite); later → Frame.
  // just_audio: skip video (stock); RVSnd still queues CSndData for AUWrite.
  if (!scrncast.record || scrncast.just_audio) {
    if (!scrncast.record && rv_scrncast_on)
      ScrnCastStop;
    return;
  }
  if (!rv_gr.dc)
    return;
  if (!rv_scrncast_on || !rv_scrncast_base) {
    ScrnCastStart(rv_gr.dc);
    return;
  }
  ScrnCastFrame(NULL);
  rv_scrncast_winmgr_hits++;
}

I64 GrHLine(CRVDC *dc = NULL, I64 x1, I64 x2, I64 y, I64 z1 = 0, I64 z2 = 0)
{
  //2D horizontal run (Adam GrHLine subset; z ignored — no depth buf).
  I64 x, cnt = 0;
  no_warn z1;
  no_warn z2;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body)
    return 0;
  if (dc->flags & DCF_DONT_DRAW)
    return 0;
  if (x1 > x2)
    SwapI64(&x1, &x2);
  for (x = x1; x <= x2; x++) {
    GrPlot(dc, x, y);
    cnt++;
  }
  return cnt;
}

I64 GrFillTri0(CRVDC *dc = NULL, CD3I32 *p1, CD3I32 *p2, CD3I32 *p3)
{
  //Flat 2D triangle fill (barycentric). No depth/z-interp — mesh libs-first.
  I64 x, y, minx, maxx, miny, maxy, res = 0;
  I64 x1, y1, x2, y2, x3, y3, area, a1, a2, a3;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body || !p1 || !p2 || !p3)
    return 0;
  if (dc->flags & DCF_DONT_DRAW)
    return 0;
  x1 = p1->x;
  y1 = p1->y;
  x2 = p2->x;
  y2 = p2->y;
  x3 = p3->x;
  y3 = p3->y;
  area = (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1);
  if (!area)
    return 0;
  minx = x1;
  if (x2 < minx)
    minx = x2;
  if (x3 < minx)
    minx = x3;
  maxx = x1;
  if (x2 > maxx)
    maxx = x2;
  if (x3 > maxx)
    maxx = x3;
  miny = y1;
  if (y2 < miny)
    miny = y2;
  if (y3 < miny)
    miny = y3;
  maxy = y1;
  if (y2 > maxy)
    maxy = y2;
  if (y3 > maxy)
    maxy = y3;
  if (minx < 0)
    minx = 0;
  if (miny < 0)
    miny = 0;
  if (maxx >= dc->width)
    maxx = dc->width - 1;
  if (maxy >= dc->height)
    maxy = dc->height - 1;
  for (y = miny; y <= maxy; y++)
    for (x = minx; x <= maxx; x++) {
      a1 = (x2 - x) * (y3 - y) - (x3 - x) * (y2 - y);
      a2 = (x3 - x) * (y1 - y) - (x1 - x) * (y3 - y);
      a3 = (x1 - x) * (y2 - y) - (x2 - x) * (y1 - y);
      if (area > 0) {
        if (a1 >= 0 && a2 >= 0 && a3 >= 0) {
          GrPlot(dc, x, y);
          res++;
        }
      } else if (a1 <= 0 && a2 <= 0 && a3 <= 0) {
        GrPlot(dc, x, y);
        res++;
      }
    }
  return res;
}

I64 Gr3Mesh(CRVDC *dc = NULL, I64 vertex_cnt, CD3I32 *p, I64 tri_cnt, CMeshTri *tri)
{
  //Flat-shaded mesh (Adam Gr3Mesh subset — no transform/lighting/symmetry).
  I64 i, res = 0;
  U32 old_color;
  CMeshTri *t;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !p || !tri || vertex_cnt < 1 || tri_cnt < 1)
    return 0;
  old_color = dc->color;
  t = tri;
  for (i = 0; i < tri_cnt; i++, t++) {
    if (t->nums[0] < 0 || t->nums[0] >= vertex_cnt)
      continue;
    if (t->nums[1] < 0 || t->nums[1] >= vertex_cnt)
      continue;
    if (t->nums[2] < 0 || t->nums[2] >= vertex_cnt)
      continue;
    dc->color = RVColor(t->color);
    res += GrFillTri0(dc, &p[t->nums[0]], &p[t->nums[1]], &p[t->nums[2]]);
  }
  dc->color = old_color;
  return res;
}

I64 RVGrSoft()
{
  // Soft Call: tiny offscreen Gr blit (UART / no interactive FB).
  // DCNew → DCFill → GrPlot → 2×2 GrBlot → GrPeek (RED+ink) → DCDel.
  // Host AOT: U32i keyword prefer + ScalarTypeForSize on local U32* peels (was 8-byte
  // ld/sd clobbering neighbors; member body[] already narrowed).
  CRVDC *dst, *src;
  I64 n;
  U32 peek, red, ink, black;
  RVPaletteSetStd;
  red = RVColor(RED);
  black = RVColor(BLACK);
  ink = RVColor(GREEN);
  dst = DCNew(8, 8);
  if (!dst)
    return 3;
  src = DCNew(2, 2);
  if (!src) {
    DCDel(dst);
    return 4;
  }
  src->flags |= DCF_NO_TRANSPARENTS;
  DCFill(dst, BLACK);
  DCFill(src, ink);
  peek = GrPeek(src, 1, 0);
  if (peek != ink) {
    DCDel(src);
    DCDel(dst);
    return 11;
  }
  src->color = RED;
  if (!GrPlot(src, 0, 0)) {
    DCDel(src);
    DCDel(dst);
    return 5;
  }
  n = GrBlot(dst, 3, 3, src);
  if (n < 4) {
    DCDel(src);
    DCDel(dst);
    return 6;
  }
  peek = GrPeek(dst, 3, 3);
  if (peek != red) {
    DCDel(src);
    DCDel(dst);
    return 7;
  }
  peek = GrPeek(dst, 4, 3);
  if (peek != ink) {
    DCDel(src);
    DCDel(dst);
    return 9;
  }
  peek = GrPeek(dst, 0, 0);
  if (peek != black) {
    DCDel(src);
    DCDel(dst);
    return 10;
  }
  DCDel(src);
  DCDel(dst);
  return 8;
}
