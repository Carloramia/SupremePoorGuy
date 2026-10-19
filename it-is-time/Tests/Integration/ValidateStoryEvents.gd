extends SceneTree
const SERVICE = preload("res://Scripts/Events/StoryEventService.gd")
const SESSION = preload("res://Scripts/Application/GameSession.gd")
var checks := 0
var failures := 0
var service := SERVICE.new()

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func fixture() -> Dictionary:
	return {"magic":1000,"array_stage":1,"monsters":[],"pending":[],"last_summon":{},"serial":0,"worlds":{},"battle_results":{}}

func configured() -> void:
	for key: String in service.config.bindings.rewards:
		service.config.bindings.rewards[key] = {"magic":3,"runes":[],"relics":[]}
	for key: String in service.config.bindings.battles:
		service.config.bindings.battles[key] = {"battle_map_id":"test_map","enemy_config_id":"authored_test","other_side":{"battle_map_id":"test_map","enemy_config_id":"other"}}
	service.config.bindings.attack_threshold = 10
	service.config.bindings.engine_max_stage = 3
	service.config.bindings.monster_fields = {"attack":"attack","large":"large","fur":"fur","flying":"flying","snake":"snake","hands":"hands","feet":"feet"}

func open_event(d: Dictionary, id: String, entrance: String) -> String:
	var result := service.open(d,id,entrance,true)
	check(result.ok,"Open "+id+" "+entrance)
	return result.get("event",{}).get("conversation","")

func receipt(r: Dictionary, outcome: String = "success") -> Dictionary:
	var result := {"request_id":r.request_id,"event_id":r.event_id,"stage":r.stage,"branch":r.branch,"kind":r.kind,"outcome":outcome,"committed":true}
	if r.has("battle_id"): result["battle_id"] = r.battle_id
	return result

