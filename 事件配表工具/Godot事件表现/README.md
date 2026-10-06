# Godot 滚动事件表现（独立原型）

这是“事件配表工具”下的独立 Godot 4 工程，不依赖、也不修改 `it-is-time` 工程。纯 GDScript，不需要 .NET。

## 打开与体验

双击上一级目录的 `打开Godot事件演示.cmd` 直接体验，或 `打开Godot事件工程.cmd` 打开编辑器。
入口使用本机现有 Godot 4.6.2；换电脑后可设置 `GODOT_EXECUTABLE` 环境变量指向 Godot 4 可执行文件。
也可以在 Godot 项目管理器导入本目录的 `project.godot`，打开后按 F6 运行 `demo/demo.tscn`，或按 F5。
点击底部“进入图书馆”：继续逐句追加 → 双列选择卡 → 分支对话 → 奖励预览 → 领取奖励 → 返回探索。
滚轮向上查看历史，“回到最新”只滚动，不推进剧情。事件结束不可再次触发；右下“重置演示”仅供测试。
左侧词条、奖励符文和日期按钮支持悬浮信息；“词条说明”和事件窗口的“说明”可打开独立说明浮层，关闭后仍停在原步骤。

这次实现的是滚动事件表现与截图参考的 UI 格式，不是完整叙事系统。采用灰阶占位，暂不制作配色、材质、正式图标。左侧队伍和顶端路线是静态示例，尚未接角色移动、条件触发、战斗、存档或配表工具导出。
详细的参考迁移关系和交互规则见 [UI布局规范](docs/UI布局规范.md)。

## 文件与职责边界

| 文件 | 职责 | 禁止越界 |
|---|---|---|
| `ui/event_window.tscn` / `.gd` | 模态遮罩、滚动记录、逐句播放、分支、奖励回执 | 不查询地图，不改背包，不控制全局暂停，不读写存档 |
| `ui/exploration_shell.gd` | 侧栏、路线/资源、场景、底部操作；接收快照，发出意图 | 不触发真实战斗、不修改队伍 |
| `ui/event_cards.gd` | 双列选择和分区奖励卡 | 不推进节点、不发奖励 |
| `ui/info_panel.gd` | 悬浮信息与独立说明浮层 | 不推进剧情、不影响奖励；ESC 只关说明 |
| `ui/layout_theme.gd` | 字体、灰阶占位样式 | 不含业务逻辑；后续美术只需改样式 |
| `data/library_demo.json` | 演示对话节点、分支和奖励描述 | 不包含可执行脚本；不是最终配表规范 |
| `demo/demo.gd` | 示例触发入口、模拟魔力/符文、奖励去重账本 | 不是正式地图/奖励系统 |
| `tests/validate.gd` | 对话、分支、回执、结束、去重测试 | 不依赖主游戏 |
| `tests/capture.gd` | 实机渲染截图 | 只用于本地验证 |

## 对接接口

1. 实例化 `ui/event_window.tscn` 加到场景树。
2. 宿主连接信号后调用 `open_event(definition, session_id)`。返回 `OK` / `ERR_BUSY` / `ERR_INVALID_DATA`。忙时不覆盖正在进行的对话。
3. 地图宿主负责暂停探索、屏蔽自己的快捷键；窗口遮罩拦截鼠标，不改变 `SceneTree.paused`。若宿主暂停游戏，本窗口仍能响应。关闭时由宿主恢复先前状态，而不是无条件取消暂停。
4. `choice_selected(event_id, choice_id)`：可供宿主记录分支。窗口已经负责节点跳转，不要再次推进。
5. `reward_requested(request_id, rewards)`：手动模式在用户点击“领取奖励”后发出；自动模式到达奖励节点即发出。宿主按请求 ID 去重、实际发放并存档，然后调用 `acknowledge_reward(request_id, true, message)`。失败时传 `false`，保留等待状态；修复后用相同 ID 确认。
6. `event_closed(event_id)`：宿主标记事件完成、恢复地图状态。关闭和奖励确认都不会再次发奖。

请求 ID 为 `session_id:event_id:reward_node_id`。正式游戏的 `session_id` 必须是可存档、可恢复的事件执行实例 ID，不能每次读取对话随机生成。**真正的跨存档去重由奖励/存档服务负责**；窗口仅阻止当前回执重复展示。`transcript` 是本次窗口记录，不是永久事件档案；再次打开会清空。

```gdscript
func on_reward_requested(request_id: String, rewards: Array) -> void:
    # 正式实现应将发奖与请求账本提交为一个原子操作。
    var receipt = reward_service.apply_once(request_id, rewards)
    event_window.acknowledge_reward(request_id, receipt.success, receipt.message)
```

## 演示数据

`line` 节点：`speaker`、`text`、`next`。
`choice` 节点：`options` 数组，每项为 `id`、`text`、`next`。
`reward` 节点：`title`、`rewards` 数组、`next`。奖励内容由宿主解释，窗口只显示 `label`。
`end` 节点：等待用户确认后关闭。

事件根字段 `reward_mode`：`manual` 先展示预览再等待点击领取；`auto` 自动请求奖励。省略时沿用旧的自动模式。演示设为 `manual`。
选择项可额外填写 `title`、`summary`、`tag`、`action`，对应卡片标题、说明、标签、按钮文字；省略时使用原 `text` 与默认文案，不改变节点跳转规范。

一次“继续”显示一个新节点；选择后追加玩家选择和该分支第一句话。未经选择的分支不进入记录。奖励卡在原记录中先预览，确认发放后更新为回执，不跳出新弹窗，也不重复添加卡片。

基础校验检查节点类型和跳转引用，不做完整策划语义校验（条件表达式、可达性、循环、奖励是否合法等留给后续配表规范）。

## 验证命令

```text
godot --headless --path <工程路径> --editor --import --quit
godot --headless --path <工程路径> --script res://tests/validate.gd
godot --path <工程路径> --script res://tests/capture.gd
```

目标是 1280×720 横屏桌面演示；暂未适配手机窄屏。系统字体优先使用微软雅黑，正式发行时应改用项目自带、许可允许的字体。
