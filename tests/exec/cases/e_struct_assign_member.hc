// Assigning a class LARGER THAN ONE WORD must copy all of it, and the left-hand side can be a
// member and not only a bare variable.
//
//     local = area.vars;      // LHS is a class INSTANCE -- always worked
//     area.vars = local;      // LHS is a MEMBER -- used to copy eight bytes
//
// The broken direction was a SHORT COPY, not an overrun: the first two fields arrived, the rest
// stayed as they were, and the bytes after the member were untouched. That is why it read as a
// plausible value rather than as a crash, and why the two directions looked alike.
//
// A FIX WAS TRIED BEFORE AND REVERTED. The condition used was "the LHS ends in a deref", which
// also caught a POINTER member store -- `Entry->Datum.AsPointer = Ptr` in CFE_Config_SetString --
// and block-copied the enclosing class over what should have been a single store.
// `cc->last_member->member_class` is what discriminates them: it is NULL for a scalar or pointer
// member and non-NULL only for a member whose own type is a class.
//
// So this case exercises all five shapes that reach the decision, and the last three are the
// ones that must NOT block-copy:
//
//     area.vars = local             a class member          -> copy all 28 bytes
//     area.vars.sig = ...           a scalar member         -> one store
//     ent.Datum.AsPointer = ...     a POINTER member        -> one store (the reverted bug)
//     ent.Datum.AsInt = ...         a scalar member, 8 wide -> one store
//     plain = ...                   not a member at all     -> one store
//
// Every guard field is checked, not just the copy: a block copy of the wrong SIZE shows up as a
// neighbour that moved, so `head` and `tail` bracket the member on both sides and the pointer
// member's neighbour is read back too. docs/HOLYC_STRUCT_LIMITS.md #2.
class RV
{
  U32 sig;
  I16 leap;
  U16 sel;
  U32 a;
  U32 b;
  U32 c;
  U32 d;
  U32 e;
};

class Area
{
  U32 head;
  RV vars;
  U32 tail;
};
// The shape CFE_Config_SetString stores through: a union-like record whose first member is a
// pointer. Assigning to it must remain a single store.
class Dat
{
  I64 *AsPointer;
  I64 AsInt;
};

class Ent
{
  U32 k;
  Dat Datum;
  U32 after;
};
Area area;
Ent ent;
I64 target;
I64 main()
{
  RV local;
  I64 plain = 0;
  I64 r = 0;
  // --- direction A: LHS is a class instance. This always worked; it is here so that a change
  // which fixes B by breaking A is caught.
  area.head = 0x1111;
  area.tail = 0x2222;
  area.vars.sig = 0xABCD;
  area.vars.leap = -7;
  area.vars.sel = 3;
  area.vars.a = 11;
  area.vars.e = 99;
  local.sig = 0;
  local.leap = 0;
  local.sel = 0;
  local.a = 0;
  local.e = 0;
  local.b = 0;
  local.c = 0;
  local.d = 0;
  local = area.vars;
  r = r * 100000 + local.sig;
  // 43981
  r = r * 100 + (local.leap + 50);
  // 43
  r = r * 100 + local.a;
  // 11
  r = r * 100 + local.e;
  // 99
  // --- direction B: LHS is a class MEMBER. This is the fix.
  local.sig = 0x5A5A;
  local.leap = 12;
  local.sel = 4;
  local.a = 21;
  local.e = 55;
  area.vars.sig = 0;
  area.vars.leap = 0;
  area.vars.sel = 0;
  area.vars.a = 0;
  area.vars.e = 0;
  area.vars = local;
  r = r * 100000 + area.vars.sig;
  // 23130
  r = r * 100 + (area.vars.leap + 50);
  // 62
  r = r * 100 + area.vars.a;
  // 21
  r = r * 100 + area.vars.e;
  // 55
  // the neighbours on BOTH sides of the member: a copy of the wrong size moves one of them
  r = r * 10 + (area.head == 0x1111);
  // 1
  r = r * 10 + (area.tail == 0x2222);
  // 1
  // --- the three that must stay single stores -------------------------------------------
  area.vars.sig = 7;
  r = r * 10 + (area.vars.sig == 7);
  // 1
  r = r * 10 + (area.vars.a == 21);
  // 1 -- a scalar member store did not smear
  ent.k = 0x33;
  ent.after = 0x44;
  target = 1234;
  ent.Datum.AsPointer = &target;
  r = r * 10 + (*ent.Datum.AsPointer == 1234);
  // 1 -- the pointer arrived as a pointer
  r = r * 10 + (ent.k == 0x33);
  // 1 -- and its neighbours are intact
  r = r * 10 + (ent.after == 0x44);
  // 1
  ent.Datum.AsInt = 7;
  r = r * 10 + (ent.Datum.AsInt == 7);
  // 1
  r = r * 10 + (ent.after == 0x44);
  // 1
  plain = 3;
  r = r * 10 + plain;
  // 3
  return r & 0xFFFFFFFFFFFF;
}
