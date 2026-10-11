# Wolf 生物

`WolfGenerator.tscn` 位于 `Scenes/Creatures/Generators`，继承 BeastGenerator，使用独立的 `Resources/Generators/WolfGeneratorDefaults.tres`。保存默认值不会覆盖 Beast、Bird 或其他生成器。

`Generate_Wolf.tscn` 继承 `_BaseGeneratedCreature.tscn`，默认四足结构共 22 个物理部件、21 个关节：Torso、4 个 SubTorso 支撑点、4 个脚掌、10 个 LegLimb、Head、独立 LowerJaw 和 Tail。前肢为两段肢体加脚掌，后肢为三段肢体加脚掌。前脚标记 ForeLeg，后脚标记 Leg。下颚没有 Head 标签，通过固定连接跟随头部。

后肢从躯干到脚依次为 Limb_3（Rear Upper Scenes）、Limb_2（Rear Middle Scenes）、Limb_1（Rear Lower Scenes）和脚掌。Leg_1_Limb_2 引用 Hind_2/Wolf2UpperLeg.tscn（08_wolf2_hind2_upper），Leg_2_Limb_2 引用 Hind_1/Wolf2UpperLeg.tscn（07_wolf2_hind1_upper）；可在 WolfGenerator 的 Wolf Part Scenes 中独立替换。初始生成时按连接点长度折叠三段后肢，保留素材原生尺寸并使脚掌接地，模拟中通过独立关节活动。

`Generate_Wolf_NPC.tscn` 继承 Generate_Wolf，挂载已有 NPCStateMachine3D，阵营默认 1，支持敌对目标搜索、导航、转向、友军避让和前腿踏地攻击。放到具有地形碰撞和可用导航网格的关卡中运行；玩家控制版本可接入现有 Controller。未给 Wolf 添加新的撕咬动作。

## 调整位置

### SubTorso 位置基准（2026-10-09，用户确认）

后续调整 Generate_Wolf 时，以以下当前保存的位置作为正确的 SubTorso 位置基准。坐标为 GeneratedParts 下的局部坐标，记录时整体缩放为 1；四个部件的旋转基底均为单位基底。Generate_Wolf_NPC 同样采用此基准。

| 部件 | X | Y | Z |
| --- | ---: | ---: | ---: |
| SubTorso_Leg_1 | -2.3858314 | 3.071241 | -0.08 |
| SubTorso_Leg_2 | -2.3873403 | 3.1148262 | 0.08 |
| SubTorso_ForeLeg_1 | 1.5291088 | 3.4680896 | -0.08 |
| SubTorso_ForeLeg_2 | 1.3200366 | 3.3942413 | 0.08 |

这些位置保留当前左右肢体之间的差异，不要根据旧程序化生成参数重新对称化或恢复旧腿根位置。除非用户明确要求调整 SubTorso，否则修改其他部件时应保持此基准，并同步维护已保存的手动布局、关节锚点和碰撞体。若用户要求改变整体缩放或整体平移，则按整体变换保持该相对布局。此记录是位置基准，不代表其他步态或物理稳定性问题已解决。

`Rear Middle Size Scale = 0.5` 将 Leg_1_Limb_2 与 Leg_2_Limb_2 的模型、碰撞轮廓和连接点在 XY 平面缩小为源部件的 1/2；Z 厚度仍由 Part Width 统一控制。源图片、GLB 和物理部件资源本身不修改。前肢改为直接使用拉长后的素材原生尺寸，不再随后肢尺寸额外放大。

初始姿态参考 `Assets/2DResources/AIGenerated/Unprocessed/Wolf_Reference.png`：只采用白色接地前足与最右侧接地前足，忽略悬空的黑色第三前足。保留四足结构、三段后肢和修改图片前的前肢连接总长。Standing Extension Ratio 调为 0.65 以压低躯干；前足相对肩根前移比例为 0.05 / 0.38，后足相对髋根为 -0.48 / 0.02（按各自肢体连接总长计算，不含脚掌）。Torso / Head / Tail Pitch Degrees 分别为 4 / -18 / 12，均绕局部 Z 轴，角色正面仍为 +X。两个后肢通过三段折叠求解匹配接地位置。以上可在 Wolf Layout 中调整；这是姿态近似，原素材轮廓和比例并非参考图的精确复刻。

