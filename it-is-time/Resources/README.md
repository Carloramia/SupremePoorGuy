# 配置资源导航

`.tres` 保存可编辑参数，`.res` 多用于烘焙的 Mesh。类定义在 Scripts，挂载位置在角色/组件场景。修改共享 `.tres` 会影响所有直接或继承使用它的实例；新建独立配置时先复制资源并更换引用。

| 目录 | 内容 |
|---|---|
| [Generators](Generators/README.md) | 生成器独立默认值、部位映射、手动布局与内嵌快照 |
| [Movement](Movement/README.md) | 步幅、速度、步频、转向、飞奔及 Snake 轨迹 |
| [AI](AI/README.md) | 行为、攻击选项与接收器路径 |
| [Actions](Actions/README.md) | 踏地、冲锋、俯冲、Spider 跳跃与冲击波 |
| [Attacks](Attacks/README.md) | Wolf/Rat/Snake 的专用攻击数据 |
| [Combat](Combat/README.md) | Arm 挥舞、武器类别和 Bow 参数 |
| [Audio](Audio/README.md) | 攻击、咬合、受伤与断裂音效，音量、冷却和播放上限 |
| [Creatures](Creatures/README.md) | 密度、专用物理数据、视觉状态与 Wolf 布局快照 |
| [Application](Application/README.md) | 地图战斗适配与敌方队伍 |
| [Meshes](Meshes/README.md) | 带厚度的烘焙几何资源 |
| [Quests](Quests/README.md) | 独立任务框架示例，当前未接入会话 API |
| [Damage/DefaultDamageRules](Damage/DefaultDamageRules.tres) | 全局冲量转换、挥舞/常态伤害与护甲 |
| [Materials/TestMaterial](Materials/TestMaterial.tres) | 材料质量、格尺寸、纹理与碰撞厚度 |
| [Items/Spear1IdleGripPose](Items/Spear1IdleGripPose.tres) | 双手持矛的常态姿态偏好 |
| [Settings/PerformanceOptimization](Settings/PerformanceOptimization.tres) | 默认性能模式及 AI 决策间隔 |

各子 README 的“直接引用”由当前代码/场景中的完整 `res://` 路径统计。它不是全运行时依赖图：动态拼接、继承覆盖、子资源、缓存与手动快照可能改变最终取值；标为“未发现字面路径引用”也不代表可以删除。

排查参数未生效：先看正在运行实例的 Script 和资源路径，再检查父场景/子场景覆盖、automatic 开关、资源共享、manual_layout，以及动作/恢复/飞行对控制的接管。
