#!/bin/bash
# c274_servebody_srcdump.sh - READ-ONLY: the mvdoor FIRE BODY (the
# patch target for the sized serve) + the R896 sync-delivery
# precedent + the R892 done-block + the request-node cell readers.
# THE c273 DOSSIER VERDICT: TEARDOWN, NOT CONSUMPTION. The door fired
# once at the wedge; then the game own chain ran for the first time:
# the pending Setloc acks popped (02 01 01), GetStat issued and
# answered (cmd 02->01 FE1C=10), then cmd 01->09 PAUSE - the game
# post-read teardown ladder - then the fault-walk restart to state 0.
# The mdec receipts are init/reset only (mdec-writes=0).
# THE MECHANISM (receipted): the doorbell served ONE STALE
# 2060-byte FIFO sector (2048+12 raw header; the c212-era convicted
# class) to 800D0994, CLEARED the request cells (FDF8 16814->0,
# FE04->0), and set ARCHIVE-TRANSFER-DONE - announcing a 92180-byte
# request complete with 2060 bytes of possibly-wrong data. The
# file#6-era calibration (serve whole small file + done) applied to a
# 46-sector request. THE SERVE SIZE IS THE DEFECT. THE FIX (next
# cycle, after this dump receipts the anchors): size the serve to
# the request - deliver the full f15 batch (LBA 108995..109040,
# 92180B, disc source) into the request dest BEFORE the done-flag,
# using the R896 SYNC DELIVERY precedent (proven: full files from
# the disc to dst BEFORE the install chain runs).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C274-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="30c6d76d8538f951014282f30ed8c2454c2a191aa4eb429a6bb2eee5b4bb5530"
if [ ! -s "$SRC" ]; then echo "C274-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1331 tree 30c6d76d - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1331 doorbell-fire tree)"

dumpblock() {
  NAME="$1"; PAT="$2"; BEFORE="$3"; AFTER="$4"
  L=$(grep -n "$PAT" "$SRC" | head -1 | cut -d: -f1)
  echo "=== $NAME (anchor line $L)==="
  if [ -n "$L" ] && [ "$L" -gt 0 ] 2>/dev/null; then
    S=$((L-BEFORE)); [ "$S" -lt 1 ] && S=1
    E=$((L+AFTER))
    sed -n "${S},${E}p" "$SRC"
  else
    echo "ANCHOR NOT FOUND"
  fi
}

echo "===MDOORBODY274=== the mvdoor fire body (match -> R879 post -> R892 done): THE PATCH TARGET"
dumpblock "fire body" "if (r887_match)" 0 110

echo "===R896BODY274=== the sdoor SYNC DELIVERY precedent (full file from disc to dst)"
dumpblock "R896 sync delivery" "SYNC DELIVERY AT SEEK" 46 34

echo "===R892BODY274=== the archive-done block"
dumpblock "R892 done block" "ARCHIVE-TRANSFER-DONE SET" 8 10

echo "===NODE274=== the request-node cell readers (F10=00331524 node: dest + size fields)"
grep -n "80059F10" "$SRC" | head -8
dumpblock "the node-cell reader family" "uint32_t node = xenolift_mem_read32(0x80059F10u)" 6 16

echo "===C274DONE=== serve-body source dump complete - the sized-serve patch is designed from these receipts"
