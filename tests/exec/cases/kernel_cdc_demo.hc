// P4 CDC widen: DCNew/GrBlot + FloodFill/brush + Sprite3 (Demo/Graphics/Blot + SpriteRaw).
// 32-bpp CRVDC body; UART hash oracle. Does not touch MassSpring / WinMgr compose.
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

I64 main()
{
  CRVDC *dc, *img, *brush;
  U8 *elems;
  RVDemoSprite s;
  I64 blot_n, h, ff_n;
  U32 sprite_peek;
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
  dc->color = RV_RGB(24, 32, 48);
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
  dc->color = RVColor(WHITE);
  GrPrint(dc, 40, 180, "FloodFill/brush/GrBlot");
  RVGrRefresh();
  h = RVFbHash() & 0xFFFFFFFF;
  Print("RVCDC smoke hash=0x%08X blot=%d ff=%d bw=%d bh=%d sprite=%d dc2=%d peek=0x%08X present=%d %dx%d\n", h, blot_n, ff_n, brush->width, brush->height, TRUE, elems != NULL, sprite_peek, rv_fb.present_ok, rv_fb.width, rv_fb.height);
  if (sprite_peek != RVColor(CYAN)) {
    Print("RVCDC smoke FAIL sprite flood peek=0x%08X\n", sprite_peek);
    if (elems)
      Free(elems);
    DCDel(img);
    DCDel(brush);
    DCDel(dc);
    return 1;
  }
  if (elems)
    Free(elems);
  DCDel(img);
  DCDel(brush);
  DCDel(dc);
  return 0;
}
