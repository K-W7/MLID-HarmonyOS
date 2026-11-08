import { curves, uiMaterial } from '@kit.ArkUI';
import { motionDuration } from '../utils/MotionUtil';
import { common } from '@kit.AbilityKit';
import { thinMaterial } from '../utils/MaterialUtil';
import { Mood } from '../model/Mood';
import { DraftPayload, MAX_IMAGES, MAX_MOODS, QuoteRef } from '../model/RecordItem';
import { MoodChip } from './MoodChip';
import { pickAndStoreImages, resolveImageUri } from '../utils/ImageStore';

const ALL_MOODS: Mood[] = [Mood.NONE, Mood.HAPPY, Mood.CALM, Mood.TIRED, Mood.IRRITABLE, Mood.LOW];

// 与 app.float.chip_bar_height 保持一致，用于高度动画
const CHIP_BAR_HEIGHT: number = 52;

@ComponentV2
export struct FloatingIsland {
  @Param openToken: number = 0;
  @Param prefillToken: number = 0;
  @Param prefillContent: string = '';
  @Param prefillMoods: Mood[] = [];
  @Param prefillImages: string[] = [];
  @Param prefillParentId: string = '';
  @Param prefillEditingId: string = '';
  @Param prefillQuote: QuoteRef | null = null;
  @Param defaultMood: Mood = Mood.NONE;
  @Param placeholderText: string = '';
  @Local inputText: string = '';
  @Local selectedMoods: Mood[] = [];
  @Local selectedImages: string[] = [];
  @Local isExpanded: boolean = false;
  // 只有用户手指点过输入框，焦点才允许展开（防止进页自动抢焦点）
  @Local userTouched: boolean = false;
  @Local chipBarHeight: number = 0;
  @Local chipBarOpacity: number = 0;
  @Local chipBarScale: number = 0.92;
  @Local chipBarTranslateY: number = 8;
  @Local parentId: string = '';
  @Local editingId: string = '';
  @Local quote: QuoteRef | null = null;

  @Event onSave: (payload: DraftPayload) => void = () => {
  };

  @Event onCancelEdit: () => void = () => {
  };

  /** 展开/收起变化时通知宿主，宿主用它决定要不要显示草稿卡 */
  @Event onExpandedChanged: (expanded: boolean) => void = () => {
  };

  /** 未提交内容变化时回调，由页面按 dateKey 落草稿 */
  @Event onDraftChanged: (payload: DraftPayload) => void = () => {
  };

  private draftTimer: number = -1;
  private static readonly DRAFT_DEBOUNCE: number = 300;
  // 底部悬浮操作栏使用官方沉浸光感"薄"材质，浮于内容之上形成通透层次
  private readonly dockMaterial: uiMaterial.Material = thinMaterial();

  aboutToDisappear(): void {
    if (this.draftTimer >= 0) {
      clearTimeout(this.draftTimer);
      this.draftTimer = -1;
    }
  }

  aboutToAppear(): void {
    if (this.prefillToken > 0) {
      // 有草稿只把内容填回去，不展开：一进页面就弹胶囊和键盘太吵
      this.applyPrefill();
    }
    // 不管有没有草稿，进来都先收起并清焦点：
    // 恢复的输入框会自己拿焦点，把胶囊和键盘一起带出来
    this.ensureCollapsed();
    if (this.defaultMood !== Mood.NONE) {
      this.selectedMoods = [this.defaultMood];
    }
  }

  @Monitor('openToken')
  onOpenTokenChanged(): void {
    this.expand();
  }

  @Monitor('prefillToken')
  onPrefillTokenChanged(): void {
    // 只把草稿填回输入框，不自动展开：一进页面就弹键盘太吵
    this.applyPrefill();
  }

  @Monitor('defaultMood')
  onDefaultMoodChanged(): void {
    if (this.isExpanded || this.editingId !== '' || this.selectedMoods.length > 0) {
      return;
    }
    this.selectedMoods = this.defaultMood !== Mood.NONE ? [this.defaultMood] : [];
  }

  @Builder
  chipBar() {
    Row({ space: 10 }) {
      ForEach(ALL_MOODS, (mood: Mood) => {
        MoodChip({
          mood: mood,
          selected: this.selectedMoods.includes(mood),
          onSelect: (picked: Mood) => {
            this.toggleMood(picked);
          }
        })
      }, (mood: Mood) => `${mood}`)
    }
    .width('100%')
    .height(this.chipBarHeight)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .opacity(this.chipBarOpacity)
    .scale({ x: this.chipBarScale, y: this.chipBarScale })
    .translate({ y: this.chipBarTranslateY })
    .clip(true)
  }

