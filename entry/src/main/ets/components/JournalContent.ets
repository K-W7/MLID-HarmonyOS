import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { motionDuration } from '../utils/MotionUtil';
import { DraftPayload, QuoteRef, RecordItem } from '../model/RecordItem';
import { Mood } from '../model/Mood';
import { getMoodColor } from '../model/MoodMeta';
import { getLunarDate, getWeekdayName } from '../model/CalendarUtils';
import { getLunarMonthName } from '../model/FestivalData';
import { getAfterSaveCopy, getEmptyCopy } from '../model/MoodMeta';
import { DEFAULT_MOOD_LAST } from '../model/AppSettings';
import { RecordCard } from './RecordCard';
import { FloatingIsland } from './FloatingIsland';
import RecordsDataSource from '../store/RecordsDataSource';
import { appStore, dateKeyOf, todayKey } from '../store/AppStore';
import { applyTheme } from '../utils/ThemeUtil';
import { resolveImageUri } from '../utils/ImageStore';
import { currentTint, stopWatchColorMode, watchColorMode } from '../utils/TintProvider';
import { MoodTint, tintForTime } from '../utils/MoodTint';

/**
 * 单日详情内容，由页面壳（router 版 JournalPage）或 Navigation 的 NavDestination 承载。
 * 日期从外部传入，内部不再读 router 参数；返回动作通过 onBack 回调交给宿主处理。
 */
@ComponentV2
export struct JournalContent {
  @Param year: number = 0;
  @Param month: number = 0;
  @Param day: number = 0;
  // 回调用 @Event（V2 中 @Param 不接受 function 类型），对外调用方式与 @Param 一致
  @Event onBack: () => void = () => {
  };
  // 数据变化通知宿主页：在用户还看着单日页时就把主页数据刷新好，退回时才不会跳变
  @Event onDataChanged: () => void = () => {
  };

  @Local dateTitle: string = '';
  @Local dateSubtitle: string = '';
  @Local isEmpty: boolean = true;
  @Local emptyCopy: string = '';
  @Local recordCount: number = 0;
  @Local defaultMood: Mood = Mood.NONE;
  @Local listVersion: number = 0;
  // 列表入场：淡入 + 轻微上移，避免一进页面「啪」地出现
  // 空态 ↔ 列表：切换时先淡出再淡入，不硬切
  @Local stateAlpha: number = 1;
  // 输入岛是否展开：收起时不显示草稿卡
  @Local islandExpanded: boolean = false;
  // 展开态（含键盘）时列表底部要多留一截，否则最后一张卡被岛压住
  @Local keyboardPad: number = 0;
  // 窗口宽度（宽屏限宽居中）
  @Local winWidth: number = 360;
  // 删除收拢：被删的那条先压扁再移除，下面的卡片顺势补位
  @Local removingId: string = '';
  @Local removeScaleY: number = 1;
  @Local removeAlpha: number = 1;
  @Local listAlpha: number = 0;
  @Local listShift: number = 12;
  // 草稿卡：边写边在列表尾部实时显示，保存时这张卡滑下去并弹一下
  @Local draftContent: string = '';
  @Local draftMoods: Mood[] = [];
  @Local draftImages: string[] = [];
  @Local draftBounce: number = 1;
  @Local draftSink: number = 0;

  // 「保存落笔」：刚写入的那条卡片从输入区位置落进列表
  @Local newRecordId: string = '';
  @Local landedAlpha: number = 1;
  @Local landedOffset: number = 0;
  @Local prefillToken: number = 0;
  @Local prefillContent: string = '';
  @Local prefillMoods: Mood[] = [];
  @Local prefillImages: string[] = [];
  @Local prefillParentId: string = '';
  @Local prefillEditingId: string = '';
  @Local prefillQuote: QuoteRef | null = null;
  @Local previewVisible: boolean = false;
  @Local previewImages: string[] = [];
  @Local previewIndex: number = 0;
  @Local islandHeight: number = 96;
  @Local showUndo: boolean = false;
  @Local isFuture: boolean = false;
  private dataSource: RecordsDataSource = new RecordsDataSource([]);
  private listScroller: Scroller = new Scroller();
  // 主题变化监听 + 色温缓存
  private envWatchId: number = -1;
  @Local tint: MoodTint = tintForTime(new Date().getHours(), true);
  private lastDeleted: RecordItem[] = [];
  private undoTimer: number = -1;
  // 进页面那天是不是「今天」：用于跨午夜判断（用户一直把这页开着，过了 00:00 再写）
  private openedAsToday: boolean = false;

