import argparse
import mmap
import pathlib
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'scratch/python'))
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

parser = argparse.ArgumentParser()
parser.add_argument('needle')
parser.add_argument('--at', type=lambda value: int(value, 0))
parser.add_argument('--size', type=lambda value: int(value, 0), default=0x180)
args = parser.parse_args()
path = pathlib.Path(__file__).resolve().parent.parent / 'scratch/game-module.bin'
with path.open('rb') as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as image:
    disassembler = Cs(CS_ARCH_X86, CS_MODE_64)
    if args.at is not None:
        for instruction in disassembler.disasm(image[args.at:args.at + args.size], args.at):
            print(f'{instruction.address:08x} {instruction.mnemonic:8} {instruction.op_str}')
    else:
        target = image.find(args.needle.encode('ascii') + b'\0')
        if target < 0:
            raise SystemExit('String not found')
        print(f'String RVA: {target:x}')
        # LEA reg,[RIP+disp32] is used for native diagnostic string references.
        for position in range(0x1000, 0x2200000 - 7):
            if image[position] not in (0x48, 0x4c) or image[position + 1] != 0x8d:
                continue
            if image[position + 2] & 0xc7 != 0x05:
                continue
            displacement = struct.unpack_from('<i', image, position + 3)[0]
            if position + 7 + displacement != target:
                continue
            print(f'XREF: {position:x}')
