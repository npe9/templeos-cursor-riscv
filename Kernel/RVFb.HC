// Native RISC-V linear framebuffer (Phase 0–1). Not VGA.
//
// Double-buffer (TempleOS gr.dc2 → scanout shape): Gr/WinMgr paint into a compose
// buffer (`rv_fb.pixels`); `RVFbPresent` MemCpy-flips to `rv_fb.scanout` then
// pushes the scanout to the backend. Mid-frame wallpaper/text blits stay invisible
// to cocoa/SDL ramfb (which maps guest scanout RAM directly).
//
// Present backends:
//   - QEMU virt: fw_cfg DMA + `-device ramfb` (see tests/scripts/run_kernel_fb_smoke.sh)
//   - Boards: simplefb DT / firmware linear FB via RVFbSimpleFbBind + RV_FB_PRESENT_SIMPLEFB
//
// Colors are 0x00RRGGBB (XRGB in a U32 on little-endian = B,G,R,X in memory = DRM XR24).
#define RV_FB_BASE_DEFAULT  CONFIG_FB_SOFT_BASE
#define RV_FB_W_DEFAULT     800
#define RV_FB_H_DEFAULT     600
#define RV_FB_BPP           32
// Soft layout: scanout @ FB_SOFT_BASE, compose @ +2MiB (keeps 0x86500000 free for fb smoke).
#define RV_FB_COMPOSE_OFF   0x200000
// Present backend kinds (RVFbSetPresent / rv_fb.backend).
#define RV_FB_PRESENT_NONE      0
#define RV_FB_PRESENT_RAMFB     1
#define RV_FB_PRESENT_SIMPLEFB  2
// DRM fourcc XR24 (XRGB8888)
#define RV_FB_FOURCC_XR24   ('X'|('R'<<8)|('2'<<16)|('4'<<24))
class CRVFb
{
  U32 *pixels;
  // compose / paint target (Gr, WinMgr, RVFbPut*)
  U32 *scanout;
  // display front buffer (ramfb / simplefb); may equal pixels if undoubled
  I64 width;
  I64 height;
  I64 stride;
  // bytes per row
  I64 present_ok;
  // TRUE after a backend accepted the buffer
  I64 backend;
  // RV_FB_PRESENT_* that last succeeded
};
CRVFb rv_fb;
I64 rv_fb_present_kind = RV_FB_PRESENT_RAMFB;
// overridden by RVFbPlatApplyPresent() from Kconfig
// Firmware / DT simple-framebuffer scanout (chosen/framebuffer@…). No DT walker yet —
// board bring-up fills this via RVFbSimpleFbBind from known firmware values.
class CRVSimpleFb
{
  U32 *base;
  // phys addr of scanout (identity map)
  I64 width;
  I64 height;
  I64 stride;
  // bytes per row (0 ⇒ width*4)
  I64 fourcc;
  // prefer RV_FB_FOURCC_XR24
  Bool bound;
};
CRVSimpleFb rv_simplefb;
U0 RVFbSetPresent(I64 kind)
{
  //Select present backend without changing draw callers.
  rv_fb_present_kind = kind;
}

Bool RVFbSimpleFbBind(U32 *base, I64 width, I64 height, I64 stride = 0, I64 fourcc = RV_FB_FOURCC_XR24)
{
  //Portable board hook: bind a firmware/DT linear XR24 FB. Does not draw yet — RVSysGrInit / RVFbInit.
  // stride=0 ⇒ tightly packed 32-bpp. Returns FALSE if args are unusable.
  // No DRM/virtio-gpu — firmware must leave a linear scanout; see BOARD_FB.md.
  if (!base || width < 16 || height < 16)
    return FALSE;
  if (width > 4096 || height > 4096)
    return FALSE;
  if (fourcc && fourcc != RV_FB_FOURCC_XR24)
    return FALSE;
  // XR24 only in this stub (r5g6b5 / AB24 need an explicit convert path later)
  if (!fourcc)
    fourcc = RV_FB_FOURCC_XR24;
  if (!stride)
    stride = width * (RV_FB_BPP / 8);
  if (stride < width * (RV_FB_BPP / 8))
    return FALSE;
  if (stride & 3)
    return FALSE;
  // row bytes must be U32-aligned for XRGB stores
  rv_simplefb.base = base;
  rv_simplefb.width = width;
  rv_simplefb.height = height;
  rv_simplefb.stride = stride;
  rv_simplefb.fourcc = fourcc;
  rv_simplefb.bound = TRUE;
  RVFbSetPresent(RV_FB_PRESENT_SIMPLEFB);
  return TRUE;
}

