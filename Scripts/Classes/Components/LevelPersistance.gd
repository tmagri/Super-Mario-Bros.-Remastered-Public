class_name LevelPersistance
extends Node

static var active_nodes := [[], [], []]

var active := false

@onready var path := get_path_string()

signal enabled
signal enabled_2

static func reset_states() -> void:
	active_nodes = [[], [], []]
	Checkpoint.old_state = [[], [], []]

static func reset_enemies() -> void:
	active_nodes[2] = []
	Checkpoint.old_state[2] = []

func _ready() -> void:
	return

func set_as_active() -> void:
	if owner.has_meta("no_persist"): return
	var idx = 0
	if owner is Enemy:
		idx = 2
	active_nodes[idx].append(path)

func set_as_active_2() -> void:
	if owner.has_meta("no_persist"): return
	active_nodes[1].append(path)

func get_path_string() -> String:
	return Global.current_level.scene_file_path + str(Vector2i(owner.global_position / 8))
