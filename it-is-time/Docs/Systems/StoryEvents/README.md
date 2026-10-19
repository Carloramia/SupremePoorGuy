# 剧情事件配置与接入

2026-10-20。适用于正式 GameRoot 的新版六边形地图。20条剧情及3条辅助记录已编排原生执行流程，并连接地点交互、现有纸面事件面板、会话存档和战斗回执。部分操作仍因原稿待定值或缺少正式怪物资源而不可执行，见末尾清单。旧地图和独立 QuestService 不切换为这套流程。

## 内容与文件边界

策划依据为 [事件总表](../../../../UI跳转原型/事件/事件总表.md)、[接入规范 v0.8](../../../../UI跳转原型/事件/接入规范.md)、[程序监听清单 v0.7](../../../../UI跳转原型/事件/程序监听清单.md)。本次采用规范允许的同义执行格式，不把网页草稿改后缀冒充 Godot 单事件文件。

| 文件 | 用途与修改边界 |
| --- | --- |
| [texts.json](../../../Content/Events/Current/texts.json) | 段落正文及来源哈希，由草稿导出；不要把正文当执行指令 |
| [flows.json](../../../Content/Events/Current/flows.json) | 23个ID的节点、选项、条件操作和后继；前期测试后不要随意重命名节点，会影响旧进度 |
| [parameters.json](../../../Content/Events/Current/parameters.json) | 当前实际读取的数值、物品ID、战场/敌军引用、奖励预设、四轮赌局配置；null不是0 |
| [StoryCatalog.gd](../../../Scripts/Events/StoryCatalog.gd) | 加载、正文引用、地图绑定及执行图校验 |
| [StoryConfiguration.gd](../../../Scripts/Events/StoryConfiguration.gd) | 执行参数字段与类型校验；保留null待定，不用0或测试编队补齐 |
| [StoryService.gd](../../../Scripts/Events/StoryService.gd) | 条件、推进、事务内状态、战斗结果；不自行读写玩家槽位 |
| [StoryController.gd](../../../Scripts/Events/StoryController.gd) | 地点菜单、对话、选择、献祭确认、自动后续和事件待办；复用 EventPanel，不重做布局 |
| [GameSession.gd](../../../Scripts/Application/GameSession.gd) | 所有正式提交的保存与失败回滚；复用已有槽位 |

地图 Source/Documentation 内的旧 `pending_binding`、旧参数与执行图快照不改写为“已发布”。正式调用以本目录说明及 `Content/Events/Current` 为准。JSON 已被现有导出规则包含，运行不依赖导出包外的策划文件。

## 更新正文与执行配置

先同步总表和写作草稿，再在工程根运行：

```powershell
python Tools/Integration/BuildStoryEvents.py
python Tools/Integration/BuildStoryEvents.py --verify
```

编译只更新正文；执行图和参数已存在时保留手工修改，不自动覆盖。后续修改分支时，同时校准 `flows.json` 和编译器中的初始模板；更改已发布节点ID前需给 `story_events.entries` 做进度迁移。`--verify`核对当前正文、来源哈希和ID集合，不代表真实玩法验收。

正文节点引用段落下标；`{"index":4,"lines":[1,2]}`可只展示该段的指定行。策划括号说明、选项标头及结果表不作为对白整段输出。

## 正式接口与监听

| 入口 | 输入与结果 | 谁调用 |
| --- | --- | --- |
| `session.open_story_event(id, context)` | context含`source_id / entry_role / trigger_mode`；返回bool，失败读`last_error` | StoryController先检查真实抵达及地点交互条件，再提交 |
| `session.advance_story_event(id, choice, revision, selected_ids=[])` | 当前节点选项ID、当前revision、献祭实例ID；返回bool | 当前事件按钮；过期点击拒绝 |
| `session.commit_battle(result, snapshot)` | 匹配已存战斗ID的真实回执与地图快照 | 原有 DeliveryMapBridge结算；不是对话按钮直接伪造胜利 |
| `StoryService.cancel_battle(data, request)` | 载入失败时取消本事件的等待；已拾取物品保留 | Bridge统一取消事务；付过本金的赌局进入待处理，不擅自退款 |
| `StoryService.due(data)` | 购买时间与当前`world_time.total_minutes`比较 | 安全的大地图阶段自动检查；打开界面、战斗、转场时延后 |
| `StoryController.task_rows / navigate` | 进行中的事件待办与真实地图导航 | 现有待办页，与4项新手指引分开统计 |

