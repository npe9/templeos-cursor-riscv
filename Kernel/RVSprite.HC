// Sprite blit subset for 32-bpp CRVDC (P4 widen toward Demo graphics apps).
// Mirrors Adam/Gr/GrSpritePlot.HC + SpriteNew.HC / Demo/Graphics/SpriteRaw.HC patterns,
// but plots via RVGr (GrPlot/Line/Rect/Circle/Blot/Gr3Mesh) — not VGA CDC / ScrnCast WinMgr.
// Index order matches SPT_END .. SPT_TEXT_DIAMOND (see Adam/Gr/Gr.HH; included from RVGr).
// Mesh: SPT_MESH / SPT_SHIFTABLE_MESH → Gr3Mesh (flat or DCF_TRANSFORM/SYMMETRY). Still deferred: bsplines;
// offscreen DCNew8 live body + FloodFill in RVGr; WinMgr default 32-bpp, opt-in ComposeEnable → is_u8.
// AOT glbl init of sizeof() arrays was untrustworthy (saw heap_next). Fill at first use.
// DocPut lives in RVWinMgr (included after this file) — forward for DocSpriteIns.
CDoc *DocPut(CTask *task = NULL);
I64 rv_sprite_elem_base_sizes[SPT_TYPES_NUM];
Bool rv_sprite_elem_sizes_ready = FALSE;
U0 RVSpriteElemSizesInit()
{
  if (rv_sprite_elem_sizes_ready)
    return;
  rv_sprite_elem_base_sizes[SPT_END] = sizeof(CSpriteBase);
  rv_sprite_elem_base_sizes[SPT_COLOR] = sizeof(CSpriteColor);
  rv_sprite_elem_base_sizes[SPT_DITHER_COLOR] = sizeof(CSpriteDitherColor);
  rv_sprite_elem_base_sizes[SPT_THICK] = sizeof(CSpriteT);
  rv_sprite_elem_base_sizes[SPT_PLANAR_SYMMETRY] = sizeof(CSpritePtPt);
  rv_sprite_elem_base_sizes[SPT_TRANSFORM_ON] = sizeof(CSpriteBase);
  rv_sprite_elem_base_sizes[SPT_TRANSFORM_OFF] = sizeof(CSpriteBase);
  rv_sprite_elem_base_sizes[SPT_SHIFT] = sizeof(CSpritePt);
  rv_sprite_elem_base_sizes[SPT_PT] = sizeof(CSpritePt);
  rv_sprite_elem_base_sizes[SPT_POLYPT] = sizeof(CSpriteNumPtU8s);
  rv_sprite_elem_base_sizes[SPT_LINE] = sizeof(CSpritePtPt);
  rv_sprite_elem_base_sizes[SPT_POLYLINE] = sizeof(CSpriteNumU8s);
  rv_sprite_elem_base_sizes[SPT_RECT] = sizeof(CSpritePtPt);
  rv_sprite_elem_base_sizes[SPT_ROTATED_RECT] = sizeof(CSpritePtPtAng);
  rv_sprite_elem_base_sizes[SPT_CIRCLE] = sizeof(CSpritePtRad);
  rv_sprite_elem_base_sizes[SPT_ELLIPSE] = sizeof(CSpritePtWHAng);
  rv_sprite_elem_base_sizes[SPT_POLYGON] = sizeof(CSpritePtWHAngSides);
  rv_sprite_elem_base_sizes[SPT_BSPLINE2] = sizeof(CSpriteNumU8s);
  rv_sprite_elem_base_sizes[SPT_BSPLINE2_CLOSED] = sizeof(CSpriteNumU8s);
  rv_sprite_elem_base_sizes[SPT_BSPLINE3] = sizeof(CSpriteNumU8s);
  rv_sprite_elem_base_sizes[SPT_BSPLINE3_CLOSED] = sizeof(CSpriteNumU8s);
  rv_sprite_elem_base_sizes[SPT_FLOOD_FILL] = sizeof(CSpritePt);
  rv_sprite_elem_base_sizes[SPT_FLOOD_FILL_NOT] = sizeof(CSpritePt);
  rv_sprite_elem_base_sizes[SPT_BITMAP] = sizeof(CSpritePtWHU8s);
  rv_sprite_elem_base_sizes[SPT_MESH] = sizeof(CSpriteMeshU8s);
  rv_sprite_elem_base_sizes[SPT_SHIFTABLE_MESH] = sizeof(CSpritePtMeshU8s);
  rv_sprite_elem_base_sizes[SPT_ARROW] = sizeof(CSpritePtPt);
  rv_sprite_elem_base_sizes[SPT_TEXT] = sizeof(CSpritePtStr);
  rv_sprite_elem_base_sizes[SPT_TEXT_BOX] = sizeof(CSpritePtStr);
  rv_sprite_elem_base_sizes[SPT_TEXT_DIAMOND] = sizeof(CSpritePtStr);
  rv_sprite_elem_sizes_ready = TRUE;
}

