// Native RISC-V ports of the asm-callable print helpers TempleOS writes in x86 in Kernel/StrA.HC.
//
// Demo/Asm/AsmHelloWorld.HC calls these "many useful kernel routines intended to be called from
// asm", and they are the reason those demos exist: they let an asm{} block print without dropping
// back into HolyC. On x86 they are thin shims — PUSH_C_REGS, push the args, CALL the HolyC
// PutHex/PutChars/PutS, POP_C_REGS, RET — and that whole block is x86, so this assembler drops it
// and the names are absent from every RISC-V image.
//
// The HolyC targets are all present and live: PutHex is Kernel/StrA.HC:12 (outside the dropped
// block), PutChars and PutS are Kernel/KeyDev.HC:21 and :31.
//
// KNOWN LIMIT, measured: exactly ONE `call` per asm{} block works. Each shim below has one and
// each prints correctly (PUT_HEX_U8(0xAB) -> "AB", PUT_HEX_U16 -> "00AB", PUT_HEX_U32 ->
// "000000AB", PUT_CHARS -> the raw byte). TWO calls in one block does NOT work: the second loses
// its argument register — `li a0,0x1234` before a second `call` printed "AB" again, then trapped —
// because of how `call` lowers. Asm `call` emits IC_CALL, and host/compiler.c's IC_CALL case is
// EmitCallArgsAndInvoke, which loads arguments into a0-a7 FROM THE COMPILER'S STACK-DEPTH MODEL
// and adjusts that model. With zero modelled arguments it leaves a0 alone — which is exactly why
// one call works — but it still moves the model, so a second call in a raw block computes its
// offsets from a state the raw instructions did not maintain. Raw register setup and
// compiler-managed calls do not compose.
//
// The fix, when someone wants it: an asm-only call that emits a plain jal/jalr to the label with
// no argument machinery. EmitLabelAddr (used by IC_FN_ADDR) already materialises a label address,
// so it would be EmitLabelAddr into a scratch register plus `jalr ra,rs` — contained, but a
// compiler-internals change that deserves its own gate.
//
// Nothing else in the tree uses `call` inside an asm{} block, so this had never been exercised. It is why Demo/Asm/AsmHelloWorld.HC, PutDec.HC and BuzzFizz.HC are still
// untranslated: each makes several calls in one block.
//
// Register discipline differs from the x86 original and callers must know it. x86 wrapped each
// shim in PUSH_C_REGS/POP_C_REGS so a caller could treat them as clobbering nothing. Here the
// ordinary RISC-V convention applies: a0-a7 and t0-t6 are caller-saved and a call through these
// may clobber them; s0-s11 survive. An asm{} block that keeps live values in t-registers across
// one of these must save them itself.

// U0 PUT_HEX_U64(a0=num) — 16 hex digits, via PutHex(num,16).
asm {
PUT_HEX_U64::
	addi	sp,sp,-16
	sd	ra,8(sp)
	li	a1,16
	call	PutHex
	ld	ra,8(sp)
	addi	sp,sp,16
	ret
}
// U0 PUT_HEX_U32(a0=num) — 8 digits. The x86 twin of this one is the block the skip registry
// names as StrA.HC:20 PUT_HEX_U32.
asm {
PUT_HEX_U32::
	addi	sp,sp,-16
	sd	ra,8(sp)
	li	a1,8
	call	PutHex
	ld	ra,8(sp)
	addi	sp,sp,16
	ret
}
// U0 PUT_HEX_U16(a0=num) — 4 digits.
asm {
PUT_HEX_U16::
	addi	sp,sp,-16
	sd	ra,8(sp)
	li	a1,4
	call	PutHex
	ld	ra,8(sp)
	addi	sp,sp,16
	ret
}
// U0 PUT_HEX_U8(a0=num) — 2 digits.
asm {
PUT_HEX_U8::
	addi	sp,sp,-16
	sd	ra,8(sp)
	li	a1,2
	call	PutHex
	ld	ra,8(sp)
	addi	sp,sp,16
	ret
}
// U0 PUT_CHARS(a0=multi-byte char constant) — prints its bytes until a zero one.
asm {
PUT_CHARS::
	addi	sp,sp,-16
	sd	ra,8(sp)
	call	PutChars
	ld	ra,8(sp)
	addi	sp,sp,16
	ret
}
// U0 PUT_STR(a0=string) — x86 takes this in RSI; on RISC-V it is simply the first argument.
asm {
PUT_STR::
	addi	sp,sp,-16
	sd	ra,8(sp)
	call	PutS
	ld	ra,8(sp)
	addi	sp,sp,16
	ret
}
