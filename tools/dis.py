#!/usr/bin/env python3
"""Minimal MIPS R3000 disassembler over SLUS_006.64. usage: dis.py <start_hex> <end_hex>"""
import struct,sys
b=open('/Users/joshuaghoreishi/Downloads/xenolift/SLUS_006.64','rb').read()
t=0x80010000
R=['zero','at','v0','v1','a0','a1','a2','a3','t0','t1','t2','t3','t4','t5','t6','t7','s0','s1','s2','s3','s4','s5','s6','s7','t8','t9','k0','k1','gp','sp','fp','ra']
def w(a): return struct.unpack_from('<I',b,0x800+a-t)[0]
def dis(a):
    x=w(a);op=x>>26;rs=(x>>21)&31;rt=(x>>16)&31;rd=(x>>11)&31;im=x&0xffff;si=im-0x10000 if im&0x8000 else im;fn=x&63
    if x==0: return 'nop'
    if op==0:
        m={8:'jr',9:'jalr',0x20:'add',0x21:'addu',0x22:'sub',0x23:'subu',0x24:'and',0x25:'or',0x26:'xor',0x27:'nor',0x2a:'slt',0x2b:'sltu',0:'sll',2:'srl',3:'sra',4:'sllv',6:'srlv',7:'srav',0xc:'syscall',0xd:'break',0x10:'mfhi',0x12:'mflo',0x18:'mult',0x19:'multu',0x1a:'div',0x1b:'divu'}.get(fn,'sp%02x'%fn)
        if fn==8: return f'jr {R[rs]}'
        if fn==9: return f'jalr {R[rd]},{R[rs]}'
        if fn in (0,2,3): return f'{m} {R[rd]},{R[rt]},{(x>>6)&31}'
        if fn in (0x10,0x12): return f'{m} {R[rd]}'
        if fn in (0x18,0x19,0x1a,0x1b): return f'{m} {R[rs]},{R[rt]}'
        return f'{m} {R[rd]},{R[rs]},{R[rt]}'
    if op in (2,3): return ('j' if op==2 else 'jal')+' %08X'%((a&0xF0000000)|((x&0x3ffffff)<<2))
    if op in (4,5): return ('beq' if op==4 else 'bne')+f' {R[rs]},{R[rt]},%08X'%(a+4+si*4)
    if op==1: return {0:'bltz',1:'bgez',16:'bltzal',17:'bgezal'}.get(rt,'regimm%d'%rt)+f' {R[rs]},%08X'%(a+4+si*4)
    if op in (6,7): return ('blez' if op==6 else 'bgtz')+f' {R[rs]},%08X'%(a+4+si*4)
    if op==0x10: return f'cop0 {x:08X}'
    if op==0x12: return f'cop2 {x:08X}'
    names={8:'addi',9:'addiu',0xa:'slti',0xb:'sltiu',0xc:'andi',0xd:'ori',0xe:'xori',0xf:'lui',0x20:'lb',0x21:'lh',0x22:'lwl',0x23:'lw',0x24:'lbu',0x25:'lhu',0x26:'lwr',0x28:'sb',0x29:'sh',0x2a:'swl',0x2b:'sw',0x2e:'swr',0x32:'lwc2',0x3a:'swc2'}
    n=names.get(op,'op%02x'%op)
    if op==0xf: return f'lui {R[rt]},0x{im:04X}'
    if op>=0x20: return f'{n} {R[rt]},{si}({R[rs]})'
    if op in (0xc,0xd,0xe): return f'{n} {R[rt]},{R[rs]},0x{im:X}'
    return f'{n} {R[rt]},{R[rs]},{si}'
if __name__=='__main__':
    lo,hi=int(sys.argv[1],16),int(sys.argv[2],16)
    for a in range(lo,hi,4): print('%08X %08X %s'%(a,w(a),dis(a)))
