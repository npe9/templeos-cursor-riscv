// KCmpStubsRV.HC — HolyC stubs for x86 asm / Adam symbols needed by Compiler_RV ExePutS.
// Included from Kernel_RV.PRJ so in-image Compiler_RV_Body does not hang on unresolved imports.
U0 HashAddAfter(CHash *tmph, CHash *pred, CHashTable *table)
{
  // Insert tmph after pred in the bucket chain (x86 _HASH_ADD_AFTER).
  no_warn table;
  if (!tmph || !pred)
    return;
  tmph->next = pred->next;
  pred->next = tmph;
}

I64 CallExtStr(U8 *name,...)
{
  // Adam extension call — unused on RV kernel smoke; return 0.
  no_warn name;
  return 0;
}

I64 CallExtNum(I64 num,...)
{
  no_warn num;
  return 0;
}

I64 LastFun(I64 argc, I64 *argv)
{
  no_warn argc;
  no_warn argv;
  return 0;
}

CHeapCtrl *MHeapCtrl(U8 *src)
{
  no_warn src;
  if (Fs)
    return Fs->data_heap;
  return NULL;
}
Bool DocUnlock(CDoc *doc);
// real: Kernel/RVDoc.HC (P2)
U8 *Doc2PlainText(CDoc *doc, CDocEntry *doc_e)
{
  no_warn doc;
  no_warn doc_e;
  return NULL;
}

U0 DocBinsValidate(CDoc *doc)
{
  no_warn doc;
}
// DocDel / DocNew / DocLoad / DocPrint / DocPutLine / DocSize / DocWrite / DocSave
// → Kernel/RVDoc.HC (P2 minimal CDoc entry stream)
U0 Ed(U8 *filename = NULL, I64 edf_dof_flags = 0)
{
  no_warn filename;
  no_warn edf_dof_flags;
}

U8 *ArcEntryGet(U8 *src, I64 *_size)
{
  no_warn src;
  if (_size)
    *_size = 0;
  return NULL;
}
/* Real call targets for Compiler.BIN IMM_I64 imports of _intern ops.
 * Host AOT of Compiler_RV turns Bt/QueInit/… into import slots; &Bt is not a jalr entry.
 * These wrappers compile to IC_* intrinsics and are what RVCmpExportImports exports. */
Bool RVBt(U8 *bf, I64 n)
{
  return Bt(bf, n);
}

Bool RVBts(U8 *bf, I64 n)
{
  return Bts(bf, n);
}

Bool RVBtr(U8 *bf, I64 n)
{
  return Btr(bf, n);
}

Bool RVLBts(U8 *bf, I64 n)
{
  return LBts(bf, n);
}

Bool RVLBtr(U8 *bf, I64 n)
{
  return LBtr(bf, n);
}

I64 RVBsf(I64 i)
{
  return Bsf(i);
}

I64 RVBsr(I64 i)
{
  return Bsr(i);
}

I64 RVToUpper(U8 ch)
{
  return ToUpper(ch);
}

I64 RVStrLen(U8 *st)
{
  return StrLen(st);
}

I64 RVMaxI64(I64 a, I64 b)
{
  return MaxI64(a, b);
}

I64 RVMinI64(I64 a, I64 b)
{
  return MinI64(a, b);
}

U0 RVQueInit(CQue *head)
{
  QueInit(head);
}

U0 RVQueIns(CQue *entry, CQue *pred)
{
  QueIns(entry, pred);
}

U0 RVQueRem(CQue *entry)
{
  QueRem(entry);
}

U0 RVSwapI64(I64 *a, I64 *b)
{
  SwapI64(a, b);
}
/* KUtilsRV asm labels: &MemSet is not a reliable jalr entry for Load()'d IMM_I64. */
U8 *RVMemSet(U8 *dst, I64 dat, I64 size)
{
  return MemSet(dst, dat, size);
}

U8 *RVMemCpy(U8 *dst, U8 *src, I64 size)
{
  return MemCpy(dst, src, size);
}

I64 *RVMemSetI64(I64 *dst, I64 v, I64 cnt)
{
  return MemSetI64(dst, v, cnt);
}

I64 RVStrCmp(U8 *a, U8 *b)
{
  return StrCmp(a, b);
}

U8 *RVStrCpy(U8 *dst, U8 *src)
{
  return StrCpy(dst, src);
}

I64 RVClampI64(I64 i, I64 lo, I64 hi)
{
  return ClampI64(i, lo, hi);
}

Bool RVBEqu(U8 *dst, U8 *src, I64 cnt)
{
  return BEqu(dst, src, cnt);
}

U8 *RVStrIMatch(U8 *needle, U8 *haystack)
{
  return StrIMatch(needle, haystack);
}
/* Call is oracle/harness import; &Call is the slot, not a jalr target. */
I64 RVCall(U8 *machine_code)
{
  return Call(machine_code);
}
/* Guest eval-SP is junk at CALL_IMPORT (SP>>28==0); FP ok.
 * SP=FP-2048 for HolyC ENTER; leave SP for caller to rebuild after RET. */
asm {
	_RV_HC_CALL::
	// Guest ra at FP-2040 (host SP=FP-2048 grows down; s-regs not preserved)
	SD	RA,-2040(S0)
	ADDI	SP,S0,-2048
	AUIPC	RA,0
	ADDI	RA,RA,12
	JALR	ZERO,0(T1)
	LD	RA,-2040(S0)
	RET
	_RV_RET42::
	LI	A0,42
	RET
}
_extern _RV_HC_CALL U0 RVHCCall();
_extern _RV_RET42 I64 RVRet42Asm();
I64 RVHCRet41()
{
  return 41;
}

I64 RVHCAdd1(I64 x)
{
  return x + 1;
}
