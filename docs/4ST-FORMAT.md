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

### Large address spans

Additional tool4d 21 R5 probes establish:

- A separate fresh database was populated with **1,000,000 actual records**.
  `CREATE SET` / `SAVE SET` produced `million-full.4st`: span 1,000,000,
  30 full pages and one bitmap, containing all million records in 4,151 bytes.
  `CREATE SET FROM ARRAY` with alternating Boolean membership produced
  `million-alternating.4st`: span 1,000,001, 31 bitmaps and exactly 500,000
  members in 127,031 bytes. Both native files are committed. Regenerate
  them with `MILLION_RECORDS=1 bash scripts/make-set-fixtures.sh`; the extra
  table uses a fresh database and 10,000-record transaction batches.
- `CREATE SET FROM ARRAY` with an all-false Boolean array of 33,587,200
  elements natively saves an empty set with span 33,587,201 and **1,026
  directory bytes**, still flat. This crosses a 1,024-page boundary without
  introducing a directory of directory addresses.
- A synthesized sparse set with span **1,000,000,000**, 30,518 directory
  bytes and eight members was loaded by `LOAD SET` and resaved by `SAVE SET`
  **byte-for-byte unchanged**. Members straddle 32,768, 2,097,152 and
  536,870,912, and include 999,999,999. The 59,214-byte engine-round-tripped
  file is committed as `billion-sparse.4st`.
- A synthesized set with **1,025 bitmap pages**, span 33,587,200 and one
  member at the start of every page also round-trips byte-for-byte. Its
  4,199,449 bytes exceed the former 4 MiB implementation limit. The generator
  verifies this file but does not commit its large body.

These are tests of **saved-set serialization**. They do not populate a
billion-record database or verify the physical record-address tree in a
`.4DD`. `LOAD SET` preserves saved addresses even when corresponding records
are absent from the current table. No additional address indirection appears
in these verified `.4st` outputs; no assumption about the database's address
hierarchy is needed to decode their membership.

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

## Streaming and preview bounds

There is **no arbitrary file-size cutoff**. The header's span is limited to a
signed 32-bit record address space; page count and file length must agree
exactly with the header and directory. That naturally bounds the directory
to 65,536 bytes and the bitmap body to 256 MiB for this encoding.
The decoder reads the 24-byte header, the bounded directory, and at most
**256 KiB of bitmap payload per read**. It does not allocate the entire file,
create a record-number list, or expand compressed pages.

Bitmap words are decoded with unaligned, explicitly little-endian 64-bit
loads and hardware bit counts, without allocating a `Data` per word.
Uniform pages require no payload reads. Output remains bounded to 16
distribution bins and the first 200 observed contiguous ranges.

On the development Mac, a release CLI run over synthetic alternating-membership
bitmaps completed as follows (local files, 2026-11-10; elapsed time includes
process startup and JSON output):

| Address span | File bytes | Elapsed | Maximum resident memory |
|---|---:|---:|---:|
| 10,000,000 | 1,253,706 | 0.024 s | 12.0 MB |
| 100,000,000 | 12,504,068 | 0.035 s | 12.3 MB |
| 1,000,000,000 | 125,032,270 | 0.156 s | 12.3 MB |

These are illustrative warm/local performance observations, not timing
guarantees or a billion-record physical database benchmark. Every run
completed within the default budget with exact half-span cardinality and
range count; output retained only 200 ranges. Slow storage or a busy host
can instead produce a partial preview.

`AnalysisOptions.timeBudget` applies to the bitmap scan (default 1.5 seconds,
measured with a monotonic clock). Header, directory and total length are
validated even when no bitmap time remains. A time-budget check precedes
each bitmap page; already-known empty/full pages are cheap and still
processed until the next unexamined bitmap. A slow individual I/O operation
cannot be preempted by this synchronous budget.

When analysis completes, counts and distribution are exact for the whole
set. Otherwise HTML displays **Partial preview**, qualifies counts as
**At least**, and marks unexamined distribution regions **Unknown**. Coverage
uses only examined addresses, not an extrapolation over the whole set.
An observed range ending at the scan boundary has `isComplete: false`;
the HTML shows its last examined address with `+`, not as a closed range.
Zero observed members never produces "This set is empty" for a partial scan.

JSON exposes `scanStatus` (`complete` or `timeBudgetExceeded`),
`scannedAddressSpan` (the examined contiguous prefix), `scannedBitmapPages`,
and per-range `isComplete`. For a partial scan, `selectedRecords` and
`rangeCount` are lower bounds from that prefix; `firstRecord`, `lastRecord`
and bin `selected` values also refer only to examined membership. A bin's
examined portion is its intersection with `[0, scannedAddressSpan)`;
zeros outside that prefix mean unknown, not absence.
The page-encoding counts describe the entire validated directory regardless
of scan status.

CLI `--thorough` uses an unlimited bitmap time budget and returns exact
summaries for supported, valid files of any permitted address span. It does
not remove the range/bin output bounds. `maxRecordsToScan` is not applied
to bitmap positions: no database records are being walked.

Record numbers are zero-based storage addresses, **not** selection positions,
primary keys, or current live record counts. A standalone set cannot reveal
whether an absent address is deleted or merely excluded. Saved sets may
become stale when record slots are reused or a data file is compacted; see
4D's [sets documentation](https://developer.4d.com/docs/Develop/sets) and
[`LOAD SET`](https://developer.4d.com/docs/commands/load-set).
