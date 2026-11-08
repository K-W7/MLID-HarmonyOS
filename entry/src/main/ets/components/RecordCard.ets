import { common } from '@kit.AbilityKit';
import { QuoteRef, RecordItem } from '../model/RecordItem';
import { Mood } from '../model/Mood';
import { getMoodColor } from '../model/MoodMeta';
import { resolveImageUri } from '../utils/ImageStore';

function formatTime(timestamp: number): string {
  const date = new Date(timestamp);
  const hour = date.getHours() < 10 ? `0${date.getHours()}` : `${date.getHours()}`;
  const minute = date.getMinutes() < 10 ? `0${date.getMinutes()}` : `${date.getMinutes()}`;
  return `${hour}:${minute}`;
}

@ComponentV2
export struct RecordCard {
  @Require @Param record: RecordItem;
  @Param showActions: boolean = true;
  @Local expanded: boolean = false;
  @Local offsetX: number = 0;
  @Local cardHeight: number = 0;
  private startOffset: number = 0;

  @Event onDelete: (id: string) => void = () => {
  };

  @Event onEdit: (record: RecordItem) => void = () => {
  };

  @Event onQuote: (record: RecordItem) => void = () => {
  };

  @Event onPreview: (images: string[], index: number) => void = () => {
  };

  @Builder
  quoteBlock() {
    Row({ space: 8 }) {
      Text(this.quoteContent())
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
        .lineHeight($r('app.float.line_body_small'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.quoteImage() !== '') {
        Image(this.imageUri(this.quoteImage()))
          .width($r('app.float.image_quote'))
          .height($r('app.float.image_quote'))
          .borderRadius($r('app.float.radius_image'))
          .objectFit(ImageFit.Cover)
          .syncLoad(false)
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.quote_bg'))
    .borderRadius($r('app.float.radius_image'))
    .margin({ bottom: 10 })
  }

  @Builder
  singleImage() {
    Image(this.imageUri(this.record.images[0]))
      .width('60%')
      .height($r('app.float.image_card_h'))
      .borderRadius($r('app.float.radius_image'))
      .objectFit(ImageFit.Cover)
      .syncLoad(false)
      // 与全屏预览共用同一个 id，点开时是同一张图长大，不是淡入一个新层
      .geometryTransition(`img-${this.record.images[0]}`)
      .onClick(() => {
        this.onPreview(this.record.images, 0);
      })
  }

  @Builder
  imageGrid() {
    Row({ space: 6 }) {
      ForEach(this.record.images, (name: string, index: number) => {
        Image(this.imageUri(name))
          .layoutWeight(1)
          .height($r('app.float.image_card_h'))
          .borderRadius($r('app.float.radius_image'))
          .objectFit(ImageFit.Cover)
          .syncLoad(false)
          .onClick(() => {
            this.onPreview(this.record.images, index);
          })
      }, (name: string, index: number) => `${name}_${index}`)
    }
    .width('100%')
  }

  @Builder
  moodDots() {
    Row({ space: 4 }) {
      ForEach(this.record.moods, (mood: Mood) => {
        Circle({ width: 6, height: 6 })
          .fill(getMoodColor(mood))
      }, (mood: Mood) => `${mood}`)
    }
  }

  @Builder
  actionButtons() {
    Row() {
      Column() {
        Text($r('app.string.action_quote'))
          .fontSize($r('app.float.font_meta'))
          .fontColor($r('app.color.text_secondary'))
      }
      .width($r('app.float.swipe_action_w'))
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.button_secondary_bg'))
      .onClick(() => {
        this.closeActions();
        this.onQuote(this.record);
      })

      Column() {
        Text($r('app.string.action_delete'))
          .fontSize($r('app.float.font_meta'))
          .fontColor($r('app.color.danger_low_sat'))
      }
      .width($r('app.float.swipe_action_w'))
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.button_secondary_bg'))
      .onClick(() => {
        this.closeActions();
        this.onDelete(this.record.id);
      })
    }
    .width($r('app.float.swipe_total_w'))
    .height(this.cardHeight)
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.End }) {
        if (this.showActions && this.offsetX < 0) {
          this.actionButtons()
        }

        Column() {
          if (this.hasQuote()) {
            this.quoteBlock()
          }

          if (this.record.content !== '') {
            Text(this.record.content)
              .width('100%')
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
              .lineHeight($r('app.float.line_body'))
              .maxLines(this.expanded ? 40 : 4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }


          if (this.record.images.length === 1) {
            this.singleImage()
          } else if (this.record.images.length > 1) {
            this.imageGrid()
          }

          Row({ space: 6 }) {
            if (this.record.isBackfill === true) {
              Text($r('app.string.backfill_tag'))
                .fontSize($r('app.float.font_meta_small'))
                .fontColor($r('app.color.text_secondary'))
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .backgroundColor($r('app.color.button_secondary_bg'))
                .borderRadius(4)
              Text(this.backfillHint())
                .fontSize($r('app.float.font_meta_small'))
                .fontColor($r('app.color.text_placeholder'))
            } else {
              Text(formatTime(this.record.timestamp))
                .fontSize($r('app.float.font_meta_small'))
                .fontColor($r('app.color.text_secondary'))
            }
            Blank()
            this.moodDots()
            // 长文才有「展开/收起」，和情绪点同一行：点会被它往左挤一格
            if (this.isLongContent()) {
              Text(this.expanded ? '收起' : '展开')
                .fontSize($r('app.float.font_meta_small'))
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 10 })
                .padding({ top: 2, bottom: 2 })
            }
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .padding($r('app.float.space_card_pad'))
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius($r('app.float.radius_card'))
        .border({ width: 1, color: $r('app.color.shadow_card') })
        // 卡片浮起一层，避免在渐变底上“糊”成一片
        .shadow({ radius: 10, color: $r('app.color.shadow_card'), offsetY: 3 })
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.cardHeight = Number(newArea.height);
        })
        .translate({ x: this.offsetX })
        .onClick(() => {
          this.onCardTap();
        })
      }
      .width('100%')
      .borderRadius($r('app.float.radius_card'))
      .clip(true)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
            .onActionStart(() => {
              this.startOffset = this.offsetX;
            })
            .onActionUpdate((event: GestureEvent) => {
              let next = this.startOffset + event.offsetX;
              if (next > 0) {
                next = 0;
              }
              if (next < -140) {
                next = -140;
              }
              this.offsetX = next;
            })
            .onActionEnd(() => {
              animateTo({ duration: 240, curve: Curve.Friction }, () => {
                this.offsetX = this.offsetX < -70 ? -140 : 0;
              });
            }),
          LongPressGesture({ fingers: 1, duration: 450 })
            .onAction(() => {
              if (this.offsetX !== 0) {
                this.closeActions();
              } else {
                this.onEdit(this.record);
              }
            })
        )
      )
    }
    .width('100%')
    .borderRadius($r('app.float.radius_card'))
    .shadow({ radius: 6, color: $r('app.color.shadow_card'), offsetY: 2 })
  }

  private imageUri(name: string): string {
    const context = getContext(this) as common.UIAbilityContext;
    return resolveImageUri(context, name);
  }

  private isLongContent(): boolean {
    return this.record.content.length > 90;
  }

  /** 补记辅助信息：补记于 M月D日 HH:mm，跨年补年份；时间为实际补写时间 */
  private backfillHint(): string {
    const date = new Date(this.record.timestamp);
    const hour = date.getHours() < 10 ? `0${date.getHours()}` : `${date.getHours()}`;
    const minute = date.getMinutes() < 10 ? `0${date.getMinutes()}` : `${date.getMinutes()}`;
    const now = new Date();
    if (date.getFullYear() === now.getFullYear()) {
      return `补记于 ${date.getMonth() + 1}月${date.getDate()}日 ${hour}:${minute}`;
    }
    return `补记于 ${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 ${hour}:${minute}`;
  }

  private hasQuote(): boolean {
    return this.record.quote !== undefined;
  }

  private quoteContent(): string {
    const quote: QuoteRef | undefined = this.record.quote;
    return quote !== undefined ? quote.content : '';
  }

  private quoteImage(): string {
    const quote: QuoteRef | undefined = this.record.quote;
    return quote !== undefined ? quote.image : '';
  }

  private closeActions(): void {
    animateTo({ duration: 240, curve: Curve.Friction }, () => {
      this.offsetX = 0;
    });
  }

  private onCardTap(): void {
    if (this.offsetX !== 0) {
      this.closeActions();
      return;
    }
    if (this.isLongContent()) {
      this.expanded = !this.expanded;
    }
  }
}
