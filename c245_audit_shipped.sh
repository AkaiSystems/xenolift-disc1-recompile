#!/bin/bash
# c245_module_content_audit.sh - READ-ONLY: no patch, no compile, no run.
# THE c244 VERDICT: all 3 seeds fired (state-1 x10 - the restore cycles
# with the restarts). THE FIRST FAULT is NOT the heap walk - it is the
# module GARBAGE DISPATCH chain: [fhelp] garbage jump #4 target=801FB3B0,
# then [modfn] module method 800781C0 entered with caller=0x48 (the
# words at 0x48 are ASCII TEXT - the module dispatched into a string
# region), guard reads, wild scratchpad jump, sp-poison fix, boot
# re-entry, and only THEN the walk trap - escalating to ~524K traps
# (latch=1) + a 1M-op LZSS runaway (frontier FFFFFFFC, the cursor=-8
# class) before the R1151 crash-kit converts. The terminal stall: the
# mvloop poll at FE1C=8 last_cmd=0D seek=2 FDF8=0x800 pend=0 sched=0 (a
# system-area read never served), with the game READING our injected
# START presses (padcell BFF74100). File#14 (state-1 module data, dst
# 801DD680) was READ ISSUED 4x - and 801DD680 sits INSIDE the stage-2
# window whose fault-time capture run.sh promotes for the next emit.
# HYPOTHESIS: the module data landed incomplete/corrupt and the game
# own validation keeps re-requesting it. DISCRIMINATOR (the c204
# content rule at last): byte-compare the disc file#14 payload vs the
# captured stage-2 window; dump the method bytes at 800781C0 (overlay
# offset 0x91C0) and the garbage target 801FB3B0 (offset 0x283B0);
# receipt the full fhelp/modfn family. The c246 fix is decided here.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C245-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="c010aab8ef71f1b011136a03c294e49d2202238fe52f49976845d7c125c633c1"
if [ ! -s "$LOG" ]; then echo "C245-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c243/c244-preserved log"; exit 0; fi
echo "BASELINE_VERIFIED"
P="audit_c245_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C245-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

echo "===GARBAGE244=== the full fhelp/modfn/wildctx family (the dispatch story)"
echo "fhelp=$(grep -c "fhelp\]" "$LOG") modfn=$(grep -c "modfn\]" "$LOG") wildctx=$(grep -c "wildctx\]" "$LOG") fhsite=$(grep -c "fhsite\]" "$LOG") spstub=$(grep -c "spstub\]" "$LOG") spexec=$(grep -c "spexec\]" "$LOG")"
grep -n "fhelp\]\|modfn\]\|wildctx\]" "$LOG" | head -14
echo "--- the trap latch census (held vs not):"
awk -F"latch " "/NULL-trap #/{print \$2}" "$LOG" | sort | uniq -c | head -6
echo "--- the lzss-runaway receipts:"
grep -n "lzss-runaway\|lzrwatch" "$LOG" | head -6

echo "===F14WALK245=== did the file#14 loads complete? (the 125304 walk)"
grep -n "125304" "$LOG" | head -10
grep -n "fldfin\|RESUMEFIX" "$LOG" | head -6
echo "--- the serve receipts for file#14's band (LBA 108933..):"
grep -n "sector serve" "$LOG" | awk -F: '$1>10000' | head -6

echo "===CONTENT245=== THE DISC-vs-MEMORY COMPARE (the c204 content rule)"
python3 - <<'PYEOF'
import hashlib, os

DISC = "/Users/joshuaghoreishi/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1).bin"
LBA, SIZE = 108933, 125304
DST = 0x801DD680
S2_BASE = 0x801D3000

if not os.path.exists(DISC):
    print("disc image missing: %s" % DISC)
