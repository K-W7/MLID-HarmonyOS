import { Configuration, ConfigurationConstant, common } from '@kit.AbilityKit';
import { Mood } from '../model/Mood';
import { appStore } from '../store/AppStore';
import { THEME_DARK, THEME_LIGHT } from '../model/AppSettings';
import { MoodTint, tintFor, tintForTime } from './MoodTint';

/** 当前是否深色（跟随系统 + 应用主题设置） */
export function isDarkMode(context: Context): boolean {
  // 以应用内的主题设置为准：context.config 在 setColorMode 的瞬间不会立刻更新，
  // 只读它会导致「卡片已变白、底色还黑」的错位
  try {
    const mode = appStore.settings.themeMode;
    if (mode === THEME_LIGHT) {
      return false;
    }
    if (mode === THEME_DARK) {
      return true;
    }
  } catch (e) {
    // 读不到设置时回落到系统
  }
  try {
    const abilityContext = context as common.UIAbilityContext;
    return abilityContext.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  } catch (e) {
    return true;
  }
}

/**
 * 全应用统一的色温来源：
 * 今天记了情绪 → 用主情绪色；没记 → 用当前时段色温。
 * 主页、单日页、设置、隐私、启动页都用它，保证切页不跳色。
 */
export function currentTint(context: Context): MoodTint {
  const dark = isDarkMode(context);
  try {
    const now = new Date();
    const moods = appStore.getMoodsForDate(now.getFullYear(), now.getMonth() + 1, now.getDate());
    if (moods.length > 0) {
      return tintFor(moods[0] as Mood, dark);
    }
    return tintForTime(now.getHours(), dark);
  } catch (e) {
    return tintForTime(new Date().getHours(), dark);
  }
}


/** 监听深浅色等环境变化；回调里刷新自己的 tint 状态即可完成“秒切” */
export function watchColorMode(context: Context, onChange: () => void): number {
  try {
    const appContext = context.getApplicationContext();
    return appContext.on('environment', {
      onConfigurationUpdated: (config: Configuration): void => {
        onChange();
      },
      onMemoryLevel: (level: number): void => {
      }
    });
  } catch (e) {
    return -1;
  }
}

export function stopWatchColorMode(context: Context, id: number): void {
  if (id < 0) {
    return;
  }
  try {
    const appContext = context.getApplicationContext();
    appContext.off('environment', id);
  } catch (e) {
    // 忽略
  }
}
