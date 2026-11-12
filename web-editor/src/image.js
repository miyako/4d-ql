import { DocumentError } from './archive.js';

function dimensions(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length >= 24 && bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71) {
    return { type: 'png', width: view.getUint32(16), height: view.getUint32(20) };
  }
  if (bytes[0] !== 255 || bytes[1] !== 216 || bytes[2] !== 255) throw new DocumentError('imageType');
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset++] !== 255) throw new DocumentError('imageType');
    while (bytes[offset] === 255) offset++;
    const marker = bytes[offset++];
    if (marker === 0xd9 || marker === 0xda) break;
    if (marker === 0x01 || marker >= 0xd0 && marker <= 0xd8) continue;
    if (offset + 2 > bytes.length) break;
    const length = view.getUint16(offset);
    if (length < 2 || offset + length > bytes.length) break;
    if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
      if (length < 8) break;
      return { type: 'jpeg', width: view.getUint16(offset + 5), height: view.getUint16(offset + 3) };
    }
    offset += length;
  }
  throw new DocumentError('imageType');
}

export async function readImage(file) {
  if (file.size > 8 * 1024 * 1024) throw new DocumentError('imageSize');
  const bytes = new Uint8Array(await file.arrayBuffer());
  const info = dimensions(bytes);
  if (!info.width || !info.height || info.width * info.height > 40_000_000) throw new DocumentError('imageSize');
  const blob = new Blob([bytes], { type: `image/${info.type}` });
  const url = URL.createObjectURL(blob);
  const picture = new Image();
  try {
    await new Promise((resolve, reject) => {
      picture.onload = resolve;
      picture.onerror = () => reject(new DocumentError('imageType'));
      picture.src = url;
    });
    const src = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(new DocumentError('imageType'));
      reader.readAsDataURL(blob);
    });
    return { src, width: picture.naturalWidth, height: picture.naturalHeight };
  } finally { URL.revokeObjectURL(url); }
}
