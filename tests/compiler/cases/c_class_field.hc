// Class field store + load through pointer.
class Pt
{
  I64 x;
  I64 y;
};

I64 main()
{
  Pt p;
  Pt *q;
  q = &p;
  q->x = 40;
  q->y = 2;
  return q->x + q->y;
}
