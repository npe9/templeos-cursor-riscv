// A STRUCT COPY INTO AN ARRAY SLOT OR THROUGH A BARE POINTER COPIES ONLY THE FIRST 8 BYTES.
//
// Silent. No diagnostic, no refusal; the bytes past the first eight are simply left as they
// were. It is the DESTINATION FORM that decides, and only two of the six forms are broken:
//
//   var = s                whole
//   var.member = s         whole
//   ptr->member = s        whole
//   var = arr[i]           whole  (the SOURCE may be an array element)
//   arr[i] = s             FIRST 8 BYTES ONLY
//   *ptr = s               FIRST 8 BYTES ONLY
//
// and the size does not matter beyond being over eight: a 12-, 16-, 20- and 24-byte class all
// copy exactly their first two words. A 4- or 8-byte class is correct by accident.
//
// TWO MEASUREMENTS BELOW ARE HERE BECAUSE A GATE DEPENDS ON THEM, not because they are
// interesting. tools/cfs/check_struct_copy.py treats `arr[i].member = s` as safe and lets a
// class of 8 bytes or less through with its size stated, and both of those were my arithmetic
// until this case ran them:
//
//   arr[i].member = s     WHOLE, although the destination address is computed
//   narrow[i] = s         WHOLE, and the NEIGHBOURS ARE NOT TOUCHED
//
// The second is the one that could have gone either way. An 8-byte store into a 2-byte array
// slot would overwrite the three entries after it, which is the recorded array-deref store bug
// exactly; and cFE has such an array -- CFE_SBR_MSGMAP, a message-id-to-route hash map of
// 2-byte CFE_SBR_RouteId, written one slot at a time. It does not happen: a narrow class is
// stored at its own width.
//
// This is the same family as the recorded array-deref store bug -- a store through a computed
// address using a fixed 8-byte width instead of the type's size -- and it is the SILENT
// counterpart of the one the compiler does refuse: a class return by value over 8 bytes is a
// diagnostic (tests/holyc/refused/struct_return_too_big.hc). An assignment is not.
//
// HOW IT WAS FOUND. cfe_es_perf.c's capture path builds a performance log entry in a local --
// a marker word and a 64-bit hardware timestamp, twelve bytes -- and stores it with
//
//     Perf->DataBuffer[DataEnd] = EntryData;
//
// The marker arrived and the TIMESTAMP DID NOT, in every entry of every capture. The
// translation's transcript read `t0=0 t1=0` where NASA's read `t0=1 t1=2`: a performance log
// whose timestamps are all zero, which is the one thing a performance log is for. Nothing else
// in the gate set could see it -- the layout matches, the signatures match, the function is
// present in the blob -- because the defect is in the STORE, not in any declaration.
//
// The workaround is MemCpy, and cfe_es_perf.HC uses it with this case named.
class Ent
{
  U32 Data;
  U32 Up;
  U32 Lo;
};

class Wide
{
  U32 a;
  U32 b;
  U32 c;
  U32 d;
  U32 e;
  U32 f;
};

class Outer
{
  U32 head;
  Ent inner;
  U32 tail;
};

class Narrow
{
  U16 v;
};

class Holder
{
  Ent inner;
  U32 tail;
};
Narrow NarrowSlots[8];
Narrow NarrowSrc;
Holder HeldSlots[4];
Ent Slots[4];
Wide WideSlots[4];
Outer Nest;
Ent Src;
Wide WideSrc;
I64 main()
{
  Ent *p;
  Outer *np;
  Ent plain;
  I64 r = 0;
  Src.Data = 1;
  Src.Up = 2;
  Src.Lo = 3;
  WideSrc.a = 1;
  WideSrc.b = 2;
  WideSrc.c = 3;
  WideSrc.d = 4;
  WideSrc.e = 5;
  WideSrc.f = 6;
  // --- THE TWO BROKEN FORMS. Each nibble below is 0 today and becomes its field's value when
  // the compiler is fixed, at which point this case fails and says so.
  Slots[1] = Src;
  r = (r << 4) | Slots[1].Up;
  // 2: inside the first eight bytes, so it survives
  r = (r << 4) | Slots[1].Lo;
  // 0 today, 3 when fixed
  p = &Slots[2];
  *p = Src;
  r = (r << 4) | Slots[2].Lo;
  // 0 today, 3 when fixed
  // Six words: everything past the second is lost, not just the tail.
  WideSlots[1] = WideSrc;
  r = (r << 4) | WideSlots[1].b;
  // 2
  r = (r << 4) | WideSlots[1].c;
  // 0 today, 3 when fixed
  r = (r << 4) | WideSlots[1].f;
  // 0 today, 6 when fixed
  // --- THE FOUR FORMS THAT WORK, which is what makes the diagnosis a rule and not a guess.
  plain = Src;
  r = (r << 4) | plain.Lo;
  // 3
  Nest.inner = Src;
  r = (r << 4) | Nest.inner.Lo;
  // 3
  Nest.inner.Lo = 0;
  np = &Nest;
  np->inner = Src;
  r = (r << 4) | Nest.inner.Lo;
  // 3
  plain.Lo = 0;
  plain = Slots[0];
  // the SOURCE being an array element is fine
  Slots[0].Lo = 9;
  plain = Slots[0];
  r = (r << 4) | plain.Lo;
  // 9
  // --- `arr[i].member = s`: AN INDEXED BASE WITH A MEMBER SELECTOR, which is a seventh form
  // and not the sixth. The destination address is computed, like `arr[i] = s`, but the copy is
  // whole -- all three words -- and the neighbouring member is untouched.
  HeldSlots[1].inner.Data = 7;
  HeldSlots[1].inner.Up = 7;
  HeldSlots[1].inner.Lo = 7;
  HeldSlots[1].tail = 8;
  HeldSlots[1].inner = Src;
  r = (r << 4) | HeldSlots[1].inner.Data;
  // 1
  r = (r << 4) | HeldSlots[1].inner.Up;
  // 2
  r = (r << 4) | HeldSlots[1].inner.Lo;
  // 3, and 7 if only the first eight bytes moved
  r = (r << 4) | HeldSlots[1].tail;
  // 8, and anything else means the store ran past the member
  // --- A CLASS NARROWER THAN THE STORE, in an array of its own. If the store width were a
  // fixed eight bytes, NarrowSlots[2] = NarrowSrc would also write slots 3, 4 and 5.
  NarrowSlots[0].v = 1;
  NarrowSlots[1].v = 2;
  NarrowSlots[2].v = 3;
  NarrowSlots[3].v = 4;
  NarrowSlots[4].v = 5;
  NarrowSlots[5].v = 6;
  NarrowSrc.v = 15;
  NarrowSlots[2] = NarrowSrc;
  r = (r << 4) | NarrowSlots[2].v;
  // F
  r = (r << 4) | NarrowSlots[3].v;
  // 4, and 0 if the store was eight bytes wide
  r = (r << 4) | NarrowSlots[4].v;
  // 5
  r = (r << 4) | NarrowSlots[5].v;
  // 6
  return r;
}
