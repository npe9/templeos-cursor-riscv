// THE TWO IDIOMS CS_TableWrapper_t IS BUILT ON, measured before 3,000 lines depend on them.
//
// CS is the first app whose code works almost entirely through a `CS_TableWrapper_t *tw` rather
// than naming one of its six checksum types. Two compiler behaviours carry that design, and
// NEITHER would fail loudly if it were wrong:
//
//   1. POINTER DIFFERENCE SCALED BY THE POINTEE. NASA's CS_GetTableId is `return tw -
//      CS_AppData.Tbl;` -- the table id recovered by subtracting the array base. In C that
//      divides the byte distance by sizeof(CS_TableWrapper_t), 112 here. If HolyC returned the
//      BYTE distance instead, CS_GetTableId(&Tbl[1]) would be 112 rather than 1, every event
//      would name the wrong checksum type, and the only symptom would be wrong text.
//
//   2. AN INDIRECT CALL THROUGH AN ARROW MEMBER. CS_CallTableUpdateHandler is
//      `tw->UpdateHandler(tw)`, and the open limit recorded in memory as the call-arrow-member
//      problem is the NEIGHBOURING shape -- `fn(a)->m`, an arrow applied to a call's RESULT --
//      so this one is worth a measurement rather than an assumption. A function pointer read
//      through `->` and called in the same expression, with the containing object passed to it.
//
//   3. POINTER ARITHMETIC OVER AN ODD-SIZED CLASS. CS's two name-based definition entries are
//      42 and 22 bytes -- the first classes in this port whose size is not a multiple of 8 --
//      and the four validation callbacks and three update handlers walk arrays of them with a
//      bare `++Entry`, from a pointer that arrived as an untyped one. If the stride were rounded
//      up to 48, every validation count and every copied entry would be wrong, and it would read
//      as a logic bug rather than as arithmetic.
//
// A fourth line is here because it is free: the SELF-REFERENTIAL member. W's UpdateHandler takes
// a `W *`, declared inside W's own body, which is what NASA's `struct CS_TableWrapper` tag
// exists for.
I64 main();

// The shape of CS_TableWrapper_t as far as these two idioms care: a size that is NOT a power of
// two, so a byte distance and a scaled distance cannot coincide, and a function pointer member
// that takes its own class.
class W
{
  U8 *name;
  U16 h1;
  U16 h2;
  U8 _pad0[4];
  I64 n;
  U0 (*handler)(W *w);
  I64 mark;
};

class G
{
  W Tbl[6];
};

G g;

// The shape of CS_Def_Tables_Table_Entry_t: 42 bytes, two-byte alignment, no padding anywhere.
class E
{
  U16 State;
  U8 Name[40];
};

E earr[4];
U8 *eraw;

// NASA's CS_GetTableId, verbatim in shape.
I64 tbl_id(W *w)
{
  return w - g.Tbl;
}

// The two update handlers. Each writes its own signature into the object it was handed, so the
// transcript can tell WHICH pointer arrived -- a call that passed the wrong `tw` would still
// return.
U0 handler_a(W *w)
{
  w->mark = 0xA0 + tbl_id(w);
}

U0 handler_b(W *w)
{
  w->mark = 0xB0 + tbl_id(w);
}

// The odd-stride walk, in the shape the validation callbacks use it: the array arrives as an
// untyped pointer (NASA casts a `void *TblPtr`), is assigned to a typed one, and walked with
// `++Entry`. The State of each slot is read back THROUGH the walked pointer, so a 48-byte stride
// would read six bytes into slot 1's Name rather than slot 2's State.
I64 odd_stride()
{
  E *e;
  I64 r;

  e = eraw;
  r = e->State; // slot 0
  ++e;
  r = r << 4 | e->State; // slot 1
  ++e;
  r = r << 4 | e->State; // slot 2
  // And the difference, scaled: two increments from the base is 2, not 84.
  r = r << 4 | (e - earr);
  return r;
}

// NASA's CS_CallTableUpdateHandler, verbatim in shape -- including the NULL guard, because four
// of CS's six wrappers have no update handler at all.
U0 call_handler(W *w)
{
  if (w->handler)
    w->handler(w);
}

I64 main()
{
  I64 r;

  MemSet(&g, 0, sizeof(G));
  g.Tbl[0].handler = &handler_a;
  g.Tbl[3].handler = &handler_b;
  // Tbl[5] deliberately keeps a NULL handler.

  // Byte 3: the pointer difference. 5 if it is scaled by sizeof(W), 200 if it is not.
  r = tbl_id(&g.Tbl[5]);
  // Byte 2: sizeof(W) is 40, so an UNSCALED difference would be 200, not 5 -- stated here so a
  // reader can see the two answers are distinguishable, and so that a future change to W's
  // shape cannot quietly make them coincide. 3 always.
  r = r << 8 | (sizeof(W) == 40) * 3;
  // Bytes 1 and 0 (and a third byte below): the indirect calls. 0xA0 and 0xB3 -- the handler identity AND the id it
  // recovered from the pointer it was passed.
  call_handler(&g.Tbl[0]);
  call_handler(&g.Tbl[3]);
  call_handler(&g.Tbl[5]); // the NULL guard: must not fault and must leave mark 0
  r = r << 8 | g.Tbl[0].mark;
  r = r << 8 | g.Tbl[3].mark;
  r = r << 8 | g.Tbl[5].mark;

  // The low four nibbles: the odd-stride walk. 0x1232 -- the States of slots 0, 1 and 2, then a
  // scaled pointer difference of 2. The States are deliberately non-zero and all different, so a
  // stride that landed inside a zeroed Name would read 0 rather than the neighbouring State.
  // POISONED, not zeroed: 0x55 everywhere first, so a read that landed inside a Name reads
  // 0x5555 rather than an accidental zero. Without this the walk could be reading the wrong
  // bytes and still look right, because the wrong bytes would be zero.
  MemSet(earr, 0x55, sizeof(E) * 4);
  earr[0].State = 1;
  earr[1].State = 2;
  earr[2].State = 3;
  earr[3].State = 4;
  eraw = earr;
  r = r << 16 | odd_stride();
  // And sizeof(E) is 42, not 48 -- 7 always.
  //
  // THIS NIBBLE IS WHAT THE STRIDE ASSERTION ACTUALLY RESTS ON, and it is worth saying why.
  // Padding E out to 48 bytes was tried as a negative control and it moved ONLY this nibble: the
  // three State reads stayed 1, 2, 3, because a 48-byte class is correctly walked 48 bytes at a
  // time. The compiler cannot be made to use a stride that disagrees with the type it was given.
  // So the property here is the conjunction -- the size IS 42, AND a walk of that type lands on
  // State -- and the poison above is what makes the second half mean something.
  r = r << 4 | (sizeof(E) == 42) * 7;
  return r;
}
