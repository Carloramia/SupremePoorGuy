# 攻击与受击音效

当前接入的是程序合成的原型音效：7 类、每类 2 个变体，共 14 个单声道 WAV。它们没有使用外部录音或采样，适合先验证时机和混战听感，后续可以保持事件接口不变并替换音频文件。

## 资源和播放链

```text
Tools/Audio/generate_combat_sfx.py
  → Assets/Audio/SFX/Combat/*.wav
  → Resources/Audio/CombatAudio.tres
  → CombatAudio Autoload / CombatAudio3D.play_at()
  → 事件所在 World3D 的 AudioStreamPlayer3D
  → SFX 总线 → Master
```

入口：[音效文件](../../../Assets/Audio/README.md)、[配置](../../../Resources/Audio/README.md)、[播放服务](../../../Scripts/Audio/CombatAudio3D.gd)、[制作工具](../../../Tools/Audio/README.md)。

## 触发时机

| 事件 ID | 当前接入 |
|---|---|
| `attack` | Wolf 飞扑起跳/啃咬前伸、Rat 啃咬前伸、Snake 突进、Spider 起跳、Bird 开始俯冲、Arm 正式挥出 |
| `bite` | Wolf 开始合颚、Rat 抵达目标点后开始合颚、Snake 进入 closing 阶段 |
| `charge` | HornedBeast/通用冲锋进入 CHARGING，播放一次起冲声 |
| `stomp` | 动作模组的前脚确认踏地，位于实际接触点；不依赖冲击波特效是否启用 |
| `bow` | 箭矢实际发射 |
| `hit` | PhysicalBodyPart3D 实际减少 HP；位置为部位中心 |
| `break` | PhysicalBodyPart3D 首次 Broken；位置为部位中心 |

攻击声允许空挥时播放，受击声由实际扣血触发。护甲抵消、友军排除或命中去重导致未扣血时，不额外播放受击声。普通身体/地面碰撞没有接入持续碰撞音，冲锋也没有循环音轨。

## 调节和扩展

在 Godot 文件系统中打开 [CombatAudio.tres](../../../Resources/Audio/CombatAudio.tres)：

- `enabled`：是否允许新播放；`volume_db`：所有战斗音效的总增益。
- `maximum_voices`：同时播放上限，默认 24；满额时跳过新声音。
- `unit_size` / `maximum_distance`：空间衰减和最远听距，默认 32 / 320 个世界单位。
- `cues`：按 event ID 配置 streams、单项 volume_db、音调范围、cooldown；文件随机选取使用独立随机数生成器，不消耗玩法的全局随机序列。

同角色、同类事件共享冷却；即使同一击同时伤到多个 Part，或 Head 断裂引起连带 Broken，也会限制重复声音。不同事件和不同角色分别计时。SFX 总线含 -1 dB 峰值限幅，减小混战叠音削波。

新增触发点可以调用：

```gdscript
CombatAudio3D.play_at(part, &"attack")
# 对于接触点效果，可显式指定世界坐标。
CombatAudio3D.play_at(part, &"stomp", contact_position)
```

新增 event 时先在 cues 中增加同名配置。未配置事件、编辑器预览、无有效发声节点或暂停期间的调用会静默跳过，不影响动作与伤害逻辑。

## 战斗视口和生命周期

正式 GameRoot 的战斗 SubViewport 开启 3D 音频监听。BattleHost 为 DragCamera 的跟随中心增加 CombatAudioListener，距观察地面 Y=8；缩放摄像机不会把监听点拉到高空。独立 TestLevel 使用自己的当前摄像机/监听点。

播放节点作为发声部位（或控制器最近的 Node3D 祖先）的子节点，保持同一 World3D；通过 top_level 固定本次发声的世界位置。游戏暂停时暂停声音，继续时恢复；播放完成、部位删除或场景离开时释放。声音节点不添加任何碰撞体、Joint 或物理力。

## 验证

在工程根目录，令 `$godot` 指向 Godot 4.7.2 编辑器控制台程序：

```powershell
& $godot --headless --path . --audio-driver Dummy --script res://Tests/ValidateCombatAudio.gd
```

[自动检查](../../../Tests/ValidateCombatAudio.gd) 覆盖资源导入、事件、扣血/断裂去重、播放上限、暂停/继续、独立 World3D、实际非静音混音和释放。[正式战斗回归](../../../Tests/Integration/ValidateBattleControlsAndDisplay.gd) 检查战斗监听和既有输入/暂停行为。自动混音检查不能代替耳机/扬声器试听。
