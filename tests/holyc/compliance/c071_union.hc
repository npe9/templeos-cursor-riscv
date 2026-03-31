union U {
  I64 a;
  I32 b;
};

I64 main() {
  U u;
  u.a = 1;
  return u.a;
}
