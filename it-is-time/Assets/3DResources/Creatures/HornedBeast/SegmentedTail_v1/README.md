# HornedBeast 分节尾巴 v1

本版本为独立新增素材，不替换原始完整 Tail。四张透明 PNG 使用 AI 重建并补齐连接端，并非原图片的逐像素切片。

## 使用

- 新角色：`res://Scenes/Creatures/Characters/Generate_HornedBeast_SegmentedTail.tscn`。
- 可运行预览：本目录 `Previews/HornedBeastSegmentedTailPreview.tscn`；包含地面、摄像机与 Controller。
- 原角色仍使用单节 Tail；也可在 HornedBeastGenerator 中开启 `Use Segmented Tail` 后重新生成。
- `Tail Segment Scenes` 按尾根→过渡→中段→尾尖顺序引用四个 PhysicalPart。
- `Tail Length` / `Tail Height` 控制整条静态尾巴的外包尺寸（旋转前）；厚度跟随 `Part Width × Overall Scale`。新角色沿用现有角色的 Tail Length=4、Tail Height=3。
- 角色根节点的 `Tail Joints` 控制 Z 轴弯曲限位、弹簧刚度与阻尼。尾根固定连接躯干，其余三处允许 Z 轴弯曲，X/Y 旋转和位移锁定。没有新增主动摆尾控制。

## 文件链路

`Assets/2DResources/HornedBeast/SegmentedTail_v1` PNG → 本目录 `Models` GLB / `Scenes` 原始模型包装 → `Resources/Meshes/HornedBeast/SegmentedTail_v1` 有厚度网格 → `Scenes/Creatures/Bodyparts/HornedBeast/SegmentedTail_v1` PhysicalPart → 新角色。

正面和背面使用同一贴图，侧面有厚度。每节带 Tail 标签、JointIn / JointOut、凸包碰撞体。凸包不复现连接孔和弯钩内凹区，沿用现有纸片部件逻辑。

`Metadata/model_manifest.json` 记录源图哈希、透明边界、孔中心及模型路径。`Tools/build_segments.py` 复用已有模型构建器，保留已存在的 GLB、贴图及 Part；首次构建后使用 Godot 导入，再运行 `res://Tools/BakeTailSegmentVolumes.gd`，最后构建脚本加 `--physical`。

## 验证与限制

结构测试：26 个物理部件、25 个关节；0.5/1/2 倍缩放、连接点连续、内部碰撞忽略、分节限位、手动姿态保存再生成和回退单节方式通过。
物理测试：落地及对尾尖施加扭矩后，各节保持有效、完整与连接。

额外行走测试发现现有姿态触发 RIGHTING 恢复状态，导致行走和踏地暂时被阻止；原单节 Tail 角色也存在相同行走现象。本次保留原控制器及恢复设置，不将该测试称为行走/攻击通过。后续可单独调整角色站立姿态和恢复高度判定。
