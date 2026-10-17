@tool
extends "res://Scripts/Creatures/WolfLegStepMovementController3D.gd"

func _wolf_needs_support_relief(foot: RigidBody3D) -> bool:
	# Walking already retries strained feet; relief must not start a gallop by itself.
	return _wolf_auto_gallop and super._wolf_needs_support_relief(foot)

func _apply_torso_tilt_stabilization() -> void:
	var attack := get_parent().get_node_or_null("WolfAttackController3D")
	# The Rat's raised bite owns Torso elevation; upright walking must not oppose it.
	if attack != null and attack.is_npc_attack_active(): return
	super._apply_torso_tilt_stabilization()
