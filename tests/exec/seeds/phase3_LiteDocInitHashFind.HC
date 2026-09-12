// Soft tip Soft Cmp: HashFind(Fs->hash_table) - Soft AOT _intern Fs via asm_hash
// plant (RVCmpWireAsmHash→RVExePubInternFsGsIn). Soft Call remat of Fs uses Soft
// AOT abs-U64 embed of Compiler &Fs (PC-rel to external &Fs hung Soft Call Load).
#define HTT_DEFINE_STR 0x4
import I64 HashFind(U8 *needle, I64 table, I64 mask);
public I64 AdamLiteDocInitHashFindProbe()
{
  if (Fs && Fs->hash_table) {
    if (HashFind("SOFT_DOCINIT_HF", Fs->hash_table, HTT_DEFINE_STR))
      return 2;
    return 1;
  }
  return 0;
}