I64 SpriteElemSize(CSprite *tmpg)
{
  //Adam/Gr/SpriteNew.HC SpriteElemSize — size walk for binary sprite streams.
  I64 i, t;
  RVSpriteElemSizesInit;
  if (!tmpg)
    return rv_sprite_elem_base_sizes[SPT_END];
  t = tmpg->type & SPG_TYPE_MASK;
  if (t < 0 || t >= SPT_TYPES_NUM)
    return rv_sprite_elem_base_sizes[SPT_END];
  i = rv_sprite_elem_base_sizes[t];
  switch (t) {
    case SPT_POLYLINE :
    i += tmpg->nu.num *sizeof(I32) * 2;
    break;
    case SPT_TEXT :
    case SPT_TEXT_BOX :
    case SPT_TEXT_DIAMOND :
    i += StrLen(tmpg->ps.st) + 1;
    break;
    case SPT_BITMAP :
    i += (tmpg->pwhu.width + 7 & ~7) * tmpg->pwhu.height;
    break;
    case SPT_POLYPT :
    i += (tmpg->npu.num * 3 + 7) >> 3;
    break;
    case SPT_BSPLINE2 :
    case SPT_BSPLINE3 :
    case SPT_BSPLINE2_CLOSED :
    case SPT_BSPLINE3_CLOSED :
    i += tmpg->nu.num * 12;
    break;
    case SPT_MESH :
    i += tmpg->mu.vertex_cnt * 12 + tmpg->mu.tri_cnt *sizeof(CMeshTri);
    break;
    case SPT_SHIFTABLE_MESH :
    i += tmpg->pmu.vertex_cnt * 12 + tmpg->pmu.tri_cnt *sizeof(CMeshTri);
    break;
  }
  return i;
}

I64 SpriteSize(U8 *elems)
{
  CSprite *tmpg, *tmpg1;
  I64 n = 0, sz;
  if (!elems)
    return 0;
  RVSpriteElemSizesInit;
  tmpg = elems(U8 *) - offset(CSprite.start);
  tmpg1 = tmpg;
  while (tmpg->type & SPG_TYPE_MASK) {
    n++;
    if (n > 4096)
      return 0;
    sz = SpriteElemSize(tmpg);
    if (sz < 1 || sz > 0x100000)
      return 0;
    tmpg(U8 *) += sz;
  }
  return tmpg(U8 *) - tmpg1(U8 *) + rv_sprite_elem_base_sizes[SPT_END];
}

U0 RVSpriteBlotBitmap(CRVDC *dc, I64 x, I64 y, I64 w, I64 h, U8 *body, I64 width_internal)
{
  //8-bit palette SPT_BITMAP → GrPlot with RVColor (TempleOS TRANSPARENT key).
  I64 ix, iy, dx, dy;
  U8 c;
  U32 saved;
  if (!dc || !body || w < 1 || h < 1)
    return;
  saved = dc->color;
  for (iy = 0; iy < h; iy++) {
    dy = y + iy;
    for (ix = 0; ix < w; ix++) {
      dx = x + ix;
      c = body[iy *width_internal + ix];
      if (c == TRANSPARENT)
        continue;
      dc->color = RVColor(c);
      GrPlot(dc, dx, dy);
    }
  }
  dc->color = saved;
}

