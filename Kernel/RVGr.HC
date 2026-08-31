// Thin Gr*/CDC path for native 32-bpp FB (Phase F). Not VGA, not full Adam/Gr/WinMgr.
//
// Draws into CRVDC bodies that are U32 XRGB8888 (same layout as rv_fb.pixels).
// Screen DC aliases rv_fb; RVGrRefresh() presents via RVFbPresent().
// Soft terminal paints 8×8 glyphs into the FB and flushes with the same present path.
//
// Full Adam GrBitMap (8-bit palette + VGA planes) stays for x86; RV demos use this file.
// VGA-style 16-color indices → XRGB8888 (matches common TempleOS palette intent).
U32 rv_palette_std[COLORS_NUM] =
{
  0x00000000, 0x000000AA, 0x0000AA00, 0x0000AAAA, 0x00AA0000, 0x00AA00AA, 0x00AA5500, 0x00AAAAAA, 0x00555555, 0x005555FF, 0x0055FF55, 0x0055FFFF, 0x00FF5555, 0x00FF55FF, 0x00FFFF55, 0x00FFFFFF};
  U32 RVColor(I64 idx)
  {
    //Map TempleOS color index 0..15 to XRGB; pass-through if already a full pixel.
    if (idx >= 0 && idx < COLORS_NUM)
      return rv_palette_std[idx];
    return idx & 0xFFFFFFFF;
  }
  class CRVDC
  {
    //Minimal CDC: 32-bpp body (not 8-bit palette). color is XRGB U32.
    U32 *body;
    I64 width;
    I64 height;
    I64 width_internal;
    // pixels per row
    U32 color;
    I64 thick;
    I64 flags;
    Bool is_scrn;
    // TRUE ⇒ body aliases rv_fb.pixels
  }
  ;
  class CRVGrGlbls
  {
    CRVDC *dc;
    // persistent screen DC
    U0 (*fp_draw_it)(CRVDC *dc);
    // optional WinMgr-lite refresh hook
  }
  ;
  CRVGrGlbls rv_gr;
  CRVDC rv_scrn_dc;
  // screen DC storage (aliases rv_fb.pixels after RVGrInit)
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
  }
  ;
  CRVTerm rv_term;
  U0 RVDCRst(CRVDC *dc)
  {
    if (!dc)
      return;
    dc->color = RVColor(WHITE);
    dc->thick = 1;
    dc->flags = 0;
  }
  Bool RVDCScrnBind(CRVDC *dc)
  {
    //Point dc at the live linear FB. Requires RVFbInit first.
    if (!dc || !rv_fb.pixels)
      return FALSE;
    dc->body = rv_fb.pixels;
    dc->width = rv_fb.width;
    dc->height = rv_fb.height;
    dc->width_internal = rv_fb.width;
    dc->is_scrn = TRUE;
    RVDCRst(dc);
    return TRUE;
  }
  Bool RVGrInit(I64 width = RV_FB_W_DEFAULT, I64 height = RV_FB_H_DEFAULT, U32 *pixels = NULL)
  {
    //Init FB + screen DC + soft terminal. Idempotent enough for smoke demos.
    // pixels=NULL ⇒ RV_FB_BASE_DEFAULT; boards may pass simplefb.base to draw into scanout.
    if (!RVFbInit(width, height, pixels))
      return FALSE;
    rv_gr.dc = &rv_scrn_dc;
    if (!RVDCScrnBind(rv_gr.dc))
      return FALSE;
    rv_gr.fp_draw_it = NULL;
    rv_term.cols = rv_fb.width / FONT_WIDTH;
    rv_term.rows = rv_fb.height / FONT_HEIGHT;
    if (rv_term.cols < 1)
      rv_term.cols = 1;
    if (rv_term.rows < 1)
      rv_term.rows = 1;
    rv_term.cur_r = 0;
    rv_term.cur_c = 0;
    rv_term.fg = RVColor(WHITE);
    rv_term.bg = RVColor(BLUE);
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
  Bool GrPlot(CRVDC *dc = NULL, I64 x, I64 y)
  {
    //2D plot. dc=NULL ⇒ screen DC. color is XRGB (use RVColor(idx) for 16-color).
    U32 *body;
    if (!dc)
      dc = rv_gr.dc;
    if (!dc || !dc->body)
      return FALSE;
    if (x < 0 || y < 0 || x >= dc->width || y >= dc->height)
      return FALSE;
    body = dc->body;
    body[y *dc->width_internal + x] = dc->color;
    return TRUE;
  }
  U0 GrRect(CRVDC *dc = NULL, I64 x, I64 y, I64 w, I64 h)
  {
    //Axis-aligned fill. Clipped.
    I64 xx, yy, x2, y2;
    U32 *body, c;
    if (!dc)
      dc = rv_gr.dc;
    if (!dc || !dc->body || w <= 0 || h <= 0)
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
    body = dc->body;
    c = dc->color;
    for (yy = y; yy < y2; yy++)
      for (xx = x; xx < x2; xx++)
        body[yy *dc->width_internal + xx] = c;
  }
  U0 GrLine(CRVDC *dc = NULL, I64 x1, I64 y1, I64 x2, I64 y2)
  {
    //Bresenham. Uses dc->thick as a square brush radius (1 = single pixel).
    I64 dx, dy, sx, sy, err, e2, x, y, t, i, j;
    if (!dc)
      dc = rv_gr.dc;
    if (!dc || !dc->body)
      return;
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
    while (TRUE) {
      if (t <= 1)
        GrPlot(dc, x, y);
      else {
        for (j = -(t >> 1); j <= (t >> 1); j++)
          for (i = -(t >> 1); i <= (t >> 1); i++)
            GrPlot(dc, x + i, y + j);
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
    }
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
        if (bits & (0x80 >> col))
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
