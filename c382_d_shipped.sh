#!/bin/bash
# c382_r1367.sh - THE R1367 PATCH+RUN CYCLE. The c381
# extraction decoded the misfire: R554 restores FDF8 =
# f_end - f_dst whenever the cb's FE08 cursor is inside the
# file-14 landing zone with FDF8==0 - and the ARCHIVE-era
# FE08 (ring slot 0x801F5320) falls NUMERICALLY inside the
# zone (end 0x801F809C), arming the receipted phantom
# 11644-byte backlog (113660+11644 = 125304 by construction)
# on the archive request. The kernel then believed it owed
# bytes, no ReadN formed for member=6 (LBA 239411), and the
# getsector data-wait spun to the fuse (exit 137, both
# boots). THIS PATCH: the request-identity gate - the seek
# cell FE04 must be in file-14's sector span [108933,108995)
# before any restore; plus a block camera (budget 8). The
# disc ADDRESS names the request (the CD model: reads carry
# no dest). PASS = R1367 blocks (~2, one per boot) + the
# archive walk proceeds past member=6 (sectors at 239411
# served) + no fault storm. REVERT on boot regression.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C382-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="13bc3bafa00d1cb05ddb1496adb335b94c3a49658a5206c2f4f74bd2d7b6c104"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1366 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1366 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c382_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "if (f_dst >= 0x801D9724u" "$SRC" || true)
PRE_G2=$(grep -c "R554 FDF8-restore DE-NESTED" "$SRC" || true)
PRE_G3=$(grep -c "R1367" "$SRC" || true)
echo "PRE f_dst-gate count=$PRE_G1 (must be 1)"
echo "PRE R554-comment count=$PRE_G2 (must be 1)"
echo "PRE R1367 count=$PRE_G3 (must be 0)"
if [ "$PRE_G1" != "1" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
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
    if s.startswith("/* R554 FDF8-restore DE-NESTED"):
        cam = [
            IND + "/* R1367 (c382): THE PHANTOM-BACKLOG GUARD. The c376/c380/c381",
            IND + " * receipts: the archive-era callback entered with FE08 = a RING",
            IND + " * SLOT (0x801F5320) that falls NUMERICALLY inside the file-14",
            IND + " * landing zone (end 0x801F809C), so R554 restored a phantom",
            IND + " * 11644-byte backlog (f_end - f_dst; 113660+11644 = 125304 by",
            IND + " * construction) on the ARCHIVE request - the kernel then believed",
            IND + " * it owed bytes, no ReadN formed for the game's next request",
            IND + " * (member=6 at LBA 239411), and the getsector data-wait spun to",
            IND + " * the fuse (exit 137, both boots identical). The disc ADDRESS is",
            IND + " * the request identity (the CD model: reads carry no dest; the",
            IND + " * seek names the file). R554 below now requires FE04 inside",
            IND + " * file-14's sector span [108933, 108995). This camera receipts",
            IND + " * each blocked would-be restore. */",
            IND + "if ((r[4] & 0xFFu) == 1u",
            IND + "    && xenolift_mem_read32(0x8004FE08u) >= 0x801D9724u",
            IND + "    && xenolift_mem_read32(0x8004FE08u) < (0x801D9724u + 125304u)",
            IND + "    && xenolift_mem_read32(0x8004FDF8u) == 0u",
            IND + "    && (xenolift_mem_read32(0x8004FE04u) < 108933u",
            IND + "        || xenolift_mem_read32(0x8004FE04u) >= 108995u)) {",
            IND + "    { static uint32_t r1367_n;",
            IND + "      if (r1367_n < 8u) { r1367_n++;",
            IND + '        r861_out("[fe34fix] R1367: phantom file-14 restore BLOCKED (dest %08X in zone but seek %u outside the 108933-108994 band - belongs to a different request)\\n",',
            IND + "                xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FE04u));",
            IND + "      } }",
            IND + "}",
        ]
        out.extend(cam)
        out.append(lines[i])
        edit1 += 1
        i += 1
        continue
    if s == "if (f_dst >= 0x801D9724u && f_dst < f_end":
        if i + 1 >= len(lines) or lines[i+1].strip() != "&& xenolift_mem_read32(0x8004FDF8u) == 0u) {":
            print("ANCHOR-FAILED: neighbor mismatch at %d" % i); sys.exit(1)
        ind = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
        new = [
            ind + "if (f_dst >= 0x801D9724u && f_dst < f_end",
            ind + "    && xenolift_mem_read32(0x8004FDF8u) == 0u",
            ind + "    /* R1367: the identity check - only restore when the seek",
            ind + "     * cell is inside file-14's sector span; any other LBA is a",
            ind + "     * different request (the ring-slot overlap trap). */",
            ind + "    && xenolift_mem_read32(0x8004FE04u) >= 108933u",
            ind + "    && xenolift_mem_read32(0x8004FE04u) < 108995u) {",
        ]
        out.extend(new)
        i += 2
        edit2 += 1
        continue
    out.append(lines[i])
    i += 1
if edit1 != 1 or edit2 != 1:
    print("ANCHOR-FAILED: edits %d/%d (must be 1/1)" % (edit1, edit2)); sys.exit(1)
patched = "\n".join(out)
if patched.count("R1367") != 3:
    print("POST-FAILED: R1367 count %d (must be 3)" % patched.count("R1367")); sys.exit(1)
old_pair = "if (f_dst >= 0x801D9724u && f_dst < f_end\n            && xenolift_mem_read32(0x8004FDF8u) == 0u) {"
if old_pair in patched:
    print("POST-FAILED: old gate pair still present"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1367 phantom-backlog guard + identity gate)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1367" "$SRC" || true)
POST_G2=$(grep -c "108995u) {" "$SRC" || true)
POST_G3=$(grep -c "if (f_dst >= 0x801D9724u" "$SRC" || true)
echo "POST R1367 count=$POST_G1 (must be 3)"
echo "POST 108995-gate count=$POST_G2 (must be 1)"
echo "POST f_dst-if count=$POST_G3 (must be 1)"
if [ "$POST_G1" != "3" ] || [ "$POST_G2" != "1" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c382_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c382_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN382=== the R1367 build, 120s budget, first-fault stop"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c382.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
echo "===FRESHLOG382=== the tree-root log (the c376 lesson: never witness dirs)"
ls -la run.log run.log.d 2>/dev/null
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c382.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1367GUARD382=== the phantom-block receipts (expect ~2, one per boot)"
grep -n "R1367" "$LOG" | head -8
echo "===FE34FIRE382=== the fe34fix family (the phantom restores must be GONE)"
grep -n "fe34fix\]" "$LOG" | head -10
echo "===MEMBERWALK382=== the walk past member=6?"
grep -n "stab\] req member=" "$LOG" | tail -10
echo "===NEWSECT382=== the 239411 serve (the ReadN that never formed - did it?)"
grep -n "LBA 2394" "$LOG" | grep "loaded into data FIFO" | tail -10
echo "===FDF8ARM382=== the arm story tail"
grep -n "FDF8 ARM-CONTEXT" "$LOG" | tail -6
echo "===CMDTL382=== the ladder tail"
grep -n "cmdtl\]" "$LOG" | tail -10
echo "===NEWMOD382=== module announces"
grep -n "newmod\]" "$LOG" | tail -6
echo "===R1366FIRE382=== the whole-member carry (if the walk reaches file-14)"
grep -n "R1366" "$LOG" | head -6
echo "===LZHLE382=== the decode receipts"
grep -n "lzss-hle" "$LOG" | tail -8
echo "===WEDGE382=== the spin census (is the wedge dead?)"
echo "wedgespin-total $(grep -c "wedgespin" "$LOG" || true)"
grep -n "wedgespin" "$LOG" | tail -3
echo "===FAULTS382=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "firstfault $(grep -c "firstfault\] R1172 BEGIN" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "segvdie $(grep -c "segvdie" "$LOG" || true)"
echo "===VIS382=== the exit + gpu story"
grep -n "rungasp" "$LOG" | tail -3
grep -n "gp0_words" "$LOG" | tail -3
grep -n "screen\] R693 snap" "$LOG" | tail -2
echo "===POSTSHA382==="
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C382DONE=== R1367 cycle complete - the verdict comes from these receipts"
