// Parity: class member is another class (aggregate layout)
class Inner {
  I64 v;
};

class Outer {
  Inner i;
  I64 tag;
};

I64 main() {
  Outer o;
  o.i.v = 40;
  o.tag = 2;
  return o.i.v + o.tag;
}
