# WorldMap 实施计划

## 项目检查
目录只有 `提示词/Godot_4.7.2_WorldMap_Codex_总开发提示词.md`。没有 project.godot、InputMap、Autoload、既有玩家、战斗或存档系统，也没有 AGENTS.md。因此新建 Godot 4.x 项目，以独立 Demo 为入口。

## 阶段与文件
1. data / hex：Resource 定义、运行状态、坐标转换及验证。
2. demo / navigation：有限地图、禁用 Hex、编辑器 Polygon2D 障碍、静态导航与真实路径。
3. player / camera：连续移动、暂停/取消、速度区域、自由相机。
4. fog：连续圆形视野，CPU 低分辨率历史遮罩和 shader 当前视野。
5. locations / ui：注册表、持久发现、独立四种 UI、统一生命周期及交互协调。
6. save / generation：JSON、版本检查、生成器契约、会话及战斗适配器。
7. debug：无外部依赖的 headless 验收脚本，交付 README、架构、清单、报告。

每阶段执行 Godot 导入/运行或对应验证。无关文件及提示词保持不变。核心无需 Autoload；UI 只发送结果，外部战斗只接收 signal 并通过公开 API 回传。普通地面点击保留地点交互意图。暂停仅作用于模块，SceneTree 不暂停。
