# 烘焙 Mesh 资源

本目录的 `.res` 是从 PNG 轮廓生成的带厚度 ArrayMesh，分为 Bird、HornedBeast、Human、PaperParts、Ratkin、Rats、Snake、Spider、Wolf 和 Environment 等组。最终 Part 场景的 MeshInstance3D 会直接或通过视觉状态引用它们。

`PaperParts` 对应部分早期/StumpBeast 资产命名；不能只按生成角色物种名推断 Mesh 路径。精确映射查 [model_manifest](../../Assets/3DResources/README.md) 的 `volume_mesh` 与 `physical_scene`。

修改 PNG、GLB 或 `paper_volume_thickness` 不等于已替换这个烘焙资源。使用对应 `Tools/Bake*Volumes.gd` 或物种构建工具后，检查 Part 的 Mesh 引用、材质贴图、视觉状态以及角色保存的内部快照。不要把 `.res` 当文本手工改写。

环境 Mesh 与生物 Mesh 使用不同物理包装脚本；身体的 2 倍碰撞厚度规则不能自动套用到静态装饰。资源构建顺序见 [工具说明](../../Tools/README.md)。
