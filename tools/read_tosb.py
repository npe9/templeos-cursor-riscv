#!/usr/bin/env python3
"""Scan a raw disk image (or a .BIN) for CBinFile 'TOSB' headers and dump them.

Prints each BIN's patch table (exports, imports and their rips) and its code words, so a
BIN the GUEST compiler wrote can be read on the host BEFORE Load touched it. That is what
separates a codegen bug from a loader bug -- see docs/NEXT_STEPS.md, where two commits
blamed codegen for what turned out to be the loader, and where a third blamed the loader
for what turned out to be a wrong planted address.

Pair it with PHASE3_KEEP=1, which makes tests/scripts/run_kernel_phase3_smoke.sh keep the
work dir holding the RedSea image the guest wrote its BINs into:

    PHASE3_KEEP=1 make kernel-phase3-smoke
    tools/read_tosb.py <kept-dir>/phase3_redsea.img RVDocInitA4cSelfTest

Usage: read_tosb.py <image-or-bin> [name-substring]
"""
import struct, sys

IET = {0:"END",2:"REL_I0",3:"IMM_U0",4:"REL_I8",5:"IMM_U8",6:"REL_I16",7:"IMM_U16",
       8:"REL_I32",9:"IMM_U32",10:"REL_I64",11:"IMM_I64",16:"REL32_EXPORT",
       17:"IMM32_EXPORT",18:"REL64_EXPORT",19:"IMM64_EXPORT",20:"ABS_ADDR",
       21:"CODE_HEAP",22:"ZEROED_CODE_HEAP",23:"DATA_HEAP",24:"ZEROED_DATA_HEAP",25:"MAIN"}
HDR = 32  # U16 jmp, U8 align, U8 rsvd, U32 sig, I64 org, I64 pto, I64 file_size

def parse_patch(b, off, end):
    out, p = [], off
    while p < end:
        et = b[p]; p += 1
        if et == 0:
            out.append((et, "END", None, None)); break
        if et == 20 or et == 23:   # ABS_ADDR / DATA_HEAP carry a count then rips
            cnt = struct.unpack_from("<I", b, p)[0]; p += 4
            nul = b.index(b"\0", p); name = b[p:nul].decode("latin1"); p = nul+1
            if et == 23: p += 8    # size
            rips = list(struct.unpack_from("<%dI" % cnt, b, p)); p += 4*cnt
            out.append((et, IET.get(et, et), name, rips)); continue
        rip = struct.unpack_from("<I", b, p)[0]; p += 4
        nul = b.index(b"\0", p); name = b[p:nul].decode("latin1"); p = nul+1
        out.append((et, IET.get(et, et), name, rip))
    return out

def main():
    img = open(sys.argv[1], "rb").read()
    want = sys.argv[2] if len(sys.argv) > 2 else None
    pos = 0
    while True:
        i = img.find(b"TOSB", pos)
        if i < 0: break
        pos = i + 4
        base = i - 4                      # sig is at +4 in CBinFile
        if base < 0: continue
        try:
            org, pto, fsz = struct.unpack_from("<qqq", img, base+8)
        except struct.error: continue
        if not (0 < fsz < 1<<22) or not (HDR <= pto < fsz): continue
        b = img[base:base+fsz]
        try: pt = parse_patch(b, pto, fsz)
        except Exception as e: pt = [("?", "PARSE FAIL %s" % e, None, None)]
        names = " ".join(str(r[2]) for r in pt if r[2])
        if want and want not in names: continue
        print("=== TOSB at image offset 0x%x  file_size=%d org=%d patch_table=0x%x" % (base, fsz, org, pto))
        for et, nm, s, rip in pt:
            print("    %-14s %-24s %s" % (nm, s, rip if not isinstance(rip, list) else "rips=%s" % [hex(r) for r in rip]))
        code = b[HDR:pto]
        print("    code %d bytes:" % len(code))
        for w in range(0, len(code), 4):
            word = struct.unpack_from("<I", code, w)[0] if w+4 <= len(code) else None
            print("      +0x%03x  %08x" % (w, word))
        print()

main()
