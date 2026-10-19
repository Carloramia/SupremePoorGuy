extends SceneTree
## Confirmed Demo pricing and fixed event payments; all writes use isolated save slots.
const RULES = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
const EXPERIMENT = preload("res://Modules/PaperUI/Scripts/SummonExperiment.gd")
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const CATALOG = preload("res://Scripts/Events/StoryCatalog.gd")
const SETTINGS = preload("res://Resources/Application/DefaultSummonGameplay.tres")
const PAYMENTS = {
	"QST_SIDE_001_001":{"private_money_magic":10},
	"QST_GRASS_009":{"magic_reward":10},
	"QST_GRASS_010":{"magic_reward":20},
	"QST_GRASS_012":{"direct_magic_reward":10,"enchanter_magic_reward":20},
	"QST_GRASS_013":{"magic_reward":10},
	"QST_GRASS_017":{"fight_magic_reward":10,"wood_magic_reward":10},
	"QST_SIDE_003_001":{"first_magic_reward":20},
	"QST_GRASS_019":{"watch_magic_reward":10}
}
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("DEMO_MAGIC_FAIL: "+label)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	check(SETTINGS.base_magic_by_stage=={1:5,2:10} and SETTINGS.magic_per_rune_cell==1 and SETTINGS.magic_per_relic==2,"Inspector resource records confirmed stages and unit fees")
	var rules := RULES.new()
	check(EXPERIMENT.preview(rules).cost==5,"Empty stage-one preview has base five; this does not authorize empty summons")
	rules.draft=RULES.current_definition("health").cells.duplicate(true)
	check(EXPERIMENT.preview(rules).cost==5,"Uncommitted strokes do not count as filled runes")
	check(rules.commit(),"Three-cell life commits")
	var preview := EXPERIMENT.preview(rules)
	check(preview.cost==8 and preview.base_cost==5 and preview.rune_cost==3 and preview.relic_cost==0,"Stage one: five plus three filled cells")
	rules.placed[0].enabled=false
	check(EXPERIMENT.preview(rules).cost==8 and EXPERIMENT.preview(rules).counts.is_empty(),"Disabled but filled rune cells still cost magic and have no active effect")
	rules.placed[0].enabled=true
	rules.stage=2
	check(EXPERIMENT.preview(rules).cost==13 and EXPERIMENT.preview(rules).tier==1,"Stage two base ten does not inflate strength tier")
	check(rules.place_relic("spiral-idol",[-2,2]),"First four-cell relic fits stage two")
	preview=EXPERIMENT.preview(rules)
	check(preview.cost==15 and preview.relic_cost==2 and preview.effective_cost==7,"One relic costs two, not four cells; old tier input remains unchanged")
	check(rules.place_relic("crystal-eye",[1,-1]),"Second generation relic fits")
	check(EXPERIMENT.preview(rules).cost==17 and EXPERIMENT.preview(rules).relic_cost==4,"Two relics add four")
	var long_rune := RULES.new()
	long_rune.stage=2
	long_rune.draft=[[-2,0],[-1,0],[0,0],[1,0],[2,0]]
	check(long_rune.commit() and EXPERIMENT.preview(long_rune).cost==15,"Five cells cost five, not one rune instance")
	for stage: int in [3,4]:
		long_rune.stage=stage
		check(EXPERIMENT.preview(long_rune).cost==5 and EXPERIMENT.preview(long_rune).cost_rule=="legacy_lab","Out-of-Demo laboratory stages keep previous pricing without an invented base")
	var session := SESSION.new()
	session.save_path="res://Tests/.runtime/demo-magic/%d.json" % Time.get_ticks_usec()
	session.data.array_stage=2
	session.data.known_relics=["spiral-idol","crystal-eye"]
	session.data.magic=16
	var before := session.data.duplicate(true)
	check(not session.summon(rules,"test","world") and session.data==before,"Insufficient magic never changes inventory, layout or balance")
	session.data.magic=17
	var rng := RandomNumberGenerator.new()
	rng.seed=123456
	var writable_path: String = session.save_path
	session.save_path="res://project.godot/blocked.json"
	before=session.data.duplicate(true)
	check(not session.summon(rules,"test","world",rng) and session.data==before,"Save failure rolls back exact-priced summon and generated units")
	session.save_path=writable_path
	check(session.summon(rules,"test","world",rng) and session.data.magic==0 and session.data.last_summon.cost==17,"Exact balance permits summon and deducts preview price once")
	var restored := SESSION.new()
	restored.save_path=session.save_path
	check(restored.load_save() and restored.data.magic==0 and restored.data.last_summon.cost==17,"Charged cost survives reload without recharging")
	for id: String in PAYMENTS:
		for field: String in PAYMENTS[id]:
			check(CATALOG.parameters()[id][field]==PAYMENTS[id][field],"Confirmed fixed payment "+id+"."+field)
	check(CATALOG.validate().is_empty(),"Updated production parameters remain valid")
	check(CATALOG.parameters()["QST_GRASS_010"].attack_threshold==null and CATALOG.parameters()["QST_GRASS_020"].loss_policy==null,"Unrelated thresholds and gambling policy stay pending")
	var invalid := {"battle_id":"test","outcome":"victory","reward":20,"parts":{},"magic_reward_pending":true,"reward_basis":"monster_level"}
	check(not session._valid_result(invalid),"Pending level loot cannot secretly pay old flat twenty")
	invalid.reward=0
	check(session._valid_result(invalid),"Pending loot uses zero transport amount, not null in the save protocol")
	print("DEMO_MAGIC_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