存档新增可选字段 `story_events={version,entries,receipts}`，每条保存`node / cursor / revision / flags / context / completed / resume`，以及可选的`dialogue_history`；`event_items`存国王特令及06物品数量。已有旧存档不强塞开场；新版新游戏先完成任命，再打开原新手待办。

### 同一事件内连续阅读

“继续”把下一段对白追加在已读对白下面，不再关闭并重新创建事件面板。`StoryController._present`复用同一纸面、Label和滚动区，只更新正文及当前操作按钮；正文增加后等待布局完成，自动滚动到最新一句，仍可手动向上回看。跨节点的对白继续累积，选择与领奖仍留在当前大面板下方；切换事件时显示该事件自己的记录，不混入其他事件。

`dialogue_history`按阅读顺序保存`{"node":"节点ID","paragraph":0}`引用，paragraph为该节点的paragraphs数组下标，不是texts.json全局段落下标。只记实际抵达的正文，未选分支不会提前出现，不把按钮提示或临时错误当成对白保存，也不复制正文字符串。写入与进度推进共用原会话保存事务，失败整体回滚；重复点击、重开、设置返回和JSON读档不会重复追加末句。段落序号比较按整数值处理，不能依赖JSON往返后的字典类型相等。

旧存档可缺少此字段，读取时仅恢复当前对白节点中由cursor证明已读的前缀，不猜测过去选了哪条分支。之后正常继续时补入新记录；不会回放或自动触发奖励。未来重命名节点或重排节点内paragraphs时，除原进度外也须迁移阅读引用。`StoryService.prose`是纯读取，UI重建或切语言不推进剧情、不写真实槽位。

任命未完成时不可用关闭按钮跳过，但仍可进入设置、保存并返回主菜单；继续游戏后按已读段落续接。首次新手待办是否展示保存为`guide_shown`，中途退出再完成任命也会出现，之后不重复。幽灵满4日后仅在安全地图阶段自动展示；本次运行关闭后不反复强弹，可回城手动续接，重新启动也可续接。

普通剧情战斗沿用玩家出战队伍；观战用`combat_mode=spectator`、空`party_ids`和两方手填编队。请求保存双方物种/数量快照，读档不改押注、不重抽阵容。两方都在真实 BattleHost 中生成、索敌和攻击，跳过玩家部署；战斗不再附带默认20魔力，事件报酬只由对应节点提交。

购买引擎、献祭、付款、发奖和推进均经同一会话保存；失败整体回滚。06先拾取并保存，再单独开战，因此之后失败、退出或载入失败不会撤销物品。20前3轮和第四轮赠礼分开去重；赠礼保存失败停留待领，不重赌。

## 怎样填战斗配置

`battle_map_id`引用新版 [地图索引](../../../Content/Maps/FrontierEditor_20261019/Runtime/index.json)中的战场ID；`enemy_config_id`和双方roster引用新版 [BattleSettings](../../../Content/Maps/FrontierEditor_20261019/Runtime/BattleSettings.tres)的键，而不是怪物显示名。编队资源的`definitions`最终引用`CreatureFactory.DEFINITIONS`。

例如普通分支需要以下字段；占位值必须换成真实已登记ID，不能照抄启用：

```json
"battles": {
  "help": {
    "battle_map_id": "填写实际战场ID",
    "enemy_config_id": "填写实际敌军编队ID"
  }
}
```

04额外必须填写`battles.clear.source_id`。它会给该地图对象增加`clear_target`入口；先向城主接取，再到目标清剿，胜利后回`city_center`交付。不能在城里远程开目标战斗，也不能把任意胜利当委托完成。

02已保留地图提供的`battle_hex_1 / wolf_encounter_team`，但该编队实际注明缺少dog且disabled；08保留`battle_forest_wolf / enemy_giant_gong_beast`，实际缺gong_beast。不要根据文件名擅自换成普通狼或角兽。08启用正式拱兽后，运行时按已确认规则施加3倍身体缩放。

