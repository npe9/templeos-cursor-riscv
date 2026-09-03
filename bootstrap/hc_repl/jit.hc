// jit.hc -- HolyC-in-HolyC RISC-V JIT for the AOT REPL (expanded).
// Multi-arg (incl. >8), if/while/do/for, ++/--/+=, locals, arrays, pointers,
// classes, strings, globals, Run("file"), builtins. No host slots.
#define JIT_BASE 0x84000000
#define JIT_END  0x84F00000
#define JIT_GLOBB 0x83F00000
// Boot registers ~147 AOT symbols via JitAdd; leave headroom for Run/redefine.
#define JIT_FUN_MAX 256
#define JIT_NAME_MAX 32
#define JIT_SLOT 16
#define JIT_CLS_MAX 16
#define JIT_MEM_MAX 8
U8 *jit_at;
U8 jit_err;
U8 jit_id[JIT_NAME_MAX];
U8 *jit_src;
U8 jit_pname[16][JIT_NAME_MAX];
I64 jit_pargc;
I64 jit_argc;
// current function argc
I64 jit_frame;
// frame bytes
I64 jit_local_n;
U8 jit_lname[JIT_SLOT][JIT_NAME_MAX];
I64 jit_loff[JIT_SLOT];
// byte offset from s0 (negative)
I64 jit_lsize[JIT_SLOT];
I64 jit_next_local;
// next free slot index after params
class CJitFun
{
  U8 name[JIT_NAME_MAX];
  U8 *entry;
  I64 argc;
  I64 is_void;
};
CJitFun jit_funs[JIT_FUN_MAX];
I64 jit_nfun;
class CJitMem
{
  U8 name[JIT_NAME_MAX];
  I64 off;
  I64 size;
};

class CJitCls
{
  U8 name[JIT_NAME_MAX];
  I64 nmem;
  I64 size;
  CJitMem mem[JIT_MEM_MAX];
};
CJitCls jit_cls[JIT_CLS_MAX];
I64 jit_ncls;
class CJitGlob
{
  U8 name[JIT_NAME_MAX];
  I64 addr;
  I64 size;
};
CJitGlob jit_globs[64];
I64 jit_nglob;
U8 *jit_glob_brk;
U8 *jit_str_brk;
// grows down from JIT_END for string literals
I64 JitAdd(U8 *name, U8 *entry, I64 argc, I64 is_void);
// fwd
asm {
	JitFenceI::
	fencei
	ret
}

U0 JitCpy(U8 *d, U8 *s, I64 max)
{
  I64 n = 0;
  if (!d)
    return;
  if (!s) {
    *d = 0;
    return;
  }
  while (*s && n < max - 1) {
    *d = *s;
    d++;
    s++;
    n++;
  }
  *d = 0;
}

I64 JitSeq(U8 *a, U8 *b)
{
  if (!a)
    a = "";
  if (!b)
    b = "";
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return !*a && !*b;
}

U0 JitInit()
{
  I64 i;
  jit_at = JIT_BASE;
  jit_nfun = 0;
  jit_ncls = 0;
  jit_nglob = 0;
  jit_err = 0;
  jit_glob_brk = JIT_GLOBB;
  jit_str_brk = JIT_END;
  for (i = 0; i < JIT_FUN_MAX; i++)
    jit_funs[i].name[0] = 0;
  // Builtins → AOT HolyC addresses
  JitAdd("MAlloc", &MAlloc, 1, 0);
  JitAdd("Free", &Free, 1, 1);
  JitAdd("CAlloc", &CAlloc, 1, 0);
  JitAdd("StrLen", &StrLen, 1, 0);
  JitAdd("StrCpy", &StrCpy, 2, 1);
  JitAdd("StrCmp", &StrCmp, 2, 0);
  JitAdd("StrCat", &StrCat, 2, 1);
  JitAdd("PutS", &PutS, 1, 1);
  JitAdd("PutCh", &PutCh, 1, 1);
  JitAdd("MaxI64", &MaxI64, 2, 0);
  JitAdd("MinI64", &MinI64, 2, 0);
  JitAdd("AbsI64", &AbsI64, 1, 0);
  JitAdd("ToUpper", &ToUpper, 1, 0);
  JitAdd("MemSet", &MemSet, 3, 0);
  JitAdd("MemCpy", &MemCpy, 3, 0);
  JitAdd("Atoi", &Atoi, 1, 0);
  JitAdd("Str2I64", &Str2I64, 3, 0);
}

U0 JitW(U32 w)
{
  if (jit_at + 4 > JIT_END) {
    jit_err = 1;
    return;
  }
  *(U32 *)jit_at = w;
  jit_at = jit_at + 4;
}

U0 JitI(U32 f3, I64 rd, I64 rs1, I64 imm)
{
  JitW(0x13 | ((rd & 31) << 7) | ((f3 & 7) << 12) | ((rs1 & 31) << 15) | ((imm & 0xFFF) << 20));
}

U0 JitR(U32 f7, U32 f3, I64 rd, I64 rs1, I64 rs2)
{
  JitW(0x33 | ((rd & 31) << 7) | ((f3 & 7) << 12) | ((rs1 & 31) << 15) | ((rs2 & 31) << 20) | ((f7 & 0x7F) << 25));
}

U0 JitJalr(I64 rd, I64 rs1, I64 imm)
{
  JitW(0x67 | ((rd & 31) << 7) | ((rs1 & 31) << 15) | ((imm & 0xFFF) << 20));
}

U0 JitSd(I64 rs2, I64 imm, I64 rs1)
{
  JitW(0x23 | ((imm & 0x1F) << 7) | (3 << 12) | ((rs1 & 31) << 15) | ((rs2 & 31) << 20) | (((imm >> 5) & 0x7F) << 25));
}

U0 JitLd(I64 rd, I64 imm, I64 rs1)
{
  JitW(0x03 | ((rd & 31) << 7) | (3 << 12) | ((rs1 & 31) << 15) | ((imm & 0xFFF) << 20));
}

U0 JitLw(I64 rd, I64 imm, I64 rs1)
{
  JitW(0x03 | ((rd & 31) << 7) | (2 << 12) | ((rs1 & 31) << 15) | ((imm & 0xFFF) << 20));
}

U0 JitLb(I64 rd, I64 imm, I64 rs1)
{
  JitW(0x03 | ((rd & 31) << 7) | (0 << 12) | ((rs1 & 31) << 15) | ((imm & 0xFFF) << 20));
}

U0 JitLbu(I64 rd, I64 imm, I64 rs1)
{
  JitW(0x03 | ((rd & 31) << 7) | (4 << 12) | ((rs1 & 31) << 15) | ((imm & 0xFFF) << 20));
}

U0 JitSb(I64 rs2, I64 imm, I64 rs1)
{
  JitW(0x23 | ((imm & 0x1F) << 7) | (0 << 12) | ((rs1 & 31) << 15) | ((rs2 & 31) << 20) | (((imm >> 5) & 0x7F) << 25));
}

U0 JitSw(I64 rs2, I64 imm, I64 rs1)
{
  JitW(0x23 | ((imm & 0x1F) << 7) | (2 << 12) | ((rs1 & 31) << 15) | ((rs2 & 31) << 20) | (((imm >> 5) & 0x7F) << 25));
}

