extends "res://Tests/Integration/MeasureLowTargetCombat.gd"
## Target has no intent or retaliation, but normal support, physics and contact damage callbacks.
func activate_creature(actor: Node3D) -> void:
	FACTORY.activate(actor)
	if not actor.get_meta(&"low_target_fixture",false): return
	var ai := actor.get_node("NPCStateMachine3D")
	ai.enabled = false
	ai.set_physics_process(false)
	for node: Node in actor.get_control_components():
		if node.has_method("set_npc_movement_input"): node.set_npc_movement_input(Vector2.ZERO)

func sample() -> void:
	super.sample()
	options.fixture = "passive_live_rat_normal_support_physics_and_contact_callbacks"
