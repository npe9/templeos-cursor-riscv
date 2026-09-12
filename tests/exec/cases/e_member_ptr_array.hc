// Array-of-pointers class member: `T *arr[N]` elements are 8-byte pointers, not T.
// The host used the pointee class size as the stride, so arr[k]= landed k*sizeof(T)
// bytes in — past the struct into unrelated globals (the guest compiler's
// cmp.internal_types[] trashed char_bmp_hex_numeric; only 0xF lexed).
class CBig
{
  I64 a, b, c, d, e, f, g, h;   // 64 bytes: stride bug would step 64 per index
};
class CHolder
{
  I64 head;
  CBig *arr[4];
  I64 tail;
};
I64 main()
{
  CHolder h;
  CBig x, y;
  x.a = 5; y.a = 7;
  h.head = 0x11; h.tail = 0x22;
  h.arr[0] = &x; h.arr[1] = &y; h.arr[2] = &x; h.arr[3] = &y;
  if (h.head != 0x11 || h.tail != 0x22) return 1;      // neighbours intact
  if (h.arr[1] != &y || h.arr[3] != &y) return 2;
  if (h.arr[1]->a != 7 || h.arr[2]->a != 5) return 3;
  if (&h.arr[1] - &h.arr[0] != 1) return 4;            // element stride is one pointer
  return 0x3c;
}
