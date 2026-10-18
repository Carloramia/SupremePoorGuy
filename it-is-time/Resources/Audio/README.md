# 战斗音频配置

[CombatAudio.tres](CombatAudio.tres) 是 CombatAudio Autoload 在运行时加载的默认配置，类型为 [CombatAudioSettings](../../Scripts/Audio/CombatAudioSettings.gd)。`cues` 中每个条目使用 [CombatSoundCue](../../Scripts/Audio/CombatSoundCue.gd)。

打开该资源可调整总开关、总音量、同时播放上限和空间距离；展开单个 Cue 可替换音频数组、调整单项音量、随机音调和同角色播放冷却。音量单位是 dB：0 保持原增益，负值减小；总音量和单项音量相加。

[default_bus_layout.tres](default_bus_layout.tres) 由 project.godot 的 `audio/buses/default_bus_layout` 引用，包含 Master 和 SFX，SFX 带 -1 dB 峰值限幅。总线布局修改会影响所有使用该总线的音源。

新增角色只要沿用已接入的攻击模组或 PhysicalBodyPart3D，就会使用这组通用音效；当前尚未按物种拆分独立音色。具体事件和限制见 [系统 README](../../Docs/Systems/Audio/README.md)。
