# 已知问题清单

记录原则：一条一行，写清「现象 → 当前判断 → 验证方式 → 状态」。验完改成 ✅，不删。

## 待验证（用户 2026-11-08 报告）

| # | 现象 | 当前判断 | 验证方式 | 状态 |
|---|---|---|---|---|
| B-01 | 主页「换一条」点了没反应 | **根因：`randomSection` 这个 `@Builder` 在 `ForEach` 里不会因 `@Local randomRecord` 变化而重建**，点击链路本身是通的（hilog 已证实） | 把随机记录 id 编进 ForEach key，key 变则条目重建 | ✅ 已修（实测卡片从「接接接」变为「今天风很大」） |
| B-02 | 设置页「清空所有数据」点了没反应 | **根因：`SettingRow.onClick` 里写了 `if (this.showArrow) this.onTap()`，无箭头的危险行点击被吞掉**；`AlertDialog.show` 已弃用只是次要问题 | 去掉 showArrow 门控；弹窗改用 `getUIContext().showAlertDialog()` | ✅ 已修（用户手指实测：确认框出现，确认后记录清零并提示） |
| B-03 | 设置页「重置应用」点了没反应 | 同 B-02 | 同 B-02 | ✅ 已修（实测应用重置并重启） |

## 验证手段（按可靠度排序）

1. **控件树**：`hdc shell uitest dumpLayout -p /data/local/tmp/layout.json`，拉回来按 text 找控件和精确坐标，不靠猜坐标。
2. **应用日志**：`hdc shell "hilog -x | grep -i com.k.mlid"`；需要时在关键动作里加 `hilog.info` 埋点。
3. **截图对比**：操作前后各截一张，比对像素差异。
4. **人工确认**：用户点一下描述现象，作为交叉验证。

## 已修

| # | 问题 | 修复 |
|---|---|---|
| F-01 | 每次启动都进隐私页 | `PreferencesStore` 用了 API 26 只有 Promise 形态的 `get()`，改为 `getSync()` |
| F-02 | 隐私页标题被前置摄像头遮挡 | 外层加 `space_header_safe` 顶部安全区 |
| F-03 | 启动强制隐私弹窗 | 去掉启动拦截，隐私说明只在设置里可看 |
