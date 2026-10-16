# UI 模块 · GitHub 原型接入

2026-10-13 新增独立 [UI Shader 材质库与实验台](shader_lab/README.md)：手绘线框、连续剪纸白底、颗粒与局部毛边，含可编辑组件、轻中强预设、五组对照和双分辨率验证。打开 `shader_lab/demo/ShaderLab.tscn` 后 F6；逐层编辑用 `shader_lab/demo/ComponentWorkshop.tscn`。本轮按需求先独立交付，现有游戏页面尚未批量替换材质。

来源：[Carloramia/SupremePoorGuy · UI跳转原型](https://github.com/Carloramia/SupremePoorGuy/tree/43f4e54f9beaa0341f7dc58a0e35680b27c513de/UI%E8%B7%B3%E8%BD%AC%E5%8E%9F%E5%9E%8B)，固定提交 `43f4e54f9beaa0341f7dc58a0e35680b27c513de`，原型版本 0.5。2026-10-13 获取171个原始文件，逐个校验 Git blob SHA-1；完整原版保留在根目录 `UI跳转原型/`，作为独立参考工程，不参与宿主扫描。

## 运行

导入根目录 `project.godot`，F5 进入带 UI 的真实大地图。Godot 4.7.2 / GL Compatibility。

```powershell
./ui_module/tools/Run-Demo.ps1
./ui_module/tools/Run-Demo.ps1 -Standalone
./ui_module/tools/Run-Tests.ps1
./ui_module/tools/Run-Tests.ps1 -Render
```

集成入口：`demo/UIWorldMapDemo.tscn`；独立交互演示：`demo/UIModuleDemo.tscn`。调布局与贴图可直接编辑 `prototype/Scenes/UI/`，组件工作台为 `prototype/Scenes/UI/UIWorkshop.tscn`，F6 独立预览。

## 已构建的流程

- 真实地图上的书本入口 → 法阵绘制、7枚符文、3种奇物 → 扣费并保存3个实例 → 可跳过的喷涌演出 → 结果安置。
- 妖兽仓库与出战队列独立入口，仓库／队列／全部筛选、详情、改名、属性和特性说明，6只队列上限。
- 公共纸雕主题、纸底、边框、铜钉、按钮、怪物卡和画板进出动画；嵌套弹窗逐层返回，关闭后恢复焦点。
- 弹窗及完整退出动画期间冻结地图；关闭后恢复原地图、玩家与路径。空白 UI 区域将鼠标交给真实寻路、拖动及缩放。
- 地图保存、读取、跟随及调试入口。原有地点事件、战斗适配器及城镇 2.5D 悬浮窗口继续负责其流程。

## 目录和接入接口

| 路径 | 责任 |
| --- | --- |
| `core/game_ui.gd` | GameUI 公共入口、弹窗状态、焦点、实际地点上下文与宿主信号 |
| `integration/world_map_ui_bridge.gd` | CanvasLayer 组合、暂停归属、当前玩家 Hex／地形上下文、地图命令 |
| `prototype/Scenes/`、`prototype/Assets/` | 编辑器可调整的原生组件、屏幕、主题与素材 |
| `prototype/Scripts/PrototypeState.gd` | 单一 UI 会话：魔力、怪物ID、仓库、队列、待安置结果及事务保存 |
| `prototype/Scripts/Ritual/` | 法阵纯规则、蜂窝输入与拖放 |
| `tests/`、`prototype/Tests/` | 宿主集成验证和原型回归 |
| `UPSTREAM.json`、`upstream/source-manifest.json` | 版本来源和完整原文件哈希清单 |

GameUI 的 `open_summon(context)`、`open_warehouse()`、`open_party()` 返回是否成功打开。`is_blocking()` 包含弹窗、退出动画及喷涌；`set_external_blocked(bool)` 防止覆盖宿主正在进行的交互。`context_provider` 可按实际玩家位置实时提供上下文。

```gdscript
ui.open_summon({
    "map_id":"frontier", "hex":[2,3], "position":[192.0,387.0],
    "terrain":"forest", "biome":"forest", "display_name":"林间营地"
})
ui.open_warehouse()
```

信号：`blocking_changed(blocked)`、`map_command_requested(command)`、`summon_committed(monster_ids, context)`、原有 `party_changed(monster_ids)`。`summon_committed` 是保存成功后的通知，监听方不得再次扣费或生成。召唤的 `source_context` 与 `pending_context` 随同结果事务保存，重启恢复不按玩家新位置重新抽取。

本模块不注册 Autoload、不替换全局输入、不调用全局 SceneTree 暂停。新地图可将 `WorldMapUIBridge` CanvasLayer 加到 WorldMapController 根节点下；`world_map_path` 指向该控制器。当前 Demo 已配置。原 WorldMapUI 只增加稳定节点名，布局和业务不依赖新模块。

## 数据与原型边界

UI 进度为 `user://ui_module_session.json`，地图继续使用自身存档。启动脚本把 APPDATA 临时指向 `.tools/userdata`，直接编辑器 F5 使用标准用户目录。两种启动方式的存档目录不同。`session_save_path` 可注入测试路径；测试只写 `native_*` 隔离文件和 `.tools` 地图测试存档。

当前没有正式魔力／怪物生成服务，因此仍使用原型测试事务和随机属性。7枚符文识别、占格、奇物、扣费去重、保存失败回退、待安置恢复可用；真实怪物模型、完整战斗特性、天气权重和正式战斗结算尚未接入。地图入口保留原有 FakeBattleAdapter，UI 不再执行原型的跳过战斗或测试地点领奖。原型参考画和纸雕贴图不代表最终美术。

宿主提供 `forest`、`desert` 或 `sand` 地形时映射至对应原型生态，其余为草原；完整 Hex、地图ID、地形与位置同时保存，未实现天气权重。正式数据接入应替换唯一 State 服务，不另建一套库存。保留“生成并保存成功 → 演出 → 展示同批实例”的顺序。

## 获取与修改记录

`node tools/Fetch-UI-Prototype.cjs` 可按清单重新获取原版；已存在文件必须与哈希相同，不覆盖本地修改。`tools/Import-UI-Prototype.cjs` 仅供首次迁移：运行副本已存在时拒绝覆盖。后续只编辑 `ui_module`，不重复运行导入覆盖当前接入代码。

迁移将所有 `res://` 引用加上 `ui_module/prototype/` 前缀，未复制上游 UID／导入缓存，使用宿主重新生成。运行副本额外改动：WorldView 增加宿主透明绘制开关；PrototypeState 隔离存档并持久化源地点；仓库换页使用即时返回，避免触发整块画板退出动画。完整上游交接资料在 `UI跳转原型/docs/`。

## 验证

测试脚本验证输出标记、失败数和脚本错误；不只依赖进程退出码。原型规则257项、布局436项、美术与动画43项，另有宿主集成测试。集成验证使用真实 GUI 输入点击书本、法阵、召唤和仓库，覆盖地图点击穿透、暂停／恢复、六种窗口尺寸、三层返回、焦点恢复、实例转移、改名、存档恢复和城镇 2.5D 往返。

运行输出为 `tests/integration_test_results.json` 和 `tests/suite_test_results.json`；`-Render` 还保存当前实现的4张截图至 `tests/screenshots/`。原版自带截图仅作为历史参考，验收以本机新测试为准。
