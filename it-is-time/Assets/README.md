# 美术资源与引用链

本目录保存原图、拆分贴图、导入模型和制作元数据。可运行角色实际引用的是 Part 场景、Mesh 和配置资源，不能用“原图改了”推断后续所有派生文件会自动同步。

```text
Assets/2DResources/<类别>/... PNG
  → Assets/3DResources/Creatures/<类别>/... GLB / Texture / 包装场景
  → Resources/Meshes/<类别>/... .res 带厚度网格
  → Scenes/Creatures/Bodyparts/<类别>/... .tscn
  → GeneratedPartSceneRule.part_scene
  → Generator / 保存的 manual_layout
  → Generate_* / *_NPC / CreatureFactory
```

导航：[2D 素材分类](2DResources/README.md)、[3D 与模型清单](3DResources/README.md)、[烘焙网格](../Resources/Meshes/README.md)、[物理部件](../Scenes/Creatures/Bodyparts/README.md)。

音效单独放在 [Audio](Audio/README.md)，通过 Audio 配置资源和战斗事件引用。

## 修改一个部件时

1. 从生成角色的 `generated_part_key`、源场景或 `PartSceneRule` 找到实际引用，不按相似文件名猜测。
2. 查该物种 `Metadata/model_manifest.json`，定位 `source`、GLB、贴图、`volume_mesh`、`physical_scene` 与像素换算。不同批次字段名称可能不同。
3. 如果改图，明确是否保持画布、alpha 边界、关节孔和像素比例。改变这些会影响模型原点与连接位置。
4. 依对应物种工具重新生成模型、厚度 Mesh 或碰撞；不是每种工具都会同时做全部步骤。检查当前角色保存的内部快照是否会覆盖新 Part 数据。
5. 在 Godot 中导入、检查正反面/法线、厚度、连接 Marker 和碰撞，再生成并保存角色。

## 引用与重命名

- 使用 Godot 文件系统面板移动资源并保留 `.uid` 和导入配置；`.godot` 是本机缓存，不是源资产。
- 同时搜索 `res://` 字符串、JSON 元数据、烘焙脚本、SceneRule 和手动布局。UID 不会自动修复 JSON 或普通字符串。
- `Textures` 可能是贴图副本，GLB 还可能内嵌纹理，`.res` Mesh 的材质也可能引用一份纹理；改一处不等于全部更新。
- 凸包碰撞通常不会保留视觉孔洞。视觉孔洞对齐、Joint 锚点重合、碰撞形状匹配是三个检查项目。
- 历史 README 与清单记录特定制作批次；“尚未接入”的旧描述不代表当前角色接线，当前索引见 [角色 README](../Scenes/Creatures/Characters/README.md)。

运行时地图装饰使用独立的 `BattleEnvironmentPhysicalPart3D`，不是生物刚体 Part；说明见 [环境场景](../Scenes/README.md)。
