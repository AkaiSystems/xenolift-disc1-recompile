//! Phase-2 C emitter: per-function emission.
//!
//! Each discovered function entry becomes its own C function:
//!   xenolift_fn_80019524(void) { ... }
//! Calls (jal) become real C calls; returns (jr $ra) become `return`;
//! jumps and branches stay `goto` when their target is inside the same
//! function, and otherwise transfer through the generated dispatcher
//! (nesting call model — exact semantics; trampoline optimization is a
//! later phase).
//!
//! Chunk splitting: if some control transfer must land on an address that
//! is in the middle of another function, that function is SPLIT into two
//! C functions at that address, so every dispatch target is a function
//! start. The split parts chain via tail calls.
//!
//! Correctness rules:
//!  1. Branch delay slots execute after the branch decision, before the
//!     transfer — condition/target/link computed into temps first.
//!  2. r[0] is hardwired zero; writes elided.
//!  3. Only reachable code (from discovery) is translated.
//!  4. Every consumed delay slot still gets a label in case something
//!     branches to it.

use crate::decoder::{self, Inst};
use std::collections::{BTreeMap, BTreeSet};

/// Emit a register write, eliding writes to the hardwired-zero register $0.
macro_rules! set {
    ($o:expr, $d:expr, $val:expr) => {
        if *$d != 0 {
            $o.push_str(&format!("r[{}] = {};\n", $d, $val));
        }
    };
}

/// signed 16-bit immediate, rendered exactly (handles negatives)
macro_rules! simm {
    ($i:expr) => {
        format!("(int32_t)(int16_t)0x{:04X}", (*$i) as u16)
    };
}

/// unsigned 16-bit immediate (zero-extended)
macro_rules! zimm {
    ($i:expr) => {
        format!("0x{:04X}u", $i)
    };
}

fn addr(rs: u8, imm: i16) -> String {
    format!("r[{}] + (int32_t)(int16_t)0x{:04X}", rs, imm as u16)
}

/// where execution continues AFTER this instruction, ignoring the taken
/// branch path: the next word for plain instructions, past the delay slot
/// for conditional branches and calls. Jumps/returns never fall through.
fn fallthrough_of(ins: &Inst, pc: u32) -> Option<u32> {
    if !decoder::is_control_flow(ins) {
        return Some(pc.wrapping_add(4));
    }
    match ins {
        Inst::Beq { .. } | Inst::Bne { .. } | Inst::Blez { .. } | Inst::Bgtz { .. }
        | Inst::Bltz { .. } | Inst::Bgez { .. } | Inst::Bltzal { .. } | Inst::Bgezal { .. }
        | Inst::Jal { .. } | Inst::Jalr { .. } => Some(pc.wrapping_add(8)),
        _ => None,
    }
}

/// statically-known target of a control transfer (None for indirect jr/jalr)
fn static_target(ins: &Inst, pc: u32) -> Option<u32> {
    match ins {
        Inst::J { target } | Inst::Jal { target } => Some(decoder::jump_target(pc, *target)),
        Inst::Beq { imm, .. }
        | Inst::Bne { imm, .. }
        | Inst::Blez { imm, .. }
        | Inst::Bgtz { imm, .. }
        | Inst::Bltz { imm, .. }
        | Inst::Bgez { imm, .. }
        | Inst::Bltzal { imm, .. }
        | Inst::Bgezal { imm, .. } => Some(decoder::branch_target(pc, *imm)),
        _ => None,
    }
}

