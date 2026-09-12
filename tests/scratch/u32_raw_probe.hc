U32i union U32
{
  U8i u8[4];
};

I64 main()
{
  U32 *p;
  U32 arr[2];
  arr[0] = 1;
  arr[1] = 2;
  p = arr;
  // If *p / p[0] is 8-byte, writing should clobber arr[1]
  p[0] = 0x55AA55AA;
  if (arr[1] == 2) return 1; // neighbor intact → 4-byte store
  if (arr[1] == 0) return 2; // zeroed high → 8-byte store of zero-ext
  return 3; // other clobber
}
