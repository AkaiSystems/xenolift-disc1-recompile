#!/bin/bash
# c504_patch.sh - STAGE B-2 v1 AT THE TRUE HOME: the R1394
# module-window interpreter with the guard at the HEAD of
# disc1.c's pristine dispatcher. The c503 probe receipted
# the site: the dispatcher definition is at disc1.c line
# 1014081 ('void xenolift_dispatch(uint32_t pc)' + brace
# next line), the R323 patcher is IDEMPOTENT and a no-op
# today (trampoline markers gone from disc1.c), and run.sh
# carries a proven post-emit patcher chain (R1202/R323/R766/
# R1153/R1154) that re-applies disc1.c patches after fresh
# emits. FOUR COORDINATED EDITS: (1) disc1.c: the guard
# call right after the dispatcher's opening brace, BEFORE
# the BIOS gates; (2) runtime/xenolift_runtime.h: the
# extern guard proto next to the dispatch declaration
# (durable - the header is hand-maintained core, never
# emit-wiped); (3) runtime/runtime.c: the R1394 head
# comment + the interpreter tail (guard EXTERN def + interp,
# GTE compute = hle_gte_execute with the (word)->(w) arg
# map receipted by c502); (4) run.sh: an idempotent
# post-emit patcher call (the R1202 pattern) so a fresh
# emit re-applies the disc1.c splice automatically.
# Hard-gated unpiped syntax checks on runtime.c + disc1.c
# (mirrors the build's own cc line); build + the 190s
# verdict run + digest. Fail-closed, tee'd to
# /tmp/c504_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C504-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c504_receipts.txt) 2>&1
SRC="runtime/runtime.c"
HDR="runtime/xenolift_runtime.h"
DISC="disc1.c"
RS="run.sh"
EXPECT="4342a7391696a99bdc7745ca697c9ec29ddcd3bf384ef5a2813d79644addcc9f"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c497 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c497 tree)"
if grep -q "r1394_interp" "$SRC"; then echo "VALID-FAILED: R1394 already present in runtime.c - refusing (idempotent)"; exit 0; fi
if grep -q "r1394_dispatch_guard" "$DISC"; then echo "VALID-FAILED: the disc1.c dispatcher already carries the guard - refusing (idempotent)"; exit 0; fi
echo "===LOCATE504=== the dispatcher anchor in disc1.c (the exact R323 anchor)"
ANCH="void xenolift_dispatch(uint32_t pc)"
L=$(grep -n -F -e "$ANCH" "$DISC" | grep -v -e "xenolift_dispatch(0x" | grep -v -e "xenolift_dispatch(__t)" | head -1 | cut -d: -f1)
if [ -z "$L" ]; then echo "VALID-FAILED: the dispatcher definition not found in disc1.c - refusing"; exit 0; fi
NEXT=$(sed -n "$((L+1))p" "$DISC")
echo "definition at disc1.c line $L; next line: $NEXT"
case "$NEXT" in
  "{"*) echo "brace on next line (the exact R323 anchor shape)" ;;
  *) echo "VALID-FAILED: unexpected brace shape - refusing"; exit 0 ;;
esac
echo "===GTEEX504=== the runtime's own GTE compute-op call (from the COP2 region)"
COP2_LN=$(grep -n -e "the GTE, the PS1's 3D math chip" "$SRC" | head -1 | cut -d: -f1)
if [ -z "$COP2_LN" ]; then COP2_LN=$(grep -n -e "COP2" "$SRC" | head -1 | cut -d: -f1); fi
echo "the COP2 region anchored at line $COP2_LN"
GTE_CALL=$(sed -n "${COP2_LN},$((COP2_LN+260))p" "$SRC" | grep -o -e "hle_gte_[a-z_]*(w)" -e "hle_gte_[a-z_]*(word)" | sort -u | grep -v -e "hle_gte_read_data" -e "hle_gte_read_ctrl" -e "hle_gte_write_data" -e "hle_gte_write_ctrl" | head -1)
echo "GTE compute call candidate: [${GTE_CALL}]"
GTE_NAME=$(printf "%s" "$GTE_CALL" | sed "s/(.*//")
if [ -n "$GTE_NAME" ]; then
  GTE_WIRED="${GTE_NAME}(w)"
  echo "(wired: ${GTE_CALL} -> ${GTE_WIRED} - the interpreter's word variable is w)"
