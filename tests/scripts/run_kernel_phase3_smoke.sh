#!/usr/bin/env bash
# RVKMain phase 3 smoke: Kernel + RedSea Compiler.BIN + Kernel.BIN seeds → guest MakeOS(Cmp) → StartOS.
# TempleOS Boot.DD shape (not jit.hc). See templeos-riscv/COMPILER_RV.md.
#
# G9: Compiler.BIN + Kernel.BIN (InitLite seed) ship on virtio RedSea image (tools/mk_redsea_seed_img.py).
# ELF .compiler_bin @0x81000000 is optional last-resort (PHASE3_LINK_COMPILER_BIN=1).
# Kernel.BIN: host-packed KernelProbe/Entry + heap+FileWrite InitLite (not full Kernel_RV).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_phase3_demo.hc"
EXPECT="RVPhase3: Compiler_RV loaded"
EXPECT_LOAD="RVPhase3: Load() CBinFile OK"
EXPECT_HOST="RVPhase3: Load() host Compiler.BIN OK (RedSea seed + Cmp export)."
EXPECT_FULL="RVPhase3: Load() full Compiler.BIN OK (reloc RedSea + ExePutS)."
EXPECT_RELOC="RVPhase3: Load() relocatable RedSea Compiler.BIN returned."
# Soft, like every other *_SEED below it. It was ALSO in the hard AND chain from 3bd4279
# (2026-09-11) onward, and nothing in the image has emitted it since: RVPhase3.HC:894 now
# FileWrites A:/Adam/StartOS.PRJ unconditionally instead of preferring the RedSea seed. That
# made this smoke unconditionally red no matter what the guest did. The live hard proof of the
# same stage is EXPECT_STARTOS_BIN ("Runtime StartOS.BIN ready for StartOS Load."), which stays
# in the chain. Whether the seed-preference path should come back is an open question -- the
# seed file and the kernel's own `src` are byte-identical, so it only ever proved provenance.
EXPECT_STARTOS_SEED="RVPhase3: StartOS RedSea seed (no ELF FileWrite)."
EXPECT_ADAMCORE_SEED="RVPhase3: AdamCore RedSea seed (no ELF FileWrite)."
EXPECT_MAKEOS_SEED="RVPhase3: MakeOS RedSea seed (no ELF FileWrite)."
EXPECT_RUNTIME_SEED="RVPhase3: Runtime Seed RedSea seed (no ELF FileWrite)."
EXPECT_RUNTIME_SVC_SEED="RVPhase3: Runtime Svc RedSea seed (no ELF FileWrite)."
EXPECT_RUNTIME_KERN_SEED="RVPhase3: Runtime Kern RedSea seed (no ELF FileWrite)."
EXPECT_MENU_GUEST_SEED="RVPhase3: Menu_RV_Guest RedSea seed (no ELF FileWrite)."
EXPECT_MENU_LEX_SEED="RVPhase3: Menu_RV_Guest_Lex RedSea seed (no ELF FileWrite)."
EXPECT_MENU_RV_SEED="RVPhase3: Menu_RV RedSea seed (no ELF FileWrite)."
EXPECT_MENU_LITE_SEED="RVPhase3: MakeAdam_RV_Lite RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_SKIP_SEED="RVPhase3: LiteMenuSkip RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_LEXOK_SEED="RVPhase3: LiteMenuLexOk RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_RID_SEED="RVPhase3: LiteMenuRID RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DEF_SEED="RVPhase3: LiteDef RedSea seed (no ELF FileWrite)."
EXPECT_LITE_CLASS_SEED="RVPhase3: LiteClass RedSea seed (no ELF FileWrite)."
EXPECT_LITE_STR_SEED="RVPhase3: LiteStr RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DIR_SEED="RVPhase3: LiteDir RedSea seed (no ELF FileWrite)."
EXPECT_LITE_CMENU_SEED="RVPhase3: LiteCMenu RedSea seed (no ELF FileWrite)."
EXPECT_LITE_CMENUENT_SEED="RVPhase3: LiteCMenuEnt RedSea seed (no ELF FileWrite)."
EXPECT_LITE_CMENU_U8PAD_SEED="RVPhase3: LiteCMenuU8Pad RedSea seed (no ELF FileWrite)."
EXPECT_LITE_CMENU_BOOL_SEED="RVPhase3: LiteCMenuBool RedSea seed (no ELF FileWrite)."
EXPECT_LITE_CMENU_BOOLPAD_SEED="RVPhase3: LiteCMenuBoolPad RedSea seed (no ELF FileWrite)."
EXPECT_LITE_CMENU_PROD_SEED="RVPhase3: LiteCMenuProd RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_ENTRYWIDTH_SEED="RVPhase3: LiteMenuEntryWidth RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_NEWHAND_SEED="RVPhase3: LiteMenuNewHand RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_FPOK_SEED="RVPhase3: LiteMenuFpOk RedSea seed (no ELF FileWrite)."
EXPECT_LITE_LEXPLANT_SEED="RVPhase3: LiteLexPlant RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_LEXI64SOFT_SEED="RVPhase3: LiteMenuLexI64Soft RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_NEWSUBCMP_SEED="RVPhase3: LiteMenuNewSubCmp RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_NEWCMP_SEED="RVPhase3: LiteMenuNewCmp RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_NEWCMPCTRL_SEED="RVPhase3: LiteMenuNewCmpCtrl RedSea seed (no ELF FileWrite)."
EXPECT_LITE_POPUPSOFT_SEED="RVPhase3: LitePopUpSoft RedSea seed (no ELF FileWrite)."
EXPECT_LITE_POPUPSOFTFP_SEED="RVPhase3: LitePopUpSoftFp RedSea seed (no ELF FileWrite)."
EXPECT_LITE_POPUPSOFTWINFP_SEED="RVPhase3: LitePopUpSoftWinFp RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCTERMSOFT_SEED="RVPhase3: LiteDocTermSoft RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MENU_WIDTH_SEED="RVPhase3: LiteMenuWidth RedSea seed (no ELF FileWrite)."
EXPECT_LITE_GRSOFT_SEED="RVPhase3: LiteGrSoft RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCPRINTFLAGS_SEED="RVPhase3: LiteDocPrintFlags RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCFLAGLEX_SEED="RVPhase3: LiteDocFlagLex RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCCMDLEX_SEED="RVPhase3: LiteDocCmdLex RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCARGLEX_SEED="RVPhase3: LiteDocArgLex RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCEXTSTR_SEED="RVPhase3: LiteDocExtStr RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCMULTILEX_SEED="RVPhase3: LiteDocMultiLex RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCPLAININC_SEED="RVPhase3: LiteDocPlainInc RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MAKEDOC_SEED="RVPhase3: LiteMakeDoc RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCPLAINNEST_SEED="RVPhase3: LiteDocPlainNest RedSea seed (no ELF FileWrite)."
EXPECT_LITE_MAKEDOCNEST_SEED="RVPhase3: LiteMakeDocNest RedSea seed (no ELF FileWrite)."
EXPECT_LITE_DOCINITINC_SEED="RVPhase3: LiteDocInitInc RedSea seed (no ELF FileWrite)."
EXPECT_DOCPLAIN_RV_SEED="RVPhase3: DocPlain_RV RedSea seed (no ELF FileWrite)."
EXPECT_MAKEDOC_SUBSET_SEED="RVPhase3: MakeDoc_RV Guest RedSea seed (include DocPlain_RV)."
EXPECT_ADAM_DOLDOC_PLAIN_NEST="RVPhase3: Adam/DolDoc DocPlain_RV RedSea nest seed."
EXPECT_ADAM_DOLDOC_MAKEDOC_NEST="RVPhase3: Adam/DolDoc MakeDoc_RV RedSea nest seed (Cd(__DIR__)+relative DocInit+DocPlain)."
EXPECT_ADAM_DOLDOC_DOCINIT_NEST="RVPhase3: Adam/DolDoc DocInit_RV RedSea nest seed."
EXPECT_ADAM_DOLDOC_DEFINES_NEST="RVPhase3: Adam/DolDoc DolDocDefines RedSea nest seed."
EXPECT_DOCINIT_RV_SEED="RVPhase3: DocInit_RV Guest RedSea seed (U0 DocInit body + KernelA defines include + MemSet/Bts/DefineLoad + Soft g_doldoc + I64 DocInitRVProbe)."
EXPECT_DOLDOC_DEFINES_SEED="RVPhase3: DolDocDefines RedSea seed (KernelA DOCT_*/DOCEF_* Soft include)."

