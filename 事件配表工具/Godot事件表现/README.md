# Godot 事件开发工作台（独立工具原型）

这是“事件配表工具”下的独立 Godot 4 工程，不依赖、也不修改 `it-is-time` 工程。纯 GDScript，不需要 .NET。

## 打开与体验

双击上一级目录的 `打开Godot事件演示.cmd` 直接体验，或 `打开Godot事件工程.cmd` 打开编辑器。
入口使用本机现有 Godot 4.6.2；换电脑后可设置 `GODOT_EXECUTABLE` 环境变量指向 Godot 4 可执行文件。
也可以在 Godot 项目管理器导入本目录的 `project.godot`。**F5 默认运行 `tools/event_workbench.tscn`，打开调试面板并启动隔离预览。** F1 收起/展开调试面板。
只看表现时，可按 F6 运行 `demo/demo.tscn`，此场景不含调试工具。

### 编辑事件与调整 UI

- 右侧面板：选择节点，改说话人/正文/next，或修改该节点 JSON 中的选项与奖励；点击“从起点预览”或“从选中节点”。
- “应用节点草稿”只改内存；“保存”需确认，旧文件保留为 `.bak`；“另存为”输出新 JSON。预览和关闭不会自动保存。
- “完整 JSON”页支持批量编辑，需显式应用。格式错误会给出 JSON 行号或字段路径。
- 在 Godot 编辑器直接打开 `ui/*.tscn` 调整控件。场景控件与样式由编辑器持有，脚本不再重建主要布局。
- 共享样式位于 `ui/wireframe_theme.tres`；对话、选择卡、奖励卡分别是 `dialogue_line.tscn`、`choice_card.tscn`、`reward_card.tscn`。

完整入口、数据协议和发布边界见 [开发与接入说明](docs/开发与接入说明.md)。
点击底部“进入图书馆”：继续逐句追加 → 双列选择卡 → 分支对话 → 奖励预览 → 领取奖励 → 返回探索。
滚轮向上查看历史，“回到最新”只滚动，不推进剧情。事件结束不可再次触发；右下“重置演示”仅供测试。
左侧词条、奖励符文和日期按钮支持悬浮信息；“词条说明”和事件窗口的“说明”可打开独立说明浮层，关闭后仍停在原步骤。

这次实现的是滚动事件表现与截图参考的 UI 格式，不是完整叙事系统。采用灰阶占位，暂不制作配色、材质、正式图标。左侧队伍和顶端路线是静态示例，尚未接角色移动、条件触发、战斗、存档或配表工具导出。
详细的参考迁移关系和交互规则见 [UI布局规范](docs/UI布局规范.md)。

## 文件与职责边界

| 文件 | 职责 | 禁止越界 |
|---|---|---|
| `ui/event_window.tscn` / `.gd` | 模态遮罩、滚动记录、逐句播放、分支、奖励回执 | 不查询地图，不改背包，不控制全局暂停，不读写存档 |
| `core/event_definition.gd` | 版本、字段、跳转、重复选项与循环校验 | 无文件读写、无 UI |
| `core/event_json_port.gd` | 正式 JSON 读取；工具显式保存、备份与冲突检查 | 不推进剧情、不修改玩家存档 |
| `core/event_session.gd` | 正式文件入口、隔离预览与外部奖励信号 | 不拥有正式背包；不保存编辑草稿 |
| `tools/event_debug_panel.tscn` / `.gd` | 草稿编辑、校验、保存及预览控制 | 正式会话不能被预览跳转或停止干扰 |
| `tools/event_workbench.tscn` | 默认开发入口，独立预览视口与调试面板 | 不作为正式游戏入口 |
| `ui/exploration_shell.gd` | 侧栏、路线/资源、场景、底部操作；接收快照，发出意图 | 不触发真实战斗、不修改队伍 |
| `ui/event_cards.gd` | 双列选择和分区奖励卡 | 不推进节点、不发奖励 |
| `ui/info_panel.gd` | 悬浮信息与独立说明浮层 | 不推进剧情、不影响奖励；ESC 只关说明 |
| `ui/wireframe_theme.tres` | 场景共享样式，Inspector 可编辑 | 不含业务逻辑 |
| `data/library_demo.json` / `event.schema.json` | v1 事件输入及结构规范 | 不包含可执行脚本；地图触发条件不在此协议内 |
| `demo/demo.gd` | 示例触发入口、模拟魔力/符文、奖励去重账本 | 不是正式地图/奖励系统 |
| `tests/validate.gd` | 对话、分支、回执、结束、去重测试 | 不依赖主游戏 |
| `tests/capture.gd` | 实机渲染截图 | 只用于本地验证 |