  @Builder
  imageStrip() {
    Row({ space: 8 }) {
      ForEach(this.selectedImages, (name: string) => {
        Stack({ alignContent: Alignment.TopEnd }) {
          Image(this.imageUri(name))
            .width($r('app.float.image_thumb'))
            .height($r('app.float.image_thumb'))
            .borderRadius($r('app.float.radius_image'))
            .objectFit(ImageFit.Cover)
            .syncLoad(false)
          Text('×')
            .width(18)
            .height(18)
            .textAlign(TextAlign.Center)
            .fontSize($r('app.float.font_meta'))
            .fontColor($r('app.color.white'))
            .backgroundColor($r('app.color.overlay_scrim'))
            .borderRadius(9)
            .onClick(() => {
              this.removeImage(name);
            })
        }
      }, (name: string) => name)
    }
    .width('100%')
    .margin({ top: 8 })
  }

  build() {
    Column({ space: 0 }) {
      if (this.editingId !== '') {
        Row() {
          Text('正在编辑这条记录')
            .fontSize($r('app.float.font_meta_small'))
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text('取消')
            .fontSize($r('app.float.font_meta_small'))
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.cancelEdit();
            })
        }
        .width('100%')
        .margin({ bottom: 8 })
      }

      if (this.quote !== null) {
        Row({ space: 8 }) {
          Text(`引用：${this.quote.content}`)
            .fontSize($r('app.float.font_meta_small'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('×')
            .fontSize($r('app.float.font_meta'))
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.quote = null;
              this.notifyDraft();
            })
        }
        .width('100%')
        .padding(8)
        .backgroundColor($r('app.color.quote_bg'))
        .borderRadius($r('app.float.radius_image'))
        .margin({ bottom: 8 })
      }

      this.chipBar()

      if (this.selectedImages.length > 0) {
        this.imageStrip()
      }

