// `sizeof` THROUGH `->` MUST STAY REFUSED UNTIL IT IS IMPLEMENTED.
//
// It does not parse (docs/HOLYC_STRUCT_LIMITS.md #16) and the refusal is the only thing standing
// between this construct and a wrong answer: being quietly ACCEPTED and given some other size is
// worse than being rejected, and that is the direction a careless fix would take it. `sizeof` of
// the same member reached with `.` works and is pinned by tests/exec/cases/e_sizeof_member.hc.
//
// NASA writes this form -- cfe_sb_priv.c's CFE_SB_GetAppTskName passes
// `sizeof(ptr->AppName)` to strncmp -- so the translation substitutes the array's bound, and
// that deviation exists only because of this.
//
// WHEN IT IS IMPLEMENTED this file stops being refused and the gate turns red. That is correct:
// move it to tests/exec/cases with the value asserted, and withdraw the substitutions.
class P
{
  U8 arr[8];
  I64 one;
};

I64 main()
{
  P s;
  P *p = &s;
  return sizeof(p->arr) + sizeof(p->one);
}
