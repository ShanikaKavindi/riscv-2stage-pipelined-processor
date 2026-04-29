"""
Usage:
    python3 convert.py input_instructions.txt output_bytes_le.hex

What it does:
 - Reads input text file (lines like "0x00100093    addi x1, x0, 1  // comment")
 - Ignores empty lines and comment-only lines
 - Finds the first hex word on each line (supports "0x" prefix or plain hex)
 - Pads the word to 8 hex digits (32-bit) if needed
 - Emits the bytes of each 32-bit word in little-endian order, one byte per line (two hex chars)
"""
import sys
import re

HEX_PATTERN_WITH_0X = re.compile(r'0[xX]([0-9a-fA-F]+)')
HEX_TOKEN_PATTERN = re.compile(r'\b([0-9a-fA-F]{1,8})\b')

def extract_first_hex_token(line):
    """Return hex string (without 0x) or None"""
    m = HEX_PATTERN_WITH_0X.search(line)
    if m:
        return m.group(1)
    m2 = HEX_TOKEN_PATTERN.search(line)
    if m2:
        return m2.group(1)
    return None

def word_to_le_bytes_hex(word_hex):
    """Convert a hex word string to list of 2-char byte hex strings in little-endian order."""
    word_hex = word_hex.lstrip().rstrip()
    if len(word_hex) > 8:
        word_hex = word_hex[-8:]
    word_hex = word_hex.zfill(8)
    val = int(word_hex, 16)
    b = val.to_bytes(4, byteorder='little', signed=False)
    return [f"{byte:02x}" for byte in b]

def convert_file(infile, outfile):
    total_words = 0
    total_bytes = 0
    with open(infile, 'r') as inf, open(outfile, 'w') as outf:
        for lineno, raw in enumerate(inf, start=1):
            line = raw.strip()
            if not line:
                continue
            if line.startswith('//') or line.startswith('#'):
                continue
            token = extract_first_hex_token(line)
            if token is None:
                continue
            bytes_le = word_to_le_bytes_hex(token)
            for b in bytes_le:
                outf.write(b + '\n')
                total_bytes += 1
            total_words += 1
    print(f"Converted {total_words} word(s) -> {total_bytes} byte lines written to '{outfile}'")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 convert.py <input_txt> <output_bytes_le.hex>")
        sys.exit(2)
    infile = sys.argv[1]
    outfile = sys.argv[2]
    convert_file(infile, outfile)
