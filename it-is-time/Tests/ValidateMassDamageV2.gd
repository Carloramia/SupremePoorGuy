extends SceneTree
const RULES = preload("res://Resources/Damage/DefaultDamageRules.tres")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const SESSION = preload("res://Scripts/Application/GameSession.gd")
var checks := 0
var failed := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func fixture(team: int, masses: Array) -> Node3D:
	var actor := Node3D.new()
	actor.set_script(CHARACTER)
	actor.faction_id = team
	actor.require_head_and_torso_connectivity = false
	for i: int in masses.size():
		var part := PhysicalBodyPart3D.new()
		part.name = "Torso"+str(i)
		part.mass = masses[i]
		part.tags = [PhysicalBodyPart3D.BodyPartTag.Torso]
		part.freeze = true
		part.damage_number_scene = null
		var sprite := Sprite3D.new()
		sprite.name = "Sprite3D"
		part.add_child(sprite)
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		shape.shape = BoxShape3D.new()
		part.add_child(shape)
		actor.add_child(part)
	root.add_child(actor)
	return actor

func run() -> void:
	var service: Node = root.get_node("DamageService")
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var host := Node3D.new()
	root.add_child(host)
	check(RULES.base_attack_damage == 35.0 and RULES.hp_per_mass == 40.0,"Global coefficients")
	for row: Array in [["res://Resources/Attacks/WolfBite.tres",1.01251955],["res://Resources/Attacks/SnakeBite.tres",0.30141956],["res://Resources/Actions/StumpBeastForeLegStomp.tres",1.21070145],["res://Resources/Actions/HornedBeastCharge.tres",0.84904925],["res://Resources/Actions/HornedBeastForeLegStomp.tres",0.84904925],["res://Resources/Actions/SpiderPounce.tres",0.42071807]]:
		check(is_equal_approx(load(row[0]).damage_multiplier,float(row[1])),"Attack multiplier must load after the Resource script: "+row[0])
	check(service.apply_armor(100.0,10.0,100.0) == 40.0,"Resilience must be applied BEFORE fixed Armor")
	check(service.apply_armor(100.0,10.0,0.0) == 90.0,"Legacy Armor preserved at default resilience")
	check(service.apply_armor(100.0,10.0,300.0) == 15.0,"No 45 percent ceiling")
	check(is_equal_approx(service.apply_armor(100.0,0.0,10.0),100.0/1.1),"No 15 percent floor")
	check(service.apply_armor(5.0,10.0,0.0) == 0.0,"Fixed armor may completely block a weak hit")
	check(service.apply_armor(INF,10.0,0.0) == 0.0 and service.apply_armor(100.0,10.0,-100.0) == 0.0,"Reject invalid defense input")
	var context := {"mass":8.0,"multiplier":1.0}
	check(is_equal_approx(service.calculate_attack_raw_damage(3.0,context),70.0),"Cube root mass scales active damage")
	context.mass = 64.0
	check(is_equal_approx(service.calculate_attack_raw_damage(3.0,context),140.0),"Eight times mass gives twice raw damage")
	check(service.calculate_attack_raw_damage(0.0,context) == 0.0,"No impulse creates no damage")
	check(service.calculate_attack_raw_damage(INF,context) == 0.0,"Reject nonfinite impulse")
	check(service.calculate_weapon_damage(10000.0,0.0,false) <= 2.0,"Passive damage remains weak")
	var source := fixture(0,[8.0])
	var victim := fixture(1,[10.0,10.0])
	var a := victim.get_node("Torso0") as PhysicalBodyPart3D
	var b := victim.get_node("Torso1") as PhysicalBodyPart3D
	check(a.max_hp == 400.0 and a.resilience == 0.0,"Runtime mass HP and default resilience")
	var shared: Dictionary = service.create_attack_context(source)
	var weapons: Array[SampleWeapon3D] = []
	for i: int in 2:
		var weapon := SampleWeapon3D.new()
		weapon.mass = 1.0
		weapon.freeze = true
		root.add_child(weapon)
		weapon.set_wielder(source,0)
		weapon.begin_damage_swing(shared)
		weapons.append(weapon)
	a.resilience = 100.0
	check(is_equal_approx(weapons[0].apply_contact_damage(a,3.0),25.0),"Complete contact uses mass, resilience and armor")
	check(is_equal_approx(weapons[0].apply_contact_damage(b,3.0),60.0),"One action retains full damage to another part")
	check(weapons[1].apply_contact_damage(a,3.0) == 0.0,"Shared hitboxes cannot hit the same Part twice")
	check(weapons[0].apply_contact_damage(source.get_node("Torso0"),3.0) == 0.0,"Friendly filter")
	var naked_mass: float = source.get_base_combat_mass()
	source.get_node("Torso0").mass += 50.0
	check(source.get_base_combat_mass() == naked_mass,"Equipment/compound body mass must not increase attack damage")
	weapons[0].end_damage_swing()
	weapons[0].begin_damage_swing()
	check(weapons[0].apply_contact_damage(a,3.0) > 0.0,"Next action may hit again")
	weapons[0].end_damage_swing()
	weapons[0].begin_damage_swing()
	b.armor = 100000.0
	check(weapons[0].apply_contact_damage(b,3.0) == 0.0,"Armor may absorb a valid action contact")
	b.armor = 10.0
	check(weapons[0].apply_contact_damage(b,3.0) == 0.0,"A blocked Part cannot be retried within the same action")
	for weapon: SampleWeapon3D in weapons: weapon.free()
	source.free(); victim.free()
	for species: String in FACTORY.SUMMON_POOL:
		var record := FACTORY.template(species)
		check(is_equal_approx(record.hp,record.base_total_mass*40.0),"Warehouse mass HP: "+species)
		var poses: Dictionary = record.poses.duplicate(true)
		record.id = "migration_"+species
		record.position = "warehouse"
		record.traits = []
		record.damage_multiplier = 1.5
		record.erase("balance_revision")
		for part: Dictionary in record.parts.values():
			part.hp = float(part.authored_hp)*1.4
			part.armor *= 1.2
			part.erase("resilience")
		check(FACTORY.valid_record(record),"Old records still validate")
		check(FACTORY.upgrade_damage_record(record),"Old record migrates")
		check(record.poses == poses and is_equal_approx(record.hp,record.base_total_mass*40.0*1.4),"Keep exact poses and health rune multiplier")
		check(record.damage_multiplier == 1.5 and record.parts.values()[0].resilience == 0.0,"Keep attack multiplier and initialize resilience")
		check(not FACTORY.upgrade_damage_record(record),"Migration is idempotent")
		var actor: Node3D = FACTORY.spawn(record,host,Vector3.ZERO,1)
		check(actor != null,"Migrated warehouse creature spawns")
		for path: String in record.parts:
			check(is_equal_approx(actor.get_node(path).max_hp,record.parts[path].hp),"Deployment must not restore old fixed HP")
		actor.free()
	# Exercise real load/save backup with an isolated path, never the player's save.
	var session := SESSION.new()
	session.reset()
	var legacy := FACTORY.template("wolf")
	legacy.merge({"id":"legacy_wolf","position":"warehouse","traits":[]},true)
	legacy.erase("balance_revision")
	for part: Dictionary in legacy.parts.values(): part.hp = part.authored_hp
	session.data.monsters.append(legacy)
	session.save_path = "user://damage_v2_migration_"+str(Time.get_ticks_usec())+".json"
	check(session.save(),"Write isolated legacy fixture")
	var original := FileAccess.get_file_as_string(session.save_path)
	check(session.load_save(),"Load and migrate legacy save")
	check(session.data.monsters[0].balance_revision == 2,"Save migration revision")
	check(session.save(),"Save migrated stats")
	check(FileAccess.get_file_as_string(session.save_path+".pre_damage_v2.bak") == original,"Preserve exact pre-migration backup")
	session = null
	print("MASS_DAMAGE_V2_", "FAILED" if failed else "PASSED", " checks=",checks)
	quit(1 if failed else 0)
