class_name PSwitcher
extends Node

var enabled := true
@export_file("*.tscn") var new_scene := ""
@export var new_offset := Vector2.ZERO

@export var properties := []

var is_switched := false

func _ready() -> void:
	Global.p_switch_toggle.connect(switch_to_other)
	if Global.p_switch_active and not is_switched:
		switch_to_other()

func switch_to_other() -> void:
	if enabled == false: return
	if new_scene != "":
		var scn = load(new_scene)
		if scn == null:
			push_warning("PSwitcher: Failed to load scene: " + new_scene)
			return
		var new_node = scn.instantiate()
		new_node.global_position = owner.global_position + new_offset
		if new_node.has_node("PSwitcher"):
			new_node.get_node("PSwitcher").new_scene = owner.scene_file_path
			new_node.get_node("PSwitcher").is_switched = true
		for i in properties:
			new_node.set(i, owner.get(i))
		# Use parent directly — owner.call_deferred("add_sibling") fails when
		# owner is also queue_free'd in the same frame.
		var parent = owner.get_parent()
		if is_instance_valid(parent):
			parent.call_deferred("add_child", new_node)
	owner.queue_free()
