# 技术设计：深层次修改

## 1. 回望区可排序设计

### 数据结构
```typescript
// Preferences 键
const KEY_LOOKBACK_ORDER = 'lookbackOrder';
// 默认顺序
const DEFAULT_LOOKBACK_ORDER: string[] = ['yesterday', 'random', 'pastYears'];
// 持久化类型
// 使用 JSON.stringify 存字符串数组
```

### 组件设计
- `CalendarPage.ets` 中的 `infoFlow()` 改为按 `this.lookbackOrder` 顺序动态渲染
- 每个模块独立为 Builder，用 `Map<string, () => void>` 注册
- 排序 UI：在设置页增加「回望区排序」选项，使用可拖拽列表（`ListItem` + `onMove`）
- 排序变更后写入 Preferences，CalendarPage 的 `onPageShow` 重新读取

## 2. 灰点标记

### CalendarCell.ets 修改
```typescript
// 在日期数字下方增加
if (this.day.hasRecord) {
  // 2×2vp 灰点
  Circle({ width: 2, height: 2 })
    .fill($r('app.color.text_placeholder'))
    .margin({ top: 4 })
}
```
- 不额外增加状态，直接使用 `day.hasRecord`
- 批注时显示小一号的点（可选）

## 3. 隐私同意流程

### 新增组件 `PrivacyDialog.ets`
- 模态弹窗，展示隐私政策摘要
- 包含「同意」和「不同意」按钮
- 不同意时调用 `terminateSelf()` 退出应用
- 同意后写 `privacyAcceptedVersion` 到 Preferences

### 触发时机
- `SplashPage.ets` 的 `aboutToAppear` 中检查
- 若未同意，跳转到 `PrivacyDialog` 或直接弹窗
- 已有 SplashPage，可在动画结束后弹窗

## 4. 设置页增强

### 深色模式
- 三个选项：跟随系统 / 浅色 / 深色
- 使用 `@ohos.app.ability.common` 的 `getConfiguration()` 监听系统主题
- 调用 `window.setWindowDarkMode()` 或通过 `ThemeUtil.applyTheme()`
- 当前已有 `applyTheme`，需扩展支持 dark palette

### 每晚提醒
- 使用 `@ohos.reminderAgentManager` 发布提醒
- 提醒点击 `want` 携带日期参数跳转到当日详情页
- 设置页使用 `TimePicker` 选择时间

### 导出/导入
- 使用 `@ohos.file.picker` 选择目录/文件
- 加密使用 AES-GCM + PBKDF2（已有 CryptoMigration / Pbkdf2）
- 导出格式：ZIP 包含 JSON 记录 + 图片
- 导入流程：解压 → 校验 → 合并 → 报告

### 清空/重置
- 两步确认：AlertDialog → 确认 → 执行
- 清空：只清记录，保留设置
- 重置：清全部数据并重引导航

## 5. 批注支持

### 数据模型扩展
```typescript
// RecordItem 增加
annotations?: Annotation[];

interface Annotation {
  id: string;
  content: string;
  moods: Mood[];
  images: string[];
  createdAt: number;
  parentId: string; // 关联的主记录 ID
}
```

### UI 表现
- RecordCard 中增加批注区域，默认折叠
- 批注卡片使用不同的背景色（quote_bg）
- 「展开」后显示全部批注

## 6. UI/UX 美化

### 减弱动画
- Preferences 键 `reducedMotion`
- 在 `CalendarCell` 等组件中判断是否跳过呼吸动画

### 大字模式
- Preferences 键 `largeText`
- 在应用初始化时设置全局字体缩放比例
- 使用 `UIContext.setFontScale()` 或自定义资源切换

## 7. 文件结构变更

```
新增：
  spec/
  entry/src/main/ets/components/PrivacyDialog.ets
  entry/src/main/ets/services/BackupManager.ets
  entry/src/main/ets/services/ReminderManager.ets

修改：
  entry/src/main/ets/pages/CalendarPage.ets（回望区排序）
  entry/src/main/ets/components/CalendarCell.ets（灰点）
  entry/src/main/ets/pages/JournalPage.ets（批注）
  entry/src/main/ets/components/RecordCard.ets（批注折叠）
  entry/src/main/ets/pages/SettingsPage.ets（大幅重写）
  entry/src/main/ets/pages/SplashPage.ets（隐私弹窗）
  entry/src/main/ets/store/PreferencesStore.ets（新键值）
  entry/src/main/ets/store/AppStore.ets（排序/批注/隐私状态）
  entry/src/main/ets/utils/ThemeUtil.ets（深色主题）
```
