# SCENARIO 2.5D Implementation Report

## Implemented

按总开发提示词完成独立场景框架与可直接 F6 运行的 Scenario25DDemo.tscn。包含固定正交 Camera、平移缩放、纸绘 PNG、QuadMesh、真实深度、BlobShadow、整物体遮挡淡化、统一交互、高亮与选择、Info Panel、模式分发、生命周期与外部扩展位置。

先完成目录分离：世界地图文档移入 world_map/docs，启动与测试工具移入 world_map/tools；2.5D 的全部代码、资源、文档和工具放在 scenario_2_5d。两个模块共用 Godot 项目与引擎，没有互相依赖。

## Architecture

ScenarioController 协调 Resource、Camera、Interaction、Occlusion 并转发信号。布局在 .tscn 中，三个 .tres 展示场景和交互定义。RuntimeState 在每个 Interactable 实例中深拷贝。DemoUI 和 Demo 窗口设置都可从正式场景移除。详细结构见 SCENARIO_25D_ARCHITECTURE.md。

## Camera

Orthographic，yaw=0°，pitch=-50°，局部距离=30；默认 size=20，min=10，max=26，zoom_step=1.5，drag smoothing=20，zoom smoothing=12。XZ Bounds=(-18,-14) 到 (18,14)，margin=2。视口角射线和真实平面交点映射拖动，边界同时考虑可见范围、当前/目标 size 和窗口尺寸。松手丢弃平移余量；禁止右键旋转与左键拖动。输入独立于暂停，失效 Focus target 安全警告。

## Billboard

QuadMesh，Y-only camera facing，底部锚点、高度/比例/pivot/ground offset 可配置。占位 PNG 在程序中绘制并修复 Alpha 边缘，开启 mipmaps，默认线性过滤；允许近邻模式。专用 Shader 使用轻度受光 + 原色 emission、保留深度测试与 Alpha 预处理。透明边缘 discard；Quad 不投影，独立软椭圆 BlobShadow 贴地。动画源/帧/请求接口已提供，当前只显示静态图。

## Occlusion

正交平行 ray 从目标 screen position 的 Camera near-plane origin 指向目标；排除已命中 Collider RID 继续检测，处理同 ray 多遮挡体和多目标合并。只对 ScenarioOccluder3D 淡化；不是所有 Mesh 自动透明。遮挡体复制自己的 StandardMaterial3D 或纸绘 ShaderMaterial，保护共享资源。Smooth Fade 到 0.22；目标移开、取消选择、注销或系统停用后恢复。恢复完成时原始 Alpha 与透明模式也恢复。

实际渲染发现并修复 material_override 高于 surface override 的优先级；不支持的 Shadow Shader 保持原始显示。未来局部 Mask 可通过同一 Fade API 扩展。动态目标使用 Marker，可由战斗/探索系统注册。

## Interaction

Camera project_ray_origin / project_ray_normal → PhysicsDirectSpaceState 最近命中。输入 UI > Interactable > Ground；实体与禁用交互物件仍挡住后方命中；只有 scenario_ground Group 发出世界坐标。Hover/Selected 有可替换反馈信号和默认纸绘 tint。Info Panel 显示名字、类型、ID、说明和 Interact。请求只发 interaction_requested(object_id, definition, runtime_state)，没有实现物品/对话玩法。

## SceneMode

EXPLORE / COMBAT 只选择 ground signal；scene_mode_changed 让外部配置 UI/hover。不会移动角色、攻击或放置单位。Demo 提供模式切换和 Ground Click Marker。

## Integration Interfaces

Battle 监听 combat_ground_clicked，注册重点单位 OcclusionTarget，使用 SpawnPoint、真实碰撞接入点和 Camera focus；Exploration 监听 explore_ground_clicked 与 interaction_requested，使用 RuntimeState、导航位置与聚焦。NavigationRoot 保留 Region 位置，无 Agent/烘焙。SpawnPoint3D 提供 ID、metadata 和 transform，无类别预设。SceneManager 监听 scenario_exit_requested；initialized/Ready 信号表示初始化。详见 README 示例。

## Files Added

- core/scenario_controller.gd
- data/scene_definition.gd、scene_mode.gd、interactable_definition.gd、interactable_runtime_state.gd
- camera/scenario_camera_controller.gd、camera_bounds_3d.gd
- visuals/billboard_visual_3d.gd、blob_shadow.gd、paper.gdshader
- interactables/interactable_3d.gd、interaction_controller.gd
- occlusion/occluder_3d.gd、occlusion_target.gd、occlusion_controller.gd
- spawn/spawn_point_3d.gd、ui/demo_ui.gd
- demo/Scenario25DDemo.tscn、scenario_demo.gd、data/*.tres、assets/Hero/NPC/Tree/Crate.png
- debug/generate_placeholders.gd、acceptance_tests.gd、render_preview.gd、JSON 结果与截图
- tools/Run-Demo.ps1、Run-Tests.ps1
- README.md、docs/计划/架构/测试清单/本报告；根目录 README.md 模块入口

Godot 同时生成 Script UID 与 PNG 导入描述。

## Files Modified / Moved

世界地图的四份 WORLD_MAP 文档移至 world_map/docs；两个根启动脚本移至 world_map/tools，更新 projectRoot 解析；world_map/README.md 更新运行命令和文档位置。project.godot 保留默认 WorldMap 主场景和显示配置。世界地图代码、存储与玩法接口未改动；回归测试重新生成原有 debug 结果/截图。

## Test Results

Godot 4.7.2 stable Windows：功能验收 42/42 PASS；实际 OpenGL 验收 5/5 PASS；全部源码导入成功，无脚本或 Shader 错误。建筑后方 Hero 显隐对比 0 个差异像素，前方 3,647 个，Fade 与不 Fade 对比 15,470 个，验证真实深度与遮挡恢复。1920×1080 和 1280×720 的画面与 UI 已检查。UI 通过真实 viewport 点击，不穿透地面。

世界地图回归：400 组数据检查、28 项 SceneTree 测试、28 项道路测试、Hex debug 和道路渲染全部 PASS。删除 Focus target 的测试按设计产生一条 warning；测试状态为通过。

## Known Limitations

不含完整战斗/探索/动画/角色移动/导航/保存/真正场景切换。拾取只承诺基本平面场景，不实现多层优先级。手工 Camera Bounds，在范围小于视野时居中而不能凭空产生场地。Occlusion 用 Collider 而非精确纹理轮廓，检测成本随目标与命中数线性增加。当前整物体 Fade，多层透明对象可能出现常见排序问题；不支持的 Shader 必须通过适配器接入。BlobShadow 贴在 Actor 局部地面，高台可直接调整 Actor 高度，坡地法线适配由外部负责。默认 Selected Marker 高度为 0.7，正式异形物件可以注册自己的目标点。占位美术用于技术验收。
