// HolyC operator precedence (Compiler/CInit.HC binary_ops): `<< >>` and ` bind tightest, then
// `* / %`, then `& ^ |`, then `+ -`, then `< >`, then `== !=`. Differs from C.
I64 main()
{
  return (( (0xDEAD&15)+48 == 61) )*1 +          // m&15 +'0'  → (m&15)+48
         (( 1<<2 +1 == 5 ))*2 +                  // (1<<2)+1
         (( 2 +3&1 == 3 ))*4 +                   // 2+(3&1)
         (( 8>>1 +1 == 5 ))*8 +                  // (8>>1)+1
         (( 1<3 == 1 ))*16 +                     // (1<3)==1
         (( 0xF0 | 0x0F +1 == 0x100 ))*32;       // 0xF0 | (0x0F+1) = 0xF0|0x10 = 0x100
}                                                // 0x3f if all match HolyC precedence
