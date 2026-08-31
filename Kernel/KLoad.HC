// Load .BIN modules (CBinFile / TOSB). Host AOT: do not use `*src(U32 *)++` —
// that advances the U8* by 8 on RV (pointer width), not 4. Use MemCpy + src+=4.

U32 LoadU32(U8 **_src)
{
  U32 v;
  MemCpy(&v,*_src,4);
  *_src+=4;
  return v;
}

I64 LoadI32(U8 **_src)
{
  I32 v;
  MemCpy(&v,*_src,4);
  *_src+=4;
  return v;
}

I64 LoadI64(U8 **_src)
{
  I64 v;
  MemCpy(&v,*_src,8);
  *_src+=8;
  return v;
}

U0 LoadOneImport(U8 **_src,U8 *module_base,I64 ld_flags)
{
  U8 *src=*_src,*ptr2,*st_ptr;
  I64 i,etype,off,val;
  CHashExport *tmpex=NULL;
  CHashImport *tmpiss;
  Bool first=TRUE;

  while (etype=*src++) {
    i=LoadU32(&src);
    st_ptr=src;
    src+=StrLen(st_ptr)+1;
    if (*st_ptr) {
      if (!first) {
	*_src=st_ptr-5;
	return;
      } else {
	first=FALSE;
	if (!(tmpex=HashFind(st_ptr,
	      Fs->hash_table,HTG_ALL-HTT_IMPORT_SYS_SYM))) {
	  if (!(ld_flags & LDF_SILENT))
	    "Unresolved Reference:%s\n",st_ptr;
	  tmpiss=CAlloc(sizeof(CHashImport));
	  tmpiss->str=StrNew(st_ptr);
	  tmpiss->type=HTT_IMPORT_SYS_SYM;
	  tmpiss->module_header_entry=st_ptr-5;
	  tmpiss->module_base=module_base;
	  HashAdd(tmpiss,Fs->hash_table);
	}
      }
    }
    if (tmpex) {
      off=i;
      ptr2=module_base+off;
      if (tmpex->type & HTT_FUN)
	val=tmpex(CHashFun *)->exe_addr;
      else if (tmpex->type & HTT_GLBL_VAR)
	val=tmpex(CHashGlblVar *)->data_addr;
      else
	val=tmpex->val;
      if (etype==IET_REL_I8) *ptr2(U8 *)=val-ptr2-1;
      else if (etype==IET_IMM_U8) *ptr2(U8 *)=val;
      else if (etype==IET_REL_I16) *ptr2(U16 *)=val-ptr2-2;
      else if (etype==IET_IMM_U16) *ptr2(U16 *)=val;
      else if (etype==IET_REL_I32) *ptr2(U32 *)=val-ptr2-4;
      else if (etype==IET_IMM_U32) *ptr2(U32 *)=val;
      else if (etype==IET_REL_I64) *ptr2(I64 *)=val-ptr2-8;
      else if (etype==IET_IMM_I64) *ptr2(I64 *)=val;
    }
  }
  *_src=src-1;
}

U0 SysSymImportsResolve(U8 *st_ptr,I64 ld_flags=0)
{
  CHashImport *tmpiss;
  U8 *ptr;
  while (tmpiss=HashSingleTableFind(st_ptr,
	Fs->hash_table,HTT_IMPORT_SYS_SYM)) {
    ptr=tmpiss->module_header_entry;
    LoadOneImport(&ptr,tmpiss->module_base,ld_flags);
    tmpiss->type=HTT_INVALID;
  }
}

U0 LoadPass1(U8 *src,U8 *module_base,I64 ld_flags)
{//if/else (not switch/start/end): host AOT miscompiles TempleOS switch ranges here.
  U8 *ptr2,*ptr3,*st_ptr;
  I64 i,j,cnt,etype;
  CHashExport *tmpex=NULL;
  while (etype=*src++) {
    i=LoadU32(&src);
    st_ptr=src;
    src+=StrLen(st_ptr)+1;
    if (etype==IET_REL32_EXPORT||etype==IET_IMM32_EXPORT||
	etype==IET_REL64_EXPORT||etype==IET_IMM64_EXPORT) {
      tmpex=CAlloc(sizeof(CHashExport));
      tmpex->str=StrNew(st_ptr);
      tmpex->type=HTT_EXPORT_SYS_SYM|HTF_IMM;
      if (etype==IET_IMM32_EXPORT||etype==IET_IMM64_EXPORT)
	tmpex->val=i;
      else
	tmpex->val=i+module_base;
      HashAdd(tmpex,Fs->hash_table);
      SysSymImportsResolve(st_ptr,ld_flags);
    } else if (etype>=IET_REL_I0 && etype<=IET_IMM_I64) {
      src=st_ptr-5;
      LoadOneImport(&src,module_base,ld_flags);
    } else if (etype==IET_ABS_ADDR) {
      if (ld_flags & LDF_NO_ABSS)
	src+=i*sizeof(U32);
      else {
	cnt=i;
	for (j=0;j<cnt;j++) {
	  ptr2=module_base+LoadU32(&src);
	  *ptr2(U32 *)+=module_base;
	}
      }
    } else if (etype==IET_CODE_HEAP||etype==IET_ZEROED_CODE_HEAP) {
      if (etype==IET_CODE_HEAP)
	ptr3=MAlloc(LoadI32(&src),Fs->code_heap);
      else
	ptr3=CAlloc(LoadI32(&src),Fs->code_heap);
      if (*st_ptr) {
	tmpex=CAlloc(sizeof(CHashExport));
	tmpex->str=StrNew(st_ptr);
	tmpex->type=HTT_EXPORT_SYS_SYM|HTF_IMM;
	tmpex->val=ptr3;
	HashAdd(tmpex,Fs->hash_table);
      }
      cnt=i;
      for (j=0;j<cnt;j++) {
	ptr2=module_base+LoadU32(&src);
	*ptr2(I32 *)+=ptr3;
      }
    } else if (etype==IET_DATA_HEAP||etype==IET_ZEROED_DATA_HEAP) {
      if (etype==IET_DATA_HEAP)
	ptr3=MAlloc(LoadI64(&src));
      else
	ptr3=CAlloc(LoadI64(&src));
      if (*st_ptr) {
	tmpex=CAlloc(sizeof(CHashExport));
	tmpex->str=StrNew(st_ptr);
	tmpex->type=HTT_EXPORT_SYS_SYM|HTF_IMM;
	tmpex->val=ptr3;
	HashAdd(tmpex,Fs->hash_table);
      }
      cnt=i;
      for (j=0;j<cnt;j++) {
	ptr2=module_base+LoadU32(&src);
	*ptr2(I64 *)+=ptr3;
      }
    }
  }
}

