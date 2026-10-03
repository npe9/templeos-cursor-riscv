// A CHAR ARRAY INITIALISED FROM A STRING LITERAL WORKS ONLY AS A LOCAL, AND ONLY UNBRACED.
//
// NASA writes this shape in cfe_es_api.c:
//
//     char AppName[OS_MAX_API_NAME]                      = { "UNKNOWN" };
//     char CDSName[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN] = { "" };
//
// Four spellings were measured and three of them are silently wrong -- no diagnostic, no
// refusal, just different bytes. The one that works is the LOCAL UNBRACED form, which is what
// the translation uses, and it also zero-fills the tail the way C guarantees.
//
//   LOCAL   U8 A[20] = "UNKNOWN";    characters, tail zeroed   <- correct, pinned below
//   LOCAL   U8 A[20] = {"UNKNOWN"};  garbage (0x18, then zeros)
//   GLOBAL  U8 G[20] = "UNKNOWN";    the string's ADDRESS written into the array bytes
//   GLOBAL  U8 G[20] = {"UNKNOWN"};  all zeros
//
// The global cases are the dangerous ones. A translation of `static const char TAG[] = "..."`
// would compile, run, and compare a pointer or a run of zeros against NASA's characters. The
// workaround is already in cfe_es_syslog.HC, which declares its FRAGMENT_TAG as a `U8 *` to a
// literal rather than an array -- and says there that the length matters, because NASA copies
// `sizeof(TAG) - 1` bytes and that number has to be written out by hand.
//
// See docs/HOLYC_STRUCT_LIMITS.md for the entry this case guards.
I64 Dirty()
{
  U8 junk[80];
  I64 i;
  for (i = 0; i < 80; i++)
    junk[i] = 0xAA;
  return junk[79];
}

I64 Probe()
{
  U8 A[20] = "UNKNOWN";
  U8 B[8] = "";
  I64 r = 0;
  I64 i;
  // The seven characters, most significant first.
  for (i = 0; i < 7; i++)
    r = r * 256 + A[i];
  // The terminator and the thirteen bytes after it must all be zero: C guarantees the tail of
  // a partially initialised array is zeroed, and that is what makes the StrNCpy below safe.
  for (i = 7; i < 20; i++)
    if (A[i] != 0)
      r += 0x1000000000000;
  // An EMPTY string literal has to zero the whole array, not just the first byte.
  for (i = 0; i < 8; i++)
    if (B[i] != 0)
      r += 0x2000000000000;
  return r;
}

I64 main()
{
  I64 d;
  // Dirty the stack first, so a zeroed tail cannot be a fresh-stack accident.
  d = Dirty();
  if (d != 0xAA)
    return 1;
  return Probe();
}
