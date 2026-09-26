// P4 CDC widen: DCNew/GrBlot + FloodFill/brush + Sprite3 (Demo/Graphics/Blot + SpriteRaw).
// Libs-first: Gr3Mesh/GrFillTri0, DCCopy/DCDiff, GR-lite + CompressBuf .GR.Z, soft ScrnCast.
// Optional offscreen 8-bit live body (DCNew8 Plot/Blot/Peek/FloodFill) — FB/WinMgr stay 32-bpp (hash pin).
// Opt-in GrUpdateVGAGraphics expand (vgaok) + WinMgr present hook after hash — PINNED_HASH stays stable.
// WinMgr ScrnCast hook + just_audio AUWrite snd queue (auok) after FB hash.
// Opt-in full-screen WinMgr paint into is_u8 (wm8ok: text + draw_it) then expand — post-hash.
#include "/Kernel/Kernel_RV.PRJ"
// Hand-built sprite like Demo/Graphics/SpriteRaw.HC (triangle + SPT_FLOOD_FILL).
class RVDemoSprite
{
  CSpriteColor color;
  CSpritePtPt line1;
  CSpritePtPt line2;
  CSpritePtPt line3;
  CSpritePt fill;
  CSpriteColor color2;
  CSpritePtRad circ;
  CSpriteBase end;
};
// Minimal SPT_MESH: 3 verts + 1 tri (flat RED triangle).
class RVDemoMeshSprite
{
  CSpriteMeshU8s hdr;
  CD3I32 v0;
  CD3I32 v1;
  CD3I32 v2;
  CMeshTri tri;
  CSpriteBase end;
};

U0 RVWm8DrawIt(CRVWin *w, CRVDC *dc)
{
  //Smoke draw_it: solid CYAN blot at window client origin + (2,2).
  I64 x, y;
  if (!w || !dc)
    return;
  x = w->left *FONT_WIDTH + 2;
  y = w->top *FONT_HEIGHT + 2;
  dc->color = CYAN;
  GrRect(dc, x, y, 4, 4);
}

