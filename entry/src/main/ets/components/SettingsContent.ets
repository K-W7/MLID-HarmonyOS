import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import {
  AppSettings,
  DEFAULT_MOOD_LAST,
  DEFAULT_MOOD_NONE,
  THEME_DARK,
  THEME_FOLLOW,
  THEME_LIGHT
} from '../model/AppSettings';
import { appStore } from '../store/AppStore';
import { applyTheme } from '../utils/ThemeUtil';
import { ENCRYPTED_SUFFIX, exportAll, importBackup, pickBackup, takeImportError } from '../utils/ImportExport';
import { PickedBackup } from '../utils/ImportExport';
import { BackupPasswordPanel } from './BackupPasswordPanel';
import { currentTint, stopWatchColorMode, watchColorMode } from '../utils/TintProvider';
import { MoodTint, tintForTime } from '../utils/MoodTint';

interface ThemeOption {
  value: number;
  label: string;
}

const THEME_OPTIONS: ThemeOption[] = [
  { value: THEME_FOLLOW, label: '跟随系统' },
  { value: THEME_LIGHT, label: '浅色' },
  { value: THEME_DARK, label: '深色' }
];

const APP_VERSION: string = '1.3.0';

@ComponentV2
struct SettingRow {
  @Param title: string = '';
  @Param value: string = '';
  @Param showArrow: boolean = false;
  @Param danger: boolean = false;
  // 行之间的细分隔线；一组里的最后一行传 false
  @Param divider: boolean = true;
  @Event onTap: () => void = () => {
  };

