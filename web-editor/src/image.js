import { DocumentError } from './archive.js';
import { rasterInfo } from './media-source.js';

export async function readImage(file) {
  if (file.size > 8 * 1024 * 1024) throw new DocumentError('imageSize');
  const bytes = new Uint8Array(await file.arrayBuffer());
  let info;
  try { info = rasterInfo(bytes); }
  catch (error) {
    if (!(error instanceof DocumentError)) throw error;
    throw new DocumentError(error.code === 'mediaBudget' ? 'imageSize' : 'imageType');
  }
  if (!['png', 'jpeg'].includes(info.type)) throw new DocumentError('imageType');
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
