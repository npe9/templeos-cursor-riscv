#!/usr/bin/env bash
# Emit pack_tosb -e NAME:0xOFF args for Compiler.BIN exports from compiler_rv.map.
# Kernel HOFYIMP1 imports these after Load (CmpCtrl*/Wire/Lex/Exe* + CInit/ExePutS/Cmp).
# Usage: eval "PACK_E=( $(tools/compiler_bin_pack_exports.sh [map]) )"
set -u
MAP="${1:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$MAP" ]; then
  MAP="$ROOT/build/compiler_rv.map"
fi
if [ ! -f "$MAP" ]; then
  exit 1
fi
# Required for phase3 Load + Kernel CompilerB imports / Job ExePrint path.
SYMS=(
  CInit
  ExePutS
  Cmp
  LexStmt2Bin
  CmpCtrlNew
  CmpCtrlDel
  Lex
  ExePrint
  ExeFile
  ClassMemberLstDel
  RVCmpWireAsmHash
  RVAotLibSync
  RVCmpCtrlAddrsGet
  RVExePutSSynced
  Ui
  U
)
for s in "${SYMS[@]}"; do
  off=$(awk -v s="$s" '$2==s{print $1; exit}' "$MAP")
  if [ -n "$off" ]; then
    printf -- '-e\n%s:0x%s\n' "$s" "$off"
  fi
done
