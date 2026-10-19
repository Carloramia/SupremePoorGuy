# 应用、存档与生物实例

## 主入口

| 文件 | 职责 |
|---|---|
| [GameRoot.tscn](../../../Scenes/Application/GameRoot.tscn)、[GameRoot.gd](../../../Scripts/Application/GameRoot.gd) | 主菜单、地图、部署、战斗、结算及设置的宿主 |
| [GameSession.gd](../../../Scripts/Application/GameSession.gd) | 统一存档、交易、召唤、编队、新手待办和战斗结算 |
| [GameUIController.gd](../../../Scripts/Application/GameUIController.gd) | 在 PaperUI 上接入真实游戏会话与界面操作 |
| [CreatureFactory.gd](../../../Scripts/Application/CreatureFactory.gd) | 读取保存的 NPC 场景，生成可存档的姿态与部件记录，部署真实角色 |
| [CreaturePortraitRenderer.gd](../../../Scripts/Application/CreaturePortraitRenderer.gd) | 角色实际视觉的正交截图、白底头像与缓存 |
| [DeliveryMapBridge.gd](../../../Scripts/Application/DeliveryMapBridge.gd) | 正式地图模块与统一存档、界面的适配 |
| [WorldMapSessionSave.gd](../../../Scripts/Application/WorldMapSessionSave.gd) | 保留的 Frontier 地图存档适配 |

## 存档边界

GameSession 继承 [PrototypeState](../../../Modules/PaperUI/Scripts/PrototypeState.gd)，扩展真实角色、地图状态和战斗回执。正式路径是 `user://saves/slot_01.json`，不是原型类默认的 `user://prototype_session.json`。当前游戏只能由同一会话协调经济、队伍和战斗结算；失败时保留可重试状态，不能在 UI 内绕过会话直接重复发奖励。

地图与战斗结果通过 `battle_id/request_id` 和回执避免重复提交。修改存档结构前同时检查 `_valid_save()`、读档恢复、结算和备份处理。不要把测试临时存档写进真实槽位。

