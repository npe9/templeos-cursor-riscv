// A CLASS DECLARATION INITIALISER CARRIES ONLY ITS FIRST 8 BYTES.
//
// Silent, and the third member of the family: docs/HOLYC_STRUCT_LIMITS.md #21 is a class copy
// into an array slot or through a bare pointer, #26 is a class passed by value, and this is a
// class copied by a DECLARATION INITIALISER. The compiler's treatment of the five forms is
// inconsistent in a way no reader would guess:
//
//   S d; d = src;          WHOLE
//   S d; d = p->m;         WHOLE
//   S d; d = v.m;          WHOLE
//   s.member = src;        WHOLE                                        (#21's note)
//   arr[i] = src;          first 8 bytes, silently                      (#21)
//   *ptr = src;            first 8 bytes, silently                      (#21)
//   f(src)                 first 8 bytes, silently                      (#26)
//   S d = src;             first 8 bytes, silently                      (#27, this file)
//   S d = p->m;            first 8 bytes, silently                      (#27, this file)
//
// So the SAME copy is whole as a statement and truncated as an initialiser. One extra line of
// source changes the semantics.
//
// FOUND BY A TRANSCRIPT DIVERGENCE, not by reading. NASA's MM_FillMemCmd writes
//     MM_SymAddr_t DestSymAddress = Msg->Payload.DestSymAddress;
// where the other four handlers in the same file declare and then assign. The 72-byte
// MM_SymAddr_t's first eight bytes are its Offset, so the OFFSET SURVIVED and the 64-byte
// SymName did not -- which made MM_ResolveSymAddr see a non-empty name in uninitialised stack,
// take the symbol-lookup branch instead of the offset branch, and send the fill to the wrong
// address. The command was built correctly and the address was wrong, which is the hardest
// version of this to chase.
//
// THE POISON IS WHY THIS FILE IS NOT VACUOUS. A declaration has no chance to be zeroed first, so
// the bytes past the eighth are whatever the frame held -- and a run where they happen to be
// zero would look like a successful copy of a zero field. `warm` is called first precisely to
// leave a known non-zero pattern in the frame these functions reuse, so a truncated copy reads
// 0xAA and not 0x00.
I64 main();

class S                     // 72 bytes, the shape of MM_SymAddr_t
{
  U64 a;
  U8 n[64];
};
class P
{
  U64 h;
  S m;
};

P g;
P *gp;

// Leave a recognisable pattern in the frame that the probes below will reuse, so a byte the
// initialiser did NOT copy reads 0xAA rather than an accidental zero.
U0 warm()
{
  U8 fill[96];
  MemSet(fill, 0xAA, 96);
}

// `S d = p->m;` -- exactly the form NASA writes.
I64 decl_from_ptr()
{
  S d = gp->m;
  return (d.a == 5) << 2 | (d.n[0] == 88) << 1 | (d.n[63] == 77);
}

// `S d = v.m;` -- the same, from a plain variable rather than through a pointer.
I64 decl_from_var()
{
  S d = g.m;
  return (d.a == 5) << 1 | (d.n[0] == 88);
}

// And the two-statement form, which IS whole. This is the control: without it a reader cannot
// tell a broken initialiser from a broken class copy.
I64 assign_from_ptr()
{
  S d;
  d = gp->m;
  return (d.a == 5) << 2 | (d.n[0] == 88) << 1 | (d.n[63] == 77);
}

I64 main()
{
  I64 r;

  MemSet(&g, 0, sizeof(P));
  g.m.a = 5;
  g.m.n[0] = 88;  // 'X'
  g.m.n[63] = 77; // 'M'
  gp = &g;

  // Nibble 3: the two-statement form. 7 today, 7 when fixed -- all three fields copied.
  warm();
  r = assign_from_ptr();
  // Nibble 2: `S d = p->m`. 4 TODAY (only `a` survives), 7 WHEN FIXED.
  warm();
  r = r << 4 | decl_from_ptr();
  // Nibble 1: `S d = v.m`. 2 TODAY (only `a` survives), 3 WHEN FIXED.
  warm();
  r = r << 4 | decl_from_var();
  // Nibble 0: sizeof says 72, so the compiler KNOWS the size it did not copy. 9 always.
  r = r << 4 | (sizeof(S) == 72) * 9;
  return r;
}
