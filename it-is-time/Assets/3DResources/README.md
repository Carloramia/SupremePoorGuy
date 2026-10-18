# 3D 素材与物理部件来源

`Creatures/<物种>` 中的模型和包装场景主要用于制作、预览与后续 Part 资源。它们通常不是最终装备或角色的刚体根节点。最终引用应沿 `physical_scene` 指向 [物理 Part](../../Scenes/Creatures/Bodyparts/README.md)。

## 模型清单

| 分类 | 模型、贴图、像素比例和 Part 路径 |
|---|---|
| StumpBeast | [model_manifest.json](Creatures/StumpBeast/Metadata/model_manifest.json) |
| HornedBeast | [model_manifest.json](Creatures/HornedBeast/Metadata/model_manifest.json)；[分段尾试验](Creatures/HornedBeast/SegmentedTail_v1/README.md) |
| Wolf | [model_manifest.json](Creatures/Wolf/Metadata/model_manifest.json)；[原制作说明](Creatures/Wolf/README.md) |
| Spider | [原模型清单](Creatures/Spider/Metadata/model_manifest.json)、[框架适配清单](Creatures/Spider/Metadata/frame_fitted_manifest.json) |
| Snake | [model_manifest.json](Creatures/Snake/Metadata/model_manifest.json) |
| Ratkin | [model_manifest.json](Creatures/Ratkin/Metadata/model_manifest.json) |
| Rats | [原模型清单](Creatures/Rats/Metadata/model_manifest.json)、[HindClaw 清单](Creatures/Rats/Metadata/hind_claw_model_manifest.json) |
| Human | [部件清单](Creatures/Human/Metadata/model_manifest.json)、[武器清单](Creatures/Human/Metadata/weapon_manifest.json) |
| Bird | [model_manifest.json](Creatures/Bird/Metadata/model_manifest.json) |

每种清单的字段随制作批次而异：常见包括 source、texture、glb、scene、volume_mesh、physical_scene、alpha_bounds、pivot_pixel 和像素单位比例。JointIn/JointOut 的初始估计未必等于后续手工校准锚点；以当前 Part 和角色快照为准。

## 带厚度纸片

[PaperVolumeMeshBuilder](../../Scripts/Geometry/PaperVolumeMeshBuilder.gd) 及 `Tools/Bake*Volumes.gd` 生成带正反面和侧面的 ArrayMesh，保存在 Resources/Meshes。直接替换 GLB 后，已经烘焙的 Mesh 和碰撞不会自动更新。生成角色的最终厚度还受 Generator 的 PartWidth 与 OverallScale 管理。

[Environment](Environment) 对应静态摆放物，[Maps](Maps) 为地图模型资源。UI 的字体、纸面和图标主要在 Modules/PaperUI，而不是全部集中在 Assets 中。

既有物种 README 是批次制作记录，里面的“未装配”“初始厚度”等描述不能替代当前生成器设置；角色接线见 [角色索引](../../Scenes/Creatures/Characters/README.md)。
