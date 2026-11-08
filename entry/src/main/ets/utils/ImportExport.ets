import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { zlib } from '@kit.BasicServicesKit';
import { ImportResult, QuoteRef, RecordItem } from '../model/RecordItem';
import { Mood } from '../model/Mood';
import { importImageFile } from './ImageStore';
import { cryptoErrorCodeOf, decryptBackup, encryptBackup } from './BackupCrypto';

interface RawRecord {
  id?: string;
  timestamp?: number;
  date?: string;
  /** 我们自己的导出用 dateKey；导入时也要认，否则会全落到未归档 */
  dateKey?: string;
  content?: string;
  text?: string;
  moods?: number[];
  mood?: number;
  images?: string[];
  parentId?: string;
  quote?: QuoteRef;
}

interface ExportBundle {
  version?: number;
  exportedAt?: number;
  records?: RecordItem[];
}

export interface ImportOutcome {
  result: ImportResult;
  records: RecordItem[];
  unarchived: RecordItem[];
}

const DATE_PATTERN = /(\d{4})\s*[-年/.]\s*(\d{1,2})\s*[-月/.]\s*(\d{1,2})/;

function pad(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function stampForName(date: Date): string {
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}${pad(date.getHours())}${pad(
    date.getMinutes())}`;
}

function newId(): string {
  return `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
}

function fileNameOf(uri: string): string {
  const clean = uri.split('?')[0];
  const index = clean.lastIndexOf('/');
  return index >= 0 ? clean.substring(index + 1) : clean;
}

function copyUriToPath(uri: string, destPath: string): void {
  const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    fs.copyFileSync(src.fd, destPath, 0);
  } finally {
    fs.closeSync(src);
  }
}

function writeTextFile(path: string, content: string): void {
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file);
  }
}

function copyToUri(sourcePath: string, uri: string): void {
  const dest = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.copyFileSync(sourcePath, dest.fd, 0);
  } finally {
    fs.closeSync(dest);
  }
}

/** 加密备份的扩展名；普通导出仍是 .zip，导入时按扩展名分流，不靠用户描述 */
export const ENCRYPTED_SUFFIX = '.mlidbackup';

/** 最近一次导入的失败原因，供 UI 决定弹密码框还是直接提示；读完即清 */
let lastImportError: string = '';
export function takeImportError(): string {
  const value = lastImportError;
  lastImportError = '';
  return value;
}

function readFileBytes(path: string): Uint8Array {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const size = fs.statSync(path).size;
    const buffer = new ArrayBuffer(size);
    const read = fs.readSync(file.fd, buffer);
    return new Uint8Array(buffer).slice(0, read);
  } finally {
    fs.closeSync(file);
  }
}

function writeFileBytes(path: string, bytes: Uint8Array): void {
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  } finally {
    fs.closeSync(file);
  }
}

