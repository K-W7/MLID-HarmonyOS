# 官方 UI 能力 API 对照表（沉浸光感 / 材质 / 动效）

- 版本：HarmonyOS 26.0.0.105 / API 26（`<DEVECO_SDK_HOME>\default`）
- 依据：SDK 内 `.d.ts` 声明（华为官方文档的可编译形态）+ 官方《组件适配沉浸光感》指南
- 用途：写代码时只查这一份，不再凭记忆；每条都标了声明位置，能回查

---

## 1. 应用级开关（决定系统组件是否默认带材质）

**位置**：`entry/src/main/module.json5` → `module.metadata`

```json5
"metadata": [
  {
    // 值：enable / default / disable（大小写不敏感，官方按 MaterialState 解析）
    "name": "ohos.arkui.UIMaterial.state",
    "value": "enable"
  }
]
```

**读取**：`uiMaterial.getMaterialInfo(): MaterialInfo`（`@ohos.arkui.uiMaterial.d.ts:163`），返回 `{ state, type }`，来源就是上面这段 metadata。

**三档语义**（`MaterialState`，d.ts:68）：

| 值 | 名称 | Dialog/Toast/AlphabetIndexer | Select/Menu/Toggle/Slider/TabBar/bindSheet 等 | 其他组件 |
|---|---|---|---|---|
| 0 | DEFAULT | 默认开启 | 不开启 | 需应用主动设置 |
| 1 | ENABLE | 默认开启 | **默认开启** | 需应用主动设置 |
| 2 | DISABLE | 全部禁止，即使显式设置也不生效 | 同左 | 同左 |

> 关键结论：ENABLE 不是“材质强度开关”，而是“全站系统组件默认换皮”。选它就要接受 Select/Toggle/Slider/TabBar/bindSheet 全部变材质风。

---

## 2. 材质对象（组件级调用的唯一入参）

**命名空间**：`import { uiMaterial } from '@kit.ArkUI';`

```ts
// 类声明：@ohos.arkui.uiMaterial.d.ts:503
class ImmersiveMaterial extends Material {
  constructor(options?: ImmersiveOptions);
}

interface ImmersiveOptions {
  style?: ImmersiveStyle;      // 默认 REGULAR
  materialColor?: ResourceColor; // 默认 Color.Transparent，给材质调色
  colorInvert?: boolean;       // 默认 false，按背景取反色（仅 THIN/ULTRA_THIN 且高/中算力）
  applyShadow?: boolean;       // 默认 true
  interactive?: boolean;       // 默认 false，按压形变反馈
  lightEffect?: LightEffectOptions | null; // 光感反馈，null 关闭
}
```

**样式档位**（`ImmersiveStyle`，d.ts:174）：`ULTRA_THIN=0` / `THIN=1` / `REGULAR=2` / `THICK=3` / `ULTRA_THICK=4`。

**关闭某个组件的材质**：`.systemMaterial(uiMaterial.Material.empty)`（d.ts:481）。前提是组件支持组件级 API，否则关不掉。

> 注意：`ADAPTIVE` 这个枚举在 API 26 **不存在**，旧规格里写错了。

---

## 3. 挂载点清单（官方能力 → 具体 API）

| 场景 | API | 声明位置 | 约束 |
|---|---|---|---|
| 任意组件 | `.systemMaterial(material)` | `component/common.d.ts:22642` | 挂上后不要再叠 backgroundColor / shadow / border，会盖掉材质 |
| Navigation 标题栏 | `.title(builder, { systemMaterial, barStyle })` | `component/navigation.d.ts:2324`（title）/ `1891`（systemMaterial）/ `1771`（barStyle） | 生效范围仅返回键与非自定义 Menu；官方建议 `BarStyle.STACK` 让内容区延伸到栏下；ENABLE 下标题栏默认就开，样式默认 ULTRA_THIN |
| 半模态 | `bindSheet(..., { systemMaterial })` | `common.d.ts:12155`（SheetOptions） | ENABLE 下默认开启 |
| 弹窗 | `AlertDialog.show({ systemMaterial })` | `alert_dialog.d.ts:894`（AlertDialogParam） | 同上 |
| 日期/时间/日历弹窗 | `DatePickerDialogOptions` / `TimePickerDialogOptions` / `CalendarDialogOptions` | `date_picker.d.ts:1075` / `time_picker.d.ts:1006` / `calendar_picker.d.ts:590` | 同上 |
| 菜单（长按/点击） | `bindMenu` / `bindContextMenu` 的 `MenuOptions`/`ContextMenuOptions.systemMaterial` | `common.d.ts:15594`（ContextMenuOptions）、`15637`（MenuOptions extends 它） | ENABLE 下默认开启 |
| 气泡 / 提示 | `PopupOptions` / `CustomPopupOptions` / `TipsOptions.systemMaterial` | `common.d.ts:13824` / `14406` / `13167` | — |
| 底部悬浮页签 | `FloatingTabBarStyle.systemMaterial` | `tabs.d.ts:895` | — |

