# 当前地图的 Godot 视觉预览

本目录是当前六边形编辑器地图的原生视觉预览源码。读取同级 `Data/Maps/hex_layout.json` 与 `Tools/hex-planner/assets` 的实际素材，包含图 8 山石、85% 树木版本及现有高清底图原始分块。没有沿用旧 Demo 的 SVG 占位素材，也没有重新编码或移动美术资源。

## 打开

补丁已附带与本次保存进度匹配的 `scene.json`。安装后直接在 Godot 4.7.2 或兼容版本导入本目录 `project.godot`，按 F5；首次打开无需 Python，保留大包目录结构即可读取原高清素材。路径相对于工程，不依赖制作电脑的盘符。

后续修改布局后，使用 `Start-CurrentMapPreview.ps1 -GodotPath <godot.exe> -PythonPath <python.exe>` 重新生成到 `generated-preview`。Python 需要 Pillow、NumPy、SciPy 和支持 `constrained_delaunay_triangles` 的 Shapely。可用 `-Output` 指定独立生成目录；`--portable` 路径随输出目录计算，移动结果时需保持相对结构。

每次编辑器保存后重新运行启动脚本。预览会校验布局 SHA256；过期的约束数据会拒绝加载，避免拿旧地图验证新效果。`scene.json` 仅为生成数据，不是地图的第二份编辑源。

左键移动，滚轮缩放，中键平移；顶部按钮查看指定城镇，F2 全图审阅，F3 回到角色。抵近按钮仅改变本次预览的位置。

## 显示规则

- 角色的视野采用地图中的 `vision_radius`，当前为 630。山石的覆盖层也按相同半径裁切；不会因一段石头进入视野而显示整条山脉。
- 视线首先命中山体近侧，范围内的山石图像可以显示至远侧；山后地形仍受遮挡。独立的第二条山脉不会因此显露。
- 视野采用细小方块及分层透明度的过渡。二维滤波收圆尖角，单独的低分辨率迷雾缓冲保留像素感；底图、树木、山石和图标仍按原始高清素材绘制。
- 迷雾在山体背面的地面向内压盖约 32 世界单位，封住后缘的亮缝。山石本体保持完整的不透明轮廓，后缘只叠加最高 22% 的薄雾色，颜色取自同一帧迷雾；按美术实边的距离遮罩连续过渡，避免把岩面裁成缺角、三角片或像素切口。像素颗粒仅用于迷雾；山石到 630 视野边界时连续淡入雾中，范围外完全隐藏。逻辑阻挡和宽通路保持原样。
- 已知城镇和召唤小屋拥有扩大、柔边的地面衬底。地标衬底仅改变显示，不揭露怪物、事件或周围可交互内容。
- `MapSight.gd` 的逻辑 LOS 和视觉表面范围分开。`ray_distance` / `visible` 保持近侧阻挡；RG 射线纹理的 G 通道只用于表现第一段连续山体表面。
- `MapPresentation.gd` 支持对象的可选 `ground_patch` 字段：`enabled`、`size`、`color`、`opacity`、`asset`。代码默认生成程序化地面衬底，后续可以接美术提供的独立底座素材。

预览不写正式地图或游戏进度，不执行事件、遭遇战、奖励和破坏存档。现有事件与战斗系统的对接仍以已交付的系统合并文档为准。本目录不能当作完整游戏入口。

## 验证

先通过启动脚本生成预览到工作目录，再对该目录运行 Godot 测试（需要实际图形渲染器，不能使用 headless）：

```powershell
godot --path <生成的预览目录> --script res://tests/test_fog.gd
godot --path <生成的预览目录> --script res://tests/test_surface_radius.gd
godot --path <生成的预览目录> --script res://tests/test_rear_overlap.gd
godot --path <生成的预览目录> --script res://tests/test_mountain_integrity.gd
godot --path <生成的预览目录> --script res://tests/capture_current.gd
```

检查内容包括山石本体显示、山后目标遮挡、像素块过渡、范围外零山石像素泄漏、当前布局与素材版本一致、地标衬底层级。截图和 JSON 结果写在生成目录内，不修改正式数据。
