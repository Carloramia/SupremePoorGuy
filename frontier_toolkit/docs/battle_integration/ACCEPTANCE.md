# 验收矩阵、运行方式与本次验证记录

审计日期 2026-10-15；本次验证当前根工程基础设施和文档契约，结果快照见 [VALIDATION.json](VALIDATION.json)。**真实 BattleHostBridge、BattleSessionCoordinator、SessionStore 尚未实现，下面的集成验收用例仍待实施。** 源码审计不等于实际战斗验证。

## 1. 本次已执行

环境：Windows、Godot `4.7.2-stable (official)` 标准版、当前根工程 GL Compatibility；未在 it-is-time 的 Forward Plus/Jolt 完整工程运行。

| 命令 / 入口 | 本次结果 | 结果文件 |
| --- | --- | --- |
| `scenario_2_5d/tools/Run-Tests.ps1` | 42/42 | [场景结果](../verification/20261015/scenario.json) |
| `world_map/tools/Run-Tests.ps1`：data_validation | 通过；400 次坐标 roundtrip 及其他数据检查 | 日志位于本地 `.tools/battle-baseline-world-map.log` |
| 同上：地图 acceptance | 28/28 | [地图结果](../verification/20261015/world_map.json) |
| 同上：road_tests | 28/28 | [道路结果](../verification/20261015/roads.json) |
| 同上：scenario_overlay_tests | 14/14 | [窗口结果](../verification/20261015/overlay.json) |
| `node tools/Verify-Package.cjs` | 18 个必需项；277 个 Godot 资源引用可解析 | stdout |
| `node tools/Build-Battle-Integration-Index.cjs` | 51 个文件索引；上游提交固定 | [机器索引](SOURCE_INDEX.json) |
| `node tools/Verify-Battle-Integration-Docs.cjs` | 契约示例、反例/正例探针、本文档本地链接、可用源码哈希检查通过 | stdout；具体数量见执行输出 |

现有 112 项基础用例全部通过。地图测试中的 FakeBattle 胜负与 pending 重建仍是模拟外部系统，不能计为真实物理战斗通过。日志中的已释放相机焦点、损坏 JSON 警告来自故障用例；嵌套原型工程忽略提示来自项目扫描。没有将这些预期警告隐藏为“零警告”。

本次未执行：实际武器在嵌入场景中的物理交战、Jolt 与 Forward Plus 渲染、完整 it-is-time 资源导入、.NET/Android 构建、GPU 画面、存档故障注入、新版 UI 整合。上游 Tests 有 261 个跟踪 GDScript，数量不代表本次执行了它们。审计缓存缺少 Assets 等资源，不适合作为正式测试工程。

### 可重复运行

在仓库根目录 PowerShell：

```powershell
node tools/Build-Battle-Integration-Index.cjs
node tools/Verify-Battle-Integration-Docs.cjs
node tools/Verify-Package.cjs
./scenario_2_5d/tools/Run-Tests.ps1 -GodotPath 'E:/gamejam/.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
./world_map/tools/Run-Tests.ps1 -GodotPath 'E:/gamejam/.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
```

GodotPath 替换为实际安装路径。索引重建依赖本地 `.tools/upstream-ui-20261015` Git 缓存；可传另一份固定提交检出的仓库路径。文档校验不要求网络；缺少源码时会报告 unavailable，不能当成哈希验证通过。没有审计缓存的交接包仍可阅读现有索引和固定 GitHub 链接。

Schema 例子使用示意的 scene/archetype/blueprint ID，必须创建对应注册资源才可启动战斗；部件例子是精简合成数据，不能拿它替代实际生成器的完整部件清单。

## 2. 首个真实闭环必须通过的用例（待实施）

