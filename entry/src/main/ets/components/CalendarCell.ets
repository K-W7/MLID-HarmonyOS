import { CalendarDay } from '../model/CalendarUtils';
import { BreathingConfig } from '../model/MoodMeta';
import { curves } from '@kit.ArkUI';
import { isReduceMotion } from '../utils/MotionUtil';

@ComponentV2
export struct CalendarCell {
  @Require @Param day: CalendarDay;
  @Param breathing: BreathingConfig = { period: 4.0, high: 0.16, low: 0.12 };
  @Local glowOpacity: number = 0.12;
  // 点击选中反馈：数字下压回弹 + 一圈扩散
  @Local tapScale: number = 1;
  @Local rippleScale: number = 0.6;
  @Local rippleOpacity: number = 0;
  private timerId: number = -1;
  private resumeId: number = -1;
  private active: boolean = false;

  @Event onTapDay: (day: CalendarDay) => void = () => {
  };

  aboutToAppear(): void {
    this.startBreathing();
  }

  aboutToDisappear(): void {
    this.stopTimers();
  }

  @Monitor('breathing')
  onBreathingChanged(): void {
    this.startBreathing();
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        if (this.day.isToday) {
          // 官方日历风格：今天用圆形底，而不是实心色块
          Column()
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor($r('app.color.today_circle'))
            .hitTestBehavior(HitTestMode.None)
        }
        if (this.day.isToday) {
          // 只做柔和径向暖光，不使用任何实心圆角底色
          Column()
            .width($r('app.float.glow_size'))
            .height($r('app.float.glow_size'))
            .radialGradient({
              center: ['50%', '50%'],
              radius: '50%',
              colors: [
                [$r('app.color.glow_center'), 0.0],
                [$r('app.color.glow_edge'), 1.0]
              ]
            })
            .opacity(this.glowOpacity)
            .hitTestBehavior(HitTestMode.None)
        }
        Column({ space: 1 }) {
          Text(`${this.day.day}`)
            .fontSize($r('app.float.font_cell_day'))
            .fontWeight(this.day.isToday ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.dayColor())
          if (this.day.hasRecord) {
            // 有记录的日子用暖金小点，扫一眼就知道哪天写过
            Circle({ width: 3, height: 3 })
              .fill($r('app.color.accent_glow'))
          }
        }
      }
      .width(40)
      .height(40)

      if (this.day.lunarText !== '') {
        // 农历是辅助信息：更淡、更小，和数字拉开层次，不做成“满屏字”
        Text(this.day.lunarText)
          .fontSize($r('app.float.font_lunar_cell'))
          // 节气/节日用赤陶色，和普通农历区分开
          .fontColor(this.day.isFestival ? $r('app.color.section_clay') : $r('app.color.text_placeholder'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .height(12)
          .margin({ top: 2 })
      }
    }
    .height($r('app.float.cell_height'))
    .justifyContent(FlexAlign.Center)
    .scale({ x: this.tapScale, y: this.tapScale })
    .opacity(this.day.isFuture ? 0.5 : (this.day.isCurrentMonth ? 1 : 0.7))
    .accessibilityText(`${this.day.month}月${this.day.day}日${this.day.hasRecord ? '，有记录' : ''}`)
    .onClick(() => {
      if (this.day.isFuture) {
        return;
      }
      this.pauseBreathing();
      this.playTapFeedback();
      this.onTapDay(this.day);
    })
  }

  /** 选中反馈：数字先下压 0.94 再弹回，同时一圈淡淡扩散 */
  private playTapFeedback(): void {
    this.rippleScale = 0.6;
    this.rippleOpacity = 0.5;
    this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut }, () => {
      this.tapScale = 0.94;
    });
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 220, curve: curves.springMotion(0.5, 0.9) }, () => {
        this.tapScale = 1;
      });
    }, 90);
    this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
      this.rippleScale = 1.5;
      this.rippleOpacity = 0;
    });
  }

  private stopTimers(): void {
    this.active = false;
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    if (this.resumeId >= 0) {
      clearTimeout(this.resumeId);
      this.resumeId = -1;
    }
  }

  private startBreathing(): void {
    this.stopTimers();
    if (!this.day.isToday) {
      return;
    }
    const config = this.breathing;
    // 减弱动画：不呼吸，直接给一个稳定的高亮值（规格 5.6：功能不丢，只去掉动）
    if (isReduceMotion()) {
      this.glowOpacity = config.high;
      return;
    }
    this.glowOpacity = config.low;
    this.active = true;
    this.runHalfCycle(config);
  }

  private runHalfCycle(config: BreathingConfig): void {
    if (!this.active) {
      return;
    }
    const half = config.period * 1000 / 2;
    animateTo({ duration: half, curve: Curve.EaseInOut }, () => {
      this.glowOpacity = config.high;
    });
    this.timerId = setTimeout(() => {
      if (!this.active) {
        return;
      }
      animateTo({ duration: half, curve: Curve.EaseInOut }, () => {
        this.glowOpacity = config.low;
      });
      this.timerId = setTimeout(() => {
        this.runHalfCycle(config);
      }, half);
    }, half);
  }

  private pauseBreathing(): void {
    if (!this.day.isToday) {
      return;
    }
    this.stopTimers();
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.glowOpacity = 0.10;
    });
    this.resumeId = setTimeout(() => {
      this.startBreathing();
    }, 5000);
  }

  private dayColor(): ResourceColor {
    if (this.day.isFuture) {
      return $r('app.color.text_secondary');
    }
    if (!this.day.isCurrentMonth) {
      // 非本月别用最暗的占位色，否则在深色渐变上要凑近才看清
      return $r('app.color.text_secondary');
    }
    return $r('app.color.text_primary');
  }
}