func commit_pending(d: Dictionary, id: String) -> void:
	check(service.commit_receipt(d,receipt(service.pending_request(d,id))).is_empty(),"Commit "+id)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	for key: String in service.config.bindings.rewards: service.config.bindings.rewards[key]=null
	for key: String in service.config.bindings.battles: service.config.bindings.battles[key]=null
	for round_data: Dictionary in service.config.bindings.bet_rounds: round_data.one=null; round_data.two=null
	service.config.bindings.approved_failure_rules=false
	service.config.bindings.bet_draw_policy=null
	service.config.bindings.bet_abort_policy=null
	service.config.bindings.bet_loss_policy=null
	service.definitions.QST_GRASS_016.operations.away.next="await_policy"
	check(service.definitions.size()==20,"Exactly 20 distinct story events, no auxiliary entries counted")
	check(SERVICE.valid_progress(fixture()),"Legacy save accepted without fabricating event progress")
	var d := fixture()
	var before := d.duplicate(true)
	check(service.ready_events(d,true).is_empty() and d==before,"Readiness query does not mutate save")
	for id: String in service.definitions:
		var definition: Dictionary = service.definitions[id]
		check(not service.open(d,id,definition.entries[0],false).ok,"Unsafe phase cannot open "+id)
	var id := "QST_GRASS_013"
	var c := open_event(d,id,"well")
	check(not service.act(d,id,"record",c).ok,"Unconfigured reward blocks action")
	check(not service.entry(d,id).completed,"Missing reward never treated as zero-reward success")
	configured()
	check(not service.act(d,id,"record","stale").ok,"Stale dialogue callback rejected")
	var action := service.act(d,id,"record",c)
	check(action.ok,"Configured record creates request")
	var r: Dictionary = action.request
	check(service.act(d,id,"record",c).request==r,"Repeat action reuses persistent request")
	var wrong := receipt(r)
	wrong.branch = "leave"
	check(not service.commit_receipt(d,wrong).is_empty(),"Wrong branch receipt rejected")
	commit_pending(d,id)
	before = d.duplicate(true)
	check(service.commit_receipt(d,receipt(r)).is_empty() and d==before,"Exact duplicate receipt is a no-op")
	check(not service.open(d,id,"well",true).ok,"Completed event cannot reopen")
	_test_dialogue_and_routes()
	_test_battles()
	_test_clock()
	_test_inventory()
	_test_bets()
	_test_remaining_events()
	_test_session()
	print("STORY_EVENTS_", "PASSED" if failures==0 else "FAILED", " checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func _test_dialogue_and_routes() -> void:
	for order: Array in [["donkey","merchant"],["merchant","donkey"]]:
		var d := fixture()
		var id := "QST_GRASS_007"
		var c := open_event(d,id,order[0])
		check(not service.act(d,id,"from_"+order[0],c).ok,"One node alone cannot return donkey")
		c = open_event(d,id,order[1])
		check(service.act(d,id,"from_"+order[1],c).ok,"Both discovery orders share return transaction")
		check(service.entry(d,id).stage=="return_dialogue" and service.pending_request(d,id).is_empty(),"Choosing return route cannot skip shared return dialogue")
		check(service.act(d,id,"return_dialogue",c).ok,"Specified return dialogue ends before rewarding")
		commit_pending(d,id)
		check(service.entry(d,id).completed,"Return dialogue completes without escort")
	var d := fixture()
	var id := "QST_GRASS_012"
	var c := open_event(d,id,"farm")
	check(service.act(d,id,"ask",c).ok,"Accept return-to-city route")
	service.act(d,id,"leave",c)
	c = open_event(d,id,"farm")
	check(not service.act(d,id,"direct",c).ok,"Leaving and revisiting cannot unlock direct route")
	check(not service.act(d,id,"enchanter",c).ok,"Farm cannot fake enchanter visit")
	c = open_event(d,id,"enchanter")
	check(service.act(d,id,"enchanter",c).ok,"City entrance permits hand-in")
	commit_pending(d,id)
	id = "QST_GRASS_005"
	c = open_event(d,id,"shepherd")
	check(service.act(d,id,"leave",c).ok and not service.entry(d,id).completed,"Closing dialogue is not completion")
	c = open_event(d,id,"shepherd")
	check(service.act(d,id,"talk",c).ok and service.entry(d,id).completed,"Rumor records specified dialogue completion only")
	for branch: String in ["funny","kind"]:
		d = fixture()
		service.entry(d,"QST_GRASS_015").triggered = true
		c = open_event(d,"QST_GRASS_015","ghost")
		check(service.act(d,"QST_GRASS_015",branch,c).ok,"Ghost answer joins shared teach stage")
		check(service.act(d,"QST_GRASS_015","teach",c).ok,"Ghost shared reward request")
		commit_pending(d,"QST_GRASS_015")

func _test_battles() -> void:
	var d := fixture()
	d.monsters = [{"id":"team","position":"team"}]
	var id := "QST_GRASS_006"
	var c := open_event(d,id,"tower")
	check(not service.act(d,id,"battle",c).ok,"Wolf fight cannot precede pickup")
	check(service.act(d,id,"pickup",c).ok,"Pickup has independent request")
	commit_pending(d,id)
	var pickup_receipts: int = d.story_events.receipts.size()
	check(service.act(d,id,"battle",c).ok,"Pickup persistence unlocks wolf fight")
	var r := service.pending_request(d,id)
	var wrong := receipt(r,"victory")
	wrong.battle_id = "old_battle"
	check(not service.commit_receipt(d,wrong).is_empty(),"Old battle cannot advance current encounter")
	check(service.commit_receipt(d,receipt(r,"defeat")).is_empty(),"Actual wolf defeat recorded separately")
	check(d.story_events.receipts.size()==pickup_receipts+1 and service.entry(d,id).stage=="await_policy","Defeat keeps pickup receipt, unresolved failure policy blocks replay")
	id = "QST_SIDE_002_001"
	c = open_event(d,id,"center")
	check(service.act(d,id,"accept",c).ok,"Accept defense commission")
	check(not service.act(d,id,"submit",c).ok,"Generic victories cannot satisfy defense commission")
	c = open_event(d,id,"defense_target")
	check(service.act(d,id,"battle",c).ok,"Start designated defense battle")
	check(service.commit_receipt(d,receipt(service.pending_request(d,id),"victory")).is_empty(),"Matching defense victory persists objective")
	check(not service.act(d,id,"submit",c).ok,"Winning at target cannot hand in remotely")
	c = open_event(d,id,"center")
	check(service.act(d,id,"submit",c).ok,"Return to lord permits reward transaction")
	commit_pending(d,id)
	for outcome: String in ["defeat","retreat","load_failed","interrupted"]:
		var copy := fixture()
		copy.monsters = [{"id":"team","position":"team"}]
		c = open_event(copy,"QST_GRASS_008","giant")
		check(service.act(copy,"QST_GRASS_008","battle",c).ok,"Start giant battle")
		r = service.pending_request(copy,"QST_GRASS_008")
		check(service.commit_receipt(copy,receipt(r,outcome)).is_empty() and not service.entry(copy,"QST_GRASS_008").completed,"Nonvictory gives no giant reward: "+outcome)
	var spectator := fixture()
	c = open_event(spectator,"QST_GRASS_019","clash")
	check(service.act(spectator,"QST_GRASS_019","watch",c).ok,"AI spectating does not require player party")
	r = service.pending_request(spectator,"QST_GRASS_019")
	check(not service.commit_receipt(spectator,receipt(r,"victory")).is_empty(),"Spectating cannot infer winner from player victory")
	var result := receipt(r,"victory")
	result["winner"] = "two"
	check(service.commit_receipt(spectator,result).is_empty() and not service.entry(spectator,"QST_GRASS_019").completed,"Spectator outcome waits for real reward settlement")
	commit_pending(spectator,"QST_GRASS_019")

func _test_clock() -> void:
	var d := fixture()
	var c := open_event(d,"QST_GRASS_014","engine")
	check(not service.act(d,"QST_GRASS_014","buy",c).ok,"Missing authority clock blocks purchase timing")
	check(service.set_game_day(d,2.5).is_empty(),"Authority clock accepts fractional game day")
	check(service.act(d,"QST_GRASS_014","buy",c).ok,"Purchase creates atomic money/upgrade request")
	check(service.ready_events(d,true).is_empty(),"Purchase intent does not start timer")
	commit_pending(d,"QST_GRASS_014")
	check(service.entry(d,"QST_GRASS_014").due_day==6.5,"Due day is 4 days from committed purchase")
	service.set_game_day(d,6.49)
	check(service.ready_events(d,true).is_empty(),"Ghost not early")
	service.set_game_day(d,10.0)
	check(service.ready_events(d,false).is_empty() and service.ready_events(d,true)==["QST_GRASS_015"],"Multi-day skip queues once, unsafe phase defers presentation")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(d))
	service.reconcile(restored)
	check(service.ready_events(restored,true)==["QST_GRASS_015"],"Load preserves due queue, no timer restart")
	open_event(restored,"QST_GRASS_015","ghost")
	service.reconcile(restored)
	check(service.ready_events(restored,true).is_empty(),"Acknowledged presentation is not queued twice")
	check(not service.set_game_day(restored,1.0).is_empty(),"Clock cannot move backwards")
	check(SERVICE.valid_progress(restored),"Clock/progression survives JSON serialization")