- 框架：四张前肢上、下段图片仅拉长中段，两端连接区域保留原像素；保持原来的世界单位/像素比例。前肢以原生 XY 尺寸生成，不再使用 Forelimb Length Ratio 额外放大，脚掌不修改。两条前肢的连接总长约为 3.521 / 4.055。内部使用 FIT_UNIFORM，以保持 Overall Scale 对模型和连接位置同步缩放的兼容性；Part Width 控制 Z 厚度。左右间距、腿根 X 位置、站立伸展比例和连接偏移仍然有效。单独改变某部件大小时，可在 Part Scene Rules 中指定 Size Multiplier。
- 部件：Wolf Part Scenes 与通用 Part Scene Rules；更换素材时需保留有效的 JointIn/JointOut。初始素材连接点仍可按视觉接缝进一步校准。
- 行走：`Resources/Movement/WolfWalk.tres`，初始目标速度 2.0，慢速/快速暂共用此预设；目标速度是控制目标，不保证物理实际速度恒定达到它。
- 质量：`Resources/Creatures/WolfDensity.tres`。
- 攻击：`Resources/Actions/WolfForeLegStomp.tres`，使用已有踏地冲击波伤害系统。
- AI：`Resources/AI/WolfAI.tres`；阵营在 NPC 根节点修改。

物理场景内部的模型、碰撞体和连接点已统一朝 +X；RigidBody 本身保留正常局部坐标，避免控制器反向判定。原始图片、GLB 和烘焙网格保留原始方向。若从构建脚本新建物理部件，导入后运行 `Tools/OrientWolfParts.gd`；该工具带有标记，重复运行不会再次翻转。

场景已保存可在编辑器中查看的冻结部件预览；运行时根据当前生成器参数重新生成。更新预览可使用根节点的“生成框架与物理角色”。

## 验证

### 四肢视觉孔洞关节标定（2026-10-09）

Generate_Wolf 和 Generate_Wolf_NPC 的四肢共 14 个关节已根据当前 PaperVolume 贴图封闭孔洞中心重设锚点。沿脚到腿根逐级配对孔洞，每段 Limb 的两端分别使用不同孔洞；双方孔洞存在间距时采用两孔中心的中点，腿根使用上段 Limb 的根部孔心。保持原关节 Z 平面及旋转基底，保留所有部件（包括 SubTorso）、视觉模型和碰撞体的当前姿态与形状。Torso/SubTorso 固定连接及头、下颚、尾部关节未改动。

连接 Marker、关节双方局部锚点和 manual_layout.blueprint.connections 同步保存。旧快照中脚部碰撞体变换与当前场景不同，已同步快照为当前碰撞状态，避免重新生成恢复旧变换；未移动或改变当前碰撞体。当前 ForeLeg_1 两处配对孔洞仍分别存在约 0.158 和 0.262 的视觉间距，锚点修正不消除模型自身的接口间距。

工作区 wolf_visual_joint_repair_validation.log 验证已保存及重复生成两次后的所有部件根姿态、网格变换、碰撞变换/凸包点和修复锚点；wolf_visual_joint_repair_standing.log 基础站立和行走通过。wolf_visual_joint_repair_attack.log 的 NPC 自动攻击测试停在 out_of_range，完整自动攻击回归未通过，不能沿用上一次攻击通过结论。修改前两场景备份在 D:/GameJamWorkspace/WolfBeforeVisualJointRepair。

### Wolf 独立物理预设（2026-10-09）

WolfCharacter3D 继承 GeneratedCreatureCharacter3D，使用独立的 Resources/Creatures/WolfPhysics.tres；不修改 HornedBeast、StumpBeast 或通用移动脚本。Wolf NPC 继承相同设置。保存预览初始化和重新生成均应用预设，不需要先重新生成才生效。

预设保持髋、膝 Z 轴 ±60°，将髋 X 轴限制为 ±12°，脚踝 X/Y 锁死、Z 轴 ±45°。踏地期间参与动作的关节 Z 范围临时扩大到至少 ±75°，结束后恢复。开启脚部关节 Y 锁定和动作朝向维持；后者继续通过接地腿牵引实现，不直接锁死躯干朝向。

每个 SubTorso 质量至少为 0.15 × OverallScale³，并且不低于所有 Torso 总质量的 10%，仍受角色质量上限约束；不改变它们的位置、视觉或碰撞形状。支撑阻尼比调整为 1.2。接地站姿维持参考 HornedBeast，遍历整个腿链以适配三段后肢和两段前肢，只对脚踝之外的膝和髋施加等大反向力矩；要求接地、已吸附、非迈步、非打滑。转向、动作和倒地恢复期间停止此维持。目标速度保持 2.0。

Tests/ValidateWolfPhysics.gd 检查已保存和重复生成的 Wolf/NPC、SubTorso 基准和所有部件根姿态、关节限位、动作限位恢复及倒地恢复排除。trackmotion 的 grounded_standing_pose 字段可输出站姿维持关节的角误差、渐入比例和实际扭矩。

