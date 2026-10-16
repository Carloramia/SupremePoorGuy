战斗地图纸片体积资源（2026-10-16）

范围
读取 FrontierDelivery_20261015 中全部 13 张战场实际使用的 battle_art 绑定，
包含地表装饰、独立摆放物、泥潭/蛛网/荆棘/落穴图案及祭坛。
23 个素材 ID 去重为 22 套资源；rock 与 demo_rock_large 共用 LargeRock。
不包含地面底色、外围虚化背景、自然围边组合或部署标记。

目录（均相对于项目根目录）
Assets/2DResources/Environment/FrontierBattle/Separated/<分类>/：整理后的 PNG
Assets/3DResources/Environment/FrontierBattle/Textures/<分类>/：模型贴图
Assets/3DResources/Environment/FrontierBattle/Models/<分类>/：可独立导入的 GLB
Assets/3DResources/Environment/FrontierBattle/Scenes/<分类>/：纯视觉模型场景
Resources/Meshes/Environment/FrontierBattle/<分类>/：体积网格与碰撞资源
Scenes/Environment/FrontierBattle/<分类>/：可直接实例化的物理部件
Previews/FrontierBattlePartsPreview.tscn：全部部件的展示场景
Metadata/model_manifest.json：素材 ID、原始来源、哈希、地图对象及产物路径

分类
GroundDecorations：9 项地表装饰。
GroundEffects：4 项效果图案（仅外观和实体，不包含效果脚本）。
Props：9 项独立摆放物。

制作方式与坐标
不重绘、不拉伸、不裁切原始贴图；原 PNG 保留原文件，SVG 按原画布栅格化。
以 1 像素 = 0.01 单位保持各素材自己的比例，场景实例可再等比缩放。
正反面采用同一贴图，沿透明轮廓生成侧壁，不填充贴图内的透明孔洞。
Props 的贴图在 XY 平面，+Z 为正面，厚度沿 Z，原点在可见轮廓底部中点。
GroundDecorations / GroundEffects 在 XZ 平面平放，+Y 为正面，厚度沿 Y。
地表原点为画布中心。源素材原有锚点另记于 manifest.authored_pivot。
体积侧壁采样上限 192 像素；碰撞采样上限 96 像素，避免高分辨率贴图产生过多面。
碰撞覆盖非透明区域，保留凹陷及分离区域，不使用整幅图片矩形作为碰撞箱。
碰撞轮廓是低分辨率近似，可能与抗锯齿边缘存在少量差异。

使用
将 Scenes/Environment/FrontierBattle 内的 tscn 拖入需要的场景。
根节点为 StaticBody3D，默认不受重力或外力推动，碰撞层/掩码均为第 1 层。
Inspector 的 Thickness 仅修改厚度，同时更新视觉和碰撞，保持 XY 尺寸不变；
地表部件因平放，其长宽保持 XZ 不变。默认地表厚度 0.02，摆放物厚度 0.08。
Collision Enabled 可关闭实体碰撞。草屑、泥潭或蛛网仅作覆盖图时可关闭。
Image Scale 用于在实例中匹配原地图的图片尺寸，视觉和碰撞同时缩放，厚度单独控制。
Opacity 保留原地图中各贴片的透明度。
需要不同碰撞层时，使用 StaticBody3D 自带 Collision Layer / Mask。
此类为独立环境物件，不继承角色身体部件，不注册角色标签、HP、Broken 或攻击系统。
凹面碰撞适用于静态物件，不应直接改为动态刚体；动态物件需要另做凸分解。

限制
这是沿贴图轮廓加厚的纸片体块，不是重新雕刻的完整石头、树木或建筑模型。
帐篷与旗帜等原本共用一张图的物件仍作为一个组合部件。
PitArtwork 只是有厚度的落穴图案，不自动挖空地面；泥潭、蛛网、荆棘也不自动施加效果。
本批资源已接入 13 张原生 3D 战斗地图，共 382 个实例，保留原对象位置、朝向、
图片尺寸、透明度和显示条件。地表继续平放，Props 类改为竖立显示。
地图实例的 Collision Enabled 暂时关闭，关联旧实体碰撞也关闭；原始独立物理部件
场景的默认碰撞仍开启。地面、边界墙、落穴与效果区域保留。
泥潭/荆棘/蛛网继续使用原战场效果区域；实体石头等在禁用碰撞期间不会阻挡或造成
基于接触冲量的碰撞伤害。二维大地图和战场二维缩略预览不作替换。

重新制作（使用 Godot 4.7.2，命令中的 godot 替换为本机可执行文件）
godot --headless --path . --script res://Tools/BuildBattleEnvironmentAssets.gd -- --prepare
godot --headless --editor --path . --import
godot --headless --path . --script res://Tools/BuildBattleEnvironmentAssets.gd -- --bake
godot --headless --editor --path . --import
godot --headless --path . --script res://Tests/Integration/ValidateBattleEnvironmentAssets.gd
prepare 会拒绝覆盖已手工修改的输出纹理；bake 会重建生成的模型、碰撞和场景。
需要长期手工编辑时，请创建继承场景，避免重新 bake 覆盖修改。
如果重新转换了交付地图，需要再次执行：
python Tools/Integration/ReplaceBattleEnvironmentParts.py
该工具只迁移原生 Scenes/Maps3D，保留效果区和边界，不覆盖已经迁移的物件设置。

验证
22 套模型加载、GLB 导入、原图哈希、贴图比例、厚度同步、实例独立性、双面射线碰撞
及 Forward+ 实际渲染均已检查。未进行大量实例同时碰撞的性能测试。
接入后又检查了全部 13 张地图的 382 处引用、碰撞禁用、尺寸/透明度/朝向、地面、
落穴、导航烘焙及效果区域，并通过正式应用流程回归和 13 张地图实际渲染检查。
