export interface FestivalEntry {
  month: number; // 1-12
  day: number; // 1-31
  name: string;
}

export interface SolarTermEntry {
  month: number; // 1-12
  approxDay: number; // 近似日期（前后1-2天浮动）
  name: string;
}

export const TRADITIONAL_FESTIVALS: FestivalEntry[] = [
  { month: 1, day: 1, name: '春节' },
  { month: 1, day: 15, name: '元宵节' },
  { month: 2, day: 2, name: '龙抬头' },
  { month: 5, day: 5, name: '端午节' },
  { month: 7, day: 7, name: '七夕' },
  { month: 7, day: 15, name: '中元节' },
  { month: 8, day: 15, name: '中秋节' },
  { month: 9, day: 9, name: '重阳节' },
  { month: 12, day: 8, name: '腊八节' },
  { month: 12, day: 23, name: '小年' },
  { month: 12, day: 30, name: '除夕' },
];

export const SOLAR_TERMS: SolarTermEntry[] = [
  { month: 1, approxDay: 6, name: '小寒' },
  { month: 1, approxDay: 20, name: '大寒' },
  { month: 2, approxDay: 4, name: '立春' },
  { month: 2, approxDay: 19, name: '雨水' },
  { month: 3, approxDay: 6, name: '惊蛰' },
  { month: 3, approxDay: 21, name: '春分' },
  { month: 4, approxDay: 5, name: '清明' },
  { month: 4, approxDay: 20, name: '谷雨' },
  { month: 5, approxDay: 6, name: '立夏' },
  { month: 5, approxDay: 21, name: '小满' },
  { month: 6, approxDay: 6, name: '芒种' },
  { month: 6, approxDay: 21, name: '夏至' },
  { month: 7, approxDay: 7, name: '小暑' },
  { month: 7, approxDay: 23, name: '大暑' },
  { month: 8, approxDay: 7, name: '立秋' },
  { month: 8, approxDay: 23, name: '处暑' },
  { month: 9, approxDay: 8, name: '白露' },
  { month: 9, approxDay: 23, name: '秋分' },
  { month: 10, approxDay: 8, name: '寒露' },
  { month: 10, approxDay: 23, name: '霜降' },
  { month: 11, approxDay: 7, name: '立冬' },
  { month: 11, approxDay: 22, name: '小雪' },
  { month: 12, approxDay: 7, name: '大雪' },
  { month: 12, approxDay: 22, name: '冬至' },
];

const LUNAR_MONTH_NAMES: string[] = [
  '正月', '二月', '三月', '四月', '五月', '六月',
  '七月', '八月', '九月', '十月', '冬月', '腊月'
];

const LUNAR_DAY_NAMES: string[] = [
  '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'
];

/**
 * 根据农历月、日查找传统节日
 */
export function findFestival(lunarMonth: number, lunarDay: number): string {
  const entry = TRADITIONAL_FESTIVALS.find(f => f.month === lunarMonth && f.day === lunarDay);
  return entry ? entry.name : '';
}

/**
 * 根据公历月、日查找节气（近似）
 */
export function findSolarTerm(month: number, day: number): string {
  const entry = SOLAR_TERMS.find(s => s.month === month && s.approxDay === day);
  return entry ? entry.name : '';
}

/**
 * 获取农历月名称
 */
export function getLunarMonthName(month: number): string {
  if (month >= 1 && month <= 12) {
    return LUNAR_MONTH_NAMES[month - 1];
  }
  return '';
}

/**
 * 获取农历日名称
 */
export function getLunarDayName(day: number): string {
  if (day >= 1 && day <= 30) {
    return LUNAR_DAY_NAMES[day - 1];
  }
  return '';
}

/**
 * 获取某天应显示的农历文本（优先级：节日 > 节气 > 初一 > 农历日）
 */
export function getLunarDisplayText(
  solarMonth: number, solarDay: number,
  lunarMonth: number, lunarDay: number
): string {
  // 1. 先查传统节日（按农历）
  const festival = findFestival(lunarMonth, lunarDay);
  if (festival) {
    return festival;
  }

  // 2. 查节气（按公历）
  const solarTerm = findSolarTerm(solarMonth, solarDay);
  if (solarTerm) {
    return solarTerm;
  }

  // 3. 初一显示月名
  if (lunarDay === 1) {
    return getLunarMonthName(lunarMonth);
  }

  // 4. 显示农历日
  return getLunarDayName(lunarDay);
}