本次检查以执行前场景文件的实际姿态为准，未回写位置；当前 Generate_Wolf 的 SubTorso 坐标与上方早先记录的基准不同，而 NPC 仍保留早先基准。两者均验证重复生成后根姿态不变。基础落地行走、NPC 平面导航和自主踏地攻击测试通过，踏地双脚均生成冲击波；长期多人战斗与复杂地形尚未验证。工作区日志：wolf_physics_validation.log、wolf_physics_standing.log、wolf_physics_npc_navigation.log、wolf_physics_attack.log。

`Tests/ValidateWolfCreature.gd` 检查重复生成、1/2 倍缩放、厚度、落地高度、连接锚点、内部碰撞例外和 NPC 接线。

`Tests/SmokeWolfStanding.gd` 检查静止与玩家移动；`Tests/SmokeWolfNPCNavigation.gd` 检查平面导航和移动；`Tests/ValidateWolfNPC.gd` 检查自主索敌、发起踏地、动作完成和两次脚部冲击波。完整关卡中的多人战斗、转向和复杂地形仍需实际测试。

Wolf_Reference 姿态调整后的检查：结构、连接点、1/2 倍缩放与基础站立行走通过（wolf_reference_structure.log、wolf_reference_standing_adjusted.log）。行走测试仍有 Z 向漂移；NPC 踏地回归只有一只前脚生成冲击波，另一只脚出现 landing_timeout（wolf_reference_npc_adjusted.log），该攻击限制尚未修复。踏地动作数值保持调整前设置。

## 前肢中段拉长资源

### 手动布局内部快照

当前 Wolf 的 22 个碰撞体已按现有 PaperVolume 侧面轮廓重新生成独立凸包，变换烘焙到碰撞点中，保留模型、部件和关节位置。碰撞体不包含透明留白，但凸包仍覆盖凹陷/孔洞。更新后的碰撞体已写入内部快照，Wolf NPC 继承使用；原始 Part 资源不修改。Tests/ValidateWolfCollisionAlignment.gd 检查当前和重新生成后的全部碰撞边界及视觉姿态。调整前备份：D:/GameJamWorkspace/Generate_Wolf_before_visual_collision_alignment.tscn。

“将当前部件姿态写入生成器”现在同时记录部件内部模型、连接标记的变换，以及独立碰撞形状。尺寸从当前碰撞范围采集，不再只读取旧框架尺寸元数据。新快照在关节创建、质量计算和控制器初始化前还原；整体缩放只应用一次。原有不带快照的布局继续按旧逻辑读取，程序化生成不变。

调整后执行该按钮并保存角色场景。Generate_Wolf 当前已保存新快照，连续重新生成两次，22 个部件根节点及内部节点变换无差异。该快照保存实例调整，不修改源 Part、PNG 或模型文件；单独改动视觉仍可能保留视觉与碰撞体的不一致。替换源 Part 或改变节点结构后，无法匹配的快照会警告并跳过，需重新采集。网格使用现有独立资源的路径引用，避免重复嵌入图片；此功能不用于保存网格顶点编辑或任意材质修改。

验证：Tests/ValidateManualPartSnapshot.gd 覆盖内部变换、碰撞点、资源保存/读取、重复生成、整体缩放及再次采集、碰撞资源独立性和源资源不匹配回退。Tests/ValidateCreatureManualLayout.gd 覆盖 StumpBeast、Bird、Beast 的旧布局与程序化生成回退。诊断日志位于工作区的 wolf_saved_pose_check.log、wolf_internal_snapshot_test.log 和 manual_snapshot_validation.log。

`Assets/3DResources/Creatures/Wolf/Tools/elongate_forelimbs.py` 从原图备份重建四张 PNG，不会叠加拉长；自检逐像素验证两端保护区域。`Metadata/forelimb_elongation.json` 保存像素位移、世界像素比例和哈希。原图与旧构建参数备份在 `Assets/2DResources/Wolf/Backups/ForelimbsBeforeElongation_20261009`，旧模型和物理部件备份在对应 3DResources/Wolf/Backups 目录。备份目录由 .gdignore 排除导入。

已更新 GLB、烘焙体积网格、碰撞体、JointIn/JointOut 及 Generate_Wolf 冻结预览。Wolf NPC 通过继承使用更新后的部件。其他直接引用这四个前肢资源的场景也会使用新素材。

本次检查日志：wolf_forelimb_structure.log、wolf_forelimb_parts.log、wolf_forelimb_standing.log。原生尺寸与 1/2 倍整体缩放、连接锚点、52 个物理资源、基础站立行走均通过。基础行走测试位移约 (3.114, 0.182, 0.014)，此结果不代表复杂地形和战斗回归；NPC 踏地双脚落地问题未在此次重测。Godot 无界面检查仍有系统证书读取及资源测试退出释放警告。