## 对接接口

1. 实例化 `ui/event_window.tscn`，增加 `core/event_session.gd` 节点并指定 `window_path`。
2. 正式宿主连接 Session 信号后调用 `play_file(json_path, session_id)`，统一经过文件读取与校验。忙时不覆盖正在进行的对话。直接 `open_event()` 保留为低层表现接口，不建议业务模块绕过 JSON 端口。
3. 地图宿主负责暂停探索、屏蔽自己的快捷键；窗口遮罩拦截鼠标，不改变 `SceneTree.paused`。若宿主暂停游戏，本窗口仍能响应。关闭时由宿主恢复先前状态，而不是无条件取消暂停。
4. `choice_selected(event_id, choice_id)`：可供宿主记录分支。窗口已经负责节点跳转，不要再次推进。
5. `reward_requested(request_id, rewards)`：手动模式在用户点击“领取奖励”后发出；自动模式到达奖励节点即发出。宿主按请求 ID 去重、实际发放并存档，然后调用 `acknowledge_reward(request_id, true, message)`。失败时传 `false`，保留等待状态；修复后用相同 ID 确认。
6. Session 的 `event_finished(event_id, preview)`：只有 `preview == false` 才能标记正式事件完成。调试预览结束不得推进任务。奖励确认通过 Session 的 `acknowledge_reward()` 转发；表现层原接口保留。

请求 ID 为 `session_id:event_id:reward_node_id`。正式游戏的 `session_id` 必须是可存档、可恢复的事件执行实例 ID，不能每次读取对话随机生成。**真正的跨存档去重由奖励/存档服务负责**；窗口仅阻止当前回执重复展示。`transcript` 是本次窗口记录，不是永久事件档案；再次打开会清空。

```gdscript
func on_reward_requested(request_id: String, rewards: Array) -> void:
    # 正式实现应将发奖与请求账本提交为一个原子操作。
    var receipt = reward_service.apply_once(request_id, rewards)
    event_session.acknowledge_reward(request_id, receipt.success, receipt.message)
```

## 演示数据

`line` 节点：`speaker`、`text`、`next`。
`choice` 节点：`options` 数组，每项为 `id`、`text`、`next`。
`reward` 节点：`title`、`rewards` 数组、`next`。奖励内容由宿主解释，窗口只显示 `label`。
`end` 节点：等待用户确认后关闭。

事件根字段 `reward_mode`：`manual` 先展示预览再等待点击领取；`auto` 自动请求奖励。省略时沿用旧的自动模式。演示设为 `manual`。
选择项可额外填写 `title`、`summary`、`tag`、`action`，对应卡片标题、说明、标签、按钮文字；省略时使用原 `text` 与默认文案，不改变节点跳转规范。

一次“继续”显示一个新节点；选择后追加玩家选择和该分支第一句话。未经选择的分支不进入记录。奖励卡在原记录中先预览，确认发放后更新为回执，不跳出新弹窗，也不重复添加卡片。

v1 校验节点类型、字段、跳转、选项 ID、版本、非负整数数量及循环；不可达草稿节点给出警告。真正的奖励 ID 是否存在、奖励能否发放、地图条件是否合法仍由外部业务模块校验。

## 验证命令

```text
godot --headless --path <工程路径> --editor --import --quit
godot --headless --path <工程路径> --script res://tests/validate.gd
godot --headless --path <工程路径> --script res://tests/validate_tools.gd
godot --path <工程路径> --script res://tests/capture.gd
godot --path <工程路径> --script res://tests/capture_workbench.gd
```

开发工作台基准 1600×900，内嵌表现预览坐标为 1280×720；暂未适配手机。系统字体优先使用微软雅黑，正式发行时应改用项目自带、许可允许的字体。
