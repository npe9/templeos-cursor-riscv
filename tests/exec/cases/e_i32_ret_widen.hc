// An I32 function's return value is NOT sign-extended when consumed directly, but IS when it
// passes through an I32 variable. The two disagree, which makes it a defect rather than a choice.
//
// Found by the NASA cFS translation's differential oracle: cFE returns status codes as int32, and
// CFE_MSG_WRONG_MSG_TYPE is 0xCA00000D. The C prints -905969651; the HolyC translation printed
// 3388997645 for the same call, and only on the path where the return was used directly.
//
// The generated code shows it. For `I32 NegI32() { return 0xCA00000D; }`:
//     lui  a0,0xca000
//     addi a0,a0,13        a0 = 0xffffffffca00000d   correct so far
//     slli a0,a0,0x20
//     srli a0,a0,0x20      LOGICAL shift: zero-extends a SIGNED value
// The zero-extension is EmitLoadImm64 loading the literal (right, for a U32 constant); what is
// missing is the conversion of the value TO the declared return type on the way out. C converts
// `return 0xCA00000D` from an int32 function to -905969651 and the ABI keeps it sign-extended.
//
// Expect 0x2 TODAY: only the via-variable path sign-extends. When the return path is fixed this
// becomes 0xf and the manifest entry changes with it -- that flip is the point of the case.
//   bit 1  direct return used as I64 is negative
//   bit 2  same value through an I32 variable is negative
//   bit 4  the two agree
//   bit 8  direct return as a function argument is negative
I32 NegI32()
{
  return 0xCA00000D;
}

I64 TakeI64(I64 v)
{
  return v;
}

I64 main()
{
  I64 r = 0;
  I64 direct, through;
  I32 via;
  direct = NegI32();
  via = NegI32();
  through = via;
  if (direct < 0)
    r |= 1;
  if (through < 0)
    r |= 2;
  if (direct == through)
    r |= 4;
  if (TakeI64(NegI32()) < 0)
    r |= 8;
  return r;
}