U0 Sprite3(CRVDC *dc = NULL, I64 x, I64 y, I64 z, U8 *elems, Bool just_one_elem = FALSE)
{
  //Subset of Adam Sprite3: COLOR/THICK/SHIFT/PT/LINE/ARROW/RECT/CIRCLE/FLOOD/TEXT/BITMAP/MESH.
  // Skips transforms, bsplines, dither (lighting/symmetry later).
  CSprite *tmpg;
  I64 i, x1, y1, x2, y2, z1, *ptr, n_el, sz;
  U32 old_color, fill_color;
  I64 old_thick, old_flags, t;
  CD3I32 *p, *p2;
  if (!dc)
    dc = rv_gr.dc;
  if (!dc || !elems)
    return;
  RVSpriteElemSizesInit;
  tmpg = elems(U8 *) - offset(CSprite.start);
  old_color = dc->color;
  old_thick = dc->thick;
  old_flags = dc->flags;
  n_el = 0;
  while (tmpg->type & SPG_TYPE_MASK) {
    t = tmpg->type & SPG_TYPE_MASK;
    n_el++;
    if (n_el > 512)
      break;
    switch (t) {
      case SPT_COLOR :
      dc->color = RVColor(tmpg->c.color);
      break;
      case SPT_THICK :
      dc->thick = tmpg->t.thick;
      if (dc->thick < 1)
        dc->thick = 1;
      if (dc->thick > 64)
        dc->thick = 64;
      break;
      case SPT_SHIFT :
      x += tmpg->p.x1;
      y += tmpg->p.y1;
      break;
      case SPT_PT :
      GrPlot(dc, tmpg->p.x1 + x, tmpg->p.y1 + y);
      break;
      case SPT_LINE :
      case SPT_ARROW :
      x1 = tmpg->pp.x1 + x;
      y1 = tmpg->pp.y1 + y;
      x2 = tmpg->pp.x2 + x;
      y2 = tmpg->pp.y2 + y;
      if (x1 < -4096 || y1 < -4096 || x2 < -4096 || y2 < -4096 || x1 > 8192 || y1 > 8192 || x2 > 8192 || y2 > 8192)
        break;
      GrLine(dc, x1, y1, x2, y2);
      break;
      case SPT_RECT :
      x1 = tmpg->pp.x1 + x;
      y1 = tmpg->pp.y1 + y;
      x2 = tmpg->pp.x2 + x;
      y2 = tmpg->pp.y2 + y;
      if (x2 < x1) {
        i = x1;
        x1 = x2;
        x2 = i;
      }
      if (y2 < y1) {
        i = y1;
        y1 = y2;
        y2 = i;
      }
      GrRect(dc, x1, y1, x2 - x1, y2 - y1);
      break;
      case SPT_CIRCLE :
      GrCircle(dc, tmpg->pr.x1 + x, tmpg->pr.y1 + y, tmpg->pr.radius);
      break;
      case SPT_FLOOD_FILL :
      case SPT_FLOOD_FILL_NOT :
      // Skip: full-scrn flood from $IB streams wedges DrawNote/PsmMenu under 32-bpp FB.
      break;
      case SPT_TEXT :
      case SPT_TEXT_BOX :
      case SPT_TEXT_DIAMOND :
      GrPrint(dc, tmpg->ps.x1 + x, tmpg->ps.y1 + y, tmpg->ps.st);
      break;
      case SPT_BITMAP :
      RVSpriteBlotBitmap(dc, tmpg->pwhu.x1 + x, tmpg->pwhu.y1 + y, tmpg->pwhu.width, tmpg->pwhu.height, &tmpg->pwhu.u, tmpg->pwhu.width + 7 & ~7);
      break;
      case SPT_POLYLINE :
      ptr = &tmpg->nu.u;
      if (tmpg->nu.num >= 1 && tmpg->nu.num < 4096) {
        x1 = ptr[0];
        y1 = ptr[1];
        for (i = 1; i < tmpg->nu.num; i++) {
          x2 = ptr[i << 1];
          y2 = ptr[i << 1 + 1];
          GrLine(dc, x1 + x, y1 + y, x2 + x, y2 + y);
          x1 = x2;
          y1 = y2;
        }
      }
      break;
      case SPT_MESH :
      if (tmpg->mu.vertex_cnt < 1 || tmpg->mu.vertex_cnt > 4096 || tmpg->mu.tri_cnt < 0 || tmpg->mu.tri_cnt > 8192)
        break;
      p2 = p = MAlloc(tmpg->mu.vertex_cnt *sizeof(CD3I32));
      if (!p)
        break;
      MemCpy(p, &tmpg->mu.u, tmpg->mu.vertex_cnt *sizeof(CD3I32));
      for (i = 0; i < tmpg->mu.vertex_cnt; i++, p2++) {
        p2->x += x;
        p2->y += y;
        p2->z += z;
      }
      Gr3Mesh(dc, tmpg->mu.vertex_cnt, p, tmpg->mu.tri_cnt, (&tmpg->mu.u)(U8 *) + sizeof(CD3I32) * tmpg->mu.vertex_cnt);
      Free(p);
      break;
      case SPT_SHIFTABLE_MESH :
      if (tmpg->pmu.vertex_cnt < 1 || tmpg->pmu.vertex_cnt > 4096 || tmpg->pmu.tri_cnt < 0 || tmpg->pmu.tri_cnt > 8192)
        break;
      x1 = tmpg->pmu.x + x;
      y1 = tmpg->pmu.y + y;
      z1 = tmpg->pmu.z + z;
      p2 = p = MAlloc(tmpg->pmu.vertex_cnt *sizeof(CD3I32));
      if (!p)
        break;
      MemCpy(p, &tmpg->pmu.u, tmpg->pmu.vertex_cnt *sizeof(CD3I32));
      for (i = 0; i < tmpg->pmu.vertex_cnt; i++, p2++) {
        p2->x += x1;
        p2->y += y1;
        p2->z += z1;
      }
      Gr3Mesh(dc, tmpg->pmu.vertex_cnt, p, tmpg->pmu.tri_cnt, (&tmpg->pmu.u)(U8 *) + sizeof(CD3I32) * tmpg->pmu.vertex_cnt);
      Free(p);
      break;
      case SPT_DITHER_COLOR :
      case SPT_PLANAR_SYMMETRY :
      case SPT_TRANSFORM_ON :
      case SPT_TRANSFORM_OFF :
      case SPT_POLYPT :
      case SPT_ROTATED_RECT :
      case SPT_ELLIPSE :
      case SPT_POLYGON :
      case SPT_BSPLINE2 :
      case SPT_BSPLINE2_CLOSED :
      case SPT_BSPLINE3 :
      case SPT_BSPLINE3_CLOSED :
      break;
    }
    if (just_one_elem)
      break;
    sz = SpriteElemSize(tmpg);
    if (sz < 1 || sz > 0x100000)
      break;
    tmpg(U8 *) += sz;
  }
  dc->color = old_color;
  dc->thick = old_thick;
  dc->flags = old_flags;
}

