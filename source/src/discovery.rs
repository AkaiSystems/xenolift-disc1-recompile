//! Function discovery: walk the code from the entry point and mark every
//! instruction address that is REACHABLE. Anything not marked is data.
//!
//! Method: a worklist of addresses to decode. From each address we decode
//! forward until a control-flow instruction; branches/jumps queue their
//! continuations (target, fallthrough, call target).
//!
//! Constant tracking: within each walk we follow simple register math
//! (lui/addiu/ori/addu-with-zero patterns), so when the code jumps through
//! a register (`jr $ra`, `jr $t0`) and we can prove what that register
//! holds, we follow it. This is what unlocks boot stubs and kernel init.
//! Registers loaded from memory stay unknown — a real jr through a vtable
//! is still a dead end (that needs table analysis, phase 2b).

use crate::decoder::{self, Inst};
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};

/// Returns (reachable instruction addresses, discovered function entries,
/// statically-resolved indirect jumps: pc -> target).
///
/// A jr/jalr whose target register holds a known constant is a JUMP to that
/// address, not a plain return — e.g. the boot stub computes r31 = 0x80029578
/// and jumps through it. The emitter needs these to keep the flow going.
/// (Limitation: const maps are per-walk; state merging across branch paths
/// is a later refinement.)
pub fn discover(
    base: u32,
    insts: &[Inst],
    entry: u32,
    extra: &BTreeSet<u32>,
) -> (BTreeSet<u32>, BTreeSet<u32>, BTreeMap<u32, u32>) {
    let end = base + (insts.len() as u32) * 4;
    let idx = |a: u32| ((a - base) / 4) as usize;
    let valid = |a: u32| a >= base && a < end && (a & 3) == 0;

    let mut visited: BTreeSet<u32> = BTreeSet::new();
    let mut functions: BTreeSet<u32> = BTreeSet::new();
    let mut jr_targets: BTreeMap<u32, u32> = BTreeMap::new();
    let mut q: VecDeque<u32> = VecDeque::new();

    if valid(entry) {
        q.push_back(entry);
        functions.insert(entry);
    } else {
        q.push_back(base);
        functions.insert(base);
    }

    // seeded entries from the data pointer scan (function-pointer tables)
    for &a in extra {
        if valid(a) {
            q.push_back(a);
            functions.insert(a);
        }
    }

    while let Some(mut a) = q.pop_front() {
        // register constants known along this walk (fresh per entry point)
        let mut consts: HashMap<u8, u32> = HashMap::new();
        loop {
            if !valid(a) || visited.contains(&a) {
                break;
            }
            visited.insert(a);
            let ins = insts[idx(a)];

            if !decoder::is_control_flow(&ins) {
                track_consts(&ins, &mut consts);
                a += 4;
                continue;
            }

            // control transfer: the delay slot belongs to this unit
            if valid(a + 4) {
                visited.insert(a + 4);
            }

            match ins {
                Inst::J { target } => {
                    // unconditional: only the target continues
                    q.push_back(decoder::jump_target(a, target));
                }
                Inst::Jal { target } => {
                    // call: the callee is a function; execution returns after
                    let t = decoder::jump_target(a, target);
                    if valid(t) {
                        functions.insert(t);
                    }
                    q.push_back(t);
                    q.push_back(a + 8);
                }
                Inst::Jr { rs } => {
                    // indirect jump — follow only if the register is a
                    // statically-known constant (e.g. boot stub `jr $ra`
                    // with r31 precomputed). Record it for the emitter.
                    if let Some(&t) = consts.get(&rs) {
                        jr_targets.insert(a, t);
                        q.push_back(t);
                    }
                }
                Inst::Jalr { rd: _, rs } => {
                    if let Some(&t) = consts.get(&rs) {
                        jr_targets.insert(a, t);
                        // R1192 (c480): a jalr to a statically-known constant
                        // is a CALL to that target. c480 receipts: the game's
                        // event pump (0x80041B24) jalr's 0x80041CA0 - a real
                        // target the walk visited and emitted as the mid-
                        // function label L_80041CA0 INSIDE fn_80041C68, but
                        // never registered as a function entry, so the
                        // generated dispatcher had no case and the runtime's
                        // unresolved-jump recovery killed the first epoch
                        // that completed the archive walk and was writing
                        // the game's main state table. Jal already inserts
                        // its target; jalr-to-constant is the same class.
                        functions.insert(t);
                        q.push_back(t);
                    }
                    q.push_back(a + 8);
                }
                Inst::Syscall | Inst::Break(_) => {
                    // the BIOS handler eventually returns to the caller
                    q.push_back(a + 4);
                }
                _ => {
                    // conditional branch: both paths continue
                    q.push_back(branch_target_of(&ins, a));
                    q.push_back(a + 8);
                }
            }
            break; // unit ended; all continuations are queued
        }
    }

    (visited, functions, jr_targets)
}

