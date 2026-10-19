extends SceneTree
## Independent framework regression. No invented GameSession quest API or production rewards.
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const DEFINITION = preload("res://Scripts/Quests/QuestDefinition.gd")
const OBJECTIVE = preload("res://Scripts/Quests/QuestObjectiveData.gd")
const SERVICE = preload("res://Scripts/Quests/QuestService.gd")
const EXAMPLE = preload("res://Resources/Quests/Examples/FirstVictory.tres")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("QUEST_FRAMEWORK_FAIL: "+label)

func definitions() -> Array:
	var visit := OBJECTIVE.new()
	visit.id=&"visit"; visit.event_key=&"map.visited"; visit.target_id=&"camp"; visit.required_count=2
	var ready := OBJECTIVE.new()
	ready.id=&"ready"; ready.event_key=&"party.ready"; ready.required_count=2
	ready.count_mode=OBJECTIVE.CountMode.MAXIMUM; ready.count_history=true
	var first := DEFINITION.new()
	first.id=&"first"; first.objectives=[visit,ready]; first.reward_magic=15; first.reward_rune_ids=[&"health"]
	var followup: DEFINITION = EXAMPLE.duplicate(true)
	followup.prerequisite_ids.assign([&"first"]); followup.auto_accept=false
	return [first,followup]

func event(key: String, id: String, target := "", amount := 1, history := false) -> Dictionary:
	return {"event_key":key,"event_id":id,"target_id":target,"amount":amount,"historical":history}

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	var session := SESSION.new()
	var untouched := session.data.duplicate(true)
	var service := SERVICE.new()
	check(service.configure(definitions()).is_empty(),"Valid definitions configure independent service")
	var state := SERVICE.empty_state()
	service.synchronize(state)
	check(service.view(state,"first").state=="active" and service.view(state,str(EXAMPLE.id)).state=="locked","Auto-accept and prerequisite locks")
	check(service.view(state,"missing").is_empty(),"Unknown quest returns no mutable placeholder")
	check(not service.accept(state,str(EXAMPLE.id)).is_empty(),"Locked quest cannot be accepted")
	check(not service.apply_events(state,[event("map.visited","wrong","town")]),"Unmatched target does not count")
	check(not service.apply_events(state,[event("map.visited","old","camp",2,true)]),"History requires explicit opt-in")
	check(service.apply_events(state,[event("map.visited","visit1","camp")]),"Matching event counts")
	var before := state.duplicate(true)
	check(not service.apply_events(state,[event("map.visited","visit1","camp")]) and state==before,"Repeated receipt is idempotent")
	check(service.apply_events(state,[event("map.visited","visit2","camp")]) and service.view(state,"first").state=="active","All objectives are required")
	check(service.apply_events(state,[event("party.ready","ready","",2,true)]) and service.view(state,"first").state=="completed","Opt-in historical maximum completes objective")
	check(service.view(state,str(EXAMPLE.id)).state=="available","Completed predecessor unlocks manual follow-up")
	var view: Dictionary = service.view(state,"first")
	view.objectives[0].count=999
	check(service.view(state,"first").objectives[0].count==2,"Read model cannot mutate stored progress")
	check(not service.apply_events(state,[event("battle.victory","early")]),"Unaccepted follow-up ignores event")
	check(service.accept(state,str(EXAMPLE.id)).is_empty(),"Manual acceptance")
	check(service.apply_events(state,[event("battle.victory","battle")]) and service.view(state,str(EXAMPLE.id)).state=="completed","Accepted follow-up progresses")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(SERVICE.valid_state(restored) and not service.apply_events(restored,[event("battle.victory","battle")]),"JSON roundtrip retains receipt and completion")
	var registry: Dictionary = service.definitions.duplicate()
	var bad := definitions()
	bad[0].prerequisite_ids.assign([EXAMPLE.id])
	check(not service.configure(bad).is_empty() and service.definitions==registry,"Cyclic configuration is rejected without replacing registry")
	check(not service.configure([false]).is_empty(),"Invalid resource element rejected")
	check(not SERVICE.valid_events([false]) and not SERVICE.valid_events([event("event","id","",-1)]),"Malformed event batches rejected")
	var corrupt := restored.duplicate(true)
	corrupt.entries.first.objectives.visit.count="invalid"
	check(not SERVICE.valid_state(corrupt),"Corrupt saved objective rejected")
	check(service.configure([]).is_empty(),"Removing definitions is supported")
	service.synchronize(restored)
	check(restored.entries.has("first"),"Unconfigured progress is preserved")
	check(service.configure(definitions()).is_empty(),"Definitions can be restored")
	service.synchronize(restored)
	check(service.view(restored,"first").state=="completed","Restoring definition preserves progress")
	var one := DEFINITION.new()
	one.id=&"one"
	var goal := OBJECTIVE.new()
	goal.id=&"goal"; goal.event_key=&"shared"
	one.objectives=[goal]
	var two: DEFINITION = one.duplicate(true)
	two.id=&"two"; two.prerequisite_ids.assign([&"one"])
	check(service.configure([one,two]).is_empty(),"Shared-event dependency chain configures")
	state=SERVICE.empty_state()
	service.synchronize(state)
	service.apply_events(state,[event("shared","receipt")])
	check(service.view(state,"one").state=="completed" and service.view(state,"two").state=="active","One receipt cannot finish newly unlocked successor")
	check(not service.apply_events(state,[event("shared","receipt")]) and service.view(state,"two").state=="active","Receipt replay cannot bypass dependency")
	check(service.apply_events(state,[event("shared","next")]) and service.view(state,"two").state=="completed","New receipt advances successor")
	check(session.data==untouched,"Standalone framework never changes real session economy, inventory or story state")
	print("QUEST_FRAMEWORK_PASSED" if failures==0 else "QUEST_FRAMEWORK_FAILED"," checks=",checks," failures=",failures)
	quit(1 if failures else 0)
