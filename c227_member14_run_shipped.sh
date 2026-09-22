#!/bin/bash
# c227_member14_run.sh - VERIFICATION RUN, NO PATCH: the c226 tree (c821d139)
# receipted the state-1 mount fork FIXED (hand 125304 -> 801DD680 REAL from
# the TRUE sentinel, mount-cell 92BC=801DD680, member-14 fetch ISSUED, READ
# ISSUED file#=14 dst=801DD680 LBA 108933 125304B, abort-130=0). The 60s
# fuse cut the run while the read sat armed - this cycle runs 120s and
# receipts the full delivery chain: does the read machinery serve the
# member-14 read, does the menu module unpack from REAL data, does state 1
# install, does the screen hold menu content, does the pad poll.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C227-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
EXPECT="c821d139f2c30c9aa470ca274656956928f42d0f9989530fdf4aa1db6ac769f4"
if [ ! -s "$R" ]; then echo "C227-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "TREE_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the c226 R1318 tree c821d139 - no run"; exit 0; fi
echo "BASELINE_VERIFIED (the R1317+R1318 tree)"
P="run_c227_$(date +%Y%m%d_%H%M%S)"
if ! mkdir -p "$P"; then echo "C227-FAILED: snapshot dir"; exit 1; fi
if [ -s run.log ]; then cp -p run.log "$P/run.log.pre" && echo "RUNLOG_PRE sha=$(shasum -a 256 "$P/run.log.pre" | cut -d" " -f1)"; fi

echo "===RUN227=== the 120s verification run (no patch, pure run)"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c227.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c227.txt
grep -n "bldprov" /tmp/run_full_c227.txt | head -1
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===MOUNT227=== the state-1 mount census"
grep -n "mountrep\|MountGameStateModule\|mount-cell 0x800592BC" run.log 2>/dev/null | head -16

echo "===F14READ227=== the member-14 read chain"
grep -n "file#=14\|member=14" run.log 2>/dev/null | head -24

echo "===DOORS227=== the read-door receipts (tail = the member-14 era)"
grep -n "fldrd\|fld2\|fldsec\|fldfin\|sectserve\|fetchcam\|sgarm\|sgdecline\|stab\]" run.log 2>/dev/null | tail -40

echo "===PROG227=== the FDF8/req progression (tail = latest)"
grep -n "\[req\]" run.log 2>/dev/null | tail -12
grep -n "fetchcam" run.log 2>/dev/null | tail -8

echo "===UNPK227=== the member-14 unpack (looking for src=801DD680 = REAL data)"
grep -n "lzsscam\|lzss-t\|unpackw" run.log 2>/dev/null | tail -12

echo "===INSTALL227=== the state-1 install + menu census"
grep -n "menuchain\|KernelMenu" run.log 2>/dev/null | head -12
grep -n "statetbl" run.log 2>/dev/null | head -6
grep -o "cur=0x[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | sort -rn | head -6

echo "===ABRT227=== the fault/exit census"
echo "abort130=$(grep -c "AbortOnGameFault" run.log 2>/dev/null) unpackfix=$(grep -c "unpack-fix" run.log 2>/dev/null) bootmain=$(grep -c "bootmain" run.log 2>/dev/null) rungasp=$(grep -c "rungasp" run.log 2>/dev/null)"
grep -n "rungasp" run.log 2>/dev/null | tail -2

echo "===PAD227=== the input receipts"
echo "padstart=$(grep -c "padstart" run.log 2>/dev/null) padrd=$(grep -c "padrd" run.log 2>/dev/null)"
grep -n "padstart" run.log 2>/dev/null | tail -6

echo "===SCREEN227=== the visual witnesses + last-frame render"
grep -n "\[screen\]" run.log 2>/dev/null | tail -4
if [ -s vram_live.bin ]; then
  ls -la vram_live.bin | head -1
  python3 - <<'PYEOF'
data = open("vram_live.bin","rb").read()
W,H = 256,240
def px(x,y):
    off=(y*1024+x)*2
    if off+1 >= len(data): return 0
    w = data[off] | (data[off+1]<<8)
    r=(w&0x1F)<<3; g=((w>>5)&0x1F)<<3; b=((w>>10)&0x1F)<<3
    return (r*299+g*587+b*114)//1000
chars=" .:-=+*#%@"
print("--- luminance grid 32x15 (OBSERVED only - not a scene claim):")
for gy in range(0,H,16):
    row=""
    for gx in range(0,W,8):
        row += chars[min(9, px(gx,gy)*10//256)]
    print(row)
PYEOF
fi
echo "===C227DONE=== verification run complete - the c228 fix (if any) is decided by these receipts"
