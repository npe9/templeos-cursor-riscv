// KThinQSortStubs.HC — RV_THIN_LOADER: drop QSort (~5 KiB). DirEntry sort lives
// in gated MakeBlkDev; SoftCall QSortSoft owns real QSortI64 in Kernel.BIN.
#ifndef K_THIN_QSORT_STUBS_HC
#define K_THIN_QSORT_STUBS_HC
U0 QSortI64(I64 *base, I64 num, I64 (*fp_compare)(I64 e1, I64 e2))
{
  no_warn base;
  no_warn num;
  no_warn fp_compare;
}

U0 QSort(U8 *base, I64 num, I64 width, I64 (*fp_compare)(U8 *e1, U8 *e2))
{
  no_warn base;
  no_warn num;
  no_warn width;
  no_warn fp_compare;
}
#endif
