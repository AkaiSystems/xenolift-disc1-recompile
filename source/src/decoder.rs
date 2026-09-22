//! MIPS I (R3000A) instruction decoder for the PS1.
//!
//! Words are decoded little-endian (PS-X EXE storage order).
//! COP2 (GTE) opcodes are captured raw as `CopUnknown` — they must NOT be
//! translated 1:1; phase 2 replaces them with software math wrappers.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Inst {
    Nop,
    // shifts
    Sll { rd: u8, rt: u8, sa: u8 },
    Srl { rd: u8, rt: u8, sa: u8 },
    Sra { rd: u8, rt: u8, sa: u8 },
    Sllv { rd: u8, rt: u8, rs: u8 },
    Srlv { rd: u8, rt: u8, rs: u8 },
    Srav { rd: u8, rt: u8, rs: u8 },
    // jumps
    Jr { rs: u8 },
    Jalr { rd: u8, rs: u8 },
    // system
    Syscall,
    Break(u32),
    // hi/lo
    Mfhi { rd: u8 },
    Mthi { rs: u8 },
    Mflo { rd: u8 },
    Mtlo { rs: u8 },
    Mult { rs: u8, rt: u8 },
    Multu { rs: u8, rt: u8 },
    Div { rs: u8, rt: u8 },
    Divu { rs: u8, rt: u8 },
    // ALU
    Add { rs: u8, rt: u8, rd: u8 },
    Addu { rs: u8, rt: u8, rd: u8 },
    Sub { rs: u8, rt: u8, rd: u8 },
    Subu { rs: u8, rt: u8, rd: u8 },
    And { rs: u8, rt: u8, rd: u8 },
    Or { rs: u8, rt: u8, rd: u8 },
    Xor { rs: u8, rt: u8, rd: u8 },
    Nor { rs: u8, rt: u8, rd: u8 },
    Slt { rs: u8, rt: u8, rd: u8 },
    Sltu { rs: u8, rt: u8, rd: u8 },
    // conditional branches
    Bltz { rs: u8, imm: i16 },
    Bgez { rs: u8, imm: i16 },
    Bltzal { rs: u8, imm: i16 },
    Bgezal { rs: u8, imm: i16 },
    Beq { rs: u8, rt: u8, imm: i16 },
    Bne { rs: u8, rt: u8, imm: i16 },
    Blez { rs: u8, imm: i16 },
    Bgtz { rs: u8, imm: i16 },
    // jumps with absolute target
    J { target: u32 },
    Jal { target: u32 },
    // immediates
    Addi { rs: u8, rt: u8, imm: i16 },
    Addiu { rs: u8, rt: u8, imm: i16 },
    Slti { rs: u8, rt: u8, imm: i16 },
    Sltiu { rs: u8, rt: u8, imm: u16 },
    Andi { rs: u8, rt: u8, imm: u16 },
    Ori { rs: u8, rt: u8, imm: u16 },
    Xori { rs: u8, rt: u8, imm: u16 },
    Lui { rt: u8, imm: u16 },
    // memory
    Lb { rs: u8, rt: u8, imm: i16 },
    Lh { rs: u8, rt: u8, imm: i16 },
    Lw { rs: u8, rt: u8, imm: i16 },
    Lbu { rs: u8, rt: u8, imm: i16 },
    Lhu { rs: u8, rt: u8, imm: i16 },
    Sb { rs: u8, rt: u8, imm: i16 },
    Sh { rs: u8, rt: u8, imm: i16 },
    Sw { rs: u8, rt: u8, imm: i16 },
    // unaligned/partial word accesses (compilers use these for struct copies)
    Lwl { rs: u8, rt: u8, imm: i16 },
    Lwr { rs: u8, rt: u8, imm: i16 },
    Swl { rs: u8, rt: u8, imm: i16 },
    Swr { rs: u8, rt: u8, imm: i16 },
    // COP0/1/2 (incl. GTE) — raw word retained for phase-2 analysis
    CopUnknown { word: u32 },
    Unknown { word: u32 },
}

#[inline]
fn sext(imm: i16) -> i32 {
    imm as i32
}

