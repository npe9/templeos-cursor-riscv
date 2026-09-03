#!/bin/bash
# Smoke-test the bare-metal REPL (bootstrap/repl.elf) under QEMU: feed statements over the
# UART, compare the printed answers (TempleOS-style "ans=0x..=.." per non-void statement) with the expected sequence.
# Covers cross-statement function calls (exe_addr indirection), redefinition, recursion, >8
# args, and a run of consecutive calls (catches per-statement stack drift).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "error: need timeout or gtimeout" >&2
  exit 2
fi

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

CALLS=64
input=""
expected=""
add_case() { # add_case "<statement>" [expected-hex-16-digits]
  input+="$1"$'\n'
  if [ $# -gt 1 ]; then expected+="$2"$'\n'; fi
}

add_case 'I64 Add(I64 a, I64 b) { return a + b; }'
add_case 'Add(1,1);' 0000000000000002
add_case 'Add(40,2);' 000000000000002a
add_case 'I64 F() { return 1; }'
add_case 'F();' 0000000000000001
add_case 'I64 F() { return 2; }'
add_case 'F();' 0000000000000002
add_case 'I64 Fib(I64 n) { if (n < 2) return n; return Fib(n-1) + Fib(n-2); }'
add_case 'Fib(10);' 0000000000000037
add_case 'I64 Get11th(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i, I64 j, I64 k) { return k; }'
add_case 'Get11th(1,2,3,4,5,6,7,8,9,10,11);' 000000000000000b
# Codegen regressions found by execution probing (each was silently wrong or a no-op before).
add_case 'I64 Loop(I64 n) { I64 i, s = 0; for (i = 0; i < n; i++) s += i; return s; }'
add_case 'Loop(10);' 000000000000002d
add_case 'I64 Dec(I64 n) { while (n > 0) { n--; } return n; }'
add_case 'Dec(3);' 0000000000000000
add_case 'I64 Pre() { I64 i = 5; I64 j = ++i; return j * 10 + i; }'
add_case 'Pre();' 0000000000000042
add_case 'I64 Neg() { I32 v = -1; I64 w = -4; return (v == -1) + (w >> 1 == -2) + (!0) + (~0 == -1); }'
add_case 'Neg();' 0000000000000004
add_case 'I64 Arr() { I64 a[4]; a[0] = 1; a[1] = 2; a[2] = 3; return a[0] + a[1] + a[2]; }'
add_case 'Arr();' 0000000000000006
add_case 'I64 Ptr() { I64 x = 1; I64 *p = &x; *p = 7; return x; }'
add_case 'Ptr();' 0000000000000007
add_case 'I64 Chain() { I64 a, b; a = b = 3; return a + b; }'
add_case 'Chain();' 0000000000000006
add_case 'I64 Byte() { U8 b; b = 255; return b; }'
add_case 'Byte();' 00000000000000ff
add_case 'I64 Cnt() { static I64 c = 0; c++; return c; }'
add_case 'Cnt();' 0000000000000001
add_case 'Cnt();' 0000000000000002
# Top-level grammar, runtime, control flow, aggregates (all execution-checked).
add_case '"%d + %d = %d\n", 40, 2, 42;'   # implicit-print statement: void, no ans= (text checked below)
add_case 'U0 Vd(I64 a) { I64 z = a + 1; }'  # U0 definition: silent
add_case 'Vd(5);'                           # U0 call: void -> NO ans= (guards the RT_U0 void fix)
add_case 'U8 *s = MAlloc(16); StrCpy(s, "abc"); StrLen(s);' 0000000000000003
add_case 'I64 Sw(I64 v) { switch (v) { case 1...5: return 99; case 7: return 70; default: return 0; } }'
add_case 'Sw(3);' 0000000000000063
add_case 'Sw(7);' 0000000000000046
add_case 'Sw(9);' 0000000000000000
add_case 'I64 Dw() { I64 i = 0; do { i++; } while (i < 5); return i; }'
add_case 'Dw();' 0000000000000005
add_case 'I64 Gt() { I64 x = 0; goto mid; x = 100; mid: x = x + 5; return x; }'
add_case 'Gt();' 0000000000000005
add_case 'I64 C2(I64 x) { if (x < 0) return 0; else if (x == 0) return 1; else return 3; }'
add_case 'C2(5) + C2(-1) + C2(0);' 0000000000000004
add_case 'class P { I64 x; I64 y; };'
add_case 'I64 Cl() { P p; p.x = 1; p.y = 2; return p.x + p.y; }'
add_case 'Cl();' 0000000000000003
add_case 'I64 M2() { I64 m[2][3]; I64 i, j, s = 0; for (i = 0; i < 2; i++) for (j = 0; j < 3; j++) { m[i][j] = i + j; s += m[i][j]; } return s; }'
add_case 'M2();' 0000000000000009
add_case '#define TWICE(x) ((x) + (x))'
add_case 'TWICE(0x41) + 1;' 0000000000000083
add_case 'I64 gv = 40;'
add_case 'gv += 2; gv;' 000000000000002a
add_case "'AB' + 0;" 0000000000004241
add_case 'I64 Id(I64 v) { return v; } Id(Id(6));' 0000000000000006
add_case 'I64 Sl(U8 *t) { I64 n = 0; while (t[n]) n++; return n; } Sl("hello!");' 0000000000000006
# F64, casts, HolyC call forms, function pointers, globals in expressions.
add_case 'F64 fa = 7.5; I64 fn = 3; I64 fr = fa / 2.5 + fn * 1.5; fr;' 0000000000000007
add_case '2.5 * 4.0 + 1.0 > 10.0;' 0000000000000001
add_case 'I64 Half(F64 v) { return v / 2.0; } Half(9.0);' 0000000000000004
add_case '(U8)(-1) + (I8)200 + ToI64(2.9);' 00000000000000c9
add_case 'I64 F42() { return 42; } F42 + 1;' 000000000000002b
add_case 'I64 Sq(I64 v) { return v * v; } I64 (*fp)(I64) = &Sq; fp(3);' 0000000000000009
add_case 'I64 ga = 3; I64 gb = 4; ga * gb + ga;' 000000000000000f
# Default arguments, unsigned arithmetic, try/catch/throw (incl. across a call and nested).
add_case 'I64 Dflt(I64 a, I64 b = 3) { return a + b; } Dflt(2) * 10 + Dflt(2, 4);' 0000000000000038
add_case 'U64 ubig = -1; (ubig > 0) + (ubig / 2 == 0x7FFFFFFFFFFFFFFF) + ((U32)(-1) >> 4 == 0x0FFFFFFF);' 0000000000000003
add_case 'I64 Fc(I64 r){ return (2<=r<=36)+10*(1<r<5<9)+100*(48<=r<=57); } Fc(3)+Fc(50)*1000;' 00000000000186ab
add_case 'I64 Sum(I64 n,...){ I64 i,s=n; for (i=0;i<argc;i++) s+=argv[i]; return s; } Sum(1,2,3)*10+Sum(4);' 0000000000000040
add_case 'U8 Hx(I64 n){ return "0123456789ABCDEF"(U8 *)[n&15]; } I64 Vx(){ I64 vv=5; return Hx(11)*256+vv(U8)+(&vv)(U8 *)[0]; } Vx();' 000000000000420a
add_case 'I64 Mth(){ return Sign(2.0`10.0-1023.5)+Sign(Sqrt(16.0)-3.9)+Sign(Exp(Ln(8.0))-7.9)+(Floor(2.7)==2.0)+(Round(2.5)==3.0); } Mth();' 0000000000000005
add_case 'I64 Ad3(I64 a,I64 b){ return a+b; } I64 Cl(){ I64 (*fp)(I64,I64)=&Ad3; return (*fp)(3,4); } Cl();' 0000000000000007
add_case 'I64 Sw(I64 x){ switch [x] { case -1: return 2; case 97: return 3; case 1...3: return 4; } return 0; } I64 Kk(I64 a,I64){ a>>=2; a<<=1; a%=7; lock a++; return a; } Sw(-1)*1000+Sw(97)*100+Sw(2)*10+Kk(40,9);' 000000000000092b
add_case 'I64 Sv(I64 d=7){ return d; } class CQz {I64 a; U8 b; I64 c;}; I64 Qq(){ I64 x=Sv; return x*100+offset(CQz.c)+0b101+0o10+0d3; } Qq();' 00000000000002d5
add_case 'I64 Pc(){ I64 a=$$; I64 b=$$; return b>a; } Pc();' 0000000000000001
add_case 'I64 gq=2; I64 Fq(I64 a,I64 b=gq*2){ return a+b; } F64 K(){ return 2.5; } F64 Dm(F64 hi=F64_MAX){ return hi; } I64 Tq(){ return Fq(2)*100+(K()==2.5)*10+(Dm>1e300); } Tq();' 0000000000000263
add_case 'I64 Rq(){ I64 reg RSI a=4, reg R13 b=5; return a+b; } class CE { U8 t[8] format "$$DA-P,", u[4]; I64 n; }; Rq()*100+sizeof(CE.u)*10+(1^^0)+(3.0<=4.0<=5.0);' 00000000000003ae
add_case 'I64 Boom() { throw(7); return 1; }'
add_case 'I64 Try2() { try { Boom(); return 99; } catch { return Fs->except_ch + 100; } }'
add_case 'Try2();' 000000000000006b
add_case 'I64 Try5() { try { try { throw(1); } catch { throw(2); } } catch { return Fs->except_ch * 10; } return 0; } Try5();' 0000000000000014
add_case 'I64 Try3() { try { return 5; } catch { return 6; } } Try3() + Try2() - 107;' 0000000000000005
# Top-level switch/try, omitted arguments, Fs->except_ch as a call argument, runtime breadth.
add_case 'I64 tv = 2; switch (tv) { case 2: "two\n"; break; default: "other\n"; } tv * 3;' 0000000000000006
add_case 'try { throw(5); } catch { "caught %d\n", Fs->except_ch; } Fs->except_ch + 100;' 0000000000000069
add_case 'I64 Om(I64 a = 1, I64 b = 2, I64 c = 3) { return a * 100 + b * 10 + c; } Om(,5) - Om(7,,9);' fffffffffffffdc0
add_case 'I64 Tb() { I64 i; for (i = 0; i < 3; i++) { try { if (i == 1) break; } catch { return 99; } } try { throw(4); } catch { return Fs->except_ch; } } Tb();' 0000000000000004
add_case 'U8 *cat = MAlloc(16); StrCpy(cat, "ab"); StrCat(cat, "cd"); StrLen(cat) + MaxI64(3, 9) + ToUpper(0x61) - 0x41 + AbsI64(-2);' 000000000000000f
# TempleOS Str2I64 / Atoi (seed str.hc): decimal, signs, 0x/0b prefixes.
add_case 'Atoi("123");' 000000000000007b
add_case 'Atoi("-42");' ffffffffffffffd6
add_case 'Atoi("0x10");' 0000000000000010
add_case 'Str2I64("0b1010");' 000000000000000a
add_case 'Str2I64("  +99xyz",10);' 0000000000000063
# Aggregate initializers, F64 %, sub_switch, Free reuse, goto out of try.
add_case 'class Agg { I32 t; U8 name[8]; }; Agg ag[] = { {10, "one"}, {20, "two"}, {30, "three"} }; ag[2].t * 100 + ag[0].t + sizeof(ag) + StrLen(ag[1].name);' 0000000000000be9
add_case 'I64 agi[] = {1, 2, 3}; agi[2] + sizeof(agi) + (7.5 % 2.0 == 1.5);' 000000000000001c
add_case 'U8 *fa = MAlloc(32); Free(fa); U8 *fb = MAlloc(32); fa == fb;' 0000000000000001
add_case 'I64 Gt2() { I64 n = 0; again: n++; try { if (n < 2) goto again; throw(n); } catch { return Fs->except_ch * 10; } } Gt2();' 0000000000000014
# Terminal geometry is HolyC-owned (seed/term.hc g_term_*). Piped UART has no emulator
# reply so TermProbe keeps 80x24; TermSetSize must stick in HolyC state (Vi/EditHoly read it).
add_case 'TermRows();' 0000000000000018
add_case 'TermCols();' 0000000000000050
add_case 'KEY_UP;' 0000000000000100
add_case 'TermSetSize(40,100); TermRows()*1000+TermCols();' 0000000000009ca4
add_case 'TermSetSize(24,80); TermRows()*1000+TermCols();' 0000000000005e10
# TermSize is cols-first (stty): TermSize(100,40) ≡ TermSetSize(40,100)
add_case 'TermSize(100,40); TermRows()*1000+TermCols();' 0000000000009ca4
add_case 'TermSize(80,24); TermRows()*1000+TermCols();' 0000000000005e10
for ((i = 1; i <= CALLS; i++)); do
  add_case "Add($i,1);" "$(printf '%016x' $((i + 1)))"
done

# Whole TempleOS demo files (second QEMU run, below), fed line by line like a user would; their
# printed output is checked for expected fragments.
EXPECT_TEXT=()
demo_input=""
add_file() { demo_input+="$(cat "$ROOT/$1")"$'\n'; }
expect_text() { EXPECT_TEXT+=("$1"); }
add_file Demo/NullCase.HC
expect_text 'Eleven'
add_file Demo/Print.HC
expect_text '123,456,789'
expect_text 'yyyyyyyyyyyyyyyyyyyyyyyyy'
add_file Demo/SubSwitch.HC
expect_text 'Zero [One] Two [Three] Four [Five]'
add_file Demo/RadixSort.HC
expect_text 'Output'
expect_text '15:'
add_file Demo/Exceptions.HC
expect_text 'D1'
add_file Demo/GlblVars.HC
expect_text 'Time 2:'
expect_text 'Static3'
# Auto-boot: boot.hc runs at startup, prints its banner and loads uart.hc -- so UartStr works
# here with NO manual Run() first (proves the system brings up its own HolyC layer).
demo_input+=$'UartStr("autoboot-live ");\n'
expect_text '[boot] HolyC primitives loaded'
expect_text 'autoboot-live '
demo_input+=$'"term %d x %d\\n", TermRows(), TermCols();\n'
expect_text 'term 24 x 80'
# Incremental Run: a file that Run()s a driver AND uses it (on a later line) -- each unit runs
# before the next compiles, so this no longer hangs (regression guard for run_source).
demo_input+=$'Ed("df.hc");\na\nRun("uart.hc");\nUartStr("df-same ");\n.\nw\nq\nRun("df.hc");\n'
expect_text 'df-same '
# Funs("Print") = filter-only dump (no Esc). FunsList; = full non-blocking dump.
# Interactive Funs; still needs a live Esc (TermKeyGet) — not in this smoke.
# StrIMatch must be live (was CALL_IMPORT hang). Man/SrcFile cover HolyC Cat.
demo_input+=$'"StrIMatch live=%d\\n", FnAddr("StrIMatch")!=0;\n"StrIMatch ab=%d\\n", StrIMatch("ab","xxabxx",0)!=0;\nFuns("Print");\nFunsList();\nMan("Cat");\n"SrcFile Cat=%s\\n", SrcFile("Cat");\nDisasm("Cat");\n'
expect_text 'StrIMatch live=1'    # HolyC StrIMatch is a live HTT_FUN (not unresolved import)
expect_text 'StrIMatch ab=1'      # case-sensitive substring match returns non-NULL
expect_text 'Funs  filter: Print' # filter-only dump via StrIMatch
expect_text 'Src-editable'        # FunsList() summary line
expect_text '(HolyC)'             # Man("Cat") header
expect_text 'Reads name from the memfs'  # Man("Cat") DESCRIPTION from files.hc
expect_text 'SrcFile Cat=files.hc'
expect_text 'addi sp'             # HolyC frame setup from Disasm("Cat")
# FunsSec(n) filters by manual section; FunSec maps names; Sections prints the legend.
# (Avoid full FunsS() here -- hundreds of lines flood the QEMU UART capture.)
demo_input+=$'FunsSec(3);\n"FunSec Dir=%d UartPut=%d MAlloc=%d\\n", FunSec("Dir"), FunSec("UartPut"), FunSec("MAlloc");\nSections();\n'
expect_text '--- 3 terminal ---'
expect_text 'in section 3'
expect_text 'FunSec Dir=2 UartPut=3 MAlloc=9'
expect_text 'Manual sections'
# FunCount/FunName feed Funs/FunPick; FunWrite dumps .funlist.
demo_input+=$'FunWrite();\nCat(".funlist");\n'
expect_text 'wrote .funlist'
expect_text 'FunPick'             # FunPick itself is in the symbol list after boot
expect_text 'FunsList'            # dump helper stays registered
# HolyC disassembler decodes floats and compressed instructions
demo_input+=$'F64 Fa(F64 a,F64 b){return a+b;}\nDisasm("Fa");\n'
expect_text 'fadd.d'                    # a float op decoded
demo_input+=$'Disasm("UartPut");\n'
expect_text '<UART0>'                   # lui of an MMIO base gets its memory-map name
# Man/SrcFile for HolyC Print + seeds (FnSize checks after MemMap — keeps Vi early)
demo_input+=$'Man("Print");\n"SrcFile Print=%s\\n", SrcFile("Print");\n"SrcFile StrLen=%s\\n", SrcFile("StrLen");\n"SrcFile MAlloc=%s\\n", SrcFile("MAlloc");\n"SrcFile Dir=%s\\n", SrcFile("Dir");\n'
expect_text 'formatted print'
expect_text 'SrcFile Print=print.hc'
expect_text 'SrcFile StrLen=str.hc'
expect_text 'SrcFile MAlloc=mem.hc'
expect_text 'SrcFile Dir=dir.hc'
# vim-lite: insert a line, save with :wq, run the file (raw keys: i..., ESC, :wq, Enter)
demo_input+=$'Vi("vf.hc");\niUartStr("vsmoke ");\x1b:wq\rRun("vf.hc");\n'
expect_text 'vsmoke '
# Inspection + in-editor exec + HolyC FnSize proofs
demo_input+=$'MemMap();\nRegs();\n"FnSize Print=%d\\n", FnSize("Print");\n"FnSize StrLen=%d\\n", FnSize("StrLen");\n"FnSize MAlloc=%d\\n", FnSize("MAlloc");\n"FnSize Run=%d\\n", FnSize("Run");\n"FnSize TermKeyGet=%d\\n", FnSize("TermKeyGet");\nEd("q.hc");\n!6*7;\nq\n'
expect_text 'code_mem'
expect_text 'FnSize Print='
expect_text 'FnSize StrLen='
expect_text 'FnSize MAlloc='
expect_text 'FnSize Run='
expect_text 'FnSize TermKeyGet='
expect_text 'mstatus'
expect_text 'ans=0x000000000000002a'   # !6*7; ran HolyC from inside Ed
# HolyC debugger: break on a function, confirm the args are reported, execution continues.
demo_input+=$'I64 Dg(I64 x,I64 y){return x+y;}\nBp(&Dg);\nDg(11,22);\n'
expect_text 'breakpoint @'
expect_text 'a0=0xB'                    # x=11 at the break
expect_text 'ans=0x0000000000000021'   # Dg still returns 33
# In-memory filesystem + ed editor: create a file, append a line, write, then list and cat it
# back -- exercises the nested UART reader (a registered C fn reading its own lines while called
# from JIT'd HolyC), the fixed-slot memfs, and Ed's a/w/q + Dir/Cat.
demo_input+=$'Ed("smoke.hc");\na\nEditor line one\nEditor line two\n.\nw\nq\nDir;\nCat("smoke.hc");\n'
expect_text 'ed smoke.hc:'
expect_text 'wrote smoke.hc'
expect_text 'smoke.hc  '
expect_text 'Editor line two'
# Format-on-save (HolyFmtSrc AST/CST): Ed w rewrites messy .hc (2-space; Allman fn; spaced if).
demo_input+=$'Ed("fmtme.hc");\na\nU0 Foo(I64 x)\n  {\nif(x){\nreturn;\n}\n}\n.\nw\nq\nCat("fmtme.hc");\n'
expect_text 'wrote fmtme.hc (45 bytes)'
expect_text $'U0 Foo(I64 x)\n{\n  if (x) {\n    return;\n  }\n}'
# Explicit Fmt("…"): FileWrite is raw; Fmt must change bytes and print confirmation.
demo_input+=$'FileWrite("fmt_raw.hc","I64 Z(){return 1;}",18);\nCat("fmt_raw.hc");\nFmt("fmt_raw.hc");\nCat("fmt_raw.hc");\n'
expect_text 'I64 Z(){return 1;}'
expect_text 'Fmt: fmt_raw.hc (24 bytes, rewritten)'
expect_text $'I64 Z()\n{\n  return 1;\n}'
# Full-screen editor (Edit): type a line, ^O (\017) to save, ^X (\030) to exit, then cat it
# back. Exercises the ANSI render loop, the blocking key reader, and the save path.
demo_input+=$'Edit("scr.hc");\nVisual editor works\017\030Cat("scr.hc");\n'
expect_text 'wrote scr.hc'
expect_text 'Visual editor works'
# Self-hosting: author a file with Ed, Run() it (compile+execute in place), call what it defined.
demo_input+=$'Ed("run.hc");\na\nI64 Trip(){ return 111; }\n.\nw\nq\nRun("run.hc");\nTrip();\n'
expect_text 'ans=0x000000000000006f'   # Trip() == 111, defined in the Run() file
# Cd / Copy / Find / DirMk -- cwd-aware memfs, TempleOS command-line file ops.
demo_input+=$'DirMk("T");\nEd("T/hi.hc");\na\nUartStr("hi-act ");\n.\nw\nq\nCd("T");\nPwd();\nFileFind("hi.hc");\nCd("..");\nCopy("T/hi.hc","T/hi2.hc");\nFind("hi-act","*.hc");\n'
expect_text 'cwd: /T/'
expect_text '/T/'
expect_text 'hi.hc ('
expect_text 'copied T/hi.hc -> T/hi2.hc'
expect_text 'T/hi.hc:'
# Enter-to-activate (DolDoc Vi on .dirlist) is timing-sensitive on piped UART; Dir of T/
# still proves the hierarchical listing (padded name) after Copy.
demo_input+=$'Cd("T");\nDir;\nCd("/");\n'
expect_text '  hi.hc  '
# Hierarchical memfs: Dir of /, Cd into Tutorials, Cat by path; MkDir alias; basename still works
demo_input+=$'Dir;\nCd("Tutorials");\nPwd();\nDir;\nCat("A01_RV64I.hc");\nCd("/");\nCat("Lib/print.hc");\nMkDir("Home/Work");\nCd("Home/Work");\nPwd();\nCd("/");\n'
expect_text ' Tutorials/'
expect_text 'cwd: /Tutorials/'
expect_text '/Tutorials/'
expect_text 'A01_RV64I.hc  '
expect_text 'A01_RV64I.hc -- Part A1'
expect_text 'print.hc -- Print / PutChars'
expect_text 'cwd: /Home/Work/'
expect_text '/Home/Work/'
# dmesg ring (log.hc): Log* silent; DMesg dumps to UART
demo_input+=$'LogInfo("smoke","dmesg-ring");\nLogWarn("smoke","warn-needle");\nLogErr("smoke","err-needle");\nDMesg();\n'
expect_text '--- dmesg ---'
expect_text 'dmesg-ring'
expect_text 'warn-needle'
expect_text 'err-needle'
# /proc-ish (sys.hc): CONSOLE.md #10
demo_input+=$'Sys();\n'
expect_text '=== sys (UART /proc-ish) ==='
expect_text '--- uptime ---'
expect_text '--- mem ---'
expect_text '--- irq ---'
expect_text '--- devices ---'
expect_text '--- cnts ---'
# Line discipline (tty.hc): CONSOLE.md #1
demo_input+=$'Tty();\nTtyRaw();\nTty();\nTtyCanon();\n'
expect_text '=== tty (line discipline) ==='
expect_text 'mode=canon'
expect_text 'mode=raw'
demo_input+=$'"tty-map=%d erase=%d kill=%d onlcr=%d eof=%d\\n", TtyMapIn(13), TtyIsErase(8), TtyIsKill(21), TtyOnlcrGet(), TtyEofHit();\n'
expect_text 'tty-map=10 erase=1 kill=1 onlcr=0 eof=0'
# Soft VT mux (console.hc): CONSOLE.md #4 — VT0=REPL; opt-in VtCapture
demo_input+=$'VtList();\nVt(1);\nVtPutStr("vt1-session");\nVtCapture(1);\nPrint("vt-cap-line\\n");\nVtCapture(0);\nVtList();\nVtDetach();\n'
expect_text '=== VT (soft mux) ==='
expect_text '--- VT 1 (vt1) ---'
expect_text 'vt1-session'
expect_text 'vt-cap-line'
expect_text '--- VT 0 (repl) ---'
# Term size/type (term.hc): CONSOLE.md #11
demo_input+=$'TermSize(80,24); TermNameAnsi; TermRep;\n'
expect_text '--- term ---'
expect_text '80 x 24'
expect_text 'name=ansi'
expect_text 'HolyC primitives loaded'
# Memfs change journal (P0): HolyC FileWrite after boot seal → FsChanges/FsLog.
demo_input+=$'FileWrite("Home/jlog.hc","z",1);\nFsChanges;\nFsLog(6);\nFsEpoch;\n'
expect_text 'epoch='
expect_text 'W  Home/jlog.hc'
expect_text 'fs log tail'
# C EdC `w` must journal like HolyC FileWrite (HashFind FsJournal).
demo_input+=$'EdC("Home/clog.hc");\na\nc\n.\nw\nq\nFsChanges;\nDel("Home/clog.hc");\n'
expect_text 'W  Home/clog.hc'
# P1: checkpoint, epoch-range FsDiff, quiet tooling (.p1q hidden unless FS_CH_ALL).
demo_input+=$'FsCheckpoint("p1");\nFileWrite("Home/jlog.hc","zz",2);\nFileWrite(".p1q","n",1);\nFsDiff(0);\nFsChanges(-1, 1);\n'
expect_text 'fs checkpoint 1'
expect_text 'diff epoch (0,'
expect_text 'W  .p1q'
# P4: in-place Rename journals R, not Copy+Del.
demo_input+=$'FileWrite("Home/rn.hc","a",1);\nRename("Home/rn.hc","Home/rn2.hc");\nFsChanges;\nDel("Home/rn2.hc");\n'
expect_text 'renamed Home/rn.hc -> Home/rn2.hc'
expect_text 'R  Home/rn.hc'
# Edit + compile + install a trap handler in place: define one in a file, Run it,
# TrapInit()/SetTrap(), then Ecall() to fire a synchronous trap into the HolyC handler.
demo_input+=$'Ed("ontrap.hc");\na\nI64 Zap(I64 c,I64 e,I64 t){ "ZAP-HIT "; return 0; }\n.\nw\nq\nRun("ontrap.hc");\nTrapInit();\nSetTrap("Zap");\nEcall();\n'
expect_text 'ZAP-HIT'
# Sync fault with a SetTrap handler installed (Zap returns 0): dump, abort the eval, next statement runs.
demo_input+=$'*(U8 *)1=7;\n"after-fault\\n";\n'
expect_text 'store access fault'
expect_text 'eval aborted'
expect_text 'after-fault'
# Editable kernel primitive: the seeded uart.hc driver, Run() then edited in place (insert an
# uppercase step into UartPut) and re-Run -- the same UartStr call changes behavior live.
# Line 67 is the lone `;` of `while (LSR)\n    ;` after --fmt; `67a` inserts before the THR store.
demo_input+=$'Run("uart.hc");\nUartStr("livedrv ");\nEd("uart.hc");\n150a\n  if (ch>=97 && ch<=122) ch -= 32;\n.\nw\nq\nRun("uart.hc");\nUartStr("livedrv ");\n'
expect_text 'livedrv '   # before the edit: lowercase
expect_text 'LIVEDRV '   # after the live edit: uppercase, same call site
# Jump-to-definition: SrcFile → nested Vi/EditHoly session; :q/^X pops back to prior buffer.
# jmp.hc's first token is UartPut.
demo_input+=$'"SrcFile UartPut: %s\\n", SrcFile("UartPut");\n"SrcFile Dir: %s\\n", SrcFile("Dir");\n"SrcFile TrapVec: %s\\n", SrcFile("TrapVec");\n'
expect_text 'SRCFILE UARTPUT: UART.HC'   # UartPut still uppercases after livedrv
expect_text 'SRCFILE DIR: DIR.HC'
expect_text 'SRCFILE TRAPVEC: TRAP.HC'
# Datasheet bitfield decode (ds.hc + datasheet/ds_*.hc) — fabricated LSR + live mstatus.
# Runs after livedrv, so UART output is uppercased by the edited UartPut.
demo_input+=$'"ds-thre=%d ds-dr=%d\\n", DsFieldGet("uart.lsr","THRE",0x21), DsFieldGet("uart.lsr","DR",0x21);\nDsDecode("uart.lsr",0x21);\nDsDecode("mstatus");\nDsFind("uart");\n'
expect_text 'DS-THRE=1 DS-DR=1'
expect_text 'DSDECODE UART.LSR'
expect_text '[5] THRE'
expect_text 'DSDECODE MSTATUS'
expect_text '[3] MIE'
expect_text 'UART.LSR'
demo_input+=$'Ed("jmp.hc");\na\nUartPut(65);\n.\nw\nq\nVi("jmp.hc");\ngd:q\r:q\r'
expect_text '-- NORMAL -- UART.HC'     # nested session status (uppercased by livedrv)
expect_text '-- NORMAL -- JMP.HC'      # after :q, parent session restored
demo_input+=$'Edit("jmp.hc");\n\x1d\x18\x18'
expect_text 'UART.HC LN '              # EditHoly ^] nests; first ^X pops
# Reverse xref: A calls B; Callers("B") lists A (JIT exe_addr-slot scan).
demo_input+=$'I64 B(){return 7;}\nI64 A(){return B();}\nA();\nCallers("B");\n'
expect_text 'ans=0x0000000000000007'
expect_text ') A'
expect_text 'callers of B'
# Sentinel: the REPL never exits (it spins on the UART after EOF), so stop QEMU as soon as
# the last answer is printed; the timeout only bounds a hung/crashed REPL.
add_case '4919;' 0000000000001337

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
# Default virt RAM is 128MiB (enough for memfs @0x87800000). Do not require -m 256M.
printf '%s' "$input" | $TIMEOUT_CMD 60 "$QEMU" -M virt -bios none -kernel "$BOOT/repl.elf" -nographic >"$log" 2>&1 &
qpid=$!
for ((t = 0; t < 600; t++)); do
  if grep -q 'ans=0x0000000000001337' "$log" 2>/dev/null; then break; fi
  kill -0 "$qpid" 2>/dev/null || break
  sleep 0.1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
out="$(tr -d '\r' <"$log")"
got="$(echo "$out" | grep -oE 'ans=0x[0-9a-f]{16}' | sed 's/ans=0x//' || true)"

if [ "$got" != "${expected%$'\n'}" ]; then
  echo "FAIL REPL smoke — answer sequence mismatch" >&2
  diff <(echo "${expected%$'\n'}") <(echo "$got") >&2 || true
  echo "--- REPL transcript ---" >&2
  echo "$out" >&2
  exit 1
fi
if ! echo "$out" | grep -q '^40 + 2 = 42$' || ! echo "$out" | grep -q '^caught 5$'; then
  echo "FAIL REPL smoke — Print output missing (expected '40 + 2 = 42')" >&2
  echo "$out" >&2
  exit 1
fi
# Second run: the demo files.
demo_input+='4919;'$'\n'
: >"$log"
printf '%s' "$demo_input" | $TIMEOUT_CMD 300 "$QEMU" -M virt -bios none -kernel "$BOOT/repl.elf" -nographic >"$log" 2>&1 &
qpid=$!
for ((t = 0; t < 3000; t++)); do
  if grep -q 'ans=0x0000000000001337' "$log" 2>/dev/null; then break; fi
  kill -0 "$qpid" 2>/dev/null || break
  sleep 0.1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
demo_out="$(tr -d '\r' <"$log")"
for t in "${EXPECT_TEXT[@]}"; do
  if ! grep -qF -- "$t" "$log"; then
    echo "FAIL REPL smoke — demo output missing: $t" >&2
    echo "$demo_out" >&2
    exit 1
  fi
done
n=$(echo "$got" | wc -l | tr -d ' ')
echo "OK   REPL: define/call, redefine, Fib(10), 11 args, loops/++/+=/arrays/pointers/static, Print/strings, switch/do/goto, class, 2-D, macros, F64, casts, fn ptrs, defaults, unsigned, try/catch, top-level switch/try, Fs, aggregates, sub_switch, TempleOS demos, $CALLS calls ($n answers)"
echo "REPL smoke: OK"
