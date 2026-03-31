// Parity: pointer to struct/class and ->
class Pt {
  I64 x;
  I64 y;
};

I64 main() {
  Pt p;
  Pt *q = &p;
  q->x = 6;
  q->y = 7;
  return q->x + q->y;
}