/// Emit a non-control-flow instruction as C.
pub fn emit_plain(o: &mut String, ins: &Inst) {
    use Inst::*;
    match ins {
        Nop => o.push_str("/* nop */\n"),
        Sll { rd, rt, sa } => set!(o, rd, format!("r[{}] << {}", rt, sa)),
        Srl { rd, rt, sa } => set!(o, rd, format!("r[{}] >> {}", rt, sa)),
        Sra { rd, rt, sa } => set!(
            o,
            rd,
            format!("(uint32_t)((int32_t)r[{}] >> {})", rt, sa)
        ),
        Sllv { rd, rt, rs } => set!(o, rd, format!("r[{}] << (r[{}] & 31u)", rt, rs)),
        Srlv { rd, rt, rs } => set!(o, rd, format!("r[{}] >> (r[{}] & 31u)", rt, rs)),
        Srav { rd, rt, rs } => set!(
            o,
            rd,
            format!("(uint32_t)((int32_t)r[{}] >> (r[{}] & 31u))", rt, rs)
        ),
        Mfhi { rd } => set!(o, rd, "hi".to_string()),
        Mflo { rd } => set!(o, rd, "lo".to_string()),
        Mthi { rs } => o.push_str(&format!("hi = r[{}];\n", rs)),
        Mtlo { rs } => o.push_str(&format!("lo = r[{}];\n", rs)),
        Mult { rs, rt } => o.push_str(&format!(
            "{{ int64_t __p = (int64_t)(int32_t)r[{}] * (int64_t)(int32_t)r[{}];\nlo = (uint32_t)__p; hi = (uint32_t)((uint64_t)__p >> 32); }}\n",
            rs, rt
        )),
        Multu { rs, rt } => o.push_str(&format!(
            "{{ uint64_t __p = (uint64_t)r[{}] * (uint64_t)r[{}];\nlo = (uint32_t)__p; hi = (uint32_t)(__p >> 32); }}\n",
            rs, rt
        )),
        Div { rs, rt } => o.push_str(&format!(
            "if (r[{1}] != 0u) {{ int32_t __a = (int32_t)r[{0}]; int32_t __b = (int32_t)r[{1}]; lo = (uint32_t)(int32_t)(__a / __b); hi = (uint32_t)(int32_t)(__a % __b); }} /* TODO: INT_MIN/-1 */\n",
            rs, rt
        )),
        Divu { rs, rt } => o.push_str(&format!(
            "if (r[{1}] != 0u) {{ lo = r[{0}] / r[{1}]; hi = r[{0}] % r[{1}]; }}\n",
            rs, rt
        )),
        Add { rs, rt, rd } => set!(o, rd, format!("r[{}] + r[{}]", rs, rt)), // phase 1: no overflow trap
        Addu { rs, rt, rd } => set!(o, rd, format!("r[{}] + r[{}]", rs, rt)),
        Sub { rs, rt, rd } => set!(o, rd, format!("r[{}] - r[{}]", rs, rt)),
        Subu { rs, rt, rd } => set!(o, rd, format!("r[{}] - r[{}]", rs, rt)),
        And { rs, rt, rd } => set!(o, rd, format!("r[{}] & r[{}]", rs, rt)),
        Or { rs, rt, rd } => set!(o, rd, format!("r[{}] | r[{}]", rs, rt)),
        Xor { rs, rt, rd } => set!(o, rd, format!("r[{}] ^ r[{}]", rs, rt)),
        Nor { rs, rt, rd } => set!(o, rd, format!("~(r[{}] | r[{}])", rs, rt)),
        Slt { rs, rt, rd } => set!(
            o,
            rd,
            format!("((int32_t)r[{}] < (int32_t)r[{}] ? 1u : 0u)", rs, rt)
        ),
        Sltu { rs, rt, rd } => set!(o, rd, format!("(r[{}] < r[{}] ? 1u : 0u)", rs, rt)),
        Addi { rs, rt, imm } => set!(o, rt, format!("r[{}] + {}", rs, simm!(imm))), // phase 1: no overflow trap
        Addiu { rs, rt, imm } => set!(o, rt, format!("r[{}] + {}", rs, simm!(imm))),
        Slti { rs, rt, imm } => set!(
            o,
            rt,
            format!("((int32_t)r[{}] < {} ? 1u : 0u)", rs, simm!(imm))
        ),
        Sltiu { rs, rt, imm } => set!(
            o,
            rt,
            format!(
                "(r[{}] < (uint32_t)(int32_t)(int16_t)0x{:04X} ? 1u : 0u)",
                rs, *imm
            )
        ),
        Andi { rs, rt, imm } => set!(o, rt, format!("r[{}] & {}", rs, zimm!(imm))),
        Ori { rs, rt, imm } => set!(o, rt, format!("r[{}] | {}", rs, zimm!(imm))),
        Xori { rs, rt, imm } => set!(o, rt, format!("r[{}] ^ {}", rs, zimm!(imm))),
        Lui { rt, imm } => {
            if *rt != 0 {
                o.push_str(&format!("r[{}] = {} << 16;\n", rt, zimm!(imm)));
            }
        }
        Lb { rs, rt, imm } => set!(
            o,
            rt,
            format!("(uint32_t)(int32_t)(int8_t)LB({})", addr(*rs, *imm))
        ),
        Lh { rs, rt, imm } => set!(
            o,
            rt,
            format!("(uint32_t)(int32_t)(int16_t)LH({})", addr(*rs, *imm))
        ),
        Lbu { rs, rt, imm } => set!(o, rt, format!("LBU({})", addr(*rs, *imm))),
        Lhu { rs, rt, imm } => set!(o, rt, format!("LHU({})", addr(*rs, *imm))),
        Lw { rs, rt, imm } => {
            if *rt != 0 {
                o.push_str(&format!("r[{}] = LW({});\n", rt, addr(*rs, *imm)));
            } else {
                o.push_str(&format!("LW({}); /* load to $0 */\n", addr(*rs, *imm)));
            }
        }
        Sw { rs, rt, imm } => o.push_str(&format!("SW({}, r[{}]);\n", addr(*rs, *imm), rt)),
        Sb { rs, rt, imm } => o.push_str(&format!("SB({}, r[{}]);\n", addr(*rs, *imm), rt)),
        Sh { rs, rt, imm } => o.push_str(&format!("SH({}, r[{}]);\n", addr(*rs, *imm), rt)),
        Lwl { rs, rt, imm } => set!(o, rt, format!("LWL({}, r[{}])", addr(*rs, *imm), rt)),
        Lwr { rs, rt, imm } => set!(o, rt, format!("LWR({}, r[{}])", addr(*rs, *imm), rt)),
        Swl { rs, rt, imm } => o.push_str(&format!("SWL({}, r[{}]);\n", addr(*rs, *imm), rt)),
        Swr { rs, rt, imm } => o.push_str(&format!("SWR({}, r[{}]);\n", addr(*rs, *imm), rt)),
        CopUnknown { word } => o.push_str(&format!(
            "xenolift_cop_stub(0x{:08X}); /* TODO: GTE mapping */\n",
            word
        )),
        Unknown { word } => {
            o.push_str(&format!("xenolift_unknown(0x{:08X});\n", word));
        }
        _ => unreachable!("control-flow handled by caller"),
    }
}

