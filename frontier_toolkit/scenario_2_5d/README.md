# 2.5D 场景框架

固定斜俯视正交 Camera3D + 真 3D 建筑 + 纸绘 QuadMesh。独立于 world_map；仅提供场景、视觉、拾取和系统接入接口。

## 地编场景制作

[地编人员完整使用手册](docs/SCENARIO_25D_LEVEL_DESIGNER_GUIDE.md)：从复制关卡、物件摆放到交互、遮挡、摄像机和交付验收的完整操作流程。

[项目地编总手册](../docs/LEVEL_DESIGNER_GUIDE.md) 同时覆盖大地图、道路、地点和存档重置，适合跨模块制作时查阅。

现有 Demo 可从大地图城镇弹窗嵌入运行，详见 [2.5D 悬浮场景接入](../integration/README.md)。子视口运行不修改主窗口缩放；场景结束信号由适配层用于返回地图。

## 运行

打开根目录 `project.godot`，再打开 `scenario_2_5d/demo/Scenario25DDemo.tscn` 按 F6。默认 F5 仍运行世界地图。

从项目根目录执行：

```powershell
./scenario_2_5d/tools/Run-Demo.ps1
./scenario_2_5d/tools/Run-Demo.ps1 -Editor
./scenario_2_5d/tools/Run-Tests.ps1 -Render
```

中键拖动、滚轮平滑缩放、左键选择/地面事件。不会旋转摄像机。Info Panel 的 Interact 只发统一事件。Demo 按钮可切换 EXPLORE/COMBAT、角色前后测试位置、淡化开关、聚焦角色及输入锁定。

验收深度：关闭 Fade，切换 Hero 前后位置；建筑后方角色完全被遮挡、前方显示。打开 Fade，Hero 在建筑后方时建筑淡化。右侧树木也是注册遮挡物，可通过外部目标进行遮挡测试。

## 新建场景

复制 Demo 作为起点，保留根节点 ScenarioController 与三个控制器引用；空间布局保存到自己的 `.tscn`，绑定独立 `SceneDefinition.tres`。删除 DemoUI 和 `scenario_demo.gd`，根节点改挂 `core/scenario_controller.gd`。摄像机已有外部引用；外部无需使用层级相对路径。

SceneDefinition 参数：scene_id、display_name、camera_bounds（Rect2 的 x/y 映射世界 X/Z）、default/min/max_camera_size、camera_drag_smoothing、camera_zoom_smoothing、camera_margin、zoom_step、default_scene_mode、metadata。速度为指数插值频率，必须使用正值；min/max size 必须大于零且 min <= max。CameraBounds3D 可覆盖资源边界，通过 set_bounds 更新手工边界。范围必须足够容纳镜头视野，否则锁定该轴中心，允许余量后仍会露出的空白是场地尺寸限制。

Demo 参考 UI 为 1920×1080；仅 Demo 脚本临时设置窗口 content scale，并在退出时恢复，不改变共享 project.godot。普通场景由外部宿主决定窗口配置。摄像机边界使用实际视口四角在水平面的投影，随缩放、窗口比例与固定 yaw 调整。

## Billboard / Actor

Node3D → PhysicsRoot（外部 Body 接入点）与 VisualRoot → BillboardVisual3D + BlobShadow。Billboard 内部创建 QuadMesh，只绕世界 Y 轴面向当前 Camera 的 XZ 位置。贴图缺失时警告并使用色块。

设置 texture、visual_height、visual_scale、ground_offset、pivot_offset；底部锚点自动计算，无需手动移动 Mesh。linear_filter=false 可切换像素风近邻过滤。默认纸绘 Shader 保留 68% 原色 emission，22% 材质受光，保留深度测试；透明边缘 discard + alpha 深度预处理。Quad 不投真实阴影，BlobShadow 随 VisualRoot 移动并可调大小/透明度。将 ActorRoot 放到真实高度即可保持立片、影子和外部物理接口同步。

play_visual_animation(name) 发出视觉请求；set_animation_source(Resource) 保存外部动画源；set_frame(Rect2) 指定归一化 UV 帧范围。当前没有动画或角色移动状态机。

