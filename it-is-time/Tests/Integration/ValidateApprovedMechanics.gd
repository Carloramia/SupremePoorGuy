extends SceneTree
const SESSION=preload("res://Scripts/Application/GameSession.gd")
const HEX=preload("res://Scripts/Events/HexMapProgress.gd")
const RULES=preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
var checks:=0
var failed:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failed=true; push_error(label)
func fixture() -> RefCounted:
	var s:=SESSION.new(); s.save_path="res://Tests/.runtime/mechanics_%d.json"%Time.get_ticks_usec()
	s.data.hex_map=HEX.initial(); s.data.magic=10000
	s.data.array_stage=3; s.data.layout.stage=3
	s.data.known_relics=RULES.RELICS.map(func(item):return item.id)
	return s
func summon(s: RefCounted,relic: String="",seed_value: int=1234) -> void:
	var rules:=RULES.new(); rules.stage=3
	check(rules.import_layout({"version":3,"stage":3,"placed":[{"uid":"health","runeId":"health","cells":[[-1,0],[0,0],[1,0]],"enabled":true}],"placedRelics":[]}),"Load actual valid rune arrangement")
	if not relic.is_empty(): check(rules.place_relic(relic,[-1,2]),"Place actual relic "+relic)
	var rng:=RandomNumberGenerator.new(); rng.seed=seed_value
	check(s.summon(rules,"hex_frontier_20261019","world",rng),"Actual summon "+relic+" "+s.last_error)
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	var s:=fixture()
	check(s.save_hex_world(s.data.hex_map.duplicate(true)),"Initialize host clock")
	var snapshot: Dictionary=s.data.hex_map.duplicate(true); snapshot.travel_distance+=2400
	check(s.save_hex_world(snapshot) and is_equal_approx(s.data.story_events.clock.day,2),"2400 real travel units advance exactly one day")
	check(s.save_hex_world(snapshot) and is_equal_approx(s.data.story_events.clock.day,2),"Saving unchanged distance advances no time")
	var dry:=fixture(); summon(dry)
	var rain:=fixture()
	for site: Dictionary in HEX.document().sites:
		if site.id=="layout_red_altar": rain.data.hex_map.player=site.position.duplicate(); break
	rain.data.story_weather={"permanent":true,"expires_day":0}
	check(HEX.rain_active(rain.data),"Rain active inside authored altar hex range")
	summon(rain)
	for i in dry.data.monsters.size():
		check(dry.data.monsters[i].definition_id==rain.data.monsters[i].definition_id and is_equal_approx(rain.data.monsters[i].hp,dry.data.monsters[i].hp*1.1),"Blood rain changes actual summoned physical HP by ten percent")
	rain.data.story_weather={"permanent":false,"expires_day":2}
	check(rain.set_story_game_day(2) and not HEX.rain_active(rain.data),"Rain expires at authoritative day")
	for case: Array in [["giant-tusk","attack",1.15],["crystal-carapace","armor",1.2]]:
		var boosted:=fixture(); summon(boosted,case[0])
		for i in dry.data.monsters.size(): check(is_equal_approx(boosted.data.monsters[i][case[1]],dry.data.monsters[i][case[1]]*case[2]),"Relic changes real "+case[1])
	var eye:=fixture(); summon(eye,"crystal-eye",8)
	check(eye.data.monsters.all(func(unit):return unit.magic_eye is bool and eye.FACTORY.valid_record(unit)),"Eye roll persists on valid physical records")
	check(eye.data.monsters.any(func(unit):return unit.magic_eye),"Seeded real summon grants an actual magic-eye ability")
	print("APPROVED_MECHANICS_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
