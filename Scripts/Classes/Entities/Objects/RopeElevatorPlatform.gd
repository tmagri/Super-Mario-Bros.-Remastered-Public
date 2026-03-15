class_name RopeElevatorPlatform
extends Node2D


@export var linked_platform: Node2D = null

@onready var platform: AnimatableBody2D = $Platform
@onready var player_detection: Area2D = $Platform/PlayerDetection

@export var rope_top := -160
var velocity := 0.0

var dropped := false

var player_stood_on := false

var destroyed := false
var destroy_velocity := Vector2.ZERO
var destroy_rotation := 0.0

var sample_colour: Texture = null

func _ready() -> void:
	$Platform/ScoreNoteSpawner.owner = $Platform

func _process(_delta: float) -> void:
	if not dropped:
		$Rope.size.y = platform.global_position.y - rope_top
		$Rope.global_position.y = rope_top

func _physics_process(delta: float) -> void:
	player_stood_on = player_detection.get_overlapping_areas().any(is_player)
	
	if destroyed:
		destroy_velocity.y += Global.entity_gravity * delta * 50
		platform.global_position += destroy_velocity * delta
		platform.rotation += destroy_rotation * delta
		if platform.global_position.y > 480:
			queue_free()
		return
		
	if dropped:
		velocity += (5 / delta) * delta
		platform.position.y += velocity * delta
		return
	else:
		var linked_is_dropped = is_instance_valid(linked_platform) and linked_platform.dropped
		if platform.global_position.y <= rope_top or linked_is_dropped or not is_instance_valid(linked_platform):
			dropped = true
			if linked_is_dropped:
				if Settings.file.audio.extra_sfx == 1:
					AudioManager.play_sfx("lift_fall", global_position)
				$Platform/ScoreNoteSpawner.spawn_note(1000)
	
	var weight_mult = 1.0
	var player = get_tree().get_first_node_in_group("Players")
	if player_stood_on and is_instance_valid(player) and player.has_mega_mushroom:
		weight_mult = 3.0 # Mega weight!
	
	if player_stood_on:
		velocity += (2 * weight_mult / delta) * delta
	else:
		# If Mega Mario is on the LINKED platform, we move up slower/resistant
		var resistance = 1.0
		if is_instance_valid(linked_platform) and linked_platform.player_stood_on and is_instance_valid(player) and player.has_mega_mushroom:
			resistance = 0.5 # Difficult to pull up Mega Mario
		velocity = lerpf(velocity, 0, delta * 2 * resistance)
		
	if is_instance_valid(linked_platform):
		linked_platform.velocity = -velocity
	platform.position.y += velocity * delta

func destroy_platform(dir: float) -> void:
	if destroyed: return
	destroyed = true
	destroy_velocity = Vector2(dir * 200, -300)
	destroy_rotation = dir * 10.0
	platform.set_collision_layer_value(1, false)
	platform.set_collision_mask_value(1, false)
	AudioManager.play_sfx("kick", platform.global_position)
	
func is_player(area: Area2D) -> bool:
	if area.owner is Player:
		return area.owner.is_on_floor()
	return false
