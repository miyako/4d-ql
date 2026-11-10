#!/usr/bin/env python3
"""Build the explicitly synthetic DB4D structure used by the CLI gallery.

The header follows FourDFileKitTests.syntheticFile. TabA/TDEF layouts follow
DB4DContainer and DB4DCatalog's documented offsets. This is a parser fixture,
not a 4D-authored or executable application: no methods, resources or records.
"""
import argparse
from pathlib import Path
import struct
import uuid


def generate():
    data = bytearray(512)

    def put(fmt, offset, value):
        struct.pack_into("<" + fmt, data, offset, value)

    data[:4] = bytes([0x02, 0x44, 0x01, 0x44])
    put("h", 0x0C, 1)
    put("i", 0x10, 2)
    put("i", 0x14, 3)
    data[0x18:0x28] = uuid.UUID("11111111-2222-4333-8444-555555555555").bytes
    put("i", 0x40, 128)
    put("i", 0x44, 7)
    data[0x7A] = 1  # contains structure
    put("q", 0x84, 512)
    put("i", 0x8C, 2)
    put("i", 0xF8, 1033)
    data[0xFC] = 1

    def block(tag, size, position):
        result = bytearray(size)
        result[:4] = tag[::-1].encode("ascii")
        struct.pack_into("<i", result, 4, size - 28)
        struct.pack_into("<i", result, 20, position)
        return result

    address_table = block("TabA", 28 + 1024 * 12, 0)
    data.extend(address_table)
    tables = [
        ("Customers", [("ID", 4), ("Name", 14), ("Email", 14), ("Joined", 8)]),
        ("Invoices", [("ID", 4), ("Customer_ID", 4), ("Amount", 6), ("Paid", 1)]),
    ]
    for index, (name, fields) in enumerate(tables):
        definition = block("TDEF", 244 + len(fields) * 132, index)
        definition[28:44] = uuid.uuid5(uuid.NAMESPACE_DNS, "cli." + name).bytes

        def name_at(text, offset):
            struct.pack_into("<h", definition, offset, len(text))
            encoded = text.encode("utf-16-le")
            definition[offset + 2:offset + 2 + len(encoded)] = encoded

        name_at(name, 44)
        struct.pack_into("<i", definition, 212, len(fields))
        for field_index, (field_name, kind) in enumerate(fields):
            base = 244 + field_index * 132
            definition[base:base + 16] = uuid.uuid5(
                uuid.NAMESPACE_DNS, "cli." + name + "." + field_name
            ).bytes
            name_at(field_name, base + 16)
            struct.pack_into("<i", definition, base + 116, kind)
            if kind == 14:
                struct.pack_into("<i", definition, base + 108, 80)
        struct.pack_into("<qi", data, 512 + 28 + index * 12, len(data), len(definition))
        data.extend(definition)
    put("q", 0x28, len(data))
    return data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(generate())
