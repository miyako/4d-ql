import { DocumentError } from './archive.js';

const MAX_BYTES = 8 * 1024 * 1024;
const MAX_PIXELS = 40_000_000;
const ascii = (bytes, start, count) => String.fromCharCode(...bytes.subarray(start, start + count));
const crcTable = Uint32Array.from({ length: 256 }, (_, value) => {
  for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ value >>> 1 : value >>> 1;
  return value >>> 0;
});
function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) value = crcTable[(value ^ byte) & 255] ^ value >>> 8;
  return (value ^ 0xffffffff) >>> 0;
}

export function rasterInfo(bytes) {
  if (!bytes || bytes.length < 10) throw new DocumentError('mediaMalformed');
  if (bytes.length > MAX_BYTES) throw new DocumentError('mediaBudget');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let type, width, height;
  if (ascii(bytes, 0, 8) === '\x89PNG\r\n\x1a\n') {
    type = 'png';
    let offset = 8, data = false, ended = false;
    while (offset + 12 <= bytes.length) {
      const length = view.getUint32(offset);
      const chunk = ascii(bytes, offset + 4, 4);
      if (length > bytes.length - offset - 12) throw new DocumentError('mediaMalformed');
      if (offset === 8) {
        if (chunk !== 'IHDR' || length !== 13) throw new DocumentError('mediaMalformed');
        width = view.getUint32(offset + 8);
        height = view.getUint32(offset + 12);
        if (!width || !height || width * height > MAX_PIXELS) throw new DocumentError('mediaBudget');
      } else if (chunk === 'IHDR') throw new DocumentError('mediaMalformed');
      if (crc32(bytes.subarray(offset + 4, offset + 8 + length)) !== view.getUint32(offset + 8 + length)) throw new DocumentError('mediaMalformed');
      if (chunk === 'acTL') throw new DocumentError('mediaUnsupported');
      if (chunk === 'IDAT') data = true;
      offset += length + 12;
      if (chunk === 'IEND') { ended = length === 0 && offset === bytes.length; break; }
    }
    if (!data || !ended) throw new DocumentError('mediaMalformed');
  } else if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) {
    type = 'jpeg';
    let offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset++] !== 255) throw new DocumentError('mediaMalformed');
      while (bytes[offset] === 255) offset++;
      const marker = bytes[offset++];
      if (marker === 0xda || marker === 0xd9) break;
      if (marker === 1 || marker >= 0xd0 && marker <= 0xd8) continue;
      if (offset + 2 > bytes.length) throw new DocumentError('mediaMalformed');
      const length = view.getUint16(offset);
      if (length < 2 || length > bytes.length - offset) throw new DocumentError('mediaMalformed');
      if ([0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) throw new DocumentError('mediaUnsupported');
      if ([0xc0, 0xc1, 0xc2].includes(marker)) {
        if (length < 8) throw new DocumentError('mediaMalformed');
        height = view.getUint16(offset + 3);
        width = view.getUint16(offset + 5);
      }
      offset += length;
    }
    if (bytes.at(-2) !== 255 || bytes.at(-1) !== 217) throw new DocumentError('mediaMalformed');
    if (!width || !height) throw new DocumentError('mediaMalformed');
  } else if (['GIF87a', 'GIF89a'].includes(ascii(bytes, 0, 6))) {
    type = 'gif';
    if (bytes.length < 14) throw new DocumentError('mediaMalformed');
    width = view.getUint16(6, true);
    height = view.getUint16(8, true);
    let offset = 13 + (bytes[10] & 128 ? 3 * 2 ** ((bytes[10] & 7) + 1) : 0), frames = 0;
    const blocks = () => {
      while (offset < bytes.length) {
        const length = bytes[offset++];
        if (!length) return;
        offset += length;
      }
      throw new DocumentError('mediaMalformed');
    };
    while (offset < bytes.length && bytes[offset] !== 0x3b) {
      const marker = bytes[offset++];
      if (marker === 0x21) {
        offset++;
        blocks();
      } else if (marker === 0x2c) {
        if (++frames > 1) throw new DocumentError('mediaUnsupported');
        if (offset + 9 > bytes.length || view.getUint16(offset, true) + view.getUint16(offset + 4, true) > width ||
          view.getUint16(offset + 2, true) + view.getUint16(offset + 6, true) > height) throw new DocumentError('mediaMalformed');
        const packed = bytes[offset + 8];
        offset += 9 + (packed & 128 ? 3 * 2 ** ((packed & 7) + 1) : 0) + 1;
        blocks();
      } else throw new DocumentError('mediaMalformed');
    }
    if (frames !== 1 || offset !== bytes.length - 1 || bytes[offset] !== 0x3b) throw new DocumentError('mediaMalformed');
  } else if (ascii(bytes, 0, 4) === 'RIFF' && ascii(bytes, 8, 4) === 'WEBP') {
    type = 'webp';
    if (bytes.length < 30 || view.getUint32(4, true) !== bytes.length - 8) throw new DocumentError('mediaMalformed');
    let offset = 12, image = false;
    while (offset + 8 <= bytes.length) {
      const chunk = ascii(bytes, offset, 4);
      const size = view.getUint32(offset + 4, true);
      if (size > bytes.length - offset - 8) throw new DocumentError('mediaMalformed');
      if (chunk === 'ANIM' || chunk === 'ANMF' || chunk === 'VP8X' && size >= 1 && bytes[offset + 8] & 2) throw new DocumentError('mediaUnsupported');
      if (chunk === 'VP8 ') {
        if (size < 10 || ascii(bytes, offset + 11, 3) !== '\x9d\x01\x2a' || image) throw new DocumentError('mediaMalformed');
        width = view.getUint16(offset + 14, true) & 0x3fff;
        height = view.getUint16(offset + 16, true) & 0x3fff;
        image = true;
      } else if (chunk === 'VP8L') {
        if (size < 5 || bytes[offset + 8] !== 0x2f || image) throw new DocumentError('mediaMalformed');
        const bits = view.getUint32(offset + 9, true);
        width = (bits & 0x3fff) + 1;
        height = (bits >>> 14 & 0x3fff) + 1;
        image = true;
      } else if (chunk === 'VP8X') {
        if (size !== 10 || offset !== 12) throw new DocumentError('mediaMalformed');
        const uint24 = at => bytes[at] + bytes[at + 1] * 256 + bytes[at + 2] * 65536 + 1;
        if (uint24(offset + 12) * uint24(offset + 15) > MAX_PIXELS) throw new DocumentError('mediaBudget');
      }
      offset += 8 + size + size % 2;
    }
    if (!image || offset !== bytes.length) throw new DocumentError('mediaMalformed');
  } else {
    // Animation, vector formats and other native codecs need separate decode budgets.
    throw new DocumentError('mediaUnsupported');
  }
  if (!width || !height || width * height > MAX_PIXELS) throw new DocumentError('mediaBudget');
  return { type, width, height };
}