U0 JitLui(I64 rd, I64 imm20)
{
  JitW(0x37 | ((rd & 31) << 7) | ((imm20 & 0xFFFFF) << 12));
}
// Branch: returns address of instruction for patching
U8 *JitBr(U32 f3, I64 rs1, I64 rs2)
{
  U8 *p = jit_at;
  JitW(0x63 | ((f3 & 7) << 12) | ((rs1 & 31) << 15) | ((rs2 & 31) << 20));
  // offset 0
  return p;
}

U8 *JitJal()
{
  U8 *p = jit_at;
  JitW(0x6F);
  // j 0 / jal x0,0
  return p;
}

U0 JitPatchB(U8 *at, U8 *target)
{
  I64 off = target - at;
  U32 w;
  if (!at)
    return;
  w = *(U32 *)at;
  w &= 0x01FFF07F;
  // keep opcode/f3/rs
  w |= ((off >> 11) & 1) << 7;
  w |= ((off >> 1) & 0xF) << 8;
  w |= ((off >> 5) & 0x3F) << 25;
  w |= ((off >> 12) & 1) << 31;
  *(U32 *)at = w;
}

U0 JitPatchJ(U8 *at, U8 *target)
{
  I64 off = target - at;
  U32 w;
  if (!at)
    return;
  w = 0x6F;
  w |= ((off >> 12) & 0xFF) << 12;
  w |= ((off >> 11) & 1) << 20;
  w |= ((off >> 1) & 0x3FF) << 21;
  w |= ((off >> 20) & 1) << 31;
  *(U32 *)at = w;
}

U0 JitAbs(I64 rd, I64 addr)
{
  // j 1f; [pad]; .quad addr; 1: auipc tmp,0; ld rd, OFF(tmp)
  // OFF is negative distance from auipc back to quad.
  U8 *j_at, *quad, *auipc_at;
  I64 tmp, off;
  tmp = 5;
  if (rd == 5)
    tmp = 6;
  j_at = jit_at;
  JitW(0x6F);
  // jal x0, placeholder
  while ((I64)jit_at & 7)
    JitW(0x00000013);
  quad = jit_at;
  if (jit_at + 8 > JIT_END) {
    jit_err = 1;
    return;
  }
  *(I64 *)jit_at = addr;
  jit_at = jit_at + 8;
  JitPatchJ(j_at, jit_at);
  // jump over quad to here
  auipc_at = jit_at;
  JitW(0x17 | ((tmp & 31) << 7));
  // auipc tmp,0
  off = quad - auipc_at;
  // negative
  JitW(0x03 | ((rd & 31) << 7) | (3 << 12) | ((tmp & 31) << 15) | ((off & 0xFFF) << 20));
  // ld rd, off(tmp)
}

U0 JitCallAbs(I64 target)
{
  // j 1f; [pad]; .quad tgt; 1: auipc t0,0; ld t0,off(t0); jalr ra,t0
  U8 *j_at, *quad, *auipc_at;
  I64 off;
  j_at = jit_at;
  JitW(0x6F);
  while ((I64)jit_at & 7)
    JitW(0x00000013);
  quad = jit_at;
  if (jit_at + 8 > JIT_END) {
    jit_err = 1;
    return;
  }
  *(I64 *)jit_at = target;
  jit_at = jit_at + 8;
  JitPatchJ(j_at, jit_at);
  auipc_at = jit_at;
  JitW(0x00000297);
  // auipc t0,0
  off = quad - auipc_at;
  JitW(0x03 | (5 << 7) | (3 << 12) | (5 << 15) | ((off & 0xFFF) << 20));
  // ld t0,off(t0)
  JitJalr(1, 5, 0);
}

U0 JitLi(I64 rd, I64 imm)
{
  I64 hi, lo;
  if (imm >= -2048 && imm <= 2047) {
    JitI(0, rd, 0, imm);
    return;
  }
  hi = (imm >> 12) & 0xFFFFF;
  lo = imm & 0xFFF;
  if (lo & 0x800) {
    lo = lo - 0x1000;
    hi = (hi + 1) & 0xFFFFF;
  }
  JitLui(rd, hi);
  if (lo)
    JitI(0, rd, rd, lo);
}

U0 JitPrologue()
{
  I64 i, n;
  jit_frame = 16 + JIT_SLOT * 8;
  n = jit_argc;
  if (n > 8)
    n = 8;
  JitI(0, 2, 2, -jit_frame);
  JitSd(1, jit_frame - 8, 2);
  JitSd(8, jit_frame - 16, 2);
  JitI(0, 8, 2, jit_frame);
  for (i = 0; i < n; i++)
    JitSd(10 + i, 16 + i * 8, 2);
  // params >8 already on caller's stack at s0+0..
}

U0 JitEpilogue()
{
  JitLd(1, jit_frame - 8, 2);
  JitLd(8, jit_frame - 16, 2);
  JitI(0, 2, 2, jit_frame);
  JitJalr(0, 1, 0);
}
// Slot i (0..7) in callee frame from s0; i>=8 = caller's stack at s0+(i-8)*8
I64 JitSlotOff(I64 i)
{
  if (i >= 8)
    return (i - 8) * 8;
  return -(jit_frame - 16 - i * 8);
}

U0 JitLoadSlot(I64 rd, I64 slot)
{
  JitLd(rd, JitSlotOff(slot), 8);
}

U0 JitStoreSlot(I64 rs, I64 slot)
{
  JitSd(rs, JitSlotOff(slot), 8);
}

I64 JitFind(U8 *name)
{
  I64 i;
  for (i = 0; i < jit_nfun; i++)
    if (JitSeq(jit_funs[i].name, name))
      return i;
  return -1;
}

I64 JitAdd(U8 *name, U8 *entry, I64 argc, I64 is_void)
{
  I64 i;
  // Reuse slot on redefine so Run("…") after Ed updates the same name
  // (livedrv second Run → LIVEDRV) without exhausting JIT_FUN_MAX.
  i = JitFind(name);
  if (i < 0) {
    if (jit_nfun >= JIT_FUN_MAX)
      return -1;
    i = jit_nfun;
    jit_nfun++;
  }
  JitCpy(jit_funs[i].name, name, JIT_NAME_MAX);
  jit_funs[i].entry = entry;
  jit_funs[i].argc = argc;
  jit_funs[i].is_void = is_void;
  return i;
}

I64 JitFindGlob(U8 *name)
{
  I64 i;
  for (i = 0; i < jit_nglob; i++)
    if (JitSeq(jit_globs[i].name, name))
      return i;
  return -1;
}

I64 JitAddGlob(U8 *name, I64 size)
{
  I64 i = JitFindGlob(name);
  if (i >= 0)
    return i;
  if (jit_nglob >= 64)
    return -1;
  i = jit_nglob;
  jit_nglob++;
  JitCpy(jit_globs[i].name, name, JIT_NAME_MAX);
  while ((I64)jit_glob_brk & 7)
    jit_glob_brk++;
  jit_globs[i].addr = jit_glob_brk;
  jit_globs[i].size = size;
  MemSet(jit_glob_brk, 0, size);
  jit_glob_brk = jit_glob_brk + size;
  return i;
}

I64 JitFindCls(U8 *name)
{
  I64 i;
  for (i = 0; i < jit_ncls; i++)
    if (JitSeq(jit_cls[i].name, name))
      return i;
  return -1;
}

I64 JitFindLocal(U8 *name)
{
  I64 i;
  for (i = 0; i < jit_local_n; i++)
    if (JitSeq(jit_lname[i], name))
      return i;
  return -1;
}

