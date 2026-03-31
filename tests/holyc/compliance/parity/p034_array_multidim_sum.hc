// Parity: 2D array walk
I64 main() {
  I64 m[2][3];
  I64 i;
  I64 j;
  I64 s = 0;
  for (i = 0; i < 2; i = i + 1)
    for (j = 0; j < 3; j = j + 1) {
      m[i][j] = i + j;
      s = s + m[i][j];
    }
  return s;
}
