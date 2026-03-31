// Parity: array of class/struct-like objects
class Item {
  I64 k;
};

I64 main() {
  Item a[3];
  a[0].k = 1;
  a[1].k = 2;
  a[2].k = 4;
  return a[0].k + a[1].k + a[2].k;
}