pub fn decode(w: u32) -> Inst {
    let op = ((w >> 26) & 0x3F) as u8;
    let rs = ((w >> 21) & 0x1F) as u8;
    let rt = ((w >> 16) & 0x1F) as u8;
    let rd = ((w >> 11) & 0x1F) as u8;
    let sa = ((w >> 6) & 0x1F) as u8;
    let funct = (w & 0x3F) as u8;
    let imm = (w & 0xFFFF) as u16;
    let simm = imm as i16;
    let target = w & 0x03FF_FFFF;

    match op {
        0x00 => match funct {
            0x00 => {
                if w == 0 {
                    Inst::Nop
                } else {
                    Inst::Sll { rd, rt, sa }
                }
            }
            0x02 => Inst::Srl { rd, rt, sa },
            0x03 => Inst::Sra { rd, rt, sa },
            0x04 => Inst::Sllv { rd, rt, rs },
            0x06 => Inst::Srlv { rd, rt, rs },
            0x07 => Inst::Srav { rd, rt, rs },
            0x08 => Inst::Jr { rs },
            0x09 => Inst::Jalr { rd, rs },
            0x0C => Inst::Syscall,
            0x0D => Inst::Break((w >> 6) & 0xFFFFF),
            0x10 => Inst::Mfhi { rd },
            0x11 => Inst::Mthi { rs },
            0x12 => Inst::Mflo { rd },
            0x13 => Inst::Mtlo { rs },
            0x18 => Inst::Mult { rs, rt },
            0x19 => Inst::Multu { rs, rt },
            0x1A => Inst::Div { rs, rt },
            0x1B => Inst::Divu { rs, rt },
            0x20 => Inst::Add { rs, rt, rd },
            0x21 => Inst::Addu { rs, rt, rd },
            0x22 => Inst::Sub { rs, rt, rd },
            0x23 => Inst::Subu { rs, rt, rd },
            0x24 => Inst::And { rs, rt, rd },
            0x25 => Inst::Or { rs, rt, rd },
            0x26 => Inst::Xor { rs, rt, rd },
            0x27 => Inst::Nor { rs, rt, rd },
            0x2A => Inst::Slt { rs, rt, rd },
            0x2B => Inst::Sltu { rs, rt, rd },
            _ => Inst::Unknown { word: w },
        },
        0x01 => match rt {
            0x00 => Inst::Bltz { rs, imm: simm },
            0x01 => Inst::Bgez { rs, imm: simm },
            0x10 => Inst::Bltzal { rs, imm: simm },
            0x11 => Inst::Bgezal { rs, imm: simm },
            _ => Inst::Unknown { word: w },
        },
        0x02 => Inst::J { target },
        0x03 => Inst::Jal { target },
        0x04 => Inst::Beq { rs, rt, imm: simm },
        0x05 => Inst::Bne { rs, rt, imm: simm },
        0x06 => Inst::Blez { rs, imm: simm },
        0x07 => Inst::Bgtz { rs, imm: simm },
        0x08 => Inst::Addi { rs, rt, imm: simm },
        0x09 => Inst::Addiu { rs, rt, imm: simm },
        0x0A => Inst::Slti { rs, rt, imm: simm },
        0x0B => Inst::Sltiu { rs, rt, imm },
        0x0C => Inst::Andi { rs, rt, imm },
        0x0D => Inst::Ori { rs, rt, imm },
        0x0E => Inst::Xori { rs, rt, imm },
        0x0F => Inst::Lui { rt, imm },
        0x20 => Inst::Lb { rs, rt, imm: simm },
        0x21 => Inst::Lh { rs, rt, imm: simm },
        0x23 => Inst::Lw { rs, rt, imm: simm },
        0x24 => Inst::Lbu { rs, rt, imm: simm },
        0x25 => Inst::Lhu { rs, rt, imm: simm },
        0x22 => Inst::Lwl { rs, rt, imm: simm },
        0x26 => Inst::Lwr { rs, rt, imm: simm },
        0x28 => Inst::Sb { rs, rt, imm: simm },
        0x29 => Inst::Sh { rs, rt, imm: simm },
        0x2A => Inst::Swl { rs, rt, imm: simm },
        0x2B => Inst::Sw { rs, rt, imm: simm },
        0x2E => Inst::Swr { rs, rt, imm: simm },
        // COP0 (0x10), COP1 (0x11), COP2/GTE (0x12) — needs phase-2 mapping
        0x10 | 0x11 | 0x12 => Inst::CopUnknown { word: w },
        // LWC2 (0x32) / SWC2 (0x3A) — GTE vector/matrix data transfers
        0x32 | 0x3A => Inst::CopUnknown { word: w },
        _ => Inst::Unknown { word: w },
    }
}

/// Conditional branches (delay slot follows).
pub fn is_branch(i: &Inst) -> bool {
    matches!(
        i,
        Inst::Beq { .. }
            | Inst::Bne { .. }
            | Inst::Blez { .. }
            | Inst::Bgtz { .. }
            | Inst::Bltz { .. }
            | Inst::Bgez { .. }
            | Inst::Bltzal { .. }
            | Inst::Bgezal { .. }
    )
}

/// Unconditional jumps (delay slot follows).
pub fn is_jump(i: &Inst) -> bool {
    matches!(i, Inst::J { .. } | Inst::Jal { .. } | Inst::Jr { .. } | Inst::Jalr { .. })
}

pub fn is_control_flow(i: &Inst) -> bool {
    is_branch(i) || is_jump(i) || matches!(i, Inst::Syscall | Inst::Break(_))
}

/// Branch target = pc + 4 + (sign_ext(imm) << 2)
#[inline]
pub fn branch_target(pc: u32, imm: i16) -> u32 {
    pc.wrapping_add(4).wrapping_add((sext(imm) << 2) as u32)
}

/// Jump target = (pc+4 region) | (index << 2)
#[inline]
pub fn jump_target(pc: u32, target: u32) -> u32 {
    (pc.wrapping_add(4) & 0xF000_0000) | (target << 2)
}
