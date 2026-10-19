extends SceneTree

const CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var checks := 0
var failed := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("SNAKE_SHARE_CHECK ",ok," ",message)
	failed = failed or not ok

func reset_hp(actor: Node3D) -> void:
	for part: PhysicalBodyPart3D in actor._get_physical_body_parts():
		if part.is_broken: continue
		part.max_hp = 1000.0
		part.current_hp = 1000.0

func torsos(actor: Node3D) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = actor.get_body_parts_with_tag(PhysicalBodyPart3D.BodyPartTag.Torso)
	result.sort_custom(func(a,b): return str(a.get_meta(&"generated_part_key")).naturalnocasecmp_to(str(b.get_meta(&"generated_part_key"))) < 0)
	return result

func check_shares(parts: Array[RigidBody3D], expected: Array, label: String) -> void:
	var valid := true
	for index: int in parts.size():
		valid = valid and is_equal_approx(1000.0-parts[index].current_hp, float(expected[index]) if index<expected.size() else 0.0)
	check(valid,label)

func validate_actor(actor: Node3D) -> void:
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	for body: RigidBody3D in actor._get_physical_body_parts(): body.freeze = true
	await process_frame
	await process_frame
	reset_hp(actor)
	var parts := torsos(actor)
	check(parts.size()>4,"Fixture has a real ordered Snake spine: "+str(actor.name))
	var target := parts[3] as PhysicalBodyPart3D
	var events := [0.0,null]
	for part: PhysicalBodyPart3D in parts:
		part.damaged.connect(func(amount,hp,source): events[0] += amount; events[1] = source)
	check(is_equal_approx(target.apply_damage(100.0,actor),100.0),"Return the whole settled hit, including transferred shares")
	check_shares(parts,[72.9,8.1,9.0,10.0],"Retain 10 percent at each segment and deliver the remainder to the tail")
	check(is_equal_approx(events[0],100.0) and events[1]==actor,"Existing damage signals preserve the original source and total")
	reset_hp(actor)
	actor.rotation.y = PI
	check(is_equal_approx(target.apply_damage(100.0),100.0),"Damage settles after turning")
	check_shares(parts,[72.9,8.1,9.0,10.0],"Turning and the S pose cannot reverse tailward propagation")
	reset_hp(actor)
	check(is_equal_approx(parts[0].apply_damage(100.0),100.0),"A hit on the tail is fully local")
	check_shares(parts,[100.0],"Tail damage does not travel toward the head")
	reset_hp(actor)
	var head: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Head")
	check(is_equal_approx(head.apply_damage(100.0),100.0) and head.current_hp==900.0,"Head damage remains local")
	check_shares(parts,[],"Head damage does not enter the Torso chain")
	reset_hp(actor)
	target.set_meta(&"summon_presentation",true)
	check(target.apply_damage(100.0)==0.0,"Summon presentation still ignores damage")
	check_shares(parts,[],"Presentation never damages downstream parts")
	target.remove_meta(&"summon_presentation")
	check(target.apply_damage(0.0)==0.0 and target.apply_damage(-10.0)==0.0,"Nonpositive hits do not propagate")
	reset_hp(actor)
	target.armor = 10.0
	target.resilience = 100.0
	for part: PhysicalBodyPart3D in parts:
		if part!=target: part.armor = 10000.0; part.resilience = 10000.0
	var weapon := SampleWeapon3D.new()
	weapon.freeze = true
	root.add_child(weapon)
	weapon.begin_damage_swing({"id":-1,"mass":8.0,"multiplier":1.0,"hits":{}})
	var hit: float = weapon.apply_contact_damage(target,3.0)
	check(is_equal_approx(hit,25.0),"Real weapon applies resilience and armor once before sharing")
	check_shares(parts,[18.225,2.025,2.25,2.5],"Downstream armor does not reduce the same hit a second time")
	check(weapon.apply_contact_damage(target,3.0)==0.0,"The original per-action hit deduplication remains effective")
	weapon.free()
	reset_hp(actor)
	parts[0].current_hp = 3.0
	check(is_equal_approx(target.apply_damage(100.0),30.1),"Return actual HP loss when tail health is exhausted")
	await process_frame
	await process_frame
	check(parts[0].is_broken and not target.is_broken and not head.is_broken,"Tail destruction retains the connected front body and existing Broken logic")
	parts[1].break_part()
	await process_frame
	await process_frame
	reset_hp(actor)
	check(is_equal_approx(target.apply_damage(100.0),100.0),"Remaining connected front chain still receives damage")
	check(parts[0].current_hp==0.0 and parts[1].current_hp==0.0 and is_equal_approx(parts[2].current_hp,910.0) and is_equal_approx(target.current_hp,990.0),"A broken segment stops transfer; the last connected living segment absorbs the remainder")
	reset_hp(actor)
	for joint: Node in actor.get_body_connections():
		if joint is Joint3D and joint.get_meta(&"generated_connection_kind","")=="SnakeSpine" and joint.get_node_or_null(joint.node_b)==target:
			joint.queue_free()
	check(is_equal_approx(target.apply_damage(100.0),100.0) and target.current_hp==900.0 and parts[2].current_hp==1000.0,"Queued joint deletion stops propagation immediately instead of jumping a gap")
	actor.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var audio := root.get_node("CombatAudio")
	audio.settings = audio.settings.duplicate()
	audio.settings.enabled = false
	for path: String in ["res://Scenes/Creatures/Characters/Generate_Snake.tscn","res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn"]:
		var actor: Node3D = load(path).instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		await validate_actor(actor)
	var record := FACTORY.template("snake")
	record.merge({"id":"snake_damage_share","position":"team","traits":[]},true)
	var host := Node3D.new()
	root.add_child(host)
	var deployed := FACTORY.spawn(record,host,Vector3.ZERO,1)
	check(CONTEXT.character_of(deployed.get_node("GeneratedParts/Torso_004"))==deployed,"Production factory preserves Snake ownership")
	await validate_actor(deployed)
	host.queue_free()
	FACTORY._release_presentation_parts()
	await process_frame
	print("SNAKE_DAMAGE_SHARING_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
