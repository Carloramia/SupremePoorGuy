# Snake 素材与物理部件

来源：`Assets/2DResources/AIGenerated/Unprocessed/Snake/Snake_1.png`、`Snake_2.png`、`Snake_3.png`。原文件未修改；分类后的原图副本在 `Assets/2DResources/Snake`。

共 32 套资源，以 Snake1、Snake2、Snake3 编号区分。前两套原有20件保留；Snake3新增12件：完整张口头部、独立上颚、独立下颚、舌头、两个身体节段、尾部、四个足部及一个可复用铆钉。重复出现的同款铆钉只制作一个。

## 目录

| 内容 | 路径 |
| --- | --- |
| 独立透明 PNG | `Assets/2DResources/Snake/Separated/{Base,Feet,Attachments}` |
| 二维总览 | `Assets/2DResources/Snake/Separated/ContactSheet.jpg`、`Preview.html` |
| 来源、哈希和分类清单 | `Assets/2DResources/Snake/Separated/asset_manifest.json` |
| AI 提示词记录 | `Assets/2DResources/Snake/Separated/imagegen_prompts.json` |
| 基础 GLB、贴图副本 | `Assets/3DResources/Creatures/Snake/{Models,Textures}` |
| 带厚度独立模型场景 | `Assets/3DResources/Creatures/Snake/Scenes` |
| 三表面烘焙网格 | `Resources/Meshes/Snake` |
| 继承的物理部件 | `Scenes/Creatures/Bodyparts/Snake/{Head,Neck,Torso,Tail,Feet,Mouth,Decorations}` |
| 模型与尺寸清单 | `Assets/3DResources/Creatures/Snake/Metadata/{build_settings,model_manifest}.json` |
| Godot 全部32件陈列预览 | `Assets/3DResources/Creatures/Snake/Previews/SnakeAllPartsPreview.tscn` |

另有 `Snake1PartsPreview.tscn`、`Snake2PartsPreview.tscn`、`Snake3PartsPreview.tscn` 分别陈列三套资源。原有 `SnakePartsPreview.tscn` 保留前20件布局。预览中的部件被冻结，关闭碰撞；正式物理部件场景保持可模拟状态。Snake3二维总览为 `Separated/Snake3Preview.jpg`、`Snake3Preview.html`，共享 `ContactSheet.jpg`、`Preview.html` 已包含全部32件。

## 制作与坐标

使用内置 image_gen 逐件提取并补全遮挡，然后按用户确认的方式使用像素脚本清理透明背景与边缘杂色。清理过程只调整 Alpha 和画布留白，不改变已生成部件的内部 RGB 纹理。AI 补全部分存在重绘，并非原图的逐像素无损裁切。

图片右方对应 +X，上方对应 +Y，正面为 +Z，厚度沿局部 Z。保留两套原素材的朝向。世界尺寸以原图部件的估计宽度乘以 0.005 为初始参考，保留各自长宽比；不强制统一连接孔的直径。

GLB 是用于烘焙的基础贴图平面。实际带厚度的模型使用 `Scenes` 中的 `.tscn` 或对应 PhysicalPart；其正面、背面和侧面分别为三个网格表面。正反面共用相同 PNG 和 UV，侧面沿透明轮廓及内部孔洞生成。默认厚度 0.08，可通过物理部件的 `Paper Volume Thickness` 调整，XY 外形不随厚度改变。后续接入生成器时仍可使用已有 PartWidth 厚度控制机制。

## 物理部件

全部继承 `_PhysicalSampleBodyParts.tscn`，使用 CUSTOM_MODEL 模式，关闭默认 Sprite，显示带厚度模型，并提供可编辑的质量、碰撞体、JointIn 和 JointOut。

Head、Torso、Tail、足部分别使用已有 Head、Torso、Tail、Leg 标签。项目当前没有独立 Neck、Jaw、Tongue 标签，颈部、下颚、舌头保持空标签，用 `metadata/anatomical_role` 记录类别；铆钉也保持空标签，作为装饰候选使用。Snake3下颚和舌头位于 Mouth 分类，上颚作为可独立装配的 Head 候选。

JointIn/JointOut 为根据连接孔和部件端部设置的初始估计，尚未进行整只生物的关节装配。碰撞体采用与现有素材相同的凸包近似，会填平凹陷与关节孔；不等同于视觉轮廓的逐像素碰撞。Snake3同时提供完整头部和独立上颚/下颚/舌头，便于后续制作开合嘴；本次没有加入开合关节或攻击控制，也没有替换 SnakeGenerator 当前的 Snake2 部件引用。

## 重建与检查

按项目根目录运行：

1. Python 执行 `Assets/3DResources/Creatures/Snake/Tools/build_models.py`，生成基础 GLB 和贴图副本；已有 GLB 保留。
2. Godot 导入资源后，执行 `--headless --path . --script res://Tools/BakeSnakeVolumes.gd`，烘焙网格。
3. Python 执行同一构建脚本并加 `--physical`，创建物理部件与陈列预览；已有物理部件和预览保留，独立模型包装场景按清单重新输出。
4. Godot 执行 `--headless --path . --script res://Tests/ValidateSnakeParts3D.gd`。

仅追加/重建 Snake3 时，为两次Python调用加 `--prefix=snake3_`；Godot烘焙调用末尾加 `-- --prefix=snake3_`。这会跳过Snake1、Snake2的模型、包装场景和烘焙网格，仍更新共享清单。已有物理场景保留，避免覆盖手动编辑。

如需按新的 XY 尺寸重建已有 GLB，应先备份手动调整的场景和模型，再明确替换对应的生成输出。无需重新生成 AI 图片。

2026-10-12：20/20 物理部件检查通过，覆盖资源加载、继承与标签、正反面源贴图、三表面绕序、连接标记、碰撞外形尺寸、实例间碰撞资源独立、仅修改 Z 厚度及三份陈列预览。二维总览已检查。日志位于 `D:/GameJamWorkspace/Reports/SnakeAssets_2026-10-12/validation.log`。

2026-10-12追加Snake3：32/32物理部件检查通过，新增12件及两份3D陈列场景均可加载。Snake3二维透明图总览已检查，中段误带前段的首轮提取已重做。原始3张源图、原有20件独立PNG/GLB/包装场景/物理部件/烘焙网格及原有3D陈列预览均通过哈希核对，保持不变；仅共享索引、构建清单、说明和构建工具更新。AI提示词记录已追加到共享imagegen_prompts.json。日志和哈希审计在 `D:/GameJamWorkspace/Reports/Snake3Assets_2026-10-12`。

无界面进程仍输出系统证书存储读取错误；编辑器导入进程另有全局编辑器设置保存权限提示和编辑器预览中的 DamageService 警告。本次没有修改这些已有环境或公共脚本。尚未进行完整生物装配、行走或攻击测试。
