/**
 * RecordDb —— 记录仓储层（@kit.ArkData / relationalStore，API 26，Stage 模型）。
 *
 * 规格与代码的差异说明（以 RecordItem.ets 的真实类型为准）：
 * * 规格 6.3.1 的 records 没有引文快照列，但 RecordItem 有 `quote?: QuoteRef`；为不丢引文，
 *   records 增补 quote_record_id / quote_content / quote_image 三个可空列，其余列与 6.3.1 完全一致。
 * * 规格 6.3.3 的 image_id / content_hash 在 RecordItem.images（string[]，只有文件名）里没有对应数据：
 *   image_id 取文件名（ImageStore 生成的文件名本身唯一），content_hash 写 NULL，等图片管线补哈希后再回填。
 * * 按 2026-11-08 的迁移决策，未归档记录用 date_key IS NULL 表达，不再单独存储。
 *
 * 事务：写操作一律 beginTransaction → await 全部语句 → commit；任何一步失败先 rollBack 再原样抛出，
 * 保证「记录 / 情绪 / 图片」三张表要么一起可见、要么一起不可见（规格 6.3.4）。
 * 本类不做并发调度：调用方必须串行 await 写操作，否则两个事务会在同一条连接上交错。
 * 图片物理文件不在这里删除：规格要求数据库提交成功后再清理文件，由图片层按 contentHash 引用数处理。
 */
import { preferences, relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Mood } from '../model/Mood';
import { QuoteRef, RecordItem } from '../model/RecordItem';

const DB_NAME = 'mlid_records.db';
const SCHEMA_VERSION = 1;

const TABLE_RECORDS = 'records';
const TABLE_MOODS = 'record_moods';
const TABLE_IMAGES = 'record_images';

// 与 PreferencesStore.ets 用同一个 Preferences 库和 key；那边没有导出这些常量，只能在此重复声明。
const PREF_STORE = 'mlid_preferences';
const PREF_KEY_RECORDS = 'records';
const PREF_KEY_UNARCHIVED = 'unarchived';
const PREF_KEY_MIGRATED = 'recordsMigrated';

const SQL_CREATE_RECORDS = `CREATE TABLE IF NOT EXISTS ${TABLE_RECORDS} (
  id TEXT PRIMARY KEY NOT NULL,
  timestamp INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  date_key TEXT,
  is_backfill INTEGER NOT NULL DEFAULT 0,
  content TEXT NOT NULL,
  parent_id TEXT,
  quote_record_id TEXT,
  quote_content TEXT,
  quote_image TEXT
)`;

const SQL_CREATE_MOODS = `CREATE TABLE IF NOT EXISTS ${TABLE_MOODS} (
  record_id TEXT NOT NULL,
  mood TEXT NOT NULL,
  PRIMARY KEY (record_id, mood),
  FOREIGN KEY (record_id) REFERENCES ${TABLE_RECORDS}(id) ON DELETE CASCADE
)`;

const SQL_CREATE_IMAGES = `CREATE TABLE IF NOT EXISTS ${TABLE_IMAGES} (
  record_id TEXT NOT NULL,
  image_id TEXT NOT NULL,
  file_name TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  content_hash TEXT,
  PRIMARY KEY (record_id, image_id),
  FOREIGN KEY (record_id) REFERENCES ${TABLE_RECORDS}(id) ON DELETE CASCADE
)`;

// 规格 6.3.4 要求的四个索引：date_key、timestamp、parent_id、(date_key, timestamp)。
// 子表不另建索引：主键 (record_id, mood) / (record_id, image_id) 的最左列已经是 record_id。
const SQL_CREATE_INDEX_DATE_KEY = `CREATE INDEX IF NOT EXISTS idx_records_date_key ON ${TABLE_RECORDS}(date_key)`;
const SQL_CREATE_INDEX_TIMESTAMP = `CREATE INDEX IF NOT EXISTS idx_records_timestamp ON ${TABLE_RECORDS}(timestamp)`;
const SQL_CREATE_INDEX_PARENT_ID = `CREATE INDEX IF NOT EXISTS idx_records_parent_id ON ${TABLE_RECORDS}(parent_id)`;
const SQL_CREATE_INDEX_DATE_TS =
  `CREATE INDEX IF NOT EXISTS idx_records_date_key_timestamp ON ${TABLE_RECORDS}(date_key, timestamp)`;