I64 JitFindParam(U8 *name)
{
  I64 i;
  for (i = 0; i < jit_pargc; i++)
    if (JitSeq(jit_pname[i], name))
      return i;
  return -1;
}

U0 JitSkip()
{
  while (*jit_src == ' ' || *jit_src == '\t' || *jit_src == '\r' || *jit_src == '\n')
    jit_src++;
  // line comments
  if (*jit_src == '/' && jit_src[1] == '/') {
    while (*jit_src && *jit_src != '\n')
      jit_src++;
    JitSkip();
  }
}

I64 JitIdent()
{
  I64 n = 0;
  JitSkip();
  if (!((*jit_src >= 'A' && *jit_src <= 'Z') || (*jit_src >= 'a' && *jit_src <= 'z') || *jit_src == '_')) {
    jit_id[0] = 0;
    return 0;
  }
  while (((*jit_src >= 'A' && *jit_src <= 'Z') || (*jit_src >= 'a' && *jit_src <= 'z') || (*jit_src >= '0' && *jit_src <= '9') || *jit_src == '_') && n < JIT_NAME_MAX - 1) {
    jit_id[n] = *jit_src;
    n++;
    jit_src++;
  }
  jit_id[n] = 0;
  return 1;
}

I64 JitNum(I64 *o)
{
  I64 v = 0, neg = 0, base = 10;
  JitSkip();
  if (*jit_src == '-') {
    neg = 1;
    jit_src++;
  }
  if (!(*jit_src >= '0' && *jit_src <= '9'))
    return 0;
  if (*jit_src == '0' && (jit_src[1] == 'x' || jit_src[1] == 'X')) {
    base = 16;
    jit_src = jit_src + 2;
    while (1) {
      I64 d = -1;
      if (*jit_src >= '0' && *jit_src <= '9')
        d = *jit_src - '0';
      else if (*jit_src >= 'a' && *jit_src <= 'f')
        d = *jit_src - 'a' + 10;
      else if (*jit_src >= 'A' && *jit_src <= 'F')
        d = *jit_src - 'A' + 10;
      if (d < 0)
        break;
      v = v * 16 + d;
      jit_src++;
    }
  } else {
    while (*jit_src >= '0' && *jit_src <= '9') {
      v = v * 10 + (*jit_src - '0');
      jit_src++;
    }
  }
  if (neg)
    v = -v;
  *o = v;
  return 1;
}

I64 JitNeed(I64 ch)
{
  JitSkip();
  if (*jit_src != ch) {
    jit_err = 1;
    return 0;
  }
  jit_src++;
  return 1;
}

I64 JitPeek(I64 ch)
{
  JitSkip();
  return *jit_src == ch;
}

U0 JitPushA0()
{
  JitI(0, 2, 2, -8);
  JitSd(10, 0, 2);
}

U0 JitPopT1()
{
  JitLd(6, 0, 2);
  JitI(0, 2, 2, 8);
}
// Forward decls
U0 JitGenExpr();
U0 JitGenStmt();
U0 JitGenBlock();
U0 JitLoadName(U8 *name);
U0 JitStoreName(U8 *name);
U8 *JitEmitStr()
{
  U8 *p, q, *d;
  I64 n = 0;
  JitSkip();
  q = *jit_src;
  if (q != '"' && q != '\'') {
    jit_err = 1;
    return 0;
  }
  jit_src++;
  // Count length first
  
  {
    U8 *s = jit_src;
    while (*s && *s != q) {
      if (*s == '\\' && s[1])
        s = s + 2;
      else
        s++;
      n++;
    }
  }
  jit_str_brk = jit_str_brk - (n + 8);
  while ((I64)jit_str_brk & 7)
    jit_str_brk--;
  if (jit_str_brk < jit_at + 256) {
    jit_err = 1;
    return 0;
  }
  p = jit_str_brk;
  d = p;
  while (*jit_src && *jit_src != q) {
    if (*jit_src == '\\' && jit_src[1]) {
      jit_src++;
      if (*jit_src == 'n') {
        *d = 10;
      } else if (*jit_src == 't') {
        *d = 9;
      } else {
        *d = *jit_src;
      }
      d++;
      jit_src++;
    } else {
      *d = *jit_src;
      d++;
      jit_src++;
    }
  }
  if (*jit_src != q) {
    jit_err = 1;
    return 0;
  }
  jit_src++;
  *d = 0;
  return p;
}

U0 JitGenCall(I64 fi)
{
  I64 narg = 0, i;
  JitNeed('(');
  JitSkip();
  if (*jit_src != ')') {
    while (narg < 16) {
      JitGenExpr();
      JitPushA0();
      narg++;
      JitSkip();
      if (*jit_src == ',') {
        jit_src++;
        continue;
      }
      break;
    }
  }
  if (!JitNeed(')'))
    return;
  // RV ABI: a0..a7 + stack arg8 at 0(sp), arg9 at 8(sp), ...
  
  {
    I64 nstk, i2;
    if (narg <= 8) {
      for (i = 0; i < narg; i++)
        JitLd(10 + i, (narg - 1 - i) * 8, 2);
      JitI(0, 2, 2, narg * 8);
      JitCallAbs(jit_funs[fi].entry);
    } else {
      nstk = narg - 8;
      for (i = 0; i < 8; i++)
        JitLd(10 + i, (narg - 1 - i) * 8, 2);
      // Pack arg8.. at high end in ascending order, then drop reg spills
      for (i2 = 0; i2 < nstk; i2++) {
        JitLd(5, (narg - 1 - (8 + i2)) * 8, 2);
        JitSd(5, (narg - nstk + i2) * 8, 2);
      }
      JitI(0, 2, 2, (narg - nstk) * 8);
      // sp → arg8
      JitCallAbs(jit_funs[fi].entry);
      JitI(0, 2, 2, nstk * 8);
    }
  }
}

