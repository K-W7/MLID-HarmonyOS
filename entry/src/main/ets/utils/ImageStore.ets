import { fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';

/** 压缩后长边上限（规格 6.7：长边 1080） */
const MAX_EDGE = 1080;
/** JPEG 编码质量 */
const JPEG_QUALITY = 85;

function extensionOf(uri: string): string {
  const match = uri.match(/\.([a-zA-Z0-9]+)(?:\?|$)/);
  if (match !== null) {
    return match[1].toLowerCase();
  }
  return 'jpg';
}

export function imageDir(context: Context): string {
  const dir = `${context.filesDir}/images`;
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir);
  }
  return dir;
}

/** 从系统相册选择器选图，不申请存储权限 */
export async function pickImageUris(maxCount: number): Promise<string[]> {
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = maxCount;
  const photoPicker = new photoAccessHelper.PhotoViewPicker();
  const result = await photoPicker.select(options);
  return result.photoUris;
}

/** EXIF 方向值 → 需要旋转的角度（镜像类不使用，只做旋转，避免画面翻转） */
function angleOfOrientation(orientation: number): number {
  if (orientation === 3 || orientation === 4) {
    return 180;
  }
  if (orientation === 5 || orientation === 6) {
    return 90;
  }
  if (orientation === 7 || orientation === 8) {
    return 270;
  }
  return 0;
}

/**
 * 图片处理管线：解码 → 按 EXIF 方向旋转 → 长边压到 1080 → 重编码 JPEG。
 * 重编码天然剥离 EXIF（含拍摄地点等敏感信息），也统一了格式（HEIF 也能进来）。
 * 任何一步失败都退回原图拷贝，保证“选得进来”比“压得漂亮”优先。
 */
async function processToJpeg(srcFd: number, destPath: string): Promise<boolean> {
  let source: image.ImageSource | null = null;
  let pixelMap: image.PixelMap | null = null;
  let packer: image.ImagePacker | null = null;
  try {
    source = image.createImageSource(srcFd);
    const info = await source.getImageInfo();
    if (info.size.width <= 0 || info.size.height <= 0) {
      return false;
    }
    let orientation = 1;
    try {
      const raw = await source.getImageProperty(image.PropertyKey.ORIENTATION);
      const parsed = Number(raw);
      if (!Number.isNaN(parsed)) {
        orientation = parsed;
      }
    } catch (e) {
      // 没有 EXIF 方向时按 1（正常方向）处理
    }

    const longest = Math.max(info.size.width, info.size.height);
    const scale = longest > MAX_EDGE ? MAX_EDGE / longest : 1;
    const decodeOptions: image.DecodingOptions = {
      desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale))
      }
    };
    pixelMap = await source.createPixelMap(decodeOptions);

    const angle = angleOfOrientation(orientation);
    if (angle !== 0) {
      await pixelMap.rotate(angle);
    }

    packer = image.createImagePacker();
    const out = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const options: image.PackingOption = { format: 'image/jpeg', quality: JPEG_QUALITY };
      await packer.packToFile(pixelMap, out.fd, options);
    } finally {
      fs.closeSync(out);
    }
    return true;
  } catch (e) {
    return false;
  } finally {
    if (pixelMap !== null) {
      pixelMap.release();
    }
    if (source !== null) {
      source.release();
    }
    if (packer !== null) {
      packer.release();
    }
  }
}

/** 动图（GIF）不能转 JPEG，否则会变静图；这类格式原样保留 */
async function isAnimatedFormat(srcFd: number): Promise<boolean> {
  let source: image.ImageSource | null = null;
  try {
    source = image.createImageSource(srcFd);
    const info = await source.getImageInfo();
    return info.mimeType === 'image/gif';
  } catch (e) {
    return false;
  } finally {
    if (source !== null) {
      source.release();
    }
  }
}

/** 把相册 URI 处理并写进沙箱：静态图压成 JPEG，动图原样保留 */
export async function copyUriToSandbox(context: Context, uri: string): Promise<string> {
  const dir = imageDir(context);
  const name = `img_${Date.now()}_${Math.floor(Math.random() * 10000)}.jpg`;
  const dest = `${dir}/${name}`;
  const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    // 动图原样拷贝，保持 .gif 扩展名与动画
    if (await isAnimatedFormat(src.fd)) {
      const gifName = `img_${Date.now()}_${Math.floor(Math.random() * 10000)}.gif`;
      fs.copyFileSync(src.fd, `${dir}/${gifName}`, 0);
      return gifName;
    }
    const ok = await processToJpeg(src.fd, dest);
    if (!ok) {
      // 兜底：处理失败就原样拷贝，扩展名跟着原图
      const fallbackName = `img_${Date.now()}_${Math.floor(Math.random() * 10000)}.${extensionOf(uri)}`;
      fs.copyFileSync(src.fd, `${dir}/${fallbackName}`, 0);
      return fallbackName;
    }
    return name;
  } finally {
    fs.closeSync(src);
  }
}

export async function pickAndStoreImages(context: Context, maxCount: number): Promise<string[]> {
  const uris = await pickImageUris(maxCount);
  const names: string[] = [];
  for (let i = 0; i < uris.length; i++) {
    try {
      const stored = await copyUriToSandbox(context, uris[i]);
      if (stored !== '') {
        names.push(stored);
      }
    } catch (e) {
      // 单张失败不影响其它图片
    }
  }
  return names;
}

/** 记录里存文件名，展示时还原为沙箱 URI */
export function resolveImageUri(context: Context, name: string): string {
  if (name === '') {
    return '';
  }
  if (name.startsWith('file://') || name.startsWith('/')) {
    return name;
  }
  return `file://${imageDir(context)}/${name}`;
}

export function clearAllImages(context: Context): void {
  const dir = imageDir(context);
  try {
    const names = fs.listFileSync(dir);
    for (let i = 0; i < names.length; i++) {
      try {
        fs.unlinkSync(`${dir}/${names[i]}`);
      } catch (e) {
        // 单个文件删除失败时继续
      }
    }
  } catch (e) {
    // 目录不存在时忽略
  }
}

export function deleteSandboxImage(context: Context, name: string): void {
  if (name === '' || name.startsWith('file://') || name.startsWith('/')) {
    return;
  }
  const path = `${imageDir(context)}/${name}`;
  try {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  } catch (e) {
    // 图片不存在时忽略
  }
}

/** 导入备份时把图片走同一条管线处理，保证与手工选图一致 */
export async function importImageFile(context: Context, sourcePath: string,
  originalName: string): Promise<string> {
  const dir = imageDir(context);
  const name = `img_${Date.now()}_${Math.floor(Math.random() * 10000)}.jpg`;
  const dest = `${dir}/${name}`;
  let src: fs.File | null = null;
  try {
    src = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
    // 导入时同样保留动图
    if (await isAnimatedFormat(src.fd)) {
      const gifName = `img_${Date.now()}_${Math.floor(Math.random() * 10000)}.gif`;
      fs.copyFileSync(src.fd, `${dir}/${gifName}`, 0);
      return gifName;
    }
    const ok = await processToJpeg(src.fd, dest);
    if (!ok) {
      const dot = originalName.lastIndexOf('.');
      const ext = dot >= 0 ? originalName.substring(dot + 1) : 'jpg';
      const fallbackName = `img_${Date.now()}_${Math.floor(Math.random() * 10000)}.${ext}`;
      fs.copyFileSync(src.fd, `${dir}/${fallbackName}`, 0);
      return fallbackName;
    }
    return name;
  } catch (e) {
    return originalName;
  } finally {
    if (src !== null) {
      fs.closeSync(src);
    }
  }
}
