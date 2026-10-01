// A BARE `FOO++` ON A NAME NOTHING DECLARED MUST BE A PARSE ERROR, not a skipped line.
//
// HolyC lets an x86 instruction be written bare at statement start (`MOV U64 [RSI],R13`), and
// parser.c recognises one by its shape: an all-upper-case name whose next token is not one of a
// short list. Everything else is taken for an opcode with an operand and THE WHOLE LINE IS
// SKIPPED with a note and a clean exit.
//
// Two things keep a variable out of that branch. One is a symbol-table check -- a name the
// compiler already knows as a variable is not an instruction -- and that one is witnessed by
// tests/exec/cases/e_upper_name_stmt.hc, whose all-caps ARRAY has a `[` after it that no
// operator list covers. The other is the list of modifying operators (`++ -- += -= *= /= &= |=
// ^= <<= >>= %=`), and a declared name cannot witness it, because the symbol check already
// saved that name. THIS is what witnesses it: `FOO` is declared nowhere, so the symbol check
// does not fire, and only `++` being in the operator list makes the compiler look at the line
// at all. Take the list out and this file compiles clean, with the typo silently discarded.
//
// docs/HOLYC_STRUCT_LIMITS.md #14.
I64 main()
{
  FOO++;
  return 0;
}
