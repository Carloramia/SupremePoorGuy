# 输入、光标与摄像机

## 输入层次

[Input Map](../../../project.godot) 保存 Left、Right、Up、Down、Shift、Space、MouseLeft、QPressed、BPressed、CallConsole、EPressed 和数字槽位等映射。它们是否生效由当前应用阶段、界面和控制组件决定；存在映射不等于所有场景都会读取。

正式 GameRoot 默认以自由地形光标进入战场，不创建玩家 Controller。QPressed 在部署/战斗中切换系统鼠标，Space 在战斗中暂停/继续，Esc 打开设置。BPressed 工坊和 Q 接入轮盘在正式流程中不启用。

独立测试能力仍保留：[PlayerController3D](../../../Scripts/Player/PlayerController3D.gd) 可挂接物理角色或以自由光标初始化，[ControllerRadialMenu](../../../Scripts/Player/ControllerRadialMenu.gd) 处理接入/弹出菜单。需要测试它们时单独配置测试场景，不要重新把轮盘输入接到正式 GameRoot 的 Q 操作上。

## 控制对象查找

[PlayerControlContext](../../../Scripts/Player/PlayerControlContext.gd) 提供 `application()`、`controller()`、`level()`、`controlled_character()`、`character_of()` 和输入门控查询。角色身体通常在 `GeneratedParts` 下，装备又可能重挂到身体部件，所以 `get_parent()` 不能作为通用的角色查找方式。

没有玩家控制对象时，`trackmotion` 不会自动等价于“所有 NPC”；用 `tracknpcmotion on 名称` 选择 NPC。界面打开、布娃娃或角色停用时，输入与控制可能被主动拒绝。

## 摄像机

[DragCamera3D](../../../Scenes/Camera/DragCamera3D.tscn) 的 [脚本](../../../Scripts/Camera/DragCamera3D.gd) 使用右键拖拽环绕、滚轮缩放，`follow_target` 跟随目标全局位置，包括高度。`input_enabled`、`orbit_enabled`、`zoom_enabled` 可单独控制；目标释放后应清理引用。

跟随角色时优先设置 Follow Target，不通过把摄像机放到旋转中的物理 Part 下来实现。否则它会继承该 Part 的物理摆动和朝向，且可能影响其他组件查找同层 Camera 的规则。

## 地形光标与指示物

[TerrainCursor3D](../../../Scripts/Input/TerrainCursor3D.gd) 根据摄像机水平投影解释鼠标运动，并探测地面、显示目标吸附和部署状态。[TerrainArcIndicator3D](../../../Scripts/VFX/TerrainArcIndicator3D.gd) 显示角色周围的方向弧；二者复用 [TerrainProbe3D](../../../Scripts/Geometry/TerrainProbe3D.gd) 的地形查询。

自由鼠标、地形光标的逻辑位置、吸附目标和部署拖动是不同状态。新增 UI 应通过应用的输入门控与暂停原因接入，避免只显示面板而让背后的战斗继续接收鼠标。
