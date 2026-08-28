// Regression for the zero-size-marker struct-layout bug: a `U0` member (a position marker like
// CDirEntry.start / CMemUsed.start in TempleOS) must occupy ZERO bytes, so the field after it shares
// its offset. Pre-fix a U0 member wrongly took 8 bytes: offset(b) was 16 and sizeof was 24, giving
// 0x118; fixed, offset(b)=8 and sizeof=16, giving 0x88.
class ZMark { I64 a; U0 mark; I64 b; };
I64 main()
{
  return offset(ZMark.b)*16 + sizeof(ZMark);   // fixed: 8*16 + 16 = 0x90
}
