#!/usr/bin/env python3
"""
mips_decode.py — MIPS I (R3000A) Crash-Dump Decoder
Dependency-free (Python stdlib only) disassembler for MIPS memory dumps.
"""

import sys
import re
import argparse

REG = [
    'zero', 'at', 'v0', 'v1', 'a0', 'a1', 'a2', 'a3',
    't0', 't1', 't2', 't3', 't4', 't5', 't6', 't7',
    's0', 's1', 's2', 's3', 's4', 's5', 's6', 's7',
    't8', 't9', 'k0', 'k1', 'gp', 'sp', 'fp', 'ra'
]

def s16(val: int) -> int:
    """Sign-extend 16-bit integer."""
    return val if val < 0x8000 else val - 0x10000

def decode_word(w: int, va: int) -> str:
    """Decode a 32-bit MIPS I instruction word at virtual address va."""
    if w == 0:
        return 'nop'

    op = (w >> 26) & 0x3F
    rs = (w >> 21) & 0x1F
    rt = (w >> 16) & 0x1F
    rd = (w >> 11) & 0x1F
    sa = (w >> 6) & 0x1F
    fn = w & 0x3F
    imm16 = w & 0xFFFF
    simm = s16(imm16)
    tgt = (va & 0xF0000000) | ((w & 0x03FFFFFF) << 2)

    if op == 0:
        # SPECIAL opcodes
        spec_map = {
            0: 'sll', 2: 'srl', 3: 'sra',
            4: 'sllv', 6: 'srlv', 7: 'srav',
            8: 'jr', 9: 'jalr',
            12: 'syscall', 13: 'break',
            16: 'mfhi', 17: 'mthi', 18: 'mflo', 19: 'mtlo',
            24: 'mult', 25: 'multu', 26: 'div', 27: 'divu',
            32: 'add', 33: 'addu', 34: 'sub', 35: 'subu',
            36: 'and', 37: 'or', 38: 'xor', 39: 'nor',
            42: 'slt', 43: 'sltu'
        }
        n = spec_map.get(fn)
        if n is None:
            return f'UNKNOWN (op=0x00, funct=0x{fn:02X})'
        if n in ('sll', 'srl', 'sra'):
            return f'{n} {REG[rd]}, {REG[rt]}, {sa}'
        if n in ('sllv', 'srlv', 'srav'):
            return f'{n} {REG[rd]}, {REG[rt]}, {REG[rs]}'
        if n == 'jr':
            return f'jr {REG[rs]}'
        if n == 'jalr':
            return f'jalr {REG[rd]}, {REG[rs]}'
        if n in ('syscall', 'break'):
            return n
        if n in ('mfhi', 'mflo'):
            return f'{n} {REG[rd]}'
        if n in ('mthi', 'mtlo'):
            return f'{n} {REG[rs]}'
        if n in ('mult', 'multu', 'div', 'divu'):
            return f'{n} {REG[rs]}, {REG[rt]}'
        return f'{n} {REG[rd]}, {REG[rs]}, {REG[rt]}'

    if op == 1:
        # REGIMM opcodes
        branch_target = va + 4 + simm * 4
        if rt == 0:
            return f'bltz {REG[rs]}, 0x{branch_target:08X}'
        if rt == 1:
            return f'bgez {REG[rs]}, 0x{branch_target:08X}'
        if rt == 0x10:
            return f'bltzal {REG[rs]}, 0x{branch_target:08X}'
        if rt == 0x11:
            return f'bgezal {REG[rs]}, 0x{branch_target:08X}'
        return f'UNKNOWN (op=0x01, rt=0x{rt:02X})'

    if op == 2:
        return f'j 0x{tgt:08X}'
    if op == 3:
        return f'jal 0x{tgt:08X}'

    branch_target = va + 4 + simm * 4
    if op == 4:
        return f'beq {REG[rs]}, {REG[rt]}, 0x{branch_target:08X}'
    if op == 5:
        return f'bne {REG[rs]}, {REG[rt]}, 0x{branch_target:08X}'
    if op == 6:
        return f'blez {REG[rs]}, 0x{branch_target:08X}'
    if op == 7:
        return f'bgtz {REG[rs]}, 0x{branch_target:08X}'

    imm_map = {
        8: 'addi', 9: 'addiu', 10: 'slti', 11: 'sltiu',
        12: 'andi', 13: 'ori', 14: 'xori'
    }
    if op in imm_map:
        if op in (12, 13, 14):
            val_str = f'0x{imm16:X}'
        else:
            val_str = str(simm)
        return f'{imm_map[op]} {REG[rt]}, {REG[rs]}, {val_str}'

    if op == 15:
        return f'lui {REG[rt]}, 0x{imm16:X}'

    mem_map = {
        32: 'lb', 33: 'lh', 34: 'lwl', 35: 'lw',
        36: 'lbu', 37: 'lhu', 38: 'lwr',
        40: 'sb', 41: 'sh', 42: 'swl', 43: 'sw', 46: 'swr'
    }
    if op in mem_map:
        return f'{mem_map[op]} {REG[rt]}, {simm}({REG[rs]})'

    if op == 0x10:
        if rs == 0:
            return f'mfc0 {REG[rt]}, c0_{rd}'
        if rs == 4:
            return f'mtc0 {REG[rt]}, c0_{rd}'
        if w & 0x02000000:
            cfn = {1: 'tlbr', 2: 'tlbwi', 6: 'tlbwr', 8: 'tlbp', 16: 'rfe'}.get(fn, f'CO?{fn:02X}')
            return cfn
        return f'UNKNOWN (op=0x10)'

    if op == 0x12:
        if w & 0x02000000:
            g = {
                1: 'RTPS', 6: 'NCLIP', 0x0C: 'OP', 0x10: 'DPCS', 0x11: 'INTPL', 0x12: 'MVMVA',
                0x13: 'NCDS', 0x14: 'CDP', 0x16: 'NCDT', 0x1B: 'NCCS', 0x1C: 'CC', 0x1E: 'NCS',
                0x20: 'NCT', 0x28: 'SQR', 0x29: 'DCPL', 0x2A: 'DPCT', 0x2D: 'AVSZ3', 0x2E: 'AVSZ4',
                0x30: 'RTPT', 0x3D: 'GPF', 0x3E: 'GPL', 0x3F: 'NCCT'
            }.get(fn, f'GTE?{fn:02X}')
            return f'GTE {g}'
        cop2_op = {0: 'mfc2', 2: 'cfc2', 4: 'mtc2', 6: 'ctc2'}.get(rs, 'cop2')
        return f'{cop2_op} {REG[rt]}, g{rd}'

    if op in (0x32, 0x3A):
        n = 'lwc2' if op == 0x32 else 'swc2'
        return f'{n} g{rt}, {simm}({REG[rs]})'

    return f'UNKNOWN (op=0x{op:02X})'