## Interactable

StaticBody3D 挂 `interactables/interactable_3d.gd`，绑定 InteractableDefinition、BillboardVisual3D，并添加 CollisionShape3D。任意 Mesh 物件也可使用，连接 hovered_changed/selected_changed 替换高亮效果即可。

Definition 的 object_id 必须在内容制作时提供稳定且唯一的值；不要使用 instance_id。每个实例会深拷贝 RuntimeState，enabled、selected 和 custom_state 不污染静态资源。Definition 缺失时交互禁用但仍挡住射线。

拾取层：1（场景实体和地面）。查询最前方命中，Interactable 消费点击；普通实体也挡住后面的地面；只有带 scenario_ground Group 的实体发出真实命中位置。UI 使用 _unhandled_input 顺序，交互面板阻止穿透；空白 UI 根节点使用 IGNORE。不要把全屏装饰层设置为 STOP。

## Occluder / OcclusionTarget

StaticBody3D 挂 `occlusion/occluder_3d.gd`，collision_layer=3（1+2），并添加真实 Collider 和 Mesh。仅该接口类型参与 Fade。StandardMaterial3D 与默认纸绘 Shader 自动生成独立材质实例；其他 Shader 需提供自己的 set_fade_amount/restore_fade 实现并适配检测器。不会修改共享材质，完全恢复后恢复初始透明模式和颜色。树的 BlobShadow Shader 不参与 Fade。

目标使用 `OcclusionTarget` Marker3D，设到角色胸口或重要物件的可见中心。场景 Ready 自动收集本场景下该 Group 的初始目标；运行时使用：

```gdscript
scenario.register_occlusion_target(target_marker)
scenario.unregister_occlusion_target(target_marker)
```

选择物件时框架自动注册一个高度 0.7 的子 Marker，取消选择时移除；其他高度的正式物件可自行注册正确位置的目标。检测使用平行正交射线，枚举整条 ray 上所有遮挡物，合并所有目标结果；不再阻挡的对象恢复。外部不应注销框架选择目标；只管理自己注册的目标。

## 外部系统接入

```gdscript
scenario.set_scene_mode(SceneMode.Mode.COMBAT)
scenario.combat_ground_clicked.connect(on_battle_ground)
scenario.explore_ground_clicked.connect(on_explore_ground)
scenario.interaction_requested.connect(on_interaction)
scenario.set_camera_input_enabled(true) # 暂停是否锁镜头由调用者决定
scenario.set_focus_target(unit)
scenario.focus_on_target()
scenario.clear_focus_target()
scenario.request_scenario_exit(&"return_to_map")
```

interaction_requested 参数为 object_id、definition、runtime_state。Hover/Selected 信号提供稳定 ID。外部战斗系统负责单位、攻击和移动；探索系统负责对话、物品与任务；SceneManager 监听 scenario_exit_requested 并执行真正切场。通过 scenario_initialized、scenario_ready 或 initialized 属性判断初始化；晚于 Ready 接入时应检查属性，避免错过一次性信号。

NavigationRoot 为未来 NavigationRegion3D 的接入位置，本版没有烘焙、Agent 或路径逻辑。SpawnRoot 下 SpawnPoint3D 提供 spawn_id、metadata 及真实 3D transform；外部生成器自行选择场景并放置，不预定义阵营分类。

## 替换资源与验收

替换 demo/assets/Hero/NPC/Tree/Crate.png 为带透明边缘的正式 PNG，保留导入设置的 mipmaps/generate=true 与 fix_alpha_border=true。`debug/generate_placeholders.gd` 用程序绘制并保存 PNG，无需任何正式美术资源。

[架构](docs/SCENARIO_25D_ARCHITECTURE.md)、[测试清单](docs/SCENARIO_25D_TEST_CHECKLIST.md)、[实施报告](docs/SCENARIO_25D_IMPLEMENTATION_REPORT.md)。结果保存于 debug/test_results.json 和 debug/render_test_results.json；截图为 debug/preview_*.png。
