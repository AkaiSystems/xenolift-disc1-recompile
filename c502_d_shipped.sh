#!/bin/bash
# c502_patch.sh - STAGE B-2 v1 RESHIP AT THE TRUE SITE: the
# R1394 module-window interpreter with the guard spliced at
# the HEAD of the LIVE TRAMPOLINE DISPATCHER. The c501
# probe receipted it: the dispatcher's definition lives in
# patches/ (r321_tramp.c / r322_tramp.c), NOT runtime.c -
# runtime.c's 61 references are all calls; the header only
# declares it. THIS SCRIPT: (1) receipts run.sh's tramp
# references + both tramp bodies, determines the LIVE tramp
# (explicit run.sh name first, active-definition test
# second, fail-closed); (2) PATCHES runtime.c with the R1394
# head (the guard now EXTERN - a separate TU) + the tail
# (the interpreter); (3) PATCHES the live tramp: the extern
# guard prototype at line 1 + the guard call after the
# definition's opening brace; (4) hard-gated unpiped syntax
# checks on BOTH files; build + the 190s verdict run +
# digest. The interpreter design is the c498-receipted,
# sandbox-functionally-proven c499/c500 set unchanged:
# jump OUT of the window tail-dispatches; jal OUT calls
# natively and RESUMES at the link address; GTE moves via
# the live HLE; the compute-op call extracted from the
# runtime's own COP2 region (content-anchored, strict,
# fail-closed); v1 limits: local hi/lo, COP0 unsupported,
# 4M budget, unhandled opcode -> the explicit [ovlstop].
# Fail-closed, tee'd to /tmp/c502_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C502-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c502_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="4342a7391696a99bdc7745ca697c9ec29ddcd3bf384ef5a2813d79644addcc9f"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c497 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c497 tree with the working guard)"
if grep -q "r1394_interp" "$SRC"; then echo "VALID-FAILED: R1394 already present - refusing (idempotent)"; exit 0; fi
echo "===LOCATE502=== the live trampoline dispatcher (from the c501 receipts)"
echo "--- run.sh tramp references + compile lines:"
grep -n -e "tramp" run.sh | head -8
grep -n -e "cc " run.sh | head -10
echo "--- patches/ contents:"
ls -la patches/ | head -12
echo "--- the tramp bodies (full, they are small):"
for TF in patches/r321_tramp.c patches/r322_tramp.c; do
  if [ -f "$TF" ]; then echo "===== $TF:"; cat "$TF"; fi
done
LIVE_TRAMP=""
NAMES=$(grep -o -e "r32[0-9]*_tramp.c" run.sh | sort -u)
if [ "$(printf "%s" "$NAMES" | grep -c .)" = "1" ]; then
  LIVE_TRAMP="patches/$(printf "%s" "$NAMES" | head -1)"
  echo "run.sh names exactly one tramp: $LIVE_TRAMP"
else
  echo "run.sh ambiguous or globbed - deciding by the active-definition test:"
  BEST=""
  for TF in patches/r322_tramp.c patches/r321_tramp.c; do
    if [ -f "$TF" ] && grep -q -e "void xenolift_dispatch" "$TF"; then
      GUARD=$(sed -n "1,8p" "$TF" | grep -c -e "#if" | tr -d " ")
      echo "  $TF: definition present, pre-guard-ifdefs=$GUARD"
      if [ "$BEST" = "" ] && [ "$GUARD" = "0" ]; then BEST="$TF"; fi
    fi
  done
  LIVE_TRAMP="$BEST"
  echo "active-definition pick: $LIVE_TRAMP"
