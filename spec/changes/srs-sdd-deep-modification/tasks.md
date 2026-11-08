# 实现任务清单

## 优先级定义
- **P0**：核心功能，必须完成
- **P1**：重要功能，建议完成
- **P2**：美化增强，条件允许时完成

---

## Task 1：回望区完善（P0）

### 1.1 昨日记录模块
- [ ] 修改 `refreshInfoFlow()`，将「今日记录」改为「昨日记录」
- [ ] 新增 `yesterdayRecords` 计算逻辑：取昨天日期的记录
- [ ] 空状态显示「昨天还没有留下痕迹」
- [ ] 卡片列表同现有样式

### 1.2 回望区可排序
- [ ] Preferences 存储键 `lookbackOrder`：JSON string[]
- [ ] AppStore 中增加 `lookbackOrder` 读写
- [ ] CalendarPage `infoFlow()` 改为按排序动态渲染
- [ ] 设置页增加「回望区排序」界面（可拖拽列表或选择式）
- [ ] `onPageShow` 重新读取排序

---

## Task 2：日历格灰点标记（P0）

### 2.1 CalendarCell 改造
- [ ] 在日期数字下方渲染 `Circle({ width: 2, height: 2 })` 灰点
- [ ] 仅当 `day.hasRecord` 为 true 时显示
- [ ] 灰点颜色 `text_placeholder`（#B8B8B8）
- [ ] 与数字间距 4vp

---

## Task 3：隐私同意流程（P0）

### 3.1 PrivacyDialog 组件
- [ ] 新建 `PrivacyDialog.ets` 模态弹窗
- [ ] 展示隐私政策摘要（硬编码文案，无网络请求）
- [ ] 「同意」→ 写入 Preferences（`privacyAcceptedVersion: 1`）
- [ ] 「不同意」→ `terminateSelf()` 退出

### 3.2 SplashPage 集成
- [ ] 启动页动画结束后检查是否已同意
- [ ] 未同意则弹 PrivacyDialog
- [ ] 已同意直接跳转 CalendarPage

---

## Task 4：设置页重写（P1）

### 4.1 深色模式
- [ ] 三个选项：跟随系统 / 浅色 / 深色
- [ ] ThemeUtil 扩展深色面板资源
- [ ] 实时切换

### 4.2 每晚提醒
- [ ] 使用 `reminderAgentManager` 创建/取消提醒
- [ ] 设置页 TimePicker 选择时间
- [ ] 通知点击 `want` 携带年月日参数

### 4.3 导出/导入
- [ ] BackupManager 服务类
- [ ] 普通导出：ZIP（JSON + 图片）
- [ ] 加密导出：AES-GCM + PBKDF2
- [ ] 导入：解压 → 校验 → 合并 → 报告

### 4.4 清空/重置
- [ ] 清空：两步确认 → 只清记录
- [ ] 重置：两步确认 → 清全部 + 重引导航

---

## Task 5：批注支持（P1）

### 5.1 数据模型
- [ ] RecordItem 增加 `annotations?: Annotation[]`
- [ ] Annotation 接口（id, content, moods, images, createdAt, parentId）

### 5.2 UI 表现
- [ ] RecordCard 增加批注区域，默认折叠
- [ ] 展开/收起状态
- [ ] 批注使用不同背景色

---

## Task 6：UI/UX 美化（P2）

### 6.1 减弱动画
- [ ] Preferences 键 `reducedMotion`
- [ ] CalendarCell 跳过呼吸动画
- [ ] 页面过渡使用无动画

### 6.2 大字模式
- [ ] Preferences 键 `largeText`
- [ ] 通过 UIContext 调整字体缩放

### 6.3 视觉 Token 审计
- [ ] 检查所有 .ets 文件，确保无硬编码颜色/字号/间距
- [ ] 统一使用 $r('app.color.xxx') / $r('app.float.xxx')

---

## 工作量预估

| 任务 | 预估工时 | 风险 |
|---|---|---|
| T1 回望区 | 2h | 低 |
| T2 灰点 | 0.5h | 低 |
| T3 隐私 | 1h | 低 |
| T4 设置 | 6h | 中（导出导入复杂） |
| T5 批注 | 3h | 中 |
| T6 美化 | 2h | 低 |

## 验收标准

1. 编译零错误
2. 回望区正确显示昨日记录、往年今日、随机一条
3. 回望区排序可调且持久化
4. 日历格日期有记录时显示灰点
5. 首次启动弹出隐私协议
6. 设置页功能完整可用
7. 批注可查看
