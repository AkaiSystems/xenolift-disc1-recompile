#!/bin/bash
# c519_patch.sh - RESHIP of c518 (identical fix, corrected gates):
# c518 was REFUSED by a false-positive idempotency gate - the bare
# "R1380" string pre-exists in the true tree (an unrelated earlier
# R-number; the c420 unique-strings lesson). Gates now key on
# [postconv] and the L1807x full tags, provably absent. The fix body
# is UNCHANGED.
# c519 = THE POST-CONVERSION COLLECTOR PASS (R1380),
# the fix the c516/c517 receipts selected. NO RUN YET (this
# script patches + gates; the verdict run follows). THE
# RECEIPTED FAULT: the fd-tick conversion (line ~22408, the
# site that fires in the file#18 window) dispatches the
# handler pair - which posts the data event (the same store,
# sw_line 128995, the healthy 0x102 shape, receipted
# 10612+10621/10622) - but NEVER dispatches the collector, so
# the posted event sits unread while the game's own re-issue
# path (fn 8004247C's clearing at 10627) ERASES it before
# the game's next scan: slot=2 only, no h4, no cbcall, no
# DMA, no FDF8 progress. THE SIBLING PRECEDENTS (source-
# receipted c517): the R159 spin-conv (L5319) and R898
# force-deliver (L21548) sites BOTH dispatch the collector
# after the pair; the R259 block "mirrors the wait-loop's
# dispatch exactly". THIS PATCH inserts the missing pass at
# the fd-tick site, AFTER the R471 drain, INSIDE the
# conversion's if (fires only on conversion rounds): scan =
# dispatch fn_800415B4; read r[2] ONLY if the dispatch ran
# (the R1183 stale-register lesson); route slots&4 -> h4
# (the read-struct fallback, then known-native 0x8002B084)
# and slots&2 -> h2, same cells/args as the wait-loop;
# full register save/restore; prints rate-limited (first 24
# + every 256th); no cd_pending gate changes; the anti-
# forge checks apply per dispatch. Gates: anchor unique,
# R1380 absent pre-patch, post-counts from the artifact,
# HARD unpiped syntax gate with restore-on-fail.
# Fail-closed, tee'd to /tmp/c519_receipts.txt. Pure-ASCII
# output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C519-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c519_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
if grep -q -F -e "[postconv]" "$SRC"; then echo "VALID-FAILED: [postconv] already present - refusing (idempotent)"; exit 0; fi
if grep -q -F -e "L18071" "$SRC"; then echo "VALID-FAILED: L18071 already present - refusing (idempotent)"; exit 0; fi
if [ "$(grep -c -F -e "for (r471_n = 0;" "$SRC")" != "1" ]; then echo "GATE-FAILED: the R471 drain anchor is not unique - refusing"; exit 0; fi
if [ "$(grep -c -F -e "STACKED-PENDING DRAIN" "$SRC")" != "1" ]; then echo "GATE-FAILED: the R471 comment anchor is not unique - refusing"; exit 0; fi
cp -p "$SRC" "$SRC.pre_c519"
cat > /tmp/r1380_block.c <<'BLOCKEOF'
            { /* R1380 (c518): POST-CONVERSION COLLECTOR PASS. The c516 receipts: the fd-tick
               * conversion's handler pair posts the data event (the same store, sw_line 128995,
               * the healthy 0x102 shape, receipted 10612+10621/10622) - but this site never
               * ran the collector, so the posted event sat unread while the game's own re-issue
               * path (fn 8004247C's clearing at 10627) ERASED it before the game's next scan:
               * slot=2 only, no h4, no DMA, no FDF8 progress (the file#18 window). The R159
               * spin-conv (L5319) and R898 force-deliver (L21548) sites already dispatch the
               * collector after the pair; this site was missing it. Mirror the R259/R206
               * routing exactly (same cells, fallbacks, args). R1183: route on r[2] only if
               * the dispatch ran (stale-register lesson). Prints rate-limited; the pass is
               * bounded by the site's own conv_budget; no cd_pending gate changes. */
                static uint32_t r1380_n;
                uint32_t sr1380[32]; uint32_t s1380hi, s1380lo;
                int r1380_ran = 0;
                memcpy(sr1380, r, sizeof r); s1380hi = hi; s1380lo = lo;
                if (!r1179_forge_blocked("L18071")) { g_guest_depth++, xenolift_dispatch(0x800415B4u), g_guest_depth--; r1380_ran = 1; }
                if (r1380_ran) {
                    uint32_t slots1380 = r[2];
                    if (r1380_n < 24u || (r1380_n % 256u) == 0u)
                        r861_out("[postconv] R1380 post-conversion collector scan: slots=%u pend=%u last_cmd=%02X FDF8=%u fifo=%u/%u seek=%u\n",
                                slots1380, (unsigned)cd_pending, cd_last_cmd,
                                xenolift_mem_read32(0x8004FDF8u), cd_data_pos, cd_data_n, cd_seek_lba);
                    if (slots1380 & 4u) {
                        uint32_t h4 = *(uint32_t *)(xenolift_mem + 0x564AC);
                        if (!(h4 >= 0x80010000u && h4 < 0x80060000u)) {
                            uint32_t rs_h4 = xenolift_mem_read32(0x80059EF8u + 0x10u);
                            h4 = (rs_h4 >= 0x80010000u && rs_h4 < 0x80060000u) ? rs_h4 : 0x8002B084u;
                        }
                        if (h4 != 0u) {
                            r[4] = xenolift_mem[0x56789]; r[5] = 0x8005A218u;
                            if (r1380_n < 24u)
                                r861_out("[postconv] R1380 dispatch h4 0x%08X (a0=%u) - the posted data event consumed in-context\n", h4, r[4]);
                            if (!r1179_forge_blocked("L18072")) { g_guest_depth++, xenolift_dispatch(h4), g_guest_depth--; }
                        }
                    }
                    if (slots1380 & 2u) {
                        uint32_t h2 = *(uint32_t *)(xenolift_mem + 0x564A8);
                        if (h2 >= 0x80010000u && h2 < 0x80060000u) {
                            r[4] = xenolift_mem[0x56788]; r[5] = 0x8005A210u;
                            if (!r1179_forge_blocked("L18073")) { g_guest_depth++, xenolift_dispatch(h2), g_guest_depth--; }
                        }
                    }
                }
                memcpy(r, sr1380, sizeof r); hi = s1380hi; lo = s1380lo;
                r1380_n++;
            }
BLOCKEOF
python3 - <<'PYEOF'
lines = open("runtime/runtime.c").read().split("\n")
idx = None
for i, l in enumerate(lines):
    if "for (r471_n = 0;" in l:
        idx = i
        break
assert idx is not None, "anchor not found"
# find the for-loop's opening brace line, then walk to its close
j = idx
while "{" not in lines[j]:
    j += 1
depth = 0
k = j
while True:
    depth += lines[k].count("{") - lines[k].count("}")
    if depth == 0:
        break
    k += 1
# lines[k] closes the for body; the next line with only a closing brace closes the R471 scope
m = k + 1
while lines[m].strip() != "}":
    m += 1
insert_at = m + 1  # after the R471 scope closes = inside the conversion if
block = open("/tmp/r1380_block.c").read().rstrip("\n").split("\n")
new = lines[:insert_at] + block + lines[insert_at:]
open("runtime/runtime.c", "w").write("\n".join(new))
print("INSERTED at line %d (for-body close at %d, R471 scope close at %d)" % (insert_at + 1, k + 1, m + 1))
print("context before: %s" % lines[m - 1].strip()[:60])
print("context at close: %s" % lines[m].strip()[:60])
PYEOF
if [ "$?" != "0" ]; then echo "VALID-FAILED: splice failed - RESTORING"; cp -p "$SRC.pre_c519" "$SRC"; exit 0; fi
echo "===GATES519==="
E_POST=$(grep -c -e "postconv" /tmp/r1380_block.c | tr -d " ")
A_POST=$(grep -c -e "postconv" "$SRC" | tr -d " ")
A_L1=$(grep -c -F -e "L18071" "$SRC" | tr -d " ")
A_L2=$(grep -c -F -e "L18072" "$SRC" | tr -d " ")
A_L3=$(grep -c -F -e "L18073" "$SRC" | tr -d " ")
echo "postconv refs: expect $E_POST got $A_POST (the R1380 count gate is dropped - c518 was refused by a false-positive: the bare R1380 string pre-exists in the true tree, the c420 lesson)"
echo "L18071 refs: got $A_L1 (expect 1, full-tag only - the loose L1807 pattern also matched the pre-existing L18070, the sandbox-caught gate bug)"
echo "L18072 refs: got $A_L2 (expect 1)"
echo "L18073 refs: got $A_L3 (expect 1)"
if [ "$A_POST" != "$E_POST" ] || [ "$A_L1" != "1" ] || [ "$A_L2" != "1" ] || [ "$A_L3" != "1" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c518 tree"
  cp -p "$SRC.pre_c519" "$SRC"
  exit 0
fi
echo "GATES OK"
echo "--- the splice context (the block sits inside the conversion if, after the R471 drain):"
FL=$(grep -n -e "for (r471_n = 0;" "$SRC" | cut -d: -f1)
awk -v f="$FL" 'NR>=f-1 && NR<=f+28 { print NR": "$0 }' "$SRC" | tail -24
echo "===SYNCHK519=== HARD GATE syntax check (unpiped rc)"
cc -fsyntax-only "$SRC" > /tmp/c518_syn.txt 2>&1
SYN_RC=$?
head -8 /tmp/c518_syn.txt
echo "SYNCHK_RC=$SYN_RC"
if [ "$SYN_RC" != "0" ]; then
  echo "VALID-FAILED: the patched tree does not parse - RESTORING the pre-c518 tree"
  cp -p "$SRC.pre_c519" "$SRC"
  exit 0
fi
echo "SYNCHK OK"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===RUN519=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -30
echo "RUN_RC=$?"
echo "===DIGEST519==="
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "--- the [postconv] receipts (the fix's own evidence: the scan finding the posted event):"
grep -n -e "\[postconv\]" "$LOG" | head -20
echo "--- the file#18 delivery evidence (h4 dispatch, cbcall, dma, FDF8 progress):"
grep -n -e "dispatch h4" "$LOG" | awk 'NR>0 && /109158|postconv/ { print }' | head -6
grep -n -e "cd-dma.*109158" "$LOG" | head -6
grep -n -e "finstamp.*4FDF8" "$LOG" | awk '/14360|109158/ { print }' | head -8
echo "--- the file#18 window before/after (the old broken receipts vs the new):"
grep -n -e "\[lzss\] unpack.*zero" "$LOG" | head -3
grep -n -e "collector slot=4" "$LOG" | awk 'NR>=8 { print }' | head -8
echo "--- the ladder + the death receipt:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -3
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- tree sha at run time:"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C519DONE=== PASS = [postconv] slots=4 receipt + h4 dispatch + cd-dma at LBA 109158 + FDF8 countdown + the file#18 member consumed + forward execution past the unpack-on-zeros - digest is pure ASCII"