else
  GTE_WIRED=""
  echo "(absent/ambiguous: the explicit unsupported-GTE stop ships; the census print names the wiring for v2)"
fi
sed -n "${COP2_LN},$((COP2_LN+260))p" "$SRC" | grep -n -e "hle_gte" | head -14
echo "===PATCH504=== head + tail in runtime.c; proto in the header; splice in disc1.c; patcher in run.sh"
cat > /tmp/r1394_head.c <<'BLOCKEOF'
/* R1394 (c504): the module-window interpreter, stage B-2 v1. The dispatch
 * guard (EXTERN, declared in xenolift_runtime.h; called from disc1.c's
 * dispatcher) compares the live module window against the emit-era
 * reference (emit_ref.bin) and on mismatch INTERPRETS the installed
 * module's live bytes instead of running the unrelated emitted
 * translation. Full design notes + the v1 limits (local hi/lo, COP0
 * unsupported, 4M-instruction budget, explicit [ovlstop] fail-safe) are
 * in the definition at the end of this file. */
BLOCKEOF
cat > /tmp/r1394_postemit_guard.py <<'PGEOF'
# R1394 (c504) post-emit patcher: re-apply the dispatch guard splice to a
# freshly emitted disc1.c (the R1202 pattern: idempotent, self-contained).
s = open('disc1.c').read()
anchor = 'void xenolift_dispatch(uint32_t pc)' + chr(10) + '{' + chr(10)
splice = '    if (r1394_dispatch_guard(pc)) { return; }' + chr(10)
if 'r1394_dispatch_guard' in s:
    print('[emit] R1394 dispatch guard already present')
elif anchor in s:
    s = s.replace(anchor, anchor + splice, 1)
    open('disc1.c', 'w').write(s)
    print('[emit] R1394 dispatch guard APPLIED (post-emit)')
else:
    print('[emit] R1394 ANCHOR MISSING (dispatch fn not found) - check manually')
PGEOF
printf "%s" "$GTE_WIRED" > /tmp/gte_call.txt
cat > /tmp/r1394_tail_template.c <<'XTEMPLATEX'

/* R1394 (c499): THE MODULE-WINDOW INTERPRETER, stage B-2 v1 (Jos's mandate:
 * a correct interpreter fallback instead of executing an unrelated
 * translation). The R1393 guard (c497) stops wrong-module dispatches; this
 * stage EXECUTES the installed module's live bytes instead. Design from the
 * c498 census receipts: guest regs = the global r[32]; memory via the
 * xenolift_mem_* helpers (every HLE hook stays live); the guard sits at the
 * HEAD of xenolift_dispatch (xenolift_trace is inside the emitted fn - an
 * interpreter returning there would run the wrong body after). CONTROL
 * RULE: a jump/branch/jr OUT of the window = the module hands control away
 * (a return or tail-jump) - tail-dispatch natively and the interpreted fn
 * is COMPLETE; a jal/jalr OUT of the window = a CALL into kernel code -
 * dispatch natively (the kick pattern) and RESUME interpretation at the
 * link address. v1 LIMITS (receipted): local hi/lo; COP0 unsupported; a 4M
 * instruction budget per call; any unhandled opcode -> the explicit
 * [ovlstop] (capture + exit 99), never silent execution. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
static unsigned int g_r1394_hi, g_r1394_lo;
static int r1394_interp(uint32_t entry);

/* R1394: the dispatch-level guard. Returns 1 = handled (the emitted
 * translation must NOT run); 0 = proceed natively. */