  private refreshTint(): void {
    const next = currentTint(getContext(this) as common.UIAbilityContext);
    // 主题切换留 1.2s 过渡：直接赋值会硬切，观感很生硬
    this.getUIContext().animateTo({ duration: 1200, curve: Curve.EaseInOut }, () => {
      this.tint = next;
    });
  }

  aboutToAppear(): void {
    this.openedAsToday = this.dayKey() === todayKey();
    this.refreshTint();
    this.envWatchId = watchColorMode(getContext(this) as common.UIAbilityContext, () => {
      this.refreshTint();
    });
    this.updateDateInfo();
    this.loadData();
    this.playListEnter();
  }

  /** 列表入场动画：先透明并下移 12vp，再淡入归位 */
  private playListEnter(): void {
    this.listAlpha = 0;
    this.listShift = 12;
    this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut, delay: 60 }, () => {
      this.listAlpha = 1;
      this.listShift = 0;
    });
  }

  onPageShow(): void {
    this.syncRecords();
  }

  aboutToDisappear(): void {
    stopWatchColorMode(getContext(this) as common.UIAbilityContext, this.envWatchId);
    this.envWatchId = -1;
    if (this.undoTimer >= 0) {
      clearTimeout(this.undoTimer);
      this.undoTimer = -1;
    }
  }

  @Builder
  emptyState() {
    Column({ space: 10 }) {
      Text(this.isFuture ? $r('app.string.future_day_empty') : this.emptyCopy)
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
        .lineHeight($r('app.float.line_body_small'))
        .textAlign(TextAlign.Center)
      if (!this.isFuture) {
        Text('在下面写点什么就行')
          .fontSize($r('app.float.font_meta_small'))
          .fontColor($r('app.color.text_placeholder'))
      }
    }
    .width('100%')
    .height($r('app.float.empty_min_height'))
    .justifyContent(FlexAlign.Center)
    .padding({ left: 40, right: 40 })
  }

  @Builder
  previewOverlay() {
    Column() {
      Row() {
        Blank()
        Stack() {
          Text('×')
            .fontSize(24)
            .fontColor($r('app.color.white'))
        }
        .width($r('app.float.icon_touch'))
        .height($r('app.float.icon_touch'))
        .onClick(() => {
          this.closePreview();
        })
        .accessibilityText('关闭图片')
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: $r('app.float.space_header_safe') })

      Swiper() {
        ForEach(this.previewImages, (name: string) => {
          Image(this.imageUri(name))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .syncLoad(false)
            .geometryTransition(`img-${name}`)
            .onClick(() => {
              this.closePreview();
            })
        }, (name: string) => name)
      }
      .index(this.previewIndex)
      .loop(false)
      .indicator(false)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .zIndex(20)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 顶部光感：与主页同一层径向光，让单日页不再是一块平色
      Column()
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .radialGradient({
          center: ['50%', '26%'],
          radius: '200%',
          colors: [
            [this.tint.glow, 0.0],
            [this.tint.glowEdge, 1.0]
          ]
        })
        .opacity(0.10)
        .hitTestBehavior(HitTestMode.None)

      Column() {
        Row() {
          Stack() {
            Text('‹')
              .fontSize(28)
              .fontColor($r('app.color.text_primary'))
          }
          .width($r('app.float.icon_touch'))
          .height($r('app.float.icon_touch'))
          .borderRadius($r('app.float.icon_touch'))
          .accessibilityText('返回')
          .onClick(() => {
            this.onBack();
          })

          Blank()

          Column({ space: 2 }) {
            Text(this.dateTitle)
              .fontSize($r('app.float.font_date_large'))
              .fontWeight(FontWeight.Bold)
              // 日期数字用暖金，和主页大日期呼应，也给这一页留一个彩色锚点
              .fontColor(this.tint.accent)
            Text(this.dateSubtitle)
              .fontSize($r('app.float.font_meta'))
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: $r('app.float.space_header_safe') })

        Column() {
        if (this.isEmpty) {
          this.emptyState()
          Blank()
        } else {
          List({ space: 12, scroller: this.listScroller }) {
            LazyForEach(this.dataSource, (item: RecordItem) => {
              ListItem() {
                RecordCard({
                  record: item,
                  onDelete: (id: string) => {
                    this.confirmDelete(id);
                  },
                  onEdit: (record: RecordItem) => {
                    this.startEdit(record);
                  },
                  onQuote: (record: RecordItem) => {
                    this.startQuote(record);
                  },
                  onPreview: (images: string[], index: number) => {
                    this.openPreview(images, index);
                  }
                })
                .opacity(item.id === this.removingId
                  ? this.removeAlpha
                  : (item.id === this.newRecordId ? this.landedAlpha : 1))
                .translate({ y: item.id === this.newRecordId ? this.landedOffset : 0 })
                .scale({ x: 1, y: item.id === this.removingId ? this.removeScaleY : 1 })
                .animation({ duration: motionDuration(180), curve: Curve.EaseIn })
              }
            }, (item: RecordItem) => item.id)
            if (this.hasDraftCard()) {
              ListItem() {
                this.draftCard()
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: this.sidePadding(), right: this.sidePadding(), top: 12 })
          .opacity(this.listAlpha)
          .translate({ y: this.listShift })
          .cachedCount(4)
          .scrollBar(BarState.Off)
          .contentEndOffset(this.islandHeight + 88 + this.keyboardPad)
        }
        }
        .width('100%')
        .height('100%')
        .opacity(this.stateAlpha)
      }
      .width('100%')
      .height('100%')

      if (!this.isFuture) {
        Column() {
          FloatingIsland({
            prefillToken: this.prefillToken,
            prefillContent: this.prefillContent,
            prefillMoods: this.prefillMoods,
            prefillImages: this.prefillImages,
            prefillParentId: this.prefillParentId,
            prefillEditingId: this.prefillEditingId,
            prefillQuote: this.prefillQuote,
            defaultMood: this.defaultMood,
            placeholderText: this.isEmpty ? '' : this.emptyCopy,
            onSave: (payload: DraftPayload) => {
              this.handleSave(payload);
            },
            onCancelEdit: () => {
              this.handleCancelEdit();
            },
            onDraftChanged: (payload: DraftPayload) => {
              this.handleDraftChanged(payload);
            },
            onExpandedChanged: (expanded: boolean) => {
              this.islandExpanded = expanded;
              this.keyboardPad = expanded ? 80 : 0;
              if (expanded) {
                // 键盘弹起会把可视区压矮，主动滚到底，最后一张卡不会被岛压住
                setTimeout(() => {
                  this.listScroller.scrollEdge(Edge.Bottom);
                }, 260);
              }
            }
          })
        }
        .width('100%')
        .padding({ left: this.sidePadding(), right: this.sidePadding(), bottom: 28 })
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.islandHeight = Number(newArea.height);
        })
      }

      if (this.showUndo) {
        Row() {
          Text('删掉了。想找回的话，现在还来得及。')
            .fontSize($r('app.float.font_meta_small'))
            .fontColor($r('app.color.white'))
            .layoutWeight(1)
          Text('撤销')
            .fontSize($r('app.float.font_meta'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.white'))
            .onClick(() => {
              this.undoDelete();
            })
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 12,
          bottom: 12
        })
        .backgroundColor($r('app.color.toast_bg'))
        .borderRadius($r('app.float.radius_image'))
        .margin({ left: 20, right: 20, bottom: this.islandHeight + 16 })
        .zIndex(15)
      }

      if (this.previewVisible) {
        this.previewOverlay()
      }
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

  private async loadData(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await appStore.init(context);
    applyTheme(context, appStore.settings);
    this.updateDateInfo();
    await this.restoreDraft();
    this.syncRecords();
  }

  /** 当天草稿 key，与 dateKey 一致：同一天只保留一份未发送内容 */
  private dayKey(): string {
    return dateKeyOf(this.year, this.month, this.day);
  }

  private async restoreDraft(): Promise<void> {
    if (this.isFuture) {
      return;
    }
    const payload = await appStore.loadDraftForDate(this.dayKey());
    if (payload === null) {
      return;
    }
    let editingId = payload.editingId !== undefined ? payload.editingId : '';
    if (editingId !== '' && appStore.getRecordById(editingId) === null) {
      // 被编辑的记录已不存在时，按新记录恢复内容
      editingId = '';
    }
    this.prefillContent = payload.content !== undefined ? payload.content : '';
    this.prefillMoods = Array.isArray(payload.moods) ? this.cloneMoods(payload.moods) : [];
    this.prefillImages = Array.isArray(payload.images) ? this.cloneStrings(payload.images) : [];
    this.prefillParentId = payload.parentId !== undefined ? payload.parentId : '';
    this.prefillEditingId = editingId;
    this.prefillQuote = payload.quote !== undefined ? payload.quote : null;
    this.prefillToken++;
    this.getUIContext().getPromptAction().showToast({ message: $r('app.string.draft_restored') });
  }

  private handleDraftChanged(payload: DraftPayload): void {
    if (this.isFuture) {
      return;
    }
    appStore.saveDraftForDate(this.dayKey(), payload);
    // 实时同步到列表尾部的草稿卡
    this.draftContent = payload.content;
    this.draftMoods = payload.moods;
    this.draftImages = payload.images;
  }

  private hasDraftCard(): boolean {
    if (!this.islandExpanded) {
      return false;
    }
    return this.draftContent !== '' || this.draftMoods.length > 0 || this.draftImages.length > 0;
  }

  /** 保存时：草稿卡往下沉 + 弹一下，表示“存进去了” */
  private playDraftSink(): void {
    // 慢一些：先下沉并轻微放大（“弹一下”），停住后收拢
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
      this.draftSink = 26;
      this.draftBounce = 1.02;
    });
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
        this.draftSink = 44;
        this.draftBounce = 0.96;
      });
    }, 300);
    setTimeout(() => {
      this.draftContent = '';
      this.draftMoods = [];
      this.draftImages = [];
      this.draftSink = 0;
      this.draftBounce = 1;
    }, 700);
  }

  @Builder
  draftCard() {
    Column({ space: 8 }) {
      Row() {
        Text('正在写')
          .fontSize($r('app.float.font_meta_small'))
          .fontColor($r('app.color.accent_glow'))
        Blank()
      }
      .width('100%')

      if (this.draftContent !== '') {
        Text(this.draftContent)
          .width('100%')
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_primary'))
          .lineHeight($r('app.float.line_body'))
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.draftMoods.length > 0) {
        Row({ space: 6 }) {
          ForEach(this.draftMoods, (mood: Mood) => {
            Circle({ width: 8, height: 8 })
              .fill(getMoodColor(mood))
          }, (mood: Mood) => `${mood}`)
          Blank()
        }
        .width('100%')
      }

      if (this.draftImages.length > 0) {
        Row({ space: 8 }) {
          ForEach(this.draftImages.slice(0, 3), (name: string) => {
            Image(this.imageUri(name))
              .width(64)
              .height(64)
              .borderRadius($r('app.float.radius_image'))
              .objectFit(ImageFit.Cover)
          }, (name: string) => name)
          Blank()
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.space_card_pad'))
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius($r('app.float.radius_card'))
    // 虚线感：用一圈更亮的描边区分“还没保存”
    .border({ width: 1, color: $r('app.color.accent_glow') })
    .opacity(0.9)
    .scale({ x: this.draftBounce, y: this.draftBounce })
    .translate({ y: this.draftSink })
  }

  private handleCancelEdit(): void {
    appStore.clearDraftForDate(this.dayKey());
    this.syncRecords();
  }

  /** 内容区左右留白：宽屏按 (宽 - 760)/2 居中 */
  private sidePadding(): number {
    if (this.winWidth <= 820) {
      return 20;
    }
    return Math.max(20, Math.floor((this.winWidth - 760) / 2));
  }

  private updateDateInfo(): void {
    const date = new Date(this.year, this.month - 1, this.day);
    const weekday = getWeekdayName(date.getDay());
    const lunar = getLunarDate(this.year, this.month, this.day);
    const lunarMonth = getLunarMonthName(lunar.month);
    const today = new Date();
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
    this.isFuture = date.getTime() > todayStart;
    this.dateTitle = `${this.day}`;
    const parts: string[] = [`${this.year}年${this.month}月`, `周${weekday}`];
    if (lunarMonth !== '') {
      parts.push(lunarMonth);
    }
    this.dateSubtitle = parts.join(' · ');
  }

  @Monitor('isEmpty')
  onEmptyChanged(): void {
    this.stateAlpha = 0;
    this.getUIContext().animateTo({ duration: motionDuration(220), curve: Curve.EaseOut }, () => {
      this.stateAlpha = 1;
    });
  }

  private syncRecords(): void {
    const records = appStore.getRecordsForDate(this.year, this.month, this.day);
    this.dataSource.updateItems(records);
    this.recordCount = records.length;
    this.isEmpty = records.length === 0;
    const moods = appStore.getMoodsForDate(this.year, this.month, this.day);
    this.emptyCopy = records.length === 0 ? getEmptyCopy(moods) : getAfterSaveCopy(moods);
    this.defaultMood = appStore.settings.defaultMoodMode === DEFAULT_MOOD_LAST
      ? (appStore.settings.lastMood as Mood)
      : Mood.NONE;
    this.listVersion++;
  }

  private imageUri(name: string): string {
    const context = getContext(this) as common.UIAbilityContext;
    return resolveImageUri(context, name);
  }

  private handleSave(payload: DraftPayload): void {
    this.saveAsync(payload);
  }

  /**
   * 保存落笔：新卡片先透明、位于输入区方向（上方），再落到位。
   * 用 scale/translate 手写而不是 geometryTransition，是因为列表是 LazyForEach，
   * 动态节点上的 geometryTransition 行为不稳定。
   */
  private playLanding(recordId: string): void {
    this.newRecordId = recordId;
    this.landedAlpha = 0;
    this.landedOffset = -26;
    this.getUIContext().animateTo({ duration: 460, curve: curves.springMotion(0.5, 0.9) }, () => {
      this.landedAlpha = 1;
      this.landedOffset = 0;
    });
    setTimeout(() => {
      if (this.newRecordId === recordId) {
        this.newRecordId = '';
      }
    }, 700);
  }

  private async saveAsync(payload: DraftPayload): Promise<void> {
    let createdId = '';
    // 跨午夜：页面是「今天」打开的，但现在已经过了 00:00 → 这条记到新的一天，别落到昨天
    const crossedMidnight = this.openedAsToday && this.dayKey() !== todayKey();
    if (payload.editingId !== '') {
      await appStore.updateRecord(payload);
    } else {
      let targetYear = this.year;
      let targetMonth = this.month;
      let targetDay = this.day;
      if (crossedMidnight) {
        const now = new Date();
        targetYear = now.getFullYear();
        targetMonth = now.getMonth() + 1;
        targetDay = now.getDate();
      }
      // 保存返回新记录，落笔动画要按它的 id 定位「刚落下的那张卡」
      const created = await appStore.addRecord(payload, targetYear, targetMonth, targetDay);
      createdId = created.id;
    }
    await appStore.clearDraftForDate(this.dayKey());
    if (crossedMidnight) {
      // 页面还停在昨天：退回日历，让主页滚到新的一天（onPageShow 会按当前日期重算）
      this.onDataChanged();
      this.getUIContext().getPromptAction().showToast({ message: '已经跨天，这条记到今天了。' });
      setTimeout(() => {
        this.onBack();
      }, 260);
      return;
    }
    this.syncRecords();
    if (createdId !== '') {
      this.playDraftSink();
      this.playLanding(createdId);
    }
    // 主页仍在被盖住时刷新它，退回时直接是最终状态
    this.onDataChanged();
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom);
    }, 120);
    this.getUIContext().getPromptAction().showToast({ message: '记下了。' });
  }

  private startEdit(record: RecordItem): void {
    this.prefillContent = record.content;
    this.prefillMoods = this.cloneMoods(record.moods);
    this.prefillImages = this.cloneStrings(record.images);
    this.prefillParentId = record.parentId !== undefined ? record.parentId : '';
    this.prefillEditingId = record.id;
    this.prefillQuote = record.quote !== undefined ? record.quote : null;
    this.prefillToken++;
  }

  private startQuote(record: RecordItem): void {
    this.prefillContent = '';
    this.prefillMoods = [];
    this.prefillImages = [];
    this.prefillParentId = '';
    this.prefillEditingId = '';
    this.prefillQuote = appStore.buildQuote(record);
    this.prefillToken++;
  }

  private openNewDraft(): void {
    this.prefillContent = '';
    this.prefillMoods = [];
    this.prefillImages = [];
    this.prefillParentId = '';
    this.prefillEditingId = '';
    this.prefillQuote = null;
    this.prefillToken++;
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

  /** 收拢：高度压到 0 + 淡出，180ms 后执行真正的删除 */
  private playRemove(recordId: string, after: () => void): void {
    this.removingId = recordId;
    this.removeScaleY = 1;
    this.removeAlpha = 1;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.removeScaleY = 0.01;
      this.removeAlpha = 0;
    });
    setTimeout(() => {
      this.removingId = '';
      this.removeScaleY = 1;
      this.removeAlpha = 1;
      after();
    }, 190);
  }

  private confirmDelete(id: string): void {
    const annotations = appStore.countAnnotations(id);
    let message = '这条要删掉吗？删了就找不回来了。';
    if (annotations > 0) {
      message = `${message}这条下面还有 ${annotations} 条批注，会一起删掉。`;
    }
    AlertDialog.show({
      title: '删除记录',
      message: message,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger_low_sat'),
        action: () => {
          const removed: RecordItem[] = [];
          for (let i = 0; i < appStore.records.length; i++) {
            const item = appStore.records[i];
            if (item.id === id || item.parentId === id) {
              removed.push(item);
            }
          }
          // 先播收拢动画，再落库删除，避免列表“瞬间跳一下”
          this.playRemove(id, () => {
            appStore.deleteRecord(id).then(() => {
              this.lastDeleted = removed;
              this.showUndo = true;
              if (this.undoTimer >= 0) {
                clearTimeout(this.undoTimer);
              }
              this.undoTimer = setTimeout(() => {
                this.showUndo = false;
              }, 6000);
              this.syncRecords();
              this.onDataChanged();
            });
          });
        }
      }
    });
  }

  private openPreview(images: string[], index: number): void {
    this.previewImages = images;
    this.previewIndex = index;
    // 用 animateTo 驱动 geometryTransition：缩略图原地长大成全屏
    this.getUIContext().animateTo({ duration: motionDuration(260), curve: Curve.EaseOut }, () => {
      this.previewVisible = true;
    });
  }

  private closePreview(): void {
    this.getUIContext().animateTo({ duration: motionDuration(220), curve: Curve.EaseIn }, () => {
      this.previewVisible = false;
    });
  }

  private undoDelete(): void {
    if (this.lastDeleted.length === 0) {
      return;
    }
    const restoring = this.lastDeleted;
    this.lastDeleted = [];
    this.showUndo = false;
    appStore.importData(restoring, []).then(() => {
      this.syncRecords();
      this.onDataChanged();
      this.getUIContext().getPromptAction().showToast({ message: '找回来了。' });
    });
  }
}