U0 JitGenPrim()
{
  I64 v, fi, pi, gi, li, ci, mi;
  U8 *sp;
  U8 *save;
  JitSkip();
  if (*jit_src == '(') {
    jit_src++;
    JitGenExpr();
    JitNeed(')');
    return;
  }
  if (*jit_src == '"' || *jit_src == '\'') {
    // char literal 'AB' or string
    if (*jit_src == '\'' && jit_src[1] && jit_src[2] == '\'') {
      // single char
      v = jit_src[1];
      jit_src = jit_src + 3;
      JitLi(10, v);
      return;
    }
    if (*jit_src == '\'' && jit_src[1] && jit_src[2] && jit_src[3] == '\'') {
      v = jit_src[1] | (jit_src[2] << 8);
      jit_src = jit_src + 4;
      JitLi(10, v);
      return;
    }
    sp = JitEmitStr();
    if (sp)
      JitAbs(10, sp);
    return;
  }
  if (*jit_src == '&') {
    jit_src++;
    if (!JitIdent()) {
      jit_err = 1;
      return;
    }
    li = JitFindLocal(jit_id);
    if (li >= 0) {
      JitI(0, 10, 8, jit_loff[li]);
      // addi a0,s0,off
      return;
    }
    pi = JitFindParam(jit_id);
    if (pi >= 0) {
      JitI(0, 10, 8, JitSlotOff(pi));
      return;
    }
    gi = JitFindGlob(jit_id);
    if (gi >= 0) {
      JitAbs(10, jit_globs[gi].addr);
      return;
    }
    fi = JitFind(jit_id);
    if (fi >= 0) {
      JitAbs(10, jit_funs[fi].entry);
      return;
    }
    jit_err = 1;
    return;
  }
  if (*jit_src == '*') {
    jit_src++;
    JitGenPrim();
    // Byte load: U8 *p / "str" walks (livedrv *s++ + ToUpper). I64* stores use
    // JitSd in assign; thin JIT does not track pointed-to size on unary *.
    JitLbu(10, 0, 10);
    return;
  }
  if (*jit_src == '!') {
    jit_src++;
    JitGenPrim();
    JitI(3, 10, 10, 1);
    // seqz via sltiu a0,a0,1
    return;
  }
  if (*jit_src == '~') {
    jit_src++;
    JitGenPrim();
    JitI(4, 10, 10, -1);
    // xori a0,a0,-1
    return;
  }
  if (JitNum(&v)) {
    JitLi(10, v);
    return;
  }
  if (!JitIdent()) {
    jit_err = 1;
    return;
  }
  // sizeof
  if (JitSeq(jit_id, "sizeof")) {
    JitNeed('(');
    if (!JitIdent()) {
      jit_err = 1;
      return;
    }
    ci = JitFindCls(jit_id);
    if (ci >= 0)
      JitLi(10, jit_cls[ci].size);
    else
      JitLi(10, 8);
    JitNeed(')');
    return;
  }
  JitSkip();
  if (*jit_src == '(') {
    fi = JitFind(jit_id);
    if (fi < 0) {
      jit_err = 1;
      return;
    }
    JitGenCall(fi);
    return;
  }
  // local / param / global, maybe .member or [index]
  pi = JitFindParam(jit_id);
  li = JitFindLocal(jit_id);
  gi = JitFindGlob(jit_id);
  if (pi >= 0)
    JitLoadSlot(10, pi);
  else if (li >= 0) {
    if (jit_lsize[li] > 8)
      JitI(0, 10, 8, jit_loff[li]);
    // array/struct → address
    else if(jit_lsize[li] == 1)JitLbu(10, jit_loff[li], 8);
    else if(jit_lsize[li] == 4)JitLw(10, jit_loff[li], 8);
    else JitLd(10, jit_loff[li], 8);
  } else if (gi >= 0) {
    JitAbs(5, jit_globs[gi].addr);
    JitLd(10, 0, 5);
  } else {
    jit_err = 1;
    return;
  }
  // postfix ++ / --
  JitSkip();
  if ((*jit_src == '+' && jit_src[1] == '+') || (*jit_src == '-' && jit_src[1] == '-')) {
    U8 nbuf[JIT_NAME_MAX];
    I64 pop = *jit_src;
    // reload by name
    if (pi >= 0)
      JitCpy(nbuf, jit_pname[pi], JIT_NAME_MAX);
    else if (li >= 0)
      JitCpy(nbuf, jit_lname[li], JIT_NAME_MAX);
    else if (gi >= 0)
      JitCpy(nbuf, jit_globs[gi].name, JIT_NAME_MAX);
    else {
      jit_err = 1;
      return;
    }
    jit_src = jit_src + 2;
    JitPushA0();
    if (pop == '+')
      JitI(0, 10, 10, 1);
    else
      JitI(0, 10, 10, -1);
    JitStoreName(nbuf);
    JitPopT1();
    JitI(0, 10, 6, 0);
    return;
  }
  // postfix [expr]
  JitSkip();
  if (*jit_src == '[') {
    I64 scale = 0;
    // byte pointer by default
    I64 use_ld = 0;
    if (li >= 0 && jit_lsize[li] > 8) {
      scale = 3;
      use_ld = 1;
    }
    // I64 array local
    if (li >= 0 && jit_lsize[li] == 8 && 0) {
      scale = 3;
      use_ld = 1;
    }
    jit_src++;
    JitPushA0();
    JitGenExpr();
    JitNeed(']');
    if (scale)
      JitI(1, 10, 10, scale);
    JitPopT1();
    JitR(0, 0, 10, 6, 10);
    if (use_ld)
      JitLd(10, 0, 10);
    else
      JitLbu(10, 0, 10);
  }
  // .member
  JitSkip();
  if (*jit_src == '.') {
    jit_src++;
    if (!JitIdent()) {
      jit_err = 1;
      return;
    }
    // Need class of local — store class id on local; for now search all classes for member
    for (ci = 0; ci < jit_ncls; ci++) {
      for (mi = 0; mi < jit_cls[ci].nmem; mi++) {
        if (JitSeq(jit_cls[ci].mem[mi].name, jit_id)) {
          // a0 is struct value — wrong for local struct we loaded whole I64
          // Reload address of local
          if (li >= 0) {
            JitI(0, 5, 8, jit_loff[li]);
            JitLd(10, jit_cls[ci].mem[mi].off, 5);
            return;
          }
        }
      }
    }
    jit_err = 1;
  }
}

U0 JitGenUnary()
{
  I64 neg = 0, op;
  JitSkip();
  if ((*jit_src == '+' && jit_src[1] == '+') || (*jit_src == '-' && jit_src[1] == '-')) {
    op = *jit_src;
    jit_src = jit_src + 2;
    if (!JitIdent()) {
      jit_err = 1;
      return;
    }
    JitLoadName(jit_id);
    if (op == '+')
      JitI(0, 10, 10, 1);
    else
      JitI(0, 10, 10, -1);
    JitStoreName(jit_id);
    return;
  }
  while (*jit_src == '-' || *jit_src == '+') {
    if (*jit_src == '-')
      neg ^= 1;
    jit_src++;
  }
  JitGenPrim();
  if (neg) {
    JitR(0x20, 0, 10, 0, 10);
  }
  // neg
}

U0 JitGenMul()
{
  I64 op;
  JitGenUnary();
  while (1) {
    JitSkip();
    op = *jit_src;
    if (op != '*' && op != '/' && op != '%')
      break;
    jit_src++;
    JitPushA0();
    JitGenUnary();
    JitPopT1();
    if (op == '*')
      JitR(1, 0, 10, 6, 10);
    else if (op == '/')
      JitR(1, 4, 10, 6, 10);
    else
      JitR(1, 6, 10, 6, 10);
  }
}

U0 JitGenAdd()
{
  I64 op;
  JitGenMul();
  while (1) {
    JitSkip();
    op = *jit_src;
    if (op != '+' && op != '-')
      break;
    // avoid matching ++ --
    if (jit_src[1] == op)
      break;
    jit_src++;
    JitPushA0();
    JitGenMul();
    JitPopT1();
    if (op == '+')
      JitR(0, 0, 10, 6, 10);
    else
      JitR(0x20, 0, 10, 6, 10);
  }
}

U0 JitGenShift()
{
  I64 op;
  JitGenAdd();
  while (1) {
    JitSkip();
    if (*jit_src == '<' && jit_src[1] == '<') {
      op = 1;
      jit_src = jit_src + 2;
    } else if (*jit_src == '>' && jit_src[1] == '>') {
      op = 2;
      jit_src = jit_src + 2;
    } else
      break;
    JitPushA0();
    JitGenAdd();
    JitPopT1();
    if (op == 1)
      JitR(0, 1, 10, 6, 10);
    // sll
    else JitR(0, 5, 10, 6, 10);
    // srl
  }
}

