#!/bin/bash
# Stage A of docs/UNMATCHED_FIRMWARE.md: wrap a flat TempleOS/RV binary in the FIT that SiFive's
# U-Boot SPL loads from GPT partition type 2E54B353-1271-4842-806F-E436D6AF6985, so the board
# powers on into TempleOS with no U-Boot and no OpenSBI.
#
# It does NOT touch the card. It builds the payload, and prints the three console blocks to paste:
# back up what is there, prove the payload boots from RAM, and only then write it. mkimage is not
# needed -- a FIT is a flattened device tree, and dtc is what makes one.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMG="${1:-$ROOT/build/exec/repl_unmatched.bin}"
LOAD="${STAGE_A_LOAD:-0x80200000}"
OUT="${STAGE_A_OUT:-$ROOT/build/unmatched}"
SRV="${UNMATCHED_SERVERIP:-192.168.8.1}"
RAMTEST="${STAGE_A_RAMTEST:-0x84000000}"
# The read and the write use different servers. Fetching comes from the router's dnsmasq TFTP
# ($SRV), which is READ-ONLY -- so the backup cannot go there. STAGE_A_PUTSRV names a server that
# accepts writes, normally the Mac's own tftpd, and the destination file must already exist and be
# writable there. Unset, the paste block says so rather than printing a line that fails.
PUTSRV="${STAGE_A_PUTSRV:-}"
if [ -n "$PUTSRV" ]; then PUTLINE="tftpput $RAMTEST <p2-size-in-bytes> $PUTSRV:loader2_backup.bin"
else PUTLINE="tftpput $RAMTEST <p2-size-in-bytes> <write-capable-tftp-host>:loader2_backup.bin   # set STAGE_A_PUTSRV"; fi
command -v dtc >/dev/null || { echo "mk_stage_a: dtc not found (brew install dtc)"; exit 1; }
[ -f "$IMG" ] || { echo "mk_stage_a: no such image: $IMG"; exit 1; }
mkdir -p "$OUT"
NAME="$(basename "${IMG%.bin}")_stage_a.itb"
ITB="$OUT/$NAME"
ITS="$OUT/${NAME%.itb}.its"
# Snapshot the payload before reading it twice. The image lives in build/, which a smoke run
# rewrites in place -- and this script otherwise reads it once for the CRC and again, through
# dtc's /incbin/, for the data. Caught that the hard way: a build running in another window
# produced a FIT whose hash described a half-written file. Copy first, then everything below
# refers to the copy.
SNAP="$OUT/${NAME%.itb}_payload.bin"
# The readback at the end proves the FIT matches the snapshot, which says nothing about whether
# the snapshot itself is a whole image. So check that the source did not move under the copy:
# same size and same mtime before and after. A build running in another window fails this.
STAT_BEFORE=$(stat -f '%z %m' "$IMG" 2>/dev/null || stat -c '%s %Y' "$IMG")
cp "$IMG" "$SNAP" || { echo "mk_stage_a: could not snapshot $IMG"; exit 1; }
STAT_AFTER=$(stat -f '%z %m' "$IMG" 2>/dev/null || stat -c '%s %Y' "$IMG")
if [ "$STAT_BEFORE" != "$STAT_AFTER" ]; then
  echo "mk_stage_a: $IMG changed while being read ($STAT_BEFORE -> $STAT_AFTER)."
  echo "            A build is probably running. Wait for it and try again."
  exit 1
