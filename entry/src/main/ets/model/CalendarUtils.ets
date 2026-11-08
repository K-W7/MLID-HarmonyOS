import { i18n } from '@kit.LocalizationKit';
import { findFestival, findSolarTerm, getLunarDisplayText } from './FestivalData';

export interface CalendarDay {
  key: string;
  year: number;
  month: number;
  day: number;
  isCurrentMonth: boolean;
  isToday: boolean;
  isFuture: boolean;
  lunarText: string;
  // 这天是节气或节日：格子里用赤陶色区分
  isFestival: boolean;
  hasRecord: boolean;
}

export interface LunarDate {
  month: number;
  day: number;
}

const CACHE: Record<string, LunarDate> = {};

export function getDaysInMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}

/** 周日开头（国内日历习惯）：周一..周六 = 1..6，周日 = 0 */
export function getFirstDayOfMonth(year: number, month: number): number {
  return new Date(year, month - 1, 1).getDay();
}

export function getLunarDate(year: number, month: number, day: number): LunarDate {
  const cacheKey = `${year}-${month}-${day}`;
  if (CACHE[cacheKey] !== undefined) {
    return CACHE[cacheKey];
  }
  try {
    // 月份从 0 开始计数；农历日必须用 'date'，'day' 不是日期字段
    const calendar = i18n.getCalendar('zh-CN', 'chinese');
    calendar.setTime(new Date(year, month - 1, day));
    const lMonth = calendar.get('month');
    const lDay = calendar.get('date');
    if (lMonth < 0 || lMonth > 11 || lDay < 1 || lDay > 30) {
      return { month: 0, day: 0 };
    }
    const result: LunarDate = { month: lMonth + 1, day: lDay };
    CACHE[cacheKey] = result;
    return result;
  } catch {
    return { month: 0, day: 0 };
  }
}

const WEEKDAY_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六'];

export function getWeekdayName(index: number): string {
  return WEEKDAY_NAMES[index];
}

export function getWeekdayNames(): string[] {
  return WEEKDAY_NAMES;
}

/** 表头顺序：周日开头，和网格排布一致 */
export function getWeekdayHeaders(): string[] {
  return ['日', '一', '二', '三', '四', '五', '六'];
}

const today = new Date();
const TODAY_YEAR = today.getFullYear();
const TODAY_MONTH = today.getMonth() + 1;
const TODAY_DAY = today.getDate();

export function isToday(year: number, month: number, day: number): boolean {
  return year === TODAY_YEAR && month === TODAY_MONTH && day === TODAY_DAY;
}

export function isFutureDate(year: number, month: number, day: number): boolean {
  const d = new Date(year, month - 1, day);
  return d.getTime() > today.getTime();
}

export function generateCalendarGrid(year: number, month: number): CalendarDay[] {
  const daysInMonth = getDaysInMonth(year, month);
  const firstDay = getFirstDayOfMonth(year, month);

  const prevMonth = month === 1 ? 12 : month - 1;
  const prevYear = month === 1 ? year - 1 : year;
  const daysInPrevMonth = getDaysInMonth(prevYear, prevMonth);

  const grid: CalendarDay[] = [];
  const totalCells = 42; // 6 rows x 7 cols

  for (let i = 0; i < totalCells; i++) {
    let cellYear: number;
    let cellMonth: number;
    let cellDay: number;
    let isCurrentMonth: boolean;

    if (i < firstDay) {
      // Previous month
      cellYear = prevYear;
      cellMonth = prevMonth;
      cellDay = daysInPrevMonth - firstDay + i + 1;
      isCurrentMonth = false;
    } else if (i >= firstDay + daysInMonth) {
      // Next month
      const nextMonth = month === 12 ? 1 : month + 1;
      const nextYear = month === 12 ? year + 1 : year;
      cellYear = nextYear;
      cellMonth = nextMonth;
      cellDay = i - firstDay - daysInMonth + 1;
      isCurrentMonth = false;
    } else {
      cellYear = year;
      cellMonth = month;
      cellDay = i - firstDay + 1;
      isCurrentMonth = true;
    }

    const cellIsToday = isToday(cellYear, cellMonth, cellDay);
    const cellIsFuture = isFutureDate(cellYear, cellMonth, cellDay);

    // 每格都带农历副行（对齐安卓版的信息密度）
    let lunarText = '';
    let isFestival = false;
    const lunar = getLunarDate(cellYear, cellMonth, cellDay);
    if (lunar.month > 0 && lunar.day > 0) {
      lunarText = getLunarDisplayText(cellMonth, cellDay, lunar.month, lunar.day);
      const festival = findFestival(lunar.month, lunar.day);
      const solarTerm = findSolarTerm(cellMonth, cellDay);
      isFestival = festival !== '' || solarTerm !== '';
    }

    grid.push({
      key: `${cellYear}-${cellMonth}-${cellDay}`,
      year: cellYear,
      month: cellMonth,
      day: cellDay,
      isCurrentMonth: isCurrentMonth,
      isToday: cellIsToday,
      isFuture: cellIsFuture,
      lunarText: lunarText,
      isFestival: isFestival,
      hasRecord: false
    });
  }

  return grid;
}

export function formatMonthTitle(year: number, month: number): string {
  return `${year}年${month}月`;
}

export function formatLunarMonthTitle(lunarMonth: number): string {
  const names = ['', '正月', '二月', '三月', '四月', '五月', '六月',
    '七月', '八月', '九月', '十月', '冬月', '腊月'];
  if (lunarMonth >= 1 && lunarMonth <= 12) {
    return names[lunarMonth];
  }
  return '';
}

export function getCurrentMonthLunarMonth(year: number, month: number): string {
  // 当前月取“今天”的农历月，避免月初跨农历月导致显示成上个月
  const now = new Date();
  const isCurrentMonth = year === now.getFullYear() && month === now.getMonth() + 1;
  const day = isCurrentMonth ? now.getDate() : 15;
  const lunar = getLunarDate(year, month, day);
  return formatLunarMonthTitle(lunar.month);
}
