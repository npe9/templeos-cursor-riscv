// RVDocText.HC — render a DolDoc document DIRECTLY to text (ANSI), no cell grid.
//
// RVDocVT.HC presents rv_winmgr.text_base: RVWinMgr composites every window into one U32 grid
// and that file turns the grid into escapes. This file takes the other road the plan asks for:
// walk a doc's own entry stream and emit escapes for it, with the window manager reduced to
// TILING (it says which rectangle a doc owns; it does not compose pixels or cells).
//
// Why that is cheap here: DocRecalc has already done the hard part. It lays every entry out and
// writes the results BACK into the entry — `doc_e->x`, `doc_e->y`, and the resolved colour baked
// into `doc_e->type` bits 8-15 (RVDoc.HC:3708). State entries ($FG,$BG,$ID…) are consumed by
// the layout and emit nothing. So rendering is: recalc, walk the ring, place, paint.
//
// Bandwidth still matters on a 115200 line, so the renderer keeps the discipline the grid
// presenter earned: it paints into a per-tile shadow, diffs against what the terminal is already
// showing, emits a cursor address only when a run breaks and an SGR only when the attribute
// changes. An unchanged re-render costs 0 bytes.
//
// Needs Kernel/RVDocVT.HC first for the wire primitives (RVVtGoto/RVVtSgr/RVVtPutGlyph/
// RVVtFlush/rv_vt_cost) — those are attribute-based and grid-independent; only RVVtPresent and
// rv_vt_shadow are tied to the grid.
#ifndef RV_DOC_TEXT_HC
#define RV_DOC_TEXT_HC
#help_index "DolDoc/VT"

#define RV_DT_CELLS 2048
// 80x25 is 2000
#define RV_DT_ROWS_MAX 64
#define RV_DT_COLS_MAX 200
#define RV_DT_TILES 4
// each tile keeps its OWN shadow: one shared shadow would be invalidated by every switch
// between tiles of different geometry, so a multi-pane view would repaint in full every time

U32 rv_dt_cell[RV_DT_CELLS];
// what this render wants on screen
U32 rv_dt_shadow[RV_DT_TILES * RV_DT_CELLS];
// per tile: what the terminal is already showing
I64 rv_dt_trow[RV_DT_TILES], rv_dt_tcol[RV_DT_TILES], rv_dt_trows[RV_DT_TILES],
    rv_dt_tcols[RV_DT_TILES], rv_dt_tused[RV_DT_TILES];
I64 rv_dt_rows, rv_dt_cols, rv_dt_bytes;

// Which shadow belongs to this rectangle? Same origin+size = same tile. A new rectangle takes a
// free slot, or evicts slot 0 (and repaints in full, which is correct for a slot it never saw).
I64 RVDocTextTile(I64 row0, I64 col0, I64 rows, I64 cols, I64 *fresh)
{
  I64 i, free_i = -1;
  *fresh = 0;
  for (i = 0; i < RV_DT_TILES; i++) {
    if (rv_dt_tused[i] && rv_dt_trow[i] == row0 && rv_dt_tcol[i] == col0 &&
        rv_dt_trows[i] == rows && rv_dt_tcols[i] == cols)
      return i;
    if (!rv_dt_tused[i] && free_i < 0)
      free_i = i;
  }
  if (free_i < 0)
    free_i = 0;
  rv_dt_tused[free_i] = 1;
  rv_dt_trow[free_i] = row0;
  rv_dt_tcol[free_i] = col0;
  rv_dt_trows[free_i] = rows;
  rv_dt_tcols[free_i] = cols;
  *fresh = 1;
  return free_i;
}

// RVDocTextInvalidate -- RVDocTextInvalidate()
// NAME
//   RVDocTextInvalidate - forget what the terminal is showing (next render repaints in full)
// SEE ALSO
//   RVDocTextRender
U0 RVDocTextInvalidate()
{
  I64 i;
  for (i = 0; i < RV_DT_TILES; i++)
    rv_dt_tused[i] = 0;
}

U0 RVDocTextCellSet(I64 row, I64 col, I64 ch, I64 attr)
{
  I64 i;
  if (row < 0 || col < 0 || row >= rv_dt_rows || col >= rv_dt_cols)
    return;
  i = row * rv_dt_cols + col;
  if (i < 0 || i >= RV_DT_CELLS)
    return;
  rv_dt_cell[i] = (ch & 255) + ((attr & 255) << 8);
}

