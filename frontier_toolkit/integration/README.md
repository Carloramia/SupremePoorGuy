# 大地图与 2.5D 悬浮场景

城镇弹窗的“进入场景 / Enter town”在原有大地图上打开应用内窗口。大地图节点、玩家位置、相机、迷雾和地点状态保留，移动与输入继续保持弹窗期间的冻结状态。2.5D 使用独立 SubViewport 和 World3D，窗口内可选择物件、拖动和缩放镜头。

点击窗口右上角“返回大地图 / Return”，或场景发出 `scenario_exit_requested(reason)`，关闭悬浮窗口、结束原城镇交互、恢复大地图并保存。记录一次 visit 和退出原因，`complete_location=false`；重复城镇保持可访问。每次进入重新实例化 2.5D 场景，当前不保存其内部状态。

## 地编配置

1. 在大地图根节点下保留 ScenarioOverlay 节点与 `integration/scenario_overlay.gd`。Demo 已配置；从 Demo 另存的地图会保留它。
2. 选择城镇地点，展开 LocationDefinition，将 `scenario_scene` 赋为目标 2.5D `.tscn`。未配置时不显示进入选项。
3. 目标场景根节点须使用 ScenarioController 或其派生脚本，且三个控制器引用完整。现有 `Scenario25DDemo.tscn` 可直接使用。
4. 当前入口仅在 SettlementPanel 中提供，其他地点类型仍使用原交互选项。
5. 修改独立城镇的目标前，将共享地点 Definition 使唯一并另存；共用 Definition 的城镇也会共用目标场景。

## 程序接入

LocationInteractionPanel 发出 `scenario_start_requested`；LocationInteractionController 使用当前地点的配置发出 `scenario_requested(location_id, scene)`。ScenarioOverlay 在模块外组合两个框架，核心不调用 SceneTree.change_scene。

场景结束时调用：

```gdscript
request_scenario_exit(&"scenario_complete")
```

这会结束原交互并返回大地图。外部系统若直接完成原交互，适配层也会清理悬浮场景，避免残留窗口。不可重复打开；目标类型或控制器配置无效时保留原弹窗与冻结状态，并显示错误提示，便于玩家继续选择原选项。

不要在嵌入场景里直接更换主场景或修改宿主 Window 的 content_scale。Demo 脚本仅在独立运行时设置 1920×1080，嵌入运行会跳过该修改。实际摄像机投影使用子视口尺寸。

## 验证

```powershell
./world_map/tools/Run-Tests.ps1 -Render
```

其中 `scenario_overlay_tests.gd` 验证真实按钮入口、子视口拾取与缩放、背景冻结、窗口尺寸变化、返回按钮、场景结束信号、重复打开与错误场景处理。结果为 `integration/scenario_overlay_test_results.json`，图形运行截图为 `integration/scenario_overlay_preview.png`。这些是测试输出，不是关卡配置。
