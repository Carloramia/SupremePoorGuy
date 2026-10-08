# 2.5D 实施计划

现有项目：Godot 4.7.2，Compatibility renderer，只有独立的 world_map 2D 模块；无 3D、战斗、角色或 SceneManager 服务；无 Autoload/InputMap 冲突。

先将世界地图文档移至 world_map/docs，入口移至 world_map/tools 并修正项目路径。保留 world_map 资源路径、主场景和原有逻辑。

新增 scenario_2_5d：data、camera、visuals、interactables、occlusion、core、spawn、navigation、lighting、ui、demo、debug。层 1=实体/地面/拾取，层 2=淡化查询；实体可以同时属于两层。所有交互取最近物理命中，UI 使用 unhandled input 优先。布局由 tscn 保存，扩展通过信号与公开 API。

不实现战斗、移动、AI、背包、保存、导航或场景切换。每个模块可单独启动和验收。