func _test_inventory() -> void:
	var d := fixture()
	d.monsters = [{"id":"low","position":"team","attack":6,"large":false},{"id":"high","position":"warehouse","attack":10,"fur":true,"flying":true,"snake":true,"hands":0,"feet":0}]
	var c := open_event(d,"QST_GRASS_010","temple")
	check(not service.act(d,"QST_GRASS_010","break",c).ok,"Equality to threshold and summed attack do not pass")
	d.monsters[1].attack = 11
	check(service.act(d,"QST_GRASS_010","break",c).ok,"Single qualifying warehouse monster passes")
	c = open_event(d,"QST_GRASS_011","mine")
	d.monsters[0].large = true
	check(not service.act(d,"QST_GRASS_011","enter",c).ok and d.monsters.size()==2,"Large unit is rejected without deleting it")
	d.monsters[0].large = false
	check(service.act(d,"QST_GRASS_011","enter",c).ok,"Small nonempty party enters mine")
	var id := "QST_SIDE_003_001"
	c = open_event(d,id,"altar")
	check(service.view(d,id).branches==["first"],"Only first sacrifice requirement exposed")
	check(not service.act(d,id,"second",c,{"monster_ids":["low","high"],"confirmed":true}).ok,"Future stage cannot be submitted")
	check(not service.act(d,id,"first",c,{"monster_ids":["high"]}).ok,"Sacrifice requires explicit irreversible confirmation")
	check(service.act(d,id,"first",c,{"monster_ids":["high"],"confirmed":true}).ok,"Stage one checks fur without length condition")
	check(service.view(d,id).branches.is_empty(),"Pending reward exposes no next stage")
	var r := service.pending_request(d,id)
	var failed := receipt(r)
	failed.committed = false
	check(not service.commit_receipt(d,failed).is_empty() and service.entry(d,id).stage=="available","Failed reward cannot reveal second stage")
	commit_pending(d,id)
	check(service.view(d,id).branches==["second"],"Reward success reveals second stage")
	check(not service.act(d,id,"second",c,{"monster_ids":["high","high"],"confirmed":true}).ok,"Same instance cannot fill two sacrifice slots")
	check(not service.act(d,id,"second",c,{"monster_ids":["low","high"],"confirmed":true}).ok,"Cannot sacrifice all owned monsters")
	for i: int in 4:
		d.monsters.append({"id":"s"+str(i),"position":"warehouse","flying":true,"snake":true,"hands":0,"feet":0})
	check(service.act(d,id,"second",c,{"monster_ids":["s0","s1"],"confirmed":true}).ok,"Two flying instances accepted")
	commit_pending(d,id)
	check(service.view(d,id).branches==["third"],"Third stage revealed only after second reward")
	d.monsters[2].hands = 1
	check(not service.act(d,id,"third",c,{"monster_ids":["s0","s1","s2"],"confirmed":true}).ok,"Snake with a hand rejected")
	d.monsters[2].hands = 0
	check(service.act(d,id,"third",c,{"monster_ids":["s0","s1","s2"],"confirmed":true}).ok,"Three limbless snakes accepted")
	commit_pending(d,id)
	check(service.entry(d,id).completed,"Third reward completes sacrifice")

