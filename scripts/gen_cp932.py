#!/usr/bin/env python3
"""Generate priv/cp932.bin mapping table for BaconNet.CP932.

Format: "CP93" <> dec_count::u32 <> dec_entries <> enc_count::u32 <> enc_entries
dec entry: value::u16 <> utf8_len::u8 <> utf8_bytes
enc entry: codepoint::u32 <> value::u16
"""
import struct
import sys

dec = {}
for b in range(256):
    try:
        dec[b] = bytes([b]).decode("cp932")
    except UnicodeDecodeError:
        pass
for lead in list(range(0x81, 0xA0)) + list(range(0xE0, 0xFD)):
    for trail in list(range(0x40, 0x7F)) + list(range(0x80, 0xFD)):
        v = (lead << 8) | trail
        try:
            dec[v] = bytes([lead, trail]).decode("cp932")
        except UnicodeDecodeError:
            pass

enc = {}
for cp in range(0x110000):
    if 0xD800 <= cp <= 0xDFFF:
        continue
    try:
        b = chr(cp).encode("cp932")
    except UnicodeEncodeError:
        continue
    enc[cp] = int.from_bytes(b, "big")

out = bytearray(b"CP93")
out += struct.pack(">I", len(dec))
for v in sorted(dec):
    u = dec[v].encode("utf-8")
    out += struct.pack(">HB", v, len(u)) + u
out += struct.pack(">I", len(enc))
for cp in sorted(enc):
    out += struct.pack(">IH", cp, enc[cp])

path = sys.argv[1] if len(sys.argv) > 1 else "priv/cp932.bin"
with open(path, "wb") as f:
    f.write(out)
print(f"wrote {path}: {len(dec)} decode entries, {len(enc)} encode entries, {len(out)} bytes")
