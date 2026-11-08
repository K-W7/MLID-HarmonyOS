import { uiMaterial } from '@kit.ArkUI';

/**
 * 沉浸光感（Immersive Light）统一材质。
 * 官方能力自 API 26.0.0 起提供；应用级"全局适配"开关已在 module.json5
 * 通过 metadata: ohos.arkui.UIMaterial.state = enable 打开，系统组件
 * （Dialog / Sheet / Menu / Toast / Chip / Select / Toggle / Slider 等）
 * 会自动使用材质。
 *
 * 自定义容器按官方规范选择对应强度：
 *   ULTRA_THIN 悬浮标题栏 / THIN 底部悬浮操作栏 / REGULAR 常规卡片
 *   THICK 菜单 / ULTRA_THICK 弹窗
 *
 * 注意：挂载 systemMaterial 后不要再叠加 backgroundColor / shadow / border，
 * 否则会覆盖或削弱材质的通透光感；圆角、padding、尺寸仍可正常使用。
 */

/** 底部悬浮操作栏 / 搜索框（薄材质） */
export function thinMaterial(): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    // 无壁纸只有渐变时，材质本身几乎透明；加一层色调才看得出“玻璃”的层次（深浅色各一套）
    materialColor: $r('app.color.material_tint'),
    applyShadow: true,
    interactive: false
  });
}

/** 悬浮标题栏（极薄材质） */
export function ultraThinMaterial(): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    applyShadow: true,
    interactive: false
  });
}

/** 常规卡片 / 面板（标准材质） */
export function regularMaterial(): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.REGULAR,
    materialColor: $r('app.color.material_tint'),
    applyShadow: true,
    interactive: false
  });
}

/** 弹窗 / 底部弹出面板（厚材质） */
export function thickMaterial(): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THICK,
    applyShadow: true,
    interactive: false
  });
}
