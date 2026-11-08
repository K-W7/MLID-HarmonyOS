import { preferences } from '@kit.ArkData';
import { QuoteRef, RecordItem } from '../model/RecordItem';
import { Mood } from '../model/Mood';
import { AppSettings, createDefaultSettings, normalizeSettings } from '../model/AppSettings';

const STORE_NAME = 'mlid_preferences';
const KEY_RECORDS = 'records';
const KEY_UNARCHIVED = 'unarchived';
const KEY_DRAFT_INDEX = 'draft_index';
const KEY_DRAFT_PREFIX = 'draft_';
const KEY_SETTINGS = 'settings';

let storeInstance: preferences.Preferences | null = null;

async function getStore(context: Context): Promise<preferences.Preferences> {
  if (storeInstance) {
    return storeInstance;
  }
  storeInstance = await preferences.getPreferences(context, STORE_NAME);
  return storeInstance;
}

function asString(val: preferences.ValueType): string {
  if (typeof val === 'string') {
    return val;
  }
  return String(val);
}

function normalizeRecord(raw: RecordItem): RecordItem {
  const id = typeof raw.id === 'string' && raw.id !== ''
    ? raw.id
    : `rec_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
  const content = typeof raw.content === 'string' ? raw.content : '';
  const timestamp = typeof raw.timestamp === 'number' ? raw.timestamp : 0;

  const moods: Mood[] = [];
  if (Array.isArray(raw.moods)) {
    for (let i = 0; i < raw.moods.length; i++) {
      const value = Number(raw.moods[i]);
      if (value >= 0 && value <= 5 && !moods.includes(value as Mood)) {
        moods.push(value as Mood);
      }
    }
  }

  const images: string[] = [];
  if (Array.isArray(raw.images)) {
    for (let i = 0; i < raw.images.length; i++) {
      if (typeof raw.images[i] === 'string') {
        images.push(raw.images[i]);
      }
    }
  }

  const item: RecordItem = {
    id: id,
    timestamp: timestamp,
    content: content,
    moods: moods,
    images: images
  };
  if (typeof raw.updatedAt === 'number') {
    item.updatedAt = raw.updatedAt;
  }
  if (typeof raw.parentId === 'string' && raw.parentId !== '') {
    item.parentId = raw.parentId;
  }
  if (raw.quote !== undefined && raw.quote !== null) {
    const quote: QuoteRef = raw.quote;
    if (typeof quote.content === 'string') {
      item.quote = quote;
    }
  }
  return item;
}

function normalizeList(parsed: RecordItem[]): RecordItem[] {
  const list: RecordItem[] = [];
  for (let i = 0; i < parsed.length; i++) {
    try {
      list.push(normalizeRecord(parsed[i]));
    } catch (e) {
      // 跳过损坏的单条记录，避免整库无法读取
    }
  }
  return list;
}

export async function loadRecords(context: Context): Promise<RecordItem[]> {
  const store = await getStore(context);
  const json = asString(store.getSync(KEY_RECORDS, '[]'));
  try {
    const parsed: Object = JSON.parse(json);
    return normalizeList(parsed as RecordItem[]);
  } catch (e) {
    return [];
  }
}

export async function saveRecords(context: Context, records: RecordItem[]): Promise<void> {
  const store = await getStore(context);
  await store.put(KEY_RECORDS, JSON.stringify(records));
  await store.flush();
}

export async function loadUnarchived(context: Context): Promise<RecordItem[]> {
  const store = await getStore(context);
  const json = asString(store.getSync(KEY_UNARCHIVED, '[]'));
  try {
    const parsed: Object = JSON.parse(json);
    return normalizeList(parsed as RecordItem[]);
  } catch (e) {
    return [];
  }
}

export async function saveUnarchived(context: Context, records: RecordItem[]): Promise<void> {
  const store = await getStore(context);
  await store.put(KEY_UNARCHIVED, JSON.stringify(records));
  await store.flush();
}

/** 草稿按 dateKey / 记录 id 分别保存，索引里只记 key，避免整表读写 */
export async function saveDraftValue(context: Context, draftKey: string, json: string): Promise<void> {
  const store = await getStore(context);
  await store.put(`${KEY_DRAFT_PREFIX}${draftKey}`, json);
  const index = await loadDraftKeys(context);
  if (!index.includes(draftKey)) {
    index.push(draftKey);
    await store.put(KEY_DRAFT_INDEX, JSON.stringify(index));
  }
  await store.flush();
}

export async function loadDraftValue(context: Context, draftKey: string): Promise<string> {
  const store = await getStore(context);
  const value = store.getSync(`${KEY_DRAFT_PREFIX}${draftKey}`, '');
  return typeof value === 'string' ? value : '';
}

export async function deleteDraftValue(context: Context, draftKey: string): Promise<void> {
  const store = await getStore(context);
  await store.delete(`${KEY_DRAFT_PREFIX}${draftKey}`);
  const index = await loadDraftKeys(context);
  const next: string[] = [];
  for (let i = 0; i < index.length; i++) {
    if (index[i] !== draftKey) {
      next.push(index[i]);
    }
  }
  await store.put(KEY_DRAFT_INDEX, JSON.stringify(next));
  await store.flush();
}

async function loadDraftKeys(context: Context): Promise<string[]> {
  const store = await getStore(context);
  const json = asString(store.getSync(KEY_DRAFT_INDEX, '[]'));
  try {
    const parsed: Object = JSON.parse(json);
    const list: string[] = [];
    const raw = parsed as string[];
    if (Array.isArray(raw)) {
      for (let i = 0; i < raw.length; i++) {
        if (typeof raw[i] === 'string') {
          list.push(raw[i]);
        }
      }
    }
    return list;
  } catch (e) {
    return [];
  }
}

async function clearAllDrafts(context: Context): Promise<void> {
  const store = await getStore(context);
  const index = await loadDraftKeys(context);
  for (let i = 0; i < index.length; i++) {
    await store.delete(`${KEY_DRAFT_PREFIX}${index[i]}`);
  }
  await store.delete(KEY_DRAFT_INDEX);
  await store.flush();
}

export async function loadSettings(context: Context): Promise<AppSettings> {
  const store = await getStore(context);
  const json = asString(store.getSync(KEY_SETTINGS, ''));
  if (json === '') {
    return createDefaultSettings();
  }
  try {
    const parsed: AppSettings = JSON.parse(json) as AppSettings;
    return normalizeSettings(parsed);
  } catch (e) {
    return createDefaultSettings();
  }
}

export async function saveSettings(context: Context, settings: AppSettings): Promise<void> {
  const store = await getStore(context);
  await store.put(KEY_SETTINGS, JSON.stringify(settings));
  await store.flush();
}

/** 清空记录与未归档数据，保留设置 */
export async function clearRecords(context: Context): Promise<void> {
  const store = await getStore(context);
  await store.delete(KEY_RECORDS);
  await store.delete(KEY_UNARCHIVED);
  await clearAllDrafts(context);
  await store.flush();
}

/** 删除全部设置，用于重置应用 */
export async function deleteSettings(context: Context): Promise<void> {
  const store = await getStore(context);
  await store.delete(KEY_SETTINGS);
  await store.flush();
}


/**
 * 同步读出应用主题（0 跟随系统 / 1 浅色 / 2 深色）。
 * 启动页第一帧就要知道主题，不能等异步 init；这里直接开 Preferences 读一次。
 */
export function peekThemeMode(context: Context): number {
  try {
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    const json = asString(store.getSync(KEY_SETTINGS, ''));
    if (json === '') {
      return 0;
    }
    const parsed = JSON.parse(json) as AppSettings;
    if (parsed !== null && parsed.themeMode !== undefined) {
      return parsed.themeMode;
    }
    return 0;
  } catch (e) {
    return 0;
  }
}
