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
// FIXED. ParseAssignment now clears last_var_symbol/last_global_var/last_member/expr_ptr_depth
// after consuming `=` and before parsing the RHS, so the target no longer leaks into it. This
// case returned 0x7 while the bug was live and returns 0xf now; it stays because all four
// spellings still have to agree, and because a regression here is silent everywhere else.
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
  if (a_init == PB4) r |= 1;   // initializer, with nothing pointer-typed before it
  if (a_var == PB4)  r |= 2;   // variable base
  if (a_cast == PB4) r |= 4;   // cast form, and what drivers should use
  if (a_asg == PB4)  r |= 8;   // assignment + constant base
  // The four bits above are the whole rule, and a third real site confirmed it. Diffing the
  // compiler's output across the fix changed exactly two bytes in the platform demo's blob:
  //     old  lui a0,0xc008 ; addi a0,a0,512  -> 0x0C008200
  //     new  lui a0,0xc002 ; addi a0,a0,128  -> 0x0C002080
  // and the instruction after it stores to a local that is then used as `u[0] = 0`, so the site
  // is kernel_plat_demo.hc's PLIC cleanup, `u = CONFIG_PLIC_BASE + CONFIG_PLIC_ENABLE_OFF;` --
  // an ASSIGNMENT to an existing pointer, bit 8's shape exactly. RVSifivePlicEnable's own
  //     U32 *en = CONFIG_PLIC_BASE + CONFIG_PLIC_ENABLE_OFF;
  // sits in the same blob and did NOT change, because it is an initializer. So enabling PLIC
  // sources always worked and the plic_meip gate was honest; what silently failed was the
  // cleanup after it, which zeroed 0x0C008200 and left all 63 sources enabled.
  return r;
}
