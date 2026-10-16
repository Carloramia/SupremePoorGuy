# 战斗请求、结果、单位及持久化契约（拟定 v1）

**本协议尚未在运行时代码实现。** Schema 和示例用于联调与 review，不代表把 JSON 放入 encounter_data 就能开战。现有接口只包含 map_id/location_id/encounter_data，参见 [当前代码地图](CURRENT_CODE_MAP.md)。

## 1. 基本约束与版本

采用 JSON 可序列化数据，数字必须有限，字符串 ID 非空；不传 Node、Resource、Callable、RID、instance_id 或绝对文件路径。注册表把 ID 解析到受控 PackedScene/Resource。Schema 版本描述结构；balance_version 描述数值规则；blueprint_revision 描述角色布局，三者不能互相替代。

Schema 文件使用 JSON Schema 2020-12。附带工具只实现本目录 Schema 实际使用的校验关键字并执行额外跨字段检查，不是通用 JSON Schema 引擎。正式运行应在 GDScript 边界实现同等验证，并用通用 Schema 工具校验来自外部的构建资产。

## 2. BattleRequest 字段

完整示例：[battle_request.json](examples/battle_request.json)。

| 字段 | 类型 / 约束 | 语义 |
| --- | --- | --- |
| schema_version | integer，固定 1 | 结构版本 |
| battle_id | string | 会话唯一 ID，在持久化前生成；同一次恢复必须沿用 |
| map_id / location_id | string | 精确关联当前地图地点，不能仅用显示名 |
| encounter_id / scene_id | string | 遭遇配置与生产场景注册 ID |
| seed | integer，0…4294967295 | 配置/生成随机源；不保证物理确定性 |
| party_revision | integer，>=0 | 权威队伍修订；提交时必须仍匹配或走明确冲突处理 |
| ruleset_id / balance_version | string | 结算政策和物理数值映射版本 |
| party_slots_limit | integer，固定 6（本版） | 新召唤队位上限 |
| health_policy | session_only / persist_parts | 本场伤势是否写回；首期建议 session_only，persist_parts 尚需实现 |
| party | array，至少一只 | 本场入选永久单位快照，含来源身份、蓝图、部署与数值 |
| waves | array，至少一波 | 有限敌方波次，不用无限 Spawner 代替 |
| return_context | object | 固定 route=world、当前 location_id；用于校验返回一致性 |

party 每项：

| 字段 | 语义 |
| --- | --- |
| monster_id | 永久单位 ID，与 UI 仓库 ID 对应；同请求唯一 |
| actor_id | 此场实例 ID；与所有敌人及动态分身一起全局唯一 |
| archetype_id | 形态/行为/装备原型注册 ID，不能仅把“兽形”当作 Wolf 路径 |
| blueprint_id / blueprint_revision | 冻结的生成布局配置；同一 ID 修订必须指向同一部件集合 |
| faction_id | 运行阵营；例子约定玩家 1、敌人 2，入树前覆盖 NPC 场景默认值 |
| spawn_id | 本场 SpawnRegistry 中的稳定部署点 ID |
| mode | normal/giant/ultra/tiny/multiply/special；实际能力须经注册表解析 |
| slot_group / slot_cost | 组 ID 与整组成本；同组成本相同，只累计一次 |
| batch_id | 召唤批次 ID；缩小共享队位时必须同批 |
| recoverable | 保留新 UI 语义；不能据此自行判定战死删除或复制入库 |
| stat_profile | hp/attack/armor/speed/interval/visual_scale/part_hp 的规范化快照 |

`mode` 沿用新 UI 的 normal/giant/ultra/tiny/multiply/special 枚举。字段未覆盖的 abilities/effects/source_layout 等必须保留在权威原始单位数据中，registry/蓝图负责生成行为；不要用这个精简快照反向覆盖整条怪物存档。

