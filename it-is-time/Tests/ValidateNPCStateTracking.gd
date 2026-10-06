extends SceneTree
const ACTOR = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const FSM = preload("res://Scenes/Creatures/Components/NPCStateMachine3D.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func make_npc(actor_name: String) -> Node:
	var actor := Node3D.new()
	actor.set_script(ACTOR)
	actor.name = actor_name
	root.add_child(actor)
	var machine := FSM.instantiate()
	machine.enabled = false
	actor.add_child(machine)
	return machine
func run() -> void:
	var first := make_npc("FirstNPC")
	var second := make_npc("SecondNPC")
	var console := root.get_node("RuntimeConsole")
	check(console.execute_command("help").contains("tracknpcstate"),"Help must list the state tracking command")
	console.execute_command("tracknpcstate on FirstNPC")
	check(console.is_npc_state_tracking_enabled(first) and not console.is_npc_state_tracking_enabled(second),"Filter must isolate one NPC")
	first.change_state(first.State.MOVE_TO_TARGET)
	first.change_state(first.State.ATTACK)
	second.change_state(second.State.ATTACK)
	var late := make_npc("LateNPC")
	check(not console.is_npc_state_tracking_enabled(late),"New NPC must respect the filter")
	console.execute_command("tracknpcstate on")
	check(console.is_npc_state_tracking_enabled(late),"Global tracking must include NPCs spawned later")
	check(console.execute_command("npcstates SecondNPC").ends_with("1"),"One-time snapshots must support filtering")
	console.execute_command("tracknpcstate on "+str(second.get_parent().get_instance_id()))
	check(console.is_npc_state_tracking_enabled(second) and not console.is_npc_state_tracking_enabled(first),"Instance ID filter must identify one actor")
	var data: Dictionary = second.get_state_diagnostics()
	check(data.disabled_reason == "component_disabled" and data.npc_id == second.get_parent().get_instance_id(),"Snapshot must report disabled reasons and stable identity")
	console.execute_command("tracknpcstate off")
	check(not console.is_npc_state_tracking_enabled(second),"Off command must stop independent FSM tracking")
	print("NPC_STATE_TRACKING_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