// Paint the doc's entries into the tile buffer. Mirrors RVDocDrawWin's walk (RVWinMgr.HC:1426)
// — same sentinel (doc_e != doc), same DOCEF_SKIP rule, same text-bearing types, same attr
// extraction — but writes cells for THIS tile instead of the global grid.
U0 RVDocTextFill(CDoc *doc, I64 sx, I64 sy, I64 dft_attr)
{
  CDocEntry *doc_e;
  U8 *tag;
  I64 t, x, y, i, attr, ch;
  if (!doc)
    return;
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->de_flags & DOCEF_SKIP) {
      doc_e = doc_e->next;
      continue;
    }
    t = doc_e->type_u8;
    if (t == DOCT_TEXT || t == DOCT_LINK || t == DOCT_TREE || t == DOCT_BTTN ||
        t == DOCT_DATA || t == DOCT_CHECK_BOX || t == DOCT_MACRO || t == DOCT_PMT ||
        t == DOCT_MENU_VAL || t == DOCT_LST) {
      tag = doc_e->tag;
      y = doc_e->y - sy;
      if (tag && y >= 0 && y < rv_dt_rows) {
        attr = (doc_e->type >> 8) & 255;
        if (!attr)
          attr = dft_attr;
        if (doc_e->type & ATTRF_INVERT)
          attr = ((attr & 0x0F) << 4) + ((attr >> 4) & 0x0F);
        x = doc_e->x - sx;
        i = 0;
        while (tag[i]) {
          ch = tag[i];
          RVDocTextCellSet(y, x, ch, attr);
          x++;
          i++;
        }
      }
    }
    doc_e = doc_e->next;
  }
}

// RVDocTextRender -- RVDocTextRender(doc, row0, col0, rows, cols)
// NAME
//   RVDocTextRender - render one DolDoc into a terminal rectangle, diffed
// SYNOPSIS
//   I64 RVDocTextRender(CDoc *doc, I64 row0, I64 col0, I64 rows, I64 cols,
//                       I64 sx = 0, I64 sy = 0, I64 dft_attr = 0x07);
// DESCRIPTION
//   Lays the doc out (DocRecalc), paints its entries into a tile, and sends only the cells that
//   differ from what the terminal is already showing. row0/col0 are 0-based and come from the
//   window manager's tiling — this function never asks where other windows are.
//   Returns the number of bytes written, so a test can assert that an idle re-render costs 0.
// EXAMPLES
//   RVDocTextRender(doc, 0, 0, 25, 80);        // full screen
//   RVDocTextRender(doc, 0, 40, 12, 40);       // right-hand tile
// SEE ALSO
//   RVDocTextInvalidate  RVVtGoto  RVVtSgr  DocRecalc
// BUGS
//   Text-bearing entries only so far: no border/scrollbar chrome, and the caret is the caller's
//   business (doc->cur_entry->x/y + doc->cur_col).
I64 RVDocTextRender(CDoc *doc, I64 row0, I64 col0, I64 rows, I64 cols,
                    I64 sx = 0, I64 sy = 0, I64 dft_attr = 0x07)
{
  I64 r, c, i, n, cur_attr = -1, run, start_bytes, tile, fresh, base;
  U32 cell;
  if (!doc || rows <= 0 || cols <= 0)
    return 0;
  if (rows > RV_DT_ROWS_MAX)
    rows = RV_DT_ROWS_MAX;
  if (cols > RV_DT_COLS_MAX)
    cols = RV_DT_COLS_MAX;
  n = rows * cols;
  if (n > RV_DT_CELLS)
    return 0;
  rv_dt_rows = rows;
  rv_dt_cols = cols;
  tile = RVDocTextTile(row0, col0, rows, cols, &fresh);
  base = tile * RV_DT_CELLS;
  i = 0;
  while (i < n) {
    rv_dt_cell[i] = ' ' + (dft_attr << 8);
    i++;
  }
  DocRecalc(doc);
  RVDocTextFill(doc, sx, sy, dft_attr);
  if (fresh) {
    i = 0;
    while (i < n) {
      rv_dt_shadow[base + i] = 0xFFFFFFFF;
      // nothing known about this tile yet: force a full paint
      i++;
    }
  }
  start_bytes = rv_vt_cost;
  r = 0;
  while (r < rows) {
    c = 0;
    run = 0;
    while (c < cols) {
      i = r * cols + c;
      cell = rv_dt_cell[i];
      if (cell == rv_dt_shadow[base + i]) {
        run = 0;
        c++;
        continue;
      }
      if (!run) {
        RVVtGoto(row0 + r, col0 + c);
        run = 1;
      }
      if (((cell >> 8) & 255) != cur_attr) {
        cur_attr = (cell >> 8) & 255;
        RVVtSgr(cur_attr & 15, (cur_attr >> 4) & 15, 0);
      }
      RVVtPutGlyph(cell & 255);
      rv_dt_shadow[base + i] = cell;
      c++;
    }
    r++;
  }
  RVVtFlush;
  rv_dt_bytes = rv_vt_cost - start_bytes;
  return rv_dt_bytes;
}

#endif