int r1394_dispatch_guard(unsigned int t)
{
    unsigned char lw[16];
    int rc;
    if (t < 0x8006F000u || t >= 0x80090000u) { return 0; }
    if (g_r1393_ref_loaded == 0) {
        FILE *f = fopen("emit_ref.bin", "rb");
        if (!f) { r861_out("[ovlstop] R1393 emit_ref.bin missing - guard INACTIVE\n"); g_r1393_ref_loaded = -1; return 0; }
        if (fread(g_r1393_ref, 1u, 0x21000u, f) != 0x21000u) { fclose(f); g_r1393_ref_loaded = -1; return 0; }
        fclose(f);
        g_r1393_ref_loaded = 1;
        r861_out("[ovlstop] R1393 emit-era reference loaded (the pSYW6z window, receipted at the fault addresses)\n");
    }
    if (g_r1393_ref_loaded < 0) { return 0; }
    memcpy(lw, xenolift_mem + (t - 0x80000000u), 16);
    if (memcmp(lw, g_r1393_ref + (t - 0x8006F000u), 16) == 0) { return 0; }
    xenolift_cur_fn = t;
    {
        static unsigned int gn = 0;
        gn++;
        if (gn <= 32u || (gn % 4096u) == 0u)
            r861_out("[ovlint] R1394 guard #%u: the live module at %08X is NOT the emit-era ref - INTERPRETING the installed module (never the wrong translation)\n", gn, t);
    }
    rc = r1394_interp(t);
    if (rc != 0) {
        r861_out("[ovlstop] R1394 interpreter FAIL class=%d fn=%08X - the explicit unsupported-overlay stop\n", rc, t);
        {
            FILE *cf = fopen("ovlstop_capture.bin", "wb");
            if (cf) { fwrite(xenolift_mem + 0x6F000u, 1u, 0x21000u, cf); fclose(cf); }
            r861_out("[ovlstop] R1393 window captured to ovlstop_capture.bin (135168 bytes)\n");
        }
        fflush(0);
        _exit(99);
    }
    return 1;
}

/* R1394: the bounded MIPS interpreter (v1). Returns 0 = ok (the fn
 * completed and control was dispatched onward); 2 = budget exhausted;
 * 3 = unsupported opcode; never silent. */
