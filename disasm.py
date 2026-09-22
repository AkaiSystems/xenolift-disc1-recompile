#!/usr/bin/env python3
"""Minimal MIPS R3000A disassembler for the Xenogears PS-X EXE.
VA -> file offset: off = va - 0x80010000 + 0x800."""
import struct, sys

IMG = open('SLUS_006.64', 'rb').read()
BASE = 0x80010000
FILE_OFF = 0x800

def va2off(va):
    return va - BASE + FILE_OFF

def word(va):
    o = va2off(va)
    return struct.unpack('<I', IMG[o:o+4])[0]

REG = [f'r{i}' for i in range(32)]
for n, i in [('zero',0),('at',1),('v0',2),('v1',3),('a0',4),('a1',5),('a2',6),('a3',7),
             ('t0',8),('t1',9),('t2',10),('t3',11),('t4',12),('t5',13),('t6',14),('t7',15),
             ('s0',16),('s1',17),('s2',18),('s3',19),('s4',20),('s5',21),('s6',22),('s7',23),
             ('t8',24),('t9',25),('k0',26),('k1',27),('gp',28),('sp',29),('fp',30),('ra',31)]:
    REG[i] = n

def s16(w): return w & 0xFFFF if w < 0x8000 else w - 0x10000

def dis(w, va):
    op = (w >> 26) & 0x3F
    rs, rt, rd = (w>>21)&31, (w>>16)&31, (w>>11)&31
    sa, fn = (w>>6)&31, w & 0x3F
    imm = w & 0xFFFF
    simm = s16(imm)
    tgt = (va & 0xF0000000) | ((w & 0x3FFFFFF) << 2)
    if w == 0: return 'nop'
    if op == 0:
        names = {0:'sll',2:'srl',3:'sra',4:'sllv',6:'srlv',7:'srav',
                 8:'jr',9:'jalr',12:'syscall',13:'break',
                 16:'mfhi',17:'mthi',18:'mflo',19:'mtlo',
                 24:'mult',25:'multu',26:'div',27:'divu',
                 32:'add',33:'addu',34:'sub',35:'subu',36:'and',37:'or',
                 38:'xor',39:'nor',42:'slt',43:'sltu'}
        n = names.get(fn)
        if n is None: return f'SPECIAL? fn=0x{fn:02X}'
        if n in ('sll','srl','sra'): return f'{n} {REG[rd]}, {REG[rt]}, {sa}'
        if n in ('sllv','srlv','srav'): return f'{n} {REG[rd]}, {REG[rt]}, {REG[rs]}'
        if n == 'jr': return f'jr {REG[rs]}'
        if n == 'jalr': return f'jalr {REG[rd]}, {REG[rs]}'
        if n in ('syscall','break'): return n
        if n in ('mfhi','mflo'): return f'{n} {REG[rd]}'
        if n in ('mthi','mtlo'): return f'{n} {REG[rs]}'
        if n in ('mult','multu','div','divu'): return f'{n} {REG[rs]}, {REG[rt]}'
        return f'{n} {REG[rd]}, {REG[rs]}, {REG[rt]}'
    if op == 1:
        n = 'bltz' if rt == 0 else 'bgez' if rt == 1 else f'BGEZAL? rt={rt}'
        return f'{n} {REG[rs]}, 0x{va+4+simm*4:08X}'
    if op == 2: return f'j 0x{tgt:08X}'
    if op == 3: return f'jal 0x{tgt:08X}'
    if op == 4: return f'beq {REG[rs]}, {REG[rt]}, 0x{va+4+simm*4:08X}'
    if op == 5: return f'bne {REG[rs]}, {REG[rt]}, 0x{va+4+simm*4:08X}'
    if op == 6: return f'blez {REG[rs]}, 0x{va+4+simm*4:08X}'
    if op == 7: return f'bgtz {REG[rs]}, 0x{va+4+simm*4:08X}'
    names = {8:'addi',9:'addiu',10:'slti',11:'sltiu',12:'andi',13:'ori',14:'xori'}
    if op in names:
        u = f'0x{imm:X}' if op >= 12 else str(simm)
        return f'{names[op]} {REG[rt]}, {REG[rs]}, {u}'
    if op == 15: return f'lui {REG[rt]}, 0x{imm:X}'
    mems = {32:'lb',33:'lh',34:'lwl',35:'lw',36:'lbu',37:'lhu',38:'lwr',
            40:'sb',41:'sh',42:'swl',43:'sw',46:'swr'}
    if op in mems:
        return f'{mems[op]} {REG[rt]}, {simm}({REG[rs]})'
    if op == 0x10:
        if rs == 0: return f'mfc0 {REG[rt]}, c0_{rd}'
        if rs == 4: return f'mtc0 {REG[rt]}, c0_{rd}'
        if w & 0x02000000:
            cfn = {1:'tlbr',2:'tlbwi',6:'tlbwr',8:'tlbp',16:'rfe'}.get(w & 0x3F, f'CO?{w&0x3F:02X}')
            return cfn
        return f'COP0? rs={rs}'
    if op == 0x12:
        if w & 0x02000000:
            g = {1:'RTPS',6:'NCLIP',0xC:'OP',0x10:'DPCS',0x11:'INTPL',0x12:'MVMVA',
                 0x13:'NCDS',0x14:'CDP',0x16:'NCDT',0x1B:'NCCS',0x1C:'CC',0x1E:'NCS',
                 0x20:'NCT',0x28:'SQR',0x29:'DCPL',0x2A:'DPCT',0x2D:'AVSZ3',0x2E:'AVSZ4',
                 0x30:'RTPT',0x3D:'GPF',0x3E:'GPL',0x3F:'NCCT'}.get(w & 0x3F, f'GTE?{w&0x3F:02X}')
            return f'GTE {g}'
        return {0:'mfc2',2:'cfc2',4:'mtc2',6:'ctc2'}.get(rs, f'COP2?rs={rs}') + f' {REG[rt]}, g{rd}'
    if op in (0x32, 0x3A):
        n = 'lwc2' if op == 0x32 else 'swc2'
        return f'{n} g{rt}, {simm}({REG[rs]})'
    return f'?op=0x{op:02X}'

def dump(va, n=48, label=None):
    print(f'===== {label or f"0x{va:08X}"} =====')
    for i in range(n):
        a = va + i*4
        w = word(a)
        print(f'0x{a:08X}: {w:08X}  {dis(w, a)}')
    print()

if __name__ == '__main__':
    for a in sys.argv[1:]:
        dump(int(a, 16))
