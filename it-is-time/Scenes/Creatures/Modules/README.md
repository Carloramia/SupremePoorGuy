# 可挂载模组模板

根模板 [_SampleModule](_SampleModule.tscn) 使用 [CreatureModule3D](../../../Scripts/Creatures/Modules/CreatureModule3D.gd)，包含 MountPoint、Parts、Joints、Visuals、Logic。Parts 和 Joints 默认可为空，不局限于肢体。

| 模板 | 用途 |
|---|---|
| [VisualModule](VisualModule.tscn) | 仅视觉挂件 |
| [SinglePartModule](SinglePartModule.tscn) | 单物理部件 |
| [TwoSegmentLegModule](TwoSegmentLegModule.tscn) | 两段腿链 |
| [ThreeSegmentLegModule](ThreeSegmentLegModule.tscn) | 三段腿链 |
| [TwoSegmentArmModule](TwoSegmentArmModule.tscn) | Arm 与 ArmLimb 结构 |

在角色 `module_attachments` 中添加 [CreatureModuleAttachment](../../../Scripts/Creatures/Modules/CreatureModuleAttachment.gd)，填唯一 instance_id、模板、基础身体的 Host Part Key、可选宿主 Marker 路径和相对变换。实际外部 Joint 由 ModuleJointSettings 配置；内部所有物理部件需与 Root Part 连通。

[Examples](../Characters/Examples) 提供装配实例。模组 PartKey 为 `Module/<InstanceId>/<原始部件名>`；不要把模组内部部件再作为其他模组的宿主键。

手工调整后用角色的布局捕获按钮保存。基础身体写入 manual_layout，模组安装项写入 captured_scene；“重新使用原始模组模板”清除此安装项快照，源模板本身不被覆盖。模组不会自动补 AI、攻击或输入组件。

详见 [完整说明](../../../Docs/Integration/CreatureModules_2026-10-18.txt)；验证 [运行时](../../../Tests/ValidateCreatureModules.gd)、[编辑器](../../../Tests/ValidateCreatureModulesEditor.gd)。
