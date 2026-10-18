# 音效资源

[SFX/Combat](SFX/Combat) 保存程序合成的攻击、咬合、冲锋、踏地、受击、断裂和射箭音效，每类 2 个变体，共 14 个文件。格式为 44.1 kHz、16-bit、单声道 WAV，时长 0.18～0.58 秒，无循环。

[manifest.json](SFX/Combat/manifest.json) 记录来源、生成脚本、时长、RMS 和 SHA256。所有波形由项目脚本合成，没有外部采样；Godot 的 `.import` 文件应随源素材保留，`.godot/imported` 缓存不作为源文件提交。

播放配置：[CombatAudio.tres](../../Resources/Audio/CombatAudio.tres)。完整时机与设置见 [音效系统](../../Docs/Systems/Audio/README.md)。

重新制作使用 [generate_combat_sfx.py](../../Tools/Audio/generate_combat_sfx.py)，会覆盖同名原型 WAV 和清单。若已把正式录音替换到这些路径，先另存或改配置引用，避免重生成覆盖。
