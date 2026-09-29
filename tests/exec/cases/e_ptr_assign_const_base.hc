// Four ways to build a pointer from a constant base and a variable offset. Three are correct and
// one is MISCOMPILED by the host compiler, which is what this case exists to pin.
//
// Found on the HiFive Unmatched: Kernel/Drv/RVSifivePrci.HC read its PLL registers with
//   U32 *p; p = CONFIG_SIFIVE_PRCI_BASE + off; return *p;
// and every read came back from `base + off*4`, so Clk() reported 52 MHz for all four PLLs while
// mcycle against the CLINT measured the core at 1.196 GHz. The host compiler's own output for
// that line:
//     lui  a0,0x10000      # base
//     mv   a0,s1           # off
//     li   a0,4            # sizeof(U32), which appears nowhere in the source
//     mul  a0,t0,t1        # off * 4
//     add  a0,t0,t1        # base + off*4
// The scaling is pointer arithmetic applied because the ASSIGNMENT's destination is a pointer.
// It does not happen in an initializer, or when the base is a variable -- which is exactly why
// the PLIC reads in RVSifiveYes.HC and the GEM driver were never bitten by it, and why this
// survived until a driver happened to be written the fourth way.
//
// The guest compiler does NOT scale in any of these forms (checked at the board's own prompt:
// `U32 *p; I64 o; o=4; p = 0x10000000 + o; p;` answers 0x10000004). So the two compilers in this
// tree disagree about this expression, which matters for self-hosting.
//
// Expect 0x7: bits 1, 2 and 4 set, bit 8 CLEAR because the bug is present. When the host
// compiler is fixed, this returns 0xf and the manifest entry must change with it -- that flip is
// the point of the case.
// Each address is moved into an I64 BEFORE it is compared. Comparing a pointer against
// `PB + 4` directly does not work as a control here: that comparison is itself pointer-typed,
// so the scaling under test contaminates the test's own yardstick. The first draft of this case
// did exactly that and reported the three good forms as the broken ones.
#define PB 0x80000000
#define PB4 0x80000004
I64 main()
{
  I64 r = 0, off = 4, vb = PB;
  I64 a_init, a_var, a_cast, a_asg;
  U32 *init = PB + off;
  U32 *asg;
  U32 *var;
  asg = PB + off;
  var = vb + off;
  a_init = init;
  a_var = var;
  a_cast = (PB + off)(U32 *);
  a_asg = asg;
  if (a_init == PB4) r |= 1;   // initializer: correct
  if (a_var == PB4)  r |= 2;   // variable base: correct
  if (a_cast == PB4) r |= 4;   // cast form: correct, and what drivers should use
  if (a_asg == PB4)  r |= 8;   // assignment + constant base: WRONG today
  return r;
}
