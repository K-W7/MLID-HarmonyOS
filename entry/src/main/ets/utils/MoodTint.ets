import { Mood } from '../model/Mood';

/**
 * A 层的落地：情绪决定色温。
 *
 * 原则（避免“看腻/发黄”）：
 * - 底色不直接用情绪原色，而是把情绪色打到很低的饱和度上（只偏移色相与冷暖）
 * - 一天固定，不随滚动变化
 * - 强调色（今天圆环、大日期、“正在写”）才用情绪原色
 */
export interface MoodTint {
  /** 背景渐变上端 */
  top: string;
  /** 背景渐变下端 */
  bottom: string;
  /** 强调色：今日、大日期、当前输入 */
  accent: string;
  /** 顶部光的中心色（带透明度） */
  glow: string;
  /** 顶部光的边缘色（透明） */
  glowEdge: string;
}

interface TintPair {
  lightTop: string;
  lightBottom: string;
  lightAccent: string;
  darkTop: string;
  darkBottom: string;
  darkAccent: string;
}

/** 每种情绪一组：底色只差一点点冷暖，强调色才明显 */
const TINTS: Map<Mood, TintPair> = new Map<Mood, TintPair>([
  [Mood.NONE, {
    lightTop: '#F5F0EC', lightBottom: '#ECE4D6', lightAccent: '#8C8275',
    darkTop: '#141311', darkBottom: '#0A0A09', darkAccent: '#9A9288'
  }],
  [Mood.CALM, {
    lightTop: '#F0F3EC', lightBottom: '#E4EADF', lightAccent: '#5F8A6B',
    darkTop: '#111613', darkBottom: '#090C0A', darkAccent: '#8CB79A'
  }],
  [Mood.HAPPY, {
    lightTop: '#F8F2E6', lightBottom: '#EEE3D2', lightAccent: '#C2872B',
    darkTop: '#171411', darkBottom: '#0B0908', darkAccent: '#E3AE55'
  }],
  [Mood.TIRED, {
    lightTop: '#F3F2F5', lightBottom: '#E8E6EC', lightAccent: '#7E7AA0',
    darkTop: '#131216', darkBottom: '#09080B', darkAccent: '#A9A2C9'
  }],
  [Mood.IRRITABLE, {
    lightTop: '#F8EFEA', lightBottom: '#F0E0D8', lightAccent: '#C0563A',
    darkTop: '#171210', darkBottom: '#0B0807', darkAccent: '#DA7B58'
  }],
  [Mood.LOW, {
    lightTop: '#F1F3F6', lightBottom: '#E4E8ED', lightAccent: '#54779E',
    darkTop: '#111417', darkBottom: '#08090B', darkAccent: '#82A0C4'
  }]
]);

/** 取某情绪的色温；深/浅色各自一套 */
export function tintFor(mood: Mood, dark: boolean): MoodTint {
  const pair = TINTS.get(mood);
  const safe = pair === undefined ? TINTS.get(Mood.NONE) : pair;
  if (safe === undefined) {
    return {
      top: dark ? '#141311' : '#F5F0EC',
      bottom: dark ? '#0A0A09' : '#ECE4D6',
      accent: dark ? '#9A9288' : '#8C8275',
      glow: '#00000000',
      glowEdge: '#00000000'
    };
  }
  const accent = dark ? safe.darkAccent : safe.lightAccent;
  return {
    top: dark ? safe.darkTop : safe.lightTop,
    bottom: dark ? safe.darkBottom : safe.lightBottom,
    accent: accent,
    // 光用强调色的低透明度版本
    glow: dark ? `${accent}8C` : `${accent}59`,
    glowEdge: '#00000000'
  };
}


/** 没记情绪时的兜底色温：按当前时段，不假造情绪 */
export function tintForTime(hour: number, dark: boolean): MoodTint {
  // 06-11 晨 / 11-17 午 / 17-22 暮 / 22-06 夜
  if (hour >= 6 && hour < 11) {
    return dark
      ? { top: '#141A1B', bottom: '#090D0E', accent: '#8FB0B3', glow: '#8C8FB0B3', glowEdge: '#00000000' }
      : { top: '#F2F5F5', bottom: '#E6EBEB', accent: '#6E8B8E', glow: '#596E8B8E', glowEdge: '#00000000' };
  }
  if (hour >= 11 && hour < 17) {
    return dark
      ? { top: '#141311', bottom: '#0A0A09', accent: '#9A9288', glow: '#8C9A9288', glowEdge: '#00000000' }
      : { top: '#F5F0EC', bottom: '#ECE4D6', accent: '#8C8275', glow: '#598C8275', glowEdge: '#00000000' };
  }
  if (hour >= 17 && hour < 22) {
    return dark
      ? { top: '#17140F', bottom: '#0B0908', accent: '#C0914F', glow: '#8CC0914F', glowEdge: '#00000000' }
      : { top: '#F7F1E7', bottom: '#EEE3D1', accent: '#B8862E', glow: '#59B8862E', glowEdge: '#00000000' };
  }
  return dark
    ? { top: '#101112', bottom: '#08090A', accent: '#7E8A93', glow: '#8C7E8A93', glowEdge: '#00000000' }
    : { top: '#EEF1F3', bottom: '#E1E6E9', accent: '#6A7880', glow: '#596A7880', glowEdge: '#00000000' };
}
