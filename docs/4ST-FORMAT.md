# Saved sets (.4st)

This is an evidence-based description of the subset decoded by `SetFileAnalyzer`,
not an official specification. The runtime decoder is independent of 4D.

## Evidence

The three supplied files (`all`, `random`, `mixed`) each have a 24-byte header,
one directory byte and one 4,096-byte bitmap. Their populations are respectively
310, 74 and 242 records. Membership is **one bit per record**, not one byte.

The original JSON arrays are preserved beside these binaries. The arrays have
an unused element zero, because their generator indexes them with 4D selection
positions starting at one. Thus JSON index 1 corresponds to record number 0
in these particular files (no deleted/reused addresses).

`all.json` and `random.json` match the binary membership exactly. The mixed
generator has a separate off-by-one: after its `For` loop, `$i` is already
advanced, and the `While` loop increments it again before writing the map.
Consequently, JSON misses binary record 155 and adds nonexistent record 310.
The binary contains records 155 through 309 in its contiguous tail. Tests
assert both the discrepancy and the corrected membership; they do not
silently rewrite the supplied JSON.

Controlled probes used a disposable table of 100,000 records, with 4D IDs
1 through 100,000 corresponding to record numbers 0 through 99,999. Sets
saved with tool4d 21 R5 establish page boundaries, empty/full compression,
directory/payload separation, and the saved current-record field:

| Set | Directory bytes (hex) | File bytes | Records in set |
|---|---|---:|---:|
| Empty | none | 24 | 0 |
| All | `01 01 01 07` | 4,124 | 100,000 |
| First record | `07 00 00 00` | 4,124 | 1 |
| Record 32,768 | `00 07 00 00` | 4,124 | 1 |
| Last record | `00 00 00 07` | 4,124 | 1 |
| First complete page | `01 00 00 00` | 28 | 32,768 |
| Second complete page | `00 01 00 00` | 28 | 32,768 |
| First two pages | `01 01 00 00` | 28 | 65,536 |
| All except first page | `00 01 01 07` | 4,124 | 67,232 |
| First 10 and last 11 | `07 00 00 07` | 8,220 | 21 |

The last case was also loaded back through `LOAD SET` / `USE SET` and
`SELECTION TO ARRAY`, confirming the selected IDs, then resaved. Fixture
generation is in `make_sets.4dm` and `bash scripts/make-set-fixtures.sh`;
the script uses a new temporary database and never rewrites an existing one.
All committed generated fixtures were subsequently regenerated from scratch
with that script under tool4d 21 R5.
Research on 2026-11-10 used tool4d 21.2 for initial record creation and
21 R5 for successful set saves and loads. The 21.2 process exited during
`SAVE SET`; the regeneration script therefore defaults to the verified R5.

## Header

| Offset | Bytes | Meaning / observed behavior |
|---|---:|---|
| `0x00` | 4 | Saved current record, signed **big-endian**; `-1` means none |
| `0x04` | 4 | Unidentified outer-header field, zero in all valid probes; not used |
| `0x08` | 4 | Payload signature: `37 30 44 34` (`70D4`), little-endian numeric `4D07` |
| `0x0C` | 4 | Little-endian serialization marker, observed value `1`; other values unsupported |
| `0x10` | 4 | Little-endian address span (record-number upper bound, exclusive) |
| `0x14` | 4 | Little-endian page count, equal to `ceil(addressSpan / 32768)` |
| `0x18` | page count | One-byte page directory |
| after directory | variable | Bitmap payloads, in directory order |

The outer saved current-record field does **not** use the payload byte order.
The singleton probes record numbers 32,768 and 99,999 distinguish the orders
unambiguously. Sets built by `CREATE EMPTY SET` and `ADD TO SET` have `-1`
there, unlike `CREATE SET` with a current record.

The address span is not the selected-record count or necessarily the table's
record count. `CREATE SET` probes preserve the table's 100,000-address span
even for a singleton; the supplied incrementally built random set ends at
address 300, giving span 301 although the table has 310 records.

## Pages

Each page covers 32,768 consecutive record addresses:

| Tag | Payload bytes | Membership |
|---|---:|---|
| `00` | 0 | All absent |
| `01` | 0 | All present within the address span |
| `07` | 4,096 | Bitmap |

**All directory bytes precede all bitmap bodies.** Treating each tag as
immediately followed by its body appears to work on the supplied single-page
files but fails on multi-page sets.

In the confirmed little-endian bitmaps, byte `i`, bit `b` (least-significant
bit first) represents record `page * 32768 + i * 8 + b`. Equivalently, a
little-endian 32-bit word has its lowest record number in bit zero.
Bits outside the final address span are padding, not records.

Only completely uniform pages compress: a run of 310 present records still
needs a bitmap, while an aligned run of 32,768 present records takes a
directory byte. No evidence supports treating tags 2 through 6 as additional
run lengths; unknown tags are rejected.

## Byte-order limits and unknowns

The reversed payload signature `34 44 30 37` (`4D07`) is recognized as a
big-endian candidate but explicitly reported as unsupported. No historical
big-endian sample was available. Reversing the signature, header integers,
and optionally 32-bit bitmap words in controlled files did **not** produce
a file accepted by the current tool4d loader. Synthetic data is therefore
not evidence of a working historical encoding. The parser does not claim
big-endian support or guess its bitmap layout.

The unidentified outer field and exact semantics of marker `1` remain
unresolved; neither is needed for membership previews. No table identifier,
table name, database UUID, set name, record contents or saved selection
ordering has been established from these bytes. The preview does not
invent them.

## Preview bounds

Files are limited to 4 MiB, the span to a signed 32-bit record address space,
and lengths must exactly match the header and directory. Parsing does not
expand compressed pages into individual records. It computes exact totals,
up to 16 distribution bins over the address span, and the first 200 complete
contiguous selected ranges. JSON exposes these same bounded ranges, the
exact total range count, and all summary fields. `--thorough` does not
remove the file-size or output bounds.

Record numbers are zero-based storage addresses, **not** selection positions,
primary keys, or current live record counts. A standalone set cannot reveal
whether an absent address is deleted or merely excluded. Saved sets may
become stale when record slots are reused or a data file is compacted; see
4D's [sets documentation](https://developer.4d.com/docs/Develop/sets) and
[`LOAD SET`](https://developer.4d.com/docs/commands/load-set).
