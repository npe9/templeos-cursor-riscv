// Regression for x86->RISC-V asm translation of the _MEMSET shape: PUSH/MOV/CLD/REP_STOSB/POP/RET1.
// AsmFill(dst,val,cnt) fills cnt bytes with val and returns dst+cnt (like MemSet). We fill 5 bytes.
U8 *AsmFill(U8 *p, I64 v, I64 n);
asm {
AsmFill::
	PUSH	RBP
	MOV	RBP,RSP
	PUSH	RDI
	CLD
	MOV	RDI,U64 SF_ARG1[RBP]
	MOV	RAX,U64 SF_ARG2[RBP]
	MOV	RCX,U64 SF_ARG3[RBP]
	REP_STOSB
	MOV	RAX,RDI
	POP	RDI
	POP	RBP
	RET1	24
}
I64 main() {
  U8 buf[8]; I64 i; for (i=0;i<8;i++) buf[i]=0;
  AsmFill(buf, 'A', 5);
  return buf[0]<<16 | buf[4]<<8 | buf[5];   // 0x41<<16 | 0x41<<8 | 0 = 0x414100
}