static int r1394_interp(uint32_t entry)
{
    uint32_t pc = entry, npc = entry + 4;
    int act = 0;            /* 0 = in-module flow; 1 = exit-out pending; 2 = call-out pending */
    uint32_t act_ret = 0;   /* the link address for a call-out */
    long long budget = 4000000;
    static unsigned int ent_n = 0, uns_n = 0;
    ent_n++;
    if (ent_n <= 32u || (ent_n % 4096u) == 0u)
        r861_out("[ovlint] R1394 interp entry #%u fn=%08X r31=%08X sp=%08X\n", ent_n, entry, (unsigned)r[31], (unsigned)r[29]);
    while (budget-- > 0) {
        uint32_t w, op, rs, rt, rd, sa, fn_, immu, tgt;
        int32_t imm;
        if (pc < 0x8006F000u || pc >= 0x80090000u) {
            /* control has left the module window */
            if (act == 1) { xenolift_cur_fn = pc; g_guest_depth++; xenolift_dispatch(pc); g_guest_depth--; return 0; }
            if (act == 2) {
                xenolift_cur_fn = pc; g_guest_depth++; xenolift_dispatch(pc); g_guest_depth--;
                pc = act_ret; npc = act_ret + 4; act = 0;
                continue;
            }
            if (uns_n < 16u) { uns_n++; r861_out("[ovlint] R1394 CONTROL OUTSIDE WINDOW without a jump (act=0) pc=%08X - the explicit stop class\n", pc); }
            return 3;
        }
        w = xenolift_mem_read32(pc);
        op = w >> 26; rs = (w >> 21) & 31; rt = (w >> 16) & 31;
        rd = (w >> 11) & 31; sa = (w >> 6) & 31; fn_ = w & 63;
        immu = w & 0xFFFFu; imm = (int16_t)immu;
        if (op == 0x00u) { /* SPECIAL */
            if (fn_ == 0x00u) { r[rd] = r[rs] << sa; }
            else if (fn_ == 0x02u) { r[rd] = r[rs] >> sa; }
            else if (fn_ == 0x03u) { r[rd] = (uint32_t)((int32_t)r[rs] >> sa); }
            else if (fn_ == 0x04u) { r[rd] = r[rs] << (r[rt] & 31); }
            else if (fn_ == 0x06u) { r[rd] = r[rs] >> (r[rt] & 31); }
            else if (fn_ == 0x07u) { r[rd] = (uint32_t)((int32_t)r[rs] >> (r[rt] & 31)); }
            else if (fn_ == 0x08u) { /* jr */
                tgt = r[rs];
                act = (tgt < 0x8006F000u || tgt >= 0x80090000u) ? 1 : 0;
                pc = npc; npc = tgt;
                continue; /* the slot executes next iteration */
            }
            else if (fn_ == 0x09u) { /* jalr */
                uint32_t tv = r[rs];
                r[rd] = npc + 4;
                if (tv < 0x8006F000u || tv >= 0x80090000u) { act = 2; act_ret = r[rd]; }
                else { act = 0; }
                pc = npc; npc = tv;
                continue;
            }
            else if (fn_ == 0x10u) { r[rd] = g_r1394_hi; }
            else if (fn_ == 0x11u) { g_r1394_hi = r[rs]; }
            else if (fn_ == 0x12u) { r[rd] = g_r1394_lo; }
            else if (fn_ == 0x13u) { g_r1394_lo = r[rs]; }
            else if (fn_ == 0x18u) { int64_t p = (int64_t)(int32_t)r[rs] * (int64_t)(int32_t)r[rt]; g_r1394_lo = (uint32_t)p; g_r1394_hi = (uint32_t)((uint64_t)p >> 32); }
            else if (fn_ == 0x19u) { uint64_t p = (uint64_t)r[rs] * (uint64_t)r[rt]; g_r1394_lo = (uint32_t)p; g_r1394_hi = (uint32_t)(p >> 32); }
            else if (fn_ == 0x1Au) { int32_t a = (int32_t)r[rs], b = (int32_t)r[rt]; g_r1394_lo = (b == 0) ? 0 : (uint32_t)(a / b); g_r1394_hi = (b == 0) ? 0 : (uint32_t)(a % b); }
            else if (fn_ == 0x1Bu) { uint32_t a = r[rs], b = r[rt]; g_r1394_lo = (b == 0) ? 0 : a / b; g_r1394_hi = (b == 0) ? 0 : a % b; }
            else if (fn_ == 0x20u || fn_ == 0x21u) { r[rd] = r[rs] + r[rt]; }
            else if (fn_ == 0x22u || fn_ == 0x23u) { r[rd] = r[rs] - r[rt]; }
            else if (fn_ == 0x24u) { r[rd] = r[rs] & r[rt]; }
            else if (fn_ == 0x25u) { r[rd] = r[rs] | r[rt]; }
            else if (fn_ == 0x26u) { r[rd] = r[rs] ^ r[rt]; }
            else if (fn_ == 0x27u) { r[rd] = ~(r[rs] | r[rt]); }
            else if (fn_ == 0x2Au) { r[rd] = ((int32_t)r[rs] < (int32_t)r[rt]) ? 1u : 0u; }
            else if (fn_ == 0x2Bu) { r[rd] = (r[rs] < r[rt]) ? 1u : 0u; }
            else { if (uns_n < 16u) { uns_n++; r861_out("[ovlint] R1394 UNSUPPORTED SPECIAL fn=%02X at pc=%08X w=%08X\n", fn_, pc, w); } return 3; }
        }
        else if (op == 0x01u) { /* REGIMM: bltz/bgez/bltzal/bgezal */
            int cond = 0;
            if (rt == 0x00u) { cond = ((int32_t)r[rs] < 0); }
            else if (rt == 0x01u) { cond = ((int32_t)r[rs] >= 0); }
            else if (rt == 0x10u) { cond = ((int32_t)r[rs] < 0); }
            else if (rt == 0x11u) { cond = ((int32_t)r[rs] >= 0); }
            else { if (uns_n < 16u) { uns_n++; r861_out("[ovlint] R1394 UNSUPPORTED REGIMM rt=%02X at pc=%08X w=%08X\n", rt, pc, w); } return 3; }
            if (rt == 0x10u || rt == 0x11u) { r[31] = npc + 4; }
            if (cond) {
                tgt = pc + 4 + ((int32_t)imm << 2);
                if (tgt < 0x8006F000u || tgt >= 0x80090000u) { act = 1; }
                pc = npc; npc = tgt;
                continue;
            }
        }
        else if (op == 0x02u) { tgt = ((pc + 4) & 0xF0000000u) | ((w & 0x3FFFFFFu) << 2); if (tgt < 0x8006F000u || tgt >= 0x80090000u) { act = 1; } pc = npc; npc = tgt; continue; }
        else if (op == 0x03u) { r[31] = npc + 4; tgt = ((pc + 4) & 0xF0000000u) | ((w & 0x3FFFFFFu) << 2); if (tgt < 0x8006F000u || tgt >= 0x80090000u) { act = 2; act_ret = r[31]; } pc = npc; npc = tgt; continue; }
        else if (op == 0x04u) { if (r[rs] == r[rt]) { tgt = pc + 4 + ((int32_t)imm << 2); if (tgt < 0x8006F000u || tgt >= 0x80090000u) { act = 1; } pc = npc; npc = tgt; continue; } }
        else if (op == 0x05u) { if (r[rs] != r[rt]) { tgt = pc + 4 + ((int32_t)imm << 2); if (tgt < 0x8006F000u || tgt >= 0x80090000u) { act = 1; } pc = npc; npc = tgt; continue; } }
        else if (op == 0x06u) { if ((int32_t)r[rs] <= 0) { tgt = pc + 4 + ((int32_t)imm << 2); if (tgt < 0x8006F000u || tgt >= 0x80090000u) { act = 1; } pc = npc; npc = tgt; continue; } }
        else if (op == 0x07u) { if ((int32_t)r[rs] > 0) { tgt = pc + 4 + ((int32_t)imm << 2); if (tgt < 0x8006F000u || tgt >= 0x80090000u) { act = 1; } pc = npc; npc = tgt; continue; } }
        else if (op == 0x08u || op == 0x09u) { r[rt] = r[rs] + (uint32_t)imm; }
        else if (op == 0x0Au) { r[rt] = ((int32_t)r[rs] < imm) ? 1u : 0u; }
        else if (op == 0x0Bu) { r[rt] = (r[rs] < (uint32_t)imm) ? 1u : 0u; }
        else if (op == 0x0Cu) { r[rt] = r[rs] & immu; }
        else if (op == 0x0Du) { r[rt] = r[rs] | immu; }
        else if (op == 0x0Eu) { r[rt] = r[rs] ^ immu; }
        else if (op == 0x0Fu) { r[rt] = immu << 16; }
        else if (op == 0x20u) { uint32_t v = xenolift_mem_read8(r[rs] + (uint32_t)imm); r[rt] = (uint32_t)(int32_t)(int8_t)v; }
        else if (op == 0x21u) { uint32_t v = xenolift_mem_read16(r[rs] + (uint32_t)imm); r[rt] = (uint32_t)(int32_t)(int16_t)v; }
        else if (op == 0x22u) { /* LWL */
            uint32_t a = r[rs] + (uint32_t)imm, old = xenolift_mem_read32(a & ~3u), sh = (a & 3u) * 8u;
            uint32_t m = (a & 3u) == 0u ? 0xFFFFFFFFu : (0xFFFFFFFFu >> sh);
            r[rt] = (r[rt] & ~m) | ((old << sh) & m);
        }
        else if (op == 0x23u) { r[rt] = xenolift_mem_read32(r[rs] + (uint32_t)imm); }
        else if (op == 0x24u) { r[rt] = xenolift_mem_read8(r[rs] + (uint32_t)imm); }
        else if (op == 0x25u) { r[rt] = xenolift_mem_read16(r[rs] + (uint32_t)imm); }
        else if (op == 0x26u) { /* LWR */
            uint32_t a = r[rs] + (uint32_t)imm, old = xenolift_mem_read32(a & ~3u), sh = (3u - (a & 3u)) * 8u;
            uint32_t m = (a & 3u) == 3u ? 0xFFFFFFFFu : (0xFFFFFFFFu << sh);
            r[rt] = (r[rt] & ~m) | ((old >> sh) & m);
        }
        else if (op == 0x28u) { xenolift_mem_write8(r[rs] + (uint32_t)imm, r[rt] & 0xFFu); }
        else if (op == 0x29u) { xenolift_mem_write16(r[rs] + (uint32_t)imm, r[rt] & 0xFFFFu); }
        else if (op == 0x2Au) { /* SWL */
            uint32_t a = r[rs] + (uint32_t)imm, old = xenolift_mem_read32(a & ~3u), sh = (a & 3u) * 8u;
            uint32_t m = (a & 3u) == 0u ? 0xFFFFFFFFu : (0xFFFFFFFFu >> sh);
            xenolift_mem_write32(a & ~3u, (old & ~m) | ((r[rt] >> sh) & m));
        }
        else if (op == 0x2Bu) { xenolift_mem_write32(r[rs] + (uint32_t)imm, r[rt]); }
        else if (op == 0x2Eu) { /* SWR */
            uint32_t a = r[rs] + (uint32_t)imm, old = xenolift_mem_read32(a & ~3u), sh = (3u - (a & 3u)) * 8u;
            uint32_t m = (a & 3u) == 3u ? 0xFFFFFFFFu : (0xFFFFFFFFu << sh);
            xenolift_mem_write32(a & ~3u, (old & ~m) | ((r[rt] << sh) & m));
        }
        else if (op == 0x12u) { /* COP2: the GTE */
            uint32_t sub = (w >> 21) & 31;
            if (sub == 0u) { r[rt] = hle_gte_read_data(rd); }
            else if (sub == 2u) { r[rt] = hle_gte_read_ctrl(rd); }
            else if (sub == 4u) { hle_gte_write_data(rd, r[rt]); }
            else if (sub == 6u) { hle_gte_write_ctrl(rd, r[rt]); }
            else { __GTE_COMPUTE_BODY__ }
        }
        else if (op == 0x32u) { /* LWC2 */
            uint32_t ea = r[rs] + (uint32_t)imm;
            hle_gte_write_data(rt, xenolift_mem_read32(ea));
        }
        else if (op == 0x3Au) { /* SWC2 */
            uint32_t ea = r[rs] + (uint32_t)imm;
            xenolift_mem_write32(ea, hle_gte_read_data(rt));
        }
        else { if (uns_n < 16u) { uns_n++; r861_out("[ovlint] R1394 UNSUPPORTED op=%02X at pc=%08X w=%08X\n", op, pc, w); } return 3; }
        pc = npc; npc = pc + 4;
    }
    r861_out("[ovlint] R1394 BUDGET EXHAUSTED fn=%08X last pc=%08X - the explicit stop class\n", entry, pc);
    return 2;
}