19的`wolf / beast`为玩家战斗，不额外生成被帮助者作为友军；胜利怪物由`reward_presets.wolf / beast`指定`res://...json`正式完整Factory记录。记录须通过`CreatureFactory.valid_record`，并提供`name/form/color/hp/attack/armor/speed`等库存字段。开战前冻结奖励记录，领取时用稳定实例ID送入仓库，仓库不设本次容量扣除，不能随机补一只普通怪物冒充强化奖励。

19的`watch`及20的每轮须分别填写`battle_map_id / side_a_roster / side_b_roster`。20的`rounds`固定4项；10/20/50/100本金、获胜总返还2倍本金、第四次胜负均发发条盒为已确认规则。正式`loss_policy`仍为null。当前只实现可选的`lose_stake`处理，不代表策划确认；负责人确认前不得开启真实支付。平局、中止和载入失败进入`unresolved`保存账务，不强判胜负、不推进轮次，也不自动重开赌局。

## 祭品属性与身体边界

18按当前1/2/3阶段逐次公开。第一阶段只看皮毛，不加体型或物种限制；第二阶段看实际可飞；第三阶段要求蛇类且无手无足。排除待接收、不可回收、锁定及当前战斗占用的实例，必须至少留下1只。确认界面只列合格者，二次确认后才执行不可逆消费。

实例可携带`event_traits={"fur":true,"can_fly":false}`，值必须为bool；当前狼模板可回退为皮毛，不能根据名字含“鸟”推断可飞。蛇类使用实际snake定义且无额外肢体。当前正式召唤池没有可飞物种，第二阶段仍依赖生物组提供正式可飞记录并标注能力，不能为通过测试把普通狼标为可飞。血雨暂不执行。

## 已确认的符文与奇物

| 来源 | 正式奖励 |
| --- | --- |
| 初始 | 生命 |
| 03 | 攻击、防御；没有里斯巴巴线索 |
| 04 | 清剿并回城交付后，螺旋人像 |
| 07 | 挑衅铃、宣传旗帜，共享一次归还结果 |
| 08 | 巨化，替代旧奇物 |
| 10 | 壳雕与20魔力；攻击阈值仍待配置 |
| 11 | 大群、撕咬诅咒，同时发放 |
| 15 | 好战、血肉顽强；两种回答同奖 |
| 16 | 结晶化眼球 |
| 18 | 首次20魔力；第二次沸血；第三次血红晶石 |
| 20第四次 | 发条盒，无论本轮胜负 |

目录仍为9类符文、8件奇物，实际效果继续由[召唤系统](../Summoning/README.md)维护。苔藓心脏的`boss:earth-guardian`仍缺明确地图/Boss来源；不能等同05传闻或亡灵羊。轻步、溅击、缓行仍不接入。

### 固定魔力报酬与战斗掉落分开

本轮用户授权自行选择少数20魔力事件，其余默认10。以下已写入`parameters.json`及编译器的首次生成模板；再次编译仍保留已有人工配置。

| 来源 | 固定魔力 | 口径 |
| --- | --- | --- |
| 03图书馆援助 | 10 | 符文与援助分开领取 |
| 09 | 10 | 原事件条件不变 |
| 10甲壳圣堂 | 20 | 强度门槛奖励，仍须补攻击阈值 |
| 12直接解决 / 回城找附魔师 | 10 / 20 | 回城多一步路程，给20；两路仍互斥 |
| 13记录星图 | 10 | 原事件条件不变 |
| 17赶鸟 / 木桥建议 | 10 / 10 | 两路仍互斥 |
| 18首次献祭 | 20 | 不可逆消费的固定报酬；后两次仍只发既定符文/奇物 |
| 19观战 | 10 | 两种结果均走原固定观战报酬 |

这些是任务自身报酬，即使由战斗胜利解锁，也不等于怪物等级掉落。杜波10/20/50/100本金、胜利总返还2倍本金不受本表影响；购买引擎100魔力不变，也不向原本仅发符文/奇物的事件追加魔力。

真实BattleHost已移除旧固定胜利+20。等级掉落公式/表尚未提供，胜利回执以`reward=0 / magic_reward_pending=true / reward_basis="monster_level"`保留待配置状态，结算UI明确提示暂不发放，而非把0视为等级奖励定值。存档协议不写null；待配置回执若带非零金额会被拒绝。后续等级奖励须单独接入，不要写进事件固定报酬字段，亦不自动追补历史回执。

