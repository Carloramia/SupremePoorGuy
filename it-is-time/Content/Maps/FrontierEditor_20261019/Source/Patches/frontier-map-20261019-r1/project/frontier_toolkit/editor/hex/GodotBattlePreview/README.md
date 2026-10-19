# 当前战场的水平部署与斜视美术

编辑源为 `../Data/Maps/hex_battles.json`，目前共41张战场。双方阵型保持原槽位、人数和内部间距，整体平移为己方左、敌方右；实际槽位/敌群的中心 Z 相同。对齐会避开实体障碍、深坑、泥潭、荆棘和蛛网。原有障碍、效果、事件和地图美术位置不随部署移动。

编辑器左侧增加“双方部署水平对齐”，可在自行修改后重新对齐；支持 Ctrl+Z 撤销和 Ctrl+S 保存。两张没有敌方配置的历史模板只预留右侧部署中心，不虚构敌方配置。

对象的“美术置换接口”增加：

| 字段 | 意义 |
| --- | --- |
| `visual.surface_mode` | `auto` 按要素、`tilted` 倾斜立起、`ground` 贴地 |
| `visual.tilt_degrees` | 相对地面的角度；0为贴地，90为竖直；默认60 |
| `map.presentation.camera_pitch_degrees` | 预览摄像机俯角，当前为-50 |
| `map.deployment_layout` | 水平对齐轴、中心线及双方中心；实际槽位仍以对象坐标为准 |

树、草、石头、蛛网、荆棘及围边植物默认离地60°，朝向斜视摄像机。图片底部保持原 X/Z 落点；贴图不新增描边。泥潭、深坑、落叶、土壤、碎页岩贴片与路障残骸保持贴地。视觉姿态与碰撞体、效果区完全独立，不以倾斜后的图片推导碰撞。

共享的 Godot 渲染实现位于 `../../godot/battle_visual_pose.gd`；原有 `battle_preview.gd` 转换适配器也使用该实现。“导出接入配置”保留这些字段。正式战斗系统创建视觉后可调用 `BattleVisualPose.apply(sprite, object_node, object_data, 60)`；节点需要已进入场景树，Sprite3D 的 `pixel_size` 为1。该函数会补偿作者设置的平面缩放和旋转，保持美术的地面接触点。

补丁附带当前保存进度的 `battle_scene.json`。安装后直接用 Godot 4.7.2 或兼容版本导入本目录 `project.godot`，按 F5，无需 Python。工程通过相对路径复用大包中的原始素材。

后续编辑战场并保存后，运行 `Start-BattlePreview.ps1 -GodotPath <godot.exe> -PythonPath <python.exe>` 重新生成到 `generated-preview`，或使用 Python：

```powershell
python ./prepare_battle_preview.py --output <独立预览目录>
godot --path <独立预览目录>
```

可通过下拉菜单检查全部战场，在45°/60°/75°间临时比较。预览读取源 PNG/SVG，没有重新压缩图片，也不写入布局或游戏进度；敌我彩色圆点用于核对部署，具体角色由同事的战斗系统创建。它不执行伤害、奖励或回合逻辑。素材默认从仓库的编辑器素材库及 `it-is-time/Content/Maps/FrontierDelivery_20261015` 解析；独立工程可用 `--asset-root` / `--native-content` 指定原素材目录。

旧的已导出静态场景不会因修改 JSON 自动更新。后续系统合并应使用当前工作集及共享姿态实现重新构建对应场景；本次没有改写旧项目的敌群配置。本轮补丁已包含这些源码、当前41张工作集以及可复现的预览快照。