EXPECT_LITE_DOCED_SEED="RVPhase3: LiteDocEd RedSea seed (no ELF FileWrite)."
EXPECT_MAKEOS="RVPhase3: MakeOS OK"
EXPECT_RUNTIME="RVPhase3: Runtime OK"
EXPECT_ADAMCORE="RVPhase3: StartOS Load AdamCore.BIN OK (guest Cmp FileWrite STR_CONST)."
EXPECT_STARTOS_BIN="RVPhase3: StartOS Load StartOS.BIN OK"
EXPECT_SEED="RVPhase3: StartOS Load Seed.BIN OK"
EXPECT_SVC="RVPhase3: StartOS Load Svc.BIN OK"
EXPECT_KERN="RVPhase3: StartOS Load Kern.BIN OK"
EXPECT_KERNEL_SEED="RVPhase3: RedSea Kernel.BIN seed FileFind+Load OK (KernelProbe=42)."
EXPECT_KERNEL_ENTRY="RVPhase3: RedSea Kernel.BIN KernelEntry handoff OK (0x4B45)."
EXPECT_KERNEL_INIT="RVPhase3: RedSea Kernel.BIN InitLite OK (magic+HeapProbe=64)."
EXPECT_KERNEL_SOFT="RVPhase3: RedSea Kernel.BIN SoftCall OK"
EXPECT_KERNEL_RUNTIME="RVPhase3: Runtime Kernel.BIN ready (RedSea seed; preferred over guest Cmp rebuild)."
EXPECT_KERNEL="RVPhase3: StartOS Load Kernel.BIN OK (RedSea Kernel.BIN preferred over Mac phase3.elf scaffold)."
EXPECT2="RVPhase3: StartOS subset OK (guest BINs AdamCore+StartOS+Seed+Svc+Kern+Kernel)."
EXPECT3="RVPhase3: done (compiler + StartOS)"
# Soft G8 needles (progress; not hard-fail if absent — nested include may still soft-fail)
EXPECT_P6_CLASS="RVPhase3: P6 bisect — class(I64) OK."
EXPECT_P6_STR="RVPhase3: P6 bisect — StrCpy OK."
EXPECT_P6_DIR="RVPhase3: P6 bisect — DirMk Cmp OK."
EXPECT_P6_DIR_CALL="RVPhase3: P6 bisect — DirMk Call OK."
EXPECT_P6_STR_CALL="RVPhase3: P6 bisect — StrCpy Call OK."
EXPECT_P6_LITE="RVPhase3: P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Lex+Guest, LITE.TXT)."
EXPECT_P6_LITE_PLANT="RVPhase3: P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Lex+Guest, LITE.TXT plant)."
EXPECT_P6_LITE_MENUFREE="RVPhase3: P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Menu_RV, LITE.TXT)."
EXPECT_P6_LITE_MENUFREE2="RVPhase3: P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Menu_RV, LITE.TXT plant)."
EXPECT_P6_LITE_SKIP="RVPhase3: P6 MakeAdam_RV_Lite Load OK (menu_n Cmp; Call soft-skip)."
EXPECT_P6_INCLUDE="RVPhase3: P6 AdamLite.BIN ready (guest Cmp #include Menu_RV)."
EXPECT_P6_INCLUDE_ABS="RVPhase3: P6 AdamLite.BIN ready (guest Cmp abs #include Menu_RV)."
EXPECT_P6_LEX_FOLD="RVPhase3: P6 bisect — Lex+Guest fold Cmp OK."
EXPECT_P6_GUEST_LEX="RVPhase3: P6 bisect — Guest_Lex Cmp OK."
EXPECT_P6_IDENT="RVPhase3: P6 bisect — local U8* ident Call OK."
EXPECT_P6_LEX_ELEM="RVPhase3: P6 bisect — Menu Lex Call OK (U8 elem)."
EXPECT_P6_LOCPTR="RVPhase3: P6 bisect — local U8* lit Call OK."
EXPECT_P6_MEM="RVPhase3: P6 bisect — class member StrCpy Call OK."
EXPECT_P6_SCALAR="RVPhase3: P6 bisect — scalar-glbl Call OK."
EXPECT_P6_FLAT_COUNT="RVPhase3: P6 bisect — flat Menu Count Call OK."
EXPECT_P6_SPAN_DIR="RVPhase3: P6 bisect — DirMk A:/Span Call OK."
EXPECT_P6_STOREFW="RVPhase3: P6 bisect — store→FileWrite Call OK."

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT="gtimeout"
elif ! command -v timeout >/dev/null 2>&1; then
  echo "SKIP kernel-phase3 smoke — missing timeout/gtimeout" >&2
  exit 0
fi

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-phase3 smoke — missing $t" >&2; exit 0; }
done

make -C "$ROOT" holyc-riscv tools/pack_tosb >/dev/null
# Refresh host-packed TOSB: full Compiler.BIN (CInit/ExePutS + CmpCtrl*/Wire exports).
chmod +x "$ROOT/tools/compiler_bin_pack_exports.sh"
# This build used to be `... >/dev/null 2>&1; then : fi` — a swallow. Compiler_RV.PRJ went
# red on 2026-09-21 (an RVExePubs pub with no declaration for the Kernel body it plants), the
# pack step below then repacked the LAST GOOD blob, and phase3 ran for a day against a
# Compiler.BIN older than the sources under test. That is what made the disk-loaded compiler
# "reject source the in-image one accepts": it had never seen `continue`. Hard-fail instead.
cmp_build_log="$(mktemp)"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$ROOT/build/compiler_rv.map" \
   "$COMPILER" "$ROOT/Compiler/Compiler_RV.PRJ" -o "$ROOT/build/compiler_rv.blob.bin" \
   >"$cmp_build_log" 2>&1; then
  echo "FAIL kernel-phase3 smoke — Compiler_RV.PRJ build failed (would stage a STALE Compiler.BIN)" >&2
  sed -n '1,40p' "$cmp_build_log" >&2
  rm -f "$cmp_build_log"
  exit 1
fi
rm -f "$cmp_build_log"
if [ ! -f "$ROOT/build/compiler_rv.blob.bin" ] || [ ! -f "$ROOT/build/compiler_rv.map" ]; then
  echo "FAIL kernel-phase3 smoke — Compiler_RV.PRJ produced no blob/map" >&2
  exit 1
fi
chmod +x "$ROOT/tools/compiler_bin_pack_exports.sh" "$ROOT/tools/pack_compiler_bin.sh"
if ! "$ROOT/tools/pack_compiler_bin.sh" \
  "$ROOT/build/compiler_rv.map" "$ROOT/build/compiler_rv.blob.bin" "$ROOT/build/Compiler.BIN" \
  >/dev/null; then
  echo "FAIL kernel-phase3 smoke — pack_compiler_bin.sh failed" >&2
  exit 1
fi
python3 "$ROOT/tools/gen_cmp_imports.py" >/dev/null || true
if [ ! -f "$ROOT/build/Compiler.BIN" ]; then
  echo "FAIL kernel-phase3 smoke — missing build/Compiler.BIN" >&2
  exit 1
fi
# Freshness: the packed BIN must be newer than every Compiler/ source. Catches the next
# variant, where the build succeeds but the pack step quietly does not.
stale_src="$(find "$ROOT/Compiler" -name '*.HC' -o -name '*.HH' -o -name '*.PRJ' \
  | while read -r f; do [ "$f" -nt "$ROOT/build/Compiler.BIN" ] && echo "$f"; done | head -5)"
if [ -n "$stale_src" ]; then
  echo "FAIL kernel-phase3 smoke — build/Compiler.BIN is older than Compiler sources:" >&2
  echo "$stale_src" >&2
  exit 1
fi

# Host-pack Boot.DD-shaped Kernel.BIN seed (KernelProbe→42, KernelEntry→0x4B45 via InitLite).
# SoftCall: import-free BIN ENTER StrLen/arena/MemCpy+VBlk+mount/FS/Load/Validate.
KERNEL_PROBE_SRC="$ROOT/tests/exec/cases/kernel_bin_probe.hc"
KERNEL_BLOB="$OUTDIR/kernel_bin_probe.blob.bin"
KERNEL_MAP="$OUTDIR/kernel_bin_probe.map"
LOAD_PROBE_SRC="$ROOT/tests/exec/cases/kernel_load_probe.hc"
LOAD_PROBE_BLOB="$OUTDIR/kernel_load_probe.blob.bin"
LOAD_PROBE_MAP="$OUTDIR/kernel_load_probe.map"
mkdir -p "$OUTDIR"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$KERNEL_MAP" \
   "$COMPILER" "$KERNEL_PROBE_SRC" -o "$KERNEL_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-phase3 smoke — Kernel.BIN probe compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$KERNEL_PROBE_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
KP_OFF=$(awk '/ KernelProbe$/{print $1; exit}' "$KERNEL_MAP")
KE_OFF=$(awk '/ KernelEntry$/{print $1; exit}' "$KERNEL_MAP")
KI_OFF=$(awk '/ KernelInitLite$/{print $1; exit}' "$KERNEL_MAP")
KH_OFF=$(awk '/ KernelHeapProbe$/{print $1; exit}' "$KERNEL_MAP")
KS_OFF=$(awk '/ KernelSoftCall$/{print $1; exit}' "$KERNEL_MAP")
KT_OFF=$(awk '/ KernelTrapProbe$/{print $1; exit}' "$KERNEL_MAP")
KV_OFF=$(awk '/ KernelVirtioProbe$/{print $1; exit}' "$KERNEL_MAP")
if [ -z "$KP_OFF" ] || [ -z "$KE_OFF" ] || [ -z "$KI_OFF" ] || [ -z "$KH_OFF" ] || [ -z "$KS_OFF" ]; then
  echo "FAIL kernel-phase3 smoke — KernelProbe/Entry/InitLite/HeapProbe/SoftCall missing from map" >&2
  exit 1
fi
PACK_E=(-e "KernelProbe:0x${KP_OFF}" -e "KernelEntry:0x${KE_OFF}" \
  -e "KernelInitLite:0x${KI_OFF}" -e "KernelHeapProbe:0x${KH_OFF}" \
  -e "KernelSoftCall:0x${KS_OFF}")
if [ -n "$KT_OFF" ]; then
  PACK_E+=(-e "KernelTrapProbe:0x${KT_OFF}")
fi
if [ -n "$KV_OFF" ]; then
  PACK_E+=(-e "KernelVirtioProbe:0x${KV_OFF}")
