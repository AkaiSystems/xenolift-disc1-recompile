#!/bin/bash
# c498_extract.sh - READ-ONLY DESIGN CENSUS, NO RUN, NO
# BUILD, NO PATCH, NO ARTIFACT MODIFICATION. The c497
# guard PASSed: the runtime now STOPS at wrong-module
# dispatches with a captured window. STAGE B-2 = the
# bounded interpreter that EXECUTES the live module
# bytes instead of stopping. THIS CENSUS receipts the
# exact integration points: (1) REGS498: the guest
# register array + the save/restore pattern; (2) MEM498:
# the memory helper signatures; (3) DISP498: the dispatch
# convention + the emitted-fn return shape; (4) R759498:
# the existing bounded executor (the seed); (5) POLL498:
# the dispatch-boundary drain (a long interpretation
# must service it); (6) COP2498: the GTE/COP2 routing.
# Fail-closed, tee'd to /tmp/c498_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C498-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c498_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="4342a7391696a99bdc7745ca697c9ec29ddcd3bf384ef5a2813d79644addcc9f"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c497 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c497 tree with the working guard)"
echo "===REGS498=== the guest register array + the save/restore pattern"
grep -n -e "sv_r\[" "$SRC" | head -6
grep -n -e "uint32_t r\[" "$SRC" | head -4
grep -n -e "] r;" "$SRC" | head -4
echo "--- the kick-restore context (the pattern the interpreter must respect):"
L=$(grep -n -e "for (i = 0; i < 32; i++) r\[i\] = sv_r\[i\];" "$SRC" | head -1 | cut -d: -f1)
echo "at line $L"
if [ -n "$L" ]; then sed -n "$(( L > 6 ? L - 6 : 1 )),$((L+6))p" "$SRC"; fi
echo "===MEM498=== the memory helper signatures"
grep -n -e "uint32_t xenolift_mem_read" "$SRC" | head -6
grep -n -e "void xenolift_mem_write" "$SRC" | head -6
grep -n -e "xenolift_mem_read8\b" "$SRC" | head -3
grep -n -e "xenolift_mem_write8\b" "$SRC" | head -3
echo "===DISP498=== the dispatch convention"
L=$(grep -n -e "^void xenolift_dispatch" "$SRC" | head -1 | cut -d: -f1)
echo "xenolift_dispatch at line $L"
if [ -n "$L" ]; then sed -n "${L},$((L+40))p" "$SRC"; fi
echo "--- the emitted-fn shape (entry + return) from disc1.c:"
LN=$(grep -n -e "0x800737EC (function)" disc1.c | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then sed -n "${LN},$((LN+14))p" disc1.c; fi
echo "--- an emitted fn END shape (a DISPATCH + a plain return):"
grep -n -e "DISPATCH(r\[31\])" disc1.c | head -3
echo "===R759498=== the existing bounded executor (the seed)"
grep -n -e "R759" "$SRC" | head -8
L=$(grep -n -e "R759" "$SRC" | grep -i -e "exec\|interp\|fetch" | head -1 | cut -d: -f1)
if [ -z "$L" ]; then L=$(grep -n -e "R759" "$SRC" | head -1 | cut -d: -f1); fi
echo "the executor region near line $L"
if [ -n "$L" ]; then sed -n "$(( L > 8 ? L - 8 : 1 )),$((L+50))p" "$SRC"; fi
echo "===POLL498=== the dispatch-boundary drain (what a long interpretation must service)"
grep -n -e "r918" "$SRC" | head -10
echo "===COP2498=== the GTE/COP2 routing"
grep -n -e "cop2\|COP2\|hle_gte\|gte_" "$SRC" | head -12
echo "===C498DONE=== the interpreter design follows from these receipts only - digest is pure ASCII"
