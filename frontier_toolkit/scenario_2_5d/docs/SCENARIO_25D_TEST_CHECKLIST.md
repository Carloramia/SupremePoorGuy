# SCENARIO 2.5D Test Checklist

验证日期：2026-10-06。Godot 4.7.2 stable official / Windows / GL Compatibility / RTX 4070 SUPER。

执行：`./scenario_2_5d/tools/Run-Tests.ps1 -Render`（从项目根目录）。

## 功能自动验收：42 / 42 PASS

| 分类 | 覆盖内容 | 结果 |
| --- | --- | --- |
| 生命周期 | 初始化完成、NavigationRoot、SpawnPoint ID | PASS |
| Camera | Orthographic、固定旋转/局部位置、中键 XZ 拖动、右键无旋转 | PASS |
| Drag | 实际 Rig 平移，在 UI 上松手立即停止，无惯性 | PASS |
| Zoom | target 先变、size 平滑逼近、min/max clamp | PASS |
| Input | 摄像机输入独立锁定，SceneTree 暂停时可继续缩放 | PASS |
| Bounds / Focus | 极端 XZ 被限制、一次聚焦、失效目标安全处理 | PASS |
| Billboard | QuadMesh、竖直、底部锚点、无真实投影、BlobShadow | PASS |
| Occlusion | Hero → Building，独立材质 Alpha，移开恢复原透明模式 | PASS |
| Multi target | Selected 被挡淡化，多个目标/多个遮挡物，同一 ray 多个遮挡体 | PASS |
| Restore | 注销目标恢复 Tree，取消选择恢复 Building，删除对象安全 | PASS |
| Interaction | 最近物体选择、旧选择取消、高亮、请求信号 | PASS |
| No click-through | Interactable 不发 ground event，建筑挡隐藏物件，障碍挡地面 | PASS |
| SceneMode | EXPLORE/COMBAT 分发不同 Ground Signal，包含真实 3D hit | PASS |
| UI | Info Panel，真实 viewport 按钮点击发出请求且不点击地面 | PASS |
| Resize | 1280×720 后仍可正确射线选择物件 | PASS |

逐项名称与布尔结果见 `debug/test_results.json`。失效 focus 测试会按设计输出一条 warning，不属于故障。

## 实际 OpenGL 渲染验收：5 / 5 PASS

| 验收 | 方法 | 结果 |
| --- | --- | --- |
| 建筑后方深度 | 关闭 Fade，对比 Hero 显示/隐藏的目标区域 | 0 个显著差异像素，PASS |
| 遮挡自动淡化 | 目标区域对比 Fade ON/OFF | 15,470 个显著差异像素，PASS |
| 建筑前方可见 | Hero 切到建筑前，对比显示/隐藏 | 3,647 个显著差异像素，PASS |
| Info Panel | 真实渲染并保存 Selected 截图 | PASS |
| 窗口适配 | 1920×1080 与 1280×720 截图，面板位于视口内 | PASS |

见 `debug/render_test_results.json` 和 `debug/preview_fade.png`、`preview_depth_behind.png`、`preview_depth_front.png`、`preview_selected.png`、`preview_resize.png`。截图已视觉检查：纸绘 Alpha 边缘、Blob Shadow、固定倾角、真实建筑遮挡和 Info Panel 正常。

## 手动复验步骤

1. F6 打开 Demo，中键拖动、滚轮缩放；右键和左键拖动不能旋转或拖动镜头。
2. Fade OFF + Hero behind/in front：后方完全隐藏，前方可见；Fade ON：后方建筑自动变透明。
3. 鼠标移到箱子或 NPC，出现 Hover；左键选中，Info Panel 出现。
4. 点 Interact，底栏打印稳定 ID；点击按钮不产生 Ground 事件。
5. 点击空地，底栏显示世界 X/Y/Z 并显示地面 Marker；切换模式后事件名称不同。
6. Camera input lock 只禁止 Camera 输入，不禁止选择；Focus hero 为一次性聚焦。
7. 改窗口尺寸，确认面板锚点、拾取与摄像机平移仍正常。

## 世界地图回归

迁移入口后运行 `./world_map/tools/Run-Tests.ps1 -Render`：400 组数据检查、28 项原验收、28 项道路验收，以及 Hex debug 显隐和道路 OpenGL 渲染全部 PASS。