U0 JitGenCmp()
{
  I64 op;
  JitGenShift();
  while (1) {
    JitSkip();
    if (*jit_src == '=' && jit_src[1] == '=') {
      op = 1;
      jit_src = jit_src + 2;
    } else if (*jit_src == '!' && jit_src[1] == '=') {
      op = 2;
      jit_src = jit_src + 2;
    } else if (*jit_src == '<' && jit_src[1] == '=') {
      op = 3;
      jit_src = jit_src + 2;
    } else if (*jit_src == '>' && jit_src[1] == '=') {
      op = 4;
      jit_src = jit_src + 2;
    } else if (*jit_src == '<') {
      op = 5;
      jit_src++;
    } else if (*jit_src == '>') {
      op = 6;
      jit_src++;
    } else
      break;
    JitPushA0();
    JitGenShift();
    JitPopT1();
    // t1=left, a0=right
    if (op == 1) {
      // ==
      JitR(0, 0, 10, 6, 10);
      JitR(0x20, 0, 10, 10, 0);
      // sub; then seqz
      JitI(3, 10, 10, 1);
      // sltiu a0,a0,1
    } else if (op == 2) {
      // !=
      JitR(0x20, 0, 10, 6, 10);
      // sub
      JitI(3, 5, 10, 1);
      JitI(4, 10, 5, 1);
      // rough snez: sltiu t0,a0,1; xori a0,t0,1
    } else if (op == 5) {
      // <
      JitR(0, 2, 10, 6, 10);
      // slt a0,t1,a0
    } else if (op == 6) {
      // >
      JitR(0, 2, 10, 10, 6);
      // slt a0,a0,t1
    } else if (op == 3) {
      // <=  !(left > right)
      JitR(0, 2, 10, 10, 6);
      // slt a0,right,left
      JitI(4, 10, 10, 1);
      // xori a0,a0,1
    } else if (op == 4) {
      // >=  !(left < right)
      JitR(0, 2, 10, 6, 10);
      // slt a0,left,right
      JitI(4, 10, 10, 1);
      // xori a0,a0,1
    }
  }
}

U0 JitGenLogic()
{
  JitGenCmp();
  while (1) {
    JitSkip();
    if (*jit_src == '&' && jit_src[1] == '&') {
      jit_src = jit_src + 2;
      JitPushA0();
      JitGenCmp();
      JitPopT1();
      // t1=left, a0=right (cmp already 0/1)
      JitR(0, 7, 10, 6, 10);
    } else if (*jit_src == '|' && jit_src[1] == '|') {
      jit_src = jit_src + 2;
      JitPushA0();
      JitGenCmp();
      JitPopT1();
      JitR(0, 6, 10, 6, 10);
    } else
      break;
  }
}

U0 JitGenExpr()
{
  JitGenLogic();
}

I64 JitAllocLocal(U8 *name, I64 size)
{
  I64 i, slot, off, bytes, esize;
  if (jit_local_n >= JIT_SLOT) {
    jit_err = 1;
    return -1;
  }
  slot = jit_next_local;
  if (slot >= JIT_SLOT) {
    jit_err = 1;
    return -1;
  }
  esize = size;
  if (size <= 0)
    size = 8;
  if (size < 8)
    bytes = 8;
  else
    bytes = (size + 7) & -8;
  i = jit_local_n;
  JitCpy(jit_lname[i], name, JIT_NAME_MAX);
  off = JitSlotOff(slot);
  jit_loff[i] = off;
  jit_lsize[i] = esize;
  // true size (1/4/8 or array bytes)
  jit_local_n++;
  jit_next_local = slot + (bytes / 8);
  return i;
}

U0 JitLoadName(U8 *name)
{
  I64 pi, li, gi;
  pi = JitFindParam(name);
  if (pi >= 0) {
    JitLoadSlot(10, pi);
    return;
  }
  li = JitFindLocal(name);
  if (li >= 0) {
    if (jit_lsize[li] > 8)
      JitI(0, 10, 8, jit_loff[li]);
    else if (jit_lsize[li] == 1)
      JitLbu(10, jit_loff[li], 8);
    else if (jit_lsize[li] == 4)
      JitLw(10, jit_loff[li], 8);
    else
      JitLd(10, jit_loff[li], 8);
    return;
  }
  gi = JitFindGlob(name);
  if (gi >= 0) {
    JitAbs(5, jit_globs[gi].addr);
    JitLd(10, 0, 5);
    return;
  }
  jit_err = 1;
}

U0 JitStoreName(U8 *name)
{
  // store a0 into name
  I64 pi, li, gi;
  pi = JitFindParam(name);
  if (pi >= 0) {
    JitStoreSlot(10, pi);
    return;
  }
  li = JitFindLocal(name);
  if (li >= 0) {
    if (jit_lsize[li] == 1)
      JitSb(10, jit_loff[li], 8);
    else if (jit_lsize[li] == 4)
      JitSw(10, jit_loff[li], 8);
    else
      JitSd(10, jit_loff[li], 8);
    return;
  }
  gi = JitFindGlob(name);
  if (gi >= 0) {
    JitAbs(5, jit_globs[gi].addr);
    JitSd(10, 0, 5);
    return;
  }
  jit_err = 1;
}

