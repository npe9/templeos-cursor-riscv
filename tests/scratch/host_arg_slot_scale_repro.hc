// scratch handoff repro (host/ lane): `K + p->member` mis-scaled as pointer
// arithmetic on `p` when it appears in an argument slot of a call whose first
// parameter is that same pointer.
//
//   run: printf 'tests/scratch/host_arg_slot_scale_repro.hc\t00000000000000ff\n' > /tmp/m.tsv
//        ORACLE_MANIFEST=/tmp/m.tsv tests/scripts/run_exec_oracles.sh
//
// Every bit must be 1 (expect 0xFF).  Failing bits show the affected shapes:
// the mis-scaled forms emit `mul <r>,<r>,sizeof(TNode)` on `p` before the load,
// i.e. `K + p->pt` is compiled like `(K + p)->pt`.
class TNode
{
  I64 a, b, c;
  U8 pt;
};

I64 g_v;

U0 Sink8(TNode *n, I64 t1, I64 r1, I64 d1, I64 t2, I64 r2, I64 d2, I64 rip)
{
  n = n;
  r1 = r1;
  d1 = d1;
  r2 = r2;
  d2 = d2;
  rip = rip;
  g_v = t1 << 32 | t2;
}

U0 Sink4(TNode *n, I64 t1, I64 r1, I64 d1)
{
  n = n;
  r1 = r1;
  d1 = d1;
  g_v = t1;
}

U0 Sink2(TNode *n, I64 t1)
{
  n = n;
  g_v = t1;
}

I64 Ret(TNode *n)
{
  return 0x800 + n->pt;
}

I64 main()
{
  I64 r = 0;
  TNode n;
  MemSet(&n, 0, sizeof(TNode));
  n.pt = 10;
  TNode *p = &n;
  // 1) plain return of the expression -- fine
  r += (Ret(p) == 0x080A) * 1;
  // 2) local var staged first -- fine (this is the workaround used in
  //    Compiler/BackA_RV.HC ICPostIncDec)
  I64 staged = 0x800 + p->pt;
  Sink8(p, staged, 10, 0, 0x400 + 10, 6, 0, 0);
  r += ((g_v >> 32) == 0x080A) * 2;
  // 3) inline in arg slot 2 of an 8-arg call -- MIS-SCALED
  Sink8(p, 0x800 + p->pt, 10, 0, 0x400 + 10, 6, 0, 0);
  r += ((g_v >> 32) == 0x080A) * 4;
  // 4) inline in arg slot 5 of an 8-arg call -- fine
  Sink8(p, 0x400 + 10, 10, 0, 0x800 + p->pt, 6, 0, 0);
  r += ((g_v & 0xFFFFFFFF) == 0x080A) * 8;
  // 5) inline in arg slot 2 of a 4-arg call
  Sink4(p, 0x800 + p->pt, 10, 0);
  r += (g_v == 0x080A) * 16;
  // 6) inline in arg slot 2 of a 2-arg call
  Sink2(p, 0x800 + p->pt);
  r += (g_v == 0x080A) * 32;
  // 7) same, but the pointer is not also an argument
  Sink2(NULL, 0x800 + p->pt);
  r += (g_v == 0x080A) * 64;
  // 8) same as 3 but with the member on the left of the +
  Sink8(p, p->pt + 0x800, 10, 0, 0x400 + 10, 6, 0, 0);
  r += ((g_v >> 32) == 0x080A) * 128;
  return r;
}
