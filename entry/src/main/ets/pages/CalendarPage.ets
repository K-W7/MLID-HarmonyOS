import { router } from '@kit.ArkUI';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { CONTENT_MAX_WIDTH } from '../utils/Breakpoint';
import {
  CalendarDay,
  formatMonthTitle,
  getLunarDate,
  getWeekdayName,
  generateCalendarGrid,
  getCurrentMonthLunarMonth,
  getWeekdayNames,
  getWeekdayHeaders
} from '../model/CalendarUtils';
import { getLunarDayName, getLunarMonthName } from '../model/FestivalData';
import { RecordItem } from '../model/RecordItem';
import { AppSettings } from '../model/AppSettings';
import { Mood } from '../model/Mood';
import { BreathingConfig, getBreathingConfig, getMoodColor } from '../model/MoodMeta';
import { appStore, dateKeyOf } from '../store/AppStore';
import { applyTheme } from '../utils/ThemeUtil';
import { thinMaterial, ultraThinMaterial } from '../utils/MaterialUtil';
import { CalendarCell } from '../components/CalendarCell';
import { CardStack } from '../components/CardStack';
import { SettingsContent } from '../components/SettingsContent';
import { PrivacyContent } from '../components/PrivacyContent';
import { isReduceMotion } from '../utils/MotionUtil';
import { MoodTint, tintFor, tintForTime } from '../utils/MoodTint';
import { currentTint, stopWatchColorMode, watchColorMode } from '../utils/TintProvider';
import { JournalContent } from '../components/JournalContent';

interface MonthPage {
  year: number;
  month: number;
  weeks: CalendarDay[][];
}

interface DayParam {
  year: number;
  month: number;
  day: number;
}

interface YearMonth {
  year: number;
  month: number;
}

const GRID_ROWS: number = 6;
const GRID_HEIGHT: number = 336;

