# 符文与奇物：首轮接入及交接

更新：2026-10-20。对应目录版本 `SummonContent.VERSION = 4`。

### 文件回退后的复核

2026-10-20按当前工作区重新检查：回退后的工程仍保留v4主体接入，不需要用旧文件整包覆盖。已把用户确认的`swarm_count=5`、`extra_limb_pairs=1`显式写入`DefaultSummonGameplay.tres`，并增加配置检查；后续在Inspector中调整这份资源，不只修改脚本默认值。

地图`Source/Exports`中的事件目录和内嵌Markdown仍含旧14符文、“概率魔眼”等历史描述，属于原始导出，不作为当前规则来源。本轮未覆盖这些原始文件，也未动新的地图补丁。正式奖励/效果以本页、`SummonContent.gd`及其运行时实现为准；事件负责人迁移导出内容时须按本页奖励表重绑定，不能直接沿用历史奖励。

本轮把确认后的9类符文、8件奇物接入正式 Godot 工程。不是最终平衡版本，也不代表20个剧情事件已经全部可玩。

## 策划确认与测试参数

- 大群包含缩小效果：一次生成5只真实本体，同批整组1队位，不产生分身。首轮沿用旧缩小分支的属性倍率，暂不能回收。
- 螺旋人像：每只适配怪物增加一对同类肢体，不增加变异率。额外肢体包括该肢体连接的分节，不是单独挂一块皮肤。
- 结晶化眼球：参与召唤时保证本批至少1只获得实际射线魔眼，不是提高出现概率。首轮单件分配给其中1只；其他怪物不会被错误标注为已有魔眼。
- 生命初始拥有；其他条目通过事件奖励接口解锁。普通新游戏不会赠送全目录。
- 轻步、溅击、缓行不进入当前目录。独立缩小符文不再出现在新构筑中。

以下仍为测试限制：每次最多1件战斗定位奇物；巨化与大群暂不混用；奇物占格和新增射线参数尚未最终定案。不要据此扩大正式设计结论。

## 如何直接测试

在 Godot 打开 [SummonContentLab.tscn](../../../Scenes/Application/SummonContentLab.tscn)，按 **F6**，选择“新游戏”。该入口开放全部条目、第四圈和10000测试魔力；地图上仍从原有书本入口打开召唤。

测试存档为 `user://saves/summon_content_lab.json`，与普通游戏的 `user://saves/slot_01.json` 隔离。这个场景不是 F5 默认入口，不要将其替换为正式主场景。选择新游戏会重置测试存档；继续游戏保留测试进度。

建议依次检查：生命构筑 → 加螺旋人像观察额外肢体 → 加结晶化眼球观察其中一只的魔眼 → 大群整组入队 → 分别测试六种战斗奇物。

## 目录与事件来源

| 符文 | 持久化ID | 来源 |
|---|---|---|
| 生命 | `health` | 初始拥有 |
| 攻击 | `attack` | 03 图书馆 |
| 防御 | `armor` | 03 图书馆 |
| 撕咬诅咒 | `bloodblade` | 11 与大群一起发放 |
| 好战 | `haste` | 15 鬼魂传授 |
| 沸血 | `burn` | 18 血祭日第二次献祭 |
| 血肉顽强 | `limb-fortitude` | 15 鬼魂传授 |
| 巨化 | `giant` | 08 超大型巨人事件，替代原奇物 |
| 大群 | `multiply` | 11，与撕咬诅咒一起发放 |

生命、攻击、防御的3/5/7格是同一个符文族的长短版本，不分别计数。角度依次为180°/60°/120°，旋转、镜像后仍可识别。

| 奇物 | 持久化ID | 来源 / 奖励键 |
|---|---|---|
| 螺旋人像 | `spiral-idol` | 04 防卫预算；`QST_SIDE_002_001` |
| 挑衅铃 | `taunt-bell` | 07 年迈的驴子；`QST_GRASS_007` |
| 宣传旗帜 | `propaganda-banner` | 07，与挑衅铃一起发放 |
| 壳雕 | `shell-carving` | 10 甲壳圣堂；`QST_GRASS_010` |
| 结晶化眼球 | `crystal-eye` | 16；`QST_GRASS_016` |
| 血红晶石 | `blood-crystal` | 18 第三次献祭；`QST_SIDE_003_001:stage_3` |
| 苔藓心脏 | `moss-heart` | 大地守卫Boss战胜利；`boss:earth-guardian` |
| 发条盒 | `clockwork-box` | 杜波第四次真实赌局结算，胜负均有；`QST_GRASS_020:round_4` |

