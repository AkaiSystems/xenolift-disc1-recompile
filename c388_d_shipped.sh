#!/bin/bash
# c388_r1368.sh - THE R1368 PATCH+RUN CYCLE. The c387
# extraction: R155's lost-register kick snapshots FE04/FDF8
# at every READ ISSUED and fires when FE04 != the snapshotted
# LBA after 8 ticks - but in the native era the DRIVE advances
# FE04 per sector, so every healthy multi-sector read looks
# 'lost' (census: 4 fires - file#14 twice mid-read, file#18
# once post-completion). The kick resets healthy reads
# mid-stream, filling the buffer with the first 7 sectors on
# repeat - the unpack (word0=0003FAFE) failed prod=-1 past
# the repeat. THIS PATCH: the progress gate - kick2 fires ONLY
# when FDF8 >= the snapshotted full length (no bytes served =
# the request truly never started); a budget-8 camera
# receipts each block. PASS = zero kick fires + the file#14
# read completes (FDF8->0) + the unpack decodes natively (the
# R1366 oracle 260,862B) + Module-6 validation passes + no
# boot cycle + deeper walk. REVERT on regression.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C388-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="52566422c865ec549026ce84b82e19a568b61b0cdd1e78984656a5b55cc437f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1367 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1367 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c388_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "&& fe04_now != xenolift_kick2_lba" "$SRC" || true)
PRE_G2=$(grep -c "R155: LOST-REGISTER KICK" "$SRC" || true)
PRE_G3=$(grep -c "R1368" "$SRC" || true)
PRE_G4=$(grep -c "kick BLOCKED" "$SRC" || true)
echo "PRE kick2-anchor count=$PRE_G1 (must be 1)"
echo "PRE R155-comment count=$PRE_G2 (must be 1)"
echo "PRE R1368 count=$PRE_G3 (must be 0)"
echo "PRE cam-text count=$PRE_G4 (must be 0)"
if [ "$PRE_G1" != "1" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "0" ] || [ "$PRE_G4" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
lines = text.split("\n")
out = []
i = 0
edit1 = 0
edit2 = 0
IND = " " * 8
while i < len(lines):
    s = lines[i].strip()
    if s == "&& fe04_now != xenolift_kick2_lba":
        if i + 1 >= len(lines) or lines[i+1].strip() != "&& xenolift_mem_read32(0x8004FE1Cu) == 0u":
            print("ANCHOR-FAILED: neighbor mismatch at %d" % i); sys.exit(1)
        ind = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
        out.append(lines[i])
        out.append(lines[i+1])
        out.append(ind + "/* R1368 (c387): the progress gate - FDF8 below the snapshotted")
        out.append(ind + " * full length proves the request WAS started (bytes served); FE04")
        out.append(ind + " * then advancing is the drive's own seek advance, NOT a lost")
        out.append(ind + " * register (the c384-c386 receipts: the kick reset healthy")
        out.append(ind + " * file#14/#18 reads mid-stream, filling the buffer with the")
        out.append(ind + " * first 7 sectors on repeat). Never kick a progressing read;")
        out.append(ind + " * genuine no-progress lost-register postures still fire. */")
        out.append(ind + "&& xenolift_mem_read32(0x8004FDF8u) >= xenolift_kick2_len")
        i += 2
        edit1 += 1
        continue
    if s.startswith("/* R155: LOST-REGISTER KICK."):
        cam = [
            IND + "/* R1368 (c387): the block camera - receipts each kick2 the",
            IND + " * progress gate refused (read in flight or completed). */",
            IND + "if (xenolift_kick2_armed && xenolift_kick2_lba != 0u",
            IND + "    && xenolift_mem_read32(0x8004FE04u) != xenolift_kick2_lba",
            IND + "    && xenolift_mem_read32(0x8004FDF8u) < xenolift_kick2_len",
            IND + "    && xenolift_mem_read32(0x8004FE1Cu) == 0u",
            IND + "    && cd_pending <= 1u && cd_scheduled == 0u",
            IND + "    && cd_arm_int1_pending == 0u) {",
            IND + "    { static uint32_t r1368_n;",
            IND + "      if (r1368_n < 8u) { r1368_n++;",
            IND + '        r861_out("[cd] R1368: lost-register kick BLOCKED (read progressing: FE04=%u req LBA=%u, FDF8=%u < full %u) - the request WAS started\\n",',
            IND + "                xenolift_mem_read32(0x8004FE04u), xenolift_kick2_lba,",
            IND + "                xenolift_mem_read32(0x8004FDF8u), xenolift_kick2_len);",
            IND + "      } }",
            IND + "}",
        ]
        out.extend(cam)
        out.append(lines[i])
        edit2 += 1
        i += 1
        continue
    out.append(lines[i])
    i += 1
if edit1 != 1 or edit2 != 1:
    print("ANCHOR-FAILED: edits %d/%d (must be 1/1)" % (edit1, edit2)); sys.exit(1)
patched = "\n".join(out)
if patched.count("R1368") != 3:
    print("POST-FAILED: R1368 count %d (must be 3)" % patched.count("R1368")); sys.exit(1)
if patched.count(">= xenolift_kick2_len") != 1:
    print("POST-FAILED: gate count != 1"); sys.exit(1)
if patched.count("kick BLOCKED") != 1:
    print("POST-FAILED: camera count != 1"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1368 progress gate + block camera)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1368" "$SRC" || true)
POST_G2=$(grep -c ">= xenolift_kick2_len" "$SRC" || true)
POST_G3=$(grep -c "kick BLOCKED" "$SRC" || true)
echo "POST R1368 count=$POST_G1 (must be 3)"
echo "POST gate count=$POST_G2 (must be 1)"
echo "POST camera count=$POST_G3 (must be 1)"
if [ "$POST_G1" != "3" ] || [ "$POST_G2" != "1" ] || [ "$POST_G3" != "1" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c388_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c388_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN388=== the R1368 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c388.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c388.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1368GUARD388=== the block receipts (the gate engaging)"
grep -n "R1368" "$LOG" | head -10
echo "===KICKCENSUS388=== every kick fire (expect ZERO lost-register)"
echo "lost-register-total $(grep -c "lost-register kick:" "$LOG" || true)"
grep -n "lost-register kick:" "$LOG" | head -4
echo "===F14READ388=== the file#14 read completion story"
grep -n "READ ISSUED fn_80029690(file#=14" "$LOG" | head -3
grep -n "sector LBA 1089" "$LOG" | wc -l | tr -d ' '
echo "FDF8 drain tail:"
grep -n "0001E978\|125304" "$LOG" | tail -8
echo "===UNPACK388=== the file#14 unpack verdict (the R1366 oracle)"
grep -n "lzss-hle" "$LOG" | head -12
grep -n "a0=801DD680" "$LOG" | head -6
echo "===EPOCH388=== the boot epoch count (the cycle must be gone)"
grep -n "bootentry\]" "$LOG" | head -6
grep -n "fn_80019ACC error-dispatcher\|Module-6 validation" "$LOG" | head -4
echo "===WALK388=== the deeper walk (post-file-14 progress)"
grep -n "newmod\]" "$LOG" | tail -8
grep -n "cmdtl\]" "$LOG" | tail -8
echo "===FAULTS388=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "firstfault $(grep -c "firstfault\] R1172 BEGIN" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "segvdie $(grep -c "segvdie" "$LOG" || true)"
echo "===VIS388=== the exit + gpu + screen story (THE MILESTONE CHECK)"
grep -n "rungasp" "$LOG" | tail -2
grep -n "gp0_words" "$LOG" | tail -3
grep -n "screen\] R693 snap\|screen\] R695" "$LOG" | tail -3
echo "===TAIL388=== the last 20 receipts"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-20)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===POSTSHA388==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C388DONE=== the R1368 cycle is complete - the verdict comes from these receipts"
