// `&Fn` where Fn is an extern/runtime function must yield the CODE address (the import
// slot's contents), not the slot itself. The unary-& lvalue path retracted the trailing
// IC_DEREF that EmitFnAddress emits, so a call through the pointer jumped into the GOT
// (illegal instruction) — first seen with the guest compiler's &RVF64Sin.
I64 main()
{
  I64 (*fp)(U8 *s) = &StrLen;
  I64 (*fq)(U8 *s);
  fq = &StrLen;
  if (fp != fq)
    return 1;
  if ((*fp)("abcd") != 4)
    return 2;
  if (fq("xyz") != 3)
    return 3;
  return 0x2b;
}