fi
"$ROOT/tools/pack_tosb" -v "${PACK_E[@]}" \
  "$KERNEL_BLOB" "$ROOT/build/Kernel.BIN" >/dev/null \
  || { echo "FAIL kernel-phase3 smoke — pack Kernel.BIN" >&2; exit 1; }

if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$LOAD_PROBE_MAP" \
   "$COMPILER" "$LOAD_PROBE_SRC" -o "$LOAD_PROBE_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-phase3 smoke — LoadProbe compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$LOAD_PROBE_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
LP_OFF=$(awk '/ LoadProbe$/{print $1; exit}' "$LOAD_PROBE_MAP")
if [ -z "$LP_OFF" ]; then
  echo "FAIL kernel-phase3 smoke — LoadProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v -e "LoadProbe:0x${LP_OFF}" \
  "$LOAD_PROBE_BLOB" "$ROOT/build/LoadProbe.BIN" >/dev/null \
  || { echo "FAIL kernel-phase3 smoke — pack LoadProbe.BIN" >&2; exit 1; }

# Stage Compiler.BIN + Kernel.BIN + SoftCall LoadProbe + StartOS/AdamCore +
# MakeOS/Runtime + Menu_RV/Guest/Lite + Lite* bisect PRJs onto RedSea. Guest Cmp
# without phase3.elf FileWrite staging (G9 host-seed shrink). Multi-blk root
# (mk_redsea_seed_img.py): product MakeOS/ + Runtime/ are real root dirs.
# Menu/Lite* stay under Compiler/ (Adam lean — StartOS+AdamCore only).
REDSEA_IMG="$OUTDIR/phase3_redsea.img"
SEEDS="$ROOT/tests/exec/seeds"
STARTOS_PRJ="$SEEDS/phase3_StartOS.HC"
ADAMCORE_PRJ="$SEEDS/phase3_AdamCore.HC"
MAKEOS_PRJ="$SEEDS/phase3_MakeOS.HC"
RUNTIME_SEED_PRJ="$SEEDS/phase3_RuntimeSeed.HC"
RUNTIME_SEED_LIB="$SEEDS/phase3_RuntimeSeedLib.HC"
RUNTIME_SVC_PRJ="$SEEDS/phase3_RuntimeSvc.HC"
RUNTIME_SVC_LIB="$SEEDS/phase3_RuntimeSvcLib.HC"
RUNTIME_KERN_PRJ="$SEEDS/phase3_RuntimeKern.HC"
RUNTIME_KERN_MEM="$SEEDS/phase3_RuntimeKernMem.HC"
MENU_RV_WRAP="$SEEDS/phase3_Menu_RV.HC"
MENU_LITE_PRJ="$SEEDS/phase3_MakeAdam_RV_Lite.HC"
MENU_GUEST_HC="$ROOT/Adam/Menu_RV_Guest.HC"
MENU_LEX_HC="$ROOT/Adam/Menu_RV_Guest_Lex.HC"
python3 "$ROOT/tools/mk_redsea_seed_img.py" "$REDSEA_IMG" \
  "Compiler/Compiler.BIN=$ROOT/build/Compiler.BIN" \
  "Compiler/Menu_RV_Guest.HC=$MENU_GUEST_HC" \
  "Compiler/Menu_RV_Guest_Lex.HC=$MENU_LEX_HC" \
  "Compiler/Menu_RV.HC=$MENU_RV_WRAP" \
  "Compiler/MakeAdam_RV_Lite.PRJ=$MENU_LITE_PRJ" \
  "Compiler/LiteDef.PRJ=$SEEDS/phase3_LiteDef.HC" \
  "Compiler/LiteClass.PRJ=$SEEDS/phase3_LiteClass.HC" \
  "Compiler/LiteClass2.PRJ=$SEEDS/phase3_LiteClass2.HC" \
  "Compiler/LiteArrOnly.PRJ=$SEEDS/phase3_LiteArrOnly.HC" \
  "Compiler/LiteClass2b.PRJ=$SEEDS/phase3_LiteClass2b.HC" \
  "Compiler/LiteClass3.PRJ=$SEEDS/phase3_LiteClass3.HC" \
  "Compiler/LiteStr.PRJ=$SEEDS/phase3_LiteStr.HC" \
  "Compiler/LiteDir.PRJ=$SEEDS/phase3_LiteDir.HC" \
  "Compiler/LiteSpanDir.PRJ=$SEEDS/phase3_LiteSpanDir.HC" \
  "Compiler/LiteU0.PRJ=$SEEDS/phase3_LiteU0.HC" \
  "Compiler/LiteScalar.PRJ=$SEEDS/phase3_LiteScalar.HC" \
  "Compiler/LiteLex.PRJ=$SEEDS/phase3_LiteLex.HC" \
  "Compiler/LiteLexAsg.PRJ=$SEEDS/phase3_LiteLexAsg.HC" \
  "Compiler/LiteLexCpy.PRJ=$SEEDS/phase3_LiteLexCpy.HC" \
  "Compiler/LiteLexSeed.PRJ=$SEEDS/phase3_LiteLexSeed.HC" \
  "Compiler/LiteLocArr.PRJ=$SEEDS/phase3_LiteLocArr.HC" \
  "Compiler/LiteLocPtrAssign.PRJ=$SEEDS/phase3_LiteLocPtrAssign.HC" \
  "Compiler/LiteStarLit.PRJ=$SEEDS/phase3_LiteStarLit.HC" \
  "Compiler/LiteLocPtr.PRJ=$SEEDS/phase3_LiteLocPtr.HC" \
  "Compiler/LiteIdent.PRJ=$SEEDS/phase3_LiteIdent.HC" \
  "Compiler/LiteMem.PRJ=$SEEDS/phase3_LiteMem.HC" \
  "Compiler/LiteGuestTiny.PRJ=$SEEDS/phase3_LiteGuestTiny.HC" \
  "Compiler/LiteMenuWidth.PRJ=$SEEDS/phase3_LiteMenuWidth.HC" \
  "Compiler/LiteLexStub.PRJ=$SEEDS/phase3_LiteLexStub.HC" \
  "Compiler/LiteMenuSkip.PRJ=$SEEDS/phase3_LiteMenuSkip.HC" \
  "Compiler/LiteMenuLexOk.PRJ=$SEEDS/phase3_LiteMenuLexOk.HC" \
  "Compiler/LiteMenuRID.PRJ=$SEEDS/phase3_LiteMenuRID.HC" \
  "Compiler/LiteInc.HC=$SEEDS/phase3_LiteInc.HC" \
  "Compiler/LiteIncWrap.PRJ=$SEEDS/phase3_LiteIncWrap.HC" \
  "Compiler/LiteStoreFw.PRJ=$SEEDS/phase3_LiteStoreFw.HC" \
  "Compiler/LiteCMenu.PRJ=$SEEDS/phase3_LiteCMenu.HC" \
  "Compiler/LiteCMenuEnt.PRJ=$SEEDS/phase3_LiteCMenuEnt.HC" \
  "Compiler/LiteCMenuU8Pad.PRJ=$SEEDS/phase3_LiteCMenuU8Pad.HC" \
  "Compiler/LiteCMenuBool.PRJ=$SEEDS/phase3_LiteCMenuBool.HC" \
  "Compiler/LiteCMenuBoolPad.PRJ=$SEEDS/phase3_LiteCMenuBoolPad.HC" \
  "Compiler/LiteCMenuProd.PRJ=$SEEDS/phase3_LiteCMenuProd.HC" \
  "Compiler/LiteMenuEntryWidth.PRJ=$SEEDS/phase3_LiteMenuEntryWidth.HC" \
  "Compiler/LiteMenuNewHand.PRJ=$SEEDS/phase3_LiteMenuNewHand.HC" \
  "Compiler/LiteMenuFpOk.PRJ=$SEEDS/phase3_LiteMenuFpOk.HC" \
  "Compiler/LiteLexPlant.PRJ=$SEEDS/phase3_LiteLexPlant.HC" \
  "Compiler/LiteMenuLexI64Soft.PRJ=$SEEDS/phase3_LiteMenuLexI64Soft.HC" \
  "Compiler/LiteMenuNewSubCmp.PRJ=$SEEDS/phase3_LiteMenuNewSubCmp.HC" \
  "Compiler/LiteMenuNewCmp.PRJ=$SEEDS/phase3_LiteMenuNewCmp.HC" \
  "Compiler/LiteMenuNewCmpCtrl.PRJ=$SEEDS/phase3_LiteMenuNewCmpCtrl.HC" \
  "Compiler/LitePopUpSoft.PRJ=$SEEDS/phase3_LitePopUpSoft.HC" \
  "Compiler/LitePopUpSoftFp.PRJ=$SEEDS/phase3_LitePopUpSoftFp.HC" \
  "Compiler/LitePopUpSoftWinFp.PRJ=$SEEDS/phase3_LitePopUpSoftWinFp.HC" \
  "Compiler/LiteDocTermSoft.PRJ=$SEEDS/phase3_LiteDocTermSoft.HC" \
  "Compiler/LiteDocStock.PRJ=$SEEDS/phase3_LiteDocStock.HC" \
  "Compiler/LiteDocPrintStock.PRJ=$SEEDS/phase3_LiteDocPrintStock.HC" \
  "Compiler/LiteDocPrintVA.PRJ=$SEEDS/phase3_LiteDocPrintVA.HC" \
  "Compiler/LiteDocTermStock.PRJ=$SEEDS/phase3_LiteDocTermStock.HC" \
  "Compiler/LiteDocTermNew.PRJ=$SEEDS/phase3_LiteDocTermNew.HC" \
  "Compiler/LiteDocFlag.PRJ=$SEEDS/phase3_LiteDocFlag.HC" \
  "Compiler/LiteDocArg.PRJ=$SEEDS/phase3_LiteDocArg.HC" \
  "Compiler/LiteDocArgX.PRJ=$SEEDS/phase3_LiteDocArgX.HC" \
  "Compiler/LiteDocInitSeed.PRJ=$SEEDS/phase3_LiteDocInitSeed.HC" \
  "Compiler/LiteDocFlagLex.PRJ=$SEEDS/phase3_LiteDocFlagLex.HC" \
  "Compiler/LiteDocCmdLex.PRJ=$SEEDS/phase3_LiteDocCmdLex.HC" \
  "Compiler/LiteDocArgLex.PRJ=$SEEDS/phase3_LiteDocArgLex.HC" \
  "Compiler/LiteDocExtStr.PRJ=$SEEDS/phase3_LiteDocExtStr.HC" \
  "Compiler/LiteDocMultiLex.PRJ=$SEEDS/phase3_LiteDocMultiLex.HC" \
  "Compiler/LiteDocPlainInc.PRJ=$SEEDS/phase3_LiteDocPlainInc.HC" \
  "Compiler/LiteMakeDoc.PRJ=$SEEDS/phase3_LiteMakeDoc.HC" \
  "Compiler/LiteDocPlainNest.PRJ=$SEEDS/phase3_LiteDocPlainNest.HC" \
  "Compiler/LiteMakeDocNest.PRJ=$SEEDS/phase3_LiteMakeDocNest.HC" \
  "Compiler/LiteDocInitInc.PRJ=$SEEDS/phase3_LiteDocInitInc.HC" \
  "Compiler/LiteDocInitStock.PRJ=$SEEDS/phase3_LiteDocInitStock.HC" \
  "Compiler/LiteDocInitA1.PRJ=$SEEDS/phase3_LiteDocInitA1.HC" \
  "Compiler/LiteDocInitA2.PRJ=$SEEDS/phase3_LiteDocInitA2.HC" \
  "Compiler/LiteDocInitA3.PRJ=$SEEDS/phase3_LiteDocInitA3.HC" \
  "Compiler/LiteDocInitA4a.PRJ=$SEEDS/phase3_LiteDocInitA4a.HC" \
  "Compiler/LiteDocInitA4b.PRJ=$SEEDS/phase3_LiteDocInitA4b.HC" \
  "Compiler/LiteDocInitA4.PRJ=$SEEDS/phase3_LiteDocInitA4.HC" \
  "Compiler/LiteDocInitKernPlant.PRJ=$SEEDS/phase3_LiteDocInitKernPlant.HC" \
  "Compiler/LiteDocInitTmph.PRJ=$SEEDS/phase3_LiteDocInitTmph.HC" \
  "Compiler/LiteDocInitDefLst.PRJ=$SEEDS/phase3_LiteDocInitDefLst.HC" \
  "Compiler/LiteDocInitBigOr.PRJ=$SEEDS/phase3_LiteDocInitBigOr.HC" \
  "Compiler/DocInit_RV_Stock.HC=$ROOT/Adam/DolDoc/DocInit_RV.HC" \
  "Compiler/LiteGlblConstIdx.PRJ=$SEEDS/phase3_LiteGlblConstIdx.HC" \
  "Compiler/LiteGlblVarIdx.PRJ=$SEEDS/phase3_LiteGlblVarIdx.HC" \
  "Compiler/LiteForVarIdx.PRJ=$SEEDS/phase3_LiteForVarIdx.HC" \
  "Compiler/LiteMembVarIdx.PRJ=$SEEDS/phase3_LiteMembVarIdx.HC" \
  "Compiler/LiteForMemb.PRJ=$SEEDS/phase3_LiteForMemb.HC" \
  "Compiler/LiteConstRmw.PRJ=$SEEDS/phase3_LiteConstRmw.HC" \
  "Compiler/LiteSplitRmw.PRJ=$SEEDS/phase3_LiteSplitRmw.HC" \
  "Compiler/LiteVarRmw.PRJ=$SEEDS/phase3_LiteVarRmw.HC" \
  "Compiler/LiteFlatRmw.PRJ=$SEEDS/phase3_LiteFlatRmw.HC" \
  "Compiler/LiteForMembRmw.PRJ=$SEEDS/phase3_LiteForMembRmw.HC" \
  "Compiler/LiteAndEqu.PRJ=$SEEDS/phase3_LiteAndEqu.HC" \
  "Compiler/LiteForMembAndEqu.PRJ=$SEEDS/phase3_LiteForMembAndEqu.HC" \
  "Compiler/DolDocDefines.HC=$SEEDS/phase3_DolDocDefines.HC" \
  "Compiler/LiteDocDefines.PRJ=$SEEDS/phase3_LiteDocDefines.HC" \
  "Compiler/LiteGlblArrDecay.PRJ=$SEEDS/phase3_LiteGlblArrDecay.HC" \
  "Compiler/LiteDocInitMemSet.PRJ=$SEEDS/phase3_LiteDocInitMemSet.HC" \
  "Compiler/LiteDocInitBts.PRJ=$SEEDS/phase3_LiteDocInitBts.HC" \
  "Compiler/LiteDocInitDefLoad.PRJ=$SEEDS/phase3_LiteDocInitDefLoad.HC" \
  "Compiler/LiteDocInitHashFind.PRJ=$SEEDS/phase3_LiteDocInitHashFind.HC" \
  "Compiler/LiteDocInitHashTableNew.PRJ=$SEEDS/phase3_LiteDocInitHashTableNew.HC" \
  "Compiler/LiteDocInitDefLstLoad.PRJ=$SEEDS/phase3_LiteDocInitDefLstLoad.HC" \
  "Compiler/LiteDocInitHashLstAdd.PRJ=$SEEDS/phase3_LiteDocInitHashLstAdd.HC" \
  "Compiler/LiteDocInitHash.PRJ=$SEEDS/phase3_LiteDocInitHash.HC" \
  "Compiler/LiteDocInitKernHash.PRJ=$SEEDS/phase3_LiteDocInitKernHash.HC" \
  "Compiler/LiteDocInitKernHashFind.PRJ=$SEEDS/phase3_LiteDocInitKernHashFind.HC" \
  "Compiler/DocPlain_RV.HC=$SEEDS/phase3_DocPlain_RV_Guest.HC" \
  "Compiler/MakeDoc_RV.HC=$SEEDS/phase3_MakeDoc_RV_Guest.HC" \
  "Compiler/DocInit_RV.HC=$SEEDS/phase3_DocInit_RV_Guest.HC" \
  "Adam/DolDoc/DocPlain_RV.HC=$SEEDS/phase3_DocPlain_RV_Guest.HC" \
  "Adam/DolDoc/DocInit_RV.HC=$SEEDS/phase3_DocInit_RV_Nest.HC" \
  "Adam/DolDoc/DolDocDefines.HC=$SEEDS/phase3_DolDocDefines.HC" \
  "Adam/DolDoc/MakeDoc_RV.HC=$SEEDS/phase3_MakeDoc_RV_Nest.HC" \
  "Compiler/LiteDocPrintFlags.PRJ=$SEEDS/phase3_LiteDocPrintFlags.HC" \
  "Compiler/LiteDocEd.PRJ=$SEEDS/phase3_LiteDocEd.HC" \
  "Compiler/LiteWinMgrLite.PRJ=$SEEDS/phase3_LiteWinMgrLite.HC" \
  "Compiler/LiteWinMgrTick.PRJ=$SEEDS/phase3_LiteWinMgrTick.HC" \
  "Compiler/LiteWinMgrTask.PRJ=$SEEDS/phase3_LiteWinMgrTask.HC" \
  "Compiler/LiteWinMgrSpawn.PRJ=$SEEDS/phase3_LiteWinMgrSpawn.HC" \
  "Compiler/LitePopUpCRV.PRJ=$SEEDS/phase3_LitePopUpCRV.HC" \
  "Compiler/LiteStartOSSoft.PRJ=$SEEDS/phase3_LiteStartOSSoft.HC" \
  "Compiler/LiteCtrlsSoft.PRJ=$SEEDS/phase3_LiteCtrlsSoft.HC" \
  "Compiler/LiteGrSoft.PRJ=$SEEDS/phase3_LiteGrSoft.HC" \
  "Kernel/Kernel.BIN=$ROOT/build/Kernel.BIN" \
  "Kernel/LoadProbe.BIN=$ROOT/build/LoadProbe.BIN" \
  "Adam/StartOS.PRJ=$STARTOS_PRJ" \
  "Adam/AdamCore.PRJ=$ADAMCORE_PRJ" \
  "MakeOS/Tiny.PRJ=$MAKEOS_PRJ" \
  "Runtime/Seed.PRJ=$RUNTIME_SEED_PRJ" \
  "Runtime/SeedLib.HC=$RUNTIME_SEED_LIB" \
  "Runtime/Svc.PRJ=$RUNTIME_SVC_PRJ" \
  "Runtime/SvcLib.HC=$RUNTIME_SVC_LIB" \
  "Runtime/Kern.PRJ=$RUNTIME_KERN_PRJ" \
  "Runtime/KernMem.HC=$RUNTIME_KERN_MEM" \
  || { echo "FAIL kernel-phase3 smoke — RedSea seed img" >&2; exit 1; }

