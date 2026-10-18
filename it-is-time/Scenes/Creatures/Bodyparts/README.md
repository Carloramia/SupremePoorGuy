# 物理身体部件

基类场景为 [_PhysicalSampleBodyParts.tscn](_PhysicalSampleBodyParts.tscn)，脚本 [PhysicalBodyPart3D](../../../Scripts/Creatures/PhysicalBodyParts.gd) 继承 RigidBody3D。Part 提供身体标签、HP/护甲、Broken、视觉、碰撞、关节 Marker、视觉状态和 Arm 挥舞绑定。

| 资源组 | 目录与说明 |
|---|---|
| 默认几何体 | [PhysicalTestCreatureParts](PhysicalTestCreatureParts)；无自定义规则时可作为生成 fallback |
| StumpBeast | [StumpParts](StumpParts)、[PaperParts](PaperParts)；生成器可能混用两组，不存在统一 StumpBeast Part 根目录 |
| HornedBeast | [HornedBeast](HornedBeast)，含尾和角及独立分段尾试验 |
| Wolf | [Wolf](Wolf)；框架、内部模型及碰撞快照可能有单独版本 |
| Spider | [Spider](Spider)；含原素材与校准/框架适配版本 |
| Snake | [Snake](Snake)；Torso、Head 与 LowerJaw 等 |
| Human | [Human](Human)；多套预设与可替换手部视觉 |
| Ratkin / Rats | [Ratkin](Ratkin) 与 [Rats](Rats)；名称和生成器不同，不可混同 |
| Bird | [Bird](Bird)；多套头、爪、翼与羽毛资源 |

## 修改注意

- BOX_FIT 使用参数同步 Sprite、Mesh 与框形碰撞；CUSTOM_MODEL 保留自定义模型与作者设置，不能假定两者采用同一套尺寸算法。
- 生成角色的纸片厚度由 PartWidth × OverallScale 设定，部件碰撞 Z 深度使用视觉厚度的 2 倍机制。
- `JointIn/JointOut` 是连接参考，不是自动从图片圆孔识别的真实关节。生成器可用规则、蓝图或手动快照重设最终锚点。
- 修改碰撞形状前，注意 Resource 可能共享；只改变某角色的碰撞时先使资源独立并捕获该角色布局。
- 修改枚举时保持旧整数索引；`Neck` 等生成类型不一定是 BodyPartTag。
- Part 的 `visual_states` 只替换视觉，适用于 Human 松手/握持状态，不应改变刚体拓扑与关节。

完整引用链在 [模型清单](../../../Assets/3DResources/README.md)；角色映射在 Generator 的 PartSceneRule；角色当前内部覆盖在 manual_layout / InternalSnapshot。三个位置都检查后再决定修改源 Part 还是角色实例。
