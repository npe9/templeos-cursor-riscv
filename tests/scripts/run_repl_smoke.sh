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
# Aggregate initializers, F64 %, sub_switch, Free reuse, goto out of try.
add_case 'class Agg { I32 t; U8 name[8]; }; Agg ag[] = { {10, "one"}, {20, "two"}, {30, "three"} }; ag[2].t * 100 + ag[0].t + sizeof(ag) + StrLen(ag[1].name);' 0000000000000be9
add_case 'I64 agi[] = {1, 2, 3}; agi[2] + sizeof(agi) + (7.5 % 2.0 == 1.5);' 000000000000001c
add_case 'U8 *fa = MAlloc(32); Free(fa); U8 *fb = MAlloc(32); fa == fb;' 0000000000000001
add_case 'I64 Gt2() { I64 n = 0; again: n++; try { if (n < 2) goto again; throw(n); } catch { return Fs->except_ch * 10; } } Gt2();' 0000000000000014
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
# Sentinel: the REPL never exits (it spins on the UART after EOF), so stop QEMU as soon as
# the last answer is printed; the timeout only bounds a hung/crashed REPL.
add_case '4919;' 0000000000001337

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
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
printf '%s' "$demo_input" | $TIMEOUT_CMD 60 "$QEMU" -M virt -bios none -kernel "$BOOT/repl.elf" -nographic >"$log" 2>&1 &
qpid=$!
for ((t = 0; t < 600; t++)); do
  if grep -q 'ans=0x0000000000001337' "$log" 2>/dev/null; then break; fi
  kill -0 "$qpid" 2>/dev/null || break
  sleep 0.1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
demo_out="$(tr -d '\r' <"$log")"
for t in "${EXPECT_TEXT[@]}"; do
  if ! echo "$demo_out" | grep -qF -- "$t"; then
    echo "FAIL REPL smoke — demo output missing: $t" >&2
    echo "$demo_out" >&2
    exit 1
  fi
done
n=$(echo "$got" | wc -l | tr -d ' ')
echo "OK   REPL: define/call, redefine, Fib(10), 11 args, loops/++/+=/arrays/pointers/static, Print/strings, switch/do/goto, class, 2-D, macros, F64, casts, fn ptrs, defaults, unsigned, try/catch, top-level switch/try, Fs, aggregates, sub_switch, TempleOS demos, $CALLS calls ($n answers)"
echo "REPL smoke: OK"
