// Parity: class with multiple methods
class Acc {
  I64 n;

  I64 Get() {
    return n;
  }

  U0 Set(I64 v) {
    n = v;
  }

  I64 Add(I64 d) {
    n = n + d;
    return n;
  }
};

I64 main() {
  Acc a;
  a.Set(10);
  a.Add(5);
  return a.Get();
}