I64 main()
{
  CRVDC *dc, *img, *brush, *copy, *diff, *loaded, *dc8, *tmp32, *dc_vga;
  U8 *elems, *gr_blob, *grz_blob, *body8, *body8_live;
  CRVGRHdr *hdr;
  RVDemoSprite s;
  RVDemoMeshSprite ms;
  CD3I32 verts[4];
  CMeshTri tris[2];
  I64 blot_n, h, ff_n, mesh_n, cast_n, cast0, gr_sz, grz_sz, peek_ok, grz_ok, wmcast, ja_hits;
  I64 u8ok, blot8_n, ff8_n, wi8, vgaok, vga_n, stride, au_n, au_sz, auok;
  I64 wm8ok, wm8_idx, wm8_x, wm8_y, wm8_wi, wm8_dx, wm8_dy, gx, gy, saw_fg, saw_bg, c8;
  U8 *wm8_body;
  CRVWin *wm8_w;
  U32 sprite_peek, mesh_peek;
  CSndData *sd;
  RVKernelInit();
  if (!RVGrInit(800, 600)) {
    Print("RVCDC init FAIL\n");
    return 1;
  }
  dc = DCAlias;
  if (!dc) {
    Print("RVCDC DCAlias FAIL\n");
    return 1;
  }
  // Demo/Graphics/Blot.HC brush template: COLOR_MONO circle + FloodFill3 + GrLine3.
  brush = DCNew(64, 64);
  if (!brush) {
    Print("RVCDC brush DCNew FAIL\n");
    DCDel(dc);
    return 1;
  }
  DCFill(brush, 0);
  brush->color = COLOR_MONO;
  brush->thick = 3;
  GrCircle(brush, 30, 30, 20);
  ff_n = GrFloodFill3(brush, 30, 30, 0, TRUE);
  GrLine3(brush, 60, 0, 0, 0, 60, 0);
  // Blot pattern: stamp brush along a stepped circle, then thick lines.
  img = DCNew(128, 128);
  if (!img) {
    Print("RVCDC img DCNew FAIL\n");
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  DCFill(img, 0);
  img->color = RED;
  img->brush = brush;
  GrCircle(img, 64, 64, 40, 17);
  img->color = BLUE;
  img->thick = 4;
  img->brush = NULL;
  GrLine3(img, 16, 16, 0, 112, 112, 0);
  GrLine3(img, 112, 16, 0, 16, 112, 0);
  img->color = YELLOW;
  GrRect(img, 54, 54, 20, 20);
  //A pen is a palette INDEX (stock). This was RV_RGB(24,32,48) = 0x182030, and since phase 2 its
  //low byte WAS already being read as an index — 0x30 = 48, 48 & 15 = 0 — so this 800x600 fill
  //has been painting BLACK accidentally. BLACK is also the nearest palette colour to 0x182030
  //(distance 3904 vs 7899 to DKGRAY), so saying it outright changes no pixel, only the source.
  dc->color = BLACK;
  GrRect(dc, 0, 0, 800, 600);
  blot_n = GrBlot(dc, 40, 40, img);
  // SpriteRaw triangle + flood + circle (COLOR/LINE/FLOOD_FILL/CIRCLE/END).
  MemSet(&s, 0, sizeof(s));
  s.color.type = SPT_COLOR;
  s.color.color = CYAN;
  s.line1.type = SPT_LINE;
  s.line1.x2 = 100;
  s.line1.y2 = 50;
  s.line2.type = SPT_LINE;
  s.line2.x2 = 50;
  s.line2.y2 = 100;
  s.line3.type = SPT_LINE;
  s.line3.x1 = 100;
  s.line3.y1 = 50;
  s.line3.x2 = 50;
  s.line3.y2 = 100;
  s.fill.type = SPT_FLOOD_FILL;
  s.fill.x1 = 20;
  s.fill.y1 = 20;
  s.color2.type = SPT_COLOR;
  s.color2.color = WHITE;
  s.circ.type = SPT_CIRCLE;
  s.circ.x1 = 50;
  s.circ.y1 = 45;
  s.circ.radius = 18;
  s.end.type = SPT_END;
  Sprite3(dc, 200, 80, 0, &s.color);
  // Prove SPT_FLOOD_FILL painted triangle interior (SpriteRaw seed-match path).
  sprite_peek = GrPeek(dc, 220, 100);
  // DC2Sprite roundtrip: quantize brush → SPT_BITMAP → Sprite3.
  elems = DC2Sprite(brush);
  if (elems)
    Sprite3(dc, 360, 40, 0, elems);
  // Flat mesh: two tris making a quad (Gr3Mesh) + SPT_MESH sprite.
  verts[0].x = 520;
  verts[0].y = 80;
  verts[0].z = 0;
  verts[1].x = 620;
  verts[1].y = 80;
  verts[1].z = 0;
  verts[2].x = 620;
  verts[2].y = 160;
  verts[2].z = 0;
  verts[3].x = 520;
  verts[3].y = 160;
  verts[3].z = 0;
  tris[0].color = RED;
  tris[0].nums[0] = 0;
  tris[0].nums[1] = 1;
  tris[0].nums[2] = 2;
  tris[1].color = LTRED;
  tris[1].nums[0] = 0;
  tris[1].nums[1] = 2;
  tris[1].nums[2] = 3;
  mesh_n = Gr3Mesh(dc, 4, verts, 2, tris);
  MemSet(&ms, 0, sizeof(ms));
  ms.hdr.type = SPT_MESH;
  ms.hdr.vertex_cnt = 3;
  ms.hdr.tri_cnt = 1;
  ms.v0.x = 0;
  ms.v0.y = 0;
  ms.v0.z = 0;
  ms.v1.x = 80;
  ms.v1.y = 0;
  ms.v1.z = 0;
  ms.v2.x = 40;
  ms.v2.y = 70;
  ms.v2.z = 0;
  ms.tri.color = GREEN;
  ms.tri.nums[0] = 0;
  ms.tri.nums[1] = 1;
  ms.tri.nums[2] = 2;
  ms.end.type = SPT_END;
  Sprite3(dc, 520, 200, 0, &ms.hdr);
  mesh_peek = GrPeek(dc, 560, 230);
  // Soft ScrnCast: base snapshot → paint → DCDiff frame → identical frame = 0.
  ScrnCastStart(dc);
  dc->color = WHITE;
  GrRect(dc, 10, 500, 40, 30);
  cast_n = ScrnCastFrame(dc);
  cast0 = ScrnCastFrame(dc);
  ScrnCastStop;
  // 8-bit GR-lite roundtrip (in-mem DCSave/DCLoad; FileWrite path is GRWrite).
  copy = DCCopy(img);
  body8 = DCBody8(img);
  gr_blob = DCSave(img, &gr_sz, 0);
  loaded = NULL;
  if (gr_blob)
    loaded = DCLoad(gr_blob);
  peek_ok = 0;
  if (loaded) {
    if (GrPeek(loaded, 64, 64) == GrPeek(img, 64, 64))
      peek_ok = 1;
    DCDel(loaded);
  }
  // CompressBuf .GR.Z roundtrip (DCSF_COMPRESSED → CArcCompress body).
  grz_blob = DCSave(img, &grz_sz, DCSF_COMPRESSED);
  grz_ok = 0;
  loaded = NULL;
  if (grz_blob) {
    hdr = grz_blob(CRVGRHdr *);
    if (hdr->flags & DCF_COMPRESSED)
      loaded = DCLoad(grz_blob);
  }
  if (loaded) {
    if (GrPeek(loaded, 64, 64) == GrPeek(img, 64, 64) && grz_sz > 0)
      grz_ok = 1;
    DCDel(loaded);
  }
  diff = NULL;
  if (copy) {
    copy->body[20 * copy->width_internal + 20] = RVColor(WHITE);
    diff = DCDiff(img, copy);
  }
  // Optional 8-bit live draw body (offscreen): Plot/Rect/Line/FloodFill → Peek + Blot expand + DCBody8.
  // Does not touch screen FB — hash pin stays stable (see run_kernel_cdc_smoke.sh PINNED_HASH).
  u8ok = 0;
  blot8_n = 0;
  ff8_n = 0;
  body8_live = NULL;
  dc8 = DCNew8(48, 48);
  tmp32 = DCNew(48, 48);
  if (dc8 && tmp32 && dc8->is_u8) {
    DCFill(dc8, 0);
    dc8->color = RED;
    GrPlot(dc8, 5, 5);
    GrRect(dc8, 10, 10, 16, 16);
    dc8->color = BLUE;
    GrLine(dc8, 0, 47, 47, 0);
    // FloodFill inside a thick circle (Blot.HC not_color shape on palette body).
    dc8->color = GREEN;
    dc8->thick = 2;
    GrCircle(dc8, 36, 12, 8);
    ff8_n = GrFloodFill3(dc8, 36, 12, 0, TRUE);
    wi8 = dc8->width_internal;
    body8_live = DCBody8(dc8);
    DCFill(tmp32, 0);
    blot8_n = GrBlot(tmp32, 0, 0, dc8);
    // STOCK: GrPeek returns a palette INDEX from an 8-bit DC (Adam/Gr/GrBitMap.HC:64) and the
    // 32-bpp pixel from a 32-bpp one. This line used to expect RVColor(RED) from dc8 — the
    // port's old XRGB-from-an-8-bit-DC behaviour — while ALREADY checking the raw body byte
    // against the bare index two terms later. tmp32 is 32-bpp, so those keep RVColor().
    if (GrPeek(dc8, 5, 5) == RED && GrPeek(dc8, 12, 12) == RED && GrPeek(dc8, 24, 23) == BLUE && ff8_n > 0 && GrPeek(dc8, 36, 12) == GREEN && body8_live && body8_live[5 * wi8 + 5] == RED && body8_live[12 * wi8 + 36] == GREEN && blot8_n > 0 && GrPeek(tmp32, 5, 5) == RVColor(RED) && GrPeek(tmp32, 12, 12) == RVColor(RED) && GrPeek(tmp32, 36, 12) == RVColor(GREEN))
      u8ok = 1;
  }
  dc->color = WHITE;
  GrPrint(dc, 40, 180, "FloodFill/brush/GrBlot/mesh/ScrnCast");
  RVGrRefresh();
  h = RVFbHash() & 0xFFFFFFFF;
  // Opt-in GrUpdateVGAGraphics: 8-bit backbuffer expand → compose on present (after hash).
  vgaok = 0;
  vga_n = 0;
  dc_vga = DCNew8(16, 16);
  if (dc_vga && rv_fb.pixels) {
    DCFill(dc_vga, BLACK);
    dc_vga->color = YELLOW;
    GrRect(dc_vga, 2, 2, 8, 8);
    dc_vga->color = CYAN;
    GrPlot(dc_vga, 0, 0);
    if (RVGrU8ComposeBind(dc_vga)) {
      RVWinMgrPresent(FALSE);
      stride = RVFbPixStride;
      vga_n = 16 * 16;
      if (rv_fb.pixels[0] == RVColor(CYAN) && rv_fb.pixels[2 * stride + 2] == RVColor(YELLOW) && rv_fb.pixels[5 * stride + 5] == RVColor(YELLOW) && rv_gr_u8_present)
        vgaok = 1;
      RVGrU8ComposeUnbind;
    }
    DCDel(dc_vga);
    dc_vga = NULL;
  }
  // WinMgr compose ScrnCast hook — after hash so PINNED_HASH stays stable.
  wmcast = 0;
  ja_hits = -1;
  au_n = 0;
  au_sz = 0;
  auok = 0;
  if (RVWinMgrInit()) {
    rv_scrncast_winmgr_hits = 0;
    ScrnCastStart(rv_gr.dc);
    RVWinMgrRefresh;
    RVWinMgrRefresh;
    wmcast = rv_scrncast_winmgr_hits;
    ScrnCastStop;
    // just_audio must not bump video frame hits.
    ja_hits = rv_scrncast_winmgr_hits;
    scrncast.record = TRUE;
    scrncast.just_audio = TRUE;
    RVWinMgrRefresh;
    ja_hits = rv_scrncast_winmgr_hits - ja_hits;
    scrncast.record = FALSE;
    scrncast.just_audio = FALSE;
    // just_audio snd queue → AUWrite (libs-first; no .AU FileWrite required).
    ScrnCastStart(NULL, TRUE);
    Snd(51);
    Snd(0);
    au_n = QueCnt(&scrncast.snd_head);
    sd = scrncast.snd_head.next;
    au_sz = AUWrite(NULL, &scrncast.snd_head, &scrncast.t0_now, scrncast.t0_tS);
    if (au_n == 2 && sd != &scrncast.snd_head && sd->ona == 51 && sd->next != &scrncast.snd_head && sd->next->ona == 0 && au_sz == (1 + au_n) * sizeof(CAUData) && wmcast >= 1 && ja_hits == 0)
      auok = 1;
    ScrnCastStop;
    QueDel(&scrncast.snd_head, TRUE);
    // Opt-in full-screen WinMgr draw into is_u8 (text + draw_it) then expand — post-hash.
    wm8ok = 0;
    wm8_idx = -1;
    if (RVGrU8ComposeEnable) {
      wm8_idx = RVWinNew(20, 40, 20, 35, "Wm8", "u8", FALSE);
      if (wm8_idx >= 0) {
        wm8_w = &rv_winmgr.wins[wm8_idx];
        wm8_w->draw_it = &RVWm8DrawIt;
        rv_winmgr.gr_idx = wm8_idx;
      }
      RVWinMgrRefresh;
      if (rv_gr_dc_u8 && rv_gr_dc_u8->is_u8 && rv_gr_dc_u8->body && RVGrU8ComposeActive) {
        wm8_body = rv_gr_dc_u8->body(U8 *);
        wm8_wi = rv_gr_dc_u8->width_internal;
        stride = RVFbPixStride;
        // Wallpaper TextPrint(1,0) BLUE<<4+YELLOW — scan cell for palette FG/BG.
        wm8_x = 1 * FONT_WIDTH;
        wm8_y = 0;
        saw_fg = 0;
        saw_bg = 0;
        for (gy = 0; gy < FONT_HEIGHT; gy++) {
          for (gx = 0; gx < FONT_WIDTH; gx++) {
            c8 = wm8_body[(wm8_y + gy) * wm8_wi + wm8_x + gx];
            if (c8 == YELLOW)
              saw_fg = 1;
            if (c8 == BLUE)
              saw_bg = 1;
          }
        }
        // draw_it CYAN rect at window (20,20) client + (2,2)
        wm8_dx = 20 * FONT_WIDTH + 2;
        wm8_dy = 20 * FONT_HEIGHT + 2;
        if (saw_fg && saw_bg && wm8_body[wm8_dy *wm8_wi + wm8_dx] == CYAN && rv_fb.pixels[wm8_y *stride + wm8_x] == RVColor(wm8_body[wm8_y *wm8_wi + wm8_x]) && rv_fb.pixels[wm8_dy *stride + wm8_dx] == RVColor(CYAN))
          wm8ok = 1;
      }
      if (wm8_idx >= 0) {
        rv_winmgr.wins[wm8_idx].draw_it = NULL;
        rv_winmgr.wins[wm8_idx].show = FALSE;
        rv_winmgr.wins[wm8_idx].used = FALSE;
      }
      RVGrU8ComposeDisable;
    }
  } else {
    wm8ok = 0;
  }
  Print("RVCDC smoke hash=0x%08X blot=%d ff=%d bw=%d bh=%d sprite=%d dc2=%d peek=0x%08X mesh=%d mpeek=0x%08X cast=%d cast0=%d gr=%d body8=%d diff=%d peek8=%d grz=%d grzok=%d wmcast=%d ja=%d u8ok=%d blot8=%d ff8=%d vgaok=%d vga_n=%d auok=%d au_n=%d au_sz=%d wm8ok=%d present=%d %dx%d\n", h, blot_n, ff_n, brush->width, brush->height, TRUE, elems != NULL, sprite_peek, mesh_n, mesh_peek, cast_n, cast0, gr_sz, body8 != NULL, diff != NULL, peek_ok, grz_sz, grz_ok, wmcast, ja_hits, u8ok, blot8_n, ff8_n, vgaok, vga_n, auok, au_n, au_sz, wm8ok, rv_fb.present_ok, rv_fb.width, rv_fb.height);
  if (sprite_peek != RVColor(CYAN)) {
    Print("RVCDC smoke FAIL sprite flood peek=0x%08X\n", sprite_peek);
    if (elems)
      Free(elems);
    if (body8)
      Free(body8);
    if (body8_live)
      Free(body8_live);
    if (gr_blob)
      Free(gr_blob);
    if (grz_blob)
      Free(grz_blob);
    if (diff)
      DCDel(diff);
    if (copy)
      DCDel(copy);
    if (tmp32)
      DCDel(tmp32);
    if (dc8)
      DCDel(dc8);
    DCDel(img);
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  if (mesh_n < 1 || mesh_peek != RVColor(GREEN)) {
    Print("RVCDC smoke FAIL mesh n=%d peek=0x%08X\n", mesh_n, mesh_peek);
    if (elems)
      Free(elems);
    if (body8)
      Free(body8);
    if (body8_live)
      Free(body8_live);
    if (gr_blob)
      Free(gr_blob);
    if (grz_blob)
      Free(grz_blob);
    if (diff)
      DCDel(diff);
    if (copy)
      DCDel(copy);
    if (tmp32)
      DCDel(tmp32);
    if (dc8)
      DCDel(dc8);
    DCDel(img);
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  if (cast_n < 1 || cast0 != 0 || !body8 || !gr_blob || gr_sz < 1 || !diff || !peek_ok || !grz_ok) {
    Print("RVCDC smoke FAIL cast=%d cast0=%d body8=%d gr=%d diff=%d peek8=%d grz=%d grzok=%d\n", cast_n, cast0, body8 != NULL, gr_sz, diff != NULL, peek_ok, grz_sz, grz_ok);
    if (elems)
      Free(elems);
    if (body8)
      Free(body8);
    if (body8_live)
      Free(body8_live);
    if (gr_blob)
      Free(gr_blob);
    if (grz_blob)
      Free(grz_blob);
    if (diff)
      DCDel(diff);
    if (copy)
      DCDel(copy);
    if (tmp32)
      DCDel(tmp32);
    if (dc8)
      DCDel(dc8);
    DCDel(img);
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  if (wmcast < 1 || ja_hits != 0) {
    Print("RVCDC smoke FAIL wmcast=%d ja=%d (WinMgr ScrnCast hook)\n", wmcast, ja_hits);
    if (elems)
      Free(elems);
    if (body8)
      Free(body8);
    if (body8_live)
      Free(body8_live);
    if (gr_blob)
      Free(gr_blob);
    if (grz_blob)
      Free(grz_blob);
    if (diff)
      DCDel(diff);
    if (copy)
      DCDel(copy);
    if (tmp32)
      DCDel(tmp32);
    if (dc8)
      DCDel(dc8);
    DCDel(img);
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  if (!u8ok) {
    Print("RVCDC smoke FAIL u8ok=%d blot8=%d ff8=%d (8-bit live body + FloodFill)\n", u8ok, blot8_n, ff8_n);
    if (elems)
      Free(elems);
    if (body8)
      Free(body8);
    if (body8_live)
      Free(body8_live);
    if (gr_blob)
      Free(gr_blob);
    if (grz_blob)
      Free(grz_blob);
    if (diff)
      DCDel(diff);
    if (copy)
      DCDel(copy);
    if (tmp32)
      DCDel(tmp32);
    if (dc8)
      DCDel(dc8);
    DCDel(img);
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  if (!vgaok) {
    Print("RVCDC smoke FAIL vgaok=%d vga_n=%d (GrUpdateVGAGraphics 8-bit expand present)\n", vgaok, vga_n);
    if (elems)
      Free(elems);
    if (body8)
      Free(body8);
    if (body8_live)
      Free(body8_live);
    if (gr_blob)
      Free(gr_blob);
    if (grz_blob)
      Free(grz_blob);
    if (diff)
      DCDel(diff);
    if (copy)
      DCDel(copy);
    if (tmp32)
      DCDel(tmp32);
    if (dc8)
      DCDel(dc8);
    DCDel(img);
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  if (!auok) {
    Print("RVCDC smoke FAIL auok=%d au_n=%d au_sz=%d (just_audio snd queue/AUWrite)\n", auok, au_n, au_sz);
    if (elems)
      Free(elems);
    if (body8)
      Free(body8);
    if (body8_live)
      Free(body8_live);
    if (gr_blob)
      Free(gr_blob);
    if (grz_blob)
      Free(grz_blob);
    if (diff)
      DCDel(diff);
    if (copy)
      DCDel(copy);
    if (tmp32)
      DCDel(tmp32);
    if (dc8)
      DCDel(dc8);
    DCDel(img);
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  if (!wm8ok) {
    Print("RVCDC smoke FAIL wm8ok=%d (WinMgr text/draw_it into is_u8 + expand)\n", wm8ok);
    if (elems)
      Free(elems);
    if (body8)
      Free(body8);
    if (body8_live)
      Free(body8_live);
    if (gr_blob)
      Free(gr_blob);
    if (grz_blob)
      Free(grz_blob);
    if (diff)
      DCDel(diff);
    if (copy)
      DCDel(copy);
    if (tmp32)
      DCDel(tmp32);
    if (dc8)
      DCDel(dc8);
    DCDel(img);
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  if (elems)
    Free(elems);
  if (body8)
    Free(body8);
  if (body8_live)
    Free(body8_live);
  if (gr_blob)
    Free(gr_blob);
  if (grz_blob)
    Free(grz_blob);
  if (diff)
    DCDel(diff);
  if (copy)
    DCDel(copy);
  if (tmp32)
    DCDel(tmp32);
  if (dc8)
    DCDel(dc8);
  DCDel(img);
  DCDel(brush);
  DCDel(dc);
  return 0;
}
