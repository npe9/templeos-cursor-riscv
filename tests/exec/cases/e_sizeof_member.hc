// `sizeof` OF A MEMBER REACHED WITH `.` WORKS. This is the premise of a workaround, which is why
// it is pinned.
//
// `sizeof(p->member)` does NOT parse (docs/HOLYC_STRUCT_LIMITS.md #16), so the cFS translation
// substitutes the array's bound wherever NASA writes it -- cfe_sb_priv.HC's CFE_SB_GetAppTskName
// is the first site. That substitution is only correct if the dot form it was checked against
// really does report the member's size, and if `sizeof` on a class member ever stopped agreeing
// with the layout, every substituted bound in the port would be wrong at once with nothing
// pointing at the cause.
//
// Three shapes: an ARRAY member, a SCALAR member, and a member of a NESTED class.
class Inner
{
  U8 four[4];
  I64 eight;
};

class Outer
{
  U8 sixteen[16];
  I64 scalar;
  Inner nest;
};

I64 main()
{
  Outer o;
  I64 r = 0;
  r = r * 100 + sizeof(o.sixteen);
  // 16
  r = r * 100 + sizeof(o.scalar);
  // 8
  r = r * 100 + sizeof(o.nest);
  // 12: four[4] + eight, packed
  r = r * 100 + sizeof(o.nest.four);
  // 4 -- a member of a member
  r = r * 100 + sizeof(Outer);
  // 36: 16 + 8 + 12, HolyC classes are packed
  return r;
}
