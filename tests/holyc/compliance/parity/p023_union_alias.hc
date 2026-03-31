// Parity: union reads/writes across members
union U {
  I64 a;
  I32 b;
};

I64 main() {
  U u;
  u.a = 0x1122334455667788;
  return (I64)u.b;
}
