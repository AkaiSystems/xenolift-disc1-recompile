#!/bin/bash
# c376_r1366.sh - THE R1366 PATCH+RUN CYCLE. The c373/c374
# receipts settled the design: the game's unpack reads the
# buffer at dest with the kernel LZSS format [size:4]
# [groups from +4]; the only sane size word (0003FAFE =
# 260862) lives at member offset 0, and the reference decode
# proved the stream starts at member+4 (259,568 real bytes
# before the capture's boundary). The R495 carry's
# payload-only layout (file[8:] -> dest) puts FFFF9C30 at
# dest[0:4] - the core wraps its terminus backward and runs
# away (c371 receipts). THIS PATCH: scoped to the file-14
# class (cmap==14 && cdest==0x801DD680), the carry writes
# the WHOLE MEMBER from file offset 0 with a sector-aligned
# span (the LZSS continuation into the last sector's
# padding). Then the existing HLE gate passes (w0 sane),
# the receipted oracle decodes 260862, R1320's zero-write
# gives the clean guest exit, and the install chain proceeds
# with the REAL expanded module. PASS = [lzss-hle]
# expanded=260862 + [lzss-x] EXIT r5=r15=r14 + state-1
# receipts. REVERT on boot regression or fault storm.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C376-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="8d14ab4f2385a0004c28bd5a07bc762c5b9407b6da8a817d96554d5e91f226b0"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1365 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1365 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c376_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_KNOB=$(grep -c "rem = s_ovl_size\[cmap\];" "$SRC" || true)
echo "PRE rem-knob count=$PRE_KNOB (must be 1)"
PRE_R1366=$(grep -c "R1366" "$SRC" || true)
echo "PRE R1366 count=$PRE_R1366 (must be 0)"
if [ "$PRE_KNOB" != "1" ] || [ "$PRE_R1366" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
src_lines = text.split("\n")
out = []
hit = 0
i = 0
while i < len(src_lines):
    s = src_lines[i].strip()
    if s == "rem = s_ovl_size[cmap];":
        if i + 2 >= len(src_lines):
            print("ANCHOR-FAILED: truncated"); sys.exit(1)
        if src_lines[i+1].strip() != "src = 8u;" or src_lines[i+2].strip() != "doff = 0u;":
            print("ANCHOR-FAILED: neighbor lines mismatch at %d" % i); sys.exit(1)
        ind = src_lines[i][:len(src_lines[i]) - len(src_lines[i].lstrip())]
        new = [
            "int r1366_whole = (cmap == 14u && cdest == 0x801DD680u);",
            "if (r1366_whole) {",
            "    uint32_t r1366_span = ((r479_max + 2047u) / 2048u) * 2048u;",
            "    uint32_t r1366_dsg = cdest - 0x80000000u;",
            "    if (r1366_dsg + r1366_span <= 0x200000u) {",
            "        r479_max = r1366_span;",
            '        r861_out("[defib6] R1366 file-14 WHOLE-MEMBER layout: rem=%u src=0 dest=0x%08X span=%u (member incl. the 8B header + sector padding for the LZSS continuation)\\n", r479_max, cdest, r1366_span);',
            "    } else {",
            "        r1366_whole = 0;",
            "    }",
            "}",
            "rem = r1366_whole ? r479_max : s_ovl_size[cmap];",
            "src = r1366_whole ? 0u : 8u;",
            "doff = 0u;",
        ]
        for n in new:
            out.append(ind + n)
        i += 3
        hit += 1
        continue
    out.append(src_lines[i])
    i += 1
if hit != 1:
    print("ANCHOR-FAILED: hits=%d (must be 1)" % hit); sys.exit(1)
patched = "\n".join(out)
if "rem = s_ovl_size[cmap];" in patched:
    print("POST-FAILED: old knob line still present"); sys.exit(1)
if patched.count("R1366") != 1 or patched.count("r1366_whole") != 5:
    print("POST-FAILED: marker counts wrong"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1366 file-14 whole-member layout, carry knobs)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_KNOB=$(grep -c "rem = r1366_whole" "$SRC" || true)
POST_R1366=$(grep -c "R1366" "$SRC" || true)
echo "POST rem-knob count=$POST_KNOB (must be 1)"
echo "POST R1366 count=$POST_R1366 (must be 1)"
if [ "$POST_R1366" != "1" ] || [ "$POST_KNOB" != "1" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
# R1366 reship: the c376 parse gate - the c376 false-fail was
# PRE-EXISTING implicit darwin decls (_dyld_get_image_header
# at 10711, runtime.c never includes mach-o/dyld.h; run.sh
# builds fine). Tolerate the implicit-decl class; syntax
# errors still fail the gate.
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c376_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c376_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN376=== the R1366 build, 120s budget, first-fault stop"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c376.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
W=$(ls -dt witness_* 2>/dev/null | head -1)
echo "WITNESS=$W"
LOG="$W/run.log"
[ -s "$LOG" ] || LOG="$W/run.log.d"
if [ -s "$LOG" ]; then
  echo "===R1366RECEIPTS=== the whole-member fires"
  grep -n "R1366" "$LOG" | head -6
  echo "===DEFIB376=== the carry receipts"
  grep -n "carry PROMOTE\|R473 stalled-load COMPLETED\|carry-v3" "$LOG" | head -12
  echo "===REHT376=== the alignment receipt (dest==header now)"
  grep -n "reshtail\]" "$LOG" | head -6
  echo "===LZHLE376=== the HLE decode + clean exit receipts"
  grep -n "lzss-hle\|dechist\|lzss-x\|R1320" "$LOG" | head -12
  echo "===UNPACK376=== the unpack receipts"
  grep -n "unpackw\|lzsscam\]" "$LOG" | tail -8
  echo "===FLDSTATE376=== the state-1 + install receipts"
  grep -n "statetbl\|pFnMain\|coordw\|fldsnap\|bankheal" "$LOG" | tail -10
  echo "===CMDTL376=== the command ladder"
  grep -n "cmdtl\]" "$LOG" | tail -10
  echo "===FTAB376=== the file reads"
  grep -n "READ ISSUED" "$LOG" | head -8
  echo "===FAULT376=== fault census"
  echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
  echo "firstfault $(grep -c "firstfault\] R1172 BEGIN" "$LOG" || true)"
  echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
  echo "segvdie $(grep -c "segvdie" "$LOG" || true)"
  echo "===VIS376=== run tail + gpu census"
  grep -n "rungasp\|gpufin\|gp0_words" "$LOG" | tail -6
  grep -n "screen\]" "$LOG" | tail -4
  echo "===SECTORS376=== sectors served"
  echo "total $(grep -c "sector LBA" "$LOG" || true)"
  grep -n "sector LBA 108933" "$LOG" | head -4
else
  echo "WITNESS-LOG-MISSING: preserving run_full tail"
  tail -20 /tmp/run_full_c376.txt
fi
echo "===POSTSHA376==="
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C376DONE=== R1366 cycle complete - the verdict comes from these receipts"