| ID | 场景 / 操作 | 预期与应保留的证据 |
| --- | --- | --- |
| B01 | 地图点击战斗入口一次/快速双击 | 同一 pending，仅一个 battle_id、一个窗口；Fake 无监听；请求日志 |
| B02 | pending 请求存盘失败 | 未进入战斗，仍保留地点交互和地图暂停；可重试；无单位或奖励 |
| B03 | 未注册 scene/archetype/blueprint | PREPARING 返回结构化 error，不能替换成默认怪或判胜 |
| B04 | 生成器失败或超时 | failed result 无奖励；清理已创建对象；地图状态不完成 |
| B05 | 角色 deferred 生成和 DamageController 延迟就绪 | readiness 之前无攻击/手操；缓存 signal 不丢；角色总数符合计划 |
| B06 | NavigationRegion 缺失、未同步或出生点不可达 | 不进入 RUNNING；显示可诊断失败；导航 map/迭代号日志 |
| B07 | 双方生成和阵营初始化 | 玩家 1/敌方 2；自伤/友伤过滤与规则一致；默认 NPC faction 被覆盖 |
| B08 | 真实武器接触敌方部件 | DamageService 数值与实际 current_hp 差一致；主动同挥击去重；无 UI 二次扣血 |
| B09 | 断臂、断躯干、头部全灭 | 断臂不直接判死亡；完整性延迟后失能；unit_defeated 仅一次 |
| B10 | 敌方全部失能但尸体保留 | 可以胜利；判定不使用节点个数或 queue_free |
| B11 | 多波次：第一波全灭，下一波还在加载 | 不提前胜利；失败波次不能减少成已完成；planned/spawning 状态日志 |
| B12 | 玩家全员失能 | defeat，统计真实；战后政策按 ruleset，不由结果页按钮决定 |
| B13 | 返回/撤退、取消加载、结束后再点返回 | 只产生一个 canceled/retreat/result；权限与时间点正确，无无条件 success |
| B14 | 胜利冻结后迟到接触/死亡/加载回调 | 冻结结果和奖励哈希不再变化；旧 battle_id 无法写入新会话 |
| B15 | 结算存盘失败、重复重试 | 场景不提前释放、地图不解冻；同 result_id；无重复奖励 |
| B16 | 在提交前后每个存储点强制退出并重启 | pending 或 ledger 可恢复；最多应用一次；地图与库存版本一致 |
| B17 | 同 battle_id 不同结果/相同结果不同内容 | conflict；保留原台账；不覆盖或再次加钱 |
| B18 | 正常返回地图 | 位置/迷雾/相机/地点状态符合政策；pending 清空；队伍与货币一致 |

## 3. 独立世界、相机与输入（待实施）

| ID | 场景 / 操作 | 预期与证据 |
| --- | --- | --- |
| W01 | 同时实例化两个 own_world_3d 场景，坐标故意相同 | AI/选中/玩家控制均只访问本场注册角色 |
| W02 | A 世界产生冲击波，B 有敌方角色 | B 不扣血、不击退；记录 wave/target world RID 与 battle_id |
| W03 | 受伤数字、装备掉落、行动冲击波 | parent 均在本场 FxRoot/DropsRoot，World3D 与来源一致 |
| W04 | 角色身体远离其 Node3D 根节点 | 相机/遮挡跟随动态 torso anchor；不跟静态根 |
| W05 | 玩家 attach/detach/切换/死亡 | 一个控制器；没有访问其他世界；死亡不被 detach 恢复 AI |
| W06 | 中键拖动、滚轮、点击实体/地面 | 唯一相机、唯一指令源；实体阻挡正确；地面不是所有 StaticBody |
| W07 | 点击仓库/队列/控制台/窗口外，键盘保持按下 | Input 轮询也被门禁；没有穿透挥击/移动；关闭后按政策恢复 |
| W08 | UI 模态与暂停菜单重叠，任意关闭顺序 | 暂停令牌最后一个释放才恢复；不误解冻地图 |
| W09 | 暂停时有挥击、计时器、落体和临时 ragdoll | 逻辑/刚体保持；恢复无速度丢失或残余伤害窗口；死亡体不复活 |
| W10 | 子窗口缩放、不同分辨率/窗口比例 | 正交投影、射线坐标、UI 命中正确；没有修改宿主 content_scale |
| W11 | 战场释放后重复进入 20 次 | 全局组/订阅/规则覆盖/临时引用无泄漏；旧回调不影响新场 |
| W12 | 巨化、超巨化、缩小物理角色 | root/generator Transform 单位缩放；几何/质量/导航/部署半径同步 |

## 4. 新版 UI、召唤与地编（待实施）