/// Translate reachable code to per-function C.
// R93: symbol map — annotations from the OpokXeno/xenogears-recomp
// project (annotations.csv, shipped with the tool) name every function
// in this exact binary. Names flow into emitted labels so the C, logs
// and backtraces read like the real kernel — extraction-ready docs.
pub static SYMBOLS: std::sync::OnceLock<std::collections::BTreeMap<u32, String>> =
    std::sync::OnceLock::new();

pub fn set_symbols(m: std::collections::BTreeMap<u32, String>) {
    let _ = SYMBOLS.set(m);
}

fn fn_label(a: u32) -> String {
    if let Some(n) = SYMBOLS.get().and_then(|m| m.get(&a)) {
        let clean: String = n
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() || c == '_' { c } else { '_' })
            .collect();
        if !clean.is_empty() {
            return format!("xenolift_fn_{:08X}_{}", a, clean);
        }
    }
    format!("xenolift_fn_{:08X}", a)
}

pub fn emit(
    base: u32,
    insts: &[Inst],
    visited: &BTreeSet<u32>,
    functions: &BTreeSet<u32>,
    jr_targets: &BTreeMap<u32, u32>,
    entry: u32,
) -> String {
    let idx = |a: u32| ((a - base) / 4) as usize;

    // ---- 1. chunk starts: every function entry, plus split points ----
    let mut starts: BTreeSet<u32> = functions.clone();
    // statically-resolved indirect jumps (e.g. the boot stub's `jr $ra` to
    // the kernel entry) land on real code — make those addresses entries
    for t in jr_targets.values() {
        if visited.contains(t) {
            starts.insert(*t);
        }
    }
    if let Some(&v0) = visited.first() {
        if starts.first().map_or(true, |&s| v0 < s) {
            starts.insert(v0);
        }
    }
    // split until no cross-chunk transfer lands mid-function
    loop {
        let mut changed = false;
        for &pc in visited.iter() {
            let ins = insts[idx(pc)];
            if let Some(t) = static_target(&ins, pc) {
                if visited.contains(&t) && !starts.contains(&t) {
                    let owner_t = starts.range(..=t).next_back().copied();
                    let owner_pc = starts.range(..=pc).next_back().copied();
                    if owner_t != owner_pc {
                        starts.insert(t);
                        changed = true;
                    }
                }
            }
            // fallthrough edges: flow continuing straight into another
            // chunk needs a callable entry at the landing address
            if let Some(c) = fallthrough_of(&ins, pc) {
                if visited.contains(&c) && !starts.contains(&c) {
                    let owner_c = starts.range(..=c).next_back().copied();
                    let owner_pc = starts.range(..=pc).next_back().copied();
                    if owner_c != owner_pc {
                        starts.insert(c);
                        changed = true;
                    }
                }
            }
        }
        if !changed {
            break;
        }
    }

    // ---- 2. assign reachable words to their chunk ----
    let mut chunks: BTreeMap<u32, Vec<u32>> = BTreeMap::new();
    for &pc in visited.iter() {
        let start = starts.range(..=pc).next_back().copied().unwrap_or(base);
        chunks.entry(start).or_default().push(pc);
    }

    // ---- 3. emit ----
    let mut o = String::with_capacity(visited.len() * 64);
    o.push_str("// Generated by xenolift. DO NOT EDIT.\n");
    o.push_str("// One C function per discovered function entry (plus split points).\n");
    o.push_str(&format!(
        "// region 0x{:08X}..0x{:08X}, {} translated functions/chunks\n\n",
        base,
        base + (insts.len() as u32) * 4,
        chunks.len()
    ));
    o.push_str("#include \"xenolift_runtime.h\"\n\n");

    // forward declarations
    for &s in &starts {
        o.push_str(&format!("static void {}(void);\n", fn_label(s)));
    }
    o.push('\n');

    // entry point
    o.push_str("void xenolift_region(void)\n{\n");
    if starts.contains(&entry) {
        o.push_str(&format!("{}();\n", fn_label(entry)));
    } else {
        o.push_str(&format!("xenolift_dispatch(0x{:08X});\n", entry));
    }
    o.push_str("}\n");

    // function bodies
    for (&start, words) in &chunks {
        let kind = if functions.contains(&start) {
            "function"
        } else {
            "split chunk"
        };
        o.push_str(&format!(
            "\n/* ---------- 0x{:08X} ({}) ---------- */\n",
            start, kind
        ));
        o.push_str(&format!("static void {}(void)\n{{\n", fn_label(start)));
        o.push_str(&format!("XTRACE(0x{:08X});\n", start));
        emit_body(&mut o, base, insts, &starts, words, jr_targets, visited);
        o.push_str("}\n");
    }

    // generated dispatcher: chunk starts are the only resolvable targets;
    // anything else means an unresolved indirect jump (reported at runtime)
    o.push_str("\nvoid xenolift_dispatch(uint32_t pc)\n{\n");
    // the three BIOS call gates (see xenolift_bios_gate): intercept before
    // the chunk switch — 0xA0/0xB0/0xC0 are service numbers in r9
    o.push_str("    if (pc == 0xA0u || pc == 0xB0u || pc == 0xC0u) {\n");
    o.push_str("        xenolift_bios_gate(pc, r[9]);\n");
    o.push_str("        return;\n");
    o.push_str("    }\n");
    o.push_str("    switch (pc) {\n");
    for &s in &starts {
        o.push_str(&format!(
            "    case 0x{:08X}u: {}(); return;\n",
            s, fn_label(s)
        ));
    }
    o.push_str("    default: xenolift_unknown(pc); return; /* unresolved indirect target */\n");
    o.push_str("    }\n}\n");

    o
}