全部奖励键与组合以 [SummonContent.EVENT_REWARDS](../../../Scripts/Summoning/SummonContent.gd) 为唯一运行时来源。03、18采用已有支线ID，不要照显示序号猜ID。`boss:earth-guardian` 是本轮预留的来源协议键，尚未绑定某个地图对象；不能擅自等同于亡灵羊或05事件。

## 代码与修改边界

| 要改什么 | 入口 |
|---|---|
| 名称、ID、格形、说明、奖励映射 | [SummonContent.gd](../../../Scripts/Summoning/SummonContent.gd) |
| 大群数量/尺寸、额外肢体对数、六种战斗奇物与射线参数 | [DefaultSummonGameplay.tres](../../../Resources/Application/DefaultSummonGameplay.tres)，在Inspector调整 |
| 参数字段定义 | [SummonGameplaySettings.gd](../../../Scripts/Summoning/SummonGameplaySettings.gd) |
| 家族识别、格盘导入兼容 | [RuneRules.gd](../../../Modules/PaperUI/Scripts/Ritual/RuneRules.gd) |
| 属性计算、风险预览、生成结果 | [SummonExperiment.gd](../../../Modules/PaperUI/Scripts/SummonExperiment.gd) |
| 真实分节肢体、关节与尺寸改造 | [SummonAnatomy.gd](../../../Scripts/Summoning/SummonAnatomy.gd) |
| HP受击、灼烧、治疗、护盾、射线、嘲讽、增益与复起 | [SummonCombatEffects3D.gd](../../../Scripts/Summoning/SummonCombatEffects3D.gd) |
| 事件发奖条件、去重 | [SummonRewardBindings.gd](../../../Scripts/Summoning/SummonRewardBindings.gd) |
| 扣费、奖励保存与失败回滚 | [GameSession.gd](../../../Scripts/Application/GameSession.gd) |
| 保存的身体结构校验、部署、头像 | [CreatureFactory.gd](../../../Scripts/Application/CreatureFactory.gd)、[CreaturePortraitRenderer.gd](../../../Scripts/Application/CreaturePortraitRenderer.gd) |

没有重写地图移动、地形生成或UI美术规范。普通召唤池仍由 `CreatureFactory.SUMMON_POOL` 管理。螺旋人像会筛掉没有可复制肢体的蛇形；其余基础池物种可接入额外肢体。新肢体用Pin关节连接并接受既有控制器的标签发现，不保证已经具备专门编排的新步态；位置、关节类型和长期稳定性仍需调参。

UI继续使用现有PaperUI组件；替换了当前目录、示例、说明、队位提示与详情。没有以一张新美术图替代交互。新中文说明尚未逐项完成英文翻译和截图验收。

## 已接入的战斗口径

- 血肉顽强：对非头/非躯干部位做等效耐久加成，不抬高总生命，不再生断肢，也不额外增强共享护盾。
- 沸血：只有普通命中的后续效果触发灼烧；同一怪物只保留最强一份并刷新，不因命中不同部位而叠加。灼烧经过既有护甲规则，可能被护甲完全吸收。
- 血红晶石：按实际敌方HP损失吸血，受固定一秒窗口上限约束；溢出、护盾吸收、友伤和自伤不产生吸血。
- 苔藓心脏：只治疗仍存活的部位，溢出不储存，不修复断肢。
- 壳雕：整只怪物一份共享护盾；到期消失，不按身体部位复制。
- 宣传旗帜：增益附近其他友军，不给自己，不叠加同类光环。
- 挑衅铃：向既有AI提供临时敌方目标，仍走原攻击合法性检查；不强行打断当前攻击，有生效期和再次生效间隔。
- 发条盒：首次死亡等待后以部分生命复起，维持同一怪物ID。保留相关冷却/治疗上限计时和已失去的非必要肢体；恢复必要结构，不复制新的初始武器。等待复起期间不提前判负。
- 魔眼：头部有可替换的临时球体标记；射线通过真实碰撞查询命中、处理护甲并扣除部位HP。球体、射线柱体不是最终美术资产。

当前射线20单位距离、2秒冷却、60%攻击倍率为新增测试值，其余具体数值见配置/计算脚本，不是已确认平衡结果。

## 事件负责人如何接入

**正式项目目前没有完整运行这批剧情事件。** 这轮实现的是发奖适配器，不是自动执行20个事件的状态机。不要在抵达地点、打开对话或战斗尚未结算时直接解锁。

对话类事件在指定对话实际结束后，调用同一个正式会话：