Bool RVFbSimpleFbBound()
{
  //TRUE after a successful RVFbSimpleFbBind (board / smoke).
  return rv_simplefb.bound && rv_simplefb.base != NULL;
}
#ifndef CONFIG_SIMPLEFB_BASE
#define CONFIG_SIMPLEFB_BASE 0
#endif
#ifndef CONFIG_SIMPLEFB_WIDTH
#define CONFIG_SIMPLEFB_WIDTH 0
#endif
#ifndef CONFIG_SIMPLEFB_HEIGHT
#define CONFIG_SIMPLEFB_HEIGHT 0
#endif
#ifndef CONFIG_SIMPLEFB_STRIDE
#define CONFIG_SIMPLEFB_STRIDE 0
#endif
Bool RVFbSimpleFbTryBoard()
{
  //Auto-bind when Kconfig SIMPLEFB_* is non-zero (board defconfig). Else manual bind.
  if (!CONFIG_SIMPLEFB_BASE || CONFIG_SIMPLEFB_WIDTH <= 0 || CONFIG_SIMPLEFB_HEIGHT <= 0)
    return FALSE;
  return RVFbSimpleFbBind ((U32 *)CONFIG_SIMPLEFB_BASE, CONFIG_SIMPLEFB_WIDTH, CONFIG_SIMPLEFB_HEIGHT, CONFIG_SIMPLEFB_STRIDE, RV_FB_FOURCC_XR24);
}

I64 RVFbPixStride()
{
  //U32 pixels per row for indexing rv_fb.pixels[]. rv_fb.stride is bytes.
  I64 n;
  if (!rv_fb.stride)
    return rv_fb.width;
  n = rv_fb.stride >> 2;
  if (n < rv_fb.width)
    n = rv_fb.width;
  return n;
}

Bool RVFbProbeRamfb()
{
  //TRUE if fw_cfg lists etc/ramfb (QEMU `-device ramfb`). Safe under `-nographic` without ramfb.
  return RVFwCfgFind("etc/ramfb") >= 0;
}

I64 RVFbBytes()
{
  //Byte size of one XR24 frame (stride × height).
  if (rv_fb.stride <= 0 || rv_fb.height <= 0)
    return 0;
  return rv_fb.stride *rv_fb.height;
}

U0 RVFbFlip()
{
  //Compose → scanout. No-op when undoubled (same pointer).
  I64 n;
  if (!rv_fb.pixels || !rv_fb.scanout || rv_fb.pixels == rv_fb.scanout)
    return;
  n = RVFbBytes;
  if (n > 0)
    MemCpy(rv_fb.scanout, rv_fb.pixels, n);
}

Bool RVFbPresentRamfb()
{
  //Locate etc/ramfb via fw_cfg and point it at rv_fb.scanout. Requires `-device ramfb`.
  // QEMU maps guest RAM as the scanout; rewriting etc/ramfb every frame recreates
  // DisplaySurfaces (cocoa/SDL crash / leak). Configure once; Flip updates pixels.
  I64 sel;
  I64 i;
  U32 *front = rv_fb.scanout;
  if (!front)
    front = rv_fb.pixels;
  if (rv_fb.backend == RV_FB_PRESENT_RAMFB && rv_fb.present_ok && front)
    return TRUE;
  if (!front)
    return FALSE;
  sel = RVFwCfgFind("etc/ramfb");
  if (sel < 0)
    return FALSE;
  // RAMFBCfg: addr(u64) fourcc flags width height stride — all BE
  U8 cfg[28];
  for (i = 0; i < 28; i++)
    cfg[i] = 0;
  I64 be_fb = EndianI64(front);
  MemCpy(cfg, &be_fb, 8);
  U32 fourcc = EndianU32(RV_FB_FOURCC_XR24);
  MemCpy(cfg + 8, &fourcc, 4);
  U32 w = EndianU32(rv_fb.width), h = EndianU32(rv_fb.height), st = EndianU32(rv_fb.stride);
  MemCpy(cfg + 16, &w, 4);
  MemCpy(cfg + 20, &h, 4);
  MemCpy(cfg + 24, &st, 4);
  RVFwCfgWriteSel(sel, cfg, 28);
  rv_fb.backend = RV_FB_PRESENT_RAMFB;
  rv_fb.present_ok = TRUE;
  return TRUE;
}

Bool RVFbPresentSimpleFb()
{
  //Push compose to a bound simplefb scanout (or no-op if Flip already landed there).
  // Stub: XR24 only; row copy when stride/base differ. DT discovery is board-side later.
  I64 y, row_bytes, dst_stride;
  U8 *src, *dst;
  if (!rv_simplefb.bound || !rv_simplefb.base || !rv_fb.pixels)
    return FALSE;
  if (rv_simplefb.fourcc && rv_simplefb.fourcc != RV_FB_FOURCC_XR24)
    return FALSE;
  if (rv_fb.width != rv_simplefb.width || rv_fb.height != rv_simplefb.height)
    return FALSE;
  dst_stride = rv_simplefb.stride;
  if (!dst_stride)
    dst_stride = rv_simplefb.width * (RV_FB_BPP / 8);
  row_bytes = rv_fb.width * (RV_FB_BPP / 8);
  if (rv_fb.scanout == rv_simplefb.base && rv_fb.stride == dst_stride) {
    // Flip already wrote compose → scanout (== firmware FB).
    rv_fb.backend = RV_FB_PRESENT_SIMPLEFB;
    rv_fb.present_ok = TRUE;
    return TRUE;
  }
  if (rv_fb.pixels == rv_simplefb.base && rv_fb.stride == dst_stride) {
    // Undoubled: paint target is the scanout.
    rv_fb.backend = RV_FB_PRESENT_SIMPLEFB;
    rv_fb.present_ok = TRUE;
    return TRUE;
  }
  src = rv_fb.pixels(U8 *);
  dst = rv_simplefb.base(U8 *);
  for (y = 0; y < rv_fb.height; y++) {
    MemCpy(dst + y *dst_stride, src + y *rv_fb.stride, row_bytes);
  }
  rv_fb.backend = RV_FB_PRESENT_SIMPLEFB;
  rv_fb.present_ok = TRUE;
  return TRUE;
}

Bool RVFbInit(I64 width = RV_FB_W_DEFAULT, I64 height = RV_FB_H_DEFAULT, U32 *pixels = NULL)
{
  //Bind 32-bpp compose + scanout. pixels=NULL ⇒ soft double buffer at FB_SOFT_BASE.
  // Non-NULL pixels = caller's scanout (simplefb); compose uses soft RAM when distinct.
  U32 *soft = RV_FB_BASE_DEFAULT;
  U32 *compose, *front;
  I64 nbytes;
  if (width <= 0 || height <= 0)
    return FALSE;
  rv_fb.width = width;
  rv_fb.height = height;
  rv_fb.stride = width * (RV_FB_BPP / 8);
  nbytes = RVFbBytes;
  if (!pixels) {
    front = soft;
    compose = (soft(U8 *) + RV_FB_COMPOSE_OFF)(U32 *);
  } else {
    front = pixels;
    if (pixels == soft)
      compose = (soft(U8 *) + RV_FB_COMPOSE_OFF)(U32 *);
    else
      compose = soft;
  }
  rv_fb.pixels = compose;
  rv_fb.scanout = front;
  rv_fb.present_ok = FALSE;
  rv_fb.backend = RV_FB_PRESENT_NONE;
  MemSet(rv_fb.pixels, 0, nbytes);
  if (rv_fb.scanout != rv_fb.pixels)
    MemSet(rv_fb.scanout, 0, nbytes);
  return TRUE;
}

U0 RVFbPresent()
{
  //Flip compose → scanout, then push scanout to the active backend.
  RVFbFlip;
  if (rv_fb_present_kind == RV_FB_PRESENT_RAMFB)
    RVFbPresentRamfb();
  else if (rv_fb_present_kind == RV_FB_PRESENT_SIMPLEFB)
    RVFbPresentSimpleFb();
}

U0 RVFbPutPixel(I64 x, I64 y, U32 color)
{
  if (!rv_fb.pixels)
    return;
  if (x < 0 || y < 0 || x >= rv_fb.width || y >= rv_fb.height)
    return;
  rv_fb.pixels[y *rv_fb.width + x] = color;
}

U0 RVFbFill(U32 color)
{
  I64 n, i;
  if (!rv_fb.pixels)
    return;
  n = rv_fb.width *rv_fb.height;
  for (i = 0; i < n; i++)
    rv_fb.pixels[i] = color;
}

U0 RVFbFillRect(I64 x, I64 y, I64 w, I64 h, U32 color)
{
  I64 xx, yy, x2, y2;
  if (!rv_fb.pixels)
    return;
  if (w <= 0 || h <= 0)
    return;
  x2 = x + w;
  y2 = y + h;
  if (x < 0)
    x = 0;
  if (y < 0)
    y = 0;
  if (x2 > rv_fb.width)
    x2 = rv_fb.width;
  if (y2 > rv_fb.height)
    y2 = rv_fb.height;
  for (yy = y; yy < y2; yy++)
    for (xx = x; xx < x2; xx++)
      rv_fb.pixels[yy *rv_fb.width + xx] = color;
}

U0 RVFbBlit(I64 dx, I64 dy, U32 *src, I64 sw, I64 sh, I64 sstride_px = 0)
{
  //Copy a tightly-or-strided 32-bpp rect into the FB (no clipping on src; dst clipped).
  I64 x, y, sstride;
  if (!rv_fb.pixels || !src || sw <= 0 || sh <= 0)
    return;
  sstride = sstride_px;
  if (sstride <= 0)
    sstride = sw;
  for (y = 0; y < sh; y++) {
    I64 yy = dy + y;
    if (yy < 0 || yy >= rv_fb.height)
      continue;
    for (x = 0; x < sw; x++) {
      I64 xx = dx + x;
      if (xx < 0 || xx >= rv_fb.width)
        continue;
      rv_fb.pixels[yy *rv_fb.width + xx] = src[y *sstride + x];
    }
  }
}

U0 RVFbPutChar(I64 x, I64 y, U32 color, I64 ch)
{
  //8×8 glyph from sys_font_std (FontStd.HC). LSB of each row is the leftmost pixel
  // (TempleOS gr.to_8_bits / GrRopEquU8NoClipping convention).
  U8 *glyph = (&sys_font_std[ch & 255])(U8 *);
  I64 row, col;
  for (row = 0; row < FONT_HEIGHT; row++) {
    U8 bits = glyph[row];
    for (col = 0; col < FONT_WIDTH; col++)
      if (bits & (1 << col))
        RVFbPutPixel(x + col, y + row, color);
  }
}

U0 RVFbPutStr(I64 x, I64 y, U32 color, U8 *st)
{
  I64 cx = x;
  if (!st)
    return;
  while (*st) {
    if (*st == '\n') {
      cx = x;
      y += FONT_HEIGHT;
      st++;
      continue;
    }
    RVFbPutChar(cx, y, color, *st++);
    cx += FONT_WIDTH;
  }
}

U32 RVFbHash()
{
  //FNV-1a over pixel U32s — CI oracle without a host screenshot (word-wise for speed).
  I64 h = 2166136261, n, i;
  U32 *w;
  if (!rv_fb.pixels)
    return 0;
  n = (rv_fb.stride *rv_fb.height) >> 2;
  w = rv_fb.pixels;
  for (i = 0; i < n; i++) {
    h ^= w[i];
    h *= 16777619;
    h &= 0xFFFFFFFF;
  }
  return h;
}
