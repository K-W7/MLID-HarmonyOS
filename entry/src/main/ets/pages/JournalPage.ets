import { router } from '@kit.ArkUI';
import { JournalContent } from '../components/JournalContent';

/**
 * 单日详情页壳：保留 @Entry，供还没迁到 Navigation 的 router 入口使用。
 * 内容全部在 JournalContent 中；日期来自 router 参数，返回走 router.back()。
 * 迁到 NavDestination 时直接复用 JournalContent，需要时再把本文件删掉。
 */
@Entry
@ComponentV2
struct JournalPage {
  @Local year: number = 0;
  @Local month: number = 0;
  @Local day: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params !== null && params !== undefined) {
      const yearValue = params['year'];
      const monthValue = params['month'];
      const dayValue = params['day'];
      if (yearValue !== undefined) {
        this.year = Number(yearValue);
      }
      if (monthValue !== undefined) {
        this.month = Number(monthValue);
      }
      if (dayValue !== undefined) {
        this.day = Number(dayValue);
      }
    }
    // 兜底：直开页面没带参数时，沿用拆分前"默认今天"的行为
    if (this.year <= 0 || this.month <= 0 || this.day <= 0) {
      const today = new Date();
      this.year = today.getFullYear();
      this.month = today.getMonth() + 1;
      this.day = today.getDate();
    }
  }

  build() {
    // @Entry 的 build 根节点必须是容器组件，自定义组件外包一层 Column
    Column() {
      JournalContent({
        year: this.year,
        month: this.month,
        day: this.day,
        onBack: () => {
          router.back();
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
