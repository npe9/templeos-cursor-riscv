// A unit that defines `_start` must still run its top-level statements.
// A string literal's address is only known once the blob is laid out, so a file-scope
// initializer that names one compiles to a store rather than to data bytes. The AOT used to
// drop that whole statement stream whenever `_start` was present, silently zeroing every such
// table: bootstrap/seed/disasm.hc RN/FRN read back as "(null)" for every register in
// repl-holyc, and asm_complete.hc / asm_doc.hc offered nothing to Tab.
// Both shapes are covered — scalar `U8 *S = "…"` and aggregate `U8 *T[N] = {…}`.
// ORACLE 00000000000000c4 = 'a' + 'c'; a dropped initializer answers 0 instead.
U8 *S1 = "ab";
U8 *S2 = "cd";
U8 *Tbl[2] = {"ef", "gh"};
I64 Chk()
{
  if (S1 == 0)
    return 0;
  if (S2 == 0)
    return 0;
  if (Tbl[0] == 0)
    return 0;
  if (Tbl[1] == 0)
    return 0;
  return *S1 + *S2;
}
// The harness enters the blob at offset 0 with ra = its own return site. Park ra in s0, which
// every HolyC callee saves, rather than on the stack: `call` inside asm{} also leaves the
// callee's result on the eval stack.
asm {
	_start::
	mv	s0, ra
	call	Chk
	mv	ra, s0
	ret
}