const SQL_SELECT_RECORDS = `SELECT id, timestamp, updated_at, date_key, is_backfill, content, parent_id,
  quote_record_id, quote_content, quote_image FROM ${TABLE_RECORDS} ORDER BY timestamp ASC, id ASC`;
const SQL_SELECT_MOODS = `SELECT record_id, mood FROM ${TABLE_MOODS}
  ORDER BY record_id ASC, CAST(mood AS INTEGER) ASC`;
const SQL_SELECT_IMAGES = `SELECT record_id, file_name FROM ${TABLE_IMAGES}
  ORDER BY record_id ASC, sort_order ASC`;

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 旧数据补日期键时用本地自然日，和 AppStore.dateKeyOf 的口径保持一致 */
function dateKeyOfTimestamp(timestamp: number): string {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

function isEmptyId(value: string | undefined): boolean {
  return value === undefined || value === '';
}

/**
 * 旧 Preferences 的 JSON 里字段是运行时数据，类型不可信；这里重写一份与 PreferencesStore 同思路的归一化，
 * 不 import 它的私有函数。比原版多保留 dateKey / isBackfill / quote 的全部字段，迁移才不会丢信息。
 */
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
      if (typeof raw.images[i] === 'string' && raw.images[i] !== '') {
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
  if (typeof raw.dateKey === 'string' && raw.dateKey !== '') {
    item.dateKey = raw.dateKey;
  }
  if (raw.isBackfill === true) {
    item.isBackfill = true;
  }
  if (typeof raw.parentId === 'string' && raw.parentId !== '') {
    item.parentId = raw.parentId;
  }
  if (raw.quote !== undefined && raw.quote !== null) {
    const quoteRecordId = typeof raw.quote.recordId === 'string' ? raw.quote.recordId : '';
    const quoteContent = typeof raw.quote.content === 'string' ? raw.quote.content : '';
    const quoteImage = typeof raw.quote.image === 'string' ? raw.quote.image : '';
    if (quoteRecordId !== '' || quoteContent !== '') {
      item.quote = {
        recordId: quoteRecordId,
        content: quoteContent,
        image: quoteImage
      };
    }
  }
  return item;
}

/** 复制一条记录；keepDateKey 为 false 时丢弃日期键（未归档记录 = date_key IS NULL） */
function cloneRecord(item: RecordItem, keepDateKey: boolean): RecordItem {
  const copy: RecordItem = {
    id: item.id,
    timestamp: item.timestamp,
    content: item.content,
    moods: item.moods,
    images: item.images
  };
  if (keepDateKey && item.dateKey !== undefined) {
    copy.dateKey = item.dateKey;
  }
  if (item.updatedAt !== undefined) {
    copy.updatedAt = item.updatedAt;
  }
  if (item.isBackfill !== undefined) {
    copy.isBackfill = item.isBackfill;
  }
  if (item.parentId !== undefined) {
    copy.parentId = item.parentId;
  }
  if (item.quote !== undefined) {
    copy.quote = item.quote;
  }
  return copy;
}

/** 原样读旧键的 JSON 字符串；空键返回 "[]"，与 Preferences 的缺省值一致 */
async function rawJsonOf(pref: preferences.Preferences, key: string): Promise<string> {
  const value: preferences.ValueType = await pref.get(key, '[]');
  return typeof value === 'string' ? value : '[]';
}

/** 迁移前把原始 JSON 落一份到应用私有目录：这是唯一的回滚依据，不能只指望旧键一直在 */
function writeMigrationBackup(context: Context, archived: string, unarchived: string): void {
  const path = `${context.filesDir}/migration-backup-${Date.now()}.json`;
  const payload = `{"records":${archived},"unarchived":${unarchived}}`;
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, payload);
  } finally {
    fs.closeSync(file);
  }
}

