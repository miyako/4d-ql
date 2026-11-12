import { describe, expect, it } from 'vitest';
import { readImage } from '../src/image.js';

const file = bytes => ({ size: bytes.length, arrayBuffer: async () => bytes.buffer });

describe('image admission before browser decoding', () => {
  it('rejects file and pixel budgets before decoding or reading oversized files', async () => {
    await expect(readImage({ size: 8 * 1024 * 1024 + 1 })).rejects.toThrow('imageSize');
    const png = new Uint8Array(24);
    png.set([137, 80, 78, 71]);
    const view = new DataView(png.buffer);
    view.setUint32(16, 10000);
    view.setUint32(20, 10000);
    await expect(readImage(file(png))).rejects.toThrow('imageSize');
    view.setUint32(16, 0);
    await expect(readImage(file(png))).rejects.toThrow('imageSize');
  });

  it('rejects active formats and malformed or truncated JPEG headers', async () => {
    for (const bytes of [
      new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"/>'),
      new Uint8Array([255, 216, 255, 192, 0, 20]),
      new Uint8Array([255, 216, 255, 192, 0, 0]),
      new Uint8Array(),
    ]) await expect(readImage(file(bytes))).rejects.toThrow('imageType');
  });
});
