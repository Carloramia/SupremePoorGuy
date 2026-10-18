# 装备、材料与武器工坊

## 物品和武器

[_SampleItem.tscn](../../../Scenes/Items/_SampleItem.tscn) 挂载 [SampleItem3D](../../../Scripts/Items/SampleItem3D.gd)，提供拾取标记、显示名、图标、视觉开关、附件位置和多个持握点。[_SampleWeapon.tscn](../../../Scenes/Items/_SampleWeapon.tscn) / [SampleWeapon3D](../../../Scripts/Items/SampleWeapon3D.gd) 在此基础上提供武器标签、攻击预设、阵营与命中去重。

`can_be_picked_up` 控制可拾取性；`item_image` 可指定图标，无图时由图像准备流程生成临时图像。Sprite 与 Mesh 的可见性独立设置。运行时更换 Human 手部视觉使用 [视觉状态切换](../../../Scripts/Creatures/BodyPartVisualSwitcher3D.gd) 与 [VisualStates](../../../Resources/Creatures/VisualStates)，不通过替换整个刚体完成。

## 物品栏和多点持握

[InventoryController3D](../../../Scripts/Items/InventoryController3D.gd) 默认 4 格，`EPressed` 拾取，`1`～`4` 选槽；满栏拒绝拾取，空槽卸下，再选同槽取消选择。拥有武器的角色与该武器之间的碰撞例外按持有关系处理。

当前默认刚性装备通过 `rigid_attachment_holder` 和复合刚体形状合并实现，不能继续按早期“Arm 和整把武器仅靠软 Joint 相连”的说明调节。辅助手由 [EquipmentMultiGrip3D](../../../Scripts/Items/EquipmentMultiGrip3D.gd) 追踪对应点位，Bow 的弦心可提供独立的移动持握目标。

编辑器中通过 Weapon Workshop 管理 `grip_point_count` 和 Marker3D。每点保存姿态、对应 Arm 的相对路径以及 [ItemGripSettings](../../../Scripts/Items/ItemGripSettings.gd)；`active_grip_point` 为零起始的主点索引。保存 Marker 后按插件按钮同步持握数据，不只在场景里移动 Marker。

[Spear1IdleGripPose](../../../Resources/Items/Spear1IdleGripPose.tres) 是双手常态姿态偏好；攻击过程会与常态持握控制协调。原说明见 [多持握点编辑](../../Combat/武器多持握点编辑说明_2026-10-15.txt)。

## 攻击类别

武器标签包括 Spear、Sword、Claw、Blunt、Shield、Bow、Arrow。近战标签映射到 [Weapons 预设](../../../Resources/Combat/Weapons)；`primary_attack_tag` 必须同时存在于 `weapon_tags`。`arm_attack_preset_override` 可覆盖默认映射。

每个 Arm 的 `arm_swing_bindings` 挂载参数资源并指定可响应的控制组；控制组输入在 LimbSwingController 上配置。一个 Arm 可以有多个 Binding。Bow 使用专用控制器，不把弓臂、弦心或箭矢当作普通近战摆臂处理。

## 材料与构建

[SampleMaterial](../../../Scripts/Materials/_SampleMaterial.gd) → [TestMaterial](../../../Scripts/Materials/TestMaterial.gd) → [TestMaterial.tres](../../../Resources/Materials/TestMaterial.tres)。材料统一保存 `material_id`、贴图、图标、`cell_size`、`mass_per_cell`、`collision_thickness`。武器网格、质量和碰撞应读取材料资源，不散落硬编码副本。

运行时工坊由 [WorkshopUIController](../../../Scripts/UI/WorkshopUIController.gd) 管理 [Playerworkshop](../../../Scenes/Workshop/Playerworkshop.tscn)、右侧材料面板与 BlurMask。画布支持中键拖动、滚轮缩放，以及 Q/E 按 30°/s 旋转网格和材料。连接点可以放在任意画布坐标，不吸附材料格；无连接点不允许构建。未放连接点时旋转以材料格位置平均值为中心。

构建数据经过 [WeaponLayout](../../../Scripts/Items/WeaponLayout.gd)、[WeaponCellBuilder](../../../Scripts/Items/WeaponCellBuilder.gd) 和 [Weapon_Test](../../../Scenes/Items/Weapon_Test.tscn) 形成实体。正式游戏已禁用 BPressed 工坊入口，保留组件与编辑器工作流；不要把资源存在理解成主流程已开放该功能。

编辑器武器工具位于 [weapon_workshop 插件](../../../addons/weapon_workshop)。诊断：`trackgrip on 名称`、`gripstates 名称`、`trackbow on 名称`、`trackswing`。