## 剩余配置项

以下是正式数据现状，不是额外新规则。不可执行的操作显示具体缺项，对话及其他已确认选项仍可访问。

| 事件 | 还需补什么 |
| --- | --- |
| 01、03、05、07、09、13、14、15 | 当前规则下无待填执行值；15需实际购买并等满4个游戏日 |
| 02 | 卡洛德dog正式敌军资源；不补设战后奖励 |
| 04 | 指定清剿地点、战场、敌军配置 |
| 06 | 明确拾取物品ID，以及狼群战场、敌军配置 |
| 08 | gong_beast正式角色和编队；不再发旧奇物 |
| 10 | `attack_threshold` |
| 11 | 鼠群战场和敌军编队；大型队伍禁入已实现 |
| 12 | 直接解决的战场、敌军 |
| 16 | 魔眼拱兽战场及正式敌军 |
| 17 | 食矿鸟战场、敌军 |
| 18 | 正式可飞祭品能力数据；血雨仍待设计 |
| 19 | 三路战场/编队、两个强化奖励记录 |
| 20 | 每轮手填双方编队与战场、失败支付规则；平局/中止后续处理仍待定 |

## 本轮修复与系统隔离

- 新增同事件连续对白：下一句向下追加，普通“继续”复用面板而不重复播放进入动效；保存已读引用并自动滚动到最新一句。追加式界面成功重试后会清除旧失败提示。文案、选项条件、奖励规则不变，单独的献祭确认等必要交互仍保留。
- 视频反馈的正文空白已定位并修复：剧情面板用`story`类型，旧阅读布局只认`event/tasks`，外层滚动收缩导致内层`DescriptionScroll`高度为0。`GameDemo._resize_event / _render_modal`现将`story`也纳入固定阅读布局；事件菜单、短对白、选择与领奖统一使用同一大号纸面，不按文字长短缩小。标题/关闭在上，正文独立滚动，操作区在下；`EventPanel.tscn`、美术材质和正式文案未改动。
- 修复前的专项测试能稳定检出零高度，修复后通过。以前流程测试能验证文字字段和按钮，但不证明文字实际可见；后续不得仅凭流程测试通过宣称显示正常。
- 修复07从商人先入场时错读驴子正文，以及旧对话按钮的延迟回调推进新节点；按钮使用创建时冻结的revision。
- 修复幽灵关闭后持续重弹、忙碌地图或控制台期间被打断，以及任命关闭守卫被通用面板重建覆盖。
- 修复任命中途退出、读档继续后漏弹首次新手待办；进度与首次展示标志均保存失败回滚。
- 补齐执行参数、段落/行号、节点/选项、存档游标、上下文、等待战斗及战斗ID一致性校验，错误配置返回明确原因，不让类型异常中断事件。
- 日志ZIP包含当前进程的控制台快照，即使`--log-file`重定向到别处也能取得最新事件轨迹。
- 按用户确认恢复设置页的一行语言选择。独立可编辑组件为[LanguageRow.tscn](../../../Scenes/Application/UI/LanguageRow.tscn)，保留原设置和显示项；切换语言不重建当前面板，保存失败恢复原选择。
- 新手待办的新配置只能引用当前奖励目录，旧存档奖励记录仍兼容；独立QuestService不接入正式会话，也不复活已不存在的旧任务接口。