/** ISO 周号：官方日历左侧的「44周」就是这个口径 */
function weekOfYear(date: Date): number {
  const probe = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  // 移到本周周四，再用「第一个周四所在周是第 1 周」计算
  probe.setDate(probe.getDate() + 3 - ((probe.getDay() + 6) % 7));
  const firstThursday = new Date(probe.getFullYear(), 0, 4);
  firstThursday.setDate(firstThursday.getDate() + 3 - ((firstThursday.getDay() + 6) % 7));
  return 1 + Math.round((probe.getTime() - firstThursday.getTime()) / 604800000);
}
function moveMonth(year: number, month: number, delta: number): YearMonth {
  const date = new Date(year, month - 1 + delta, 1);
  return { year: date.getFullYear(), month: date.getMonth() + 1 };
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function isSameDay(timestamp: number, year: number, month: number, day: number): boolean {
  const date = new Date(timestamp);
  return date.getFullYear() === year && date.getMonth() + 1 === month && date.getDate() === day;
}

@Entry
@ComponentV2
struct CalendarPage {
  @Local year: number = new Date().getFullYear();
  @Local month: number = new Date().getMonth() + 1;
  @Local activePage: number = 1;
  // 大日期显示的那一天：切月显示该月 1 号，点某天跟着变（对齐官方日历）
  @Local selectedDay: number = new Date().getDate();
  @Local monthPages: MonthPage[] = [];
  @Local todayBreathing: BreathingConfig = { period: 4.0, high: 0.16, low: 0.12 };
  @Local todayRecords: RecordItem[] = [];
  @Local yesterdayRecords: RecordItem[] = [];
  @Local pastYearRecords: RecordItem[] = [];
  @Local randomRecord: RecordItem | null = null;
  // 随机一条的堆叠数据：最多 5 张，划完循环
  @Local randomStackItems: RecordItem[] = [];
  // 只有有数据的区块才渲染（用户要求：没记录就不显示这一块）
  @Local visibleSections: string[] = [];
  @Local unarchivedList: RecordItem[] = [];
  @Local showUnarchived: boolean = false;
  @Local dataVersion: number = 0;
  // 沉浸光感：滚动偏移驱动顶部光晕的视差与衰减
  @Local scrollOffset: number = 0;
  // 大日期切换时的淡入
  @Local bigDateAlpha: number = 1;
  // A 层：当天情绪决定色温（底色 + 强调 + 光）
  @Local tint: MoodTint = tintFor(Mood.NONE, true);
  // 回望区入场：数据变化后先淡入上移，避免生硬重排
  @Local sectionAlpha: number = 1;
  @Local sectionShift: number = 0;
  private swiperController: SwiperController = new SwiperController();
  // 转场最小测试：用官方 Navigation 栈替代 router
  private rebuildingPages: boolean = false;
  // 窗口宽度：大屏上内容限宽居中，不把卡片拉成整屏
  @Local winWidth: number = 360;
  // 主题变化监听 + 色温缓存（回调里刷新，实现秒切）
  private envWatchId: number = -1;
  private pathStack: NavPathStack = new NavPathStack();

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
    this.monthPages = this.buildPagesAround(this.year, this.month, 1);
    this.activePage = 1;
    this.loadData();
  }

  onPageShow(): void {
    // 不再在这里全量 loadData：从其它应用切回会触发 onPageShow，
    // 全量重载会让回望区在恢复过程中被整体重建，看起来是“下半部分跳出来”。
    // 应用内数据变化由 JournalContent 的 onDataChanged 回调推送；进程重启由 aboutToAppear 负责。
  }

  @Builder
  symbolButton(symbol: Resource, a11y: string, action: () => void) {
    Stack() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')])
    }
    .width($r('app.float.icon_touch'))
    .height($r('app.float.icon_touch'))
    .borderRadius($r('app.float.icon_touch'))
    // 官方日历那种半透明圆钮：自绘组件必须显式挂材质（ENABLE 只覆盖系统组件）
    .systemMaterial(thinMaterial())
    .accessibilityText(a11y)
    .onClick(action)
  }

  @Builder
  pageHeader() {
    Column({ space: 2 }) {
      Row() {
        // 官方日历风格：月份大标题 + 右侧圆形按键
        Text(`${this.month}月`)
          .fontSize($r('app.float.font_logo'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Blank()

        this.symbolButton($r('sys.symbol.slider_horizontal_2'), '设置', () => {
          this.pathStack.pushPathByName('settings', null);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 大日期 + 农历行（今天）
      Text(`${this.selectedDay}`)
        .width('100%')
        .textAlign(TextAlign.Center)
        .fontSize(72)
        .fontWeight(FontWeight.Bold)
        // 大日期用当天情绪色，和底色呼应
        .fontColor(this.tint.accent)
        // 切换日期时淡入 + 轻微放大，避免数字硬切
        .opacity(this.bigDateAlpha)
        .scale({ x: 0.96 + 0.04 * this.bigDateAlpha, y: 0.96 + 0.04 * this.bigDateAlpha })
        .margin({ top: 4 })

      Text(this.todayLunarLine())
        .width('100%')
        .textAlign(TextAlign.Center)
        .fontSize($r('app.float.font_meta'))
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: 20,
      right: 12,
      top: $r('app.float.space_header_safe'),
      bottom: 6
    })
  }

  /** 大日期下方一行：星期 + 这天写了几条，避免和格子里的农历重复 */
  private todayLunarLine(): string {
    const weekday = `星期${getWeekdayName(new Date(this.year, this.month - 1, this.selectedDay).getDay())}`;
    const count = this.selectedDayCount();
    if (count === 0) {
      return `${weekday} · 还没写`;
    }
    return `${weekday} · ${count} 条记录`;
  }

  /** 当前选中那天有几条记录（不是今天也算） */
  private selectedDayCount(): number {
    const key = dateKeyOf(this.year, this.month, this.selectedDay);
    const all = appStore.records;
    let count = 0;
    for (let i = 0; i < all.length; i++) {
      const date = new Date(all[i].timestamp);
      if (dateKeyOf(date.getFullYear(), date.getMonth() + 1, date.getDate()) === key) {
        count++;
      }
    }
    return count;
  }

  @Builder
  unarchivedBanner() {
    Column() {
      Row() {
        Text(`有 ${this.unarchivedList.length} 条记录待归档`)
          .fontSize($r('app.float.font_meta_small'))
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text('去处理')
          .fontSize($r('app.float.font_meta_small'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.showUnarchived = true;
          })
      }
      .width('100%')
      .padding({
        left: 12,
        right: 12,
        top: 8,
        bottom: 8
      })
      .backgroundColor($r('app.color.quote_bg'))
      .borderRadius($r('app.float.radius_image'))
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10 })
  }

  @Builder
  weekHeader() {
    Row() {
      ForEach(getWeekdayHeaders(), (name: string, index: number) => {
        Text(name)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontSize($r('app.float.font_meta_small'))
          .fontColor(index === 0 || index === 6 ?
            $r('app.color.text_secondary') : $r('app.color.text_placeholder'))
      }, (name: string, index: number) => `${index}_${name}`)
    }
    .width('100%')
    .height(28)
    .padding({ left: 12, right: 12 })
    .margin({ top: 16, bottom: 2 })
  }

  @Builder
  monthGrid(page: MonthPage) {
    Column() {
      ForEach(page.weeks, (week: CalendarDay[]) => {
        Row() {
          ForEach(week, (day: CalendarDay) => {
            CalendarCell({
              day: day,
              breathing: this.todayBreathing,
              onTapDay: (picked: CalendarDay) => {
                this.openDay(picked);
              }
            })
              .layoutWeight(1)
              // 几何转场：与详情页同 id，系统把这一格形变成详情内容
              .geometryTransition(`day-${day.year}-${day.month}-${day.day}`)
          }, (day: CalendarDay) => `${day.key}_${page.year}_${page.month}_${day.hasRecord}`)
        }
        .width('100%')
      }, (week: CalendarDay[]) => `${page.year}-${page.month}-${week[0].key}`)
    }
    .width('100%')
    .height(GRID_HEIGHT)
    .padding({ left: 12, right: 12 })
  }

  @Builder
  calendarSwiper() {
    Swiper(this.swiperController) {
      ForEach(this.monthPages, (page: MonthPage) => {
        this.monthGrid(page)
      }, (page: MonthPage) => `${page.year}-${page.month}-${this.dataVersion}`)
    }
    .index(this.activePage)
    .loop(true)
    .indicator(false)
    .duration(260)
    .width('100%')
    .height(GRID_HEIGHT)
    .onChange((index: number) => {
      this.handlePageChange(index);
    })
    .onAnimationStart((index: number, targetIndex: number) => {
      // 手指一推就把大日期压淡，落定后再由 syncSelectedDay 淡入，
      // 避免“网格已经翻页、上面还停在旧月份”的错觉
      if (targetIndex !== index) {
        this.bigDateAlpha = 0.4;
      }
    })
    .onAnimationEnd((index: number) => {
      this.handleAnimationEnd(index);
    })
  }

  @Builder
  sectionTitle(title: string, accent: ResourceColor = $r('app.color.section_gold')) {
    Row({ space: 8 }) {
      // 彩色短竖线：每块一个色标，打破单色
      Column()
        .width(3)
        .height(14)
        .borderRadius(2)
        .backgroundColor(accent)
      Text(title)
        .fontSize($r('app.float.font_body'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  recordCard(item: RecordItem) {
    Column({ space: 8 }) {
      Row() {
        Text(this.recordMetaText(item.timestamp))
          .fontSize($r('app.float.font_meta_small'))
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Row({ space: 4 }) {
          ForEach(item.moods, (mood: Mood) => {
            Circle({ width: 6, height: 6 })
              .fill(getMoodColor(mood))
          }, (mood: Mood) => `${item.id}_${mood}`)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.recordPreview(item))
        .width('100%')
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_primary'))
        .lineHeight($r('app.float.line_body_small'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (item.images.length > 0 && item.content.trim() !== '') {
        Text(`含 ${item.images.length} 张图片`)
          .fontSize($r('app.float.font_meta_small'))
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .padding($r('app.float.space_card_pad'))
    .borderRadius($r('app.float.radius_card'))
    // 无壁纸时材质卡不显形（已实测三次），回望区用实色卡；材质只给悬浮岛/圆钮/弹窗
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.shadow_card') })
    .shadow({ radius: 6, color: $r('app.color.shadow_card'), offsetY: 2 })
    .onClick(() => {
      this.openRecord(item);
    })
  }

  @Builder
  todaySection() {
    Column({ space: 10 }) {
      this.sectionTitle('今日记录')
      if (this.todayRecords.length === 0) {
        Text('今天还没有留下痕迹')
          .width('100%')
          .fontSize($r('app.float.font_meta'))
          .fontColor($r('app.color.text_placeholder'))
          .padding({ top: 2, bottom: 2 })
      } else {
        ForEach(this.todayRecords, (item: RecordItem) => {
          this.recordCard(item)
        }, (item: RecordItem) => `today_${item.id}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  yesterdaySection() {
    Column({ space: 10 }) {
      this.sectionTitle('昨日回望', $r('app.color.section_gold'))
      // 卡片堆叠：左右划走过一张，只是翻看，不删数据
      CardStack({
        items: this.yesterdayRecords,
        onOpen: (item: RecordItem) => {
          this.openRecord(item);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  pastSection() {
    Column({ space: 10 }) {
      this.sectionTitle('往年今日', $r('app.color.section_clay'))
      // 与另外两块同一套卡片堆叠
      CardStack({
        items: this.pastYearRecords,
        emptyText: '暂无回忆。',
        onOpen: (item: RecordItem) => {
          this.openRecord(item);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

    @Builder
  unarchivedSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay_scrim'))
        .onClick(() => {
          this.showUnarchived = false;
        })

      Column() {
        Row() {
          Text('待归档记录')
            .fontSize($r('app.float.font_title'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text('关闭')
            .fontSize($r('app.float.font_meta'))
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.showUnarchived = false;
            })
        }
        .width('100%')
        .margin({ bottom: 12 })

        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.unarchivedList, (item: RecordItem) => {
              Column({ space: 8 }) {
                Text(this.unarchivedTitle(item))
                  .width('100%')
                  .fontSize($r('app.float.font_body_small'))
                  .fontColor($r('app.color.text_primary'))
                  .lineHeight($r('app.float.line_body_small'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Row() {
                  Text('还没有日期')
                    .fontSize($r('app.float.font_meta_small'))
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text('补日期')
                    .fontSize($r('app.float.font_meta'))
                    .fontColor($r('app.color.text_primary'))
                    .padding({
                      left: 12,
                      right: 12,
                      top: 6,
                      bottom: 6
                    })
                    .backgroundColor($r('app.color.button_secondary_bg'))
                    .borderRadius($r('app.float.radius_button'))
                    .onClick(() => {
                      this.pickArchiveDate(item);
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding($r('app.float.space_card_pad'))
              .backgroundColor($r('app.color.quote_bg'))
              .borderRadius($r('app.float.radius_card'))
            }, (item: RecordItem) => item.id)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Text('全部归到今天')
          .width('100%')
          .height(44)
          .textAlign(TextAlign.Center)
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.button_secondary_bg'))
          .borderRadius($r('app.float.radius_button'))
          .margin({ top: 12 })
          .onClick(() => {
            this.archiveAllToday();
          })
      }
      .width('100%')
      .height('62%')
      .padding(20)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
    .zIndex(10)
  }

  /** 内容区左右留白：宽屏时按 (窗口宽 - 760) / 2 居中，手机保持 16 */
  private sidePadding(): number {
    const w = this.winWidth;
    if (w <= 820) {
      return 16;
    }
    return Math.max(16, Math.floor((w - CONTENT_MAX_WIDTH) / 2));
  }

  /** 宽屏时格子可以高一点，读起来不挤 */
  private wideCellBoost(): number {
    return this.sidePadding() > 16 ? 8 : 0;
  }

  /** 状态栏图标的颜色：深色主题用白，浅色主题用近黑 */
  private statusIconColor(): string {
    try {
      const mode = appStore.settings.themeMode;
      if (mode === 1) {
        return '#1F1B14';
      }
      if (mode === 2) {
        return '#FFFFFF';
      }
      const dark = (getContext(this) as common.UIAbilityContext).config.colorMode
        === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      return dark ? '#FFFFFF' : '#1F1B14';
    } catch (e) {
      return '#FFFFFF';
    }
  }

  aboutToDisappear(): void {
    stopWatchColorMode(getContext(this) as common.UIAbilityContext, this.envWatchId);
    this.envWatchId = -1;
  }

  build() {
    Navigation(this.pathStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 沉浸光感：顶部一层极淡的品牌色径向光，和渐变一起构成光感（不参与交互）
        Column()
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .radialGradient({
            // 光心避开状态栏：压在 12% 会把白色状态栏图标“洗”掉，挪到 26%
            center: ['50%', '26%'],
            // 半径按宽度算，95% 会在页面中部留一道弧线硬边；放大到 200% 让光自然淡出
            radius: '200%',
            colors: [
              [this.tint.glow, 0.0],
              [this.tint.glowEdge, 1.0]
            ]
          })
          // 往下滚时光晕上移、变淡，制造“光在下面”的层次
          .translate({ y: this.scrollOffset * 0.28 })
          .opacity(0.10 + Math.max(0, 0.06 - this.scrollOffset / 1200))
          .hitTestBehavior(HitTestMode.None)

        // 官方 onMove 只对 List/Grid 生效，所以整页改成一个 List：
        // 前两个 ListItem 固定（头部、日历），后三个回望块可拖拽排序
        List() {
          ListItem() {
            this.pageHeader()
          }

          ListItem() {
            Column() {
              if (this.unarchivedList.length > 0) {
                this.unarchivedBanner()
              }
              this.weekHeader()
              this.calendarSwiper()
            }
            .width('100%')
          }

          // 官方拖拽排序：Repeat + DynamicNode.onMove（List 内每个 item 生成一个 ListItem）
          Repeat(this.visibleSections)
            .each((repeatItem: RepeatItem<string>) => {
              ListItem() {
                Column() {
                  if (repeatItem.item === 'yesterday') {
                    this.yesterdaySection()
                  } else if (repeatItem.item === 'pastYears') {
                    this.pastSection()
                  } else if (repeatItem.item === 'random') {
                    // 与昨日回望同一套堆叠：去掉「换一条」，直接划卡
                    Column({ space: 10 }) {
                      this.sectionTitle('随机一条', $r('app.color.section_sage'))
                      CardStack({
                        items: this.randomStackItems,
                        emptyText: '还没有可回看的记录。',
                        onOpen: (picked: RecordItem) => {
                          this.openRecord(picked);
                        }
                      })
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                  }
                }
                .width('100%')
                .padding({
          left: this.sidePadding(),
          right: this.sidePadding(),
          top: 16,
          bottom: 16
        })
                .opacity(this.sectionAlpha)
                .translate({ y: this.sectionShift })
              }
            })
            .key((section: string) => {
              if (section === 'random') {
                return `random-${this.randomRecord !== null ? this.randomRecord.id : 'none'}`;
              }
              if (section === 'pastYears') {
                return `past-${this.pastYearRecords.length}`;
              }
              return section;
            })
            .onMove((from: number, to: number) => {
              this.onSectionMove(from, to);
            })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .contentEndOffset(40)
        .onScroll((offset: number) => {
          this.scrollOffset = offset;
        })

        if (this.showUnarchived) {
          this.unarchivedSheet()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const w = parseFloat(`${newArea.width}`);
        if (w > 0 && w !== this.winWidth) {
          this.winWidth = w;
        }
      })
      .linearGradient({
        angle: 180,
        // 底色跟随当天情绪色温（A 层）
      colors: [[this.tint.top, 0.0], [this.tint.bottom, 1.0]]
      })
    }
    // 状态栏内容色跟随主题：浅色底上用深色图标，否则白字看不见
    .systemBarStyle({ statusBarContentColor: this.statusIconColor() })
    .mode(NavigationMode.Stack)
    .navDestination(this.destinationMap)
    .titleMode(NavigationTitleMode.Full)
    // 规格 S-02：Header 属于页面内容；塞进系统标题栏会因高度不足与星期栏重叠
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
    .backgroundColor(this.tint.top)
  }

  /** onMove 的下标包含头部与日历两个固定项，换算成回望区下标 */
  private onSectionMove(from: number, to: number): void {
    // 拖拽下标是可见区块的顺序，映射回 lookbackOrder 里的 key
    if (from < 0 || to < 0 || from >= this.visibleSections.length || to >= this.visibleSections.length) {
      return;
    }
    const fromKey = this.visibleSections[from];
    const toKey = this.visibleSections[to];
    const order: string[] = appStore.settings.lookbackOrder.slice();
    const fromIndex = order.indexOf(fromKey);
    const toIndex = order.indexOf(toKey);
    if (fromIndex < 0 || toIndex < 0) {
      return;
    }
    const temp = order[fromIndex];
    order[fromIndex] = order[toIndex];
    order[toIndex] = temp;
    this.persistLookbackOrder(order);
    this.computeVisibleSections();
  }

  private persistLookbackOrder(order: string[]): void {
    const current = appStore.settings;
    const next: AppSettings = {
      themeMode: current.themeMode,
      largeFont: current.largeFont,
      nightlyReminder: current.nightlyReminder,
      reminderTime: current.reminderTime,
      defaultMoodMode: current.defaultMoodMode,
      lastMood: current.lastMood,
      reminderId: current.reminderId,
      privacyAcceptedVersion: current.privacyAcceptedVersion,
      privacyAcceptedAt: current.privacyAcceptedAt,
      lastBackupAt: current.lastBackupAt,
      lookbackOrder: order
    };
    appStore.updateSettings(next);
  }

  private async loadData(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await appStore.init(context);

    applyTheme(context, appStore.settings);
    this.unarchivedList = appStore.unarchived.slice();
    if (this.unarchivedList.length === 0) {
      this.showUnarchived = false;
    }
    this.todayBreathing = this.computeTodayBreathing();
    this.refreshInfoFlow();
    this.dataVersion++;
    this.rebuildCurrentPages();
  }

  private computeTodayBreathing(): BreathingConfig {
    const now = new Date();
    const moods = appStore.getMoodsForDate(now.getFullYear(), now.getMonth() + 1, now.getDate());
    return getBreathingConfig(moods);
  }

  private makeMonthPage(year: number, month: number): MonthPage {
    const days = generateCalendarGrid(year, month);
    for (let i = 0; i < days.length; i++) {
      const day = days[i];
      day.hasRecord = appStore.hasRecordsOn(day.year, day.month, day.day);
    }
    const weeks: CalendarDay[][] = [];
    for (let w = 0; w < GRID_ROWS; w++) {
      weeks.push(days.slice(w * 7, w * 7 + 7));
    }
    return { year: year, month: month, weeks: weeks };
  }

  private buildPagesAround(year: number, month: number, centerIndex: number): MonthPage[] {
    const prev = moveMonth(year, month, -1);
    const next = moveMonth(year, month, 1);
    const pages: MonthPage[] = [
      { year: year, month: month, weeks: [] },
      { year: year, month: month, weeks: [] },
      { year: year, month: month, weeks: [] }
    ];
    pages[centerIndex] = this.makeMonthPage(year, month);
    pages[(centerIndex + 1) % 3] = this.makeMonthPage(next.year, next.month);
    pages[(centerIndex + 2) % 3] = this.makeMonthPage(prev.year, prev.month);
    return pages;
  }

  private rebuildCurrentPages(): void {
    this.rebuildingPages = true;
    this.monthPages = this.buildPagesAround(this.year, this.month, this.activePage);
    this.rebuildingPages = false;
  }

  private refreshInfoFlow(): void {
    const now = new Date();
    const todayYear = now.getFullYear();
    const todayMonth = now.getMonth() + 1;
    const todayDay = now.getDate();

    this.todayRecords = appStore.getRecordsForDate(todayYear, todayMonth, todayDay);

    const yesterday = new Date(todayYear, todayMonth - 1, todayDay - 1);
    this.yesterdayRecords = appStore.getRecordsForDate(
      yesterday.getFullYear(),
      yesterday.getMonth() + 1,
      yesterday.getDate()
    );

    const past: RecordItem[] = [];
    const all = appStore.records;
    for (let i = 0; i < all.length; i++) {
      const item = all[i];
      const date = new Date(item.timestamp);
      if (date.getFullYear() < todayYear &&
        date.getMonth() + 1 === todayMonth &&
        date.getDate() === todayDay) {
        past.push(item);
      }
    }
    past.sort((a: RecordItem, b: RecordItem) => b.timestamp - a.timestamp);
    this.pastYearRecords = past;

    this.pickRandomRecord();
    this.buildRandomStack();
    this.computeVisibleSections();
    this.applyTodayTint();
    this.playSectionsEnter();
  }

  /** 把当天主情绪换算成色温，并刷新底色/强调/光 */
  private applyTodayTint(): void {
    const now = new Date();
    const moods = appStore.getMoodsForDate(now.getFullYear(), now.getMonth() + 1, now.getDate());
    const primary = moods.length > 0 ? moods[0] : Mood.NONE;
    let dark = true;
    try {
      dark = (getContext(this) as common.UIAbilityContext).config.colorMode
        === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (e) {
      dark = true;
    }
    // 有情绪用情绪色，没有就按时段兜底
    this.tint = moods.length > 0 ? tintFor(primary, dark) : tintForTime(now.getHours(), dark);
  }

  /** 回望区入场：淡入 + 上移 10vp，数据刷新时播放 */
  private playSectionsEnter(): void {
    this.sectionAlpha = 0;
    this.sectionShift = 10;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.sectionAlpha = 1;
      this.sectionShift = 0;
    });
  }

  /** 只有有数据的区块才渲染：没记录就不显示这一块（用户明确要求） */
  private computeVisibleSections(): void {
    const order = appStore.settings.lookbackOrder;
    const visible: string[] = [];
    for (let i = 0; i < order.length; i++) {
      const section = order[i];
      if (section === 'yesterday' && this.yesterdayRecords.length > 0) {
        visible.push(section);
      } else if (section === 'pastYears' && this.pastYearRecords.length > 0) {
        visible.push(section);
      } else if (section === 'random' && this.randomStackItems.length > 0) {
        visible.push(section);
      }
    }
    this.visibleSections = visible;
  }

  /** 随机一条的堆叠数据：从已归档记录里随机取最多 5 条，划完循环 */
  private buildRandomStack(): void {
    const all = appStore.records;
    // 随机一条从“已归档记录”里抽，今天的也算；只排除昨日回望里已经出现的
    const candidates: RecordItem[] = all.slice();
    // 优先排除「昨日回望」已展示过的记录，避免两块内容一模一样
    const shownIds = new Set<string>();
    for (let i = 0; i < this.yesterdayRecords.length; i++) {
      shownIds.add(this.yesterdayRecords[i].id);
    }
    const filtered: RecordItem[] = [];
    for (let i = 0; i < candidates.length; i++) {
      if (!shownIds.has(candidates[i].id)) {
        filtered.push(candidates[i]);
      }
    }
    // 排除后为空（记录本来就只有昨天那几条）才退回全集
    const pool = filtered.length > 0 ? filtered : (candidates.length > 0 ? candidates.slice() : all.slice());
    const picked: RecordItem[] = [];
    while (picked.length < 5 && pool.length > 0) {
      const index = Math.floor(Math.random() * pool.length);
      picked.push(pool[index]);
      pool.splice(index, 1);
    }
    this.randomStackItems = picked;
  }
  private pickRandomRecord(): void {
    const all = appStore.records;
    if (all.length === 0) {
      this.randomRecord = null;
      return;
    }

    const now = new Date();
    const candidates: RecordItem[] = [];
    for (let i = 0; i < all.length; i++) {
      const item = all[i];
      if (!isSameDay(item.timestamp, now.getFullYear(), now.getMonth() + 1, now.getDate())) {
        candidates.push(item);
      }
    }
    const pool = candidates.length > 0 ? candidates : all;
    let index = Math.floor(Math.random() * pool.length);
    let next = pool[index];
    if (this.randomRecord !== null && pool.length > 1 && next.id === this.randomRecord.id) {
      index = (index + 1) % pool.length;
      next = pool[index];
    }
    this.randomRecord = next;
  }

  private pageDelta(from: number, to: number): number {
    if (from === 1) {
      return to === 2 ? 1 : -1;
    }
    if (from === 2) {
      return to === 0 ? 1 : -1;
    }
    return to === 1 ? 1 : -1;
  }

  private handlePageChange(index: number): void {
    if (this.rebuildingPages || index === this.activePage) {
      return;
    }
    const delta = this.pageDelta(this.activePage, index);
    const target = moveMonth(this.year, this.month, delta);
    this.year = target.year;
    this.month = target.month;
    this.activePage = index;
    this.syncSelectedDay();
  }

  private handleAnimationEnd(index: number): void {
    if (this.rebuildingPages) {
      return;
    }
    if (index !== this.activePage) {
      const delta = this.pageDelta(this.activePage, index);
      const target = moveMonth(this.year, this.month, delta);
      this.year = target.year;
      this.month = target.month;
      this.activePage = index;
      this.syncSelectedDay();
    }
    this.rebuildingPages = true;
    this.monthPages = this.buildPagesAround(this.year, this.month, index);
    this.rebuildingPages = false;
  }

  /** 切月时大日期跟着变：当月含今天就显示今天，否则显示该月 1 号（对齐官方日历） */
  private syncSelectedDay(): void {
    const now = new Date();
    const isCurrentMonth = (this.year === now.getFullYear() && this.month === now.getMonth() + 1);
    if (isCurrentMonth) {
      this.selectedDay = now.getDate();
    } else {
      // 切到别的月份时保持“日”一致：12 月就落 12 月 8 日；该月没有这一天就取月末
      const daysInMonth = new Date(this.year, this.month, 0).getDate();
      this.selectedDay = Math.min(now.getDate(), daysInMonth);
    }
    this.playBigDateIn();
  }

  /** 大日期换数字时的入场：先降到低透明度再动画回来，像光重新亮起 */
  private playBigDateIn(): void {
    this.bigDateAlpha = 0.35;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.bigDateAlpha = 1;
    });
  }

  private openDay(day: CalendarDay): void {
    this.selectedDay = day.day;
    this.playBigDateIn();
    const param: DayParam = { year: day.year, month: day.month, day: day.day };
    // 不在 onPop 里刷新：那时页面正在做弹出动画，数据中途替换会跳变。
    // 改为单日页保存/删除时通过 onDataChanged 回调，在主页仍被盖住时更新。
    this.pathStack.pushPathByName('day', param);
  }

  @Builder
  destinationMap(name: string, param: Object) {
    NavDestination() {
      if (name === 'settings') {
        SettingsContent({
          onBack: () => {
            this.pathStack.pop();
          },
          onOpenPrivacy: () => {
            this.pathStack.pushPathByName('privacy', false);
          }
        })
      } else if (name === 'privacy') {
        PrivacyContent({
          consentMode: (param as boolean) === true,
          onBack: () => {
            this.pathStack.pop();
          },
          onAgree: () => {
            this.pathStack.pop();
          }
        })
      } else {
        JournalContent({
          year: (param as DayParam).year,
          month: (param as DayParam).month,
          day: (param as DayParam).day,
          onBack: () => {
            this.pathStack.pop();
          },
          onDataChanged: () => {
            this.loadData();
          }
        })
        // 几何转场另一端：与日历格同 id，系统做形状/位置过渡
        .geometryTransition(`day-${(param as DayParam).year}-${(param as DayParam).month}-${(param as DayParam).day}`)
      }
    }
    // 各页面自带 Header（含安全区），不用系统标题栏
    .hideTitleBar(true)
    // 转场期间 NavDestination 默认底色是系统色（深色下为黑），先铺上本色
    .backgroundColor(this.tint.top)
    .systemBarStyle({ statusBarContentColor: this.statusIconColor() })
    // 子页返回时重算色温：在设置里换了深浅色，回主页立刻生效
    .onDisAppear(() => {
      // 子页里可能新增/导入了记录：色温、随机池、区块都要重算，否则只有重启才更新
      this.pickRandomRecord();
      this.buildRandomStack();
      this.computeVisibleSections();
      this.applyTodayTint();
    })
  }

  private openRecord(item: RecordItem): void {
    const date = new Date(item.timestamp);
    const param: DayParam = {
      year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate()
    };
    this.pathStack.pushPathByName('day', param);
  }

  private recordMetaText(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const time = `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
    if (date.getFullYear() === now.getFullYear() &&
      date.getMonth() === now.getMonth() &&
      date.getDate() === now.getDate()) {
      return time;
    }
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 ${time}`;
  }

  private recordPreview(item: RecordItem): string {
    const text = item.content.trim();
    if (text !== '') {
      return text;
    }
    if (item.images.length > 0) {
      return `图片记录 · ${item.images.length} 张`;
    }
    return '无文字记录';
  }

  private pickArchiveDate(item: RecordItem): void {
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: new Date(),
      selected: new Date(),
      onDateAccept: (value: Date) => {
        appStore.archive(item.id, value.getFullYear(), value.getMonth() + 1, value.getDate())
          .then(() => {
            this.loadData();
          });
      }
    });
  }

  private archiveAllToday(): void {
    appStore.archiveAllToToday().then(() => {
      this.loadData();
    });
  }

  private unarchivedTitle(item: RecordItem): string {
    if (item.content.trim() !== '') {
      return item.content.trim();
    }
    return '这条只有图片';
  }
}
