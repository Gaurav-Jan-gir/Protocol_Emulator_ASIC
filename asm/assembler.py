#!/usr/bin/env python3
"""
ProtoPlex-8 Micro-Engine Assembler
Compiles human-readable assembly for the Protocol Emulator ASIC into 16-bit machine words.

ISA Instruction Format:
[15:13] Opcode (3 bits)
[12:8]  Delay  (5 bits: 0..31 cycles)
[7:0]   Payload (8 bits: instruction-specific arguments)
"""

import sys
import os
import re

OPCODES = {
    'JMP':  0b000,
    'WAIT': 0b001,
    'IN':   0b010,
    'OUT':  0b011,
    'PUSH': 0b100,
    'PULL': 0b100,
    'MOV':  0b101,
    'SET':  0b110,
    'ALU':  0b111,
    'NOP':  0b101, # MOV X, X
}

JMP_CONDS = {
    'ALWAYS': 0b000,
    '!X':     0b001,
    'X--':    0b010,
    '!Y':     0b011,
    'Y--':    0b100,
    'PIN':    0b101,
    '!OSRE':  0b110,
    '!RXF':   0b111,
}

WAIT_SRCS = {
    'PIN0': 0b000,
    'PIN1': 0b001,
    'PIN2': 0b010,
    'PIN3': 0b011,
    'IRQ0': 0b100,
    'IRQ1': 0b101,
    'TXF':  0b110,
    'RXF':  0b111,
}

IN_SRCS = {
    'PIN0': 0b000,
    'PIN1': 0b001,
    'PIN2': 0b010,
    'PIN3': 0b011,
    'X':    0b100,
    'Y':    0b101,
    '0':    0b110,
    'ZERO': 0b110,
    '1':    0b111,
    'ONE':  0b111,
}

OUT_DSTS = {
    'PINS': 0b000,
    'X':    0b001,
    'Y':    0b010,
    'OE':   0b011,
    'PC':   0b100,
    'IRQ':  0b101,
}

MOV_REGS = {
    'X':      0,
    'Y':      1,
    'ISR':    2,
    'OSR':    3,
    'PINS':   4,
    'OE':     5,
    '!X':     5,
    'NOT_X':  5,
    '!Y':     6,
    'NOT_Y':  6,
    'SWAP_X': 7,
}

SET_DSTS = {
    'PINS': 0b000,
    'X':    0b001,
    'Y':    0b010,
    'OE':   0b011,
    'SIDE': 0b100,
    'IRQ':  0b101,
}

ALU_OPS = {
    'ADD':    0b000,
    'SUB':    0b001,
    'AND':    0b010,
    'OR':     0b011,
    'XOR':    0b100,
    'INC':    0b101,
    'DEC':    0b110,
    'BITREV': 0b111,
}