/// emit one chunk body; `words` are its addresses in order
fn emit_body(
    o: &mut String,
    base: u32,
    insts: &[Inst],
    starts: &BTreeSet<u32>,
    words: &[u32],
    jr_targets: &BTreeMap<u32, u32>,
    visited: &BTreeSet<u32>,
) {
    let idx = |a: u32| ((a - base) / 4) as usize;
    let own: BTreeSet<u32> = words.iter().copied().collect();
    let n = words.len();
    let mut i = 0usize;

    while i < n {
        let pc = words[i];
        let ins = insts[idx(pc)];

        // data gap marker within the chunk
        if i > 0 && words[i - 1] != pc.wrapping_sub(4) {
            o.push_str("/* data gap: not translated */\n");
        }

        // every translated slot gets a label
        o.push_str(&format!("L_{:08X}:;\n", pc));

        if !decoder::is_control_flow(&ins) {
            emit_plain(o, &ins);
            // chunks only chain via calls: if flow continues straight into
            // another chunk, hand off explicitly
            let next = pc.wrapping_add(4);
            if !own.contains(&next) && visited.contains(&next) {
                o.push_str(&format!(
                    "{}(); /* fallthrough */\nreturn;\n",
                    fn_label(next)
                ));
            }
            i += 1;
            continue;
        }

        if matches!(ins, Inst::Syscall | Inst::Break(_)) {
            if matches!(ins, Inst::Syscall) {
                // syscall = "call the OS": the handler does its work and
                // execution CONTINUES at the next instruction — do not return
                o.push_str("xenolift_syscall();\n");
            } else if let Inst::Break(code) = ins {
                // R90: break = the kernel's SOFTWARE-INTERRUPT GATE. The
                // 0x8004C3xx farm is break-stub syscalls: shuffle args,
                // `break <svc>`, then interpret v0/v1. The handler services
                // it and execution continues at the next instruction.
                o.push_str(&format!("xenolift_break(0x{:X}u);\n", code));
            }
            i += 1;
            continue;
        }

        // ---- branch/jump unit with its delay slot ----
        let slot_pc = pc.wrapping_add(4);
        let slot_owned = own.contains(&slot_pc);
        let raw_slot = insts.get(idx(pc).wrapping_add(1)).copied().unwrap_or(Inst::Nop);
        let slot_is_cf = decoder::is_control_flow(&raw_slot);
        // R94 FIX: a plain delay-slot instruction must ALWAYS execute —
        // MIPS semantics: every path through the branch runs the slot.
        // When the slot address belongs to another chunk we used to NOP it,
        // silently dropping the instruction (this froze the sound-heap walk:
        // bne 0x80038F80's slot `a1 = v1` at 0x80038F84 was a chunk start).
        // Inlining is safe: the not-taken fallthrough continues at pc+8
        // (skipping the slot address), and any path dispatching INTO the
        // slot chunk executes it exactly once there. No double execution.
        let slot = if slot_is_cf {
            o.push_str("/* UNPREDICTABLE: control flow in delay slot, treated as nop */\n");
            Inst::Nop
        } else {
            raw_slot
        };
        // the slot gets an in-unit label only when we CONSUME it below
        let slot_label = slot_owned && !slot_is_cf;

        match ins {
            // ---- conditional branches ----
            Inst::Beq { rs, rt, imm } => br(o, "{rs} == {rt}", Some((rs, rt)), None, pc, imm, &own, starts, slot_label, &slot),
            Inst::Bne { rs, rt, imm } => br(o, "{rs} != {rt}", Some((rs, rt)), None, pc, imm, &own, starts, slot_label, &slot),
            Inst::Bltz { rs, imm } => br(o, "(int32_t){rs} < 0", Some((rs, 0)), None, pc, imm, &own, starts, slot_label, &slot),
            Inst::Bgez { rs, imm } => br(o, "(int32_t){rs} >= 0", Some((rs, 0)), None, pc, imm, &own, starts, slot_label, &slot),
            Inst::Blez { rs, imm } => br(o, "(int32_t){rs} <= 0", Some((rs, 0)), None, pc, imm, &own, starts, slot_label, &slot),
            Inst::Bgtz { rs, imm } => br(o, "(int32_t){rs} > 0", Some((rs, 0)), None, pc, imm, &own, starts, slot_label, &slot),
            Inst::Bltzal { rs, imm } => br(o, "(int32_t){rs} < 0", Some((rs, 0)), Some(pc.wrapping_add(8)), pc, imm, &own, starts, slot_label, &slot),
            Inst::Bgezal { rs, imm } => br(o, "(int32_t){rs} >= 0", Some((rs, 0)), Some(pc.wrapping_add(8)), pc, imm, &own, starts, slot_label, &slot),

            // ---- absolute jumps ----
            Inst::J { target } => {
                let t = decoder::jump_target(pc, target);
                o.push_str("{\n");
                emit_slot(o, &slot, slot_label, slot_pc);
                o.push_str(&transfer(&t, &own, starts, false, pc));
                o.push_str("}\n");
            }
            Inst::Jal { target } => {
                let t = decoder::jump_target(pc, target);
                o.push_str("{\n");
                o.push_str(&format!("r[31] = 0x{:08X};\n", pc.wrapping_add(8)));
                emit_slot(o, &slot, slot_label, slot_pc);
                if starts.contains(&t) {
                    o.push_str(&format!("{}();\n", fn_label(t))); // real call, returns here
                } else {
                    // external call: dispatch WITHOUT returning — when the
                    // callee finishes, execution continues right here
                    o.push_str(&format!(
                        "xenolift_dispatch(0x{:08X}); /* BIOS/external call: TODO HLE */\n",
                        t
                    ));
                }
                o.push_str("}\n");
            }

            // ---- register jumps ----
            Inst::Jr { rs } => {
                o.push_str("{\n");
                emit_slot(o, &slot, slot_label, slot_pc);
                if let Some(&t) = jr_targets.get(&pc) {
                    // statically-known target (e.g. boot stub's `jr $ra`
                    // with r31 precomputed) — a JUMP, not a return
                    o.push_str(&transfer(&t, &own, starts, false, pc));
                } else if rs == 31 {
                    o.push_str("return;\n"); // genuine function return
                } else {
                    o.push_str(&format!("DISPATCH(r[{}]);\n", rs));
                }
                o.push_str("}\n");
            }
            Inst::Jalr { rd, rs } => {
                o.push_str("{\n");
                if let Some(&t) = jr_targets.get(&pc) {
                    // statically-known call target — a real call
                    if rd != 0 {
                        o.push_str(&format!("r[{}] = 0x{:08X};\n", rd, pc.wrapping_add(8)));
                    }
                    emit_slot(o, &slot, slot_label, slot_pc);
                    if starts.contains(&t) {
                        o.push_str(&format!("{}();\n", fn_label(t)));
                    } else {
                        o.push_str(&format!("DISPATCH(0x{:08X}); /* external call: TODO HLE */\n", t));
                    }
                } else {
                    o.push_str(&format!("uint32_t __t = r[{}];\n", rs));
                    if rd != 0 {
                        o.push_str(&format!("r[{}] = 0x{:08X};\n", rd, pc.wrapping_add(8)));
                    }
                    emit_slot(o, &slot, slot_label, slot_pc);
                    // indirect CALL: dispatch without returning — when the
                    // callee returns, execution continues at pc+8, which is
                    // exactly the code following this unit
                    o.push_str("xenolift_dispatch(__t); /* indirect call */\n");
                }
                o.push_str("}\n");
            }
            _ => unreachable!(),
        }

        // fallthrough hand-off for the unit just emitted: the not-taken
        // path of a branch, or the code after a call returns. Taken paths
        // were emitted inside the unit; this covers flow continuing past it.
        if let Some(c) = fallthrough_of(&ins, pc) {
            if !own.contains(&c) && visited.contains(&c) {
                o.push_str(&format!(
                    "{}(); /* fallthrough */\nreturn;\n",
                    fn_label(c)
                ));
            }
        }

        // unit consumption: slot owned & normal => it was emitted above
        i += if slot_owned && !slot_is_cf { 2 } else { 1 };
    }
}