waves 每项包含 wave_id、trigger（首波 on_start，后续 after_previous）及 enemies。敌人记录 actor_id/archetype_id/faction_id/spawn_id；其固定蓝图和数值在版本化 encounter/registry 中解析，不能从当前可变默认 Resource 临时读取。示例中注册 ID 仅为联调占位，尚未创建对应资源。

### 请求语义校验

除 Schema 外，运行入口必须校验：

1. map/location 与正在交互的地点匹配；pending 不属于另一个 battle_id；保存成功后才 emit/开窗口。
2. party_revision 对应权威队伍；所有 monster_id 属于 team，非 pending/warehouse；不能把 UI 临时拖拽状态当作已保存阵容。
3. actor_id 全场唯一；怪物 ID 唯一；spawn_id 可解析，部署空间和阵营合法；所有 registry ID 和版本可解析。
4. 同一 slot_group 的 mode/cost 一致；仅 tiny 可多个永久单位共组，且必须同 UI batch_id；普通/巨化/超巨化分别 1/2/5；tiny 同批组 1、最多 5 只，不允许同批拆成多个队位组。不能以 party.size<=6 替代队位校验。
5. 首波 on_start，后续 after_previous；至少一个敌人；本版玩家队伍使用同一 faction，所有敌方 faction 与其不同；复杂联盟需在未来规则中显式定义。
6. health_policy=persist_parts 时，要求蓝图有稳定 part_key、原有损伤快照和迁移能力，否则拒绝请求。
7. 可变规则/生成器 Resource 每角色复制，权威快照锁定到本场结束。

## 3. UI → 物理系统映射

| UI / 原型字段 | 物理落点 | 转换要求 |
| --- | --- | --- |
| id | monster_id，注册表关联 actor_id | 永久和临时 ID 分离；不能直接使用节点名 |
| form / recipe_id | archetype + blueprint registry | 人形/兽形/蛇形仅粗分类；必须有明确匹配或报不支持 |
| hp | StatProfile 基准 | 单位级基准，不自动变成部件总和 |
| part_hp.头部 / 核心 / 肢体 | tag Head/Torso/其他的每部件 max_hp | 中文标签规范化为 head/core/limb；明确多头多躯干是每个还是按权重分配；当前尚无平衡公式 |
| armor | 每部件 armor 或版本化部位修正 | DamageService 扣甲；设置前确认部件已生成 |
| attack | 版本化武器/动作伤害配置 | 映射到伤害规则与动作，不能再额外扣一遍 attack |
| speed | 各原型 movement data | 不是直接给每个刚体写同一个速度；需步态/转向/飞行分别配置 |
| interval | 动作/AI 冷却 | 单位秒；不等于物理帧间隔 |
| visual_scale | generator.overall_scale / 蓝图几何参数 | 根 Transform 保持单位缩放；同步质量、碰撞、导航半径和出生间距 |
| abilities / effects / traits | 能力和修正器注册 ID | 展示文本与实际行为分离；每项有支持状态和叠加顺序 |
| batch_id / slots / mode | slot_group/slot_cost/规范化 mode | 缩小同批组，巨化等规则保留；recoverable 不自行改写 |
| clone_count / clone_ratio | 临时分身模板、来源 monster_id | 独立 actor_id；不复制永久存档 ID；结束回收，不当作新召唤入库 |
| source_layout / base_stats / source_cost | 权威单位来源和审计数据 | 不用战斗快照覆盖或删除这些字段 |

`part_hp` 当前是 UI 原型描述，不是实际已生成部件的清单。拟定数值 resolver 应输出逐 part_key 的初始化表，同时保留映射版本；在生成后应用并检查完整性。

## 4. BattleResult 字段与完成语义

完整示例：[battle_result.json](examples/battle_result.json)。结果一旦冻结不可再改；所有重试提交使用同一 result_id 和同一内容哈希。

