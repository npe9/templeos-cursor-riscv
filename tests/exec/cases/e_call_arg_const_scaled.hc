// A CONSTANT `A + B` IN A CALL ARGUMENT IS SCALED BY ANOTHER ARGUMENT'S POINTEE SIZE.
//
// This is a SILENT WRONG CONSTANT, with no diagnostic, and it is the same leak as limit 17 in
// docs/HOLYC_STRUCT_LIMITS.md -- there the arrow in `fn(args)->member` resolved against the
// FIRST ARGUMENT's class; here the pointer argument's POINTEE SIZE reaches a constant fold in
// a later argument and multiplies its right operand.
//
//     U0 Two(U32 *p, U32 v);
//     Two(r, (0 | ((0x10 + 1) << 16)) + slot);   // r is U32 *
//
// `0x10 + 1` is 17. The compiler emits `li a0,20` -- 16 + 1*4, where 4 is sizeof(U32), the
// pointee size of `r`. Changing only `r`'s type changes the constant and nothing else:
//
//     U8  *r  ->  li 17   (scale 1: correct by accident)
//     U16 *r  ->  li 18
//     U32 *r  ->  li 20
//     U64 *r  ->  li 24
//
// The rule is exactly `A + B*sizeof(*r)`, confirmed across five constant pairs:
// 0x10+1 -> 20, 0x20+1 -> 36, 3+4 -> 19, 100+7 -> 128, 1+1 -> 5.
//
// HOW IT WAS FOUND. cfe_es_api.c's differential driver plants ES's app table with
//     CFE_ES_AppRecordSetUsed(arp, CFE_ES_APPID_BASE + slot)
// where CFE_ES_APPID_BASE expands to `(CFE_RESOURCEID_MARK | ((OS_OBJECT_TYPE_USER + 1) <<
// CFE_RESOURCEID_SHIFT))`. The `OS_OBJECT_TYPE_USER + 1` inside it became OS_OBJECT_TYPE_USER +
// 4, so every app id was planted at base 0xC80000 instead of 0x110000. Nothing diagnosed it.
// CFE_ES_GetAppID then answered CFE_ES_ERR_RESOURCEID_NOT_VALID for a record that was sitting
// right there, and the failure surfaced as `CFE_TA_TaskInit: Call to CFE_ES_GetAppID Failed`
// -- two modules away from the arithmetic, exactly like the dropped (cpuaddr) cast in
// cfe_sb_priv.c that e_ptr_minus_int_scales.hc pins.
//
// THE WORKAROUND IS A LOCAL, the same one limit 17 takes: compute the value into a variable and
// pass the variable. That form is measured here too and is correct.
U32 Table8[64];
U32 Got;
U0 TakesPtrAndValue(U32 *p, U32 v)
{
  Got = v;
}

U0 TakesValueOnly(U32 v)
{
  Got = v;
}

I64 Bad(U32 slot)
{
  U32 *r = Table8;
  TakesPtrAndValue(r, (0 | ((0x10 + 1) << 16)) + slot);
  return Got;
}

I64 ViaLocal(U32 slot)
{
  U32 *r = Table8;
  U32 v = (0 | ((0x10 + 1) << 16)) + slot;
  TakesPtrAndValue(r, v);
  return Got;
}

I64 NoPointerArg(U32 slot)
{
  TakesValueOnly ((0 | ((0x10 + 1) << 16)) + slot);
  return Got;
}

I64 main()
{
  I64 bad, loc, nop;
  bad = Bad(1);
  loc = ViaLocal(1);
  nop = NoPointerArg(1);
  // Bits 16-23 of each, most significant first: the broken one, then the two correct forms.
  // 0x11 is right; the first is 0x14 today and becomes 0x11 when the leak is fixed, at which
  // point this case's pinned value changes to 0x111111 and the comment above becomes history.
  return (((bad >> 16) & 0xFF) << 16) | (((loc >> 16) & 0xFF) << 8) | ((nop >> 16) & 0xFF);
}