func _test_bets() -> void:
	var d := fixture()
	var id := "QST_GRASS_020"
	var c := open_event(d,id,"knight")
	check(not service.act(d,id,"one",c).ok,"Unconfirmed accounting blocks wager")
	service.config.bindings.bet_loss_policy = "lose_stake"
	service.config.bindings.bet_draw_policy = "hold_for_resolution"
	service.config.bindings.bet_abort_policy = "hold_for_resolution"
	check(not service.act(d,id,"one",c).ok,"Missing hand-authored rosters blocks wager")
	for round_data: Dictionary in service.config.bindings.bet_rounds:
		round_data.one = {"battle_map_id":"test_map","enemy_config_id":"one"}
		round_data.two = {"battle_map_id":"test_map","enemy_config_id":"two"}
	for round_index: int in 4:
		check(service.act(d,id,"one",c).ok,"Lock wager round "+str(round_index+1))
		var r := service.pending_request(d,id)
		check(r.kind=="bet" and not r.has("battle_id") and r.plan.stake==[10,20,50,100][round_index],"Deduction transaction must precede actual AI battle")
		commit_pending(d,id)
		r = service.pending_request(d,id)
		check(r.kind=="spectator","Committed stake starts actual spectator request")
		check(not service.commit_receipt(d,receipt(r,"draw")).is_empty() and service.entry(d,id).rounds==round_index,"Draw keeps unresolved original wager and count")
		var result := receipt(r,"victory")
		result["winner"] = "one" if round_index%2==0 else "two"
		check(service.commit_receipt(d,result).is_empty(),"Actual spectator winner creates settlement request")
		r = service.pending_request(d,id)
		check(service.entry(d,id).rounds==round_index,"Battle result alone never consumes round")
		check(r.plan.reward.magic==(int(r.plan.stake)*2 if round_index%2==0 else 0),"Winning payout includes stake exactly once; loss payout zero")
		commit_pending(d,id)
		check(service.entry(d,id).rounds==round_index+1,"Only successful accounting advances round")
	check(service.entry(d,id).completed and not service.open(d,id,"knight",true).ok,"Fourth settlement permanently closes knight entrance")

func _test_session() -> void:
	var session := SESSION.new()
	session.story_events.config = service.config.duplicate(true)
	session.save_path = "res://Tests/.runtime/story_events/session_%d.json" % Time.get_ticks_usec()
	check(session.save(),"Real session persists additive state")
	var id := "QST_GRASS_013"
	var opened: Dictionary = session.open_story_event(id,"well",true)
	check(opened.ok,"Real session opens event")
	check(session.story_event_action(id,"record",opened.event.conversation).ok,"Real session saves request before resource effects")
	var r: Dictionary = session.pending_story_request(id)
	var ack := receipt(r)
	check(not session.commit_story_receipt(ack),"UI receipt without resource adapter cannot finish event")
	var before: Dictionary = session.data.duplicate(true)
	var path: String = session.save_path
	session.save_path += "/blocked.json"
	var reward := func(state: Dictionary, request: Dictionary) -> String:
		state.magic += int(request.plan.reward.magic)
		return ""
	check(not session.commit_story_receipt(ack,reward) and session.data==before,"Save failure atomically rolls back money, event and receipt")
	session.save_path = path
	check(session.commit_story_receipt(ack,reward),"Same durable request can retry after rollback")
	var money: float = session.data.magic
	check(session.commit_story_receipt(ack,reward) and session.data.magic==money,"Repeated ack does not rerun resource adapter")
	var reloaded := SESSION.new()
	reloaded.save_path = path
	check(reloaded.load_save() and reloaded.story_event_view(id).completed,"Actual session reload preserves completed event")
	check(reloaded.set_story_game_day(5) and not reloaded.set_story_game_day(4),"Session authoritative clock persists and rejects rollback")
	var bad: Dictionary = reloaded.data.duplicate(true)
	bad.story_events.sequence = -1
	check(not reloaded._valid_save(bad),"Malformed event save cannot overwrite valid slot")
	check(session.record_story_arrival("QST_GRASS_007","donkey"),"Verified-arrival adapter records node discovery")
	check(not session.record_story_arrival("QST_GRASS_007","wrong"),"Unbound entrance rejected")
	var invalid := service.config.duplicate(true)
	invalid.events[1].id = invalid.events[0].id
	check(not session.story_events.configure(invalid).is_empty(),"Duplicate config ID rejected without replacing active catalog")

