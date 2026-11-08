import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { appStore } from '../store/AppStore';
import { peekThemeMode } from '../store/PreferencesStore';
import { cleanupTempCache } from '../utils/ImportExport';
import { motionDuration } from '../utils/MotionUtil';
import { THEME_DARK, THEME_LIGHT } from '../model/AppSettings';
import { getLunarDate, getWeekdayName } from '../model/CalendarUtils';
import { getLunarMonthName, getLunarDayName } from '../model/FestivalData';

/**
 * 启动页 = 扉页，跟随主题：浅色一套、深色一套，分开写。
 *
 * 两套只有配色不同，结构与动效完全一致：
 * 页眉日期 → 时 / 叙 依次浮现 → 朱砂「記」→ 页脚副题
 * 总时长约 2 秒，结束时 240ms 淡出。
 */
@Entry
@ComponentV2
struct SplashPage {
  @Local firstCharOpacity: number = 0;
  @Local secondCharOpacity: number = 0;
  @Local sealOpacity: number = 0;
  @Local headOpacity: number = 0;
  // 只淡内容，不淡背景：整页一起淡会露出窗口黑底，出现黑屏闪一下
  @Local contentAlpha: number = 1;
  @Local datePartText: string = '';
  @Local lunarPartText: string = '';
  // 首帧就要知道深浅，决定画哪一套
  @Local dark: boolean = true;
  private leaving: boolean = false;

  // 两套配色
  private bgColor(): string {
    return this.dark ? '#141311' : '#F5F0EC';
  }

  private inkColor(): string {
    return this.dark ? '#EFE9DF' : '#30281D';
  }

  private faintColor(): string {
    return this.dark ? '#8C857A' : '#9A948B';
  }

  private sealColor(): string {
    return '#B4432F';
  }

  aboutToAppear(): void {
    this.resolveTheme();
    this.syncStatusBar();
    this.computeDate();

    setTimeout(() => {
      animateTo({ duration: motionDuration(320), curve: Curve.EaseOut }, () => {
        this.headOpacity = 1;
      });
    }, 120);
    setTimeout(() => {
      animateTo({ duration: motionDuration(420), curve: Curve.EaseOut }, () => {
        this.firstCharOpacity = 1;
      });
    }, 320);
    setTimeout(() => {
      animateTo({ duration: motionDuration(420), curve: Curve.EaseOut }, () => {
        this.secondCharOpacity = 1;
      });
    }, 760);
    setTimeout(() => {
      animateTo({ duration: motionDuration(380), curve: Curve.EaseOut }, () => {
        this.sealOpacity = 1;
      });
    }, 1180);

    this.bootstrap();
  }

  /** 主题判定：应用设置优先，跟随系统时看系统深浅色；同步完成，第一帧就对 */
  private resolveTheme(): void {
    let mode = THEME_LIGHT;
    try {
      mode = peekThemeMode(getContext(this) as common.UIAbilityContext);
    } catch (e) {
      mode = 0;
    }
    if (mode === THEME_DARK) {
      this.dark = true;
      return;
    }
    if (mode === THEME_LIGHT) {
      this.dark = false;
      return;
    }
    // 跟随系统
    try {
      const config = (getContext(this) as common.UIAbilityContext).config;
      this.dark = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (e) {
      this.dark = true;
    }
  }

  /** 启动页第一帧就把状态栏图标色摆正，否则浅色底上白字看不见 */
  private syncStatusBar(): void {
    try {
      window.getLastWindow(getContext(this) as common.UIAbilityContext).then((win: window.Window) => {
        win.setWindowSystemBarProperties({
          statusBarContentColor: this.dark ? '#FFFFFF' : '#1F1B14'
        }).catch(() => {
        });
      }).catch(() => {
      });
    } catch (e) {
      // 忽略
    }
  }

  private computeDate(): void {
    const now = new Date();
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    this.datePartText = `${now.getFullYear()}.${pad(now.getMonth() + 1)}.${pad(now.getDate())}  星期${getWeekdayName(now.getDay())}`;
    const lunar = getLunarDate(now.getFullYear(), now.getMonth() + 1, now.getDate());
    this.lunarPartText = lunar.month > 0 && lunar.day > 0
      ? `${getLunarMonthName(lunar.month)}${getLunarDayName(lunar.day)}`
      : '';
  }

  private async bootstrap(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      await appStore.init(context);
      await cleanupTempCache(context);
    } catch (e) {
      // 初始化失败也照常进入
    }
    setTimeout(() => {
      this.leave();
    }, 2000);
  }

  private leave(): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    animateTo({ duration: motionDuration(240), curve: Curve.EaseIn }, () => {
      this.contentAlpha = 0;
    });
    setTimeout(() => {
      router.replaceUrl({ url: 'pages/CalendarPage' });
    }, 250);
  }

  /** 浅色一套 */
  @Builder
  lightSplash() {
    Column() {
      Row({ space: 8 }) {
        Text(this.datePartText)
          .fontSize($r('app.float.font_meta_small'))
          .fontColor(this.faintColor())
        Text(this.lunarPartText)
          .fontSize($r('app.float.font_meta_small'))
          .fontColor(this.sealColor())
      }
      .width('100%')
      .opacity(this.headOpacity)

      Blank()

      Column({ space: 14 }) {
        Row() {
          Text('时')
            .fontSize($r('app.float.font_logo'))
            .fontColor(this.inkColor())
            .opacity(this.firstCharOpacity)
            .margin({ right: 10 })
          Text('叙')
            .fontSize($r('app.float.font_logo'))
            .fontColor(this.inkColor())
            .opacity(this.secondCharOpacity)
        }
        Text('記')
          .fontSize(22)
          .fontColor(this.sealColor())
          .opacity(this.sealOpacity)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Blank()

      Text($r('app.string.app_slogan'))
        .width('100%')
        .fontSize($r('app.float.font_meta_small'))
        .fontColor(this.faintColor())
        .opacity(this.headOpacity)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 60, bottom: 40 })
    .backgroundColor(this.bgColor())
    .opacity(this.contentAlpha)
  }

  /** 深色一套 */
  @Builder
  darkSplash() {
    Column() {
      Row({ space: 8 }) {
        Text(this.datePartText)
          .fontSize($r('app.float.font_meta_small'))
          .fontColor(this.faintColor())
        Text(this.lunarPartText)
          .fontSize($r('app.float.font_meta_small'))
          .fontColor(this.sealColor())
      }
      .width('100%')
      .opacity(this.headOpacity)

      Blank()

      Column({ space: 14 }) {
        Row() {
          Text('时')
            .fontSize($r('app.float.font_logo'))
            .fontColor(this.inkColor())
            .opacity(this.firstCharOpacity)
            .margin({ right: 10 })
          Text('叙')
            .fontSize($r('app.float.font_logo'))
            .fontColor(this.inkColor())
            .opacity(this.secondCharOpacity)
        }
        Text('記')
          .fontSize(22)
          .fontColor(this.sealColor())
          .opacity(this.sealOpacity)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Blank()

      Text($r('app.string.app_slogan'))
        .width('100%')
        .fontSize($r('app.float.font_meta_small'))
        .fontColor(this.faintColor())
        .opacity(this.headOpacity)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 60, bottom: 40 })
    .backgroundColor(this.bgColor())
    .opacity(this.contentAlpha)
  }

  build() {
    Column() {
      if (this.dark) {
        this.darkSplash()
      } else {
        this.lightSplash()
      }
    }
    .width('100%')
    .height('100%')
    // 外层保持不透明：底色一直盖住窗口，避免黑屏
    .backgroundColor(this.bgColor())
  }
}
