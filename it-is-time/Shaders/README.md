# Shader 资源

| Shader | 用途与使用入口 |
|---|---|
| [BodyPartOutline](BodyPartOutline.gdshader) | Sprite 身体边界描边，PhysicalBodyParts / BodyPartsOutline 使用 |
| [PaperHandBack](PaperHandBack.gdshader) | Human 手部正反面视觉相关材质 |
| [SpiderLimbVisualStretch](SpiderLimbVisualStretch.gdshader) | Spider Limb 的视觉端点拉伸，不是增加刚体的物理伸缩自由度 |
| [StompShockwave](StompShockwave.gdshader) | 踏地冲击波外观；物理作用与伤害仍由脚本决定 |
| [UI/BlurMask](UI/BlurMask.gdshader) | 界面模糊遮罩 |

其他材质在 [PaperUI/TA](../Modules/PaperUI/TA) 和 [FrontierDelivery/Map](../Modules/FrontierDelivery/Scripts/Map) 中。Shader 可能由场景材质引用，也可能由脚本 preload 或运行时创建；只查 `.tscn` 不能找全使用方。

描边组件 [AutoOutline](../Scripts/VFX/AutoOutline.gd) 有独立 `outline_enabled` 开关，轮廓构建与 Sprite Shader 并非完全同一实现。调整透明排序、深度偏移和正反面裁剪后，应在实际 Forward+/D3D12 包体检查，不能只靠 headless。