func _test_remaining_events() -> void:
	for pair: Array in [["QST_MAIN_001_001","opening","read"],["QST_SIDE_001_001","library","talk"],["QST_GRASS_009","cart","read"],["QST_GRASS_017","bridge","wood"]]:
		var d := fixture()
		var c := open_event(d,pair[0],pair[1])
		check(service.act(d,pair[0],pair[2],c).ok,"Configured explicit dialogue completion creates transaction: "+pair[0])
		commit_pending(d,pair[0])
		check(service.entry(d,pair[0]).completed,"Transaction completes: "+pair[0])
	var d := fixture()
	d.monsters = [{"id":"team","position":"team"}]
	var c := open_event(d,"QST_GRASS_016","circus")
	check(service.act(d,"QST_GRASS_016","away",c).ok,"Retreat causes no eyeball reward or extra creature")
	check(service.entry(d,"QST_GRASS_016").stage=="await_policy" and not service.open(d,"QST_GRASS_016","circus",true).ok,"Unconfirmed revisit rule is blocked")
	d = fixture()
	check(not service.open(d,"QST_GRASS_002","tree",true).ok,"Tree guard cannot open before successful settled summon")
	d.serial = 1
	d.last_summon = {"succeeded":1}
	d.monsters = [{"id":"team","position":"team"}]
	service.reconcile(d,false)
	check(service.ready_events(d,true).is_empty(),"Summon itself does not replace world-enter notification")
	service.reconcile(d,true)
	check(service.ready_events(d,true)==["QST_GRASS_002"],"World entry after settled summon and party queues tree guard")
	c = open_event(d,"QST_GRASS_002","tree")
	check(service.act(d,"QST_GRASS_002","battle",c).ok,"Tree guard request remains explicit while opening presentation is unbound")
	var r := service.pending_request(d,"QST_GRASS_002")
	check(service.commit_receipt(d,receipt(r,"victory")).is_empty(),"Matched tree victory advances to pending postbattle settlement")
	commit_pending(d,"QST_GRASS_002")
	d = fixture()
	d.monsters = [{"id":"fur","position":"warehouse","fur":true},{"id":"last","position":"team"}]
	c = open_event(d,"QST_SIDE_003_001","altar")
	check(service.act(d,"QST_SIDE_003_001","first",c,{"monster_ids":["fur"],"confirmed":true}).ok,"Create sacrifice with separable persistent consumption")
	r = service.pending_request(d,"QST_SIDE_003_001")
	check(service.commit_receipt(d,receipt(r,"consumed")).is_empty(),"Consumption receipt records reward-only request without stage reveal")
	d.monsters.remove_at(0)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(d))
	r = service.pending_request(restored,"QST_SIDE_003_001")
	check(r.kind=="transaction" and r.plan.consumed_ids==["fur"] and service.revalidate_operation(restored,r).is_empty(),"Reload retries only pending reward; never consumes nonexistent instance again")
	check(service.entry(restored,"QST_SIDE_003_001").stage=="available" and service.view(restored,"QST_SIDE_003_001").branches.is_empty(),"Consumed-but-unrewarded stage stays hidden from next requirement")
	commit_pending(restored,"QST_SIDE_003_001")
	check(service.entry(restored,"QST_SIDE_003_001").stage=="stage_2","Only reward acknowledgement advances recovered sacrifice")