export function parseDateFromText(text: string): Date | null {
  const match = text.match(DATE_PATTERN);
  if (match === null) {
    return null;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  const date = new Date(year, month - 1, day, 20, 0, 0);
  if (isNaN(date.getTime())) {
    return null;
  }
  return date;
}

function uniqueImageNames(records: RecordItem[]): string[] {
  const names: string[] = [];
  for (let i = 0; i < records.length; i++) {
    const images = records[i].images;
    for (let j = 0; j < images.length; j++) {
      const name = images[j];
      if (name !== '' && !names.includes(name)) {
        names.push(name);
      }
    }
  }
  return names;
}

export async function exportAll(context: Context, records: RecordItem[], password: string = ''): Promise<boolean> {
  const workDir = `${context.cacheDir}/export_${Date.now()}`;
  const imagesDir = `${workDir}/images`;
  const zipPath = `${context.cacheDir}/shixu_${Date.now()}.zip`;
  try {
    fs.mkdirSync(workDir);
    fs.mkdirSync(imagesDir);
    const bundle: ExportBundle = {
      version: 1,
      exportedAt: Date.now(),
      records: records
    };
    writeTextFile(`${workDir}/records.json`, JSON.stringify(bundle));

    const names = uniqueImageNames(records);
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      if (name.startsWith('file://') || name.startsWith('/')) {
        continue;
      }
      const src = `${context.filesDir}/images/${name}`;
      if (fs.accessSync(src)) {
        fs.copyFileSync(src, `${imagesDir}/${name}`, 0);
      }
    }

    const zipOptions: zlib.Options = {};
    await zlib.compressFile(workDir, zipPath, zipOptions);

    // 有密码就再包一层 .mlidbackup：明文 ZIP 不落用户目录，避免“看起来加密了其实是明文”
    let outPath = zipPath;
    let suffix = '.zip';
    if (password !== '') {
      const zipBytes = readFileBytes(zipPath);
      const encrypted = await encryptBackup(zipBytes, password);
      outPath = `${context.cacheDir}/shixu_${Date.now()}${ENCRYPTED_SUFFIX}`;
      writeFileBytes(outPath, encrypted);
      suffix = ENCRYPTED_SUFFIX;
    }

    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`时叙导出_${stampForName(new Date())}${suffix}`];
    options.fileSuffixChoices = [suffix];
    const uris = await documentPicker.save(options);
    if (uris.length === 0) {
      return false;
    }
    copyToUri(outPath, uris[0]);
    return true;
  } catch (e) {
    return false;
  }
}

function parseJsonRecords(text: string): RawRecord[] {
  const parsed: Object = JSON.parse(text);
  const list: RawRecord[] = [];
  if (Array.isArray(parsed)) {
    const arr = parsed as RawRecord[];
    for (let i = 0; i < arr.length; i++) {
      if (arr[i] !== null && arr[i] !== undefined) {
        list.push(arr[i]);
      }
    }
    return list;
  }
  const bundle = parsed as ExportBundle;
  if (bundle.records !== undefined) {
    const arr = bundle.records as RawRecord[];
    for (let i = 0; i < arr.length; i++) {
      if (arr[i] !== null && arr[i] !== undefined) {
        list.push(arr[i]);
      }
    }
    return list;
  }
  const single = parsed as RawRecord;
  if (single.content !== undefined || single.text !== undefined) {
    list.push(single);
  }
  return list;
}

function findNamedEntry(dir: string, name: string): string {
  try {
    const names = fs.listFileSync(dir);
    for (let i = 0; i < names.length; i++) {
      if (names[i] === name) {
        return `${dir}/${names[i]}`;
      }
    }
    for (let i = 0; i < names.length; i++) {
      const sub = `${dir}/${names[i]}`;
      try {
        if (fs.statSync(sub).isDirectory()) {
          const nested = `${sub}/${name}`;
          if (fs.accessSync(nested)) {
            return nested;
          }
        }
      } catch (e) {
        // 忽略无法访问的条目
      }
    }
  } catch (e) {
    return '';
  }
  return '';
}

function moodValue(value: number): Mood {
  if (value >= 0 && value <= 5) {
    return value as Mood;
  }
  return Mood.NONE;
}

