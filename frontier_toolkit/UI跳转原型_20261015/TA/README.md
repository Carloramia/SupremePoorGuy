# 新版 UI 的 Shader 接入说明

需求依据：上游 `docs/06_组件隔离与TA材质接口.md` 及同提交的 UI Shader 材质需求案。布局基线为0.7.12，功能与召唤口径沿用 `docs/08_召唤2.0接入与边界.md`。本轮只在独立测试场景接入材质。

## 文件与预设

| 文件 | 职责 |
| --- | --- |
| `Shaders/ink.gdshader` | S1，透明笔触纹理和九宫格的局部笔触强化 |
| `Shaders/paper.gdshader` | S3，面内颗粒与部分边缘缺墨 |
| `Shaders/cutout.gdshader` | S2，整体剪影距离场、连续白底和绘制留边 |
| `Presets/light.tres`、`medium.tres`、`strong.tres` | 原生 UISkinPreset，分别包含独立 ShaderMaterial |
| `PresetLibrary.gd` | 使用同一套基础素材生成五种效果组合，资源深复制 |
| `ShaderSkinBinding.gd` | 原 UISkinSlots 的视觉适配器，处理绘制锚点、按钮状态、焦点及剪影准备 |
| `SilhouetteField.gd` | Alpha 外部洪泛填充、欧氏距离场及缓存 |
| `Scenes/NativeSkinPreview.tscn` | 继承上游原生 TA 场景，无业务模型 |
| `Scenes/ShaderComparison.tscn` | 使用原生 ActionButton、LooseLeafPage、SummonBookButton、MonsterPortrait 做五列对照 |
| `Assets/` | 无字、无投影的底纸、透明笔触及透明测试图形 |

预设的 `surface_texture` 与 `outline_texture` 配套替换，避免原按钮自带边框与新线框叠加。主描边和复笔来自可替换源素材，Shader 修饰其表面，不生成参考图中的复杂素描结构。

## 单组件接入

独立验证通过后，在待接入组件或测试父节点下添加 Node，挂 `ShaderSkinBinding.gd`：

1. `Target Root` 指向包含现有 VisualSkin 插槽的组件；默认是父节点。
2. `Initial Preset` 指定 `medium.tres` 或自己的 UISkinPreset。
3. 原 VisualSkin 的 `Local Preset` 可指定一份设为唯一的预设；它不会逐字段合并公共预设。
4. 原 VisualSkin 的 `Enabled=false` 可撤回单件材质；适配器的 `restore()` 可统一撤回。
5. 动态新增组件后调用 `rescan()`，再按需应用预设。修改 ShaderMaterial 内部参数后调用 `apply_preset(preset)`，或使用独立预览的“应用测试预设”按钮。

```gdscript
# 此节点只操作展示组件，无库存、生成或文件读写。
$ShaderSkinBinding.rescan()
$ShaderSkinBinding.apply_preset(my_test_preset)
# 撤回测试
$ShaderSkinBinding.restore()
```

适配器沿用上游材质实例复制，`ui_size_px` 使用实际绘制尺寸，`ui_seed` 使用预设稳定种子。它的 Node2D 锚点不参与容器尺寸计算；所有新增视觉层忽略鼠标，标题、正文、数值、点击矩形和原布局仍由原组件负责。

不要只把 S2 的裸 ShaderMaterial 挂到图标上：它需要适配器生成并绑定完整剪影距离场。底纸、轮廓和插画分层设置，不能给整个页面或 RuneBoard 根节点套滤镜。原 RuneBoard 输入和绘图脚本保持原样，本轮不声称正式页面全部线条已经批量换肤。

## 参数

在预设中展开 `surface_material`、`outline_material` 或 `cutout_material` 的 Shader Parameters；先复制预设或设为唯一，再做单件调整。改嵌套材料参数后重新应用。

| 材质 | 关键参数 | 中强度 |
| --- | --- | --- |
| S1 | `line_width`、`width_variation`、`irregularity` | 2.8、0.25、0.32 |
| S1 | `ink_color`、`repeat_strength`、`ink_loss` | 深墨色、0.7、0.10 |
| S1/S3 | `grain_size`、`edge_coverage` | 1.3设计像素、0.34 |
| S3 | `paper_grain`、`pigment_grain`、`edge_size` | 0.065、0.045、1.2 |
| S3 | `protected_margin`、`protection_mask` | 8像素；可选红通道保护遮罩 |
| S2 | `backing_width`、`backing_color` | 6设计像素、纯白 |
| S2 | `smoothing`、`backing_enabled` | 0.7像素抗锯齿、开启 |
| 预设 | `stable_seed`、`patch_margin` | 42、24 |

S3 的遮罩红通道为1处保护边缘，遮罩坐标覆盖整个显示组件。粒度用局部像素坐标计算，九宫格 UV 接缝的导数做限幅，避免拼接处采到对侧边线。悬停、按下、禁用和焦点只更新状态色，不重抽纹理或种子。

对照页按1280×720设计画布等比放大到1920×1080；原生 TA 预览遵守上游禁用整体拉伸的窗口设置，按实际像素检查三个窗口尺寸。两者验证目的不同，均不修改原 project.godot。

## 透明资源与绘制边界

S2 输入应为带真实 Alpha 的完整主体。自动填充封闭透明内孔，不对白底内部每条黑纹理单独描边。连通外部的缺口保留；分离部件之间的空白不会自动变成整体实体，成组素材应先合成完整 RGBA 图。

上游三张概念参考 PNG 带背景且烘焙了阴影。适配器对完全不透明的参考图跳过白底，不进行自动抠图。独立测试只给原 Artwork 插槽指定透明示意 SVG，不改概念原图或正式怪物外观。

白底通过顶点扩展生成留边，控件矩形和命中范围不变。父级 `clip_contents`、滚动容器和视口裁剪仍有效；正式页面如需要新增布局留白，须按上游交接规则先提交具体方案，本轮未做这种调整。

遮罩最长边最多256像素，按显示尺寸对小图进一步降采样，缓存最多32项；原图仍按原分辨率采样。换图／显示尺寸变化时可能重建一次距离场，静止帧不扫描像素。极细尖角和大批首次换图需在目标设备再评估。

| 资源 v1 | 画布 | 对齐和用途 |
| --- | --- | --- |
| `paper.svg` | 96×96 | 中心、24像素九宫格角区；无边框、无投影 |
| `outline.svg` | 96×96 | 中心、透明中央、24像素角区；主笔触＋稀疏复笔 |
| `separator.svg` | 96×12 | 水平中心、左右4像素端区 |
| `badge.svg` | 128×144 | 中心，透明异形徽章，无白底 |
| `book.svg` | 144×128 | 中心，透明备用书本，无白底；当前对照采用上游书本图标 |
| `monster.svg` | 240×200 | 中心，四周约20像素透明空间，无白底 |

以上简单图形为本地自制示意 SVG，透明区域由矢量画布自然生成，可替换为 PNG RGBA / sRGB。纸面使用静态程序颗粒，无需下载笔刷。测试字体沿用上游 Xiaolai-Regular.ttf。

完整回归结果及限制见 [构建记录](../BUILD.md) 和 [验证数据](VALIDATION.json)。
