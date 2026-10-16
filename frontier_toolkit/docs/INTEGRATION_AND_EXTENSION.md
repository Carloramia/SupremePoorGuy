# 模块整合与扩展约定

本指南用于继续开发当前工具集和与 it-is-time 整合。交接包沿用 `frontier_toolkit/`；运行资源在各自 project.godot 内解析。详细战斗方案见 [技术文档](BATTLE_INTEGRATION_GUIDE.md)。

## 数据与运行职责

| 模块 | 负责内容 | 外部应使用的边界 | 扩展位置 |
| --- | --- | --- | --- |
| world_map | 地图、移动、道路、地点、迷雾和地图状态 | WorldMapController 公共方法与地点交互信号 | 数据类、地点类型、独立配置资源 |
| scenario_2_5d | 相机、遮挡、空间交互和场景模式 | ScenarioController 信号/方法与 SceneDefinition | 派生生产场景、视觉组件、部署数据 |
| editor | 作者数据、布局、配置验证与转换 | DATA_CONTRACT、editor_data 和稳定配置 ID | catalogs、验证器、生产 builder |
| ui_module | 当前 UI、召唤原型、库存与队列界面 | GameUI 门面、blocking_changed、summon_committed | UI adapter 与单一状态服务 |
| integration | 跨模块编排 | 订阅公共信号、管理会话所有权 | 未来 battle/ 适配层；不把战斗写入地编 |
| it-is-time | 物理角色、武器、AI、部件伤害 | RuntimeAdapter、BattleContext（待实施） | 保留原物理核心，新增上下文/事件适配 |

稳定 ID 连接初始配置与运行实例：地图/地点 ID、永久 monster_id、本场 actor_id、部件 part_key、原型/蓝图/规则 ID 分别拥有独立语义。NodePath、RID、节点实例 ID 不写入可恢复业务存档。

## 新增场景和地编内容

1. 新的探索/战斗布局保存作者源文件，使用现有转换器生成预览，不手工维护重复配置。
2. 新场景继承 ScenarioController，配置相机、交互和遮挡引用；DemoUI 与预览帮助条不进入生产场景。
3. 新敌人、能力和部署规则先加入受控 registry/catalog，校验稳定 ID、版本与资源依赖。
4. 为生产战斗补导航区域、出生空间、角色就绪和波次调度；仅有 Marker 或导出成功不能视为可战斗。

规范见 [地编契约](../editor/docs/DATA_CONTRACT.md) 与 [场景框架](../scenario_2_5d/README.md)。资源重定位时同时处理 gd/tscn/tres 的字面量引用、动态路径与 UID，并重新导入验证。

## 新增 UI 和 TA 效果

当前宿主基于 0.5；新版 0.7.12 独立工程支持召唤 2.0 与 TA 插槽。升级前先完成队位、pending、来源字段和 user:// 目录迁移；不要直接覆盖 ui_module/prototype。

UI 只发操作意图和展示权威状态。召唤提交信号已经发生在保存成功后，监听方不重复扣费/造怪；正式战斗奖励统一通过会话服务提交。阻挡 UI 获取暂停所有权，关闭只释放自己取得的状态。

TA 从独立场景开始验证，再应用到单个页面。每个 Control 使用独立材质/参数副本；文字、点击矩形和布局由原控件拥有。保留撤回路径，检查宽窄九宫格、焦点、禁用、多分辨率和 GPU 静帧。

材料说明：[宿主实验台](../ui_module/shader_lab/README.md)、[新版 TA 适配](../UI跳转原型_20261015/TA/README.md)。两个固定来源工程的文件清单保留；需要改变上游源文件时，先明确它不再是原样快照并更新版本/来源与验证规则。

## 实际战斗整合顺序

按 [实施计划](battle_integration/IMPLEMENTATION_PLAN.md) 的 M0–M5：确定完整工程基线 → 一个真实物理对战 → 地图入口/独立世界/输入门禁 → 幂等存档结算 → 新 UI/队位/能力 → 生产地编与性能预算。

首期优先解决：current_scene 导致 FX/掉落落错世界、全树 group 选择、Input 单例穿透、部件破坏与整只死亡语义、生成/导航屏障、保存确认前清理窗口。复用城镇 SubViewport 基础设施时保留城镇访问语义，战斗退出必须走自己的结果协议。

不要全量覆盖 project.godot。工具集使用 GL Compatibility，it-is-time 声明 Jolt/Forward Plus 及 Autoload/InputMap。正式工程保留哪套设置由 M0 决定，在目标引擎和完整资源下验收。

## 协议和版本演进

配置 schema_version、balance_version 和 blueprint_revision 分别表示结构、平衡和布局版本。先提交迁移器与旧样例，再修改消费者；未知版本拒绝并保留原数据。旧存档备份与来源清单不删除。

新增 BattleRequest/Result 字段时同步更新 [契约](battle_integration/CONTRACTS.md)、两个 Schema、正反例和运行边界校验。数值检查不能代替原型可解析、部署可达、权威队伍 revision 等业务校验。

## 交付和验证规则

修改模块后运行相关测试，Godot/渲染验证按 [BUILD](../BUILD.md)。仓库 CI 执行无需引擎的静态检查；显式 `--contracts-only` 不比对历史工作区字节哈希，避免 Git 换行转换误报源码漂移。

历史 SOURCE_INDEX 与 PR FILE_DIFF 是审计快照；重建需要对应 Git 对象/审计缓存，不是干净克隆的必需步骤。当前源码以运行测试为准，历史证据归档于 [verification](verification/20261015/README.md)。

扩展交付内容时修改 `tools/github-package.config.json` 和仓库模板，再生成新名称的包。结构检查必须验证新入口与资源；不将 .tools、.runtime 或实际 it-is-time 审计缓存加入交付，以免把本机依赖变成正式项目的一部分。
