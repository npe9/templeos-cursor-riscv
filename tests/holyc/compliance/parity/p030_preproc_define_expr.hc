// Parity: #define constant folding into expressions
#define MAGIC 0x41
#define TWICE(x) ((x) + (x))

I64 main() {
  return TWICE(MAGIC) + 1;
}
