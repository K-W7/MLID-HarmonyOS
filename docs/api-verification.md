# API 26 开发前核对结果

- 核对日期：2026-11-08
- 依据：`<DEVECO_SDK_HOME>\default`（HarmonyOS 26.0.0.105 / API 26 Release）+ 华为开发者官方文档
- 工程：`<repo>`（bundleName `com.k.mlid`，compileSdk/target 26.0.0）
- 方法：先查 **本地 SDK 的 .d.ts 声明**（官方文档的可编译形态），再用 `hvigorw` 构建与源码现状取证。凡“官方支持”与“本工程已实现”分开记，不合并。

结论口径：
- **通过**：官方声明存在 + 本工程有实现 + 编译通过。
- **未实现**：官方支持，但本工程没有对应代码。
- **待真机**：只能靠设备判定，模拟器不算。

## 汇总

| 结论 | 数量 | 条目 |
|---|---|---|
| 通过 | 9 | E-02 E-04 E-07 E-08 E-09 E-14 E-15 E-18 E-22(可选) |
| 未实现 | 7 | E-10 E-13 E-17 E-20 E-21 E-24 |
| 待真机 / 部分 | 8 | E-01 E-03 E-05 E-06 E-11 E-12 E-16 E-19 E-23 |

> 注：E-22 触觉为 P2 可选，官方支持但本工程未用，不阻塞 M0。

---

## A.1 工程与框架

| ID | 核对项 | 级别 | 结论 | 证据 |
|---|---|---|---|---|
| E-01 | Stage 工程与目标 SDK | P0 | **待签名** | `hvigorw assembleHap --mode module -p product=default` → `BUILD SUCCESSFUL`；但 `signingConfigs: []`，产物未签名（`Will skip sign 'hos_hap'`），不满足“产物可安装” |
| E-02 | ArkTS 编译 | P0 | **通过** | 同上构建；`BuildProfile` modelVersion 26.0.0，SDK 26.0.0.105 |
| E-03 | V2 状态管理 | P0 | **待真机** | 全工程使用 `@ComponentV2` + `@Local`/`@Consumer`，无 V1；真实响应需设备验证 |
| E-04 | V1 禁用检查 | P0 | **通过** | 全量检索 `@Component`/`@State`/`@Prop`/`@Link`/`@Observed`/`@ObjectLink`/`@Provide`/`@Consume`/`@Watch`：**0 命中** |
| E-05 | 路由与参数 | P0 | **未实现** | 现用 `router.pushUrl/replaceUrl/back`（10 处），编译期提示 `pushUrl`/`replaceUrl` **已弃用**；`openDay` 未校验非法参数 |
| E-06 | 窗口与安全区 | P0 | **部分** | `EntryAbility.onWindowStageCreate`：`setWindowLayoutFullScreen(true)` + 背景色随深浅、`setKeyboardAvoidMode(RESIZE)`；页面未见 `expandSafeArea`，安全区靠 `app.float.space_header_safe` 内边距 |

## A.2 安全与系统能力

| ID | 核对项 | 级别 | 结论 | 证据 |
|---|---|---|---|---|
| E-07 | 权限清单 | P0 | **通过** | `module.json5` 仅声明 `ohos.permission.PUBLISH_AGENT_REMINDER`；无 INTERNET/CAMERA/MIC/位置/通讯录/完整相册 |
| E-08 | Photo Picker | P0 | **通过** | `utils/ImageStore.ets` 用 `photoAccessHelper.PhotoViewPicker` + `PhotoSelectOptions`；声明见 `@ohos.file.photoAccessHelper.d.ts:4443` |
| E-09 | 文档 Picker | P0 | **通过** | `utils/ImportExport.ets:141/404` 用 `picker.DocumentViewPicker`；声明见 `@ohos.file.picker.d.ts:628` |
| E-10 | 加密能力 | P0 | **未实现** | 导出仅 `zlib.compressFile` 生成普通 ZIP，全工程 **无** `cryptoFramework`、AES-GCM、PBKDF2 调用。官方入口：`cryptoFramework.PBKDF2Spec`（`algName` 形如 `PBKDF2|SHA256`）、GCM Cipher；另 `relationalStore` 自带 `KDF_SHA256` 仅用于库加密，不能替代备份加密 |
| E-11 | 通知与提醒 | P0 | **待真机** | `utils/ReminderUtil.ets`：`notificationManager.isNotificationEnabled/requestEnableNotification` + `reminderAgentManager.publishReminder/cancelReminder`，用 `previousId` 做幂等；重启恢复、修改取消幂等需真机 |
| E-12 | 主题切换 | P0 | **待真机** | `utils/ThemeUtil.applyTheme` 存在；规格要求“跟随系统”，需真机验浅/深/跟随三态与持久化 |
| E-13 | 减少动画 | P1 | **未实现** | 无读取系统动画/无障碍设置的代码 |
| E-14 | 备份扩展能力 | P0 | **通过** | `module.json5` 未声明 backup 扩展能力，符合“记录/图片不参与系统云备份” |

