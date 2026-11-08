import { ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppSettings, THEME_DARK, THEME_LIGHT } from '../model/AppSettings';

/** 应用深色模式与大字号设置 */
export function applyTheme(context: Context, settings: AppSettings): void {
  try {
    const appContext = context.getApplicationContext();
    let colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (settings.themeMode === THEME_LIGHT) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (settings.themeMode === THEME_DARK) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    appContext.setColorMode(colorMode);
    // 字号完全跟随系统，应用不做覆盖
    syncStatusBar(context, colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  } catch (e) {
    // 部分设备不支持动态设置时保持系统默认
  }
}


/**
 * 状态栏图标颜色必须跟主题走：
 * 深色底用白字，浅色底用近黑，否则浅色下时间和电量几乎看不见。
 */
function syncStatusBar(context: Context, dark: boolean): void {
  try {
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowSystemBarProperties({
        statusBarContentColor: dark ? '#FFFFFF' : '#1F1B14'
      }).catch(() => {
      });
    }).catch(() => {
    });
  } catch (e) {
    // 拿不到窗台时忽略
  }
}