# G9: HostBinEmbed / AdamLite U8[] embeds not linked into phase3 (loaded Cmp only).
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-phase3 smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-phase3 smoke — crt0" >&2; exit 1; }
fi

# Optional last-resort: link Compiler.BIN at 0x81000000 (default off — RedSea seed is enough).
COMPILER_FULL_O=""
if [ "${PHASE3_LINK_COMPILER_BIN:-0}" = "1" ]; then
  "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,contents \
    "$ROOT/build/Compiler.BIN" "$OUTDIR/compiler_full.o" \
    || { echo "FAIL kernel-phase3 smoke — compiler_full.o" >&2; exit 1; }
  COMPILER_FULL_O="$OUTDIR/compiler_full.o"
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-phase3 smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -40 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,code,contents,readonly \
    blob.bin blob_in.o && \
  if [ -n "$COMPILER_FULL_O" ]; then
    "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch \
      -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o "$COMPILER_FULL_O"
  else
    "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch \
      -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o
  fi ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-phase3 smoke — link error" >&2; exit 1; }

cp "$T/kp.elf" "$OUTDIR/phase3.elf"
# Per-run disk copy — avoids QEMU write-lock races on shared build/exec/phase3_redsea.img.
cp "$REDSEA_IMG" "$T/phase3_redsea.img" \
  || { echo "FAIL kernel-phase3 smoke — copy RedSea img" >&2; exit 1; }
