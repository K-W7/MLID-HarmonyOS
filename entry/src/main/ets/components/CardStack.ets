import { common } from '@kit.AbilityKit';
import { RecordItem } from '../model/RecordItem';
import { itemDayKey } from '../store/AppStore';
import { resolveImageUri } from '../utils/ImageStore';
import { curves } from '@kit.ArkUI';
import { motionDuration } from '../utils/MotionUtil';

/**
 * 通用卡片堆叠（昨日回望 / 随机一条共用）。
 *
 * 为什么是组件：堆叠需要自己的拖拽状态（@Local），且父级数据变化时要靠 @Param 刷新。
 * 划走只是翻看，不删除任何记录。
 */
@ComponentV2
export struct CardStack {
  @Param items: RecordItem[] = [];
  @Param emptyText: string = '还没有记录。';
  @Event onOpen: (item: RecordItem) => void = () => {
  };

  @Local cursor: number = 0;
  @Local dragX: number = 0;
  // 手指按在卡片上时轻微收缩，松手回弹
  @Local pressed: boolean = false;

  aboutToAppear(): void {
    this.cursor = 0;
  }

  @Monitor('items')
  onItemsChanged(): void {
    this.cursor = 0;
    this.dragX = 0;
  }

  build() {
    Column({ space: 10 }) {
      if (this.items.length === 0) {
        Text(this.emptyText)
          .width('100%')
          .fontSize($r('app.float.font_meta'))
          .fontColor($r('app.color.text_placeholder'))
          .padding({ top: 2, bottom: 2 })
      } else {
        Stack({ alignContent: Alignment.Top }) {
          // 只渲染最上面 3 张，越靠上层级越高
          ForEach(this.visibleItems(), (item: RecordItem, offset: number) => {
            this.card(item, offset)
          }, (item: RecordItem) => `stack_${item.id}_${this.cursor}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 层叠向上偏移，留出上方空间，避免压住区块标题
    .padding({ top: 22, bottom: 6 })
  }

  /** 拖动位移的阻尼：越拖越沉，避免 1:1 的“滑顺”感 */
  private dampedX(): number {
    const sign = this.dragX >= 0 ? 1 : -1;
    const magnitude = Math.abs(this.dragX);
    return sign * magnitude * 0.6;
  }

  private visibleItems(): RecordItem[] {
    const result: RecordItem[] = [];
    if (this.items.length === 0) {
      return result;
    }
    // 循环：永远取最上面的 3 张，末尾自动绕回开头
    const count = Math.min(3, this.items.length);
    for (let k = 0; k < count; k++) {
      result.push(this.items[(this.cursor + k) % this.items.length]);
    }
    return result;
  }

  @Builder
  card(item: RecordItem, offset: number) {
    // 所有卡片固定同样的高度；时间单独占顶部一行，正文放大一档
    Column({ space: 10 }) {
      Text(this.metaText(item))
        .width('100%')
        .fontSize($r('app.float.font_meta_small'))
        .fontColor($r('app.color.text_secondary'))

      Row({ space: 14 }) {
        Text(this.preview(item))
          .layoutWeight(1)
          .fontSize($r('app.float.font_body'))
          .lineHeight($r('app.float.line_body'))
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (item.images.length > 0) {
          // 图片靠右，与正文并排
          Image(this.imageUri(item.images[0]))
            .width(88)
            .height(88)
            .borderRadius($r('app.float.radius_image'))
            .objectFit(ImageFit.Cover)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(132)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius($r('app.float.radius_card'))
    .border({ width: 1, color: $r('app.color.shadow_card') })
    // 越往下越小、越往上叠；按下时再收 2%，给出触感反馈
    .scale({
      x: (1 - offset * 0.04) * (this.pressed ? 0.98 : 1),
      y: (1 - offset * 0.04) * (this.pressed ? 0.98 : 1)
    })
    .animation({ duration: motionDuration(120), curve: Curve.EaseOut })
    // 阻尼：跟手只走 72%，手感更“重”，不再是 1:1 滑动
    .translate({ y: -offset * 12, x: offset === 0 ? this.dampedX() : 0 })
    // 跟手轻微旋转，划起来更像卡片
    .rotate({ angle: offset === 0 ? this.dragX / 30 : 0 })
    .zIndex(10 - offset)
    .opacity(offset === 0 ? 1 - Math.min(Math.abs(this.dragX) / 900, 0.35) : 1)
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 5 })
        .onActionStart(() => {
          this.dragX = 0;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (offset !== 0) {
            return;
          }
          this.dragX = event.offsetX;
        })
        .onActionCancel(() => {
          // 手势被列表滚动打断时也要归零，否则卡片会歪着停住
          animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
            this.dragX = 0;
          });
        })
        .onActionEnd(() => {
          if (offset !== 0) {
            return;
          }
          if (Math.abs(this.dragX) > 80) {
            animateTo({ duration: motionDuration(220), curve: Curve.EaseOut }, () => {
              this.dragX = this.dragX > 0 ? 600 : -600;
            });
            setTimeout(() => {
              // 循环推进：最后一张划走后回到第一张；下层卡片用弹性曲线升上来
              animateTo({ duration: motionDuration(260), curve: curves.springMotion(0.45, 0.9) }, () => {
                this.cursor = (this.cursor + 1) % this.items.length;
                this.dragX = 0;
              });
            }, 220);
          } else {
            animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              this.dragX = 0;
            });
          }
        })
    )
    // 兜底：任何抬手/取消都复位，避免手势被子列表抢走后 dragX 停在半路
    .onTouch((event: TouchEvent) => {
      this.pressed = event.type === TouchType.Down;
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (Math.abs(this.dragX) <= 80) {
          animateTo({ duration: motionDuration(150), curve: Curve.EaseOut }, () => {
            this.dragX = 0;
          });
        }
      }
    })
    .onClick(() => {
      this.onOpen(item);
    })
  }

  private imageUri(name: string): string {
    const context = getContext(this) as common.UIAbilityContext;
    return resolveImageUri(context, name);
  }

  private pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private metaText(item: RecordItem): string {
    // 日期取业务日（dateKey），时间取真实写入时刻：补记的卡片不会再把日期写成「写的那天」
    const date = new Date(item.timestamp);
    const key = itemDayKey(item);
    const parts = key.split('-');
    const year = parts.length === 3 ? Number(parts[0]) : date.getFullYear();
    const month = parts.length === 3 ? Number(parts[1]) : date.getMonth() + 1;
    const day = parts.length === 3 ? Number(parts[2]) : date.getDate();
    return `${year}年${month}月${day}日 ${this.pad(date.getHours())}:${this.pad(date.getMinutes())}`;
  }

  private preview(item: RecordItem): string {
    const text = item.content.trim();
    if (text !== '') {
      return text;
    }
    if (item.images.length > 0) {
      return `图片记录 · ${item.images.length} 张`;
    }
    return '无文字记录';
  }
}