fi
if [ -z "$LIVE_TRAMP" ] || [ ! -f "$LIVE_TRAMP" ]; then echo "VALID-FAILED: the live tramp could not be determined - refusing"; exit 0; fi
if grep -q -e "r1394_dispatch_guard" "$LIVE_TRAMP"; then echo "VALID-FAILED: the tramp already carries the guard - refusing (idempotent)"; exit 0; fi
DEF_LN=""
DEF_BRACE=""
for L in $(grep -n -e "void xenolift_dispatch" "$LIVE_TRAMP" | cut -d: -f1); do
  THIS=$(sed -n "${L}p" "$LIVE_TRAMP")
  case "$THIS" in *"{") if [ -z "$DEF_LN" ]; then DEF_LN=$L; DEF_BRACE=same; fi ;; esac
  NEXT=$(sed -n "$((L+1))p" "$LIVE_TRAMP")
  case "$NEXT" in *"{") if [ -z "$DEF_LN" ]; then DEF_LN=$L; DEF_BRACE=next; fi ;; esac
done
if [ -z "$DEF_LN" ]; then echo "VALID-FAILED: no brace-bearing definition in $LIVE_TRAMP - refusing"; exit 0; fi
DEF_LINE=$(sed -n "${DEF_LN}p" "$LIVE_TRAMP")
PN=$(printf "%s" "$DEF_LINE" | sed "s/.*xenolift_dispatch[ ]*(\([^)]*\)).*/\1/" | tr -d ")" | tr " " "\n" | grep -v -e "^uint32_t$" -e "^unsigned$" -e "^int$" -e "^const$" -e "^$" | head -1)
if [ -z "$PN" ]; then echo "VALID-FAILED: could not extract the dispatch param name from: $DEF_LINE"; exit 0; fi
echo "live tramp: $LIVE_TRAMP, definition at line $DEF_LN (brace on $DEF_BRACE line), param=[$PN]"
echo "===GTEEX502=== the runtime's own GTE compute-op call (from the COP2 region)"
COP2_LN=$(grep -n -e "the GTE, the PS1's 3D math chip" "$SRC" | head -1 | cut -d: -f1)
if [ -z "$COP2_LN" ]; then COP2_LN=$(grep -n -e "COP2" "$SRC" | head -1 | cut -d: -f1); fi
echo "the COP2 region anchored at line $COP2_LN"
GTE_CALL=$(sed -n "${COP2_LN},$((COP2_LN+260))p" "$SRC" | grep -o -e "hle_gte_[a-z_]*(w)" | sort -u | grep -v -e "hle_gte_read_data" -e "hle_gte_read_ctrl" -e "hle_gte_write_data" -e "hle_gte_write_ctrl" | head -1)
echo "GTE compute call candidate: [${GTE_CALL}]"
if [ -n "$GTE_CALL" ]; then echo "(wired: the interpreter calls the runtime's own GTE exec)"; else echo "(absent/ambiguous: the explicit unsupported-GTE stop ships; the census print names the wiring for v2)"; fi
sed -n "${COP2_LN},$((COP2_LN+260))p" "$SRC" | grep -n -e "hle_gte" | head -14
echo "===PATCH502=== runtime.c: head + tail; the live tramp: extern proto + the guard splice"
cat > /tmp/r1394_head.c <<'BLOCKEOF'
/* R1394 (c502): the module-window interpreter, stage B-2 v1. The dispatch
 * guard (EXTERN: the dispatcher lives in the trampoline TU) sits at the
 * HEAD of xenolift_dispatch in the live tramp file: it compares the live
 * module window against the emit-era reference (emit_ref.bin, the pSYW6z
 * window receipted at the fault addresses) and on mismatch INTERPRETS the
 * installed module's live bytes instead of running the unrelated emitted
 * translation. Full design notes + the v1 limits (local hi/lo, COP0
 * unsupported, 4M-instruction budget, explicit [ovlstop] fail-safe) are
 * in the definition at the end of this file. */
