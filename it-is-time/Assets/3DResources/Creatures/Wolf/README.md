# Wolf 资源

下颚增补：修整后的无牙齿、无红色尖端图片现已覆盖 `Base/04_lower_jaw.png`；原有带牙齿版本备份为 `Base/04_lower_jaw_with_teeth_original.png`。独立下颚模型为 `Models/Head/LowerJaw.glb`，物理部件为 `Scenes/Creatures/Bodyparts/Wolf/Head/LowerJaw.tscn`，增加 HeadSkull 后总计 18 套模型和物理部件。下颚初始宽度 2.5、厚度 0.08、质量 0.12；JointIn 位于后端，JointOut 位于前端，仍为可调的初始估计。下颚暂不设 Head 标签，避免作为额外存活头部参与死亡判定；现已装配到 Generate_Wolf 的 Head 下颚连接点。

沿用 HornedBeast 的纸片体块流程。原始图完整保留在 `Assets/2DResources/AIGenerated/Unprocessed/Wolf.png`，分类目录另存一份到 `Assets/2DResources/Wolf/Wolf.png`。

## 内容与目录

- 16 张独立透明 PNG：躯干、头部、尾部、4 套上腿/下腿/脚掌、1 个可复用铆钉。通过内置 image_gen 提取并补全遮挡；不是逐像素无损裁切。
- `Assets/2DResources/Wolf/Separated`：Base、Limbs、Feet、Attachments；含清单、提示词记录及 Preview.html。
- `Assets/3DResources/Creatures/Wolf/Models`：18 个 GLB，含 JointIn、JointOut 初始标记。
- `Textures`：模型贴图副本；烘焙网格引用分类后的原始独立 PNG。
- `Scenes`：冻结的独立模型预览包装场景。
- `Resources/Meshes/Wolf`：正面、背面、侧面三表面的烘焙 ArrayMesh。
- `Scenes/Creatures/Bodyparts/Wolf`：继承 `_PhysicalSampleBodyParts.tscn` 的 18 个物理部件场景。
- `Previews/WolfPartsPreview.tscn`：物理部件静态陈列场景，可直接运行。

## 坐标与调整

图片位于 XY 平面，厚度沿 Z。正面 +Z，图像右方 +X、上方 +Y。保留原图朝左（-X）的方向，装入以 +X 为前的生成器时应统一处理朝向。

初始厚度统一 0.08，通过部件 Inspector 的 Paper Volume Thickness 调整；生成器使用这些部件时仍按项目既有 PartWidth 机制处理。调整厚度不改变 XY 外形。

上腿、下腿标记 LegLimb；前两套脚掌标记 ForeLeg，后两套脚掌标记 Leg；头、躯干、尾巴分别使用 Head、Torso、Tail 标签。铆钉没有身体标签，仅作装饰候选，装配时通常不需要其独立物理模拟。

比例与 JointIn/JointOut 是根据图像设定的初始估计，可在部件场景中手动调整，已接入 WolfGenerator，并完成基础装配、站立、行走与 NPC 攻击检查。凸包碰撞是外形近似，会填平凹陷与关节孔，不代表逐像素碰撞。

## 重建

1. 修改 `Metadata/build_settings.json` 中的尺寸、连接标记、质量或标签。
2. 运行 `Tools/build_models.py`，再让 Godot 导入新 GLB。
3. Godot `--headless --path . --script res://Tools/BakeWolfVolumes.gd`。
4. 运行 `Tools/build_models.py --physical`。
5. Godot `--headless --path . --script res://Tests/ValidateWolfParts3D.gd`。

生成脚本保留已有 GLB、包装场景和物理场景，避免覆盖手工编辑；调整设置后若要重建对应输出，应先另存手工修改版本。烘焙网格会更新。

## 本次检查

16 个部件全部通过 ValidateWolfParts3D 的继承、材质、侧面网格、标签、连接标记、独立碰撞厚度与预览场景断言。测试日志：`D:/GameJamWorkspace/wolf_validation.log`。无界面进程启动有系统证书存储读取错误，退出有 ObjectDB/RID 资源清理警告；断言通过不代表这些进程级警告已解决。角色设置与验证说明见 Scenes/Creatures/Characters/Wolf_README.md。

物理部件内部模型、碰撞体和连接标记已经旋转为 +X 前方；原始图片与 GLB 仍保持原始方向。重新创建物理场景后可运行 Tools/OrientWolfParts.gd 统一方向。

## Wolf_2 扩展资源

新增 Wolf_2 的 34 套资源与原 Wolf 共用上述目录，以 wolf2_ / Wolf2 前缀区分。内容、预览与复现方式见 [Wolf2_README.md](Wolf2_README.md)。目前共 52 套部件；新旧部件检查及原 Wolf 装配回归均通过，111 个原有 Wolf 资源哈希未改变。新资源尚未替换 WolfGenerator 的引用。

