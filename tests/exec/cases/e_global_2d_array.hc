// Multi-dimensional GLOBAL arrays: declaration, subscript (with per-dimension stride), and flat
// initializers. Previously only 1-D global arrays parsed; 2-D worked only for locals.
I64 gm[3][4];
I64 gt[2][2][2];
U16 gh[2][3];
I64 gi[2][3] = {1, 2, 3, 4, 5, 6};
// flat initializer fills row-major storage
I64 gn[2][3] = {{1, 2, 3}, {4, 5, 6}};
// nested-brace initializer, one group per row
I64 main()
{
  I64 i, j;
  for (i = 0; i < 3; i++)
    for (j = 0; j < 4; j++)
      gm[i][j] = i * 10 + j;
  gt[1][0][1] = 77;
  gt[0][1][0] = 5;
  gh[1][2] = 300;
  gh[0][0] = 7;
  return (gm[2][3] == 23) * 1 + (gm[1][2] == 12) * 2 + (gt[1][0][1] == 77) * 4 + (gt[0][1][0] == 5) * 8 + (gh[1][2] == 300) * 16 + (gh[0][0] == 7) * 32 + (gi[0][0] == 1) * 64 + (gi[1][2] == 6) * 128 + (gn[0][0] == 1) * 256 + (gn[1][2] == 6) * 512;
  // 0x3ff
}
