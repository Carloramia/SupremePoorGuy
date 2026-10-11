# Spider 纸片部件资源

本批资源由 `Assets/2DResources/AIGenerated/Unprocessed/Spider/Spider.png` 经内置 imagegen 逐部件提取、补全遮挡轮廓生成。原始图片保留；AI 重建并非逐像素裁切，局部纹理可能略有变化。

共 22 个独立部件：后躯干、前躯干、头部、左右口器、八条腿各自的上段及下段、一个可复用铆钉。Left/Right 是原始素材图的左右；编号 1 从最外侧开始，4 最靠近中间。

## 目录

- `Assets/2DResources/Spider/Separated`：透明 PNG、提取清单、`Preview.html` 图集。
- `Assets/3DResources/Creatures/Spider/Models`：内嵌贴图的 GLB 平面模型。
- 同目录 `Textures`：对应贴图副本；`Scenes`：带碰撞体的冻结预览包装场景。
- `Resources/Meshes/Spider`：带原贴图正反面及实体侧面的 ArrayMesh。
- `Scenes/Creatures/Bodyparts/Spider`：继承 `_PhysicalSampleBodyParts.tscn` 的物理部件。
- `Previews/SpiderPartsPreview.tscn`：所有物理部件的 Godot 展示场景。
- `Metadata/build_settings.json`：模型尺寸、初始连接点、质量、标签、厚度。
- `Metadata/model_manifest.json`：PNG → GLB → 厚度网格 → Part 路径和像素换算关系。
- `Metadata/final_extraction.json`：最终图像来源及实际使用的提取/修正提示词。

## 物理和坐标

图像平面为 XY，+X 向右、+Y 向上、+Z 为正面。厚度沿 Z，初始为 0.08，通过 Part 的 `paper_volume_thickness` 调整。正反面复用同一贴图；碰撞体按 alpha 轮廓的凸包生成，因此孔洞和凹口不作为空洞碰撞处理。

躯干使用 Torso 标签、头部使用 Head、上腿使用 LegLimb、下腿使用 Leg。口器和铆钉暂不赋予功能标签，口器不会自动造成武器伤害。各 Part 均具备 JointIn/JointOut，连接点为初始估计，可在编辑器调整；尚未装配或替换现有 SpiderGenerator/Generate_Spider 的部件。

## 重建顺序

在项目根目录使用具备 Pillow 的 Python，依次执行：

1. `python Assets/3DResources/Creatures/Spider/Tools/prepare_assets.py`
2. `python Assets/3DResources/Creatures/Spider/Tools/build_models.py`
3. Godot 导入资源。
4. `godot --headless --path . --script res://Tools/BakeSpiderVolumes.gd`
5. `python Assets/3DResources/Creatures/Spider/Tools/build_models.py --physical`
6. `godot --headless --path . --script res://Tests/ValidateSpiderParts3D.gd`

脚本保留已存在的模型与 Part 场景，避免覆盖手工调整；重新制作某个既有输出前需先另存自己的修改版本。`prepare_assets.py` 的图像缓存路径属于制作机器；完整资源已经复制到项目，日常使用无需该缓存。
