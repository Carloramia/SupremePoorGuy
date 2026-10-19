# 原型音效生成

在工程根目录执行：

```powershell
python Tools/Audio/generate_combat_sfx.py
```

仅使用 Python 标准库，不需要 NumPy 或联网。按固定种子生成原有 7 类 × 2 个 WAV、7 个利器音效（`blade_swing_01`～`03` 挥砍、`blade_hit_01`～`02` 命中、`blade_clash_01`～`02` 碰撞），以及 4 个短促受击音效（`hit_crisp_01`～`04`），并写入 [Assets/Audio/SFX/Combat](../../Assets/Audio/SFX/Combat) 和 manifest.json。利器音效以低中频气流、短促冲击与阻尼金属泛音构成，避免刺耳的高频啸叫；`hit_crisp` 在起音处加入清脆触点，迅速衰减，可用于命中或受击反馈。波形有首尾淡入淡出与峰值余量；脚本检查采样未溢出，固定输入可以复现相同文件。

这是写操作，会覆盖这些同名合成音效；不修改攻击代码、播放配置或其他美术资源。运行后让 Godot 完成 WAV 重新导入，再执行 [ValidateCombatAudio](../../Tests/ValidateCombatAudio.gd)。

替换为正式音效时优先另存文件并在 [CombatAudio.tres](../../Resources/Audio/CombatAudio.tres) 改引用，保留生成脚本用于原型制作。完整说明见 [音效系统](../../Docs/Systems/Audio/README.md)。