U0 JitGenAssignOrExpr()
{
  U8 *save;
  U8 name[JIT_NAME_MAX];
  I64 li, ci, mi, op;
  save = jit_src;
  // ++name / --name
  if ((*jit_src == '+' && jit_src[1] == '+') || (*jit_src == '-' && jit_src[1] == '-')) {
    op = *jit_src;
    jit_src = jit_src + 2;
    if (!JitIdent()) {
      jit_err = 1;
      return;
    }
    JitLoadName(jit_id);
    if (op == '+')
      JitI(0, 10, 10, 1);
    else
      JitI(0, 10, 10, -1);
    JitStoreName(jit_id);
    return;
  }
  // *p = expr
  if (*jit_src == '*') {
    jit_src++;
    JitGenPrim();
    // address in a0
    JitSkip();
    if (*jit_src == '=' && jit_src[1] != '=') {
      jit_src++;
      JitPushA0();
      JitGenExpr();
      JitPopT1();
      // t1=addr
      JitSd(10, 0, 6);
      return;
    }
    jit_src = save;
  }
  if (JitIdent()) {
    JitCpy(name, jit_id, JIT_NAME_MAX);
    JitSkip();
    // name++ / name--
    if ((*jit_src == '+' && jit_src[1] == '+') || (*jit_src == '-' && jit_src[1] == '-')) {
      op = *jit_src;
      jit_src = jit_src + 2;
      JitLoadName(name);
      JitPushA0();
      // old value
      if (op == '+')
        JitI(0, 10, 10, 1);
      else
        JitI(0, 10, 10, -1);
      JitStoreName(name);
      JitPopT1();
      JitI(0, 10, 6, 0);
      // a0 = old
      return;
    }
    // name +=/-=/*= expr  or name = expr (incl. chain a=b=3 via recursive GenExpr path)
    if ((*jit_src == '+' || *jit_src == '-' || *jit_src == '*') && jit_src[1] == '=') {
      op = *jit_src;
      jit_src = jit_src + 2;
      JitLoadName(name);
      JitPushA0();
      JitGenExpr();
      JitPopT1();
      if (op == '+')
        JitR(0, 0, 10, 6, 10);
      else if (op == '-')
        JitR(0x20, 0, 10, 6, 10);
      else
        JitR(1, 0, 10, 6, 10);
      JitStoreName(name);
      return;
    }
    // name = expr  (right side may itself be assign → chain)
    if (*jit_src == '=' && jit_src[1] != '=') {
      jit_src++;
      JitGenAssignOrExpr();
      // value in a0 (supports a=b=3)
      JitStoreName(name);
      return;
    }
    // name.member = expr
    if (*jit_src == '.') {
      jit_src++;
      if (!JitIdent()) {
        jit_err = 1;
        return;
      }
      
      {
        U8 mem[JIT_NAME_MAX];
        JitCpy(mem, jit_id, JIT_NAME_MAX);
        JitSkip();
        if (*jit_src == '=' && jit_src[1] != '=') {
          jit_src++;
          li = JitFindLocal(name);
          if (li < 0) {
            jit_err = 1;
            return;
          }
          JitGenExpr();
          JitPushA0();
          for (ci = 0; ci < jit_ncls; ci++)
            for (mi = 0; mi < jit_cls[ci].nmem; mi++)
              if (JitSeq(jit_cls[ci].mem[mi].name, mem)) {
                JitI(0, 5, 8, jit_loff[li]);
                JitPopT1();
                JitSd(6, jit_cls[ci].mem[mi].off, 5);
                return;
              }
          jit_err = 1;
          return;
        }
      }
    }
    // name[i] = expr  (or name[i] rvalue → GenExpr below)
    if (*jit_src == '[') {
      jit_src++;
      li = JitFindLocal(name);
      if (li < 0) {
        jit_err = 1;
        return;
      }
      JitGenExpr();
      // index
      JitNeed(']');
      JitSkip();
      if (*jit_src == '=' && jit_src[1] != '=') {
        jit_src++;
        JitPushA0();
        // index
        JitGenExpr();
        // value
        JitPushA0();
        JitLd(10, 0, 2);
        // value
        JitLd(6, 8, 2);
        // index
        JitI(0, 2, 2, 16);
        JitI(1, 6, 6, 3);
        // index*8
        JitI(0, 5, 8, jit_loff[li]);
        JitR(0, 0, 5, 5, 6);
        JitSd(10, 0, 5);
        return;
      }
      // Rvalue name[i] inside assign RHS — do not leak PushA0; reload via GenExpr.
      jit_src = save;
      JitGenExpr();
      return;
    }
  }
  jit_src = save;
  JitGenExpr();
}

U0 JitGenStmt()
{
  U8 *save, *b_else, *b_end, *b_loop, *b_cont;
  I64 is_void;
  U8 *d, *s;
  JitSkip();
  if (!*jit_src || *jit_src == '}')
    return;
  if (*jit_src == '{') {
    JitGenBlock();
    return;
  }
  if (*jit_src == ';') {
    jit_src++;
    return;
  }
  save = jit_src;
  if (JitIdent()) {
    // return
    if (JitSeq(jit_id, "return")) {
      JitSkip();
      if (*jit_src != ';')
        JitGenExpr();
      else
        JitLi(10, 0);
      JitNeed(';');
      JitEpilogue();
      return;
    }
    // if
    if (JitSeq(jit_id, "if")) {
      JitNeed('(');
      JitGenExpr();
      JitNeed(')');
      b_else = JitBr(0, 10, 0);
      // beq a0,zero
      JitGenStmt();
      JitSkip();
      save = jit_src;
      if (JitIdent() && JitSeq(jit_id, "else")) {
        b_end = JitJal();
        JitPatchB(b_else, jit_at);
        JitGenStmt();
        JitPatchJ(b_end, jit_at);
      } else {
        jit_src = save;
        JitPatchB(b_else, jit_at);
      }
      return;
    }
    // while
    if (JitSeq(jit_id, "while")) {
      b_loop = jit_at;
      JitNeed('(');
      JitGenExpr();
      JitNeed(')');
      b_end = JitBr(0, 10, 0);
      JitGenStmt();
      b_cont = JitJal();
      JitPatchJ(b_cont, b_loop);
      JitPatchB(b_end, jit_at);
      return;
    }
    // do { } while (cond);
    if (JitSeq(jit_id, "do")) {
      b_loop = jit_at;
      JitGenStmt();
      JitSkip();
      if (!JitIdent() || !JitSeq(jit_id, "while")) {
        jit_err = 1;
        return;
      }
      JitNeed('(');
      JitGenExpr();
      JitNeed(')');
      JitNeed(';');
      // branch if nonzero back to loop
      
      {
        U8 *b_skip = JitBr(0, 10, 0);
        // beq zero → done
        b_cont = JitJal();
        JitPatchJ(b_cont, b_loop);
        JitPatchB(b_skip, jit_at);
      }
      return;
    }
    // for (init; cond; incr) stmt
    if (JitSeq(jit_id, "for")) {
      JitNeed('(');
      // init
      JitSkip();
      if (*jit_src != ';') {
        // I64 i = 0  or i = 0
        save = jit_src;
        if (JitIdent() && (JitSeq(jit_id, "I64") || JitSeq(jit_id, "U8") || JitSeq(jit_id, "I32"))) {
          if (!JitIdent()) {
            jit_err = 1;
            return;
          }
          JitAllocLocal(jit_id, 8);
          JitSkip();
          if (*jit_src == '=') {
            jit_src++;
            JitGenExpr();
            JitStoreName(jit_lname[jit_local_n - 1]);
          }
        } else {
          jit_src = save;
          JitGenAssignOrExpr();
        }
      }
      JitNeed(';');
      b_loop = jit_at;
      JitSkip();
      if (*jit_src != ';')
        JitGenExpr();
      else
        JitLi(10, 1);
      JitNeed(';');
      b_end = JitBr(0, 10, 0);
      // skip incr parse for now — save incr source
      
      {
        U8 *incr_s = jit_src;
        U8 *body_patch;
        while (*jit_src && *jit_src != ')')
          jit_src++;
        JitNeed(')');
        JitGenStmt();
        // emit incr
        
        {
          U8 *saved_src = jit_src;
          jit_src = incr_s;
          JitSkip();
          if (*jit_src && *jit_src != ')') {
            // i++ or i=i+1
            save = jit_src;
            if (JitIdent()) {
              U8 iname[JIT_NAME_MAX];
              JitCpy(iname, jit_id, JIT_NAME_MAX);
              JitSkip();
              if (*jit_src == '+' && jit_src[1] == '+') {
                jit_src = jit_src + 2;
                // load, +1, store
                
                {
                  I64 li = JitFindLocal(iname);
                  I64 pi = JitFindParam(iname);
                  if (li >= 0)
                    JitLd(10, jit_loff[li], 8);
                  else if (pi >= 0)
                    JitLoadSlot(10, pi);
                  JitI(0, 10, 10, 1);
                  JitStoreName(iname);
                }
              } else {
                jit_src = save;
                JitGenAssignOrExpr();
              }
            }
          }
          jit_src = saved_src;
        }
        body_patch = JitJal();
        JitPatchJ(body_patch, b_loop);
        JitPatchB(b_end, jit_at);
      }
      return;
    }
    // local decl I64 x; I64 x = expr; I64 a[4]; I64 i, s = 0; U8 b;
    if (JitSeq(jit_id, "I64") || JitSeq(jit_id, "U8") || JitSeq(jit_id, "I32") || JitSeq(jit_id, "U0")) {
      I64 sz0 = 8;
      if (JitSeq(jit_id, "U8"))
        sz0 = 1;
      else if (JitSeq(jit_id, "I32"))
        sz0 = 4;
      else if (JitSeq(jit_id, "U0")) {
        jit_err = 1;
        return;
      }
      while (1) {
        I64 sz = sz0, is_arr = 0, arrn = 0;
        U8 tname[JIT_NAME_MAX];
        JitSkip();
        if (*jit_src == '*') {
          jit_src++;
          sz = 8;
        }
        if (!JitIdent()) {
          jit_err = 1;
          return;
        }
        JitCpy(tname, jit_id, JIT_NAME_MAX);
        JitSkip();
        if (*jit_src == '[') {
          jit_src++;
          if (!JitNum(&arrn)) {
            jit_err = 1;
            return;
          }
          JitNeed(']');
          is_arr = 1;
          sz = 8 * arrn;
          if (sz < 8)
            sz = 8;
        }
        JitAllocLocal(tname, sz);
        JitSkip();
        if (*jit_src == '=') {
          jit_src++;
          JitGenExpr();
          JitStoreName(tname);
        }
        JitSkip();
        if (*jit_src == ',') {
          jit_src++;
          continue;
        }
        break;
      }
      JitNeed(';');
      return;
    }
    // class Type var;
    
    {
      I64 ci = JitFindCls(jit_id);
      if (ci >= 0) {
        U8 vname[JIT_NAME_MAX];
        if (!JitIdent()) {
          jit_err = 1;
          return;
        }
        JitCpy(vname, jit_id, JIT_NAME_MAX);
        JitAllocLocal(vname, jit_cls[ci].size);
        JitNeed(';');
        return;
      }
    }
  }
  jit_src = save;
  // assignment or expression statement
  JitGenAssignOrExpr();
  JitNeed(';');
}

