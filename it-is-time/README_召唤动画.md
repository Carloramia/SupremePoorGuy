# 涌现 · 纸偶部件召唤动画

这是现有 Godot 工程中的独立视觉测试模块：怪物部件从召唤阵高喷、随机混落，再分别吸附到空中组装，整只怪物错峰落地并轻微回弹两次。

**正常 1× 播放，全程固定 4 秒。** 从起势开始，到最后一只怪物站稳结束；完成后的结果展示不计入时长。没有地面开裂效果，也没有在结尾补静止画面。

## 1. 快速运行

工程目录：`D:\Documents\gamejam\SupremePoorGuy\it-is-time`。

### 在 Godot 编辑器中

1. 导入或打开本目录的 `project.godot`。
2. 打开 `Scenes/Tests/SummonAssemblyLab.tscn`。
3. 按 **F6（运行当前场景）**。

注意：**F5 运行的是原游戏主入口** `Scenes/Application/GameRoot.tscn`，不是本实验台。本模块没有修改游戏主入口。

### 本机快捷启动

双击本目录的 [运行召唤组装测试.cmd](运行召唤组装测试.cmd)。启动器目前绑定 `E:\codex\Godot_v4.7.2-stable_win64.exe`；换电脑后需调整该路径，或直接用编辑器 F6。

已使用 Godot **4.7.2** 验证本测试。其他版本的兼容性尚未验证。

## 2. 当前效果规则

```text
起势 → 高喷、混合散落 → 每片短暂停顿 → 加速吸附、空中组装
                                            ↓
                          整只错峰下落 → 轻微回弹两次 → 保留结果
```

这不是整批同步执行的阶段队列：每片按自己的触地时刻计时，先落地的先开始吸附，不等待其他部件；每只怪物拼好后独立进入下落。

- 所有部件从同一个召唤阵喷出，第一落点与最终归属无关，先呈现一堆混合部件，再逐渐显现完整怪物。
- 地面散布为 XZ 平面上的圆盘，半径默认 **9.75**，稍偏向中心。45°俯视透视下，圆盘投影为椭圆属于正常现象。
- 纸片全程跟随活动镜头朝向，保留原始拼接角度；不自转、不翻面，落地也不躺平。
- 吸附由慢到快，使用 `p²` 缓入曲线，接点最终精确归位。
- 空中组装高度以 **2.4** 为中心、上下变化 **1.2**，不同怪物高低错落。
- 改变数量只改变排列密度，不自动缩小怪物或拉远镜头；允许前后遮挡，并可轮换选中。
- 标准、紧凑回拢与自动档在正常播放时**都为 4 秒**，差别只是内部时间分配。
- 完成后结果持续保留，除非主动重播、清空或开启循环。

## 3. 操作说明

| 操作 | 作用 |
| --- | --- |
| `1 / 2 / 3 / 4` | 切换 2 / 5 / 12 / 20 只并播放，保持当前体型 |
| `R` | 相同种子、相同档位重播 |
| `N` | 新种子、新一抽 |
| `空格` | 暂停 / 继续 |
| `Enter` | 跳过，直接显示完整结果 |
| `Esc` | 清空演出 |
| 拖动底部时间轴 | 暂停并检查任意时刻，也支持倒回 |
| 点击已成形怪物 | 显示选框与来源；重复点击轮换重叠候选 |
| `Tab / Shift+Tab` | 正向 / 反向轮换选择 |

左栏可滚动，可调整种类、数量、体型、随机种子、喷射高度、散布和节奏分配。播放速度即时生效，其他设置在下一次开始或重播时应用。

**4 秒以 1× 速度、不中断播放为准。** 调速、暂停和主动跳过会改变实际观看时间。自动档首抽用标准分配，后续新抽用紧凑分配；总长不变。R 重播不增加新抽计数。

## 4. 在哪里维护

| 文件 / 目录 | 职责 |
| --- | --- |
| `Scenes/Tests/SummonAssemblyLab.tscn` | 实验台：地面、镜头、召唤阵、界面及组件分布 |
| `Scenes/VFX/SummonAssembly3D.tscn` | 可复用的召唤演出组件 |
| `Scripts/VFX/SummonAssembly3D.gd` | 喷射、独立计时、吸附、组装、下落、回弹和时间轴 |
| `Scripts/VFX/SummonAssemblyLab.gd` | 实验台控制与测试结果列表 |
| `Scripts/VFX/SummonVisualSnapshot.gd` | 从原怪物场景提取视觉部件及原始接点变换 |
| `Scripts/VFX/SummonSelectionOverlay.gd` | 选框与轻量拼合、接地提示 |
| `Resources/VFX/SummonAssembly_Default.tres` | 标准演出模板 |
| `Resources/VFX/SummonAssembly_Quick.tres` | 紧凑回拢模板，仍为 4 秒 |
| `Resources/VFX/SummonAssemblyTemplate.gd` | 模板字段定义，包括默认 `total_duration = 4.0` |
| `Scenes/Creatures/Characters/` | 原怪物预制体 |
| `Scenes/Creatures/Bodyparts/` | 原纸偶部件预制体 |

