#!/bin/bash
# c487_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c486 decode: the movie module's
# second-stage region (0x8009A280+, its code and the
# 8009A2E0 table) is an EMITTED NOP-SLIDE - the module's
# init walked the empty table, wrote GPU packets to a
# garbage dest, and jumped to 0x8009A2F8. THE
# DISCRIMINATOR (this census): (a) the ORIGINAL BINARY
# has real content at 0x8009A280+ that the emitter
# SKIPPED (an emission gap) vs (b) the region is
# runtime-loaded overlay content (a missing load).
# RECEIPTS: (1) BINFIND487: the input binary candidates;
# (2) BINHDR487: the PSX-EXE header + the ORIGINAL BYTES
# at 0x8009A280..0x8009A480; (3) NOPCHAIN487: how far
# the nop region extends in disc1.c; (4) STAGE2487: the
# stage2 map receipts; (5) EMIT487: the emitter's
# untranslated-region handling. Fail-closed, tee'd to
# /tmp/c487_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C487-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c487_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no preserved run log"; exit 0; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found"; exit 0; fi
echo "===BINFIND487=== the input binary candidates"
find . -maxdepth 3 -type f \( -iname "*.bin" -o -iname "*.exe" -o -iname "SLPS*" \) 2>/dev/null | head -12
echo "--- the big candidates (>256k):"
find . -maxdepth 3 -type f \( -iname "*.bin" -o -iname "*.exe" -o -iname "SLPS*" \) -size +256k 2>/dev/null | while read -r f; do wc -c "$f"; done | head -8
echo "===BINHDR487=== the PSX-EXE header + the ORIGINAL BYTES at 0x8009A280"
BIN=$(find . -maxdepth 3 -type f -size +256k \( -iname "*.bin" -o -iname "*.exe" -o -iname "SLPS*" \) 2>/dev/null | head -1)
echo "BIN=$BIN"
if [ -n "$BIN" ]; then
  echo "--- the first 16 bytes (the PSX-EXE magic check):"
  od -An -tx1 -N16 "$BIN" | head -2
  TADDR=$(od -An -tu4 -j16 -N4 "$BIN" | tr -d " ")
  TXSTART=$(od -An -tu4 -j24 -N4 "$BIN" | tr -d " ")
  TXSIZE=$(od -An -tu4 -j28 -N4 "$BIN" | tr -d " ")
  echo "t_addr=$TADDR tx_start=$TXSTART tx_size=$TXSIZE"
  TARGET=$((0x8009A280))
  if [ "$TADDR" -gt 0 ] && [ "$TARGET" -ge "$TADDR" ] && [ "$TARGET" -lt $((TADDR + TXSIZE)) ]; then
    OFF=$(( TXSTART + TARGET - TADDR ))
    echo "file offset for 0x8009A280 = $OFF (INSIDE the text segment - the original bytes follow)"
    echo "--- the ORIGINAL BYTES at 0x8009A280..0x8009A480 (the movie module's second-stage region):"
    od -An -tx4 -j "$OFF" -N 512 "$BIN" | head -34
  else
    echo "0x8009A280 NOT inside the EXE text range (t_addr..t_addr+tx_size) - the region is runtime-loaded content (discriminator b)"
  fi
else
  echo "(no input binary candidate found - name it for the next census)"
fi
echo "===NOPCHAIN487=== how far the nop region extends in disc1.c (first real content after 0x8009A33C)"
sed -n "332838,333400p" "$D" | grep -n -v -e "nop" | head -20
echo "===STAGE2487=== the stage2 map receipts"
grep -n -e "\[stage2\]" "$LOG" | head -8
grep -n -e "stage2p" "$LOG" | head -6
echo "===EMIT487=== the emitter untranslated-region handling (the Rust src)"
ls src/ 2>/dev/null | head -8
grep -rn -e "nop" src/ 2>/dev/null | head -10
echo "===C487DONE=== the original bytes at 0x8009A280 decide emission-gap vs missing-load - digest is pure ASCII"
