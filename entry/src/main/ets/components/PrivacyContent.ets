import { common } from '@kit.AbilityKit';
import { appStore } from '../store/AppStore';
import { PRIVACY_REQUIRED_VERSION } from '../model/Privacy';
import { applyTheme } from '../utils/ThemeUtil';
import { currentTint, stopWatchColorMode, watchColorMode } from '../utils/TintProvider';
import { MoodTint, tintForTime } from '../utils/MoodTint';

/**
 * S-05 隐私政策内容，由页面壳（router 版 PrivacyPage）或 Navigation 的 NavDestination 承载。
 * consentMode 模式：首次启动的隐私同意态，同意后才允许进入主页（跳转由宿主在 onAgree 里做）
 * read 模式：从设置进入，只读展示，返回通过 onBack 交给宿主
 * 这里只保留界面、两态切换、同意落库与 busy 态；"去哪里"完全由 onBack / onAgree 决定。
 */
@ComponentV2
export struct PrivacyContent {
  // 启动同意态（true）与只读查看态（false）
  @Param consentMode: boolean = false;
  @Event onBack: () => void = () => {
  };
  // 同意并进入：宿主负责 replaceUrl / 路由跳转，组件不直接跳
  @Event onAgree: () => void = () => {
  };

  @Local busy: boolean = false;
  // 每次进入都回到顶部，避免停在上一次的滚动位置
  private scroller: Scroller = new Scroller();
  private envWatchId: number = -1;
  @Local tint: MoodTint = tintForTime(new Date().getHours(), true);

  private refreshTint(): void {
    const next = currentTint(getContext(this) as common.UIAbilityContext);
    // 主题切换留 1.2s 过渡：直接赋值会硬切，观感很生硬
    this.getUIContext().animateTo({ duration: 1200, curve: Curve.EaseInOut }, () => {
      this.tint = next;
    });
  }

  aboutToAppear(): void {
    this.refreshTint();
    this.envWatchId = watchColorMode(getContext(this) as common.UIAbilityContext, () => {
      this.refreshTint();
    });
    this.prepare();
    // 每次进入都回到顶部：不回到顶部会从上次位置打开，看起来像“内容错位”
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Top);
    }, 80);
  }

  aboutToDisappear(): void {
    stopWatchColorMode(getContext(this) as common.UIAbilityContext, this.envWatchId);
    this.envWatchId = -1;
  }

  build() {
    Stack() {
      // 顶部光感：与其它页面同一层径向光
      Column()
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .radialGradient({
          center: ['50%', '24%'],
          radius: '200%',
          colors: [
            [this.tint.glow, 0.0],
            [this.tint.glowEdge, 1.0]
          ]
        })
        .opacity(0.08)
        .hitTestBehavior(HitTestMode.None)

      Column() {
      Row() {
        if (!this.consentMode) {
          Stack() {
            Text('‹')
              .fontSize(28)
              .fontColor($r('app.color.text_primary'))
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .accessibilityText($r('app.string.nav_back'))
          .onClick(() => {
            this.onBack();
          })
        }

        Blank()

        Text($r('app.string.privacy_page_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Stack()
          .width(44)
          .height(44)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12 })

      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Text($r('app.string.privacy_policy_updated'))
            .width('100%')
            .fontSize(12)
            .fontColor($r('app.color.text_placeholder'))

          Text($r('app.string.privacy_policy_body'))
            .width('100%')
            .fontSize(15)
            .lineHeight(26)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      if (this.consentMode) {
        Row({ space: 12 }) {
          Column() {
            Text($r('app.string.privacy_consent_disagree'))
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
          }
          .layoutWeight(1)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.button_secondary_bg'))
          .borderRadius(24)
          .onClick(() => {
            this.exitApp();
          })

          Column() {
            Text($r('app.string.privacy_consent_agree'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.white'))
          }
          .layoutWeight(1)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(24)
          .opacity(this.busy ? 0.5 : 1)
          .onClick(() => {
            this.agree();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 28 })
      }
    }
    .width('100%')
    .height('100%')
    // 全屏布局下内容从 y=0 开始，不加安全区会被状态栏和前置摄像头挖孔压住
      .padding({ top: $r('app.float.space_header_safe') })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    // 与主页同一层渐变，避免其他页面是“平的”一块色
    .linearGradient({
      angle: 180,
      // 顶部浅一档：和主页的顶部光感呼应，避免子页像一块平色
      colors: [[this.tint.top, 0.0], [this.tint.bottom, 1.0]]
    })
  }

  private async prepare(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await appStore.init(context);
      applyTheme(context, appStore.settings);
    } catch (e) {
      // 读取设置失败时使用默认主题，不阻断隐私页展示
    }
  }

  // 同意：落库成功后再通知宿主跳转，失败留在本页可重试（busy 由本组件管）
  private async agree(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await appStore.init(context);
      const ok = await appStore.acceptPrivacy(PRIVACY_REQUIRED_VERSION);
      if (ok) {
        this.onAgree();
        return;
      }
      this.toast($r('app.string.privacy_save_failed'));
    } catch (e) {
      this.toast($r('app.string.privacy_save_failed'));
    } finally {
      this.busy = false;
    }
  }

  // 「不同意」是拒绝授权直接退出应用，语义上不是"返回上一页"，因此不走 onBack
  private exitApp(): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.terminateSelf();
    } catch (e) {
      // 退失败时停留在隐私页，不进入主页
    }
  }

  private toast(message: Resource): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