2026-10-20 Demo经济更新：真实BattleHost不再默认胜利+20魔力。按怪物等级的胜利奖励公式/表尚未配置，暂以`reward=0`和`magic_reward_pending=true / reward_basis="monster_level"`保留状态；结算页显示待配置，尚不实际发放。GameSession拒绝待配置标志与非零金额同时出现，但仍兼容旧回执及独立测试里明确传入的奖励金额。未来接入等级奖励时须校准真实敌人等级、持久化与重复回执，不自动追补历史结果。事件固定10/20魔力由[事件系统](../StoryEvents/README.md#固定魔力报酬与战斗掉落分开)另行处理，不能与战斗掉落混成一笔。

## 角色定义与召唤池

`CreatureFactory.DEFINITIONS` 当前登记 `human`、`stump_beast`、`wolf`、`snake`、`horned_beast`、`spider`；其中 `human` 指向持矛人形 NPC。当前随机召唤池仅为：

```text
stump_beast, wolf, snake, horned_beast, spider
```

Bird、Rat、Ratkin 和其他武器人形已有测试资源，但不会因场景存在就自动加入该池。敌方编队通过 [敌方阵容配置](../../../Resources/Application/README.md) 另行指定。

Factory 读取已经保存的角色姿态进行部署，不在每场战斗重新随机生成框架。它保存 NodePath 对应的变换、部件标识、HP、护甲和模板场景哈希；修改模板后，旧记录可能因哈希或结构不匹配而被拒绝。引用路径和保存布局都属于生物数据的一部分。

头像来自角色视觉渲染，使用白底正交视图，以可见 Head 部位为中心，使其正面外接矩形面积约占图片四分之一；细长头部优先完整显示，没有可见 Head 则回退到全身取景。无图形模式使用占位图；图形模式负责截图、缓存与请求失效处理。详见 [头像说明](../../Creatures/生物头像生成说明_2026-10-16.txt)。

## 召唤小战场演出

正式召唤通过 `GameWorldView → SummonAssemblyView → Scenes/Application/SummonBattleStage3D.tscn`，在独立 SubViewport / World3D 中创建平坦临时战场。地面、光照、观察摄像机和中心召唤阵可以直接在场景中编辑，替换整个场景可使用配置中的 `stage_scene`。不调用 BattleHost.deploy，不生成敌军或部署编队，也不启动索敌、攻击和胜负结算。

观察复用战斗场景的 `DragCamera3D.tscn` 透视摄像机和 `TerrainCursor3D.tscn` 蓝色自由地形光标。默认捕获鼠标：移动鼠标平移光标和摄像机，右键拖拽环绕旋转，滚轮缩放；`QPressed` 切换系统鼠标，以点击跳过、设置和导航按钮，再按 Q 回到地形光标。打开设置或控制台会释放鼠标并停止观察输入，关闭后恢复原有鼠标模式；结束、跳过或离开召唤也会释放鼠标。此光标不选择、拖动或控制生物，且 X/Z 位置限制在空气墙内侧。

初始取景与地面尺寸独立：镜头按圆形活动范围、部件喷出半径、上升高度余量及保存的完整生物包围盒计算，保留 5% 距离余量，不再为了显示整张地面而拉远。召唤场景单独将初始俯角设为 35°，不更改公共 DragCamera3D 场景。地面基础尺寸为 120×80，按朝向地面的视锥角点继续扩展，边缘额外留出 8 单位；朝向天空的射线显示黑色背景。碰撞箱、空气墙和光标边界同步适配，窗口宽高比变化时重新计算。

召唤环境使用黑色背景、0.25 的冷色环境光及 0.65 的方向光强度。地面采用 [SummonGroundFade.gdshader](../../../Shaders/SummonGroundFade.gdshader)，从暗蓝灰色向黑色渐隐，矩形归一化边距的 45% 开始变暗，在 95% 完全变黑，和外部黑色环境衔接，避免硬边。ShaderMaterial 为场景独立资源，随实际地面尺寸更新 `ground_half_size`；`ground_color`、`fade_start`、`fade_end` 可在地面材质 Inspector 调整。渐隐不使用透明碰撞或缩减地形碰撞。默认视野仍覆盖完整活动圆和保存的生物，之后可自由观察。

召唤视口由 `SummonAssemblyView.is_observation_input_blocked()` 单独判定观察输入，`PlayerControlContext.interface_open()` 优先采用该视口的输入判定，原大地图/战斗的全局暂停与输入屏蔽保持生效。`TerrainCursor3D.world_horizontal_bounds` 默认空值、不限制其他场景；这里只设置为召唤地面的 X/Z 范围，地形射线使用演出专用的碰撞层。

每只生物先在以地图中心为圆心的水平圆内预留组装位置，按保存的完整视觉与碰撞包围范围计算间距，默认至少 1.5 单位。`emission_radius` 为 0 时根据整批生物占地自动计算，正值为指定半径；空间不足时扩展实际半径、地面和空气墙。装饰散件仍在这个圆内独立随机喷出；生物的每一个部件改为在**自己的组装点附近**、半径 `part_spawn_radius`（默认 2 单位）的圆内独立随机喷出，而非在整张地图任意出生。

生物取消随机姿态和整只布娃娃喷发。读取保存的真实部件、质量、模型、碰撞箱及姿态，以 Torso → SubTorso → 肢体连接段 → 脚/手 → Neck → Head → 其他附件的顺序喷出，同类按节点路径自然排序，默认相邻部件间隔 0.1 秒。只保证喷出顺序，不等待上一部件到位，因此多个部件可以同时飞行和吸附。每只生物开始后延迟 `creature_start_interval`（默认 1 秒）启动下一只，多只生物独立并行组装，不等待前一只完成。

未喷出的部件隐藏并冻结。每个部件保持保存的初始旋转、没有随机初始自转，从地面模型下方开始：整个可见模型与碰撞包围范围都低于底面。穿地时碰撞层和掩码为 0，通过向上初速度及竖直维持力穿出地面。真实部件与视觉散件的向上喷发速度统一提高到 10–14；真实部件另有最大每轴 1.5 的随机水平初速度，保持纸片平面但允许接地后自然绕 Z 转动。

真实部件全部出地后进入 `free_motion`：开启地面/空气墙碰撞（层 4、掩码 2），停止上升维持力和吸附力，仅按重力、阻尼及接触响应自由运动。完全出地后至少经过 `part_free_motion_duration`（默认 1 秒），并且当前接触缓存确认接触的是 Ground、法向朝上超过 0.5 时，才进入 `attracting`。使用 PhysicalBodyParts 已有的求解器接触缓存，不用高度估计、射线或空气墙接触替代真实接地；若仍在空中则继续自由运动，没有超时直接吸附的分支。`ground_time`、`ground_position`、`ground_normal`、`ground_collider_id` 和 `attraction_time` 记录判定证据。

进入吸附后重新关闭碰撞（层和掩码归零），用质量/惯量换算的 PD 力与 Z 轴力矩追踪固定组装位置和原始旋转。吸附力追踪真实质心，避免偏心纸片模型的平移与旋转耦合；不会因为已落地而被地面阻挡，也不与散件或其他生物相撞。

组装前断开所有 Joint3D 的两端路径并暂停体节弹簧；保存连接信息，避免已到位和未到位的部件相互拉扯。部件在距离、角度与速度连续满足到位条件后，消除微小残差并冻结在保存姿态。整只完成后在该姿态下恢复关节路径、弹簧原有处理模式和地形碰撞，直接展示待机，不再落地等待 3 秒或执行起身恢复。展示副本保持冻结，AI、行走和攻击继续禁用，因此不会在展示期间重新失衡；真实战斗角色与存档不受影响。Snake 同样恢复保存的贴地后身、抬头前身及 Head/Jaw 姿态。

装饰散件在准备时从真实部件随机构建有上限的视觉池，演出中每隔 `decoration_interval`（默认 0.12 秒，按物理帧取整）重新随机选点、速度和 Z 轴旋转喷出一块。完全出地后才启用地形/空气墙碰撞，恢复自由重力运动，开始自由运动 2.4 秒和后续 1 秒淡出。只要仍有生物未完成组装，淡出后的散件就隐藏、冻结并复用，避免持续实例化和无限堆积；池全部占用时等待空闲，不突破数量上限。最后一个组装完成的生物完成时停止新喷发，剩余散件自然淡出销毁，未使用的池节点立即清理，最后进入展示和结果页。`wrong_part_ratio=0` 仍可完全关闭装饰散件。

生物及散件均锁定世界 X/Y 旋转，保持纸片视觉。地图四周保留无顶盖的不可见空气墙。演出副本通过 `summon_presentation` 标记拒绝伤害和 Broken 请求。`decorations_emitted`、`last_decoration_time`、`summon_complete_time` 可用于检查持续喷发与结束时间。

在 GameRoot 根节点的 `Summon Animation Settings` 调整 [DefaultSummonAnimation.tres](../../../Resources/Application/DefaultSummonAnimation.tres)：

| 参数 | 默认值 | 含义 |
|---|---:|---|
| `stage_scene` | SummonBattleStage3D.tscn | 临时地图、镜头和美术入口 |
| `preparation_budget_ms` | 6 毫秒 | 装饰准备分帧预算；完整模板每帧最多创建一只 |
| `emission_radius` | 0（自动） | 组装位置及装饰喷发的地图中心圆半径；拥挤时扩展 |
| `creature_spacing` | 1.5 | 完整生物外轮廓的最小间隔 |
| `part_spawn_radius` | 2 | 每个生物部件相对于自身组装点的随机喷出半径 |
| `part_interval` | 0.1 秒 | 同一只生物相邻部件的喷出间隔 |
| `creature_start_interval` | 1 秒 | 相邻两只生物开始召唤的间隔，允许前一只尚未完成 |
| `part_free_motion_duration` | 1 秒 | 真实部件完全出地后的最短自由运动时间；满足时间且真实接触地面才吸附 |
| `emergence_clearance` | 0.15 | 初始低于底面及完全出地的安全余量 |
| `attraction_frequency` | 1.5 Hz | 部件吸附的位置和旋转追踪频率 |
| `attraction_maximum_acceleration` / `attraction_maximum_angular_acceleration` | 45 / 60 | 质量/惯量换算前的吸附加速度上限 |
| `arrival_distance` / `arrival_speed` / `arrival_confirmation_time` | 0.05 / 0.3 / 0.1 秒 | 部件到位距离、速度阈值及连续确认时间；同时要求角度误差小于 2°、角速度小于 0.1 |
| `wrong_part_ratio` / `maximum_wrong_parts` | 0.4 / 48 | 装饰池大小按总部位数乘比例并受上限限制；比例 0 可关闭 |
| `decoration_size` | 2 | 装饰部件等比缩放后的最大边长度 |
| `decoration_interval` | 0.12 秒 | 持续喷发间隔；池占满时等待空闲节点 |
| `free_motion_duration` | 2.4 秒 | 仅装饰：每次完全出地后的自由运动时间 |
| `decoration_fade_duration` | 1 秒 | 装饰淡出时间，完成后销毁刚体 |
| `minimum_upward_speed` / `maximum_upward_speed` | 10 / 14 | 真实部件与装饰的初始上升速度范围；完全出地前以物理力维持上升，出地后停止施加维持力 |
| `part_horizontal_speed` | 1.5 | 真实部件随机水平初速度各轴的上限 |
| `horizontal_speed` / `spin_speed` | 4.5 / 5 | 仅装饰的初始水平速度与 Z 角速度范围 |
| `reveal_duration` | 1 秒 | 全部生物待机、装饰消失后的展示时间 |
| `diagnostic_logging` | 关闭 | `[summon_stage]` 组装/待机时间和位置；`[summon_part]` 各部件喷出、吸附、到位时间和目标点 |

已移除整只喷发的随机姿态、随机自转、接地等待与起身恢复参数，以及一次性散件喷发窗口 `emission_duration`；这些均只属于旧演出，不影响正常战斗控制器的对应功能。

设置菜单同时暂停演出物理和全部演出计时。若外部游戏处于 SceneTree 全局暂停，演出仅临时开放自己的 3D 物理空间，先停住其他所有 Viewport 空间，再监听新 Viewport 进入而不逐帧扫描整棵场景树；结束/跳过/退出时恢复其原有活动状态；外部战斗和地图仍暂停。跳过直接进入原有结果界面，返回主菜单保留待安置记录。演出读取已提交的召唤结果，不重新抽取、不重复扣费，不回写展示副本的位置、姿态、HP 或断裂状态。

验证入口：[ValidateSummonAssembly](../../../Tests/Integration/ValidateSummonAssembly.gd)，覆盖召唤池五物种逐件喷出、自由下降、真实地面接触及最短自由运动时间后才吸附、每隔 1 秒开始的并行组装、两类部件的喷发速度、连接隔离和恢复、保存姿态及视觉/碰撞箱一致、装饰池复用上限、全部生物完成后的喷发停止与淡出、空气墙、暂停隔离、观察控制、正式 UI 跳过/退出和存档不变，输出 `SUMMON_PARALLEL`；`SUMMON_ASSEMBLY_RESULT` 包含每种生物部件的最短实际自由运动时间。另验证多种宽高比及正式 UI 的完整圆/生物可见、35° 初始俯角、黑色环境及渐隐材质尺寸。传 `-- --seed=99 --radius=1` 检查另一随机分布与小半径；图形模式传 `-- <截图目录>` 可查看 `free_motion` 等阶段截图。

## 常见扩展

- 新增可召唤物种：先完成 Part、Generator、角色、NPC 与攻击接线，再登记 Factory 定义；需要随机抽取时才改 `SUMMON_POOL`。
- 调整地图敌人：改敌方 `.tres` 与对应地图的配置 ID，不通过修改召唤池实现。
- 修改玩家初始数据：检查 `GameSession.reset()`、继承的 PrototypeState 与新手进度，不只改 UI 展示文字。

相关验证：[会话](../../../Tests/Integration/ValidateGameSession.gd)、[完整宿主](../../../Tests/Integration/ValidateGameRoot.gd)、[恢复与结算](../../../Tests/Integration/ValidateApplicationRecovery.gd)。
