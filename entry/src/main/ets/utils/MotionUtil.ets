import { accessibility } from '@kit.AccessibilityKit';

/**
 * 减弱动画开关（跟随系统）。
 *
 * 规格 5.6 要求：开启系统「减少动画」后，动效降级为短时长或静态，
 * 但功能不能丢。判定入口是官方 isAnimationReduceEnabledSync()。
 */

// 减弱动画时的统一短时长（规格 5.6「减弱动画改 120ms 淡出」）
const REDUCED_MS: number = 120;

export function isReduceMotion(): boolean {
  try {
    return accessibility.isAnimationReduceEnabledSync();
  } catch (e) {
    // 取不到就按“不减弱”处理，动画正常走
    return false;
  }
}

/** 需要动画时长的地方统一走这里：减弱动画时压到 120ms */
export function motionDuration(normalMs: number): number {
  if (!isReduceMotion()) {
    return normalMs;
  }
  return Math.min(normalMs, REDUCED_MS);
}
