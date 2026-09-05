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
// Full 8-bit palette CDC body / ScrnCast / mesh still deferred.
// TempleOS CDC* name → 32-bpp CRVDC (stock Demo/Graphics/*.HC).
#define CDC CRVDC
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
  //32-bpp CDC bridge (not 8-bit palette body). color is XRGB U32.
  U32 *body;
  I64 width;
  I64 height;
  I64 width_internal;
  // pixels per row
  U32 color;
  U32 color2;
  U32 bkcolor;
  I64 thick;
  I64 flags;
  // DCF_* subset: DONT_DRAW, RECORD_EXTENTS, NO_TRANSPARENTS, ALIAS, SCRN_BITMAP
  Bool is_scrn;
  // TRUE ⇒ body aliases rv_fb.pixels (compose)
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
  // persistent screen DC
  U0 (*fp_draw_it)(CRVDC *dc);
  // optional WinMgr-lite refresh hook
};
CRVGrGlbls rv_gr;
CRVDC rv_scrn_dc;
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
  n = width *height *sizeof(U32);
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
// TempleOS API names used by Demo/Graphics blot patterns (32-bpp CRVDC, not 8-bit CDC).
#define DCNew RVDCNew
#define DCDel RVDCDel
#define DCFill RVDCFill
#define DCClear RVDCClear
#define DCRst RVDCRst
U0 RVDCFill(CRVDC *dc = NULL, U32 val = 0)
{
  I64 i, n;
  U32 *p;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body)
    return;
  n = dc->width_internal *dc->height;
  p = dc->body;
  for (i = 0; i < n; i++)
    p[i] = val;
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

U32 GrPeek(CRVDC *dc = NULL, I64 x, I64 y)
{
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !dc->body || x < 0 || y < 0 || x >= dc->width || y >= dc->height)
    return RV_TRANSPARENT;
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

U0 RVGrRefresh()
{
  //WinMgr-lite: optional draw_it, then push pixels to the active present backend.
  if (rv_gr.fp_draw_it && rv_gr.dc)
    (*rv_gr.fp_draw_it)(rv_gr.dc);
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
  if (!dc || !dc->body || !img || !img->body)
    return 0;
  if (dc->flags & DCF_DONT_DRAW)
    return 0;
  w = img->width;
  h = img->height;
  pen = RVDCPenColor(dc);
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
      c = img->body[iy *img->width_internal + ix];
      if (!c || c == RV_TRANSPARENT)
        continue;
      dst = dc->body;
      dst[dy *dc->width_internal + dx] = pen;
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
  body = dc->body;
  body[y *dc->width_internal + x] = RVDCPenColor(dc);
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
  //Adam GrFloodFill shape on 32-bpp CRVDC (scanline BFS; no depth_buf).
  // not_color=TRUE: fill while pixel != pen (boundary); FALSE: fill while == seed.
  // Queue starts modest and doubles — full width*height MAlloc fails on lean smoke heaps.
  // Pixel loads via U32* can widen to I64 in HolyC compares — always mask to 32-bit.
  I64 res = 0, old_flags, qcap, head, tail, x0, x1, xx, yy, n, new_cap, idx;
  U32 seed, fill, c2, *body, old_c2, px;
  CRVDC *old_brush;
  CRVFFPt *q, *q2;
  Bool match;
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
  seed = GrPeek(dc, x, y);
  fill = RVDCPenColor(dc);
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
  if (dc->width > 4096 || dc->height > 4096 || dc->width_internal < dc->width)
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
  body = dc->body;
  while (head < tail) {
    xx = q[head].x;
    yy = q[head].y;
    head++;
    if (xx < 0 || yy < 0 || xx >= dc->width || yy >= dc->height)
      continue;
    // Already filled / not a seed match — skip (dedupe queue).
    px = body[yy *dc->width_internal + xx] & 0xFFFFFFFF;
    match = not_color ? px != c2 : px == c2;
    if (!match)
      continue;
    // Expand left to run start
    x0 = xx;
    while (x0 > 0) {
      px = body[yy *dc->width_internal + (x0 - 1)] & 0xFFFFFFFF;
      match = not_color ? px != c2 : px == c2;
      if (!match)
        break;
      x0--;
    }
    x1 = xx;
    while (x1 + 1 < dc->width) {
      px = body[yy *dc->width_internal + (x1 + 1)] & 0xFFFFFFFF;
      match = not_color ? px != c2 : px == c2;
      if (!match)
        break;
      x1++;
    }
    for (xx = x0; xx <= x1; xx++) {
      idx = yy *dc->width_internal + xx;
      px = body[idx] & 0xFFFFFFFF;
      match = not_color ? px != c2 : px == c2;
      if (!match)
        continue;
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
        px = body[(yy - 1) * dc->width_internal + xx] & 0xFFFFFFFF;
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
        px = body[(yy + 1) * dc->width_internal + xx] & 0xFFFFFFFF;
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
  //32-bpp blit. Skips RV_TRANSPARENT unless DCF_NO_TRANSPARENTS on img.
  I64 ix, iy, dx, dy, w, h, cnt = 0;
  U32 *dst, *src, c;
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
      c = img->body[iy *img->width_internal + ix];
      if (skip_tr && c == RV_TRANSPARENT)
        continue;
      dst = dc->body;
      dst[dy *dc->width_internal + dx] = c;
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
