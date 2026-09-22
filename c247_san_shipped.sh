#!/bin/bash
# c247_promotion_sanity.sh - THE R1324 VTABLE-SANITY GATE (one edit,
# run.sh). THE c246 RECEIPTS: the stage-2 promotion in run.sh is
# DRIFT-BASED ONLY (R789: |NZ-drift| > 20% promotes) - NO content
# validation; the fldcap2 capture in runtime.c is UNGUARDED (unlike
# [ovlfault], which has the R783 text-poison/same-words/zeros guards);
# and the CURRENT emit input head contains ZERO pointer-class words
# (00182100 1018C000 628C1800...), consistent with the module walking
# its callback table into ASCII STRINGS (16 skiphook receipts:
# Mod/Stre/Paus/ Err/Wait/ing). A string-era capture was burned in as
# emit input and every subsequent emit re-poisons the module.
# R1324: gate the promotion on CONTENT - the capture head must hold
# >=2 pointer-class words (0x80xxxxxx) among its first 16 words before
# it may overwrite stage2_region.bin; refusals keep the previous
# capture and print a receipt. If refusals persist, that RECEIPTS
# "the field install never completes with real vtables" - the next
# diagnostic. PASS = the gate holds (REFUSED receipt on garbage eras),
# stable compile cache, and the module-walk census tracked. REVERT =
# restore the preserved run.sh.pre.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C247-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
RSH="run.sh"
if [ ! -s "$RSH" ]; then echo "C247-FAILED: run.sh missing"; exit 1; fi
SS=$(shasum -a 256 "$RSH" | cut -d" " -f1)
echo "RUNSH_SHA_BEFORE=$SS"
P="patch_c247_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$RSH" "$P/run.sh.pre"); then echo "C247-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.sh.pre sha=$SS"

echo "===PATCH247=== the R1324 promotion gate (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("run.sh","rb").read()
if b"R1324" in data:
    print("IDEMPOTENT-SKIP: R1324 already present - no edit made"); sys.exit(0)

a = (b'        cp stage2_field.bin stage2_region.bin; echo "stage2: field-era capture '
     b'promoted to stage2_region.bin ($NZ nonzero hex chars, drift ${DRIFT}% > 20% era-jump gate)"\n')
n = data.count(a)
print("R1324 anchor count=%d (must be 1)" % n)
if n != 1: sys.exit(1)

gate = (b"        # R1324 VTABLE SANITY GATE (c247, the c245/c246 receipts): the\n"
 + b"        # unguarded promotion burned STRING-ERA captures in as emit input - the\n"
 + b"        # module walked its callback table into ASCII strings (16 skiphook\n"
 + b"        # receipts: Mod/Stre/Paus/ Err/Wait/ing; the ovlfault R783 poison\n"
 + b"        # guards exist for overlay_fault but the stage-2 path had NO content\n"
 + b"        # gate, only the R789 NZ-drift gate). GATE: the capture head must hold\n"
 + b"        # >=2 pointer-class words (0x80xxxxxx) among its first 16 words before\n"
 + b"        # it may overwrite stage2_region.bin; a refused string/garbage era\n"
 + b"        # KEEPS the previous capture. Persistent refusals receipt that the\n"
 + b"        # field install never completes with real vtables - the next target.\n"
 + b"        S2PTR=$(od -An -tx4 -N64 stage2_field.bin 2>/dev/null | tr -s ' \\t' '\\n' | grep -c '^80[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$' || true)\n"
 + b"        if [ \"${S2PTR:-0}\" -ge 2 ]; then\n"
 + b"          cp stage2_field.bin stage2_region.bin; echo \"stage2: field-era capture promoted to stage2_region.bin ($NZ nonzero hex chars, drift ${DRIFT}%, $S2PTR ptr-class head words)\"\n"
 + b"        else\n"
 + b"          echo \"stage2: promotion REFUSED (R1324 vtable sanity: $S2PTR ptr-class head words - string/garbage era; keeping previous capture)\"\n"
 + b"        fi\n")
data = data.replace(a, gate, 1)

checks = [("R1324", data.count(b"R1324"), 2),
          ("refused-receipt", data.count(b"promotion REFUSED"), 1),
          ("promoted-receipt", data.count(b"ptr-class head words"), 2),
          ("od-gate", data.count(b"od -An -tx4 -N64 stage2_field.bin"), 1)]
ok = True
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("run.sh","wb").write(data)
print("NEW_RUNSH_SHA=%s" % hashlib.sha256(data).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$RSH" | cut -d" " -f1)"

echo "===PARSE247=== the bash syntax gate (restore on break)"
if ! bash -n "$RSH"; then
  cp -p "$P/run.sh.pre" "$RSH"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===GATESELF247=== self-test the gate logic against the CURRENT artifacts"
S2PTR=$(od -An -tx4 -N64 stage2_region.bin 2>/dev/null | tr -s ' \t' '\n' | grep -c '^80[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$' || true)
echo "current stage2_region.bin ptr-class head words: ${S2PTR:-0} (the c245-era input - expect 0 = the receipted string era)"
S2PTRF=$(od -An -tx4 -N64 stage2_field.bin 2>/dev/null | tr -s ' \t' '\n' | grep -c '^80[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$' || true)
echo "current stage2_field.bin ptr-class head words: ${S2PTRF:-0} (the pending capture)"

echo "===RUN247=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c247.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c247.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===PROMO247=== the promotion receipts (did the gate hold?)"
grep -n "stage2:" /tmp/run_full_c247.txt | head -6
echo "--- the capture that arrived this run (head words):"
od -An -tx4 -N64 stage2_field.bin 2>/dev/null | head -2
echo "--- post-run region input (head words):"
od -An -tx4 -N64 stage2_region.bin 2>/dev/null | head -2

echo "===WALK247=== the module-walk census (strings still being executed?)"
echo "skiphook=$(grep -c "skiphook\]" run.log 2>/dev/null) fhelp=$(grep -c "fhelp\]" run.log 2>/dev/null) wildctx=$(grep -c "wildctx\]" run.log 2>/dev/null) vtcell=$(grep -c "vtcell\]" run.log 2>/dev/null) spstub=$(grep -c "spstub\]" run.log 2>/dev/null)"
grep -n "skiphook\]" run.log 2>/dev/null | head -4

echo "===TRAP247=== the trap census"
echo "traps=$(grep -c "NULL-trap #" run.log 2>/dev/null)"
awk -F"latch " "/NULL-trap #/{print \$2}" run.log 2>/dev/null | sort | uniq -c | head -4
grep -n "lzss-runaway\|lzrwatch" run.log 2>/dev/null | head -4

echo "===STATE247=== the state census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null)"
grep -n "STATE-1 CB ENTER" run.log 2>/dev/null | head -3
grep -n "active state" run.log 2>/dev/null | head -4
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===SCREEN247=== the scene census"
grep -n "nonblank" run.log 2>/dev/null | tail -3
grep -n "gpuprim" run.log 2>/dev/null | tail -3

echo "===C247DONE=== promotion sanity cycle complete - verdict from these receipts; REVERT = restore $P/run.sh.pre"