fn branch_target_of(ins: &Inst, pc: u32) -> u32 {
    match ins {
        Inst::Beq { imm, .. }
        | Inst::Bne { imm, .. }
        | Inst::Blez { imm, .. }
        | Inst::Bgtz { imm, .. }
        | Inst::Bltz { imm, .. }
        | Inst::Bgez { imm, .. }
        | Inst::Bltzal { imm, .. }
        | Inst::Bgezal { imm, .. } => decoder::branch_target(pc, *imm),
        _ => pc,
    }
}

/// insert a known constant, never for the hardwired-zero register $0
fn put(c: &mut HashMap<u8, u32>, reg: u8, val: u32) {
    if reg != 0 {
        c.insert(reg, val);
    }
}

/// register written by an instruction (if any)
fn writes(ins: &Inst) -> Option<u8> {
    use Inst::*;
    Some(match *ins {
        Sll { rd, .. } | Srl { rd, .. } | Sra { rd, .. }
        | Sllv { rd, .. } | Srlv { rd, .. } | Srav { rd, .. } => rd,
        Mfhi { rd } | Mflo { rd } => rd,
        Add { rd, .. } | Addu { rd, .. } | Sub { rd, .. } | Subu { rd, .. }
        | And { rd, .. } | Or { rd, .. } | Xor { rd, .. } | Nor { rd, .. }
        | Slt { rd, .. } | Sltu { rd, .. } => rd,
        Addi { rt, .. } | Addiu { rt, .. } | Slti { rt, .. } | Sltiu { rt, .. }
        | Andi { rt, .. } | Ori { rt, .. } | Xori { rt, .. } | Lui { rt, .. } => rt,
        Lb { rt, .. } | Lh { rt, .. } | Lw { rt, .. } | Lbu { rt, .. }
        | Lhu { rt, .. } | Lwl { rt, .. } | Lwr { rt, .. } => rt,
        _ => return None,
    })
}

/// update the constant map across one instruction
fn track_consts(ins: &Inst, c: &mut HashMap<u8, u32>) {
    use Inst::*;
    match *ins {
        Lui { rt, imm } => put(c, rt, (imm as u32) << 16),

        Addi { rs, rt, imm } | Addiu { rs, rt, imm } => {
            if let Some(&v) = c.get(&rs) {
                put(c, rt, v.wrapping_add((imm as i32) as u32));
            } else {
                c.remove(&rt);
            }
        }
        Andi { rs, rt, imm } => {
            if let Some(&v) = c.get(&rs) {
                put(c, rt, v & (imm as u32));
            } else {
                c.remove(&rt);
            }
        }
        Ori { rs, rt, imm } => {
            if let Some(&v) = c.get(&rs) {
                put(c, rt, v | (imm as u32));
            } else {
                c.remove(&rt);
            }
        }
        Xori { rs, rt, imm } => {
            if let Some(&v) = c.get(&rs) {
                put(c, rt, v ^ (imm as u32));
            } else {
                c.remove(&rt);
            }
        }
        Sll { rd, rt, sa } => {
            if let Some(&v) = c.get(&rt) {
                put(c, rd, v << (sa as u32));
            } else {
                c.remove(&rd);
            }
        }
        Srl { rd, rt, sa } => {
            if let Some(&v) = c.get(&rt) {
                put(c, rd, v >> (sa as u32));
            } else {
                c.remove(&rd);
            }
        }

        // three-register ALU ops: known if both operands are known
        // ($zero always reads as the constant 0, e.g. `addu $t, $s, $zero` = move)
        Add { rs, rt, rd } | Addu { rs, rt, rd } | Sub { rs, rt, rd } | Subu { rs, rt, rd }
        | And { rs, rt, rd } | Or { rs, rt, rd } | Xor { rs, rt, rd } | Nor { rs, rt, rd }
        | Slt { rs, rt, rd } | Sltu { rs, rt, rd } => {
            let a = if rs == 0 { Some(0) } else { c.get(&rs).copied() };
            let b = if rt == 0 { Some(0) } else { c.get(&rt).copied() };
            if let (Some(x), Some(y)) = (a, b) {
                let v = match ins {
                    Add { .. } | Addu { .. } => x.wrapping_add(y),
                    Sub { .. } | Subu { .. } => x.wrapping_sub(y),
                    And { .. } => x & y,
                    Or { .. } => x | y,
                    Xor { .. } => x ^ y,
                    Nor { .. } => !(x | y),
                    Slt { .. } => ((x as i32) < (y as i32)) as u32,
                    _ => (x < y) as u32,
                };
                put(c, rd, v);
            } else {
                c.remove(&rd);
            }
        }

        // anything else that writes a register makes it unknown
        _ => {
            if let Some(r) = writes(ins) {
                c.remove(&r);
            }
        }
    }
}