XTEMPLATEX
echo "template embedded: $(wc -l < /tmp/r1394_tail_template.c | tr -d ' ') lines"
python3 - <<'PYEOF'
tpl = open("/tmp/r1394_tail_template.c").read()
call = open("/tmp/gte_call.txt").read().strip()
if call:
    body = "{ if (uns_n < 16u) { uns_n++; }\n                " + call + "; }"
else:
    body = "{ if (uns_n < 16u) { uns_n++; r861_out(\"[ovlint] R1394 UNSUPPORTED GTE compute op at pc=%08X w=%08X - the explicit stop class (v2 wires the runtime's own GTE exec)\\n\", pc, w); } return 3; }"
open("/tmp/r1394_tail.c", "w").write(tpl.replace("__GTE_COMPUTE_BODY__", body))
print("tail built (GTE compute: %s)" % (call if call else "the explicit unsupported stop"))
PYEOF

cp -p "$SRC" "$SRC.pre_c504"
cp -p "$HDR" "$HDR.pre_c504"
cp -p "$DISC" "$DISC.pre_c504"
cp -p "$RS" "$RS.pre_c504"
HLINES=$(wc -l < /tmp/r1394_head.c | tr -d " ")
{ cat /tmp/r1394_head.c; cat "$SRC"; } > /tmp/rt_p1.c
{ cat /tmp/rt_p1.c; cat /tmp/r1394_tail.c; } > /tmp/rt_new.c
mv /tmp/rt_new.c "$SRC"
HDECL=$(grep -n -F -e "void xenolift_dispatch(uint32_t pc);" "$HDR" | head -1 | cut -d: -f1)
if [ -z "$HDECL" ]; then echo "VALID-FAILED: dispatch declaration not found in the header - RESTORING"; cp -p "$SRC.pre_c504" "$SRC"; cp -p "$DISC.pre_c504" "$DISC"; cp -p "$RS.pre_c504" "$RS"; exit 0; fi
awk -v L="$HDECL" 'NR==L {print; print "int r1394_dispatch_guard(unsigned int t); /* R1394 (c504): the module-window interpreter guard - extern, called from the disc1.c dispatcher */"; next} {print}' "$HDR" > /tmp/hdr_new.h
mv /tmp/hdr_new.h "$HDR"
INS=$(( L + 1 ))
awk -v L="$INS" 'NR==L {print; print "    if (r1394_dispatch_guard(pc)) { return; }"; next} {print}' "$DISC" > /tmp/disc_new.c
mv /tmp/disc_new.c "$DISC"
RSAN=$(grep -n -F -e "# R750/R752 GATED BYPASS" "$RS" | head -1 | cut -d: -f1)
if [ -z "$RSAN" ]; then echo "VALID-FAILED: the R750/R752 anchor not found in run.sh - RESTORING"; cp -p "$SRC.pre_c504" "$SRC"; cp -p "$HDR.pre_c504" "$HDR"; cp -p "$DISC.pre_c504" "$DISC"; exit 0; fi
awk -v L="$RSAN" 'NR==L {print "# R1394 (c504): re-apply the dispatch-guard splice post-emit (idempotent; the disc1.c dispatcher guard)"; print "python3 r1394_postemit_guard.py"; print ""; next} {print}' "$RS" > /tmp/rs_new.sh
mv /tmp/rs_new.sh "$RS"
cp -p /tmp/r1394_postemit_guard.py r1394_postemit_guard.py
echo "runtime.c: head + tail; header: proto at line $((HDECL+1)); disc1.c: splice at line $((INS+1)); run.sh: patcher call before line $RSAN"
echo "===GATES504==="
E_INT=$(grep -c -e "r1394_interp" /tmp/r1394_tail.c | tr -d " ")
A_INT_TOT=$(grep -c -e "r1394_interp" "$SRC" | tr -d " ")
A_GRD_RT=$(grep -c -e "r1394_dispatch_guard" "$SRC" | tr -d " ")
A_GRD_HDR=$(grep -c -e "r1394_dispatch_guard" "$HDR" | tr -d " ")
A_GRD_DISC=$(grep -c -e "r1394_dispatch_guard" "$DISC" | tr -d " ")
A_GRD_RS=$(grep -c -e "r1394_postemit_guard" "$RS" | tr -d " ")
A_OVLINT=$(grep -c -e "ovlint" "$SRC" | tr -d " ")
echo "interp refs runtime.c: expect $E_INT got $A_INT_TOT"
echo "guard refs runtime.c: expect 1 got $A_GRD_RT (def)"
echo "guard refs header: expect 1 got $A_GRD_HDR (proto)"
echo "guard refs disc1.c: expect 1 got $A_GRD_DISC (splice)"
echo "patcher refs run.sh: expect 1 got $A_GRD_RS (the call line)"
echo "ovlint receipt sites: $A_OVLINT"
echo "the disc1.c splice line: $(sed -n "$((INS+1))p" "$DISC")"
if [ "$A_INT_TOT" != "$E_INT" ] || [ "$A_GRD_RT" != "1" ] || [ "$A_GRD_HDR" != "1" ] || [ "$A_GRD_DISC" != "1" ] || [ "$A_GRD_RS" != "1" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c504 files"
  cp -p "$SRC.pre_c504" "$SRC"; cp -p "$HDR.pre_c504" "$HDR"; cp -p "$DISC.pre_c504" "$DISC"; cp -p "$RS.pre_c504" "$RS"
  exit 0
fi
echo "GATES OK"
echo "NEW_TREE_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)"
echo "NEW_HDR_SHA=$(shasum -a 256 "$HDR" | cut -d" " -f1)"
echo "NEW_DISC_SHA=$(shasum -a 256 "$DISC" | cut -d" " -f1)"
echo "===SYNCHK504=== HARD GATE syntax check (unpiped rc) on runtime.c + disc1.c (mirrors the build cc line)"
cc -fsyntax-only "$SRC" > /tmp/c504_syn.txt 2>&1
SYN_RC=$?
head -8 /tmp/c504_syn.txt
echo "runtime.c SYNCHK_RC=$SYN_RC"
cc -fsyntax-only -Iruntime -Werror=implicit-function-declaration "$DISC" > /tmp/c504_syn2.txt 2>&1
SYN_RC2=$?
head -8 /tmp/c504_syn2.txt
echo "disc1.c SYNCHK_RC=$SYN_RC2"
if [ "$SYN_RC" != "0" ] || [ "$SYN_RC2" != "0" ]; then
  echo "VALID-FAILED: a patched file does not parse - RESTORING the pre-c504 files"
  cp -p "$SRC.pre_c504" "$SRC"; cp -p "$HDR.pre_c504" "$HDR"; cp -p "$DISC.pre_c504" "$DISC"; cp -p "$RS.pre_c504" "$RS"
  exit 0
fi
echo "SYNCHK OK (both files)"
echo "===RUN504=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh > /tmp/c504_run.txt 2>&1
echo "RUN_RC=$?"
grep -n -e "R1394" -e "R323" /tmp/c504_run.txt | head -8
tail -30 /tmp/c504_run.txt
echo "===DIGEST504==="
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "--- the [ovlint] receipts (the interpreter):"
grep -c -e "ovlint" "$LOG" | tr -d " " | sed "s/^/ovlint count: /"
grep -n -e "ovlint" "$LOG" | head -30
echo "--- the [ovlstop] receipts (the fail-safe):"
grep -n -e "ovlstop" "$LOG" | head -8
echo "--- the capture:"
ls -la ovlstop_capture.bin 2>/dev/null
echo "--- the ladder + the death receipt:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -4
grep -n -e "wildctx" "$LOG" | head -3
grep -n -e "fvp" "$LOG" | tail -3
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- tree + disc sha at run time:"
shasum -a 256 "$SRC" | cut -d" " -f1
shasum -a 256 "$DISC" | cut -d" " -f1
echo "===C504DONE=== PASS = [ovlint] entries + either forward execution or an honest named-stop receipt - digest is pure ASCII"