| 字段 | 语义 |
| --- | --- |
| schema_version / result_id / battle_id | 版本、唯一结果、请求关联 |
| map_id / location_id / party_revision | 与请求必须一致，用于冲突检测 |
| outcome | victory/defeat/retreat/canceled/error |
| reason_code | 机器可读原因；显示文案由 UI 映射，不用解析文本驱动政策 |
| health_policy | 与请求一致；session_only 下 parts 为审计，不写回伤势 |
| duration_seconds | RUNNING 实际经过时间，排除加载/暂停；不能用 UI 页打开时长冒充 |
| unit_results | 每个请求 party 成员恰好一条，含 monster_id/actor_id/status/parts |
| rewards | 本规则计算的 magic 与 item_id/quantity 列表；已校验结果，不由结果页按钮填入 |
| metrics | enemy_defeated、ally_disabled；来自实际事件，分身计数策略归规则 |

unit_results.status 为 alive/dead/unspawned。dead 表示本场失能观测，不自动等于永久删除。parts 每项含 part_key/max_hp/current_hp/broken，max_hp>0，0<=current_hp<=max_hp，broken 时 current_hp=0。加载取消时允许 parts=[]；RUNNING 后结果要求完整蓝图清单。缺失部件不可擅自按满血修复。

| outcome | 地点完成 | 默认奖励建议 | 特别处理 |
| --- | --- | --- | --- |
| victory | 按地点 repeatable/completion_behavior | ruleset 计算 | 确认所有波次完成，无 pending spawn |
| defeat | 否 | 0 | 战后损失政策显式决定 |
| retreat | 否 | 0 | 必须有撤退权限；不能由通用返回按钮绕过 |
| canceled | 否 | 0 | RUNNING 前主动取消，已加载对象清理 |
| error | 否 | 0 | 配置/生成/导航失败；保留 reason 与诊断 |

这是拟定首期默认政策。若设计要求败战保留掉落或撤退惩罚，升级 ruleset 并添加验收；不能在 UI 中随意修改 rewards。

## 5. 拟新增适配接口

以下为职责规格伪代码，不是可以直接运行的现有脚本：

```gdscript
# BattleSessionCoordinator（拟新增）
signal state_changed(battle_id: String, state: StringName)
signal battle_finished(result: Dictionary) # 冻结后只发一次
signal commit_failed(battle_id: String, reason: String)
func start_request(request: Dictionary) -> bool # 接受/拒绝，不代表已进入 RUNNING
func request_retreat(battle_id: String) -> bool
func acquire_pause(owner: StringName) -> int # 所有权令牌，非直接 toggle
func release_pause(token: int) -> void
func retry_commit(result_id: String) -> void

# BattleRuntimeAdapter（拟新增）
signal runtime_ready(battle_id: String)
signal runtime_failed(battle_id: String, reason: String)
signal unit_defeated(battle_id: String, actor_id: String) # once
func prepare(context: Object, request: Dictionary) -> void
func collect_result(outcome: StringName) -> Dictionary
func dispose(battle_id: String) -> void # 可重复调用；仅释放自己所有对象

# SessionStore（拟新增）
func prepare_battle(request: Dictionary) -> Dictionary # ok/error + 保存修订号
func commit_battle_result(result: Dictionary) -> Dictionary # ok/already_applied/conflict/error
```

错误返回必须区分：请求拒绝、异步准备失败、结果修订冲突、存储失败、已应用同一结果。不能全部归为 bool false 后直接关闭。

旧地图结果适配（概念示例）：

```gdscript
var map_result := {
    "success": result.outcome == "victory",
    "result_type": result.outcome,
    "complete_location": result.outcome == "victory",
    "custom_data": {"battle_id":result.battle_id, "result_id":result.result_id}
}
```

**不能现在直接用这段调用 resolve 作为最终事务。** 先重构旧 resolve，把地点纯数据投影、持久化与关闭/解冻分开。否则其内部会提前清 pending、解冻并忽略保存失败。rewards 由 SessionStore 写入权威库存；旧地图只记录完成与审计引用，不再次发放。

