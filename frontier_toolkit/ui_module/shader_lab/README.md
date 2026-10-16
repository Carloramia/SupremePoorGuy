# UI Shader 材质库与独立实验台

依据 [2026-10-13 需求案](../../shader需求/UI_Shader材质需求案_2026-10-13.md) 实现。默认中强度，Godot 4.7.2 / GL Compatibility。先在独立场景验证，再由各系统负责人接入；当前游戏默认入口保持原配置。

打开根目录项目，然后打开 [ShaderLab.tscn](demo/ShaderLab.tscn)，按 F6。五列使用同样的素材，分别展示原始、仅 S1、仅 S2、仅 S3、组合效果。顶部可切换轻／中／强、浅纸／深色／复杂地图底，以及线宽、白底宽度、颗粒和毛边。地图底是测试用程序图案。

```powershell
./ui_module/shader_lab/tools/Run-Lab.ps1
./ui_module/shader_lab/tools/Run-Lab.ps1 -Tests
./ui_module/shader_lab/tools/Run-Lab.ps1 -Capture
```

`-Tests` 检查组件和算法；`-Capture` 使用真实 OpenGL 渲染，另外检查像素和静止帧，并重新生成 [对照图](tests/screenshots/)。首次检出需先让 Godot 完成资源导入。引擎路径可用 `-GodotPath` 或项目现有 `GODOT_BIN` 配置。

## 资源索引

| 资源 | 用途 |
| --- | --- |
| `shaders/ink.gdshader` | 可编辑笔触带：局部断墨、毛边、保护核心 |
| `shaders/textured_ink.gdshader` | 已制作的透明笔触／九宫格边框：用基础素材提供复笔结构 |
| `shaders/paper.gdshader` | 纸面颗粒、颜料颗粒和局部边缘磨损；圆角大小不随拉伸变化 |
| `shaders/cutout.gdshader` | 完整剪影的连续白底，单次距离场采样，无投影或发光 |
| `components/ink_path.gd` | 可调圆角框、分割线、归一化路径；可关闭复笔保护输入线段 |
| `components/paper_surface.gd` | 纸面层；可替换纸纹及红通道保护遮罩 |
| `components/paper_cutout.gd` | 独立透明图形；自动生成距离场和绘制留边，保持 Control 尺寸 |
| `components/silhouette_field.gd` | 外部透明区域洪泛填充 + 两遍精确欧氏距离变换 |
| `components/PaperButton.tscn` | 原生 Button，独立底纸、墨线和焦点层；支持原生输入状态 |
| `presets/off/light/medium/strong.tres` | 公共样式 Resource，可在 Inspector 调整、复制并单件覆盖 |
| `presets/*_medium.tres` | 可直接查看、复制的 ShaderMaterial |
| `demo/ComponentWorkshop.tscn` | 可在场景树逐层编辑：五种按钮状态、宽窄九宫格、进度条、准确路径和头像 |
| `assets/` | 本轮自制 SVG 占位图与基础九宫格笔触，不含文字或预制白边 |
| `tests/acceptance.gd` | 组件、真实鼠标／Tab 输入、距离场、实际像素与双分辨率验证 |

## 接入方式

1. 需要原生按钮时，实例化 `PaperButton.tscn`，保留 Button 自身的文字、布局、信号、焦点和业务处理。当前组件中的标签示意可直接改为真实文本。
2. 面板、卡片、进度条等，在原控件下添加独立 Control，挂 `paper_surface.gd` 或 `ink_path.gd`，使视觉层与父控件对齐。用 `show_behind_parent` 放到文字后方，不把材质设到含文字的父节点。
3. 线性图标或召唤阵使用 `ink_path.gd` 的 Editable path。路径坐标为 0—1；中心线由组件实际尺寸映射。召唤输入路径关闭 `allow_repeat`、开启 `protect_centerline`，继续由原系统处理输入及连通关系。
4. 透明图形使用 `paper_cutout.gd`，赋值 `texture`。原图保留无白边版本；`silhouette` 可选，用于美术提供的完整剪影。剪影与原图应使用相同画布和对齐，算法读取 Alpha（不读取 RGB 灰度）。
5. 成组装饰先离屏合成为一张整体 RGBA，再作为主体输入；或者提供整体剪影。不要给怪物每个拼接零件分别加白底。
6. 九宫格使用 `NinePatchRect`，指定自制或替换的透明笔触、24 px 角区及 `textured_ink_medium.tres`。示例采用 Stretch 连接直边，噪声取局部像素坐标。替换素材时维持直边端点匹配；复杂纹理应制作可平铺中段。

