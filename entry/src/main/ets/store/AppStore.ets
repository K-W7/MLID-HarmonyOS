import { DraftPayload, QuoteRef, RecordItem } from '../model/RecordItem';
import { AppSettings, createDefaultSettings, DEFAULT_MOOD_LAST } from '../model/AppSettings';
import { Mood } from '../model/Mood';
import { clearAllImages } from '../utils/ImageStore';
import { RecordDb } from '../data/RecordDb';
import {
  deleteDraftValue,
  deleteSettings,
  loadDraftValue,
  loadSettings,
  saveDraftValue,
  saveSettings
} from './PreferencesStore';

function newId(): string {
  return `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
}

function sameDay(timestamp: number, year: number, month: number, day: number): boolean {
  const d = new Date(timestamp);
  return d.getFullYear() === year && d.getMonth() + 1 === month && d.getDate() === day;
}

function timestampOfDate(year: number, month: number, day: number): number {
  const now = new Date();
  if (now.getFullYear() === year && now.getMonth() + 1 === month && now.getDate() === day) {
    return now.getTime();
  }
  return new Date(year, month - 1, day, 21, 0, 0).getTime();
}

function cloneMoods(moods: Mood[]): Mood[] {
  const copy: Mood[] = [];
  for (let i = 0; i < moods.length; i++) {
    copy.push(moods[i]);
  }
  return copy;
}

function cloneImages(images: string[]): string[] {
  const copy: string[] = [];
  for (let i = 0; i < images.length; i++) {
    copy.push(images[i]);
  }
  return copy;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 业务自然日键：YYYY-MM-DD */
export function dateKeyOf(year: number, month: number, day: number): string {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

export function todayKey(): string {
  const now = new Date();
  return dateKeyOf(now.getFullYear(), now.getMonth() + 1, now.getDate());
}


@ObservedV2
export class AppStore {
  @Trace records: RecordItem[] = [];
  @Trace unarchived: RecordItem[] = [];
  @Trace settings: AppSettings = createDefaultSettings();
  @Trace loaded: boolean = false;
  private context: Context | null = null;
  private db: RecordDb | null = null;

  async init(context: Context): Promise<void> {
    this.context = context;
    if (this.loaded) {
      return;
    }
    // 打开数据库放在 try 里：这里一抛，后面连设置都读不到，启动会一直退回隐私页
    try {
      this.db = await RecordDb.open(context);
    } catch (err) {
      this.db = null;
    }
    // 旧版把记录存在 Preferences 的 JSON 里；首次启动搬进关系库，之后不再读写那份 JSON。
    // 迁移失败不能让应用起不来：记录还在旧 JSON 里，下次启动会再试一次。
    try {
      await RecordDb.migrateFromPreferences(context);
    } catch (err) {
    }
    try {
      await this.loadRecordsFromDb();
    } catch (err) {
      this.records = [];
      this.unarchived = [];
    }
    try {
      this.settings = await loadSettings(context);
    } catch (err) {
      // 读设置失败就用默认值继续，不让页面起不来
    }
    this.loaded = true;
  }

  async reload(): Promise<void> {
    if (this.context === null) {
      return;
    }
    await this.loadRecordsFromDb();
    this.settings = await loadSettings(this.context);
  }

  
/** 未归档记录在库里以 date_key IS NULL 表达，读出来时按有无 dateKey 拆成两个列表 */
  private async loadRecordsFromDb(): Promise<void> {
    if (this.db === null) {
      return;
    }
    const all = await this.db.loadRecords();
    const dated: RecordItem[] = [];
    const undated: RecordItem[] = [];
    for (let i = 0; i < all.length; i++) {
      const item = all[i];
      const key = item.dateKey;
      if (key !== undefined && key !== '') {
        dated.push(item);
      } else {
        undated.push(item);
      }
    }
    this.records = dated;
    this.unarchived = undated;
  }

  getSettings(): AppSettings {
    return this.settings;
  }

  async updateSettings(next: AppSettings): Promise<void> {
    this.settings = next;
    if (this.context !== null) {
      await saveSettings(this.context, next);
    }
  }

  /** 是否仍需展示隐私弹窗：仅当已接受版本低于当前要求版本 */
  needsPrivacyConsent(requiredVersion: number): boolean {
    return this.settings.privacyAcceptedVersion < requiredVersion;
  }

  /** 记录用户同意；写盘成功后才视为生效 */
  async acceptPrivacy(version: number): Promise<boolean> {
    if (this.context === null) {
      return false;
    }
    const next: AppSettings = {
      themeMode: this.settings.themeMode,
      largeFont: this.settings.largeFont,
      nightlyReminder: this.settings.nightlyReminder,
      reminderTime: this.settings.reminderTime,
      defaultMoodMode: this.settings.defaultMoodMode,
      lastMood: this.settings.lastMood,
      reminderId: this.settings.reminderId,
      privacyAcceptedVersion: version,
      privacyAcceptedAt: Date.now(),
      lastBackupAt: this.settings.lastBackupAt,
      lookbackOrder: this.settings.lookbackOrder
    };
    await this.updateSettings(next);
    return this.settings.privacyAcceptedVersion === version;
  }

  /** 标记最近一次成功导出 */
  async markBackupDone(): Promise<void> {
    const next: AppSettings = {
      themeMode: this.settings.themeMode,
      largeFont: this.settings.largeFont,
      nightlyReminder: this.settings.nightlyReminder,
      reminderTime: this.settings.reminderTime,
      defaultMoodMode: this.settings.defaultMoodMode,
      lastMood: this.settings.lastMood,
      reminderId: this.settings.reminderId,
      privacyAcceptedVersion: this.settings.privacyAcceptedVersion,
      privacyAcceptedAt: this.settings.privacyAcceptedAt,
      lastBackupAt: Date.now(),
      lookbackOrder: this.settings.lookbackOrder
    };
    await this.updateSettings(next);
  }

  async rememberMood(mood: Mood): Promise<void> {
    if (this.settings.defaultMoodMode !== DEFAULT_MOOD_LAST) {
      return;
    }
    if (this.settings.lastMood === mood) {
      return;
    }
    const next: AppSettings = {
      themeMode: this.settings.themeMode,
      largeFont: this.settings.largeFont,
      nightlyReminder: this.settings.nightlyReminder,
      reminderTime: this.settings.reminderTime,
      defaultMoodMode: this.settings.defaultMoodMode,
      lastMood: mood,
      reminderId: this.settings.reminderId,
      privacyAcceptedVersion: this.settings.privacyAcceptedVersion,
      privacyAcceptedAt: this.settings.privacyAcceptedAt,
      lastBackupAt: this.settings.lastBackupAt,
      lookbackOrder: this.settings.lookbackOrder
    };
    await this.updateSettings(next);
  }

  getRecordsForDate(year: number, month: number, day: number): RecordItem[] {
    const list: RecordItem[] = [];
    for (let i = 0; i < this.records.length; i++) {
      const item = this.records[i];
      if (sameDay(item.timestamp, year, month, day)) {
        list.push(item);
      }
    }
    list.sort((a: RecordItem, b: RecordItem) => a.timestamp - b.timestamp);
    return list;
  }

  getMoodsForDate(year: number, month: number, day: number): Mood[] {
    const moods: Mood[] = [];
    for (let i = 0; i < this.records.length; i++) {
      const item = this.records[i];
      if (!sameDay(item.timestamp, year, month, day)) {
        continue;
      }
      for (let j = 0; j < item.moods.length; j++) {
        if (!moods.includes(item.moods[j])) {
          moods.push(item.moods[j]);
        }
      }
    }
    return moods;
  }

  hasRecordsOn(year: number, month: number, day: number): boolean {
    for (let i = 0; i < this.records.length; i++) {
      if (sameDay(this.records[i].timestamp, year, month, day)) {
        return true;
      }
    }
    return false;
  }

  getRecordById(id: string): RecordItem | null {
    for (let i = 0; i < this.records.length; i++) {
      if (this.records[i].id === id) {
        return this.records[i];
      }
    }
    return null;
  }

  countAnnotations(parentId: string): number {
    let count = 0;
    for (let i = 0; i < this.records.length; i++) {
      if (this.records[i].parentId === parentId) {
        count++;
      }
    }
    return count;
  }

  async addRecord(payload: DraftPayload, year: number, month: number, day: number): Promise<RecordItem> {
    const key = dateKeyOf(year, month, day);
    const item: RecordItem = {
      id: newId(),
      timestamp: timestampOfDate(year, month, day),
      dateKey: key,
      isBackfill: key < todayKey(),
      content: payload.content.trim(),
      moods: cloneMoods(payload.moods),
      images: cloneImages(payload.images)
    };
    if (payload.parentId !== '') {
      item.parentId = payload.parentId;
    }
    if (payload.quote !== null) {
      item.quote = payload.quote;
    }
    this.records = this.records.concat([item]);
    await this.persistRecords();
    if (item.moods.length > 0) {
      await this.rememberMood(item.moods[0]);
    }
    return item;
  }

  async updateRecord(payload: DraftPayload): Promise<void> {
    const index = this.records.findIndex((item: RecordItem) => item.id === payload.editingId);
    if (index < 0) {
      return;
    }
    const old = this.records[index];
    const updated: RecordItem = {
      id: old.id,
      timestamp: old.timestamp,
      dateKey: old.dateKey,
      isBackfill: old.isBackfill,
      updatedAt: Date.now(),
      content: payload.content.trim(),
      moods: cloneMoods(payload.moods),
      images: cloneImages(payload.images)
    };
    if (old.parentId !== undefined) {
      updated.parentId = old.parentId;
    }
    if (old.quote !== undefined) {
      updated.quote = old.quote;
    }
    const next = this.records.slice();
    next[index] = updated;
    this.records = next;
    await this.persistRecords();
    if (updated.moods.length > 0) {
      await this.rememberMood(updated.moods[0]);
    }
  }

  async deleteRecord(id: string): Promise<void> {
    const next: RecordItem[] = [];
    for (let i = 0; i < this.records.length; i++) {
      const item = this.records[i];
      if (item.id !== id && item.parentId !== id) {
        next.push(item);
      }
    }
    this.records = next;
    await this.persistRecords();
  }

  buildQuote(record: RecordItem): QuoteRef {
    return {
      recordId: record.id,
      content: record.content,
      image: record.images.length > 0 ? record.images[0] : ''
    };
  }

  async archive(recordId: string, year: number, month: number, day: number): Promise<void> {
    const index = this.unarchived.findIndex((item: RecordItem) => item.id === recordId);
    if (index < 0) {
      return;
    }
    const old = this.unarchived[index];
    const key = dateKeyOf(year, month, day);
    const archived: RecordItem = {
      id: old.id,
      timestamp: timestampOfDate(year, month, day),
      dateKey: key,
      isBackfill: key < todayKey(),
      content: old.content,
      moods: cloneMoods(old.moods),
      images: cloneImages(old.images)
    };
    if (old.quote !== undefined) {
      archived.quote = old.quote;
    }
    const rest = this.unarchived.slice();
    rest.splice(index, 1);
    this.unarchived = rest;
    this.records = this.records.concat([archived]);
    await this.persistRecords();
    await this.persistUnarchived();
  }

  async archiveAllToToday(): Promise<void> {
    if (this.unarchived.length === 0) {
      return;
    }
    const now = new Date();
    const moved: RecordItem[] = [];
    const key = todayKey();
    for (let i = 0; i < this.unarchived.length; i++) {
      const old = this.unarchived[i];
      const archived: RecordItem = {
        id: old.id,
        timestamp: new Date(now.getFullYear(), now.getMonth(), now.getDate(), 12, 0, 0).getTime(),
        dateKey: key,
        isBackfill: false,
        content: old.content,
        moods: cloneMoods(old.moods),
        images: cloneImages(old.images)
      };
      if (old.quote !== undefined) {
        archived.quote = old.quote;
      }
      moved.push(archived);
    }
    this.records = this.records.concat(moved);
    this.unarchived = [];
    await this.persistRecords();
    await this.persistUnarchived();
  }

  async importData(records: RecordItem[], unarchived: RecordItem[]): Promise<void> {
    this.records = this.records.concat(records);
    this.unarchived = this.unarchived.concat(unarchived);
    await this.persistRecords();
    await this.persistUnarchived();
  }

  async clearAll(): Promise<void> {
    this.records = [];
    this.unarchived = [];
    if (this.db !== null) {
      await this.db.replaceAll([]);
    }
    if (this.context !== null) {
      clearAllImages(this.context);
    }
  }

  /** 重置应用：删除全部记录、图片、草稿与设置，回到首次安装状态 */
  async resetAll(): Promise<void> {
    this.records = [];
    this.unarchived = [];
    if (this.db !== null) {
      await this.db.replaceAll([]);
    }
    if (this.context !== null) {
      clearAllImages(this.context);
      await deleteSettings(this.context);
    }
    this.settings = createDefaultSettings();
    this.loaded = true;
  }

  private async persistRecords(): Promise<void> {
    await this.persistAll();
  }

  private async persistUnarchived(): Promise<void> {
    await this.persistAll();
  }

  /**
   * 记录与未归档现在同在一张表里，按 dateKey 区分；一次事务写全量。
   * 个人记录的体量下全量写最不容易出「一半成功一半失败」的状态；写入变为瓶颈时再改增量 upsert。
   */
  private async persistAll(): Promise<void> {
    if (this.db === null) {
      return;
    }
    await this.db.replaceAll(this.records.concat(this.unarchived));
  }

  /** 草稿按 dateKey 保存；提交成功或主动取消后由调用方清除 */
  async saveDraftForDate(key: string, payload: DraftPayload): Promise<void> {
    if (this.context === null) {
      return;
    }
    await saveDraftValue(this.context, key, JSON.stringify(payload));
  }

  async loadDraftForDate(key: string): Promise<DraftPayload | null> {
    if (this.context === null) {
      return null;
    }
    const json = await loadDraftValue(this.context, key);
    if (json === '') {
      return null;
    }
    try {
      const parsed: Object = JSON.parse(json);
      const payload = parsed as DraftPayload;
      if (payload === null || payload === undefined) {
        return null;
      }
      const hasContent = typeof payload.content === 'string' && payload.content !== '';
      const hasImages = Array.isArray(payload.images) && payload.images.length > 0;
      const hasMoods = Array.isArray(payload.moods) && payload.moods.length > 0;
      if (!hasContent && !hasImages && !hasMoods) {
        return null;
      }
      return payload;
    } catch (e) {
      return null;
    }
  }

  async clearDraftForDate(key: string): Promise<void> {
    if (this.context === null) {
      return;
    }
    await deleteDraftValue(this.context, key);
  }
}

export const appStore = new AppStore();
