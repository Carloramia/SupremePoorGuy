# HornedBeast 独立平衡预设

Generate_HornedBeast 改用 HornedBeastCharacter3D（继承 GeneratedCreatureCharacter3D），其 NPC 子场景自动继承。StumpBeast 仍使用原脚本与资源。

- HornedBeastDensity.tres：脚密度 5.34（实际约 0.20）、SubTorso 密度 20.408（实际约 0.19）、Tail 密度 0.46875（实际约 0.45）。主 Torso 保留约 2.26。
- HornedBeastPhysics.tres：腿段最低质量 0.15，随 OverallScale 三次方变化，并遵守质量上限。腿根 X±12°、Y锁定、Z±45°；膝部 X/Y锁定、Z±50°；脚踝 X/Y锁定、Z±30°。这些角度相对于生成时的关节姿态。
- 行走控制器初始化腿链时会尊重这些专用限位，不再用通用 60° 覆盖。其他角色没有这项关节元数据，保留原逻辑。
- 踏地期间仅动作控制的前腿临时扩大 Z 活动范围至 60°（Action Z Limit），动作结束或取消时恢复行走限位；侧倾限制不放开。
- HornedBeastGenerator 的 Standing Layout：Balanced Standing Layout 默认开启，Standing Extension Ratio=0.82，Rear Foot X Offset=-0.8，Fore Foot X Offset=0.45。通过两段腿的解析布局对齐端点、保持脚底在 Y=0，不缩放或修改原模型。手动保存的布局仍优先。
- Leg Pair Width=0.5。关闭 Balanced Standing Layout 可恢复按原模型连接点摆放腿的方式。
- HornedBeastWalk.tres：Gallop关闭，至少保留2只脚，最多2只脚同时迈步；目标速度仍3、参考步频仍4。初始站立参考高度随重新生成计算，约3.58。

Grounded Standing Pose 位于 HornedBeastPhysics.tres：默认开启，Strength=120、Damping=16、Dead Zone=5°、Blend Time=0.2s、Maximum Acceleration=80、Maximum Torque=4。只控制接地且被固定、没有迈步或打滑的腿链的膝部与腿根；不直接控制脚踝。扭矩仅沿关节Z轴施加，子体和父体施加相反扭矩。离地、迈步、转向、倒地恢复、踏地攻击或冲锋期间退出；再次接地后渐入。扭矩上限随 OverallScale 的五次方缩放。trackmotion/tracknpcmotion 中的 grounded_standing_pose 列出每个参与关节的误差、渐入权重和实际提交扭矩。

TestLevel 中已清除 GenerateHornedBeastNPC 根节点的通用脚本覆写，使其真正继承 HornedBeastCharacter3D。重新挂载通用根脚本会绕过专用质量、限位和站姿功能。没有新增躯干高度补偿，避免与现有 SubTorso 支撑叠加。

运行中启用 tracknpcmotion on GenerateHornedBeastNPC，配合 trackcharge 检查部位和冲锋。没有修改全局恢复规则或其他生物的密度、关节、步态。

较高站姿：仅 HornedBeast 的移动组件覆盖 Sub Torso Weight Share=0.85、Height Gain=20、Damping Ratio=1.2、Auxiliary Support Weight Limit=0.95。沿用已有高度误差支撑和伸展限制，不新增支撑力来源。TestLevel 站立验证高度比约0.91，最大主动关节误差约16°；行走和踏地测试通过。

上部结构抬高：Standing Extension Ratio 从0.76改为0.82。保持脚位和模型尺寸，重新求解两段腿的连接姿态。OverallScale=1时后腿根上移约0.235、前腿根约0.188，躯干/头/尾约0.211；下腿连接线相对竖直方向的夹角后腿约76.5°变65.0°，前腿约66.0°变56.4°。已重新生成编辑器部件，NPC继承同样结构。

后腿后弯：Standing Layout 新增 Rear Knee Bends Backward，默认开启。选取保持腿根和脚位一致、膝部向-X移动的两段腿解；上半连接线相对竖直夹角约4.2°变35.4°，下半约65.0°变33.8°，前腿姿态保持不变。切换后重新生成部件和关节，站姿参考随新结构捕获。关闭开关可恢复膝部向前的解。
