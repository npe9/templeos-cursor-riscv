// `fn(args)->member` HAS A SILENT FORM, and the documented one says it REFUSES.
//
// docs/HOLYC_STRUCT_LIMITS.md #17 records that the compiler resolves the `->` against the FIRST
// ARGUMENT's class and refuses to compile. That is what happens when the first argument IS a class
// pointer. With an INTEGER first argument there is no class to resolve against -- and it does not
// refuse. It compiles, and the load goes through ZERO:
//
//     TRAP mcause=0x5 (load-fault) mepc=... mtval=0x0000000000000000
//
// FOUND IN CS's STEP-2 EXERCISE. `CS_GetEepromResEntry(0)->State` is one of nine such accessors in
// cs_utils.h -- every one takes a `uint16 EntryIdx` and returns a typed pointer, which is exactly
// the shape -- and the transcript died mid-line after printing `csi_tbl_res eep0=`. The same call
// assigned to a local and then dereferenced is correct, which is #17's own workaround.
//
// SO THE SEVERITY OF #17 IS NOT WHAT IT SAYS. "Refuses" is a compile error a reader cannot miss;
// this is a null load three steps from the cause, in a function whose own body is right. Any
// translated cFS accessor that takes a scalar and returns a pointer is in this shape, and NASA
// writes that pattern constantly.
I64 main();

class R
{
  U16 State;
  U16 Extra;
  U32 Tail;
};

R rtab[4];
R *rptr;

// The CS shape: a SCALAR in, a typed pointer out. cs_utils.h has nine of these.
R *by_index(U16 i)
{
  if (i < 4)
    return &rtab[i];
  return NULL;
}

// And the shape #17 is written about: a CLASS POINTER in. Kept in a separate function so that if a
// future compiler starts refusing it, the refusal lands on one line and names itself.
U16 via_ptr_arg(R *r)
{
  return r->State;
}

// The WORKAROUND, which is what the exercise now does at every such site.
I64 hoisted()
{
  R *p;
  p = by_index(2);
  return p->State;
}

// THE DEFECT ITSELF IS NOT CALLED HERE. `by_index(2)->State` is a load through zero -- running it
// would end the case at the trap and the remaining bytes would never print, so there would be
// nothing to compare. The assertion is therefore the WORKAROUND against a DIRECT index, which is
// the pair a correct compiler makes equal and this one makes equal only through the local.
//
// BUT IT WAS CALLED ON PURPOSE, ONCE, to make sure this case is about something real: a throwaway
// probe whose whole body was `return by_index(2)->State;` -- with the SAME class, the SAME accessor
// and 0x33 in the slot -- produced NO ORACLE LINE AT ALL, which is the harness reporting a crash.
// So the two forms are not "one is tidier": one returns 0x33 and the other does not return.
I64 main()
{
  I64 r;

  rtab[0].State = 0x11;
  rtab[1].State = 0x22;
  rtab[2].State = 0x33;
  rtab[3].State = 0x44;

  // Byte 3: the hoisted call. 0x33 -- slot 2's State, reached through a local.
  r = hoisted();
  // Byte 2: the same slot read directly. 0x33, and equal to the line above.
  r = r << 8 | rtab[2].State;
  // Byte 1: #17's documented shape, a CLASS POINTER argument. 0x44 today. If a future compiler
  // starts refusing this, the error is on one line in via_ptr_arg and says so.
  rptr = &rtab[3];
  r = r << 8 | via_ptr_arg(rptr);
  // Byte 0: by_index still works as a FUNCTION -- the defect is in the arrow applied to its result,
  // not in the function. NULL out of range, non-NULL in range: 3.
  r = r << 8 | ((by_index(0) != NULL) | (by_index(9) == NULL) << 1);
  return r;
}