## 6. 推荐统一存档事务

拟新增 SessionSnapshot（版本独立于旧 world_map/UI 版本）：

```text
schema_version / revision
world_maps[map_id]             地点、位置、迷雾等数据
party                         怪物、队位、来源数据
inventory                     货币和永久道具
pending_battle                request + phase + frozen_result（若有）
battle_ledger[battle_id]       result_id / content_hash / applied_revision
```

事务步骤：

1. prepare：验证请求和 revision，写包含 pending 的完整新快照；写失败不进入战斗。
2. finish：停止新伤害/波次，等待延迟部件图更新，生成一次 result，写入冻结 pending；未持久化成功不丢弃内存结果。
3. project：从旧权威快照复制生成新快照；验证 result/request；应用奖励和地点策略，写 ledger，清 pending，revision+1。此步骤无 UI 或 Node 副作用，可反复计算。
4. commit：临时文件写入/flush/错误检查/保留备份/替换；失败保持旧权威快照。成功后只从新快照刷新内存与 UI，再释放场景和地图暂停令牌。
5. replay：同 battle_id/result_id/hash 已在 ledger 返回 already_applied，零增量；同 battle_id 不同结果或同 result_id 不同内容返回 conflict。

注意单文件 rename 的跨平台行为与断电持久性仍需故障注入验证；不要把函数返回 true 等同于所有硬件级断电情形均保证。统一快照至少消除了 UI 与地图文件各写一半的应用级窗口。

### 多文件备选

无法迁移统一快照时，PREPARED 日志包含完整 request/result、预期版本及投影快照；每个存储记录 applied transaction ID，按幂等顺序写入；全部写成后标 COMMITTED。启动读取日志完成未提交操作，再解锁地图。若某存储 revision 与预期不同，停止自动重放并保留冲突证据，不能再次加钱试图“补齐”。

### 旧存档迁移

当前宿主 UI 是 `user://ui_module_session.json`，新版独立原型为 `user://prototype_session.json`；user:// 根目录还受工程 config/name 影响。整合到 ItIsTime 后，必须显式定位原工程用户目录并备份，不能假设同名文件自动可见。地图路径由 WorldMapSaveService/调用参数决定，按实际配置读取。

迁移保留全部 monsters、pending、layout、completed 和召唤来源字段；为队伍建立 revision；旧三字段战斗请求第一次分配 battle_id 后立即保存；旧测试 completed 标记与新 battle_ledger 分开。先 dry-run 校验，再生成新文件，保留原文件和迁移报告。

## 7. 事件与资源所有权

| 对象 | 创建者 | 销毁/恢复者 |
| --- | --- | --- |
| BattleRequest / result_id | 协调器 | SessionStore 保留历史；不在 UI 清除 |
| SubViewport、相机与场景 | BattleHostBridge | 提交完成后的 dispose；错误路径同样幂等 |
| 角色/部件/动作/临时分身 | RuntimeAdapter | 本场 RuntimeRoot；外部 Autoload 不持有失效引用 |
| 伤害数字/冲击波 | 物理/行动模块，经 Context 找 FxRoot | FxRoot 与自身寿命；目标限本场 |
| 地面装备 | 装备模块，经 Context 找 DropsRoot | ruleset 决定结算/销毁；不直接变成怪物仓库 |
| DamageService 临时规则 | 协调器（若有覆盖） | dispose 恢复快照；避免跨会话并行覆盖 |
| 输入/暂停令牌 | 各 UI 所有者 | 同一所有者释放；重复释放无副作用 |
| 订阅与角色注册 | RuntimeAdapter | 节点退出或 dispose 断开；延迟回调校验 battle_id |

事件主线程执行，物理回调中破坏/重挂/释放通过 deferred 安排；生命周期汇总在延迟结果稳定后读取。任何迟到回调先核对当前会话和状态，不能向新 battle_id 的台账提交旧结果。