  build() {
    Row() {
      Text(this.title)
        .fontSize($r('app.float.font_body'))
        .fontColor(this.danger ? $r('app.color.danger_low_sat') : $r('app.color.text_primary'))
      Blank()
      if (this.value !== '') {
        Text(this.value)
          .fontSize($r('app.float.font_meta'))
          .fontColor($r('app.color.text_secondary'))
          .margin({ right: 6 })
      }
      if (this.showArrow) {
        Text('›')
          .fontSize(20)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .height(48)
    .border({
      width: { bottom: this.divider ? 0.5 : 0 },
      color: $r('app.color.shadow_card')
    })
    // 以前这里只在 showArrow=true 时才调 onTap，导致「清空/重置」这种无箭头的行点击被吞掉
    .onClick(() => {
      this.onTap();
    })
  }
}

/**
 * 设置页内容，由页面壳（router 版 SettingsPage）或 Navigation 的 NavDestination 承载。
 * 只负责界面与自身状态：返回走 onBack，打开隐私政策走 onOpenPrivacy，由宿主决定怎么走。
 * 例外是「重置应用」：重置后必须回到启动页，属于页面级跳转，仍在组件内用 router 完成。
 */
@ComponentV2
export struct SettingsContent {
  // 回调用 @Event（V2 中 @Param 不接受 function 类型）
  @Event onBack: () => void = () => {
  };
  // 打开隐私政策：宿主负责 push NavDestination（router 版壳里是 pushUrl）
  @Event onOpenPrivacy: () => void = () => {
  };

  @Local themeMode: number = THEME_FOLLOW;
  @Local largeFont: boolean = false;
  @Local nightlyReminder: boolean = false;
  @Local reminderTime: string = '21:30';
  @Local defaultMoodMode: number = DEFAULT_MOOD_NONE;
  @Local lookbackOrder: string[] = ['yesterday', 'random', 'pastYears'];
  @Local recordCount: number = 0;
  @Local busy: boolean = false;
  // 进入设置页时内容淡入，避免生硬地整块出现
  @Local pageAlpha: number = 0;
  // 主题变化监听 + 色温缓存
  private envWatchId: number = -1;
  @Local tint: MoodTint = tintForTime(new Date().getHours(), true);
  // 运行时语言（跟随系统 / 简体中文 / English）
  // 加密备份密码面板：导出 / 导入各一个
  @Local exportPanelVisible: boolean = false;
  @Local importPanelVisible: boolean = false;
  // 已经选好的备份文件：弹密码框期间保留，避免让用户重复选文件
  private pendingBackup: PickedBackup | null = null;
  private reminderId: number = 0;
  private lastMood: number = 0;

  private refreshTint(): void {
    const next = currentTint(this.getUIContext().getHostContext() as common.UIAbilityContext);
    // 主题切换留 1.2s 过渡：直接赋值会硬切，观感很生硬
    this.getUIContext().animateTo({ duration: 1200, curve: Curve.EaseInOut }, () => {
      this.tint = next;
    });
  }

  aboutToAppear(): void {
    this.refreshTint();
    this.envWatchId = watchColorMode(this.getUIContext().getHostContext() as common.UIAbilityContext, () => {
      this.refreshTint();
    });
    this.loadData();
  }

  // 页面级生命周期；被 NavDestination 承载时不会触发，宿主可用 NavDestination 的 onShown 做等价刷新
  onPageShow(): void {
    this.syncFromStore();
  }

  @Builder
  sectionTitle(title: string, accent: ResourceColor = $r('app.color.section_gold')) {
    Row({ space: 8 }) {
      Column()
        .width(3)
        .height(12)
        .borderRadius(2)
        .backgroundColor(accent)
      Text(title)
        .fontSize($r('app.float.font_meta'))
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: $r('app.float.space_section_gap'), bottom: 8, left: 4 })
  }

  aboutToDisappear(): void {
    stopWatchColorMode(this.getUIContext().getHostContext() as common.UIAbilityContext, this.envWatchId);
    this.envWatchId = -1;
  }

  build() {
    Stack() {
      // 顶部光感：与主页、单日页同一层径向光
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
        Scroll() {
        Column() {
          Row() {
            Stack() {
              Text('‹')
                .fontSize(28)
                .fontColor($r('app.color.text_primary'))
            }
            .width($r('app.float.icon_touch'))
            .height($r('app.float.icon_touch'))
            .accessibilityText('返回')
            .onClick(() => {
              this.onBack();
            })

            Text('设置')
              .fontSize($r('app.float.font_title'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            Blank()
          }
          .width('100%')
          .padding({ top: $r('app.float.space_header_safe') })

          this.sectionTitle('外观', $r('app.color.section_gold'))

          Column() {
            Row() {
              Text('深色模式')
                .fontSize($r('app.float.font_body'))
                .fontColor($r('app.color.text_primary'))
              Blank()
            }
            .width('100%')
            .height(48)

            Row({ space: 8 }) {
              ForEach(THEME_OPTIONS, (option: ThemeOption) => {
                Text(option.label)
                  .fontSize($r('app.float.font_meta'))
                  .fontColor(this.themeMode === option.value
                    ? $r('app.color.bg_page')
                    : $r('app.color.text_primary'))
                  .height(40)
                  .padding({ left: 14, right: 14 })
                  // 选中态用暖金，不用品牌青，和树洞色调保持一致
                  .backgroundColor(this.themeMode === option.value
                    ? $r('app.color.accent_glow')
                    : $r('app.color.button_secondary_bg'))
                  .borderRadius($r('app.float.radius_chip'))
                  .onClick(() => {
                    this.selectTheme(option.value);
                  })
              }, (option: ThemeOption) => `${option.value}`)
            }
            .width('100%')
            .margin({ bottom: 12 })

            // 字号跟随系统，不提供入口
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius($r('app.float.radius_card'))
          .border({ width: 1, color: $r('app.color.shadow_card') })
          .shadow({ radius: 6, color: $r('app.color.shadow_card'), offsetY: 2 })

          // 记录分组已整体移除：每晚提醒与提醒时间都删掉了。
          // 理由：提醒是唯一需要通知权限的功能，与本应用“安静、不申请权限”的定位冲突，
          // 且系统提醒配额异常时完全不可用；回访改由应用内的空态文案承担。
          // 「新记录默认情绪」「回望区排序」此前也已移除。
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius($r('app.float.radius_card'))
          .border({ width: 1, color: $r('app.color.shadow_card') })
          .shadow({ radius: 6, color: $r('app.color.shadow_card'), offsetY: 2 })

          this.sectionTitle('数据', $r('app.color.section_clay'))

          Column() {
            SettingRow({
              title: '导出全部记录',
              value: `${this.recordCount} 条`,
              showArrow: true,
              onTap: () => {
                this.doExport();
              }
            })

            SettingRow({
              title: '导入记录',
              showArrow: true,
              onTap: () => {
                this.doImport();
              }
            })

            SettingRow({
              title: '清空所有数据',
              danger: true,
              showArrow: false,
              onTap: () => {
                this.confirmClear();
              }
            })

            SettingRow({
              title: '重置应用',
              divider: false,
              danger: true,
              showArrow: false,
              onTap: () => {
                this.confirmReset();
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius($r('app.float.radius_card'))
          .border({ width: 1, color: $r('app.color.shadow_card') })
          .shadow({ radius: 6, color: $r('app.color.shadow_card'), offsetY: 2 })

          this.sectionTitle('关于', $r('app.color.text_secondary'))

          Column() {
            SettingRow({
              title: '版本',
              value: APP_VERSION
            })

            SettingRow({
              title: '隐私政策',
              showArrow: true,
              onTap: () => {
                this.onOpenPrivacy();
              }
            })

            SettingRow({
              title: '意见反馈',
              divider: false,
              showArrow: true,
              onTap: () => {
                this.showFeedback();
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius($r('app.float.radius_card'))
          .border({ width: 1, color: $r('app.color.shadow_card') })
          .shadow({ radius: 6, color: $r('app.color.shadow_card'), offsetY: 2 })

          Text('时叙不申请网络权限，数据永远留在本机。')
            .width('100%')
            .fontSize($r('app.float.font_meta_small'))
            .fontColor($r('app.color.text_placeholder'))
            .textAlign(TextAlign.Center)
            .padding({ bottom: 40 })
            .margin({ top: 24, bottom: 20 })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .width('100%')
      .layoutWeight(1)
      // 不要右侧滚动条，设置页保持干净
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    // 加密导出：输入密码
    BackupPasswordPanel({
      visible: this.exportPanelVisible,
      title: '加密导出',
      hint: '密码至少 8 位，忘记就无法恢复。',
      onCancel: () => {
        this.exportPanelVisible = false;
      },
      onConfirm: (pwd: string) => {
        this.exportPanelVisible = false;
        this.doExportEncrypted(pwd);
      }
    })

    // 加密备份导入：输入密码
    BackupPasswordPanel({
      visible: this.importPanelVisible,
      title: '输入备份密码',
      hint: '这是加密备份，需要密码才能导入。',
      onCancel: () => {
        this.importPanelVisible = false;
      },
      onConfirm: (pwd: string) => {
        this.importPanelVisible = false;
        this.doImportWithPassword(pwd);
      }
    })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    // 内容淡入（pageAlpha 初值 0，loadData 里动画到 1）
    .opacity(this.pageAlpha)
    // 与主页同一层渐变，避免其他页面是“平的”一块色
    .linearGradient({
      angle: 180,
      // 顶部浅一档：和主页的顶部光感呼应，避免子页像一块平色
      colors: [[this.tint.top, 0.0], [this.tint.bottom, 1.0]]
    })
    }
    .width('100%')
    .height('100%')
  }

  private async loadData(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await appStore.init(context);
    this.syncFromStore();
    // 内容淡入，避免整块设置项生硬出现
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.pageAlpha = 1;
    });
  }
  private syncFromStore(): void {
    const settings = appStore.settings;
    this.themeMode = settings.themeMode;
    this.largeFont = settings.largeFont;
    this.nightlyReminder = settings.nightlyReminder;
    this.reminderTime = settings.reminderTime;
    this.defaultMoodMode = settings.defaultMoodMode;
    this.lookbackOrder = settings.lookbackOrder;
    this.reminderId = settings.reminderId;
    this.lastMood = settings.lastMood;
    this.recordCount = appStore.records.length;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    applyTheme(context, settings);
  }

  private async persist(): Promise<void> {
    const current = appStore.settings;
    const next: AppSettings = {
      themeMode: this.themeMode,
      largeFont: this.largeFont,
      nightlyReminder: this.nightlyReminder,
      reminderTime: this.reminderTime,
      defaultMoodMode: this.defaultMoodMode,
      lastMood: this.lastMood,
      reminderId: this.reminderId,
      privacyAcceptedVersion: current.privacyAcceptedVersion,
      privacyAcceptedAt: current.privacyAcceptedAt,
      lastBackupAt: current.lastBackupAt,
      lookbackOrder: this.lookbackOrder
    };
    await appStore.updateSettings(next);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    applyTheme(context, next);
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private selectTheme(mode: number): void {
    this.themeMode = mode;
    this.persist();
  }

  private readonly ORDER_VARIANTS: string[][] = [
    ['yesterday', 'random', 'pastYears'],
    ['yesterday', 'pastYears', 'random'],
    ['random', 'yesterday', 'pastYears'],
    ['random', 'pastYears', 'yesterday'],
    ['pastYears', 'yesterday', 'random'],
    ['pastYears', 'random', 'yesterday']
  ];

  private cycleLookbackOrder(): void {
    const current = this.lookbackOrder.join(',');
    for (let i = 0; i < this.ORDER_VARIANTS.length; i++) {
      if (this.ORDER_VARIANTS[i].join(',') === current) {
        this.lookbackOrder = this.ORDER_VARIANTS[(i + 1) % this.ORDER_VARIANTS.length];
        this.persist();
        return;
      }
    }
    this.lookbackOrder = this.ORDER_VARIANTS[0];
    this.persist();
  }

  private doExport(): void {
    // 规格 FR-BAK-001：由用户选择普通 ZIP 还是加密备份
    this.getUIContext().showAlertDialog({
      title: '导出备份',
      message: '普通 ZIP 谁拿到都能看；加密备份需要密码，忘记无法恢复。',
      primaryButton: {
        value: '普通 ZIP',
        action: () => {
          this.doExportPlain();
        }
      },
      secondaryButton: {
        value: '加密备份',
        action: () => {
          this.exportPanelVisible = true;
        }
      }
    });
  }

  private async doExportPlain(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const ok = await exportAll(context, appStore.records);
    this.busy = false;
    this.toast(ok ? '导出好了。' : '这次没导出成，稍后再试试。');
  }

  private async doExportEncrypted(password: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const ok = await exportAll(context, appStore.records, password);
    this.busy = false;
    this.toast(ok ? '加密备份导出好了。' : '这次没导出成，稍后再试试。');
  }

  private async doImport(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      // 文件只选一次：加密备份先记住这个文件，弹密码框后直接用同一个文件导入
      const picked = await pickBackup(context);
      if (picked === null) {
        this.busy = false;
        return;
      }
      if (picked.fileName.toLowerCase().endsWith(ENCRYPTED_SUFFIX)) {
        this.pendingBackup = picked;
        this.busy = false;
        this.importPanelVisible = true;
        return;
      }
      // 选完文件后必须释放 busy：performImport 自己会加锁，
      // 否则它第一行的 busy 判断会把自己挡在门外，导入被静默跳过
      this.busy = false;
      await this.performImport(context, picked, '');
    } catch (e) {
      this.busy = false;
      this.toast('这次没导入成，稍后再试试。');
    }
  }

  private async doImportWithPassword(password: string): Promise<void> {
    const picked = this.pendingBackup;
    this.pendingBackup = null;
    if (picked === null) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.performImport(context, picked, password);
  }

  private async performImport(context: Context, picked: PickedBackup, password: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const outcome = await importBackup(context, picked, appStore.records, password);
      if (outcome === null) {
        const reason = takeImportError();
        this.busy = false;
        if (reason === 'NEED_PASSWORD') {
          // 还缺密码：保留同一个文件，弹面板，不再让用户重选
          this.pendingBackup = picked;
          this.importPanelVisible = true;
        } else if (reason === 'BAD_PASSWORD') {
          this.toast('密码不对，备份没有导入。');
        } else if (reason === 'BROKEN_BACKUP') {
          this.toast('这个备份文件读不了。');
        }
        return;
      }
      await appStore.importData(outcome.records, outcome.unarchived);
      this.recordCount = appStore.records.length;
      const result = outcome.result;
      let message = `带回来 ${result.added} 条记录，都放好了。`;
      if (result.skipped > 0) {
        message = `${message}跳过 ${result.skipped} 条重复的。`;
      }
      if (result.unarchived > 0) {
        message = `${message}有 ${result.unarchived} 条没认出日期，先放在待归档。`;
      }
      if (result.orphans > 0) {
        message = `${message}有 ${result.orphans} 条批注因原记录已删除而未导入。`;
      }
      this.getUIContext().showAlertDialog({
        title: '导入结果',
        message: message,
        primaryButton: {
          value: '好',
          action: () => {
            // 导入后直接回主页，让新记录立刻出现在日历上
            this.onBack();
          }
        }
      });
    } catch (e) {
      this.toast('这次没导入成，稍后再试试。');
    }
    this.busy = false;
  }

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: '清空所有数据',
      message: '清空后找不回来了。确定吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.danger_low_sat'),
        action: () => {
          appStore.clearAll().then(() => {
            this.recordCount = 0;
            this.toast('清空了。');
          });
        }
      }
    });
  }

  private confirmReset(): void {
    this.getUIContext().showAlertDialog({
      title: '重置应用',
      message: '会删除全部记录、图片、草稿、提醒和设置，应用回到第一次打开的样子。已经导出到其他位置的备份不受影响。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '继续',
        fontColor: $r('app.color.danger_low_sat'),
        action: () => {
          this.doReset();
        }
      }
    });
  }

  private doReset(): void {
    this.getUIContext().showAlertDialog({
      title: '确认重置',
      message: '这一步之后就找不回来了。确定要重置应用吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '重置应用',
        fontColor: $r('app.color.danger_low_sat'),
        action: () => {
          this.performReset();
        }
      }
    });
  }

  // 重置后必须离开设置页回到启动页：页面级跳转，保留 router 调用（Navigation 下可换 clear/pop 到根）
  private async performReset(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await appStore.resetAll();
    this.recordCount = 0;
    router.replaceUrl({ url: 'pages/SplashPage' });
  }

  private showFeedback(): void {
    this.getUIContext().showAlertDialog({
      title: '意见反馈',
      message: '可以在应用市场给时叙留言。不想说也没关系。',
      primaryButton: {
        value: '好',
        action: () => {
        }
      }
    });
  }
}