def process_dump_text(text: str, user_base: int = None) -> list:
    """
    Parse a plain-text memory dump into decoded instruction strings.
    Returns list of formatted lines: "0xADDR: HEXWORD  DISASM".
    """
    lines = text.splitlines()
    cur_addr = user_base

    # If no user base was passed, check for header base address line
    if cur_addr is None:
        m = re.search(r'(?:code|data|stack)?\s*@[^\s]*\s*@?0x([0-9a-fA-F]{8})', text)
        if not m:
            m = re.search(r'0x([0-9a-fA-F]{8}):', text)
        if m:
            cur_addr = int(m.group(1), 16)
        else:
            cur_addr = 0x80000000

    results = []

    for line in lines:
        # Check if line is a header like '[crash] code @cur_fn @0x800769A4:'
        header_match = re.search(r'@[a-zA-Z0-9_]*\s*@?0x([0-9a-fA-F]{8}):?', line)
        if header_match and ('code' in line or 'data' in line or 'stack' in line):
            if user_base is None:
                cur_addr = int(header_match.group(1), 16)
            continue

        # Extract potential hex 32-bit tokens
        tokens = line.strip().split()
        for token in tokens:
            # Strip trailing punctuation/colons
            t_clean = token.strip(':,;[]()')
            if t_clean.startswith('0x') or t_clean.startswith('0X'):
                t_hex = t_clean[2:]
            else:
                t_hex = t_clean

            if len(t_hex) == 8 and re.match(r'^[0-9a-fA-F]{8}$', t_hex):
                word = int(t_hex, 16)
                disasm = decode_word(word, cur_addr)
                results.append(f'0x{cur_addr:08X}: {word:08X}  {disasm}')
                cur_addr += 4

    return results