async function readRecordsFromPreferences(
  pref: preferences.Preferences,
  key: string
): Promise<RecordItem[]> {
  const json = await rawJsonOf(pref, key);
  try {
    const parsed: Object = JSON.parse(json);
    if (!Array.isArray(parsed)) {
      return [];
    }
    const source = parsed as RecordItem[];
    const list: RecordItem[] = [];
    for (let i = 0; i < source.length; i++) {
      try {
        list.push(normalizeRecord(source[i]));
      } catch (e) {
        // 跳过损坏的单条，避免整次搬迁失败
      }
    }
    return list;
  } catch (e) {
    return [];
  }
}

async function ensureSchema(store: relationalStore.RdbStore): Promise<void> {
  if (store.version === 0) {
    // 只有建表放在事务外：DDL 失败时 version 仍为 0，下次启动靠 IF NOT EXISTS 幂等重试。
    await store.executeSql(SQL_CREATE_RECORDS);
    await store.executeSql(SQL_CREATE_MOODS);
    await store.executeSql(SQL_CREATE_IMAGES);
    await store.executeSql(SQL_CREATE_INDEX_DATE_KEY);
    await store.executeSql(SQL_CREATE_INDEX_TIMESTAMP);
    await store.executeSql(SQL_CREATE_INDEX_PARENT_ID);
    await store.executeSql(SQL_CREATE_INDEX_DATE_TS);
    store.version = SCHEMA_VERSION;
    return;
  }
  if (store.version < SCHEMA_VERSION) {
    // 目前只有 v1；未来的字段变更在这里逐版 ADD COLUMN / 回填，禁止 deleteRdbStore 后重建（规格 6.3.4）。
    store.version = SCHEMA_VERSION;
  }
  // store.version > SCHEMA_VERSION：旧程序打开了更新版本写过的库，保持原样、不动数据，由上层决定是否提示。
}

export class RecordDb {
  private store: relationalStore.RdbStore;
  private closed: boolean = false;
  // getRdbStore 对同名库重复调用是禁止的，这里缓存单例，open 幂等。
  private static shared: RecordDb | null = null;
  // 打开过程中的 Promise：两个页面同时第一次取库时合并成一次 getRdbStore，避免同名库被打开两次。
  private static opening: Promise<RecordDb> | null = null;

  private constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  static async open(context: Context): Promise<RecordDb> {
    if (RecordDb.shared !== null) {
      return RecordDb.shared;
    }
    if (RecordDb.opening === null) {
      RecordDb.opening = RecordDb.create(context);
    }
    const pending = RecordDb.opening;
    try {
      return await pending;
    } finally {
      if (RecordDb.opening === pending) {
        RecordDb.opening = null;
      }
    }
  }

