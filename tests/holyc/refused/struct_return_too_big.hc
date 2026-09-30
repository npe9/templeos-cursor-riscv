// Must be REFUSED at compile time, not miscompiled. See docs/HOLYC_STRUCT_LIMITS.md: there is no
// struct-return ABI, so a class larger than 8 bytes comes back truncated -- a 16-byte one hands
// the caller a field pair where a pointer belongs, which faults on first use.
class S16 { I64 a; I64 b; };
S16 TooBig()
{
  S16 v;
  v.a = 1;
  v.b = 2;
  return v;
}
I64 main() { S16 x; x = TooBig; return x.a; }