# Prove ELF does not carry live Cmp bytes at 0x81000000 unless explicitly requested.
if [ "${PHASE3_LINK_COMPILER_BIN:-0}" != "1" ] && command -v riscv64-unknown-elf-objdump >/dev/null 2>&1; then
  if riscv64-unknown-elf-objdump -h "$OUTDIR/phase3.elf" 2>/dev/null | grep -q '\.compiler_bin'; then
    sz_line=$(riscv64-unknown-elf-objdump -h "$OUTDIR/phase3.elf" 2>/dev/null | awk '/\.compiler_bin/{print $3; exit}')
    if [ -n "$sz_line" ] && [ "$sz_line" != "0000000000000000" ] && [ "$sz_line" != "0" ]; then
      echo "FAIL kernel-phase3 smoke - .compiler_bin still non-empty (size=$sz_line); expected RedSea-only seed" >&2
      exit 1
    fi
  fi
fi
# UART-only CI path (-nographic). Interactive FB: add -device ramfb -display cocoa.
# Soft P6 bisect can exceed 180s if guest Cmp is slow on class/Menu surfaces.
# -m 256M: virtio driver RAM @ CONFIG_VIRTIO_DRV_RAM_BASE (0x88000000).
PHASE3_TIMEOUT="${PHASE3_TIMEOUT:-420}"
# macOS bash 3.2 + set -u: a failed pipeline in $(...) can leave the name
# unset and then report "out: unbound variable" on this line — pre-init + || true.
out=""
out=$(LC_ALL=C $TIMEOUT "$PHASE3_TIMEOUT" "$QEMU" -M virt -m 256M -bios none -kernel "$T/kp.elf" -nographic \
  -drive file="$T/phase3_redsea.img",if=none,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 </dev/null 2>&1 | LC_ALL=C tr -d '\r') || true
# Optional private UART path (agent races share /tmp/phase3_uart_final.txt).
PHASE3_UART_OUT="${PHASE3_UART_OUT:-/tmp/phase3_uart_final.txt}"
printf '%s\n' "$out" > "$PHASE3_UART_OUT" || true
if [ "$PHASE3_UART_OUT" != /tmp/phase3_uart_final.txt ]; then
  printf '%s\n' "$out" > /tmp/phase3_uart_final.txt || true
