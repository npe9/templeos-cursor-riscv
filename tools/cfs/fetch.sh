#!/bin/bash
# Fetch NASA's cFS sources for the translation work. Pinned by commit so a transcript recorded
# today can be reproduced: the differential oracle compares against THESE bytes, and an upstream
# move would change the reference without changing anything in this tree.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
V="$ROOT/vendor"
CFE_SHA="546a002515be5a1e3b66f9ae2c14f948d9cec76f"
PSP_SHA="53df1d54c3d29fd23832c59df1104de07a043af2"
OSAL_SHA="dad0ee99c121f2ecc11f8c0798c1e836e41d8ab1"
# The first cFS APP. Pinned on the dev branch for the same reason cFE is: cFE here is
# 7.0.1+dev, a day later than this commit, and MD's v7.0.1 tag predates both.
MD_SHA="65eb7b3b0aa8acd05076128a623cd696582b6d7c"
# The second cFS APP, and the OTHER memory app: MM pokes and dumps arbitrary memory where MD
# only reads it, so it needs the WRITE half of the simulated window MD established.
MM_SHA="0a767de5bbb6da05d7b5705e75221495aca444f9"
# The THIRD cFS APP, and the one that COMPLETES THE MEMORY TRIO: MD reads memory, MM writes it,
# CS checksums it -- so CS is the app that notices when MM's damage was not intended. Pinned on
# the dev branch for the same reason as the other two: this commit is dated one day before the
# cFE pin, exactly as MD's is.
CS_SHA="795e387fce497c698c87a5a68f2a9014f13c3ce8"
# The FOURTH cFS APP. LC (Limit Checker) watches telemetry against limits and fires actions when
# one is breached -- so it is the first app whose INPUT is other apps' packets rather than memory,
# and the first that CAUSES something (it sends a stored command) instead of only reporting. Chosen
# over HS/SC/DS/FM because module_deps reports 34 cFE+OSAL calls and ZERO missing symbols: nothing
# new has to be simulated. Pinned one day before the cFE pin, exactly as MD, MM and CS are.
LC_SHA="32c76661dc339247d1c3b9250ed27dd18c34a344"
# The FIFTH cFS APP. HK (Housekeeping) subscribes to OTHER APPS' telemetry and copies selected
# fields into combined packets -- so it is the first app whose whole job is the four already
# translated: MD, MM, CS and LC each produce an HK packet, and HK is what collects them. 1,582
# lines over five sources, and module_deps reports ZERO missing functions: the only three names
# it needs that this port lacks are MACROS (CFE_ES_MEMADDRESS_C, CFE_ES_MEMADDRESS_TO_PTR --
# already written out for MM and CS -- and CFE_RESOURCEID_TO_ULONG).
#
# **SCH WAS THE OBVIOUS CANDIDATE AND IS NOT TRANSLATABLE AGAINST THIS cFE PIN.** The Scheduler
# is what sends LC its sample-actionpoint message, so it was the natural fifth -- 2,634 lines,
# four sources and NO call cycle at all, the cleanest dependency graph of any remaining app. But
# its newest release is v2.2.2 and it is written against the cFE **6.x** API: CFE_SB_InitMsg,
# CFE_SB_SendMsg, CFE_SB_RcvMsg, CFE_SB_GetMsgId, CFE_SB_GetCmdCode, CFE_SB_GetTotalMsgLength and
# CFE_ES_RegisterApp, none of which exist in Draco. There is no draco-integration branch. So SCH
# needs a cFE-6-to-7 shim layer before a line of it can be translated, which is a different job
# from translating it -- and it is a finding about the cFS ecosystem rather than about this port:
# the apps have NOT all moved to the current core API. HK and HS both have draco-integration
# branches and use CFE_MSG_*/CFE_SB_TransmitMsg; SCH, as of this pin, does not.
HK_SHA="766dab1591b95ff89d99baaab9b43d234de4e699"
# The SIXTH cFS APP, and the first that needs SIMULATED HARDWARE RATHER THAN SIMULATED MEMORY.
# HS (Health & Safety) is the watchdog app: it pets the hardware watchdog, watches that the other
# applications are still checking in, watches the event stream for a configured pattern, and reads
# CPU utilisation. module_deps reports SEVEN sources with **NO CALL CYCLE AT ALL** -- the cleanest
# dependency graph of any app in this port -- and eight missing symbols, every one of them PSP:
#
#   CFE_PSP_WatchdogEnable / WatchdogService / WatchdogSet      a watchdog timer
#   CFE_PSP_IODriver_FindByName / IODriver_Command              an I/O driver abstraction
#   CFE_PSP_IODriver_CONST_STR / U32ARG / VPARG                 header `static inline`s, which
#                                                               travel with their caller
#
# So two devices have to be simulated where MD, MM and CS needed only a memory window. Pinned on
# the dev-merge commit for the same reason as the five before it.
HS_SHA="947b903174bca0878210e7fbc53104cff8e7b335"
# The SEVENTH cFS APP, and the one chosen because it needs NO new simulated device at all.
# SC (Stored Command) is the onboard sequencer: it holds Absolute Time Sequences and Relative Time
# Sequences uploaded from the ground and releases their commands onto the software bus when their
# time arrives. So it is the app that CLOSES THE LOOP on LC -- LC fires an RTS request when a limit
# breaks, and SC is what actually runs that RTS.
#
# **CHOSEN BY MEASURING NEW SIMULATION SURFACE, which is this project's real selection criterion.**
# Five apps remained translatable (DS, FM, SC, CI_lab, TO_lab); all five have draco-integration
# branches and ZERO cFE-6.x legacy calls, so none is blocked the way SCH is. What separates them is
# what has to be invented before a line can be gated:
#
#   SC      ~4545 lines, 20 sources   NOTHING new            34 distinct CFE/OS calls
#   DS      ~4626 lines, 14 sources   a filesystem           53
#   FM      ~4256 lines, 19 sources   filesystem + dirs      68
#   CI_lab  ~1003 lines, 11 sources   sockets / UDP          39
#   TO_lab  ~1075 lines, 11 sources   sockets / UDP          42
#
# SC's 34 matches LC's documented 34 BY THE SAME GREP METHOD -- calibrated against a finished app
# rather than counted in isolation, which is the mistake that would make the number meaningless.
# Zero missing symbols against this pin: the only grep hit, CFE_MSG_PTR, is a false positive (it is
# in cFE/modules/msg/option_inc/default_cfe_msg_hdr_pri.h and is already translated three times).
#
# **ITS ONE REAL COST IS A CONTROLLABLE CLOCK.** SC schedules on absolute and relative time and
# calls CFE_TIME_GetTime/GetUTC/GetTAI/Compare/Add/Print. TIME is already gated, so nothing new is
# simulated -- but the exercise has to ADVANCE time deterministically to make a stored sequence
# fire, which is the same shape of cost as HS's simulated watchdog and not a blocker. Like LC, SC
# is woken by a scheduler message the exercise injects directly; SCH itself stays blocked.
#
# **PINNED DIFFERENTLY FROM THE SIX BEFORE IT, and the difference is worth stating.** MD, MM, CS,
# LC, HK and HS are each pinned one day before the cFE pin, on a dev branch that was moving. SC's
# draco-integration branch has NOT moved since 2026-01-23 -- eight months before the cFE pin -- so
# this SHA is that branch's HEAD rather than a date-matched commit. That is a fact about SC's
# maintenance rather than a choice here, and it means SC is the first app in this port whose
# sources are materially older than the core it is being compiled against.
SC_SHA="8d6941096ae21be8f8be7f0977a31a244cadd236"
mkdir -p "$V"
fetch() {
  name="$1"; url="$2"; sha="$3"
  if [ -d "$V/$name/.git" ]; then
    have="$(cd "$V/$name" && git rev-parse HEAD)"
    [ "$have" = "$sha" ] && { echo "$name: already at $sha"; return; }
    echo "$name: at $have, want $sha — fetching"
  else
    git clone -q "$url" "$V/$name"
  fi
  ( cd "$V/$name" && git fetch -q origin "$sha" 2>/dev/null || git fetch -q origin; git checkout -q "$sha" )
  echo "$name: $sha"
}
fetch cFE  https://github.com/nasa/cFE.git  "$CFE_SHA"
fetch osal https://github.com/nasa/osal.git "$OSAL_SHA"
fetch PSP  https://github.com/nasa/PSP.git  "$PSP_SHA"
fetch MD   https://github.com/nasa/MD.git   "$MD_SHA"
fetch MM   https://github.com/nasa/MM.git   "$MM_SHA"
fetch CS   https://github.com/nasa/CS.git   "$CS_SHA"
fetch LC   https://github.com/nasa/LC.git   "$LC_SHA"
fetch HK   https://github.com/nasa/HK.git   "$HK_SHA"
fetch HS   https://github.com/nasa/HS.git   "$HS_SHA"
fetch SC   https://github.com/nasa/SC.git   "$SC_SHA"
echo "vendor/shim is committed in this repo: it stands in for the headers CMake would generate."
