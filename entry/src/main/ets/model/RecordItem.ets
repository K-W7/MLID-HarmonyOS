import { Mood } from './Mood';

/** 引文快照：引用或批注时保存原记录的一小段内容与缩略图，避免原记录删除后引文丢失 */
export interface QuoteRef {
  recordId: string;
  content: string;
  image: string;
}

export interface RecordItem {
  id: string;
  timestamp: number;
  updatedAt?: number;
  /** 记录所属自然日 YYYY-MM-DD；创建后不可变更 */
  dateKey?: string;
  /** 创建时 dateKey 早于实际创建日，即补记；创建后固定 */
  isBackfill?: boolean;
  content: string;
  moods: Mood[];
  images: string[];
  parentId?: string;
  quote?: QuoteRef;
}

/** 情绪选择上限（NONE 与其他项互斥） */
export const MAX_MOODS = 6;

/** 每条记录最多图片数 */
export const MAX_IMAGES = 9;

/** 悬浮岛向外抛出的草稿数据 */
export interface DraftPayload {
  content: string;
  moods: Mood[];
  images: string[];
  parentId: string;
  quote: QuoteRef | null;
  editingId: string;
}

/** 导入结果汇总 */
export interface ImportResult {
  added: number;
  skipped: number;
  unarchived: number;
  orphans: number;
}

export function isValidRecord(r: RecordItem): boolean {
  return r.content.trim() !== '' || r.images.length > 0;
}

export function moodsContainNone(moods: Mood[]): boolean {
  return moods.includes(Mood.NONE);
}