/// emit the delay slot code. The label is emitted ONLY for consumed slots
/// (owned, normal): if the slot is control flow it is processed as its own
/// unit right after (and gets its label there), so labeling it here too
/// would define the same C label twice.
fn emit_slot(o: &mut String, slot: &Inst, emit_label: bool, slot_pc: u32) {
    if emit_label {
        o.push_str(&format!("L_{:08X}:;\n", slot_pc));
    }
    emit_plain(o, slot);
}

/// the transfer after a J (unconditional): goto / tail call / dispatch
fn transfer(t: &u32, own: &BTreeSet<u32>, starts: &BTreeSet<u32>, as_branch: bool, cur: u32) -> String {
    let _ = as_branch;
    if own.contains(t) {
        if *t == cur {
            // self-jump block = IRQ-park ("j self"): on real HW this loop is
            // preempted by interrupt-driven machinery. Give the runtime its
            // preemption point every iteration.
            format!("xenolift_park_tick();\ngoto L_{:08X};\n", t)
        } else {
            format!("goto L_{:08X};\n", t)
        }
    } else if starts.contains(t) {
        format!("{}();\nreturn;\n", fn_label(*t))
    } else {
        format!("DISPATCH(0x{:08X});\n", t)
    }
}

/// conditional branch, delay-slot-correct, with link (bltzal/bgezal) support.
/// `regs` is (rs, rt) — rt=0 for the one-register forms (unused in the template).
#[allow(clippy::too_many_arguments)]
fn br(
    o: &mut String,
    cond: &str,
    regs: Option<(u8, u8)>,
    link: Option<u32>,
    pc: u32,
    imm: i16,
    own: &BTreeSet<u32>,
    starts: &BTreeSet<u32>,
    slot_label: bool,
    slot: &Inst,
) {
    let (rs, rt) = regs.unwrap_or((0, 0));
    let cond = cond
        .replace("{rs}", &format!("r[{}]", rs))
        .replace("{rt}", &format!("r[{}]", rt));
    let t = decoder::branch_target(pc, imm);

    o.push_str("{\n");
    if let Some(la) = link {
        o.push_str(&format!("r[31] = 0x{:08X};\n", la));
    }
    // condition evaluated BEFORE the delay slot clobbers any registers
    o.push_str(&format!("uint32_t __c = ({}) ? 1u : 0u;\n", cond));
    emit_slot(o, slot, slot_label, pc.wrapping_add(4));

    if own.contains(&t) {
        o.push_str(&format!("if (__c) goto L_{:08X};\n", t));
    } else if starts.contains(&t) {
        // branch into another function: tail-style transfer
        o.push_str(&format!("if (__c) {{ {}(); return; }}\n", fn_label(t)));
    } else {
        o.push_str(&format!("if (__c) DISPATCH(0x{:08X});\n", t));
    }
    o.push_str("}\n");
}
