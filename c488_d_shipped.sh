#!/bin/bash
# c488_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c487 receipts: the emitter faithfully
# emits nops for its input; the real candidate is
# duckstation/xenogears.bin (600,359,760 bytes =
# 2352*255,255 = a raw MODE2/2352 sector dump of the
# actual disc). THE DECISIVE QUESTION: does the disc's
# PS-X EXE contain REAL CODE at 0x8009A280 (an emission
# gap - the emitter or its input skipped real code) or
# ZEROS (runtime-loaded overlay content)? RECEIPTS:
# (1) EXEIN488: the emitter's input name (main.rs/docs);
# (2) MAGIC488: the PS-X EXE magics inside the disc
# image + each header; (3) ORIG488: the ORIGINAL BYTES
# at 0x8009A280 (512B, sector-mathed) + the CONTROLS at
# 0x800739A0 (the known-real running init) and
# 0x8009A2F8 (the unresolved jump target); (4)
# EMITSTOP488: the last real translated fn before the
# nop region. Fail-closed, tee'd to /tmp/c488_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C488-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c488_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found"; exit 0; fi
echo "===EXEIN488=== the emitter's input name (main.rs + docs)"
grep -n -e "input" -e "args" -e "\.bin" -e "\.exe" src/main.rs 2>/dev/null | head -10
grep -rn -e "disc1" -e "emit" docs/*.md 2>/dev/null | head -8
find . -maxdepth 2 -type f -size +400k -size -3M 2>/dev/null | head -12
echo "===MAGIC488=== the PS-X EXE magics inside the disc image"
IMG="duckstation/xenogears.bin"
if [ ! -f "$IMG" ]; then IMG=$(find . -maxdepth 3 -iname "xenogears.bin" 2>/dev/null | head -1); fi
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then echo "GATE-FAILED: the disc image not found"; exit 0; fi
echo "IMG=$IMG size=$(wc -c < "$IMG" | tr -d " ")"
MAGICS=$(LC_ALL=C grep -abo -m 8 -e "PS-X EXE" "$IMG" | cut -d: -f1)
echo "magic hits: $MAGICS"
BEST=""
for OFF in $MAGICS; do
  TADDR=$(od -An -tu4 -j $((OFF+16)) -N4 "$IMG" | tr -d " ")
  TXSTART=$(od -An -tu4 -j $((OFF+24)) -N4 "$IMG" | tr -d " ")
  TXSIZE=$(od -An -tu4 -j $((OFF+28)) -N4 "$IMG" | tr -d " ")
  COVERS=no
  if [ "$TADDR" -gt 0 ] && [ "$TADDR" -le $((0x8009A280)) ] && [ $((TADDR + TXSIZE)) -gt $((0x8009A280)) ]; then COVERS=YES; BEST="$OFF"; fi
  echo "magic@$OFF (sector$((OFF/2352))): t_addr=$TADDR tx_start=$TXSTART tx_size=$TXSIZE covers_8009A280=$COVERS"
done
echo "BEST=$BEST"
if [ -z "$BEST" ]; then echo "no magic covers 0x8009A280 - using the first hit as a fallback"; BEST=$(echo $MAGICS | awk "{print \$1}"); fi
if [ -z "$BEST" ]; then echo "GATE-FAILED: no PS-X EXE magic found in the image"; exit 0; fi
TADDR=$(od -An -tu4 -j $((BEST+16)) -N4 "$IMG" | tr -d " ")
TXSTART=$(od -An -tu4 -j $((BEST+24)) -N4 "$IMG" | tr -d " ")
SEC0=$((BEST / 2352))
echo "chosen magic@$BEST: t_addr=$TADDR tx_start=$TXSTART first_sector=$SEC0 magic_in_sector_off=$((BEST % 2352)) (expect 24)"
echo "===ORIG488=== the ORIGINAL BYTES at 0x8009A280 + the controls"
dump_at() {
  V=$1
  NB=$2
  FOFF=$(( TXSTART + V - TADDR ))
  SEC=$(( SEC0 + FOFF / 2048 ))
  IMGOFF=$(( SEC * 2352 + 24 + FOFF % 2048 ))
  echo "--- vaddr 0x$(printf %X "$V"): file_off=$FOFF sector=$SEC image_off=$IMGOFF (first $NB bytes):"
  od -An -tx4 -j "$IMGOFF" -N "$NB" "$IMG" | head -34
}
echo "THE QUESTION: 0x8009A280 (the movie module second-stage region):"
dump_at $((0x8009A280)) 512
echo "CONTROL 1: 0x800739A0 (the module's running init code, KNOWN REAL - must decode as addiu/ori/jal patterns):"
dump_at $((0x800739A0)) 128
echo "CONTROL 2: 0x8009A2F8 (the unresolved jump target):"
dump_at $((0x8009A2F8)) 128
echo "===EMITSTOP488=== the last real translated fn before the nop region (disc1.c ~332790-332845)"
sed -n "332790,332845p" "$D" | head -58
echo "===C488DONE=== the disc bytes at 0x8009A280 decide emission-gap vs runtime-load - digest is pure ASCII"
