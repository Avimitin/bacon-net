#!/usr/bin/env python3
"""Cross-check helper: generate kbin test vectors with the reference library."""
import sys

from kbinxml import KBinXML

XML = """<?xml version="1.0" encoding="UTF-8"?>
<response>
  <cardmng status="0">
    <card dataid="E004010203040506" refid="E004010203040506"/>
    <counts __type="u16" __count="3">1 2 3</counts>
    <name __type="str">テスト ＡＢＣ</name>
    <blob __type="bin" __size="4">deadbeef</blob>
    <f __type="float">1.5</f>
    <fd __type="double">-2.25</fd>
    <ip __type="ip4">127.0.0.1</ip>
    <b __type="bool">1</b>
    <t __type="time">1700000000</t>
    <v __type="2s16">-1 2</v>
    <v4 __type="4u32" __count="2">1 2 3 4 5 6 7 8</v4>
    <big __type="s64" __count="2">-5 9999999999</big>
    <neg __type="s8">-128</neg>
    <bytes __type="u8">255</bytes>
    <word __type="s16">-32768</word>
    <uword __type="u16">65535</uword>
    <empty __type="str"></empty>
    <void attr1="x" attr2="y"/>
    <nested><a><b deep="1"><c __type="s32">-7</c></b></a></nested>
  </cardmng>
</response>
"""

mode = sys.argv[1] if len(sys.argv) > 1 else "compressed"
out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/test.kbin"

k = KBinXML(XML.encode("utf-8"))
if mode == "compressed":
    data = k.to_binary()
elif mode == "uncompressed":
    data = k.to_binary(compressed=False)
elif mode == "utf8":
    data = k.to_binary(encoding="UTF-8")

with open(out, "wb") as f:
    f.write(data)
print(f"wrote {out} ({len(data)} bytes, {mode})")