U0 JitGenBlock()
{
  JitNeed('{');
  while (1) {
    JitSkip();
    if (!*jit_src || *jit_src == '}')
      break;
    JitGenStmt();
    if (jit_err)
      return;
  }
  JitNeed('}');
}

I64 JitParseClass()
{
  I64 ci, off;
  if (!JitIdent() || !JitSeq(jit_id, "class"))
    return 0;
  if (!JitIdent()) {
    jit_err = 1;
    return -1;
  }
  if (jit_ncls >= JIT_CLS_MAX) {
    jit_err = 1;
    return -1;
  }
  ci = jit_ncls;
  jit_ncls++;
  JitCpy(jit_cls[ci].name, jit_id, JIT_NAME_MAX);
  jit_cls[ci].nmem = 0;
  jit_cls[ci].size = 0;
  off = 0;
  JitNeed('{');
  while (1) {
    JitSkip();
    if (*jit_src == '}')
      break;
    if (!JitIdent()) {
      jit_err = 1;
      return -1;
    }
    // type
    if (!(JitSeq(jit_id, "I64") || JitSeq(jit_id, "U8") || JitSeq(jit_id, "I32") || JitSeq(jit_id, "U64"))) {
      jit_err = 1;
      return -1;
    }
    
    {
      I64 msz = 8;
      if (JitSeq(jit_id, "U8"))
        msz = 1;
      else if (JitSeq(jit_id, "I32"))
        msz = 4;
      if (!JitIdent()) {
        jit_err = 1;
        return -1;
      }
      if (jit_cls[ci].nmem >= JIT_MEM_MAX) {
        jit_err = 1;
        return -1;
      }
      // align
      if (msz >= 8)
        off = (off + 7) & -8;
      else if (msz >= 4)
        off = (off + 3) & -4;
      JitCpy(jit_cls[ci].mem[jit_cls[ci].nmem].name, jit_id, JIT_NAME_MAX);
      jit_cls[ci].mem[jit_cls[ci].nmem].off = off;
      jit_cls[ci].mem[jit_cls[ci].nmem].size = msz;
      jit_cls[ci].nmem++;
      off = off + ((msz + 7) & -8);
      // pad members to 8 for simplicity
    }
    JitNeed(';');
  }
  JitNeed('}');
  JitSkip();
  if (*jit_src == ';')
    jit_src++;
  jit_cls[ci].size = (off + 7) & -8;
  if (jit_cls[ci].size < 8)
    jit_cls[ci].size = 8;
  return 1;
}

I64 JitParseFun()
{
  I64 is_void = 0;
  U8 *entry;
  U8 fname[JIT_NAME_MAX];
  JitSkip();
  if (!JitIdent())
    return 0;
  if (JitSeq(jit_id, "U0"))
    is_void = 1;
  else if (JitSeq(jit_id, "I64") || JitSeq(jit_id, "U8") || JitSeq(jit_id, "I32"))
    is_void = 0;
  else
    return 0;
  JitSkip();
  if (*jit_src == '*')
    return 0;
  // typed pointer global, not a function
  if (!JitIdent()) {
    jit_err = 1;
    return -1;
  }
  JitCpy(fname, jit_id, JIT_NAME_MAX);
  if (!JitPeek('('))
    return 0;
  // not a function — global decl maybe
  JitNeed('(');
  jit_pargc = 0;
  JitSkip();
  if (*jit_src != ')') {
    while (jit_pargc < 16) {
      if (!JitIdent()) {
        jit_err = 1;
        return -1;
      }
      if (JitSeq(jit_id, "I64") || JitSeq(jit_id, "U0") || JitSeq(jit_id, "U8") || JitSeq(jit_id, "I32") || JitSeq(jit_id, "U64") || JitSeq(jit_id, "U8")) {
        JitSkip();
        if (*jit_src == '*')
          jit_src++;
        if (!JitIdent()) {
          jit_err = 1;
          return -1;
        }
      }
      JitCpy(jit_pname[jit_pargc], jit_id, JIT_NAME_MAX);
      jit_pargc++;
      JitSkip();
      if (*jit_src == ',') {
        jit_src++;
        continue;
      }
      break;
    }
  }
  JitNeed(')');
  JitSkip();
  if (*jit_src != '{') {
    jit_err = 1;
    return -1;
  }
  jit_argc = jit_pargc;
  jit_local_n = 0;
  jit_next_local = jit_pargc;
  if (jit_next_local > 8)
    jit_next_local = 8;
  entry = jit_at;
  // Register before body so recursive calls resolve.
  JitAdd(fname, entry, jit_argc, is_void);
  JitPrologue();
  // bind param names after frame size is known (incl. stack args >8)
  
  {
    I64 i;
    for (i = 0; i < jit_pargc; i++) {
      JitCpy(jit_lname[jit_local_n], jit_pname[i], JIT_NAME_MAX);
      jit_loff[jit_local_n] = JitSlotOff(i);
      jit_lsize[jit_local_n] = 8;
      jit_local_n++;
    }
  }
  JitGenBlock();
  // fallthrough return 0
  JitLi(10, 0);
  JitEpilogue();
  JitFenceI;
  if (jit_err)
    return -1;
  return 1;
}

