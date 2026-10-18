# Arm 与武器攻击配置

LimbSwingPresetBase 提供可复用挥舞参数；ArmSwingBinding 在每个 Arm 上挂载预设并加入控制组。控制组输入由 LimbSwingController 配置。Weapons 下按武器标签映射近战参数，BowAttack 由专用射击控制器使用。

系统说明：[README.md](../../Docs/Systems/EquipmentWorkshop/README.md)。下面记录 2026-10-18 当前工作区的直接引用，未展开所有继承与动态路径。

| 配置文件 | 数据脚本 | 直接引用者（最多两项） |
|---|---|---|
| [HumanArmSwing.tres](HumanArmSwing.tres) | [LimbSwingPresetBase.gd](../../Scripts/Combat/LimbSwingPresetBase.gd) | [GeneratedHumanCharacter3D.gd](../../Scripts/Creatures/GeneratedHumanCharacter3D.gd)、[Generate_Human.tscn](../../Scenes/Creatures/Characters/Generate_Human.tscn) |
| [PrimaryArmSwing.tres](PrimaryArmSwing.tres) | [LimbSwingPresetBase.gd](../../Scripts/Combat/LimbSwingPresetBase.gd) | [Character_Test_2.tscn](../../Scenes/Creatures/Characters/Character_Test_2.tscn)、[Character_Test_NPC.tscn](../../Scenes/Creatures/Characters/Character_Test_NPC.tscn) |
| [Weapons/BluntAttack.tres](Weapons/BluntAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |
| [Weapons/BowAttack.tres](Weapons/BowAttack.tres) | [BowAttackData.gd](../../Scripts/Combat/BowAttackData.gd) | [BowAttackController3D.gd](../../Scripts/Combat/BowAttackController3D.gd)、[BowAttackController3D.tscn](../../Scenes/Creatures/Components/BowAttackController3D.tscn) |
| [Weapons/ClawAttack.tres](Weapons/ClawAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |
| [Weapons/ShieldAttack.tres](Weapons/ShieldAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |
| [Weapons/SpearAttack.tres](Weapons/SpearAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |
| [Weapons/SwordAttack.tres](Weapons/SwordAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |
