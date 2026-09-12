#include "/Adam/Gr/Gr.HH"
I64 main() {
  // Pack expected: COLOR=2 PT=9 LINE=17 TEXT fixed=9 BASE=1 THICK=5
  // Return bitfield of matches + raw sizes in low encoding
  I64 r = 0;
  r += (sizeof(CSpriteBase) == 1) * 1;
  r += (sizeof(CSpriteColor) == 2) * 2;
  r += (sizeof(CSpriteT) == 5) * 4;
  r += (sizeof(CSpritePt) == 9) * 8;
  r += (sizeof(CSpritePtPt) == 17) * 16;
  r += (sizeof(CSpritePtRad) == 13) * 32;
  r += (sizeof(CSpritePtStr) == 9) * 64;
  // Also encode sizeof(CSpriteColor) in high byte for debug
  return r | (sizeof(CSpriteColor) << 8) | (sizeof(CSpritePtPt) << 16);
}
