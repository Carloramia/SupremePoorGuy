class_name DeliveryBattleSettings
extends Resource

@export_range(1.0,30.0,0.5) var unit_scale := 8.0
@export var enemy_rosters: Dictionary[String,EnemyRosterData] = {}

func availability_error(id: String) -> String:
	var roster: EnemyRosterData = enemy_rosters.get(id)
	return "敌方编队尚未配置："+id if roster==null else roster.availability_error()