U8 *DC2Sprite(CRVDC *tmpb)
{
  //Adam DC2Sprite analogue — quantize 32-bpp CRVDC body to 8-bit SPT_BITMAP + END.
  CSprite *tmpg;
  I64 wi, x, y, n, idx;
  U8 *dst;
  U32 c;
  if (!tmpb || !tmpb->body)
    return NULL;
  wi = tmpb->width + 7 & ~7;
  n = rv_sprite_elem_base_sizes[SPT_BITMAP] + wi *tmpb->height + rv_sprite_elem_base_sizes[SPT_END];
  tmpg = CAlloc(n)(U8 *) - offset(CSprite.start);
  tmpg->type = SPT_BITMAP;
  tmpg->pwhu.width = tmpb->width;
  tmpg->pwhu.height = tmpb->height;
  tmpg->pwhu.x1 = 0;
  tmpg->pwhu.y1 = 0;
  dst = &tmpg->pwhu.u;
  for (y = 0; y < tmpb->height; y++)
    for (x = 0; x < tmpb->width; x++) {
      c = tmpb->body[y *tmpb->width_internal + x];
      idx = RVColorNearestIdx(c);
      dst[y *wi + x] = idx;
    }
  return tmpg(U8 *) + offset(CSprite.start);
}

U0 SpritePlot(U8 *elems)
{
  //Bare Gr plot at origin (no DocPut). PsmMenu uses Sprite→DocSpriteIns instead.
  if (!elems || !rv_gr.dc)
    return;
  Sprite3(rv_gr.dc, 0, 0, 0, elems);
}
