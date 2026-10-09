#!/usr/bin/env python3
"""The directories the translation lives in -- ONE copy, because seven was one too many.

WHY THIS FILE EXISTS. Every gate in tools/cfs that enumerates translated HolyC files carried
its own spelling of this list: check_coverage, check_signatures, check_structs, check_variadic,
check_constants, check_in_blob, check_seam, and check_padding twice. They agreed for as long as
the list never changed.

Then Kernel/Cfs/md arrived for MD, the first cFS app, and the failure was not that a gate
complained -- it was that check_padding DID NOT. check_structs was taught the new directory and
compared 380 classes; check_padding still had its own pair of copies, measured 358, and reported
OK. It even holds a guard for exactly this ("the two struct gates must cover the SAME set"),
and the guard could not fire, because it pairs check_structs' NASA structs against
check_padding's OWN class list -- so both sides of the comparison were the same 358 and the 22
unmeasured classes were invisible to it. A cross-check between two tools is worth only the
inputs they do not share.

So the list is here, imported, and a new module or app is one edit. check_wired.py is the
exception that stays as it is: it WALKS Kernel/Cfs looking for a translated file no driver
includes, and walking is the point -- it is the gate that caught md_*.HC being unreachable, and
it could only do that because it never had a list to forget to update.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# THE cFS APPS, in the order they were gated. An app is a repository of its own -- fsw/src,
# fsw/inc and config -- and five gates needed those three directories: check_structs (which NASA
# structs exist), check_padding (the probe's include path), check_manifest (what CMake builds),
# check_oracle_globals (its $MD path substitution) and the smoke script. check_structs and
# check_padding each had their own hand-written copy of MD's three, which is the NASA-side version
# of exactly the defect this file was created to fix on the HolyC side -- unify one list and the
# other goes on being two.
APPS = ["MD", "MM", "CS", "LC", "HK"]

# OSAL first, then cFE, then the apps -- lowest layer outwards, which is also the order a reader
# wants them reported in.
#
# **DERIVED FROM APPS, NOT LISTED.** These were two hand-written lists that happened to agree with
# APPS, and adding HK showed what that costs: HK's classes were written, its header was added to
# check_padding's list, and check_padding STILL reported the same 498 classes -- because the HolyC
# side came from here and here had not been touched. A poison test (widening a padding member by
# two bytes) changed nothing in the output, which is how the omission was caught rather than
# shipped. Three lists for one app, and missing any one of them drops coverage SILENTLY.
HCNAMES = ["osal", "cfe"] + [a.lower() for a in APPS]
HCDIRS = [os.path.join(ROOT, "Kernel", "Cfs", n) for n in HCNAMES]



def app_dirs():
    """fsw/src, fsw/inc and config for every gated app, in APPS order."""
    out = []
    for app in APPS:
        out.append(os.path.join(ROOT, "vendor", app, "fsw", "src"))
        out.append(os.path.join(ROOT, "vendor", app, "fsw", "inc"))
        out.append(os.path.join(ROOT, "vendor", app, "config"))
    return out