def run_selftest() -> bool:
    """
    Run self-test on at least 12 hand-written MIPS instructions.
    Returns True if all test cases pass.
    """
    test_cases = [
        # (word, base_va, expected_disasm)
        (0x00000000, 0x80000000, "nop"),
        (0x27BDFFF0, 0x80000000, "addiu sp, sp, -16"),
        (0x3C048007, 0x80000000, "lui a0, 0x8007"),
        (0x8FA40010, 0x80000000, "lw a0, 16(sp)"),
        (0xAFBF001C, 0x80000000, "sw ra, 28(sp)"),
        (0x03E00008, 0x80000000, "jr ra"),
        (0x0C01DA69, 0x80000000, "jal 0x800769A4"),
        (0x10800003, 0x80000000, "beq a0, zero, 0x80000010"),
        (0x14A6FFFE, 0x80000004, "bne a1, a2, 0x80000000"),
        (0x00A64021, 0x80000000, "addu t0, a1, a2"),
        (0x00041080, 0x80000000, "sll v0, a0, 2"),
        (0x01050018, 0x80000000, "mult t0, a1"),
        (0x00001012, 0x80000000, "mflo v0"),
        (0x04010005, 0x80000004, "bgez zero, 0x8000001C"),
        (0x340200FF, 0x80000000, "ori v0, zero, 0xFF"),
        (0x3043000F, 0x80000000, "andi v1, v0, 0xF"),
        (0x3843000F, 0x80000000, "xori v1, v0, 0xF"),
        (0x94820002, 0x80000000, "lhu v0, 2(a0)"),
        (0xA0820000, 0x80000000, "sb v0, 0(a0)"),
        (0xFC000000, 0x80000000, "UNKNOWN (op=0x3F)"),
    ]

    passed = 0
    total = len(test_cases)
    print(f"=== Running mips_decode.py Selftest ({total} test cases) ===")

    for w, va, expected in test_cases:
        actual = decode_word(w, va)
        if actual == expected:
            passed += 1
            print(f"  PASS: 0x{w:08X} @ 0x{va:08X} -> {actual}")
        else:
            print(f"  FAIL: 0x{w:08X} @ 0x{va:08X}")
            print(f"        Expected: '{expected}'")
            print(f"        Got:      '{actual}'")

    print(f"=== Selftest Result: {passed}/{total} PASSED ===")
    if passed == total:
        print("PASS")
        return True
    else:
        print("FAIL")
        return False

def main():
    parser = argparse.ArgumentParser(description="MIPS I crash dump decoder")
    parser.add_argument("file", nargs="?", help="Input dump text file (reads stdin if omitted)")
    parser.add_argument("--base", help="Base address in hex (e.g., 0x800769A4)")
    parser.add_argument("--selftest", action="store_true", help="Run internal self-tests and exit")

    args = parser.parse_args()

    if args.selftest:
        success = run_selftest()
        sys.exit(0 if success else 1)

    base_addr = None
    if args.base:
        base_addr = int(args.base, 16)

    if args.file:
        with open(args.file, "r") as f:
            text = f.read()
    else:
        text = sys.stdin.read()

    decoded = process_dump_text(text, user_base=base_addr)
    for line in decoded:
        print(line)

if __name__ == "__main__":
    main()