U0 LoadPass2(U8 *src,U8 *module_base,I64)
{
  U8 *st_ptr;
  I64 i,etype;
  while (etype=*src++) {
    i=LoadU32(&src);
    st_ptr=src;
    src+=StrLen(st_ptr)+1;
    if (etype==IET_MAIN)
      Call(i+module_base);
    else if (etype==IET_ABS_ADDR)
      src+=sizeof(U32)*i;
    else if (etype==IET_CODE_HEAP||etype==IET_ZEROED_CODE_HEAP)
      src+=4+sizeof(U32)*i;
    else if (etype==IET_DATA_HEAP||etype==IET_ZEROED_DATA_HEAP)
      src+=8+sizeof(U32)*i;
  }
}

CBinFile *LoadPass(CBinFile *bfh,I64 size,U8 *absname_for_hash,I64 ld_flags=0,
	CBinFile *bfh_addr=INVALID_PTR)
{//Shared Load body: patch + optional MAIN. Caller owns/frees input `bfh` unless in-place.
  U8 *module_base,*fbuf;
  I64 module_align,misalignment;

  module_align=1<<bfh->module_align_bits;
  if (!module_align || bfh->bin_signature!=BIN_SIGNATURE_VAL)
    throw('BinModul');

  if (bfh_addr==INVALID_PTR) {
    if (bfh->org==INVALID_PTR) {
      misalignment=module_align-sizeof(CBinFile);
      if (misalignment<0)
	misalignment&=module_align-1;
      if (Fs->code_heap!=Fs->data_heap) {
	if (module_align<16)
	  module_align=16;
	bfh_addr=MAllocAligned(size,module_align,Fs->code_heap,misalignment);
      } else if (module_align>8)
	bfh_addr=MAllocAligned(size,module_align,,misalignment);
      else {
	bfh_addr=bfh;
	goto lo_skip;
      }
    } else
      bfh_addr=bfh->org;
  }
  if (bfh_addr!=bfh) {
    MemCpy(bfh_addr,bfh,size);
    Free(bfh);
  }

  lo_skip:
  module_base=bfh_addr(U8 *)+sizeof(CBinFile);

  if (absname_for_hash) {
    fbuf=StrNew(absname_for_hash);
    FileExtRem(fbuf);
    if (fbuf[1]==':' && StrLen(fbuf)>2)
      HashGenericAdd(fbuf+2,HTT_MODULE|HTF_PUBLIC,bfh_addr);
    Free(fbuf);
  }
  LoadPass1(bfh_addr(U8 *)+bfh_addr->patch_table_offset,module_base,ld_flags);
  if (!(ld_flags&LDF_JUST_LOAD))
    LoadPass2(bfh_addr(U8 *)+bfh_addr->patch_table_offset,module_base,ld_flags);
  return bfh_addr;
}

CBinFile *LoadBuf(U8 *absname,CBinFile *src,I64 size,I64 ld_flags=0)
{//Load an in-memory TOSB (e.g. linked Compiler.BIN at RV_FULL_CMP_BIN).
  CBinFile *bfh;
  if (!src || size<sizeof(CBinFile) || src->bin_signature!=BIN_SIGNATURE_VAL)
    return NULL;
  bfh=MAlloc(size);
  MemCpy(bfh,src,size);
  return LoadPass(bfh,size,absname,ld_flags,INVALID_PTR);
}

CBinFile *Load(U8 *filename,I64 ld_flags=0,CBinFile *bfh_addr=INVALID_PTR)
{//Load a .BIN file module into memory.
//bfh_addr==INVALID_PTR means don't care what load addr.
  U8 *fbuf,*absname;
  I64 size;
  CBinFile *bfh,*res;

  fbuf=ExtDft(filename,"BIN.Z");
  if (!(bfh=FileRead(fbuf,&size))) {
    Free(fbuf);
    return NULL;
  }
  absname=FileNameAbs(fbuf);
  Free(fbuf);
  res=LoadPass(bfh,size,absname,ld_flags,bfh_addr);
  Free(absname);
  return res;
}

U0 LoadKernel()
{
  HashGenericAdd(KERNEL_MODULE_NAME,HTT_MODULE|HTF_PUBLIC,
	mem_boot_base-sizeof(CBinFile));

  //Abs patches done here $LK,"CPatchTableAbsAddr",A="FF:D:/Kernel/KStart32.HC,CPatchTableAbsAddr"$.
  LoadPass1(sys_boot_patch_table_base,mem_boot_base,LDF_NO_ABSS|LDF_SILENT);

  //No main routines
  //  LoadPass2(sys_boot_patch_table_base,mem_boot_base,0);
}