## A.3 视觉与数据能力

| ID | 核对项 | 级别 | 结论 | 证据 |
|---|---|---|---|---|
| E-15 | 系统符号 | P1 | **通过** | 页面使用 `$r('sys.symbol.slider_horizontal_2')` 等系统符号 |
| E-16 | 材质 | P1 | **通过** | 官方 `@ohos.arkui.uiMaterial.d.ts`（`@since 26.0.0`）；本工程 `module.json5` metadata `ohos.arkui.UIMaterial.state=enable`。**真机证据（2026-11-08，KLE-AL00U / API 26）**：`getGlobalMaterialLevel()=1`（GENTLE 中算力）、`isImmersiveMaterialSupported()=true`；单日页悬浮岛挂 `THIN`，列表滚动时卡片从岛下方穿过（截图 `mat-3`）。注：主页内容不满一屏，标题栏 `ULTRA_THIN` 没有可透的内容，材质应在浮层（悬浮岛/弹窗/半模态）上体现 |
| E-17 | 几何转场 | P1 | **未实现** | 源码无 `geometryTransition` |
| E-18 | 农历 | P0 | **通过** | `model/CalendarUtils.ets:38` `i18n.getCalendar('zh-CN', 'chinese')`；官方另有 `i18n.getChineseCalendar(locale)` 入口 |
| E-19 | 图片处理 | P0 | **部分** | 有 `photoAccessHelper` 选图与沙箱复制（`ImageStore.ets`）；**无** `image.createImageSource` 解码、HEIF、旋转、1080 压缩、EXIF 剥离 |
| E-20 | 关系数据库 | P0 | **未实现** | 全工程无 `relationalStore`/`getRdbStore`；记录走 `Preferences`（`store/PreferencesStore.ets` + `store/AppStore.ets`）。与规格 6.2/6.3 的 `records`/`record_moods`/`record_images` 表设计冲突 |
| E-21 | 字体缩放 | P0 | **未实现** | 无 `fontScale`/配置变更处理 |
| E-22 | 触觉反馈 | P2 | **通过（可选）** | 官方 `vibrator.startVibration` 存在；本工程未调用，属可选增强，不阻塞 |
| E-23 | 多语言资源 | P0 | **部分** | 资源目录 `base`/`dark`/`en_US` 存在；中文在 `base`，中英 key 对齐与回退链未核 |
| E-24 | 运行时语言 | P0 | **未实现** | 无 `onConfigurationUpdate`/语言切换刷新逻辑 |

---

## 附录 A 本身需要修正的条目

1. **E-16** 写的“ADAPTIVE 或等价可用”在 API 26 SDK 中**不存在**该枚举。应改为 `uiMaterial.ImmersiveStyle`（ULTRA_THIN/THIN/REGULAR/THICK/ULTRA_THICK），并用 `isImmersiveMaterialSupported()` + `getGlobalMaterialLevel()` 做降级判定。
2. **E-18** 未写官方入口，应补：`i18n.getCalendar('zh-CN','chinese')` 或 `i18n.getChineseCalendar(locale)`。
3. **E-10** 的通过标准与工程现状差距最大：规格禁止“降级为假加密”，当前导出为明文 ZIP，必须在 M0 前决定是补 AES-256-GCM+PBKDF2 还是把加密备份移出 V1.1。
4. **E-20** 的“关系数据库”条目与工程实现不一致，需在规格里明确“V1.0 用 Preferences，RelationalStore 迁移列入 V1.2”还是“立即迁移”。

## 待办（按阻塞程度）

1. 签名（需华为账号自动签名）→ 打通 E-01，之后所有真机项才可判定。
2. 真机核对：E-03、E-06、E-11、E-12、E-16、E-19(部分)、E-23。
3. 代码补齐（可离线做）：E-13 减少动画、E-17 几何转场、E-21 字体缩放、E-24 运行时语言。
4. 决策类：E-10 加密、E-20 数据库，需先改规格再改代码。

## 决策（2026-11-08）

- **E-10 加密**：补实现。按规格 8.4.2 做 `.mlidbackup`（50 字节明文头 + PBKDF2-HMAC-SHA256 + AES-256-GCM，AAD 为明文头），保留普通 ZIP 导出。
- **E-20 关系数据库**：立即迁 RelationalStore。表与索引照 6.3；`unarchived` 以 `date_key IS NULL` 表达，不再单独存储；旧 Preferences JSON 一次性搬迁后置 `recordsMigrated=1`。
- 接线约定：`RecordDb`（新）负责读写，`AppStore` 的 `persistRecords/persistUnarchived` 合并为一次 `replaceAll` 事务写；`BackupCrypto`（新）负责 `.mlidbackup` 加解密，`ImportExport` 增加可选密码参数。
