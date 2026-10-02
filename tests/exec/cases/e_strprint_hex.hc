// StrPrintNV's hex and field-width conversions must match C's snprintf exactly.
//
// Why this is pinned rather than left to the cFS gate. Until EVS, every formatted string in the
// translation was deliberately OUTSIDE the differential comparison: CFE_ES_WriteToSysLog takes a
// plain string here, and the event wording was a stub's business. EVS ends that. Its event text
// is built with vsnprintf into the 122-byte packet payload and the packet IS the message, so
// either the formatter agrees with C character for character or the transcript fails for a
// reason that has nothing to do with the translation.
//
// The conversions cFS actually uses, counted across EVS's three sources: %s (14), %d (6),
// %u (5), %ld (2), %08x (2), %08X (1), and SB adds %zu. The hex, width and 'z' forms were
// added to CfsStr.HC for
// those, and this case is the check on them. The expected value is not a hash of a formatter:
// every line here was run through C's snprintf and compared character by character first.
#include "/Kernel/Cfs/CfsStr.HC"
I64 StrLenX(U8 *s)
{
  I64 n = 0;
  while (s[n])
    n++;
  return n;
}
// Fold a string into the accumulator so a wrong character anywhere changes the answer: a sum
// alone would miss a transposition, so each byte is also weighted by its position.
I64 Fold(I64 acc, U8 *s)
{
  I64 i = 0;
  while (s[i]) {
    acc = acc * 33 + s[i] * (i + 1);
    acc = acc & 0xFFFFFFFF;
    // masked EVERY step, so neither side can rely on wraparound
    i++;
  }
  acc = acc * 31 + StrLenX(s);
  return acc & 0xFFFFFFFF;
}

I64 main()
{
  U8 b[160];
  I64 r = 0;
  I64 n;
  // the four conversions that existed before EVS, unchanged
  StrPrintN(b, sizeof(b), "a=%s u=%u d=%d ld=%ld", "str", 42, -7, -1);
  r = Fold(r, b);
  // C: a=str u=42 d=-7 ld=-1
  // lowercase and uppercase hex, bare
  StrPrintN(b, sizeof(b), "[%x][%X]", 255, 255);
  r = Fold(r, b);
  // C: [ff][FF]
  // zero-padded hex, which is the form every cFS status and id is printed with
  StrPrintN(b, sizeof(b), "[%08x][%08X]", 0xabc, 0xdeadbeef);
  r = Fold(r, b);
  // C: [00000abc][DEADBEEF]
  // space-padded and zero-padded decimal: the width applies to %d and %u too
  StrPrintN(b, sizeof(b), "[%5d][%05d][%5u]", 42, 42, 42);
  r = Fold(r, b);
  // C: [   42][00042][   42]
  // a negative number inside a field width: C counts the sign INSIDE the width
  StrPrintN(b, sizeof(b), "[%6d][%06d]", -42, -42);
  r = Fold(r, b);
  // C: [   -42][-00042]
  // the extremes: zero, and the most negative 32-bit value
  StrPrintN(b, sizeof(b), "[%u][%d][%x]", 0, -2147483648, 0);
  r = Fold(r, b);
  // C: [0][-2147483648][0]
  // a width SHORTER than the number does not truncate it
  StrPrintN(b, sizeof(b), "[%2d][%02x]", 123456, 0xabcdef);
  r = Fold(r, b);
  // C: [123456][abcdef]
  // the return value is C's: the length that WOULD have been written, even past the buffer
  n = StrPrintN(b, 8, "0123456789abcdef");
  r = r * 1000 + n;
  // 16
  r = r * 100 + StrLenX(b);
  // 7 -- Size-1 characters plus the NUL
  // Size == 0 writes nothing at all and still reports the full length
  b[0] = 'Z';
  n = StrPrintN(b, 0, "abcd");
  r = r * 100 + n;
  // 4
  r = r * 10 + (b[0] == 'Z');
  // 1 -- untouched
  // THE 'll' LENGTH MODIFIER IS 64-BIT. A %x or %u is masked to 32 bits, because every cFS
  // call site that uses one puts an (unsigned int) cast on the argument -- but %llX must not
  // be, and TA prints a 64-bit affinity mask with exactly "0x%016llX". In a one-core
  // configuration that mask fits in 32 bits, so the truncation agreed with C's output and was
  // invisible until a value above 2^32 went through it.
  StrPrintN(b, sizeof(b), "[%016llX][%llx][%llu]", 0x123456789ABCDEF0, 0x100000000, 0xFEDCBA9876543210);
  r = Fold(r, b);
  // C: [123456789ABCDEF0][100000000][18364758544493064720]
  // and the 32-bit forms still mask, which is the behaviour the cFS call sites rely on
  StrPrintN(b, sizeof(b), "[%x][%08X]", 0x123456789A, 0x123456789A);
  r = Fold(r, b);
  // C (with the (unsigned int) cast cFS puts there): [3456789a][3456789A]
  // THE 'z' LENGTH MODIFIER IS size_t, AND THE REASON IT IS HERE IS THE ARGUMENT SHIFT. An
  // unhandled conversion comes out literally AND CONSUMES NOTHING, so when cfe_sb_api.c logs
  // "requested size %zu larger than allowed %d" the %d would have taken the size and the line
  // would be wrong in two places at once rather than one. On LP64, %zu is %lu.
  StrPrintN(b, sizeof(b), "[%zu][%zx][%08zu]", 1234567890123, 0xabcdef, 42);
  r = Fold(r, b);
  // C (measured with snprintf): [1234567890123][abcdef][00000042]
  // an unhandled conversion is emitted literally rather than dropped, so it shows up in a
  // transcript. It consumes no argument, which is why nothing follows it here: a %s after a
  // %q would take the %q's argument and dereference an integer as a pointer.
  StrPrintN(b, sizeof(b), "[%q]");
  r = Fold(r, b);
  // [%q]
  return r & 0xFFFFFFFFFFFF;
}
