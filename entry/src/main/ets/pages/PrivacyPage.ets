import { router } from '@kit.ArkUI';
import { PrivacyContent } from '../components/PrivacyContent';

/**
 * S-05 隐私政策页壳：保留 @Entry，供还没迁到 Navigation 的 router 入口使用。
 * 只剩两件事：从 router 参数决定 consent / read 两态，以及同意后跳主页。
 * 界面、busy 态、同意落库都在 PrivacyContent 中；返回走 router.back()。
 */
@Entry
@ComponentV2
struct PrivacyPage {
  @Local consentMode: boolean = false;

  aboutToAppear(): void {
    // 照旧读 router 参数：mode === 'read' 是只读查看，其余（含无参数）都是启动同意态
    let consent = true;
    const params = router.getParams() as Record<string, Object>;
    if (params !== null && params !== undefined) {
      const mode = params['mode'];
      if (mode !== undefined && `${mode}` === 'read') {
        consent = false;
      }
    }
    this.consentMode = consent;
  }

  build() {
    // @Entry 的 build 根节点必须是容器组件，自定义组件外包一层 Column
    Column() {
      PrivacyContent({
        consentMode: this.consentMode,
        onBack: () => {
          router.back();
        },
        onAgree: () => {
          router.replaceUrl({ url: 'pages/CalendarPage' });
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