function unwrap(bytes) {
  if (ascii(bytes, 0, 4) !== 'TCP4') return { bytes, wrapped: false };
  if (bytes.length < 68) throw new DocumentError('mediaMalformed');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  // Only the independently observed v8, single-codec record layout is supported.
  if (view.getUint32(4, true) !== 8 || view.getUint32(8, true) !== 1 ||
    view.getUint32(24, true) !== 0) throw new DocumentError('mediaUnsupported');
  const size = view.getUint32(12, true);
  const codecSize = view.getUint32(16, true);
  const metadataSize = view.getUint32(20, true);
  const chars = -view.getInt32(28, true);
  if (chars < 1 || chars > 16 || codecSize !== 4 + chars * 2) throw new DocumentError('mediaMalformed');
  const table = 28 + codecSize + metadataSize + 24;
  if (table + 8 > bytes.length || size !== bytes.length - table - 8 ||
    view.getUint32(table, true) !== table + 8 || view.getUint32(table + 4, true) !== size ||
    bytes.subarray(table - 24, table).some(byte => byte !== 0)) throw new DocumentError('mediaMalformed');
  let codec = '';
  for (let index = 0; index < chars; index++) codec += String.fromCharCode(view.getUint16(32 + index * 2, true));
  if (!['.png', '.jpg', '.jpeg'].includes(codec.toLowerCase())) throw new DocumentError('mediaUnsupported');
  const payload = bytes.subarray(table + 8);
  const info = rasterInfo(payload);
  if (info.type !== (codec.toLowerCase() === '.png' ? 'png' : 'jpeg')) throw new DocumentError('mediaMalformed');
  return { bytes: payload, wrapped: true };
}

function base64(bytes) {
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 8192) binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  return btoa(binary);
}

export function mediaSource(src, files, entry) {
  try {
    let bytes, mime = null;
    if (/^data:/i.test(src)) {
      const match = /^data:(image\/(?:png|jpeg|gif|webp)|application\/4dpicture);base64,([a-z0-9+/=\s]+)$/i.exec(src);
      if (!match) throw new DocumentError('mediaUnsupported');
      mime = match[1].toLowerCase();
      if (match[2].length > MAX_BYTES * 1.4) throw new DocumentError('mediaBudget');
      const payload = match[2].replace(/\s/g, '');
      if (payload.length % 4 || !/^[a-z0-9+/]*={0,2}$/i.test(payload)) throw new DocumentError('mediaMalformed');
      let binary;
      try { binary = atob(payload); } catch { throw new DocumentError('mediaMalformed'); }
      bytes = Uint8Array.from(binary, char => char.charCodeAt(0));
    } else {
      if (!src || /^(?:[a-z][\w+.-]*:|\/\/|\/)|[\\?#\u0000-\u0020]/i.test(src)) throw new DocumentError('mediaUnsupported');
      let path;
      try {
        const url = new URL(src, `https://archive.invalid/${entry}`);
        path = decodeURIComponent(url.pathname.slice(1));
      } catch { throw new DocumentError('mediaMalformed'); }
      if (!Object.hasOwn(files, path)) throw new DocumentError('mediaMalformed');
      bytes = files[path];
    }
    if (bytes.length > MAX_BYTES) throw new DocumentError('mediaBudget');
    const extracted = unwrap(bytes);
    if (mime === 'application/4dpicture' && !extracted.wrapped) throw new DocumentError('mediaMalformed');
    const info = rasterInfo(extracted.bytes);
    if (mime?.startsWith('image/') && (extracted.wrapped || mime !== `image/${info.type}`)) throw new DocumentError('mediaMalformed');
    return { ...info, src: `data:image/${info.type};base64,${base64(extracted.bytes)}`, wrapped: extracted.wrapped, size: bytes.length };
  } catch (error) {
    if (!(error instanceof DocumentError)) throw error;
    return { src: null, reason: error.code };
  }
}
