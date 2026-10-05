// StrToUL is Kernel/Cfs/CfsStr.HC's strtoul(s, NULL, 0), and BASE 0 MEANS THE PREFIX DECIDES.
// cfe_es_startupscript.c converts every numeric field of a startup-script line through it, and
// the real scripts in tos/ use all three forms -- "0x40" for a priority, "16384" for a stack
// size, "0" for an exception action -- so reading 0755 as 755 would silently misconfigure a
// task. Each nibble below is one conversion, checked against what C's strtoul returns.
#include "/Kernel/Cfs/CfsStr.HC"
I64 main()
{
  I64 r = 0;
  // decimal
  r = (r << 4) | (StrToUL("9") == 9);
  r = (r << 4) | (StrToUL("16384") == 16384);
  // hex, both cases of the prefix and of the digits
  r = (r << 4) | (StrToUL("0x40") == 64);
  r = (r << 4) | (StrToUL("0X1f") == 31);
  r = (r << 4) | (StrToUL("0xAB") == 171);
  // OCTAL, which is the one a hand-written parser gets wrong
  r = (r << 4) | (StrToUL("0755") == 493);
  r = (r << 4) | (StrToUL("010") == 8);
  // "0" alone is zero, not an unterminated octal prefix
  r = (r << 4) | (StrToUL("0") == 0);
  // it stops at the first character that is not a digit in the base, and returns what it has
  r = (r << 4) | (StrToUL("12abc") == 12);
  r = (r << 4) | (StrToUL("0x1fg") == 31);
  r = (r << 4) | (StrToUL("09") == 0);
  // 9 is not an octal digit: stops immediately
  r = (r << 4) | (StrToUL("") == 0);
  r = (r << 4) | (StrToUL("abc") == 0);
  // leading whitespace and an explicit sign
  r = (r << 4) | (StrToUL("  42") == 42);
  r = (r << 4) | (StrToUL("+7") == 7);
  // NULL is zero rather than a fault, because a startup-script token can be absent
  r = (r << 4) | (StrToUL(NULL) == 0);
  // and IsGraph, which decides what counts as part of a token
  r = (r << 4) | (IsGraph('A') && IsGraph('/') && !IsGraph(' ') && !IsGraph('\t'));
  return r;
}