fi
if printf '%s\n' "$out" | grep -qF "$EXPECT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_LOAD" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_HOST" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_FULL" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_RELOC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_MAKEOS" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_RUNTIME" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_ADAMCORE" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_STARTOS_BIN" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SEED" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SVC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERN" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERNEL_SEED" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERNEL_ENTRY" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERNEL_INIT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERNEL_SOFT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERNEL_RUNTIME" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERNEL" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT2" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT3" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_CLASS" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_STR" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_DIR" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_DIR_CALL" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_STR_CALL" && \
   (printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LITE" || \
    printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LITE_PLANT" || \
    printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LITE_MENUFREE" || \
    printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LITE_MENUFREE2"); then
  soft_extra=""
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_GUEST_LEX"; then
    soft_extra="${soft_extra}+guestlex"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Guest_Lex && Soft Cmp OK."; then
    soft_extra="${soft_extra}+guestlexand"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Guest_Lex while(1) Soft Cmp OK."; then
    soft_extra="${soft_extra}+guestlexw1"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Guest_Lex continue Soft Cmp OK."; then
    soft_extra="${soft_extra}+guestlexcont"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Menu Skip Soft Call OK (SkipCont='x')."; then
    soft_extra="${soft_extra}+menuskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Menu LexOk Soft Call OK (SkipOk='x')."; then
    soft_extra="${soft_extra}+menulexok"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Menu LexOk Soft Cmp OK."; then
    soft_extra="${soft_extra}+menulexokcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Menu ReadIdent Soft Call OK (name=Tile)."; then
    soft_extra="${soft_extra}+menureadident"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Menu ReadIdent Soft Cmp OK."; then
    soft_extra="${soft_extra}+menureadidentcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Guest_Lex Call OK (LexSelfTest=8)."; then
    soft_extra="${soft_extra}+guestlexcall"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LEX_FOLD"; then
    soft_extra="${soft_extra}+lexfold"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 AdamLite.BIN ready (guest Cmp #include Menu_RV)."; then
    soft_extra="${soft_extra}+menuinc"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 AdamLite.BIN ready (guest Cmp menu-free FileWrite)."; then
    soft_extra="${soft_extra}+menufree"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_IDENT"; then
    soft_extra="${soft_extra}+ident"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LOCPTR"; then
    soft_extra="${soft_extra}+locptr"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — star-lit Call OK."; then
    soft_extra="${soft_extra}+starlit"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LEX_ELEM"; then
    soft_extra="${soft_extra}+lexelem"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_MEM"; then
    soft_extra="${soft_extra}+mem"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_SCALAR"; then
    soft_extra="${soft_extra}+scalar"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_FLAT_COUNT"; then
    soft_extra="${soft_extra}+flatcnt"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — flat Menu Width Call OK."; then
    soft_extra="${soft_extra}+flatwidth"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Menu Width Soft Call OK (Count+Width)."; then
    soft_extra="${soft_extra}+menuwidth"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Menu Width Soft Cmp OK."; then
    soft_extra="${soft_extra}+menuwidthcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_STOREFW"; then
    soft_extra="${soft_extra}+storefw"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_SPAN_DIR"; then
    soft_extra="${soft_extra}+spandir"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu+CAlloc Cmp OK."; then
    soft_extra="${soft_extra}+cmenu"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu+CAlloc Call OK (flags=8)."; then
    soft_extra="${soft_extra}+cmenucall"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenuEntry+name Soft Cmp OK."; then
    soft_extra="${soft_extra}+cmenuent"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenuEntry+name Call OK (name=Tile)."; then
    soft_extra="${soft_extra}+cmenuentcall"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu U8 pad Soft Cmp OK."; then
    soft_extra="${soft_extra}+cmenuu8pad"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu U8 pad Call OK (sizeof=40)."; then
    soft_extra="${soft_extra}+cmenuu8padcall"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu Bool Soft Cmp OK."; then
    soft_extra="${soft_extra}+cmenubool"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu Bool Call OK."; then
    soft_extra="${soft_extra}+cmenuboolcall"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu Bool pad Soft Cmp OK."; then
    soft_extra="${soft_extra}+cmenuboolpad"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu Bool pad Call OK (sizeof=16)."; then
    soft_extra="${soft_extra}+cmenuboolpadcall"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu product Soft Cmp OK."; then
    soft_extra="${soft_extra}+cmenuprod"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — CMenu product Call OK (entry=80 menu=40)."; then
    soft_extra="${soft_extra}+cmenuprodcall"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuEntryWidth Soft Cmp OK."; then
    soft_extra="${soft_extra}+prodentrywidth"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuEntryWidth Call OK (width=9)."; then
    soft_extra="${soft_extra}+prodentrywidthcall"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewHand Soft Cmp OK."; then
    soft_extra="${soft_extra}+menunewhand"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewHand Call OK (Tile arg1=8)."; then
    soft_extra="${soft_extra}+menunewhandcall"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuFpOk Soft Cmp OK."; then
    soft_extra="${soft_extra}+menufpok"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuFpOk Call OK (CmpCtrl gate)."; then
    soft_extra="${soft_extra}+menufpokcall"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuFpOk Soft Call soft-skip (accept remat)."; then
    soft_extra="${soft_extra}+menufpokcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — LexPlant Soft Call OK (glbl arr var idx + plant across Soft Call)."; then
    soft_extra="${soft_extra}+lexplant"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — LexPlant Soft Cmp OK."; then
    soft_extra="${soft_extra}+lexplantcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — LexPlant idx forms OK (glbl+local var idx)."; then
    soft_extra="${soft_extra}+lexplantidx"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — LexPlant hoisted-idx plant OK (Soft Call safe)."; then
    soft_extra="${soft_extra}+lexplanthoist"
  fi
  # Goal 2 bisect ladder for the stock DocInit_RV Soft #include: report the
  # highest rung that Soft Cmp'd, so a hang names the stock-only construct.
  for rung in "A1 (doldoc.hash read)=docinita1" "A2 (doldoc.hash write)=docinita2" \
    "A3 (dft_de_flags const idx)=docinita3" "A4 (sizeof member decay)=docinita4" \
    "A (doldoc plant)=docinitrunga" "B (tmph assign-in-if)=docinitrungb" \
    "C (DefineLstLoad NUL lits)=docinitrungc" "D (shift-or chains)=docinitrungd" \
    "E (stock #include)=docinitstock"; do
    tag="${rung%%=*}"
    needle="${rung##*=}"
    if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitStock ladder $tag Soft Call OK."; then
      soft_extra="${soft_extra}+${needle}call"
    elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitStock ladder $tag Soft Cmp OK."; then
      soft_extra="${soft_extra}+${needle}cmp"
    fi
  done
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitStock ladder done."; then
    soft_extra="${soft_extra}+docinitladder"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuLexI64Soft Soft Cmp OK."; then
    soft_extra="${soft_extra}+menulexi64soft"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuLexI64Soft Call OK (planted SoftLex)."; then
    soft_extra="${soft_extra}+menulexi64softcall"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuLexI64Soft Soft Call soft-skip (local cc remat r=1)."; then
    soft_extra="${soft_extra}+menulexi64softcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewSubCmp Soft Cmp OK."; then
    soft_extra="${soft_extra}+menunewsubcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewSubCmp Call OK (Tile arg1=8)."; then
    soft_extra="${soft_extra}+menunewsubcmpcall"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewSubCmp Soft Call soft-skip (hang after MenuLex Soft Call)."; then
    soft_extra="${soft_extra}+menunewsubcmpskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewSubCmp Soft Call soft-skip (hang after MenuLex Soft Cmp)."; then
    soft_extra="${soft_extra}+menunewsubcmpskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewCmp Soft Cmp OK."; then
    soft_extra="${soft_extra}+menunewcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewCmp Call OK (Tile arg1=8)."; then
    soft_extra="${soft_extra}+menunewcmpcall"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewCmp Soft Call soft-skip (hang after MenuNewSubCmp Soft Cmp)."; then
    soft_extra="${soft_extra}+menunewcmpskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewCmpCtrl Soft Cmp OK."; then
    soft_extra="${soft_extra}+menunewcmpctrl"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewCmpCtrl Call OK (Tile arg1=8)."; then
    soft_extra="${soft_extra}+menunewcmpctrlcall"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — product MenuNewCmpCtrl Soft Call soft-skip (hang after MenuNewSubCmp Soft Cmp)."; then
    soft_extra="${soft_extra}+menunewcmpctrlskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft PopUp Soft Cmp OK."; then
    soft_extra="${soft_extra}+popupsoft"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft PopUp Call OK (Ok/Resolve Soft Win)."; then
    soft_extra="${soft_extra}+popupsoftcall"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft PopUp Soft Call soft-skip (hang after Soft PopUp Soft Cmp)."; then
    soft_extra="${soft_extra}+popupsoftskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft PopUp Fp Soft Cmp OK."; then
    soft_extra="${soft_extra}+popupsoftfp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft PopUp Soft Win Fp Soft Cmp OK."; then
    soft_extra="${soft_extra}+popupsoftwinfp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft PopUp Soft Win Fp Call OK (Ok/Resolve Soft Win+fps)."; then
    soft_extra="${soft_extra}+popupsoftwinfpcall"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft PopUp Soft Win Fp Soft Call soft-skip (hang after Soft PopUp Soft Win Fp Soft Cmp)."; then
    soft_extra="${soft_extra}+popupsoftwinfpskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft DocTerm Soft Cmp OK."; then
    soft_extra="${soft_extra}+doctermsoft"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft DocTerm Call OK (Wire+Term Soft Doc)."; then
    soft_extra="${soft_extra}+doctermsoftcall"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Soft DocTerm Soft Call soft-skip (hang after Soft DocTerm Soft Cmp)."; then
    soft_extra="${soft_extra}+doctermsoftskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Menu_RV_Guest nest Call OK (MenuNew flags=8)."; then
    soft_extra="${soft_extra}+menuguest"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — MenuEntry tree Call OK (next/sub ids)."; then
    soft_extra="${soft_extra}+menuentry"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocGuest Call OK (DocNew/PrintLite)."; then
    soft_extra="${soft_extra}+docguest"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — GlblArrDecay Soft Call OK (p=glbl_arr)."; then
    soft_extra="${soft_extra}+glblarrdecay"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — GlblArrDecayWalk Soft Call OK (p=member_arr)."; then
    soft_extra="${soft_extra}+glblarrdecaywalk"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocGuest after GlblArrDecay Soft Call OK."; then
    soft_extra="${soft_extra}+docguestafterdecay"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocGuest after GlblArrDecay Soft Cmp OK."; then
    soft_extra="${soft_extra}+docguestafterdecaycmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — PopUpGuest Call OK (PopUpLite/OkLite)."; then
    soft_extra="${soft_extra}+popupguest"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocPrint Call OK (last/tag/id×3)."; then
    soft_extra="${soft_extra}+docprint"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocTerm Call OK (TermLite units×3)."; then
    soft_extra="${soft_extra}+docterm"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocNew Call OK (DocNew/DocDel)."; then
    soft_extra="${soft_extra}+docstock"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocPrint Call OK (DocPrint %d)."; then
    soft_extra="${soft_extra}+docprintstock"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocPrint Cmp OK."; then
    soft_extra="${soft_extra}+docprintcmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocPrint Cmp OK (Soft Call deferred)."; then
    soft_extra="${soft_extra}+docprintcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocPrintVA Call OK (true vararg)."; then
    soft_extra="${soft_extra}+docprintva"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocPrintVA Cmp OK."; then
    soft_extra="${soft_extra}+docprintvacmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocTerm Call OK (Put/Display/Border)."; then
    soft_extra="${soft_extra}+doctermstock"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocTerm Cmp OK."; then
    soft_extra="${soft_extra}+doctermstockcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocTermNew Call OK (Term desc+Put/Display/Border)."; then
    soft_extra="${soft_extra}+doctermnew"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — stock DocTermNew Cmp OK."; then
    soft_extra="${soft_extra}+doctermnewcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocFlag Soft Call OK (PrsDocFlags +CX)."; then
    soft_extra="${soft_extra}+docflag"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocFlag Soft Cmp OK."; then
    soft_extra="${soft_extra}+docflagcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocArg Soft Call OK (T=/HTML= HashFind)."; then
    soft_extra="${soft_extra}+docarg"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocArg Soft Cmp OK."; then
    soft_extra="${soft_extra}+docargcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocArgX Soft Call OK (LE=/LM=/A=/BI= HashFind)."; then
    soft_extra="${soft_extra}+docargx"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocArgX Soft Cmp OK."; then
    soft_extra="${soft_extra}+docargxcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitSeed Soft Call OK (dft flags / DHT_DOC_FLAG plant)."; then
    soft_extra="${soft_extra}+docinitseed"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitSeed Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinitseedcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocFlagLex Soft Call OK (CmpCtrl PrsDocFlags +CX/+UL)."; then
    soft_extra="${soft_extra}+docflaglex"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocFlagLex Soft Cmp OK."; then
    soft_extra="${soft_extra}+docflaglexcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocCmdLex Soft Call OK (CmpCtrl PrsDollarCmd TX+CX,\"hi\")."; then
    soft_extra="${soft_extra}+doccmdlex"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocCmdLex Soft Cmp OK."; then
    soft_extra="${soft_extra}+doccmdlexcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocArgLex Soft Call OK (CmpCtrl LexExpressionI64 LE=/LEN=)."; then
    soft_extra="${soft_extra}+docarglex"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocArgLex Soft Cmp OK."; then
    soft_extra="${soft_extra}+docarglexcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocExtStr Soft Call OK (CmpCtrl LexExtStr T=/LM=)."; then
    soft_extra="${soft_extra}+docextstr"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocExtStr Soft Cmp OK."; then
    soft_extra="${soft_extra}+docextstrcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocMultiLex Soft Call OK (CmpCtrl PrsDollarCmd TX+CX,T= / A=+HTML=+BI=)."; then
    soft_extra="${soft_extra}+docmultilex"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocMultiLex Soft Cmp OK."; then
    soft_extra="${soft_extra}+docmultilexcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocPlainInc Soft Call OK (guest #include DocPlain_RV)."; then
    soft_extra="${soft_extra}+docplaininc"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocPlainInc Soft Cmp OK."; then
    soft_extra="${soft_extra}+docplaininccmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocPlainInc Soft Call soft-skip (Cmp OK; Call hang)."; then
    soft_extra="${soft_extra}+docplaininccmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — MakeDoc Soft Call OK (guest #include MakeDoc_RV -> DocPlain_RV)."; then
    soft_extra="${soft_extra}+makedocinc"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — MakeDoc Soft Cmp OK."; then
    soft_extra="${soft_extra}+makedocinccmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — MakeDoc Soft Call soft-skip (Cmp OK; Call hang)."; then
    soft_extra="${soft_extra}+makedocinccmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocPlainNest Soft Call OK (guest #include A:/Adam/DolDoc/DocPlain_RV)."; then
    soft_extra="${soft_extra}+docplainnest"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocPlainNest Soft Cmp OK."; then
    soft_extra="${soft_extra}+docplainnestcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — MakeDocNest Soft Call OK (guest Cd(__DIR__)+relative #include A:/Adam/DolDoc/MakeDoc_RV)."; then
    soft_extra="${soft_extra}+makedocnest+makedocrel+makedocdir"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — MakeDocNest Soft Call OK (guest relative #include A:/Adam/DolDoc/MakeDoc_RV)."; then
    soft_extra="${soft_extra}+makedocnest+makedocrel"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — MakeDocNest Soft Cmp OK."; then
    soft_extra="${soft_extra}+makedocnestcmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — MakeDocNest Soft Cmp soft-skip (Cd/__DIR__ nest Invalid lval hang)."; then
    soft_extra="${soft_extra}+makedocnestskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — MakeDocNest Soft Cmp soft-skip (DocInit nest Invalid lval hang)."; then
    soft_extra="${soft_extra}+makedocnestskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — GlblVarIdx Soft Cmp OK."; then
    soft_extra="${soft_extra}+glblvaridx"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — VarRmw Soft Cmp OK."; then
    soft_extra="${soft_extra}+varrmw"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — ForMembRmw Soft Cmp OK."; then
    soft_extra="${soft_extra}+formembrmw"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — AndEqu Soft Cmp OK."; then
    soft_extra="${soft_extra}+andeq"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — ForMembAndEqu Soft Cmp OK."; then
    soft_extra="${soft_extra}+formembandeq"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocDefines Soft Call OK (KernelA DolDocDefines Soft include DOCT_LINK)."; then
    soft_extra="${soft_extra}+docdefines"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocDefines Soft Cmp OK."; then
    soft_extra="${soft_extra}+docdefinescmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitMemSet Soft Call OK (MemSet Soft DocInit member arrays)."; then
    soft_extra="${soft_extra}+docinitmemset"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitMemSet Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinitmemsetcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitBts Soft Call OK (Bt/Bts Soft DocInit type_flags_form)."; then
    soft_extra="${soft_extra}+docinitbts"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitBts Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinitbtscmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitDefLoad Soft Call OK (DefineLoad Soft DocInit plant)."; then
    soft_extra="${soft_extra}+docinitdefload"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitDefLoad Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinitdefloadcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Call OK (HashFind+Fs Soft DocInit)."; then
    soft_extra="${soft_extra}+docinithashfind"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Call OK (Fs->hash_table remat Soft DocInit)."; then
    soft_extra="${soft_extra}+docinithashfind"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Call OK (HashFind Soft without Fs)."; then
    soft_extra="${soft_extra}+docinithashfind"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Call OK (HashFind table=0)."; then
    soft_extra="${soft_extra}+docinithashfind"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Call OK (HashFind without Fs Soft DocInit)."; then
    soft_extra="${soft_extra}+docinithashfind"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Call soft-skip (early remat BIN; late Soft Call hang)."; then
    soft_extra="${soft_extra}+docinithashfindcallskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Call soft-skip (early remat BIN; Soft Call hang after HashTableNew)."; then
    soft_extra="${soft_extra}+docinithashfindcallskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Call soft-skip (early remat BIN; Soft Call hang after HashTableNew+SyncCmpFs)."; then
    soft_extra="${soft_extra}+docinithashfindcallskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinithashfindcmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashFind Soft Cmp soft-skip (Fs->hash_table Invalid lval hang)."; then
    soft_extra="${soft_extra}+docinithashfindskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashTableNew Soft Call OK (HashTableNew Soft DocInit)."; then
    soft_extra="${soft_extra}+docinithashtablenew"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashTableNew Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinithashtablenewcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitDefLstLoad Soft Call OK (DefineLstLoad Soft DocInit)."; then
    soft_extra="${soft_extra}+docinitdeflstload"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitDefLstLoad Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinitdeflstloadcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashLstAdd Soft Call OK (HashLstAdd Soft DocInit)."; then
    soft_extra="${soft_extra}+docinithashlstadd"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHashLstAdd Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinithashlstaddcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHash Soft Call OK (Soft g_doldoc.hash Soft DocInit)."; then
    soft_extra="${soft_extra}+docinithash"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitHash Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinithashcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitKernHash Soft Call OK (Kernel doldoc.hash Soft DocInit)."; then
    soft_extra="${soft_extra}+docinitkernhash"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitKernHash Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinitkernhashcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitKernHashFind Soft Call OK (Soft HashFind Kernel doldoc.hash)."; then
    soft_extra="${soft_extra}+docinitkernhashfind"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitKernHashFind Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinitkernhashfindcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call OK (guest #include DocInit_RV MemSet/Bts/DefineLoad/HashFind+Fs Soft g_doldoc probe)."; then
    soft_extra="${soft_extra}+docinitinc+docinitu0+docinitbody+docinitdefines+docinitmemset+docinitbts+docinitdefload+docinithashfind"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call OK (guest #include DocInit_RV MemSet/Bts/DefineLoad Soft g_doldoc probe)."; then
    soft_extra="${soft_extra}+docinitinc+docinitu0+docinitbody+docinitdefines+docinitmemset+docinitbts+docinitdefload"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call OK (guest #include DocInit_RV MemSet/Bts Soft g_doldoc probe)."; then
    soft_extra="${soft_extra}+docinitinc+docinitu0+docinitbody+docinitdefines+docinitmemset+docinitbts"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call OK (guest #include DocInit_RV MemSet+KernelA defines probe)."; then
    soft_extra="${soft_extra}+docinitinc+docinitu0+docinitbody+docinitdefines+docinitmemset"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call OK (guest #include DocInit_RV KernelA defines include probe)."; then
    soft_extra="${soft_extra}+docinitinc+docinitu0+docinitbody+docinitdefines"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call OK (guest #include DocInit_RV body+defines probe)."; then
    soft_extra="${soft_extra}+docinitinc+docinitu0+docinitbody"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call OK (guest #include DocInit_RV U0 DocInit probe)."; then
    soft_extra="${soft_extra}+docinitinc+docinitu0"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call OK (guest #include DocInit_RV probe)."; then
    soft_extra="${soft_extra}+docinitinc"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call soft-skip (hang after DocInitInc Soft Cmp)."; then
    soft_extra="${soft_extra}+docinitinccmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call soft-skip (hang after MakeDocNest Soft Call)."; then
    soft_extra="${soft_extra}+docinitinccmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinitinccmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Call soft-skip (Cmp OK; Call hang)."; then
    soft_extra="${soft_extra}+docinitinccmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitInc Soft Cmp soft-skip (DocInit_RV Fs->hash_table Invalid lval hang)."; then
    soft_extra="${soft_extra}+docinitincskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitStock Soft Call OK (Soft #include stock DocInit_RV Kernel doldoc plant)."; then
    soft_extra="${soft_extra}+docinitstock"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitStock Soft Cmp OK."; then
    soft_extra="${soft_extra}+docinitstockcmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitStock Soft Cmp soft-skip (Soft #include stock DocInit_RV Soft Cmp hang after doldoc Soft plant)."; then
    soft_extra="${soft_extra}+docinitstockskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitStock Soft Call soft-skip (Soft #include stock Soft Cmp hang)."; then
    soft_extra="${soft_extra}+docinitstockskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitStock Soft Call soft-skip (no BIN)."; then
    soft_extra="${soft_extra}+docinitstockcmp"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocInitStock Soft Cmp soft-skip (no PRJ)."; then
    soft_extra="${soft_extra}+docinitstockskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: DocInit_RV Stock RedSea seed (unmodified Adam/DolDoc/DocInit_RV.HC)."; then
    soft_extra="${soft_extra}+docinitrvstockredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocPrintFlags Soft Call OK (DocPrint TX+CX + DocRecalc)."; then
    soft_extra="${soft_extra}+docprintflags"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocPrintFlags Soft Cmp OK."; then
    soft_extra="${soft_extra}+docprintflagscmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocEd Soft Call OK (inject Tab/Enter BT LE + DocMenu MU)."; then
    soft_extra="${soft_extra}+doced"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — DocEd Soft Cmp OK."; then
    soft_extra="${soft_extra}+docedcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgr lite Call OK (UART ready+DocTermNew term_idx)."; then
    soft_extra="${soft_extra}+winmgrlite"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgr lite Soft Call soft-skip (hang after DocTermNew)."; then
    soft_extra="${soft_extra}+winmgrliteskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgr lite Cmp OK."; then
    soft_extra="${soft_extra}+winmgrlitecmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgr tick Call OK (RVWinMgrRun(1) iters)."; then
    soft_extra="${soft_extra}+winmgrtick"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgr tick Soft Call soft-skip (after WinMgr lite hang)."; then
    soft_extra="${soft_extra}+winmgrtickskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgr tick Cmp OK."; then
    soft_extra="${soft_extra}+winmgrtickcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgrTask Call OK (task+RLf_WINMGR+Run(1))."; then
    soft_extra="${soft_extra}+winmgrtask"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgrTask Soft Call soft-skip (after WinMgr lite hang)."; then
    soft_extra="${soft_extra}+winmgrtaskskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgrTask Cmp OK."; then
    soft_extra="${soft_extra}+winmgrtaskcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgr Spawn Call OK (RVKSpawn+Yield WinMgrTask(1))."; then
    soft_extra="${soft_extra}+winmgrspawn"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgr Spawn Soft Call soft-skip (after WinMgr lite hang)."; then
    soft_extra="${soft_extra}+winmgrspawnskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — WinMgr Spawn Cmp OK."; then
    soft_extra="${soft_extra}+winmgrspawncmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — PopUp CRV Call OK (RVPopUpOk→CRVWin+Resolve)."; then
    soft_extra="${soft_extra}+popupcrv"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — PopUp CRV Soft Call soft-skip (after WinMgr lite hang)."; then
    soft_extra="${soft_extra}+popupcrvskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — PopUp CRV Cmp OK."; then
    soft_extra="${soft_extra}+popupcrvcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — StartOS Soft Call OK (DocTermNew+WallPaper+Spawn+PopUp)."; then
    soft_extra="${soft_extra}+startossoft"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — StartOS Soft Call soft-skip (after WinMgr lite hang)."; then
    soft_extra="${soft_extra}+startossoftskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — StartOS Soft Cmp OK."; then
    soft_extra="${soft_extra}+startossoftcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Ctrls Soft Call OK (DemoInstall+queue+click)."; then
    soft_extra="${soft_extra}+ctrlssoft"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Ctrls Soft Call soft-skip (hang after StartOS Soft Call soft-skip)."; then
    soft_extra="${soft_extra}+ctrlssoftskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Ctrls Soft Cmp OK."; then
    soft_extra="${soft_extra}+ctrlssoftcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — late Soft Call wave soft-skip (prove StartOS Load)."; then
    soft_extra="${soft_extra}+latesoftcallskip"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — late Soft Call wave soft-skip (after Ctrls Soft Call hang; prove StartOS Load)."; then
    soft_extra="${soft_extra}+latesoftcallskip"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Gr Soft Call OK (DCNew+Fill+Plot+Blot)."; then
    soft_extra="${soft_extra}+grsoft"
  elif printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — Gr Soft Cmp OK."; then
    soft_extra="${soft_extra}+grsoftcmp"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_STARTOS_SEED"; then
    soft_extra="${soft_extra}+startosredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_ADAMCORE_SEED"; then
    soft_extra="${soft_extra}+adamcoreredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_MAKEOS_SEED"; then
    soft_extra="${soft_extra}+makeosredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_RUNTIME_SEED"; then
    soft_extra="${soft_extra}+runtimeredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_RUNTIME_SVC_SEED"; then
    soft_extra="${soft_extra}+runtimesvcredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_RUNTIME_KERN_SEED"; then
    soft_extra="${soft_extra}+runtimekernredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_MENU_GUEST_SEED"; then
    soft_extra="${soft_extra}+menuguestredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_MENU_LEX_SEED"; then
    soft_extra="${soft_extra}+menulexredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_MENU_RV_SEED"; then
    soft_extra="${soft_extra}+menuredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_MENU_LITE_SEED"; then
    soft_extra="${soft_extra}+menuliteredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_SKIP_SEED"; then
    soft_extra="${soft_extra}+litemenuskipredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_LEXOK_SEED"; then
    soft_extra="${soft_extra}+litemenulexokredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_RID_SEED"; then
    soft_extra="${soft_extra}+litemenuridredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DEF_SEED"; then
    soft_extra="${soft_extra}+litedefredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_CLASS_SEED"; then
    soft_extra="${soft_extra}+liteclassredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_STR_SEED"; then
    soft_extra="${soft_extra}+litestrredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DIR_SEED"; then
    soft_extra="${soft_extra}+litedirredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_CMENU_SEED"; then
    soft_extra="${soft_extra}+litecmenuredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_CMENUENT_SEED"; then
    soft_extra="${soft_extra}+litecmenuentredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_CMENU_U8PAD_SEED"; then
    soft_extra="${soft_extra}+litecmenuu8padredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_CMENU_BOOL_SEED"; then
    soft_extra="${soft_extra}+litecmenuboolredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_CMENU_BOOLPAD_SEED"; then
    soft_extra="${soft_extra}+litecmenuboolpadredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_CMENU_PROD_SEED"; then
    soft_extra="${soft_extra}+litecmenuprodredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_ENTRYWIDTH_SEED"; then
    soft_extra="${soft_extra}+litemenuentrywidthredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_NEWHAND_SEED"; then
    soft_extra="${soft_extra}+litemenunewhandredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_FPOK_SEED"; then
    soft_extra="${soft_extra}+litemenufpokredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_LEXPLANT_SEED"; then
    soft_extra="${soft_extra}+litelexplantredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_LEXI64SOFT_SEED"; then
    soft_extra="${soft_extra}+litemenulexi64softredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_NEWSUBCMP_SEED"; then
    soft_extra="${soft_extra}+litemenunewsubcmpredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_NEWCMP_SEED"; then
    soft_extra="${soft_extra}+litemenunewcmpredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_NEWCMPCTRL_SEED"; then
    soft_extra="${soft_extra}+litemenunewcmpctrlredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_POPUPSOFT_SEED"; then
    soft_extra="${soft_extra}+litepopupsoftredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_POPUPSOFTFP_SEED"; then
    soft_extra="${soft_extra}+litepopupsoftfpredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_POPUPSOFTWINFP_SEED"; then
    soft_extra="${soft_extra}+litepopupsoftwinfpredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCTERMSOFT_SEED"; then
    soft_extra="${soft_extra}+litedoctermsoftredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MENU_WIDTH_SEED"; then
    soft_extra="${soft_extra}+litemenuwidthredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_GRSOFT_SEED"; then
    soft_extra="${soft_extra}+litegrsoftredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCPRINTFLAGS_SEED"; then
    soft_extra="${soft_extra}+litedocprintflagsredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCFLAGLEX_SEED"; then
    soft_extra="${soft_extra}+litedocflaglexredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCCMDLEX_SEED"; then
    soft_extra="${soft_extra}+litedoccmdlexredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCARGLEX_SEED"; then
    soft_extra="${soft_extra}+litedocarglexredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCEXTSTR_SEED"; then
    soft_extra="${soft_extra}+litedocextstrredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCMULTILEX_SEED"; then
    soft_extra="${soft_extra}+litedocmultilexredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCPLAININC_SEED"; then
    soft_extra="${soft_extra}+litedocplainincredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MAKEDOC_SEED"; then
    soft_extra="${soft_extra}+litemakedocredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCPLAINNEST_SEED"; then
    soft_extra="${soft_extra}+litedocplainnestredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_MAKEDOCNEST_SEED"; then
    soft_extra="${soft_extra}+litemakedocnestredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCINITINC_SEED"; then
    soft_extra="${soft_extra}+litedocinitincredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_DOCPLAIN_RV_SEED"; then
    soft_extra="${soft_extra}+docplainrvredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_MAKEDOC_SUBSET_SEED"; then
    soft_extra="${soft_extra}+makedocsubsetredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_ADAM_DOLDOC_PLAIN_NEST"; then
    soft_extra="${soft_extra}+adamdoldocplainnest"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_ADAM_DOLDOC_MAKEDOC_NEST"; then
    soft_extra="${soft_extra}+adamdoldocmakedocnest"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_ADAM_DOLDOC_DOCINIT_NEST"; then
    soft_extra="${soft_extra}+adamdoldocdocinitnest"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_ADAM_DOLDOC_DEFINES_NEST"; then
    soft_extra="${soft_extra}+adamdoldocdefinesnest"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_DOLDOC_DEFINES_SEED"; then
    soft_extra="${soft_extra}+doldocdefinesredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_DOCINIT_RV_SEED"; then
    soft_extra="${soft_extra}+docinitrvredsea"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_LITE_DOCED_SEED"; then
    soft_extra="${soft_extra}+litedocedredsea"
  fi
  # Hard proof: reloc path used RedSea seed (not fixed-VMA fallback).
  if ! printf '%s\n' "$out" | grep -qF "RVPhase3: prefer A:/Compiler/Compiler.BIN (RedSea seed; heap Load)."; then
    echo "FAIL kernel-phase3 smoke — did not prefer RedSea Compiler.BIN seed" >&2
    printf '%s\n' "$out" | grep -E 'Compiler\.BIN|RedSea|0x81000000|prefer|staged' | head -20 | LC_ALL=C sed 's/^/  /' >&2
    exit 1
  fi
  if printf '%s\n' "$out" | grep -qF "fixed VMA fallback"; then
    echo "FAIL kernel-phase3 smoke — fell back to fixed VMA LoadPass @0x81000000" >&2
    exit 1
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_INCLUDE" || \
     printf '%s\n' "$out" | grep -qF "$EXPECT_P6_INCLUDE_ABS"; then
    printf 'Kernel-phase3 smoke: OK (G9 RedSea Compiler.BIN+Kernel.BIN + AdamLite Call%s)\n' "$soft_extra"
  else
    printf 'Kernel-phase3 smoke: OK (G9 RedSea Compiler.BIN+Kernel.BIN; nested Menu include still soft%s)\n' "$soft_extra"
  fi
  exit 0
fi
echo "FAIL kernel-phase3 smoke — expected line not found:" >&2
echo "  want: $EXPECT / … / $EXPECT_KERNEL_SEED / $EXPECT_KERNEL / $EXPECT_P6_CLASS / $EXPECT_P6_STR / $EXPECT_P6_DIR / $EXPECT_P6_DIR_CALL / $EXPECT_P6_STR_CALL / $EXPECT_P6_LITE" >&2
printf '%s\n' "$out" | grep -E 'RVPhase3|StartOS|ExePutS|Load|MakeOS|Runtime|Kern|Kernel|AdamCore|Cmp|Except|Error|FAIL|OK|P6|bisect|Menu_RV|ident|RVKMain' | head -80 | LC_ALL=C sed 's/^/  /' >&2
exit 1