事件执行器本身不改玩家移动算法、怪物物理/AI算法或仓库容量。本次另按用户确认调整Demo召唤计费和胜利掉落占位，见[召唤计费](../Summoning/README.md#demo魔力计费2026-10-20更新)。观战仅在事件请求显式指定时跳过玩家部署，普通战斗仍走原部署与结算链。没有使用测试编队替代正式缺失怪物，也未修改真实玩家存档或个人设置。

## 验证

在工程根执行：

```powershell
python Tools/Testing/RunStoryIntegrationChecks.py --godot $godot
# 仅复核剧情与开场边界：
python Tools/Testing/RunStoryIntegrationChecks.py --godot $godot --only ValidateStoryEvents ValidateStoryEventPaths ValidateStoryEventBoundaries
```

2026-10-20已执行连续对白、正文布局、Demo魔力、剧情与相邻系统30个测试入口，全部通过；同时检查退出码、成功标识、非零失败数、超时及`ERROR:`/`SCRIPT ERROR:`，不以最后一行PASS掩盖异常。

| 测试 | 结果与范围 |
| --- | --- |
| [ValidateStoryDialogueLog](../../../Tests/Integration/ValidateStoryDialogueLog.gd) | 41项无图形检查，43项含实际截图：连续追加顺序、同一控件复用、末尾自动滚动、过期点击、失败回滚/重试去重及提示清除、设置返回、真实存档往返、旧档前缀兼容、坏引用拒绝、不同事件隔离、未选分支不泄露、商人先入场不泄露驴子对白 |
| [ValidateStoryTextLayout](../../../Tests/Integration/ValidateStoryTextLayout.gd) | 894项无图形检查：124个显示案例，含20条剧情入口、最小尺寸下各对白/选择/操作节点、菜单与剧情同尺寸、正文实际高度/裁切、设置返回、长文滚到底及实时缩放；不是只检查Label.visible。另有900项图形检查（增加6张实际渲染截图），1120×680、1366×768、1920×1080均确认正文可见 |
| [ValidateDemoMagic](../../../Tests/Integration/ValidateDemoMagic.gd) | 32项：一/二阶基准、每格符文与每件奇物费用、预览/实际扣费一致、余额不足、保存回滚、读档、正式固定奖励及待配置等级奖励不得付费 |
| [ValidateStoryEvents](../../../Tests/Integration/ValidateStoryEvents.gd) | 132项：真实GameRoot/UI/地点入口、两方AI观战载入、奖励、交付、阶段消费、失败回滚、重复回执、奖励冻结、第四轮失败赠礼 |
| [ValidateStoryEventPaths](../../../Tests/Integration/ValidateStoryEventPaths.gd) | 2208项、57条路径：20条剧情主通路、主要分支、战败/撤退、关闭不领奖、重进和逐节点读档；遍历全部98个剧情节点，另测罗瓦重复对白及两个城市容器 |
| [ValidateStoryEventBoundaries](../../../Tests/Integration/ValidateStoryEventBoundaries.gd) | 74项：损坏配置/存档拒绝、任命UI与读档续接、特令去重、首次待办、幽灵时机/关闭/重进等；旧OpeningAppointment测试入口复用本组，不是额外独立覆盖 |
| 相邻系统 | 会话、恢复、输入、原地图、新六边形地图、旧档后端、石头行动时间、部署与战斗控制、召唤及效果、测试场、新手待办、世界时间、设置、本地化、日志归档均通过 |
| 独立QuestService | 29项纯框架检查；不证明通用任务已接入正式会话或已能发奖 |

可复跑入口为[RunStoryIntegrationChecks.py](../../../Tools/Testing/RunStoryIntegrationChecks.py)。完整结果和逐项日志输出到`Tests/.runtime/story-regression/<运行目录>/`，路径覆盖明细在`Tests/.runtime/story-paths/coverage.json`；这些是隔离测试产物，不作为正式源资产入库。部分旧测试夹具已按当前开场顺序、当前符文目录与滚动设置页修正，保留实际行为断言。

正文显示可独立复测：`python Tools/Testing/RunStoryIntegrationChecks.py --only ValidateStoryTextLayout`。实际渲染使用Godot非headless运行该脚本并在末尾传`-- --capture`，输出`Tests/.runtime/story-text-layout/`中的`geometry.json / graphical.json / library_*.png / long_prose_end_*.png`。超长正文只在隔离测试中临时赋值，不写入内容配置；测试存档、显示设置与真实槽位隔离。

连续对白可运行`--only ValidateStoryDialogueLog`；非headless给该脚本传`-- --capture`生成`Tests/.runtime/story-dialogue-log/opening_three_lines.png`及`opening_accumulated.png`。测试会故意制造保存失败，验证重试后不重发对白或奖励；这些测试只使用隔离槽位。

**通过的是已覆盖的显示、接线与事务流程，不是全部生产内容已可游玩。** 未填正式数值、未登记怪物编队的分支按上表禁用。测试数值、代用编队、能力标签和强化怪物预设仅注入隔离会话，不写入正式`parameters.json`；手动胜负回执不证明真实物理战斗一定结束或长期胜率正确。显示验证限上述三种尺寸及截图，不代表全部分辨率、美术细节与所有设备已验收。