function normalizeRecord(raw: RawRecord, imageMap: Map<string, string>): RecordItem {
  let content = '';
  if (raw.content !== undefined) {
    content = String(raw.content);
  } else if (raw.text !== undefined) {
    content = String(raw.text);
  }

  let timestamp = 0;
  if (raw.timestamp !== undefined) {
    timestamp = Number(raw.timestamp);
    if (timestamp > 0 && timestamp < 100000000000) {
      timestamp = timestamp * 1000;
    }
  }
  if (timestamp <= 0 && raw.date !== undefined) {
    const parsed = parseDateFromText(String(raw.date));
    if (parsed !== null) {
      timestamp = parsed.getTime();
    }
  }
  if (timestamp <= 0) {
    const parsed = parseDateFromText(content);
    if (parsed !== null) {
      timestamp = parsed.getTime();
    }
  }

  const moods: Mood[] = [];
  if (raw.moods !== undefined && Array.isArray(raw.moods)) {
    for (let i = 0; i < raw.moods.length; i++) {
      const mood = moodValue(Number(raw.moods[i]));
      if (!moods.includes(mood)) {
        moods.push(mood);
      }
    }
  } else if (raw.mood !== undefined) {
    moods.push(moodValue(Number(raw.mood)));
  }
  if (moods.length === 0) {
    moods.push(Mood.NONE);
  }

  const images: string[] = [];
  if (raw.images !== undefined && Array.isArray(raw.images)) {
    for (let i = 0; i < raw.images.length; i++) {
      if (typeof raw.images[i] !== 'string') {
        continue;
      }
      const original = raw.images[i];
      const mapped = imageMap.get(original);
      images.push(mapped !== undefined ? mapped : original);
    }
  }

  const item: RecordItem = {
    id: '',
    timestamp: timestamp,
    content: content.trim(),
    moods: moods,
    images: images
  };
  // 备份里的自然日：dateKey（自家导出）> date（外部/旧格式）> 时间戳推算
  let dateKey = '';
  if (raw.dateKey !== undefined && String(raw.dateKey) !== '') {
    dateKey = String(raw.dateKey);
  } else if (raw.date !== undefined && String(raw.date) !== '') {
    const d = parseDateFromText(String(raw.date));
    if (d !== null) {
      dateKey = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    }
  }
  if (dateKey === '') {
    const d = new Date(timestamp);
    dateKey = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }
  item.dateKey = dateKey;
  if (raw.parentId !== undefined && String(raw.parentId) !== '') {
    item.parentId = String(raw.parentId);
  }
  if (raw.quote !== undefined && raw.quote !== null) {
    const quote = raw.quote;
    if (typeof quote.content === 'string') {
      item.quote = quote;
    }
  }
  return item;
}

function keyOf(timestamp: number, content: string): string {
  return `${timestamp}|${content.trim()}`;
}

function timestampOfParent(parentId: string, added: RecordItem[], existing: RecordItem[]): number {
  for (let i = 0; i < added.length; i++) {
    if (added[i].id === parentId) {
      return added[i].timestamp;
    }
  }
  for (let i = 0; i < existing.length; i++) {
    if (existing[i].id === parentId) {
      return existing[i].timestamp;
    }
  }
  return 0;
}

function mergeImport(rawList: RawRecord[], imageMap: Map<string, string>, existing: RecordItem[]): ImportOutcome {
  const result: ImportResult = {
    added: 0,
    skipped: 0,
    unarchived: 0,
    orphans: 0
  };
  const added: RecordItem[] = [];
  const unarchived: RecordItem[] = [];
  const existingKeys = new Set<string>();
  const existingIdByKey = new Map<string, string>();
  const localIds = new Set<string>();

  for (let i = 0; i < existing.length; i++) {
    const item = existing[i];
    const key = keyOf(item.timestamp, item.content);
    existingKeys.add(key);
    existingIdByKey.set(key, item.id);
    localIds.add(item.id);
  }

  const idMap = new Map<string, string>();
  const pendingAnnotations: RawRecord[] = [];

  for (let i = 0; i < rawList.length; i++) {
    const raw = rawList[i];
    if (raw.parentId !== undefined && String(raw.parentId) !== '') {
      pendingAnnotations.push(raw);
      continue;
    }
    const item = normalizeRecord(raw, imageMap);
    item.id = newId();
    if (item.timestamp <= 0) {
      unarchived.push(item);
      result.unarchived++;
      if (raw.id !== undefined) {
        idMap.set(String(raw.id), item.id);
      }
      continue;
    }
    const key = keyOf(item.timestamp, item.content);
    if (existingKeys.has(key)) {
      result.skipped++;
      const existingId = existingIdByKey.get(key);
      if (raw.id !== undefined && existingId !== undefined) {
        idMap.set(String(raw.id), existingId);
      }
      continue;
    }
    added.push(item);
    existingKeys.add(key);
    existingIdByKey.set(key, item.id);
    result.added++;
    if (raw.id !== undefined) {
      idMap.set(String(raw.id), item.id);
    }
  }

  for (let i = 0; i < pendingAnnotations.length; i++) {
    const raw = pendingAnnotations[i];
    const item = normalizeRecord(raw, imageMap);
    const oldParent = item.parentId !== undefined ? item.parentId : '';
    let newParent = idMap.get(oldParent);
    if (newParent === undefined && localIds.has(oldParent)) {
      newParent = oldParent;
    }
    if (newParent === undefined) {
      result.orphans++;
      continue;
    }
    item.parentId = newParent;
    if (item.timestamp <= 0) {
      item.timestamp = timestampOfParent(newParent, added, existing);
    }
    if (item.timestamp <= 0) {
      item.timestamp = Date.now();
    }
    item.id = newId();
    const key = keyOf(item.timestamp, item.content);
    if (existingKeys.has(key)) {
      result.skipped++;
      continue;
    }
    added.push(item);
    existingKeys.add(key);
    existingIdByKey.set(key, item.id);
    result.added++;
  }

  return { result: result, records: added, unarchived: unarchived };
}

