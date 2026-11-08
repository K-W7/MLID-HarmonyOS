import { Mood } from './Mood';

export interface BreathingConfig {
  period: number;
  high: number;
  low: number;
}

export function getMoodLabel(mood: Mood): string {
  switch (mood) {
    case Mood.HAPPY:
      return '愉悦';
    case Mood.CALM:
      return '平静';
    case Mood.TIRED:
      return '疲惫';
    case Mood.IRRITABLE:
      return '烦躁';
    case Mood.LOW:
      return '低落';
    default:
      return '无';
  }
}

export function getMoodColor(mood: Mood): ResourceColor {
  switch (mood) {
    case Mood.HAPPY:
      return $r('app.color.mood_happy');
    case Mood.CALM:
      return $r('app.color.mood_calm');
    case Mood.TIRED:
      return $r('app.color.mood_tired');
    case Mood.IRRITABLE:
      return $r('app.color.mood_irritable');
    case Mood.LOW:
      return $r('app.color.mood_low');
    default:
      return $r('app.color.mood_none');
  }
}

function breathingOf(mood: Mood): BreathingConfig {
  switch (mood) {
    case Mood.HAPPY:
      return { period: 1.9, high: 0.24, low: 0.15 };
    case Mood.CALM:
      return { period: 2.4, high: 0.22, low: 0.14 };
    case Mood.TIRED:
      return { period: 3.0, high: 0.18, low: 0.13 };
    case Mood.IRRITABLE:
      return { period: 2.0, high: 0.20, low: 0.15 };
    case Mood.LOW:
      return { period: 3.4, high: 0.18, low: 0.13 };
    default:
      return { period: 4.0, high: 0.16, low: 0.12 };
  }
}

/** 多条记录取周期与幅度的平均值 */
export function getBreathingConfig(moods: Mood[]): BreathingConfig {
  if (moods.length === 0) {
    return breathingOf(Mood.NONE);
  }
  let period = 0;
  let high = 0;
  let low = 0;
  for (let i = 0; i < moods.length; i++) {
    const cfg = breathingOf(moods[i]);
    period += cfg.period;
    high += cfg.high;
    low += cfg.low;
  }
  return {
    period: period / moods.length,
    high: high / moods.length,
    low: low / moods.length
  };
}

function primaryMood(moods: Mood[]): Mood {
  if (moods.length === 0) {
    return Mood.NONE;
  }
  if (moods.includes(Mood.NONE)) {
    return Mood.NONE;
  }
  return moods[0];
}

/** 当天已有记录时，再次打开输入区的邀请文案 */
export function getAfterSaveCopy(moods: Mood[]): string {
  // 这些文案会直接做输入框 placeholder，必须极短，否则会折行
  switch (primaryMood(moods)) {
    case Mood.HAPPY:
      return '还想再记点什么？';
    case Mood.CALM:
      return '想说什么，写下来吧。';
    case Mood.TIRED:
      return '累了就歇着，不用写。';
    case Mood.IRRITABLE:
      return '想说就说吧。';
    case Mood.LOW:
      return '这里一直都在。';
    default:
      return '再写点什么吗？';
  }
}

/** 空状态文案：只用用户主动选择的标签，缺失时用中性兜底 */
export function getEmptyCopy(moods: Mood[]): string {
  if (moods.length === 0) {
    return '写点什么吧。';
  }
  const mood = primaryMood(moods);
  if (mood === Mood.TIRED) {
    return '累了就歇着。';
  }
  if (mood === Mood.LOW) {
    return '这里随时都在。';
  }
  return '写点什么吧。';
}

export function getMoodSummary(moods: Mood[]): string {
  if (moods.length === 0) {
    return '没有选情绪';
  }
  const labels: string[] = [];
  for (let i = 0; i < moods.length; i++) {
    if (moods[i] !== Mood.NONE) {
      labels.push(getMoodLabel(moods[i]));
    }
  }
  return labels.length === 0 ? '无' : labels.join('、');
}