  private static async create(context: Context): Promise<RecordDb> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      // 日记属于个人敏感数据：取 S3（泄漏影响大）。该级别建库后不宜改，改动需重新评估。
      securityLevel: relationalStore.SecurityLevel.S3
    };
    const store = await relationalStore.getRdbStore(context, config);
    await ensureSchema(store);
    const db = new RecordDb(store);
    RecordDb.shared = db;
    return db;
  }

  /** 全部记录（含批注）按 timestamp 升序；批注靠 parentId 关联，dateKey 缺省即未归档 */
  async loadRecords(): Promise<RecordItem[]> {
    const list: RecordItem[] = [];
    const byId = new Map<string, RecordItem>();

    const recordSet = await this.store.querySql(SQL_SELECT_RECORDS);
    try {
      const idIndex = recordSet.getColumnIndex('id');
      const timestampIndex = recordSet.getColumnIndex('timestamp');
      const updatedAtIndex = recordSet.getColumnIndex('updated_at');
      const dateKeyIndex = recordSet.getColumnIndex('date_key');
      const isBackfillIndex = recordSet.getColumnIndex('is_backfill');
      const contentIndex = recordSet.getColumnIndex('content');
      const parentIdIndex = recordSet.getColumnIndex('parent_id');
      const quoteIdIndex = recordSet.getColumnIndex('quote_record_id');
      const quoteContentIndex = recordSet.getColumnIndex('quote_content');
      const quoteImageIndex = recordSet.getColumnIndex('quote_image');

      while (recordSet.goToNextRow()) {
        const id = recordSet.getString(idIndex);
        const item: RecordItem = {
          id: id,
          timestamp: recordSet.getLong(timestampIndex),
          updatedAt: recordSet.getLong(updatedAtIndex),
          isBackfill: recordSet.getLong(isBackfillIndex) === 1,
          content: recordSet.getString(contentIndex),
          moods: [],
          images: []
        };
        if (!recordSet.isColumnNull(dateKeyIndex)) {
          item.dateKey = recordSet.getString(dateKeyIndex);
        }
        if (!recordSet.isColumnNull(parentIdIndex)) {
          item.parentId = recordSet.getString(parentIdIndex);
        }
        if (!recordSet.isColumnNull(quoteIdIndex)) {
          const quoteContent = recordSet.isColumnNull(quoteContentIndex)
            ? ''
            : recordSet.getString(quoteContentIndex);
          const quoteImage = recordSet.isColumnNull(quoteImageIndex)
            ? ''
            : recordSet.getString(quoteImageIndex);
          item.quote = {
            recordId: recordSet.getString(quoteIdIndex),
            content: quoteContent,
            image: quoteImage
          };
        }
        list.push(item);
        byId.set(id, item);
      }
    } finally {
      recordSet.close();
    }

    if (list.length === 0) {
      return list;
    }

    // 情绪与图片分两次查再回填：比三表 JOIN 好读，也避免一行记录被 JOIN 拆成多行后去重。
    const moodSet = await this.store.querySql(SQL_SELECT_MOODS);
    try {
      const recordIdIndex = moodSet.getColumnIndex('record_id');
      const moodIndex = moodSet.getColumnIndex('mood');
      while (moodSet.goToNextRow()) {
        const item = byId.get(moodSet.getString(recordIdIndex));
        if (item === undefined) {
          continue;
        }
        const value = Number(moodSet.getString(moodIndex));
        if (value >= 0 && value <= 5 && !item.moods.includes(value as Mood)) {
          item.moods.push(value as Mood);
        }
      }
    } finally {
      moodSet.close();
    }

    const imageSet = await this.store.querySql(SQL_SELECT_IMAGES);
    try {
      const recordIdIndex = imageSet.getColumnIndex('record_id');
      const fileNameIndex = imageSet.getColumnIndex('file_name');
      while (imageSet.goToNextRow()) {
        const item = byId.get(imageSet.getString(recordIdIndex));
        if (item === undefined) {
          continue;
        }
        const fileName = imageSet.getString(fileNameIndex);
        if (fileName !== '') {
          item.images.push(fileName);
        }
      }
    } finally {
      imageSet.close();
    }

    return list;
  }

  /** 单条写入（新增或编辑）：记录行 + 情绪 + 图片在同一事务里提交 */
  async upsert(item: RecordItem): Promise<void> {
    this.store.beginTransaction();
    try {
      await this.writeItem(item);
      this.store.commit();
    } catch (e) {
      try {
        this.store.rollBack();
      } catch (rollbackError) {
        // 回滚失败不能盖掉原始错误
      }
      throw e as Error;
    }
  }

  /** 删除主记录与其批注；批注的情绪/图片一并清掉，顺序是先子表再 records，外键开不开都成立 */
  async remove(id: string): Promise<void> {
    this.store.beginTransaction();
    try {
      await this.store.executeSql(
        `DELETE FROM ${TABLE_MOODS} WHERE record_id = ? OR record_id IN (SELECT id FROM ${TABLE_RECORDS} WHERE parent_id = ?)`,
        [id, id]
      );
      await this.store.executeSql(
        `DELETE FROM ${TABLE_IMAGES} WHERE record_id = ? OR record_id IN (SELECT id FROM ${TABLE_RECORDS} WHERE parent_id = ?)`,
        [id, id]
      );
      await this.store.executeSql(`DELETE FROM ${TABLE_RECORDS} WHERE parent_id = ?`, [id]);
      await this.store.executeSql(`DELETE FROM ${TABLE_RECORDS} WHERE id = ?`, [id]);
      this.store.commit();
    } catch (e) {
      try {
        this.store.rollBack();
      } catch (rollbackError) {
        // 同上
      }
      throw e as Error;
    }
  }

  /** 导入 / 清空：整表替换，单事务；items 为空即清空 */
  async replaceAll(items: RecordItem[]): Promise<void> {
    this.store.beginTransaction();
    try {
      await this.store.executeSql(`DELETE FROM ${TABLE_MOODS}`);
      await this.store.executeSql(`DELETE FROM ${TABLE_IMAGES}`);
      await this.store.executeSql(`DELETE FROM ${TABLE_RECORDS}`);

      // 两轮写入：先父记录再批注。运行库若启用外键，批注先写会因找不到父行而失败。
      for (let i = 0; i < items.length; i++) {
        if (isEmptyId(items[i].parentId)) {
          await this.writeItem(items[i]);
        }
      }
      for (let i = 0; i < items.length; i++) {
        if (!isEmptyId(items[i].parentId)) {
          await this.writeItem(items[i]);
        }
      }
      this.store.commit();
    } catch (e) {
      try {
        this.store.rollBack();
      } catch (rollbackError) {
        // 同上
      }
      throw e as Error;
    }
  }

  async close(): Promise<void> {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      await this.store.close();
    } finally {
      if (RecordDb.shared === this) {
        RecordDb.shared = null;
      }
    }
  }

  /**
   * 一次性把 Preferences 里的旧 JSON 搬进数据库：库为空且旧数据存在时导入，返回导入条数。
   * 旧 JSON 保留不删（回滚依据），成功后写 recordsMigrated=1 防止重复导入。
   */
  static async migrateFromPreferences(context: Context): Promise<number> {
    const pref = await preferences.getPreferences(context, PREF_STORE);
    const flag: preferences.ValueType = await pref.get(PREF_KEY_MIGRATED, 0);
    if (Number(flag) === 1) {
      return 0;
    }

    const db = await RecordDb.open(context);
    if ((await db.countRecords()) > 0) {
      // 库里已有数据，说明不是首次启动，不覆盖；也不写标记，保留人工核对的余地。
      return 0;
    }

    const rawArchived = await rawJsonOf(pref, PREF_KEY_RECORDS);
    const rawUnarchived = await rawJsonOf(pref, PREF_KEY_UNARCHIVED);
    // 先备后搬：原始 JSON 原样落盘，出问题还能人工核对，不依赖旧键是否被覆盖
    writeMigrationBackup(context, rawArchived, rawUnarchived);

    const archived = await readRecordsFromPreferences(pref, PREF_KEY_RECORDS);
    const unarchived = await readRecordsFromPreferences(pref, PREF_KEY_UNARCHIVED);
    const merged: RecordItem[] = [];
    const seenIds = new Set<string>();

    for (let i = 0; i < archived.length; i++) {
      // 旧库只靠“在哪个数组里”区分归档；ImportExport 导入的记录没有 dateKey，直接搬会被当成未归档。
      // 这里按 timestamp 的本地自然日补键（dateKey 语义是“所属自然日”，补的是事实值，不是猜业务状态）。
      const item = cloneRecord(archived[i], true);
      if (isEmptyId(item.dateKey) && item.timestamp > 0) {
        item.dateKey = dateKeyOfTimestamp(item.timestamp);
      }
      if (seenIds.has(item.id)) {
        continue;
      }
      seenIds.add(item.id);
      merged.push(item);
    }

    for (let i = 0; i < unarchived.length; i++) {
      // 未归档 = date_key IS NULL，无论旧 JSON 里写了什么日期键都丢掉。
      const item = cloneRecord(unarchived[i], false);
      if (seenIds.has(item.id)) {
        continue;
      }
      seenIds.add(item.id);
      merged.push(item);
    }

    await db.replaceAll(merged);
    // 搬完必须核对条数：旧版就是没核这一条，把“读到 0 条”当成功，直接落标记，数据看着像丢了。
    const written = await db.countRecords();
    if (written !== merged.length) {
      throw new Error(`records migration mismatch: parsed ${merged.length}, stored ${written}`);
    }
    // 只有条数对得上才落标记；失败则下次启动重试，replaceAll 幂等。
    await pref.put(PREF_KEY_MIGRATED, 1);
    await pref.flush();
    return merged.length;
  }

  private async countRecords(): Promise<number> {
    const resultSet = await this.store.querySql(`SELECT COUNT(*) AS total FROM ${TABLE_RECORDS}`);
    try {
      if (!resultSet.goToNextRow()) {
        return 0;
      }
      return resultSet.getLong(resultSet.getColumnIndex('total'));
    } finally {
      resultSet.close();
    }
  }

  /** 写一行记录并整体替换它的情绪/图片；必须由调用方包在事务里 */
  private async writeItem(item: RecordItem): Promise<void> {
    // 情绪、图片是整体替换语义：先删后插，不做差量合并。
    await this.store.executeSql(`DELETE FROM ${TABLE_MOODS} WHERE record_id = ?`, [item.id]);
    await this.store.executeSql(`DELETE FROM ${TABLE_IMAGES} WHERE record_id = ?`, [item.id]);

    const updatedAt = item.updatedAt !== undefined ? item.updatedAt : Date.now();
    const dateKey: string | null =
      item.dateKey !== undefined && item.dateKey !== '' ? item.dateKey : null;
    const parentId: string | null =
      item.parentId !== undefined && item.parentId !== '' ? item.parentId : null;
    const quote: QuoteRef | undefined = item.quote;
    const quoteRecordId: string | null = quote !== undefined ? quote.recordId : null;
    const quoteContent: string | null = quote !== undefined ? quote.content : null;
    const quoteImage: string | null = quote !== undefined ? quote.image : null;

    // 键名用标识符写法，避免 ArkTS 对“字符串字面量属性名”的限制；列名本身就是合法标识符。
    const values: relationalStore.ValuesBucket = {
      id: item.id,
      timestamp: item.timestamp,
      updated_at: updatedAt,
      date_key: dateKey,
      is_backfill: item.isBackfill === true ? 1 : 0,
      content: item.content,
      parent_id: parentId,
      quote_record_id: quoteRecordId,
      quote_content: quoteContent,
      quote_image: quoteImage
    };

    // 不能用 INSERT OR REPLACE：REPLACE 先删旧行，外键级联开启时会把这条记录的批注一起删掉。
    const predicates = new relationalStore.RdbPredicates(TABLE_RECORDS);
    predicates.equalTo('id', item.id);
    const affected = await this.store.update(values, predicates);
    if (affected === 0) {
      await this.store.insert(TABLE_RECORDS, values);
    }

    // mood 列存枚举的数值文本：Mood 是数字枚举，存名字还要反向映射，存数值最直接且无损。
    const seenMoods = new Set<string>();
    for (let i = 0; i < item.moods.length; i++) {
      const mood = `${item.moods[i]}`;
      if (seenMoods.has(mood)) {
        continue;
      }
      seenMoods.add(mood);
      const moodValues: relationalStore.ValuesBucket = {
        record_id: item.id,
        mood: mood
      };
      await this.store.insert(TABLE_MOODS, moodValues);
    }

    // RecordItem.images 是文件名的有序数组；image_id 直接用文件名，保证同一文件在同一记录里只占一行。
    const seenImages = new Set<string>();
    let sortOrder = 0;
    for (let i = 0; i < item.images.length; i++) {
      const fileName = item.images[i];
      if (fileName === '' || seenImages.has(fileName)) {
        continue;
      }
      seenImages.add(fileName);
      const imageValues: relationalStore.ValuesBucket = {
        record_id: item.id,
        image_id: fileName,
        file_name: fileName,
        sort_order: sortOrder,
        // 暂无哈希来源（RecordItem 不带 contentHash），先留 NULL，图片管线接入后回填。
        content_hash: null
      };
      await this.store.insert(TABLE_IMAGES, imageValues);
      sortOrder++;
    }
  }
}
