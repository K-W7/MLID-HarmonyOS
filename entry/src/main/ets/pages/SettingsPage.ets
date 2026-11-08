import { router } from '@kit.ArkUI';
import { SettingsContent } from '../components/SettingsContent';

/**
 * 设置页壳：保留 @Entry，供还没迁到 Navigation 的 router 入口使用。
 * 内容、状态与生命周期全部在 SettingsContent 中；这里只做路由接线：
 * 返回走 router.back()，隐私政策走 router.pushUrl()（Navigation 版由宿主 push NavDestination）。
 * 迁到 NavDestination 时直接复用 SettingsContent，需要时再把本文件删掉。
 */
@Entry
@ComponentV2
struct SettingsPage {
  build() {
    // @Entry 的 build 根节点必须是容器组件，自定义组件外包一层 Column
    Column() {
      SettingsContent({
        onBack: () => {
          router.back();
        },
        onOpenPrivacy: () => {
          router.pushUrl({ url: 'pages/PrivacyPage', params: { mode: 'read' } });
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
