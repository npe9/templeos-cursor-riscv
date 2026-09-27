// sizeof(<class> *) must be 8, not sizeof(<class>).
//
// ParseType keeps the class in last_type_class for `Class *` (p->member needs it), and the
// expression-context sizeof preferred that class's size over the star count: sizeof(U8 *) was 8
// only because U8 has no class size to prefer, while sizeof(CDocEntry *) answered 208. Live in the
// shipping image: Compiler/RVExePubs.HC sets member sizes from sizeof(CHashTable *) etc., and
// Sort() passed QSort a 208-byte width for an array of pointers, which is why it trapped.
// Bit 16 exercises the constant-expression arm (array dimension) separately from the value arm.
class CBig { U8 buf[200]; };
I64 main() {
  I64 r = 0;
  U8 arr[sizeof(CBig *)];
  if (sizeof(CBig *) == 8)  r |= 1;
  if (sizeof(U8 *) == 8)    r |= 2;
  if (sizeof(CBig) == 200)  r |= 4;
  if (sizeof(U0 *) == 8)    r |= 8;
  if (sizeof(arr) == 8)     r |= 16;
  return r;
}