fi
# A FIT with no hash node leaves `iminfo` nothing to check, and block 2 below depends on iminfo
# being a real answer rather than a shrug. mkimage would fill this in; here the CRC is computed
# and written directly. U-Boot stores a crc32 hash value as four big-endian bytes, which is
# exactly what a <0x...> cell in a device tree source emits.
CRC=$(python3 -c "import zlib,sys;print('0x%08x' % (zlib.crc32(open(sys.argv[1],'rb').read()) & 0xffffffff))" "$SNAP")
# os = "u-boot" is what makes the SPL JUMP, in M-mode, with no further ceremony. "opensbi" would
# have it try to boot a firmware blob with a device tree instead, which is the thing we are
# removing. type = "firmware" is the entry the SPL's configuration node points at.
cat > "$ITS" <<EOF
/dts-v1/;
/ {
	description = "TempleOS/RV for HiFive Unmatched, Stage A";
	#address-cells = <2>;
	images {
		templeos {
			description = "TempleOS/RV M-mode kernel";
			data = /incbin/("$SNAP");
			type = "firmware";
			os = "u-boot";
			arch = "riscv";
			compression = "none";
			load = <0x0 $LOAD>;
			entry = <0x0 $LOAD>;
			hash-1 {
				algo = "crc32";
				value = <$CRC>;
			};
		};
	};
	configurations {
		default = "conf";
		conf {
			description = "TempleOS/RV, alone";
			firmware = "templeos";
		};
	};
};
EOF
dtc -I dts -O dtb -q "$ITS" -o "$ITB" || { echo "mk_stage_a: dtc failed on $ITS"; exit 1; }
RAW=$(wc -c < "$SNAP" | tr -d ' ')
SZ=$(wc -c < "$ITB" | tr -d ' ')
BLKS=$(( (SZ + 511) / 512 ))
MAGIC=$(od -An -tx1 -N4 "$ITB" | tr -d ' ')
[ "$MAGIC" = "d00dfeed" ] || { echo "mk_stage_a: built file is not a FIT (magic $MAGIC)"; exit 1; }
# Read the FIT back and check that what it actually carries is what we meant to put in it: the
# embedded data must equal the snapshot byte for byte, and the stored hash must be that data's
# crc32 in the four big-endian bytes U-Boot compares against. Without this the script can emit a
# self-consistent-looking FIT describing the wrong file, which is exactly the failure that
# prompted the snapshot above -- and on the board it would surface as an `iminfo` mismatch with
# no way to tell a bad payload from a bad tool.
python3 - "$ITB" "$SNAP" "$CRC" <<'PYEOF' || exit 1
import struct, sys, zlib
fit, snap, want = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read(), int(sys.argv[3], 16)
hdr = struct.unpack('>10I', fit[:40])
off_struct, off_strings, size_strings, size_struct = hdr[2], hdr[3], hdr[8], hdr[9]
strs = fit[off_strings:off_strings + size_strings]
i, path, found = off_struct, [], {}
while i < off_struct + size_struct:
    tok = struct.unpack('>I', fit[i:i + 4])[0]; i += 4
    if tok == 1:
        e = fit.index(b'\0', i); path.append(fit[i:e].decode()); i = (e + 4) & ~3
    elif tok == 2:
        path.pop()
    elif tok == 3:
        ln, no = struct.unpack('>II', fit[i:i + 8]); i += 8
        name = strs[no:strs.index(b'\0', no)].decode()
        val = fit[i:i + ln]; i = (i + ln + 3) & ~3
        if name == 'data' and 'templeos' in path: found['data'] = val
        if name == 'value' and 'hash-1' in path: found['hash'] = val
    elif tok == 9:
        break
bad = []
if found.get('data') != snap: bad.append('embedded data differs from the payload snapshot')
if found.get('hash') != struct.pack('>I', want): bad.append('stored hash is not the payload crc32')
if zlib.crc32(snap) & 0xffffffff != want: bad.append('crc32 of the snapshot is not what was written')
if bad:
    print('mk_stage_a: FIT readback FAILED -- ' + '; '.join(bad)); sys.exit(1)
print('readback  : FIT carries the payload byte for byte, hash matches its crc32')
PYEOF
echo "payload : $IMG  ($RAW bytes, load/entry $LOAD, crc32 $CRC)"
echo "FIT     : $ITB  ($SZ bytes = $BLKS blocks of 512, magic d00dfeed)"
echo
echo "Stage up the FIT for tftp, then paste these at the U-Boot prompt IN ORDER."
echo "Nothing before block 3 changes the card."
cat <<EOF

--- 1. what is on the card now (read only) ----------------------------------------
mmc dev 0
part list mmc 0
# Read p2's start and size from that table. The payload needs $BLKS blocks; if p2 is
# smaller, STOP -- the card has to be repartitioned first, and overwriting past the
# end of p2 lands in whatever follows it.
mmc read $RAMTEST <p2-start> 8
md.l $RAMTEST 4
# d00dfeed means the stock loader2 is a FIT, which is what we are replacing.

--- 2. back it up, and prove the payload boots, WITHOUT writing anything -----------
# Back up the current p2. This does NOT go to $SRV: that is the router's dnsmasq TFTP and it
# is read-only. It needs a server that accepts writes, with the destination file already
# created and writable there -- normally the Mac's own tftpd. Pulling the card and dd-ing it
# is the version of this step with no caveats.
mmc read $RAMTEST <p2-start> <p2-size>
$PUTLINE
# Now load OUR payload into a different place and boot it from RAM. This exercises the
# FIT and the entry point with the card untouched, so a mistake here costs a reset:
tftpboot $RAMTEST $SRV:$NAME
iminfo $RAMTEST
bootm $RAMTEST
# TempleOS should come up. If instead the board goes quiet, look for "hN": crt0 prints
# it when it is entered on a hart it was not built for.

--- 3. write it (this is the destructive step) -------------------------------------
tftpboot $RAMTEST $SRV:$NAME
mmc write $RAMTEST <p2-start> $BLKS
reset
EOF
