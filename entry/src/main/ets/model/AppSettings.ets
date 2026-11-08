/** 0=跟随系统 1=浅色 2=深色 */
export const THEME_FOLLOW = 0;

export const THEME_LIGHT = 1;

export const THEME_DARK = 2;

/** 0=不预设 1=记住上次 */
export const DEFAULT_MOOD_NONE = 0;

export const DEFAULT_MOOD_LAST = 1;

export interface AppSettings {
  themeMode: number;
  largeFont: boolean;
  nightlyReminder: boolean;
  reminderTime: string;
  defaultMoodMode: number;
  lastMood: number;
  reminderId: number;
  /** 用户已接受的隐私政策版本 */
  privacyAcceptedVersion: number;
  /** 最近一次同意的时间戳 */
  privacyAcceptedAt: number;
  /** 最近一次成功导出的时间戳，0 表示从未导出 */
  lastBackupAt: number;
  /** 回望区模块排序：['yesterday','random','pastYears'] 等 */
  lookbackOrder: string[];
}

export function createDefaultSettings(): AppSettings {
  return {
    themeMode: THEME_FOLLOW,
    largeFont: false,
    nightlyReminder: false,
    reminderTime: '20:30',
    defaultMoodMode: DEFAULT_MOOD_NONE,
    lastMood: 0,
    reminderId: 0,
    privacyAcceptedVersion: 0,
    privacyAcceptedAt: 0,
    lastBackupAt: 0,
    lookbackOrder: ['yesterday', 'random', 'pastYears']
  };
}

function numberOr(value: number | undefined, fallback: number): number {
  return value === undefined ? fallback : value;
}

function stringOr(value: string | undefined, fallback: string): string {
  return value === undefined ? fallback : value;
}

function booleanOr(value: boolean | undefined, fallback: boolean): boolean {
  return value === undefined ? fallback : value;
}

/** 兼容旧版本数据，缺失字段回落到默认值 */
export function normalizeSettings(raw: AppSettings | null): AppSettings {
  const def = createDefaultSettings();
  if (raw === null) {
    return def;
  }
  return {
    themeMode: numberOr(raw.themeMode, def.themeMode),
    largeFont: booleanOr(raw.largeFont, def.largeFont),
    nightlyReminder: booleanOr(raw.nightlyReminder, def.nightlyReminder),
    reminderTime: stringOr(raw.reminderTime, def.reminderTime),
    defaultMoodMode: numberOr(raw.defaultMoodMode, def.defaultMoodMode),
    lastMood: numberOr(raw.lastMood, def.lastMood),
    reminderId: numberOr(raw.reminderId, def.reminderId),
    privacyAcceptedVersion: numberOr(raw.privacyAcceptedVersion, def.privacyAcceptedVersion),
    privacyAcceptedAt: numberOr(raw.privacyAcceptedAt, def.privacyAcceptedAt),
    lastBackupAt: numberOr(raw.lastBackupAt, def.lastBackupAt),
    lookbackOrder: arrayOr(raw.lookbackOrder, def.lookbackOrder)
  };
}

function arrayOr(value: string[] | undefined, fallback: string[]): string[] {
  return (value !== undefined && Array.isArray(value) && value.length === 3) ? value : fallback;
}