else:
    with open(DISC, "rb") as f:
        raw = f.read()
    print("disc size=%d sectors=%d" % (len(raw), len(raw)//2352))
    # file#14 payload: mode-2 form-1, 2048 bytes/sector at +24
    data = b""
    lba, need = LBA, SIZE
    while need > 0:
        off = lba*2352 + 24
        data += raw[off:off+min(2048, need)]
        lba += 1; need -= 2048
    print("file#14 disc payload: %d bytes sha256=%s" % (len(data), hashlib.sha256(data).hexdigest()))
    # also try mode-1 (+16) in case the image is mode-1
    data1 = b""
    lba, need = LBA, SIZE
    while need > 0:
        off = lba*2352 + 16
        data1 += raw[off:off+min(2048, need)]
        lba += 1; need -= 2048
    print("file#14 (mode1+16)  : %d bytes sha256=%s" % (len(data1), hashlib.sha256(data1).hexdigest()))

    # the captured stage-2 window (fault-time capture) - where 801DD680 lives
    for cand in ("stage2_field.bin", "stage2_region.bin", "overlay_fault.bin"):
        if os.path.exists(cand):
            sz = os.path.getsize(cand)
            with open(cand, "rb") as f:
                cap = f.read()
            print("%s: %d bytes sha256=%s" % (cand, sz, hashlib.sha256(cap).hexdigest()))
            if len(cap) >= 0x21000:
                off_in = DST - S2_BASE
                inwin = min(SIZE, 0x21000 - off_in)
                seg = cap[off_in:off_in+inwin]
                print("  guest file#14 in-window part: off=0x%X len=%d sha256=%s" % (off_in, len(seg), hashlib.sha256(seg).hexdigest()))
                # diff against BOTH mode guesses
                for name, ref in (("mode2+24", data), ("mode1+16", data1)):
                    refseg = ref[:inwin]
                    diff = sum(1 for a, b in zip(seg, refseg) if a != b)
                    firstd = next((i for i, (a, b) in enumerate(zip(seg, refseg)) if a != b), -1)
                    print("  vs %s: bytes=%d differing=%d first-diff-off=0x%X %s" % (name, inwin, diff, firstd, "IDENTICAL" if diff == 0 else "DIFFERS"))
        else:
            print("%s: absent" % cand)

    # the module method 800781C0 lives in the STAGE-1 overlay (mapped 0x8006F000)
    for cand in ("overlay_region.bin",):
        if os.path.exists(cand):
            with open(cand, "rb") as f:
                ov = f.read()
            moff = 0x800781C0 - 0x8006F000
            words = [ov[moff+i*4] | (ov[moff+i*4+1]<<8) | (ov[moff+i*4+2]<<16) | (ov[moff+i*4+3]<<24) for i in range(12)]
            print("%s: method 800781C0 @off 0x%X first words: %s" % (cand, moff, " ".join("%08X" % w for w in words)))
            # the state-1 coordinator entry 80077E88 for comparison
            coff = 0x80077E88 - 0x8006F000
            cwords = [ov[coff+i*4] | (ov[coff+i*4+1]<<8) | (ov[coff+i*4+2]<<16) | (ov[coff+i*4+3]<<24) for i in range(4)]
            print("  coordinator 80077E88 @off 0x%X first words: %s" % (coff, " ".join("%08X" % w for w in cwords)))
        else:
            print("%s: absent" % cand)

    # the garbage jump target 801FB3B0 in the stage-2 window
    for cand in ("stage2_field.bin", "stage2_region.bin"):
        if os.path.exists(cand):
            with open(cand, "rb") as f:
                cap = f.read()
            if len(cap) >= 0x21000:
                goff = 0x801FB3B0 - S2_BASE
                gwords = [cap[goff+i*4] | (cap[goff+i*4+1]<<8) | (cap[goff+i*4+2]<<16) | (cap[goff+i*4+3]<<24) for i in range(8)]
                print("%s: garbage target 801FB3B0 @off 0x%X first words: %s" % (cand, goff, " ".join("%08X" % w for w in gwords)))
            break
PYEOF

echo "===CALLER245=== who dispatched the garbage? (the callsites around the first fhelp)"
FH=$(grep -n "fhelp\]" "$LOG" | head -1 | cut -d: -f1)
echo "first_fhelp_line=$FH"
if [ -n "$FH" ]; then
  S=$((FH-16)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((FH+4))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]" | head -16
fi

echo "===TERM245=== the terminal stall census (for the NEXT cycle)"
grep -c "waitbr\] R1306" "$LOG"
awk -F"FE1C=" "/waitbr/ {print \$2}" "$LOG" | cut -d" " -f1 | sort | uniq -c | head -6
echo "--- the last_cmd census at the stall:"
grep "mvloop" "$LOG" | tail -200 | grep -o "last_cmd=[0-9A-F]*" | sort | uniq -c

echo "===C245DONE=== module content audit complete - the c246 fix is decided by these receipts"