```gdscript
var ok := game_root.session.claim_content_reward(
    "QST_SIDE_001_001",       # 图书馆；一次解锁攻击和防御
    "library:dialogue:done",  # 由事件系统持久化的回执，不用每帧生成新ID
    {"dialogue_completed": true}
)
if not ok:
    # 保留待发奖状态供重试，不能推进到“已领取”。
    show_error(game_root.session.last_error)
```

接口一次性保存解锁内容、领取标记和回执；保存失败会回滚这些变更。重复调用同一奖励键不会再次发放。不另建GameSession，不绕过接口直接改 `known_runes` / `known_relics`。

| 来源 | 调用方必须监听/提供 |
|---|---|
| 03、07、15 | 指定对话实际结束；`dialogue_completed=true` |
| 04 | 对应战斗胜利回执 + 回城主交付；`battle_id`、`returned_to_giver=true` |
| 08、11、16、大地守卫 | 对应来源的真实胜利回执；`battle_id` |
| 10 | 检查出战及仓库内自有单只怪物的攻击条件；`single_owned_attack_check_passed=true`，不得把多只攻击相加 |
| 18 第二次 | 消费已提交，阶段为`stage_2`；`sacrifice_committed=true` |
| 18 第三次 | 第二次奖励已领取，再提交第三次消费；阶段为`stage_3` |
| 20 第四次 | 真实双方斗蛐蛐战斗已结算，`battle_id`、`settled_rounds=4`；观战模式，胜负均可 |

战斗类奖励只接受 `session.data.battle_results` 中已保存且 `content_source` 匹配的回执。`GameSession.commit_battle()` 从已提交战斗请求的 `event_id`（或显式`content_source`）取来源，不能用地图名字或随意传入的结果字段代替。普通请求记录为`party`；20需要事件战斗负责人接好真正的`spectator`请求和手工决定的双方怪物，不是把普通战斗改个标签。

18应由事件系统持久化“消费已提交、奖励待发放”状态，发奖成功后才能显示下一次献祭要求；保存失败重试奖励，不能再次扣同一只怪物。本适配器不负责消耗祭品或编写下一段对话。20的10/20/50/100下注、赢取双倍本金、第四次赠礼后退出及原稿末尾台词仍由事件状态机实现；本接口只处理独立道具奖励，不凭空增加赌金。

## 存档兼容

旧版本布局按旧格形校验，读取后放入 `legacy_rune_layout_v3`，当前盘面清空为v4，要求重画；不把旧短线防御误认作新符文。第一次成功保存前保留原文件为 `.pre_summon_v4.bak`。更早版本另保留已有的布局归档。

旧怪物不重抽物种、姿态或数值；旧能力描述和旧奇物知识保留兼容，不重新上架停用构筑。旧护甲/生命/攻击升级符文知识合并进对应基础族，旧缩小知识合并进大群，不自动赠送新奇物。

后续改动额外肢体的节点名称、复制分支规则或物种模板时，必须同时考虑既有`parts/poses`的严格校验与迁移，不要删除校验来绕过不兼容。

## 验证与未完成项

使用Godot 4.7.2，运行命令形式：

```powershell
& '你的Godot控制台程序.exe' --headless --path '本工程绝对路径' --script res://Tests/Integration/ValidateCurrentSummoning.gd
```

本轮实际通过：

- `ValidateCurrentSummoning.gd`：276项，确认配置、目录、格形旋转/镜像、发奖覆盖、幂等/回滚、旧存档备份、额外完整肢体分支部署及短时物理有限性。
- `ValidateSummonCombatEffects.gd`：25项，真实受击、射线、治疗、护盾、灼烧不按部位叠加、光环、嘲讽时限、复起和断肢保留。
- `ValidateSummonContentLab.gd`：13项，原生召唤UI、独立解锁、5只大群整组转移与1队位、仓库及详情。
- 既有 `ValidateGameSession`、`ValidateGameRoot`、`ValidateNewPlayerTaskSession`（33项）、`ValidateWorldTime`（45项）、`ValidateSummonAssembly`（146项）回归通过。

仍需完成/确认：

1. 事件文本、完整状态机、交付/献祭条件/赌博双方及地图对象的正式挂接。奖励适配器测试不等于这些事件已玩通。
2. 魔眼构筑若可能全部召唤失败，如何兑现保底尚未确认；目前在扣费前拦截该组合，未擅自改成重抽、退费或凭空补一只。
3. 天气/地形召唤权重仍未接入；没有借本轮修改地图系统。
4. 额外肢体的最终布局/受力/步态、长期混战与性能、所有数值平衡、图形表现和美术资产替换。短时检查不代表这些已验收。

所有自动检查只写 `Tests/.runtime/integration` 的专用数据，未修改普通玩家存档。