class Assembler:
    def __init__(self):
        self.labels = {}
        self.defines = {}
        self.instructions = []

    def clean_line(self, line):
        # Remove comments (; # //)
        line = re.sub(r'(;|#|//).*$', '', line).strip()
        return line

    def parse_delay(self, token):
        # Parses [5] or 5
        m = re.match(r'\[(\d+)\]', token)
        if m:
            return int(m.group(1))
        return 0

    def assemble(self, source_code):
        lines = source_code.splitlines()
        self.labels = {}
        self.defines = {}
        raw_ops = []

        # Pass 1: Collect definitions, labels, and tokenized lines
        addr = 0
        for line_num, orig_line in enumerate(lines, 1):
            line = self.clean_line(orig_line)
            if not line:
                continue

            # Check for .define NAME VALUE
            if line.startswith('.define'):
                parts = line.split()
                if len(parts) >= 3:
                    self.defines[parts[1]] = int(parts[2], 0)
                continue

            # Check for label
            if ':' in line:
                parts = line.split(':', 1)
                lbl = parts[0].strip()
                self.labels[lbl] = addr
                line = parts[1].strip()
                if not line:
                    continue

            # Substitute defines
            for k, v in self.defines.items():
                line = re.sub(r'\b' + re.escape(k) + r'\b', str(v), line)

            raw_ops.append((line_num, addr, line))
            addr += 1

        if addr > 32:
            raise ValueError(f"Program exceeds 32 instruction capacity of micro-engine! (Total: {addr})")

        # Pass 2: Encode instructions
        machine_code = []
        listing = []

        for line_num, pc, line in raw_ops:
            word = self.encode_instruction(line, pc)
            machine_code.append(word)
            listing.append(f"0x{pc:02X} (0x{word:04X}): {line}")

        return machine_code, listing

    def encode_instruction(self, line, pc):
        tokens = [t.strip(',') for t in line.split()]
        mnemonic = tokens[0].upper()

        delay = 0
        # Check if last token is [delay]
        if tokens[-1].startswith('[') and tokens[-1].endswith(']'):
            delay = self.parse_delay(tokens[-1])
            tokens = tokens[:-1]

        if delay > 31:
            raise ValueError(f"Delay {delay} exceeds 5-bit limit (max 31)")

        if mnemonic == 'NOP':
            # Encoded as MOV X, X with delay
            opcode = OPCODES['MOV']
            payload = (MOV_REGS['X'] << 4) | MOV_REGS['X']
            return (opcode << 13) | (delay << 8) | payload

        elif mnemonic == 'JMP':
            opcode = OPCODES['JMP']
            # JMP [cond] target or JMP target
            if len(tokens) == 2:
                cond_str = 'ALWAYS'
                target_str = tokens[1]
            elif len(tokens) == 3:
                cond_str = tokens[1].upper()
                target_str = tokens[2]
            else:
                raise ValueError(f"Invalid JMP syntax: {line}")

            cond = JMP_CONDS.get(cond_str, None)
            if cond is None:
                raise ValueError(f"Unknown JMP condition '{cond_str}'")

            if target_str in self.labels:
                target_addr = self.labels[target_str]
            else:
                target_addr = int(target_str, 0)

            payload = ((cond & 0x7) << 5) | (target_addr & 0x1F)
            return (opcode << 13) | (delay << 8) | payload

        elif mnemonic == 'WAIT':
            opcode = OPCODES['WAIT']
            # WAIT <pol> <src>
            if len(tokens) < 3:
                raise ValueError(f"Invalid WAIT syntax: {line}")
            pol = int(tokens[1], 0) & 1
            src_str = tokens[2].upper()
            src = WAIT_SRCS.get(src_str, None)
            if src is None:
                raise ValueError(f"Unknown WAIT src '{src_str}'")
            payload = (pol << 7) | ((src & 0x7) << 4)
            return (opcode << 13) | (delay << 8) | payload

        elif mnemonic == 'IN':
            opcode = OPCODES['IN']
            # IN <src>, <nbits>
            src_str = tokens[1].upper()
            src = IN_SRCS.get(src_str, None)
            if src is None:
                raise ValueError(f"Unknown IN src '{src_str}'")
            nbits = int(tokens[2], 0)
            if nbits == 16:
                nbits_raw = 0
            else:
                nbits_raw = nbits & 0x1F
            payload = ((src & 0x7) << 5) | nbits_raw
            return (opcode << 13) | (delay << 8) | payload

        elif mnemonic == 'OUT':
            opcode = OPCODES['OUT']
            # OUT <dst>, <nbits>
            dst_str = tokens[1].upper()
            dst = OUT_DSTS.get(dst_str, None)
            if dst is None:
                raise ValueError(f"Unknown OUT dst '{dst_str}'")
            nbits = int(tokens[2], 0)
            if nbits == 16:
                nbits_raw = 0
            else:
                nbits_raw = nbits & 0x1F
            payload = ((dst & 0x7) << 5) | nbits_raw
            return (opcode << 13) | (delay << 8) | payload

        elif mnemonic in ('PUSH', 'PULL'):
            opcode = OPCODES['PUSH']
            sel = 0 if mnemonic == 'PUSH' else 1
            # Optional flags
            payload = (sel << 7)
            return (opcode << 13) | (delay << 8) | payload

        elif mnemonic == 'MOV':
            opcode = OPCODES['MOV']
            # MOV <dst>, <src>
            dst_str = tokens[1].upper()
            src_str = tokens[2].upper()
            dst = MOV_REGS.get(dst_str, None)
            src = MOV_REGS.get(src_str, None)
            if dst is None or src is None:
                raise ValueError(f"Unknown MOV registers '{dst_str}', '{src_str}'")
            payload = ((dst & 0xF) << 4) | (src & 0xF)
            return (opcode << 13) | (delay << 8) | payload

        elif mnemonic == 'SET':
            opcode = OPCODES['SET']
            # SET <dst>, <val>
            dst_str = tokens[1].upper()
            dst = SET_DSTS.get(dst_str, None)
            if dst is None:
                raise ValueError(f"Unknown SET dst '{dst_str}'")
            val = int(tokens[2], 0) & 0x1F
            payload = ((dst & 0x7) << 5) | val
            return (opcode << 13) | (delay << 8) | payload

        elif mnemonic in ALU_OPS:
            opcode = OPCODES['ALU']
            op = ALU_OPS[mnemonic]
            # e.g. ADD X, Y or INC X
            payload = (op << 5)
            return (opcode << 13) | (delay << 8) | payload

        else:
            raise ValueError(f"Unknown mnemonic '{mnemonic}' in line: {line}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 assembler.py <source.asm> [-o output.hex] [-f format]")
        sys.exit(1)

    src_file = sys.argv[1]
    with open(src_file, 'r') as f:
        code = f.read()

    asm = Assembler()
    machine_code, listing = asm.assemble(code)

    print(f"--- Assembled {len(machine_code)} instructions from {src_file} ---")
    for l in listing:
        print(l)

    # Output file
    out_file = None
    if "-o" in sys.argv:
        idx = sys.argv.index("-o")
        if idx + 1 < len(sys.argv):
            out_file = sys.argv[idx + 1]

    if not out_file:
        out_file = os.path.splitext(src_file)[0] + ".hex"

    with open(out_file, 'w') as f:
        for word in machine_code:
            f.write(f"{word:04X}\n")

    print(f"Written machine code to: {out_file}")

if __name__ == '__main__':
    main()