修改实验台布局请编辑实验台场景；修改美术、部件或接点请维护原 Character / Bodyparts 预制体，不需要重新制作一套演出专用贴图。组件会缓存视觉快照，更新素材后重新运行测试以重新读取。

当前混合列表使用灰狼、蛇兽、角兽、树桩兽、蜘蛛、人形六类素材。鸟类场景尚未读取到可见部件，因此没有列入默认列表。

## 5. 调参说明：总时长和阶段分配

模板 `total_duration` 默认 **4.0**。组件先按阶段参数计算自然时序，再把整条时间线等比映射到 4 秒；不同数量也遵守同一总长。

因此停顿、吸附、飞行等字段是**映射前的调度参数**，不是固定总长下最终播放的绝对秒数。实验台顶部显示换算后的实际停顿和吸附时间。

常用参数：

- `burst_height`：喷射高度；`scatter_radius`：实验台散布半径。
- `scatter_center_bias`：径向采样指数，默认 **0.65**；0.5 为均匀圆盘，增大则更偏向中心。
- `landing_pause`：部件触地后的停顿分配。
- `landing_to_assembly_duration`：模板中的触地至组装预算，**包含停顿**。实际吸附段为该预算减去停顿。
- `acceleration_power`：吸附加速指数，默认 **2.0**。
- `assembly_height / assembly_height_variation`：空中组装高度及差异。
- `drop_duration`、`landing_stagger`、`landing_sequence_window`：下落与错峰分配。
- `first_bounce_* / second_bounce_*`：两次象征性回弹的高度及时间分配。
- `layout_width / layout_depth / max_row_spacing`：最终排列区域与间距，不改变单位大小。

`elapsed`、`duration`、`seek()` 使用实际演出秒数；部件字典内的阶段时刻使用原始调度秒数。开发时通过 `animation_time()` 获取对应调度时刻，不要混用两种时间。

## 6. 接入正式召唤流程

当前仅为**独立视觉模块，尚未接入正式召唤、仓库或战斗流程**。演出本身不抽取结果、不扣资源、不重复创建仓库记录。

将 `Scenes/VFX/SummonAssembly3D.tscn` 实例化到目标场景，先由游戏逻辑确定结果，再传给组件：

```gdscript
func show_summon_results() -> void:
    var requests: Array[Dictionary] = [
        {
            "scene": "res://Scenes/Creatures/Characters/Generate_Wolf.tscn",
            "height": 3.2,
            "id": "wolf_001",
        },
        {
            "scene": "res://Scenes/Creatures/Characters/Generate_Snake.tscn",
            "height": 3.2,
            "id": "snake_001",
        },
    ]
    $SummonAssembly3D.total_duration = 4.0
    $SummonAssembly3D.playback_speed = 1.0
    if not $SummonAssembly3D.play_batch(requests):
        push_error($SummonAssembly3D.load_error)
```

`scene` 支持资源路径或 `PackedScene`；`height` 是视觉显示尺度，不改变战斗属性；`id` 对应调用方已经确定的结果记录。

主要信号包括 `batch_started`、`part_landed`、`part_attraction_started`、`creature_assembled`、`creature_landed`、`creature_settled`、`batch_finished`，可分别连接界面、声音和流程控制。跳过不会重复触发批次完成。

返回的怪物节点是**视觉副本，不是可战斗单位**，不含原角色的物理、AI与碰撞。正式接入时，由调用方使用同一召唤结果创建真实单位，再清除演出副本，避免重复显示。调用 `clear()` 或新一批 `play_batch()` 会清理上一批演出节点。

## 7. 验证与已知限制

已通过自动测试：六类素材、独立部件计时、持续加速、空中组装、错峰落地、两次回弹、接点归位、镜头朝向、固定体型、重叠轮换选择、倒放、跳过幂等与非法素材处理；额外验证 **1 / 2 / 5 / 12 / 20 / 30 只均在 4 秒结束**，结束前没有统一静止补时。

在工程目录执行，替换为自己的 Godot 可执行文件路径：

```powershell
& 'E:\codex\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://Tests/ValidateSummonAssembly.gd
```

通过标志为 `SUMMON_ASSEMBLY_VALIDATION PASS failures=0`。

已知限制：

- 选取基于投影包围矩形，并非逐像素检测，透明区域可能进入候选。
- 演出使用确定性轨迹，不模拟部件互撞或真实刚体喷射。
- 同时设置极大体型与大量怪物会严重遮挡，不会自动缩小来容纳。
- 离线录制和无界面测试不代表正式游戏或目标设备的帧率保证。
- 目前仍需在正式流程中接入业务结果、音效与真实单位切换。

更多接口与实现说明见 [召唤部件喷射与吸附测试](Docs/召唤部件喷射与吸附测试.md)。本机预览视频位于 `D:\Documents\gamejam\outputs\summon_vfx_preview\godot_four_seconds.mp4`。
