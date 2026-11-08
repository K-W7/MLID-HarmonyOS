# 项目上下文与架构分析

## 项目概况

- **项目名称**：时叙 MLID（Shixu）
- **技术栈**：HarmonyOS 7（API 26）· Stage 模型 · ArkUI / ArkTS · @ComponentV2 装饰器
- **项目路径**：`E:/O/MLID`
- **目标**：单人开发的原生鸿蒙情绪日记应用

## 当前架构

### 源码目录
```
entry/src/main/ets/
├── pages/
│   ├── CalendarPage.ets     # 日历主页（Swiper 滑动切月 + 回望区）
│   ├── JournalPage.ets       # 单日详情页（悬浮岛 + 记录列表）
│   ├── SettingsPage.ets      # 设置页
│   └── SplashPage.ets        # 启动页
├── components/
│   ├── CalendarCell.ets      # 日历单格（今日光晕 + 记录标记）
│   ├── EchoStack.ets         # 回响栈？
│   ├── FloatingIsland.ets    # 悬浮岛（输入框 + 情绪选择）
│   ├── MonthGrid.ets         # 月份网格？
│   ├── MoodChip.ets          # 情绪胶囊（纯色圆点）
│   └── RecordCard.ets        # 可复用记录卡片
├── model/
│   ├── CalendarUtils.ets     # 日历工具（农历、格网生成）
│   ├── FestivalData.ets      # 节气数据
│   ├── Mood.ets              # 情绪枚举
│   ├── MoodMeta.ets          # 情绪元数据（颜色、标签）
│   ├── RecordItem.ets        # 记录数据模型
│   └── AppSettings.ets       # 设置模型
├── store/
│   ├── AppStore.ets          # 全局状态（Preferences 持久化）
│   └── PreferencesStore.ets  # Preferences 读写
├── utils/
│   ├── DateUtils.ets
│   ├── JsonExport.ets
│   ├── CryptoMigration.ets
│   ├── Pbkdf2.ets
│   └── ImageStore.ets
└── data/
    └── AppDatabase.ets       # 数据库初始化
```

### 当前技术差异（vs SRS/SDD）

| 规格要求 | 当前状态 | 差距 |
|---|---|---|
| 关系数据库 RelationalStore | 使用 Preferences | 中等——需迁移 |
| 记录含批注（annotation） | 未实现 | 大 |
| 回望区可拖拽排序 | 固定顺序 | 中 |
| 回望区「昨日记录」 | 显示「今日记录」 | 小 |
| 备份/导出加密 | 有基础实现？ | 需验证 |
| 隐私同意流程 | 未实现 | 中 |
| 深色/跟随系统主题 | 有 applyTheme | 需完善 |
| 日历格「有记录灰点」 | 未实现 | 小 |
| 单日详情「引文引用」 | 有 QuoteRef | 需验证 |
| 减弱动画 / 大字模式 | 未实现 | 小 |
| 多语言（中/英） | 中文仅 | 小 |
| 「回望区」排序持久化 | 未实现 | 中 |

## 关键决策记录

1. **@ComponentV2**：整个项目已统一使用 V2 装饰器体系
2. **零网络权限**：不申请 INTERNET
3. **签到证书不可变更**：debug.keystore 必须保留
4. **Swiper 滑动切月**：已实现 3 页循环 + loop(true) 方案
5. **视觉 Token 唯一来源**：使用 color/float string 资源文件

## 当前构建状态

- 最近构建：成功
- 已知问题：无编译错误