int r1394_dispatch_guard(unsigned int t);
BLOCKEOF
printf "%s" "$GTE_CALL" > /tmp/gte_call.txt
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
cp -p "$SRC" "$SRC.pre_c502"
cp -p "$LIVE_TRAMP" "$LIVE_TRAMP.pre_c502"
HLINES=$(wc -l < /tmp/r1394_head.c | tr -d " ")
{ cat /tmp/r1394_head.c; cat "$SRC"; } > /tmp/rt_p1.c
INS=$(( DEF_LN + 1 )); if [ "$DEF_BRACE" = "next" ]; then INS=$(( DEF_LN + 2 )); fi
awk -v L="$INS" -v PN="$PN" 'NR==L {print; print "    if (r1394_dispatch_guard(" PN ")) { return; }"; next} {print}' "$LIVE_TRAMP" > /tmp/tramp_new.c
{ printf "extern int r1394_dispatch_guard(unsigned int t);\n"; cat /tmp/tramp_new.c; } > /tmp/tramp_p2.c
mv /tmp/tramp_p2.c "$LIVE_TRAMP"
{ cat /tmp/rt_p1.c; cat /tmp/r1394_tail.c; } > /tmp/rt_new.c
mv /tmp/rt_new.c "$SRC"
echo "runtime.c: head + tail applied; tramp: extern proto + splice at line $((INS+1))"
echo "===GATES502==="
E_GRD=$(grep -c -e "r1394_dispatch_guard" /tmp/r1394_tail.c | tr -d " ")
A_GRD_RT=$(grep -c -e "r1394_dispatch_guard" "$SRC" | tr -d " ")
A_GRD_TR=$(grep -c -e "r1394_dispatch_guard" "$LIVE_TRAMP" | tr -d " ")
E_GRD=$((E_GRD + 1))
E_INT=$(grep -c -e "r1394_interp" /tmp/r1394_tail.c | tr -d " ")
E_INTH=$(grep -c -e "r1394_interp" /tmp/r1394_head.c | tr -d " ")
E_INT=$((E_INT + E_INTH))
A_INT_TOT=$(grep -c -e "r1394_interp" "$SRC" | tr -d " ")
A_OVLINT=$(grep -c -e "ovlint" "$SRC" | tr -d " ")
echo "guard refs runtime.c: expect $E_GRD got $A_GRD_RT (def+proto)"
echo "guard refs tramp: expect 2 got $A_GRD_TR (extern proto + splice)"
echo "interp refs: expect $E_INT got $A_INT_TOT"
echo "ovlint receipt sites: $A_OVLINT"
echo "the tramp splice line: $(sed -n "$((INS+1))p" "$LIVE_TRAMP")"
if [ "$A_GRD_RT" != "$E_GRD" ] || [ "$A_GRD_TR" != "2" ] || [ "$A_INT_TOT" != "$E_INT" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c502 tree + tramp"
  cp -p "$SRC.pre_c502" "$SRC"
  cp -p "$LIVE_TRAMP.pre_c502" "$LIVE_TRAMP"
  exit 0
fi
echo "GATES OK"
echo "NEW_TREE_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)"
echo "NEW_TRAMP_SHA=$(shasum -a 256 "$LIVE_TRAMP" | cut -d" " -f1)"
echo "===SYNCHK502=== HARD GATE syntax check (unpiped rc) on BOTH patched files"
cc -fsyntax-only "$SRC" > /tmp/c502_syn.txt 2>&1
SYN_RC=$?
head -8 /tmp/c502_syn.txt
echo "runtime.c SYNCHK_RC=$SYN_RC"
cc -fsyntax-only -I runtime -I . "$LIVE_TRAMP" > /tmp/c502_syn2.txt 2>&1
SYN_RC2=$?
head -8 /tmp/c502_syn2.txt
echo "tramp SYNCHK_RC=$SYN_RC2"
if [ "$SYN_RC" != "0" ] || [ "$SYN_RC2" != "0" ]; then
  echo "VALID-FAILED: a patched file does not parse - RESTORING the pre-c502 tree + tramp"
  cp -p "$SRC.pre_c502" "$SRC"
  cp -p "$LIVE_TRAMP.pre_c502" "$LIVE_TRAMP"
  exit 0
fi
echo "SYNCHK OK (both files)"
echo "===RUN502=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -30
echo "RUN_RC=$?"
echo "===DIGEST502==="
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
echo "--- tree + tramp sha at run time:"
shasum -a 256 "$SRC" | cut -d" " -f1
shasum -a 256 "$LIVE_TRAMP" | cut -d" " -f1
echo "===C502DONE=== PASS = [ovlint] entries + either forward execution or an honest named-stop receipt - digest is pure ASCII"
