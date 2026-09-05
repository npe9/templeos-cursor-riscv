#!/usr/bin/env bash
# Smoke: HolyC AOT REPL — Dir/Src + guest JIT covering core repl-smoke language.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/hc_repl.elf"
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

make -C "$ROOT" holyc-riscv >/dev/null
make -C "$ROOT/bootstrap/hc_repl" all

# Mandate: Mac-AOT guest has no 0x87001xxx host slots and does not link worry_dream/holy_rt.
# seed_embed.hc is generated memfs payload (legacy seed copies as strings) — not guest runtime.
if grep -RIn --include='*.hc' -E '0x87001[0-9A-Fa-f]{3}' "$ROOT/bootstrap/hc_repl" \
  | grep -v seed_embed.hc \
  | grep -v -E 'No 0x87001|no 0x87001'; then
  echo "FAIL hc-repl-smoke — HolyC sources still reference host slots" >&2
  exit 1
fi
if command -v "${CROSS_NM:-riscv64-unknown-elf-nm}" >/dev/null 2>&1; then
  NM="${CROSS_NM:-riscv64-unknown-elf-nm}"
elif command -v nm >/dev/null 2>&1; then
  NM=nm
else
  NM=""
fi
if [ -n "$NM" ] && [ -f "$ELF" ]; then
  if "$NM" "$ELF" 2>/dev/null | grep -Ei 'worry_dream|holy_rt|RuntimeRegister'; then
    echo "FAIL hc-repl-smoke — ELF links C runtime symbols" >&2
    exit 1
  fi
fi