/** 已选中的备份文件：加密备份可以先选文件、再补密码，避免让用户选两次 */
export interface PickedBackup {
  uri: string;
  fileName: string;
}

/** 只负责选文件，不做导入 */
export async function pickBackup(context: Context): Promise<PickedBackup | null> {
  const documentPicker = new picker.DocumentViewPicker(context);
  const options = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  options.fileSuffixFilters = ['.json', '.txt', '.md', '.zip', ENCRYPTED_SUFFIX];
  hilog.info(0x0000, 'MLIDImport', 'pick: before select');
  let uris: string[] = [];
  try {
    uris = await documentPicker.select(options);
    hilog.info(0x0000, 'MLIDImport', `pick: uris=${uris.length} ${JSON.stringify(uris)}`);
  } catch (e) {
    hilog.error(0x0000, 'MLIDImport', `pick: select threw ${(e as Error)?.message ?? JSON.stringify(e)}`);
    return null;
  }
  if (uris.length === 0) {
    hilog.warn(0x0000, 'MLIDImport', 'pick: cancelled or denied');
    return null;
  }
  const uri = uris[0];
  return { uri: uri, fileName: fileNameOf(uri) };
}

/** 导入已选中的备份文件；加密备份需要密码时返回 null 并置 takeImportError()='NEED_PASSWORD' */
export async function importBackup(context: Context, picked: PickedBackup, existing: RecordItem[],
  password: string = ''): Promise<ImportOutcome | null> {
  const uri = picked.uri;
  const fileName = picked.fileName;
  const lower = fileName.toLowerCase();
  const cachePath = `${context.cacheDir}/import_${Date.now()}_${fileName}`;
  const imageMap = new Map<string, string>();
  let rawList: RawRecord[] = [];

  try {
    hilog.info(0x0000, 'MLIDImport', `start uri=${uri} name=${fileName}`);
    copyUriToPath(uri, cachePath);
    hilog.info(0x0000, 'MLIDImport', `copied size=${fs.statSync(cachePath).size}`);

    // 加密容器先解出 ZIP 再走原流程；密码缺失或认证失败都不进入数据库
    let archivePath = cachePath;
    if (lower.endsWith(ENCRYPTED_SUFFIX)) {
      if (password === '') {
        lastImportError = 'NEED_PASSWORD';
        return null;
      }
      try {
        const fileBytes = readFileBytes(cachePath);
        const zipBytes = await decryptBackup(fileBytes, password);
        archivePath = `${context.cacheDir}/decrypted_${Date.now()}.zip`;
        writeFileBytes(archivePath, zipBytes);
      } catch (e) {
        const code = cryptoErrorCodeOf(e as Error);
        lastImportError = code === 'AUTH_FAILED' ? 'BAD_PASSWORD' : 'BROKEN_BACKUP';
        return null;
      }
    }

    if (lower.endsWith('.zip') || lower.endsWith(ENCRYPTED_SUFFIX)) {
      const outDir = `${context.cacheDir}/unzip_${Date.now()}`;
      fs.mkdirSync(outDir);
      const unzipOptions: zlib.Options = {};
      await zlib.decompressFile(archivePath, outDir, unzipOptions);
      const jsonPath = findNamedEntry(outDir, 'records.json');
      hilog.info(0x0000, 'MLIDImport', `unzipped jsonPath=${jsonPath}`);
      if (jsonPath !== '') {
        rawList = parseJsonRecords(fs.readTextSync(jsonPath));
      }
      const imagesDir = findNamedEntry(outDir, 'images');
      if (imagesDir !== '' && fs.statSync(imagesDir).isDirectory()) {
        const names = fs.listFileSync(imagesDir);
        for (let i = 0; i < names.length; i++) {
          const mapped = await importImageFile(context, `${imagesDir}/${names[i]}`, names[i]);
          imageMap.set(names[i], mapped);
        }
      }
    } else {
      const text = fs.readTextSync(cachePath);
      hilog.info(0x0000, 'MLIDImport', `text len=${text.length} suffix json=${lower.endsWith('.json')}`);
      if (lower.endsWith('.json')) {
        try {
          rawList = parseJsonRecords(text);
          hilog.info(0x0000, 'MLIDImport', `parsed=${rawList.length}`);
        } catch (e) {
          rawList = [];
          hilog.error(0x0000, 'MLIDImport', `parse fail ${JSON.stringify(e)}`);
        }
      }
      if (rawList.length === 0) {
        const trimmed = text.trim();
        if (trimmed !== '') {
          let timestamp = 0;
          const fromName = parseDateFromText(fileName);
          if (fromName !== null) {
            timestamp = fromName.getTime();
          } else {
            const fromText = parseDateFromText(trimmed);
            if (fromText !== null) {
              timestamp = fromText.getTime();
            }
          }
          const plain: RawRecord = {
            timestamp: timestamp,
            content: trimmed,
            moods: [Mood.NONE],
            images: []
          };
          rawList.push(plain);
        }
      }
    }
  } catch (e) {
    hilog.error(0x0000, 'MLIDImport', `thrown ${(e as Error)?.message ?? JSON.stringify(e)}`);
    return null;
  } finally {
    try {
      if (fs.accessSync(cachePath)) {
        fs.unlinkSync(cachePath);
      }
    } catch (e) {
      // 忽略清理失败
    }
  }

  hilog.info(0x0000, 'MLIDImport', `raw=${rawList.length} existing=${existing.length}`);
  const outcome = mergeImport(rawList, imageMap, existing);
  hilog.info(0x0000, 'MLIDImport', `merge result=${outcome.result} total=${outcome.records.length}`);
  return outcome;
}

/** 兼容旧调用：先选文件再导入；需要密码时返回 null，错误码从 takeImportError() 取 */
export async function importFromPicker(context: Context, existing: RecordItem[],
  password: string = ''): Promise<ImportOutcome | null> {
  const picked = await pickBackup(context);
  if (picked === null) {
    return null;
  }
  return await importBackup(context, picked, existing, password);
}

/**
 * 清理导入/导出留下的临时文件。
 * 这些文件只在一次导入/导出期间有用，结束后留着只会占空间，所以启动时清一次。
 */
export async function cleanupTempCache(context: Context): Promise<void> {
  try {
    const dir = context.cacheDir;
    if (!fs.accessSync(dir)) {
      return;
    }
    const names = fs.listFileSync(dir);
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      const isTemp = name.startsWith('import_') || name.startsWith('unzip_')
        || name.startsWith('decrypted_') || name.startsWith('export_');
      if (!isTemp) {
        continue;
      }
      try {
        fs.rmdirSync(`${dir}/${name}`);
      } catch (e) {
        try {
          fs.unlinkSync(`${dir}/${name}`);
        } catch (e2) {
          // 忽略单个失败
        }
      }
    }
  } catch (e) {
    // 缓存目录不存在时忽略
  }
}
