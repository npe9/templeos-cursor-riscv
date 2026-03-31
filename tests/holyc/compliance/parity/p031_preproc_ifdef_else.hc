// Parity: #ifdef / #else / #endif
#define FEATURE

I64 main() {
  I64 v = 0;
#ifdef FEATURE
  v = 10;
#else
  v = 20;
#endif
  return v;
}
