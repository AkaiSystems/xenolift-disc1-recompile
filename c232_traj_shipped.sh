#!/bin/bash
# c232_deep_trajectory.sh - VERIFICATION RUN, NO PATCH: the c231 receipts
# (tree 3196afd3, the R1319 guest-native widen in) killed the runaway class
# ENTIRELY: lzrwatch=0, runaway lines=0, bootmain 8->3, every unpack exiting
# NATURALLY ([lzss-x] EXIT x8), menu init running - but that run took the
# file#3 archive trajectory, so the state-1 mount/member-14 era never
# happened and the widened branch never fired (proven no-op that run).
# This cycle runs 150s (more boot cycles to catch the deep trajectory) and
# receipts: the native-branch firing + the menu module's natural exit +
# cur=1 held + the state census + the trajectory census (which files each
# era walks). PASS = [fldfp] guest-native decompress fires for the
# 801DD680->8006FAF0/260862 stream, [lzss-x] EXIT at r5=r15=800AF5EE,
# no lzrwatch, cur=1 held, active state 1, coordinator entry.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C232-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
EXPECT="3196afd3620848ed4de8c6660c66b99e2e9f0dd8e8edce4d003b466164bff836"
if [ ! -s "$R" ]; then echo "C232-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "TREE_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the c231 R1319 tree 3196afd3 - no run"; exit 0; fi
echo "BASELINE_VERIFIED (the R1317+R1318+R1319 tree)"
P="run_c232_$(date +%Y%m%d_%H%M%S)"
if ! mkdir -p "$P"; then echo "C232-FAILED: snapshot dir"; exit 1; fi
if [ -s run.log ]; then cp -p run.log "$P/run.log.pre" && echo "RUNLOG_PRE sha=$(shasum -a 256 "$P/run.log.pre" | cut -d" " -f1)"; fi

echo "===RUN232=== the 150s verification run (no patch, pure run)"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c232.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c232.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===NATIVE232=== the guest-native branch receipts (THE BRANCH FIRING)"
grep -n "fldfp\|R1319" run.log 2>/dev/null | head -8
grep -n "lzss-hle\] src=0x801DD680" run.log 2>/dev/null | head -4

echo "===EXIT232=== the natural-exit receipts"
grep -c "lzss-x\] EXIT" run.log 2>/dev/null
grep -n "lzss-x\] EXIT" run.log 2>/dev/null | grep "800AF5EE\|8006FAF0\|8006FAF8" | head -6
echo "lzrwatch=$(grep -c lzrwatch run.log 2>/dev/null) runaway=$(grep -c lzss-runaway run.log 2>/dev/null)"

echo "===DD680232=== the state-1 mount era (member-14 trajectory)"
echo "dd680_mentions=$(grep -c "801DD680" run.log 2>/dev/null)"
grep -n "mountrep\|member=14\|file#=14" run.log 2>/dev/null | head -16

echo "===STATE232=== the state census"
grep -n "active state" run.log 2>/dev/null | head -8
echo "cur1_receipts=$(grep -c "cur=0x00000001" run.log 2>/dev/null) coord_entries=$(grep -c coordw run.log 2>/dev/null)"
grep -n "menuchain\|KernelMenu" run.log 2>/dev/null | head -8
grep -n "80077E88" run.log 2>/dev/null | grep -v "coordw\|narrowblast\|statetbl" | head -8

echo "===TRAJ232=== the trajectory census (which files each era walks)"
grep -n "READ ISSUED\|ftab\] file#=" run.log 2>/dev/null | grep -o "file#[0-9]*" | sort | uniq -c | sort -rn | head -8
grep -n "READ ISSUED" run.log 2>/dev/null | head -8

echo "===CENSUS232=== the fault/exit census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) abort130=$(grep -c AbortOnGameFault run.log 2>/dev/null) unpackfix=$(grep -c unpack-fix run.log 2>/dev/null)"
grep -n "rungasp" run.log 2>/dev/null | tail -2
grep -n "bldprov" /tmp/run_full_c232.txt 2>/dev/null | head -1

echo "===SCREEN232=== the visual witnesses + last-frame render"
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
echo "===PAD232==="
echo "padstart=$(grep -c padstart run.log 2>/dev/null) padrd=$(grep -c padrd run.log 2>/dev/null)"
echo "===C232DONE=== verification run complete - the next fix (if any) is decided by these receipts"