---

## 4. 设备能力判定与降级（必须做，否则低端机是空的）

| 用途 | API | 声明位置 | 说明 |
|---|---|---|---|
| 设备算力档 | `getGlobalMaterialLevel()` → `EXQUISITE(0)/GENTLE(1)/SMOOTH(2)` | d.ts:280 / enum 237 | 由设备决定，改不了 |
| 是否支持沉浸材质 | `isImmersiveMaterialSupported()` → boolean | d.ts:296 | false 时设 systemMaterial 不生效，必须给实色兜底 |
| 当前应用配置 | `getMaterialInfo()` → `{state,type}` | d.ts:163 | 判断 ENABLE/DISABLE 用 |

**官方效果差异**（d.ts:486 注释）：高/中算力才有 filter 与阴影效果；低算力只影响背景色、边框色、边框宽、阴影——即“看起来像半透明色块”，没有模糊。`style` 参数也只在高/中算力生效。

---

## 5. 动效（官方系统动效 → API）

| 动效 | API | 声明位置 | 用法 |
|---|---|---|---|
| 页面系统转场 | `NavDestination().systemTransition(type)` | `nav_destination.d.ts:1065` | 枚举 `NavigationSystemTransitionType`：DEFAULT/NONE/TITLE/CONTENT/FADE/EXPLODE/SLIDE_RIGHT/SLIDE_BOTTOM（d.ts:111-191） |
| 几何转场（日期格→详情） | `.geometryTransition(id, options?)` | `common.d.ts:21406 / 21421` | 两处组件用同一个 id，系统自己做形变过渡 |
| 属性动画 | `animateTo(param, () => {...})` | `common.d.ts:5919` | 系统动效曲线的入口 |
| 立即完成的属性动画 | `animateToImmediately(param, () => {...})` | `common.d.ts:5931` | 不排队，用于手势跟随 |
| 弹性曲线 | `curves.interpolatingSpring(...)` | `common.d.ts` 内 `interpolatingSpring` | 手感接近系统弹性的写法 |
| 共享元素 | `.sharedTransition(id, options)` | `common.d.ts`（8 处） | 跨页面元素连续性 |

> 结论：“官方动效”不是一个开关，是这五类 API。当前工程里只用了最基础的 `animateTo`，转场、几何转场、共享元素都没用；页面切换还是 `router`（官方已弃用），所以系统转场无从谈起。

---

## 6. 本工程当前调用状态

| 能力 | 官方要求 | 现状 | 结论 |
|---|---|---|---|
| 应用级开关 | metadata `ohos.arkui.UIMaterial.state` | 已是 `enable` | ✅ 正确 |
| 材质对象 | `new uiMaterial.ImmersiveMaterial({style})` | `utils/MaterialUtil.ets` 有 thin/ultraThin/regular/thick 四个工厂 | ✅ 可用 |
| 标题栏材质 | Navigation 标题栏 + `BarStyle.STACK`，或自绘组件挂 systemMaterial | 自绘 `pageHeader()`，曾挂 systemMaterial 但视觉无差异 | ⚠️ 未验成 |
| 弹窗/Toast/半模态 | ENABLE 下默认开启，不必显式挂 | 曾显式挂 13 处，已回退 | ✅ 已纠正 |
| 长按菜单 | `bindContextMenu` + ContextMenuOptions | 代码里没有菜单 | ❌ 未实现 |
| 页面转场 | `NavDestination.systemTransition` | 用 `router`，无 NavDestination | ❌ 未实现 |
| 几何转场 | `geometryTransition` | 未使用 | ❌ 未实现 |
| 降级判定 | `isImmersiveMaterialSupported` / `getGlobalMaterialLevel` | 未调用 | ❌ 未实现 |

---

## 7. 待真机确认（每条都要截图或录屏留证）

1. `AES256|GCM|NoPadding` 之外，材质 transformation 无需验证；但材质**观感**要在三档算力设备对比。
2. 自绘组件挂 `systemMaterial` 与 Navigation 标题栏，哪个观感更像“纸”而不是“系统玻璃”。
3. 低算力设备（SMOOTH）上材质退化后的实际样子。
4. 深色模式下手账底色与材质的关系。
