# Wolf_2 部件资源

Wolf_2 与原 Wolf 共享资源根目录；新资源使用 `wolf2_` / `Wolf2` 前缀，不替换原 Wolf 部件或 WolfGenerator 的引用。

## 内容

共 34 套透明 PNG、GLB、模型包装场景、带厚度网格和 PhysicalPart 场景：

- 2 个头部候选、1 个躯干、1 个尾巴。
- 4 个上腿、6 个下腿、6 个脚掌（包括替换姿态候选）。
- 14 个耳、眼、鬃毛、纹饰和铆钉等装饰候选。

图片使用 AI 提取并补齐被遮挡区域，保留纸片拼贴风格；补画内容和比例属于重建估计，并非原图的无损裁切。原始整图保存在 `Assets/2DResources/Wolf/Wolf_2.png`，Unprocessed 原文件保留。

## 目录

- `Assets/2DResources/Wolf/Separated/{Base,Limbs,Feet,Attachments}`：透明图片。
- `Assets/2DResources/Wolf/Separated/Wolf2Preview.html`：全部图片预览。
- `Assets/3DResources/Creatures/Wolf/{Models,Textures,Scenes}`：GLB、纹理与包装场景，按 Head、Torso、Tail、Legs、Decorations 分类。
- `Resources/Meshes/Wolf`：正背面使用同一图片的轮廓厚度网格。
- `Scenes/Creatures/Bodyparts/Wolf`：继承物理部件基类的场景。
- `Assets/3DResources/Creatures/Wolf/Previews/Wolf2PartsPreview.tscn`：全部新物理部件预览。

物理部件默认厚度 0.08，采用独立凸包碰撞；凸包会填平凹陷。物理场景内部模型、碰撞体及连接点统一朝 +X，原始 PNG 和 GLB 保持图片方向。上腿/下腿使用 LegLimb，前脚使用 ForeLeg，后脚及替换脚使用 Leg；头、躯干、尾巴分别使用 Head、Torso、Tail，装饰不添加身体标签。

JointIn / JointOut 和可见尺寸是装配初值，记录在 `Metadata/build_settings.json`；正式装配生物时应根据接缝调整。本次不创建新的 Wolf_2 角色或自动替换已有角色引用。

## 复现与检查

完整图像提示词、来源及 AI 输出路径：`Assets/2DResources/Wolf/Separated/wolf2_generation_prompts.json`。透明度、轮廓范围和 PNG SHA256：同目录 `wolf2_asset_manifest.json`。

运行顺序：`Tools/prepare_wolf2_resources.py`、`Tools/build_models.py`、Godot 导入、`res://Tools/BakeWolfVolumes.gd -- --wolf2-only`、`Tools/build_models.py --physical`、`res://Tools/OrientWolfParts.gd`。

生成脚本保留已有输出，避免覆盖手工修改；重新生成指定资源前应备份对应输出。`--wolf2-only` 烘焙会更新全部 Wolf2 网格。

检查脚本：`res://Tests/ValidateWolfParts3D.gd`（原 Wolf 与 Wolf2 共 52 个部件）、`res://Tests/ValidateWolfCreature.gd`（原 Wolf 装配回归）。旧资源哈希快照：`Metadata/pre_wolf2_hashes.json`。

本次两项检查均通过，111 个旧资源哈希一致。日志保存为 `D:/GameJamWorkspace/wolf2_validation.log`、`D:/GameJamWorkspace/wolf2_creature_regression.log`。无界面 Godot 仍报告系统证书读取错误，部件预览测试退出仍有资源清理警告；这些进程级提示未在本次资源任务中修复。