      Row({ space: 8 }) {
        TextArea({
          text: this.inputText,
          placeholder: this.placeholderText !== '' ? this.placeholderText : $r('app.string.placeholder_input')
        })
          .layoutWeight(1)
          .constraintSize({ minHeight: 40, maxHeight: 132 })
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_placeholder'))
          .backgroundColor($r('app.color.button_secondary_bg'))
          .borderRadius($r('app.float.radius_input'))
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .maxLength(10000)
          .id('dock_input')
          .focusable(true)
          .onChange((value: string) => {
            this.inputText = value;
            this.notifyDraft();
          })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.userTouched = true;
            }
          })
          .onFocus(() => {
            if (this.userTouched) {
              this.expand();
            }
          })
          .onBlur(() => {
            // 失焦且什么都没写，就收起：情绪胶囊不该常驻
            const empty = this.inputText === ''
              && this.selectedMoods.length === 0
              && this.selectedImages.length === 0
              && this.editingId === '';
            if (empty) {
              this.collapse();
            }
          })

        Stack() {
          Stack() {
            Text('+')
              .fontSize(22)
              .fontColor($r('app.color.text_primary'))
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.button_secondary_bg'))
        }
        .width($r('app.float.icon_touch'))
        .height($r('app.float.icon_touch'))
        .accessibilityText('添加图片')
        .onClick(() => {
          this.addImages();
        })

        Stack() {
          Stack() {
            Text('↑')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.white'))
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.brand_primary'))
          .opacity(this.canSend() ? 1 : 0.35)
        }
        .width($r('app.float.icon_touch'))
        .height($r('app.float.icon_touch'))
        .accessibilityText('保存记录')
        .onClick(() => {
          this.send();
        })
      }
      .width('100%')
      .margin({ top: this.chipBarHeight > 0 ? 8 : 0 })
    }
    .width('100%')
    .padding($r('app.float.space_dock_pad'))
    .borderRadius($r('app.float.radius_dock'))
    // 官方沉浸光感：薄材质替代实色背景 + 手写阴影，形成浮于纸面的通透光感
    .systemMaterial(this.dockMaterial)
  }

  private applyPrefill(): void {
    this.inputText = this.prefillContent;
    this.selectedMoods = this.cloneMoods(this.prefillMoods);
    this.selectedImages = this.cloneStrings(this.prefillImages);
    this.parentId = this.prefillParentId;
    this.editingId = this.prefillEditingId;
    this.quote = this.prefillQuote;
  }

  private cloneMoods(source: Mood[]): Mood[] {
    const copy: Mood[] = [];
    for (let i = 0; i < source.length; i++) {
      copy.push(source[i]);
    }
    return copy;
  }

  private cloneStrings(source: string[]): string[] {
    const copy: string[] = [];
    for (let i = 0; i < source.length; i++) {
      copy.push(source[i]);
    }
    return copy;
  }

  private imageUri(name: string): string {
    const context = getContext(this) as common.UIAbilityContext;
    return resolveImageUri(context, name);
  }

  /** 静默收起：不播动画，直接归位，用于进页时 */
  private ensureCollapsed(): void {
    this.userTouched = false;
    this.isExpanded = false;
    this.chipBarHeight = 0;
    this.chipBarOpacity = 0;
    this.onExpandedChanged(false);
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().clearFocus();
      } catch (e) {
        // 忽略
      }
    }, 60);
  }

  private expand(): void {
    this.isExpanded = true;
    this.onExpandedChanged(true);
    animateTo({ duration: motionDuration(360), curve: curves.springMotion(0.6, 0.8) }, () => {
      this.chipBarHeight = CHIP_BAR_HEIGHT;
      this.chipBarOpacity = 1;
      this.chipBarScale = 1;
      this.chipBarTranslateY = 0;
    });
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus('dock_input');
      } catch (e) {
        // 输入框尚未挂载时忽略
      }
    }, 80);
  }

  private collapse(): void {
    this.isExpanded = false;
    this.onExpandedChanged(false);
    animateTo({ duration: motionDuration(220), curve: Curve.EaseIn }, () => {
      this.chipBarHeight = 0;
      this.chipBarOpacity = 0;
      this.chipBarScale = 0.92;
      this.chipBarTranslateY = 8;
    });
  }

  private toggleMood(mood: Mood): void {
    if (mood === Mood.NONE) {
      if (this.selectedMoods.includes(Mood.NONE)) {
        this.selectedMoods = [];
      } else {
        this.selectedMoods = [Mood.NONE];
      }
      this.notifyDraft();
      return;
    }
    const next: Mood[] = [];
    for (let i = 0; i < this.selectedMoods.length; i++) {
      if (this.selectedMoods[i] !== Mood.NONE && this.selectedMoods[i] !== mood) {
        next.push(this.selectedMoods[i]);
      }
    }
    if (!this.selectedMoods.includes(mood) && next.length < MAX_MOODS) {
      next.push(mood);
    }
    this.selectedMoods = next;
    this.notifyDraft();
  }

  private async addImages(): Promise<void> {
    const remain = MAX_IMAGES - this.selectedImages.length;
    if (remain <= 0) {
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const names = await pickAndStoreImages(context, remain);
      if (names.length > 0) {
        this.selectedImages = this.selectedImages.concat(names);
        this.notifyDraft();
      }
    } catch (e) {
      // 用户取消选择时不做处理
    }
  }

  private removeImage(name: string): void {
    const next: string[] = [];
    for (let i = 0; i < this.selectedImages.length; i++) {
      if (this.selectedImages[i] !== name) {
        next.push(this.selectedImages[i]);
      }
    }
    this.selectedImages = next;
    this.notifyDraft();
  }

  private canSend(): boolean {
    return this.inputText.trim() !== '' || this.selectedImages.length > 0;
  }

  private buildDraft(): DraftPayload {
    return {
      content: this.inputText,
      moods: this.cloneMoods(this.selectedMoods),
      images: this.cloneStrings(this.selectedImages),
      parentId: this.parentId,
      quote: this.quote,
      editingId: this.editingId
    };
  }

  /** 300ms 防抖后把未提交内容交给页面落草稿 */
  private notifyDraft(): void {
    if (this.draftTimer >= 0) {
      clearTimeout(this.draftTimer);
    }
    this.draftTimer = setTimeout(() => {
      this.draftTimer = -1;
      this.onDraftChanged(this.buildDraft());
    }, FloatingIsland.DRAFT_DEBOUNCE);
  }

  private send(): void {
    if (!this.canSend()) {
      return;
    }
    this.onSave(this.buildDraft());
    this.resetDraft();
    this.collapse();
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
      // 忽略失焦失败
    }
  }

  private resetDraft(): void {
    if (this.draftTimer >= 0) {
      clearTimeout(this.draftTimer);
      this.draftTimer = -1;
    }
    this.inputText = '';
    this.selectedMoods = [];
    this.selectedImages = [];
    this.parentId = '';
    this.editingId = '';
    this.quote = null;
  }

  private cancelEdit(): void {
    this.resetDraft();
    this.collapse();
    this.onCancelEdit();
  }
}
