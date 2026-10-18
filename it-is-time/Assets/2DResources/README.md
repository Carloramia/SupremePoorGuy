# 2D 图片分类

| 目录 | 用途与对应后续资产 |
|---|---|
| [AIGenerated](AIGenerated) | AI 原始材料与未处理图；`Unprocessed` 不作为运行时主引用目录 |
| [StumpBeast](StumpBeast) | Source、Textures 和 Metadata；对应 StumpParts / PaperParts 与 StumpBeast 模型 |
| [HornedBeast](HornedBeast) | 兽身、角、尾部；SegmentedTail_v1 为独立分段尾试验 |
| [Wolf](Wolf) | Wolf 与 Wolf2 分件及修订；Backups 不作为当前素材判断依据 |
| [Spider](Spider) | Separated 原分件与 FrameFitted 框架适配版本，不能只按 UpperLeg 同名判断引用 |
| [Snake](Snake) | 多套 Snake 素材、头部和独立下颚 |
| [Ratkin](Ratkin) | Ratkin 人形鼠素材，与 Rats 不共用生成类别 |
| [Rats](Rats) | Rat_1 / Rat_2、修订图与 HindClaw 派生脚爪 |
| [Human](Human) | 多套 Humanoid、手部视觉状态、武器分件 |
| [Bird](Bird) | Originals、SourceCrops、Separated、RawEdits、Metadata，含 Bird_1～3 部位 |
| [Environment](Environment) | 地表装饰和场景摆放物，后续为静态环境资源 |
| [Samples](Samples) | WhiteCube 等通用占位贴图 |
| [SplitWorkplace](SplitWorkplace) | 拆图制作材料，不直接作为完整角色装配入口 |

图片通常位于 XY 平面，模型约定 +X 向前/右、+Y 向上、Z 为厚度方向。原图中的 Left/Right 可能指图片视角，而生成角色的 Leg_1/Leg_2 是框架键，两者不保证一一按名称相等。

制作前先查 [模型清单](../3DResources/README.md) 的源图记录。不要覆盖唯一原图；修补、拉长、无牙下颚、框架适配和手部握持状态应保留可追溯的派生版本，并记录后续引用。