# Core language cases from tests/scripts/run_repl_smoke.sh (HolyC guest JIT path).
input=""
expected=""
add_case() {
  input+="$1"$'\n'
  if [ $# -gt 1 ]; then expected+="$2"$'\n'; fi
}

# G5 hist_seed: cold Up before any session push → HIST_SEED_OK (same as holyc-regression)
input+=$'\x1b[A\n'
# Soft VT mux (console.hc): CONSOLE.md #4 — after hist_seed so Up recalls seed, not Vt*
add_case 'VtList();'
add_case 'Vt(1);'
add_case 'VtPutStr("vt1-session");'
add_case 'VtCapture(1);'
add_case 'Print("vt-cap-line\\n");'
add_case 'VtCapture(0);'
add_case 'VtList();'
add_case 'VtDetach();'
add_case 'VtPane(0,1);'
add_case 'VtPaneOff();'
# /proc-ish (sys.hc) early — before Dir (Dir can be slow on large memfs)
add_case 'Sys();'
# G5 history session Up×1 / Up×2 — before TtyRaw / Src starve the ring
input+=$'Print("HIST_RECALL_OK\\n");\n'
input+=$'\x1b[A\n'
input+=$'Print("HIST_UP2_OK\\n");\n'
input+=$'Print("HIST_UP2_TOP\\n");\n'
input+=$'\x1b[A\x1b[A\n'
# Line discipline (tty.hc): CONSOLE.md #1
add_case 'Tty();'
add_case 'TtyRaw();'
add_case 'Tty();'
add_case 'TtyCanon();'
add_case 'TtyMapIn(13);' 000000000000000a
add_case 'TtyIsErase(8);' 0000000000000001
add_case 'TtyIsErase(127);' 0000000000000001
add_case 'TtyIsKill(21);' 0000000000000001
add_case 'TtyEofHit();' 0000000000000000
add_case 'TtyOnlcrGet();' 0000000000000000
add_case 'TtyOnlcr(1);'
add_case 'TtyOnlcrGet();' 0000000000000001
add_case 'TtyOnlcr(0);'
# Rubout: BS (0x08) and DEL (0x7f) erase last char; echo must be BS-space-BS (not literal "b b").
input+=$'x\x08Print("BS08_ERASE_OK\\n");\n'
input+=$'y\x7fPrint("DEL7F_ERASE_OK\\n");\n'
# Buffer mutation: 9 + BS + 3; → 3 (if erase failed → 93)
input+=$'9\x083;\n'
expected+=$'0000000000000003\n'
# DEL rubout on a typed digit
input+=$'8\x7f4;\n'
expected+=$'0000000000000004\n'
# Term size/type (term.hc): CONSOLE.md #11
add_case 'TermSize(80,24);'
add_case 'TermNameAnsi;'
add_case 'TermRep;'

add_case 'Dir;'
add_case 'Cd("Tutorials");'
add_case 'Pwd();'
add_case 'Cd("/");'
# G28 path bridge: TempleOS prefixes on UART memfs
add_case 'Cd("::/Tutorials");'
add_case 'Pwd();'
add_case 'Cd("A:/");'
add_case 'Cd("~/");'
add_case 'Pwd();'
add_case 'Cd("/");'
add_case 'Cat("Lib/print.hc");'
add_case 'MkDir("Home/Work");'
add_case 'Cd("Home/Work");'
add_case 'Pwd();'
add_case 'Cd("/");'
add_case 'Cat("Home/hello.hc");'
# G3 Src opens Vi — quit like legacy regression (:q)
input+=$'Src("hello.hc");\n:q\r'
add_case 'DumpFile("hello.hc");'
add_case 'DumpMem(0x87800000, 8, "fshead");'
add_case 'FileWrite("Home/jlog.hc","z",1);'
add_case 'FsChanges;'
add_case 'DumpChanges;'
add_case 'FsReplay;'
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
add_case 'I64 Loop(I64 n) { I64 i, s = 0; for (i = 0; i < n; i++) s += i; return s; }'
add_case 'Loop(10);' 000000000000002d
add_case 'I64 Dec(I64 n) { while (n > 0) { n--; } return n; }'
add_case 'Dec(3);' 0000000000000000
add_case 'I64 Pre() { I64 i = 5; I64 j = ++i; return j * 10 + i; }'
add_case 'Pre();' 0000000000000042
add_case 'I64 Arr() { I64 a[4]; a[0] = 1; a[1] = 2; a[2] = 3; return a[0] + a[1] + a[2]; }'
add_case 'Arr();' 0000000000000006
add_case 'I64 Ptr() { I64 x = 1; I64 *p = &x; *p = 7; return x; }'
add_case 'Ptr();' 0000000000000007
add_case 'I64 Chain() { I64 a, b; a = b = 3; return a + b; }'
add_case 'Chain();' 0000000000000006
add_case 'I64 Byte() { U8 b; b = 255; return b; }'
add_case 'Byte();' 00000000000000ff
add_case 'I64 Dw() { I64 i = 0; do { i++; } while (i < 5); return i; }'
add_case 'Dw();' 0000000000000005
add_case 'class P { I64 x; I64 y; };'
add_case 'I64 Cl() { P p; p.x = 1; p.y = 2; return p.x + p.y; }'
add_case 'Cl();' 0000000000000003
add_case 'I64 gv = 40;'
add_case 'gv += 2;' 000000000000002a
add_case 'gv;' 000000000000002a
add_case 'I64 Id(I64 v) { return v; } Id(Id(6));' 0000000000000006
add_case 'I64 Sl(U8 *t) { I64 n = 0; while (t[n]) n++; return n; } Sl("hello!");' 0000000000000006
add_case 'Print("jit-print");'
add_case 'LogInfo("smoke","dmesg-ring");'
add_case 'LogWarn("smoke","warn-needle");'
add_case 'LogErr("smoke","err-needle");'
add_case 'DMesg();'
add_case 'Atoi("123");' 000000000000007b
add_case 'U8 *s = MAlloc(16);'
add_case 'StrCpy(s, "abc");'
add_case 'StrLen(s);' 0000000000000003
add_case 'Man("Print");'
add_case 'Man("CLINT");'
add_case 'Man("Regs");'
add_case 'Sections;'
add_case 'FunsList;'
add_case 'Funs("Print");'
add_case 'SrcFileRep("Print");'
add_case 'FnSizeRep("Print");'
# G5 Tab / CompCollectSyms / multiline indent+complete
add_case 'CompCollectSyms("MEM_PL", 6);' 0000000000000005
add_case 'CompCollectSyms("UART_LSR", 8);' 0000000000000003
add_case 'CompCollectSyms("Pri", 3);' 0000000000000001
add_case '#define SESDEF_TAB_OK 1'
add_case 'CompCollectSyms("SESDEF_TAB", 10);' 0000000000000001
add_case 'CompMidDemo();'
add_case 'RlMidDemo();'
input+=$'Print("MEM_PLIC=%X\\n", MEM_PL\t);\n'
input+=$'pri\t("hc-tab-print\\n");\n'
input+=$'U0 MlTabFn()\n{\n\tPrint("  MLTAB_MARK\\n");\n}\n'
add_case 'MlTabFn();'
# G5 multiline unit recall: Up re-runs braced Print (HIST_ML_OK ≥2)
input+=$'{\nPrint("HIST_ML_OK\\n");\n}\n'
input+=$'\x1b[A\n'
# (HIST_RECALL_OK / HIST_UP2_* wired early after Dir — see above)
# G1 soft Regs / MemMap / StkRep / Callers (HolyC; no host slots)
add_case 'MemMap;'
add_case 'Reg("a0");'
add_case 'Reg("x10");'
add_case 'Man("ABI");'
add_case 'Regs;'
add_case 'StkRep;'
add_case 'I64 CB(){return 7;}'
add_case 'I64 CA(){return CB();}'
add_case 'CA();' 0000000000000007
add_case 'Callers("CB");'
# Compound eval: asm {…}; Reg — post-asm snap (a0 survives HolyC arg clobber)
add_case 'asm { li a0,5 }; Reg("a0");' 0000000000000005

log="$(mktemp)"
# shellcheck disable=SC2086
printf '%s' "$input" | $TIMEOUT_CMD 240 "$QEMU" -M virt -m 128M -bios none -kernel "$ELF" -nographic \
  >"$log" 2>&1 || true

fail=0
need() {
  if ! grep -qF -- "$1" "$log"; then
    echo "FAIL hc-repl-smoke — missing: $1" >&2
    fail=1
  fi
}

need "HolyC AOT REPL"
need "A2: ExePutS owns compile loop"
need "A2: bridge→Jit (Cmp=make repl-cmp / build/repl-cmp.elf)"
need "> "
need "Dir: "
need "Home/"
need "Lib/"
need "Tutorials/"
need "cwd: /Tutorials/"
need "::/Tutorials/"
need "print.hc -- Print / PutChars"
need "cwd: /Home/"
need "::/Home/"
need "cwd: /Home/Work/"
need "hello.hc"
need "Hello from HolyC memfs"
need '$HC_DUMP name=hello.hc'
need '$HC_DUMP name=fshead size=8 addr=0x87800000$'
need '$HC_END$'
need 'W  Home/jlog.hc'
need '$HC_CHANGES'
need 'replay=0'
need "jit-print"
need "--- dmesg ---"
need "dmesg-ring"
need "warn-needle"
need "err-needle"
need "=== sys (UART /proc-ish) ==="
need "--- uptime ---"
need "--- mem ---"
need "--- irq ---"
need "--- devices ---"
need "--- cnts ---"
need "=== tty (line discipline) ==="
need "mode=canon"
need "mode=raw"
need "onlcr=0"
need "eof_hit=0"
need "BS08_ERASE_OK"
need "DEL7F_ERASE_OK"
# Erase echo: after typed 'x' then BS, UART must emit BS-space-BS (0x08 0x20 0x08), not "b b".
if ! grep -aob $'x\x08 \x08' "$log" >/dev/null; then
  echo "FAIL hc-repl-smoke — missing BS-space-BS erase echo after 'x' (0x08)" >&2
  fail=1
fi
if ! grep -aob $'y\x08 \x08' "$log" >/dev/null; then
  echo "FAIL hc-repl-smoke — missing BS-space-BS erase echo after 'y' (DEL→rubout)" >&2
  fail=1
fi
if grep -aob $'xb b' "$log" >/dev/null || grep -aob $'yb b' "$log" >/dev/null; then
  echo "FAIL hc-repl-smoke — erase echoed literal 'b b' (broken Holyc \\\\b escape)" >&2
  fail=1
fi
need "--- term ---"
need "80 x 24"
need "name=ansi"
need "=== VT (soft mux) ==="
need "--- VT 1 (vt1) ---"
need "vt1-session"
need "vt-cap-line"
need "host --vt-panes"
need "VtPane: off"
need "--- VT 0 (repl) ---"
need "repl-holyc ready"
need "formatted print to the UART"
need "Core-Local Interruptor"
need "Regs - dump GPRs"
need "Manual sections"
need "Symbol table:"
need "Funs filter: Print"
need "SrcFile Print=print.hc"
need "FnSize Print="
need "G5: Tab=complete/indent  Up/Down=history"
need "MEM_PLIC="
need "hc-tab-print"
need "  MLTAB_MARK"
need "x=MEM_PLIC;"
# hist_seed cold Up → Print HIST_SEED_OK
if [ "$(grep -cF 'HIST_SEED_OK' "$log" || true)" -lt 1 ]; then
  echo "FAIL hc-repl-smoke — need HIST_SEED_OK (hist_seed Up)" >&2
  fail=1
fi
# History Up re-ran Print → at least two HIST_RECALL_OK
if [ "$(grep -cF 'HIST_RECALL_OK' "$log" || true)" -lt 2 ]; then
  echo "FAIL hc-repl-smoke — need ≥2 HIST_RECALL_OK (history Up)" >&2
  fail=1
fi
# Up×2 re-ran older Print → at least two HIST_UP2_OK (and TOP once from its own Enter)
if [ "$(grep -cF 'HIST_UP2_OK' "$log" || true)" -lt 2 ]; then
  echo "FAIL hc-repl-smoke — need ≥2 HIST_UP2_OK (history Up×2)" >&2
  fail=1
fi
if ! grep -qF 'HIST_UP2_TOP' "$log"; then
  echo "FAIL hc-repl-smoke — missing HIST_UP2_TOP" >&2
  fail=1
fi
# Multiline compile-unit Up recall
if [ "$(grep -cF 'HIST_ML_OK' "$log" || true)" -lt 2 ]; then
  echo "FAIL hc-repl-smoke — need ≥2 HIST_ML_OK (multiline unit Up)" >&2
  fail=1
fi
# G1 soft dbg (HolyC path)
need "Regs (HolyC soft)"
need "FS=1"
need "x10/a0"
need "RISC-V integer register naming"
need "MEM_REGS_SNAP"
need "RVUart"
need "Bt (live)"
need "callers of CB"
need "x10/a0 = 0x0000000000000005"

# Compare ans= oracles as an ordered subsequence of guest ans lines.
# Soft probes like Reg("a0") are I64 and emit ans= that are not oracles —
# index-aligned compare falsely drifts (ans-order); subsequence is honest.
mapfile -t got_ans < <(grep -oE 'ans=0x[0-9a-fA-F]+' "$log" | sed 's/ans=0x//' | tr 'A-F' 'a-f')
mapfile -t exp_ans < <(printf '%s' "$expected")
ans_match() {
  local g="$1" e="$2" g_norm
  if [ "$g" = "$e" ]; then
    return 0
  fi
  g_norm=$(printf '%016x' "0x$g" 2>/dev/null || echo "$g")
  [ "$g_norm" = "$e" ] || [ "$g" = "$e" ]
}
if [ "${#got_ans[@]}" -lt "${#exp_ans[@]}" ]; then
  echo "FAIL hc-repl-smoke — got ${#got_ans[@]} ans lines, expected ≥${#exp_ans[@]}" >&2
  fail=1
else
  gi=0
  i=0
  while [ "$i" -lt "${#exp_ans[@]}" ]; do
    e="${exp_ans[$i]}"
    found=0
    while [ "$gi" -lt "${#got_ans[@]}" ]; do
      g="${got_ans[$gi]}"
      gi=$((gi + 1))
      if ans_match "$g" "$e"; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      echo "FAIL hc-repl-smoke — ans oracle[$i]=$e not found (subsequence after prior oracles)" >&2
      fail=1
      break
    fi
    i=$((i + 1))
  done
fi

if [ "$fail" -ne 0 ]; then
  echo "---- ans lines ----" >&2
  grep -E 'ans=|JIT:' "$log" | head -50 >&2
  echo "---- log tail ----" >&2
  tail -20 "$log" >&2
  rm -f "$log"
  exit 1
fi

echo "HolyC AOT REPL smoke: OK (${#exp_ans[@]} ans oracles + Dir/Src/Print)"
rm -f "$log"
exit 0