| ID | 场景 / 操作 | 预期与证据 |
| --- | --- | --- |
| U01 | 新 UI 发 battle scene_requested | 外部模式只走真实桥，不同时打开本地测试 battle 页 |
| U02 | 点击旧跳过战斗/重复领奖入口 | 正式模式不可用；只有 SessionStore 发奖励 |
| U03 | normal×6、giant×3、ultra+normal | 都是 6 队位；单位数量可不同 |
| U04 | tiny 同批 5 只/少于 5 只、两个批次 | 同批整组 1；不同批分别占用；入库/入队数据不拆错组 |
| U05 | 多种 mode 混合、超队位、pending/warehouse 单位 | 与 PrototypeState 规则一致；非法队伍拒绝开战 |
| U06 | 增殖分身 | 独立 actor_id、来源 ID；无重复永久 monster_id，战后不额外入库 |
| U07 | 新旧 session 迁移及 user:// 目录变化 | 字段完整、备份保留、修订号正确；重复迁移幂等 |
| U08 | 受击/HUD/TA 参数更新 | 来自真实事件；每个 Control 独立材质；动画不触发奖励或第二次伤害 |
| E01 | 导入地编敌人、部署点、场景边界 | ID 可解析、位置 XZ/Y 与旋转一致、Marker 转换正确 |
| E02 | 障碍、视觉遮挡、交互区和效果区重叠 | 各自掩码与职责明确；不能穿墙攻击/部署；视觉淡化不取消物理碰撞 |
| E03 | 不支持的能力/原型或缺失美术 | 准备阶段明确报告，不静默替换；未启用原型不阻塞首期 |

## 5. 上游测试复用与新增测试边界

完整战斗工程导入后，先按实际测试脚本退出方式运行上游现有回归，再跑新增嵌入式场景。可以优先检查：

| 上游 Tests 文件 | 可复用的验证范围 | 不能替代的集成验证 |
| --- | --- | --- |
| ValidateDamageSystem.gd / ValidateGlobalDamageService.gd | 部件伤害、全局服务 | 多 World3D、会话台账 |
| ValidateCombatDamageBalance3D.gd | 主动/被动伤害与护甲平衡 | 召唤 stat_profile 到部件的映射 |
| ValidateStompShockwave3D.gd | 冲击波距离、伤害、击退 | 嵌入场景跨世界隔离（需新增 W02） |
| ValidatePlayerController3D.gd | attach/detach 与控制基础 | 宿主 UI/Input 门禁、多控制器上下文 |
| ValidateGeneratedNPCAttack3D.gd / SmokeWolfNPCNavigation.gd | 生成 NPC 攻击/导航 | 有限波次、地图入口和结算 |

运行示例仅在资源完整的目标工程使用：

```powershell
# 替换为已确定的正式工程路径，先完成完整资源导入。
& $env:GODOT_BIN --headless --editor --path '<完整战斗工程>' --import --quit
& $env:GODOT_BIN --headless --path '<完整战斗工程>' --script res://Tests/ValidateDamageSystem.gd
& $env:GODOT_BIN --headless --path '<完整战斗工程>' --script res://Tests/ValidateStompShockwave3D.gd
```

每个新增用例应真正实例化生产组件和独立世界，使用超时与失败退出码；不能只把拟定类名写进字符串后检查存在。存储测试通过注入 write/flush/replace 失败验证故障窗口，契约测试通过真实非法请求验证拒绝路径。

## 6. 性能与诊断要求

暂不承诺固定帧率或单位上限；当前“6 队位”不是“6 个刚体”，tiny/分身/多部件会放大物理成本。M5 在目标机器、目标渲染和实际美术下记录：CPU/GPU 帧时间 P50/P95/P99、physics step、活跃刚体/关节数、接触数、AI 导航查询、生成耗时、场景切入峰值内存、FX/掉落数量、结算耗时、重复进入的内存趋势。

至少采样双方 1v1、满队位 normal、tiny 多组、ultra、增殖、拥挤敌方波次；开启/关闭遮挡与 TA 动画对比。导航烘焙与生成不能无界阻塞 UI；性能预算由目标平台确认后写入发布门槛。

建议结构化日志：battle_id/result_id/state、actor_id/monster_id/part_key、World3D RID、wave_id、planned/spawning/active 数、request/result 哈希、party_revision/session_revision、commit 状态和错误码。运行时 RID 只记诊断，不写入可恢复存档。发布报告附复现请求、配置版本和日志，避免只交截图。
