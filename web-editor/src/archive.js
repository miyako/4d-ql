import { unzipSync, zipSync, strToU8 } from 'fflate';

export const MAX_ARCHIVE = 16 * 1024 * 1024;
export const MAX_EXPANDED = 32 * 1024 * 1024;
const MAX_ENTRIES = 512;

export class DocumentError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

export function readArchive(bytes) {
  if (bytes.length > MAX_ARCHIVE) throw new DocumentError('tooLarge');
  try {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let end = bytes.length - 22;
    const lower = Math.max(0, end - 65535);
    while (end >= lower && (view.getUint32(end, true) !== 0x06054b50 ||
      end + 22 + view.getUint16(end + 20, true) !== bytes.length)) end--;
    if (end < lower) throw new Error('Missing ZIP directory');
    const count = view.getUint16(end + 10, true);
    const start = view.getUint32(end + 16, true);
    const size = view.getUint32(end + 12, true);
    if (view.getUint32(end + 4, true) !== 0 || count !== view.getUint16(end + 8, true) ||
      count > MAX_ENTRIES || start + size !== end) throw new Error('Unsupported ZIP');
    const directory = new Map();
    let offset = start;
    let total = 0;
    for (let i = 0; i < count; i++) {
      if (view.getUint32(offset, true) !== 0x02014b50) throw new Error('Invalid directory');
      const flags = view.getUint16(offset + 8, true);
      const method = view.getUint16(offset + 10, true);
      const compressed = view.getUint32(offset + 20, true);
      const length = view.getUint32(offset + 24, true);
      const nameLength = view.getUint16(offset + 28, true);
      const name = new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(offset + 46, offset + 46 + nameLength));
      const local = view.getUint32(offset + 42, true);
      total += length;
      if (total > MAX_EXPANDED) throw new DocumentError('tooLarge');
      if (flags & 1 || ![0, 8].includes(method) || view.getUint16(offset + 34, true) !== 0 ||
        !name || name.includes('\\') || name.startsWith('/') || name.split('/').includes('..') ||
        name.includes('\0') || directory.has(name) || local + 30 > start ||
        view.getUint32(local, true) !== 0x04034b50) throw new Error('Unsupported entry');
      const dataStart = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
      if (dataStart + compressed > start) throw new Error('Invalid entry bounds');
      directory.set(name, { length, crc: view.getUint32(offset + 16, true) });
      offset += 46 + nameLength + view.getUint16(offset + 30, true) + view.getUint16(offset + 32, true);
    }
    if (offset !== end) throw new Error('Invalid directory size');
    let expanded = 0;
    const files = unzipSync(bytes, {
      filter(entry) {
        expanded += entry.originalSize;
        if (entry.originalSize > MAX_EXPANDED || expanded > MAX_EXPANDED) throw new DocumentError('tooLarge');
        return true;
      },
    });
    if (Object.keys(files).length !== directory.size) throw new Error('Entry mismatch');
    for (const [name, data] of Object.entries(files)) {
      const entry = directory.get(name);
      if (!entry || data.length !== entry.length || crc32(data) !== entry.crc) throw new Error('Corrupt entry');
    }
    return files;
  } catch (error) {
    if (error instanceof DocumentError) throw error;
    throw new DocumentError('invalidArchive');
  }
}

export function writeArchive(files, name, xhtml) {
  const entries = { ...files, [name]: strToU8(xhtml) };
  if (Object.keys(entries).length > MAX_ENTRIES ||
    Object.values(entries).reduce((sum, bytes) => sum + bytes.length, 0) > MAX_EXPANDED) throw new DocumentError('tooLarge');
  const archive = zipSync(entries, { level: 6 });
  if (archive.length > MAX_ARCHIVE) throw new DocumentError('tooLarge');
  return archive;
}