所有工具组件支持 `@tool` 编辑器预览，视觉节点默认忽略鼠标。它们不注册 Autoload，也不读取召唤、库存、地图或角色数据。已有 StyleBox 的底纸、边框、阴影应在实际接入时关闭相应项，避免重复绘制。

白底绘制会超出 Control 的原矩形，点击范围保持不变。父控件的 `clip_contents`、ScrollContainer 或 SubViewport 边界仍会裁切子内容；在这些容器内，应由布局预留外围空隙，或把装饰放到不裁切的独立层。Shader 无法越过祖先节点的裁剪。

## 参数与单组件覆盖

在 Inspector 展开 Profile；要只改一个组件，先将资源“设为唯一”，或保存一份新的 `.tres`。共享 Resource 的修改会通知全部使用者，悬停／按下不复制或重新随机生成资源。

| 参数 | 含义 |
| --- | --- |
| `line_width / width_variation` | 设计像素线宽、提按变化 |
| `irregularity / repeat_strength` | 轻微边缘偏折、短段复笔强度；中心线偏移限制在线宽的 18% 内 |
| `ink_color / ink_loss / seed` | 墨色、局部缺墨、稳定种子 |
| `paper_grain / pigment_grain / grain_size` | 纸面和颜料颗粒强度、程序颗粒的设计像素尺寸 |
| `edge_coverage / edge_size` | 局部毛边覆盖比例、磨损宽度 |
| `backing_width / backing_color` | 白底的设计像素宽度和颜色，默认纯白 |
| `s1_enabled / s2_enabled / s3_enabled` | 效果开关；S1、S3 都可影响墨线局部边缘 |
| Paper 的 `protected_margin / protection_mask` | 边缘以内的保护范围；遮罩红色为 1 的区域保护磨损 |
| Paper 的 `paper_texture` | 可选无缝灰度纸纹，读取红通道、Repeat，平铺周期 128 设计像素 |
| Cutout 的 `smoothing` | 白底边缘抗锯齿宽度；0.4—2 设计像素，不作为光晕 |

`ink.gdshader` 需要组件提供笔触带 UV，不能直接挂到任意照片上。可伸缩笔触的基础结构来自可编辑路径；透明素材的复笔结构来自美术源图。单独的 ShaderMaterial 不负责生成路径、设置组件尺寸或预处理完整剪影，建议使用上述组件。

默认画布 1280×720；1920×1080 等比放大时线宽和白底按设计像素一起放大。组件宽窄变化不会拉长程序颗粒；变更组件尺寸会重建路径或必要的剪影缓存，不改变父节点的尺寸或点击规则。

## 素材清单

| 文件 | 画布 | 对齐／默认显示 | 透明留边 |
| --- | --- | --- | --- |
| `badge.svg` | 128×144 | 中心 / 约 74×83 | 四周至少 8 px |
| `book.svg` | 144×128 | 中心 / 77×68 | 四周至少 10 px |
| `monster.svg` | 240×200 | 中心 / 172×143 | 四周至少 20 px |
| `nine_slice_ink.svg` | 96×96 | 九宫格 / 220×120、910×120 | 四周约 6 px；角区 24 px |

版本均为本轮 v1，无预制白底、投影、伪文字或外部付费素材。SVG 的笔墨／填色是源图本体；源图可替换为 RGBA PNG、sRGB。纸面和磨损使用静态程序噪声，不需要下载额外纹理。

## 验证与限制

本机验证环境：Windows，Godot 4.7.2-stable，OpenGL 3.3 / GL Compatibility，NVIDIA GeForce RTX 4070 SUPER。最终记录见 [验证记录](VERIFICATION.md)。程序检查日志和失败列表每次写入 `tests/test_results.json`（生成文件，Git 忽略）。

距离场在换图或需要不同遮罩尺寸时于 CPU 构建并缓存，静止帧没有纹理重抽或 CPU 像素扫描。遮罩最长边最多 256 px，小组件进一步降采样，缓存最多 32 项；原图仍按原导入分辨率采样。非常细的尖角可能受遮罩采样精度影响，需提高遮罩分辨率或预制高质量距离场后再做项目级接入。大批首次换图仍可能产生准备耗时，正式列表建议预热素材。

自动填洞只填封闭透明区。细缝与外部透明区域连通时，无法推断美术想要的整体形状，请提供完整剪影。分离零件之间的空白也不会自动凭空合并。

需求链接中的 U1—U6、R1—R6 图片和同名 PDF 未出现在当前工作目录；本轮按完整 Markdown 文字要求实现。当前 SVG 为功能验证占位图，笔触与最终美术强度仍应在拿到主参考和正式素材后评审。未进行目标移动设备性能预算测试。