I64 JitCallEntry(U8 *entry)
{
  I64 (*fp)();
  fp = entry;
  return fp();
}
I64 JitTry(U8 *line);
// fwd for Run
I64 JitRunFile(U8 *name)
{
  U8 *src, *p, *start;
  I64 n;
  src = FileRead(name);
  if (!src) {
    UartStr("Run: no file ");
    UartStr(name);
    PutCh('\n');
    return -1;
  }
  // Execute as a unit: walk statements
  p = src;
  while (*p) {
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
      p++;
    if (!*p)
      break;
    start = p;
    // find semicolon or function/class end at brace depth 0
    
    {
      I64 depth = 0, in_str = 0, q = 0;
      while (*p) {
        if (in_str) {
          if (*p == '\\' && p[1]) {
            p = p + 2;
            continue;
          }
          if (*p == q)
            in_str = 0;
          p++;
          continue;
        }
        if (*p == '"' || *p == '\'') {
          in_str = 1;
          q = *p;
          p++;
          continue;
        }
        if (*p == '{')
          depth++;
        if (*p == '}')
          depth--;
        if (*p == ';' && depth == 0) {
          p++;
          break;
        }
        if (*p == '}' && depth == 0) {
          p++;
          break;
        }
        p++;
      }
    }
    // temporary NUL
    
    {
      U8 saved = *p;
      U8 *chunk = start;
      // If we stopped at ; the ; is before p. Include it.
      n = p - start;
      if (n > 0 && start[n - 1] != ';' && start[n - 1] != '}') {
        // ok
      }
      // Use a buffer
      
      {
        U8 buf[2048];
        I64 i;
        if (n > 2047)
          n = 2047;
        for (i = 0; i < n; i++)
          buf[i] = start[i];
        buf[n] = 0;
        if (JitTry(buf) < 0)
          return -1;
      }
    }
  }
  return 1;
}
// 1=handled, 0=not ours, -1=error
I64 JitTryOne(U8 *line)
{
  U8 *save, *tramp;
  I64 fi, r, rc;
  U8 fname[JIT_NAME_MAX];
  jit_src = line;
  jit_err = 0;
  JitSkip();
  if (!*jit_src)
    return 0;
  save = jit_src;
  // class
  if (JitIdent() && JitSeq(jit_id, "class")) {
    jit_src = save;
    if (JitParseClass() < 0 || jit_err) {
      UartStr("JIT: class error\n");
      return -1;
    }
    return 1;
  }
  jit_src = save;
  // Run("file");
  if (JitIdent() && JitSeq(jit_id, "Run")) {
    U8 *sp;
    if (!JitNeed('('))
      return -1;
    sp = JitEmitStr();
    if (!sp || !JitNeed(')'))
      return -1;
    JitSkip();
    if (*jit_src == ';')
      jit_src++;
    return JitRunFile(sp);
  }
  jit_src = save;
  // function or typed global
  if (JitIdent() && (JitSeq(jit_id, "I64") || JitSeq(jit_id, "U0") || JitSeq(jit_id, "U8") || JitSeq(jit_id, "I32"))) {
    jit_src = save;
    rc = JitParseFun();
    if (rc > 0)
      return 1;
    if (jit_err) {
      UartStr("JIT: compile error\n");
      return -1;
    }
    // global: I64 gv = 40;  or U8 *s = MAlloc(16);
    jit_src = save;
    
    {
      I64 is_void = 0, sz = 8;
      U8 gname[JIT_NAME_MAX];
      I64 gi;
      JitIdent();
      // type
      if (JitSeq(jit_id, "U8"))
        sz = 1;
      JitSkip();
      if (*jit_src == '*') {
        jit_src++;
        sz = 8;
      }
      if (!JitIdent())
        return 0;
      JitCpy(gname, jit_id, JIT_NAME_MAX);
      JitSkip();
      if (*jit_src == '(')
        return 0;
      // was fun failed
      gi = JitAddGlob(gname, sz < 8 ? 8 : sz);
      if (*jit_src == '=') {
        jit_src++;
        // emit trampoline that stores
        tramp = jit_at;
        jit_argc = 0;
        JitPrologue();
        JitGenExpr();
        JitAbs(5, jit_globs[gi].addr);
        JitSd(10, 0, 5);
        JitEpilogue();
        JitFenceI;
        JitCallEntry(tramp);
      }
      JitSkip();
      if (*jit_src == ';')
        jit_src++;
      return 1;
    }
  }
  jit_src = save;
  // Print("...");
  if (JitIdent() && JitSeq(jit_id, "Print")) {
    U8 *strp;
    if (!JitNeed('('))
      return -1;
    strp = JitEmitStr();
    if (!strp || !JitNeed(')'))
      return -1;
    JitSkip();
    if (*jit_src == ';')
      jit_src++;
    tramp = jit_at;
    jit_argc = 0;
    JitPrologue();
    JitAbs(10, strp);
    JitCallAbs(&PutS);
    JitEpilogue();
    JitFenceI;
    JitCallEntry(tramp);
    return 1;
  }
  jit_src = save;
  // Name(args);  or expr;
  if (JitIdent()) {
    JitCpy(fname, jit_id, JIT_NAME_MAX);
    JitSkip();
    if (*jit_src == '(') {
      fi = JitFind(fname);
      if (fi < 0) {
        UartStr("JIT: unknown fun ");
        UartStr(fname);
        PutCh('\n');
        return -1;
      }
      tramp = jit_at;
      jit_argc = 0;
      jit_pargc = 0;
      jit_local_n = 0;
      jit_next_local = 0;
      JitPrologue();
      // rewind to Name
      jit_src = save;
      JitIdent();
      // consume name
      JitGenCall(fi);
      JitEpilogue();
      JitFenceI;
      if (jit_err) {
        UartStr("JIT: call error\n");
        return -1;
      }
      r = JitCallEntry(tramp);
      if (!jit_funs[fi].is_void)
        Print("ans=%p=%d\n", r, r);
      return 1;
    }
    if (*jit_src == ';') {
      fi = JitFind(fname);
      if (fi >= 0) {
        jit_src++;
        JitFenceI;
        r = JitCallEntry(jit_funs[fi].entry);
        if (!jit_funs[fi].is_void)
          Print("ans=%p=%d\n", r, r);
        return 1;
      }
    }
    // name = expr;  or bare expr involving name
  }
  jit_src = save;
  // general expression / assignment at toplevel
  
  {
    U8 *p = jit_src;
    I64 has_assign = 0;
    while (*p && *p != ';') {
      if (*p == '=' && p[1] != '=')
        has_assign = 1;
      p++;
    }
    if (has_assign || (*jit_src >= '0' && *jit_src <= '9') || *jit_src == '(' || *jit_src == '-' || JitIdent()) {
      jit_src = save;
      // if Ident failed above, still try expr
      tramp = jit_at;
      jit_argc = 0;
      jit_pargc = 0;
      jit_local_n = 0;
      jit_next_local = 0;
      JitPrologue();
      JitGenAssignOrExpr();
      JitSkip();
      if (*jit_src == ';')
        jit_src++;
      JitEpilogue();
      JitFenceI;
      if (jit_err)
        return 0;
      // let I64 eval fallback
      r = JitCallEntry(tramp);
      Print("ans=%p=%d\n", r, r);
      return 1;
    }
  }
  return 0;
}
// Process one or more units on a line (fun def + call, etc.)
I64 JitTry(U8 *line)
{
  I64 rc, got = 0;
  U8 *p = line;
  while (1) {
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')
      p++;
    if (!*p)
      return got ? 1 : 0;
    rc = JitTryOne(p);
    if (rc < 0)
      return -1;
    if (rc == 0)
      return got ? 1 : 0;
    got = 1;
    // advance past what TryOne consumed
    p = jit_src;
  }
}
