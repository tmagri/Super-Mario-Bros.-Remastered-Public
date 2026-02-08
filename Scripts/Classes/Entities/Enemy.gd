@icon("res://Assets/Sprites/Editor/Enemy.svg")
class_name Enemy
extends CharacterBody2D

signal killed(direction: int)

@export var on_screen_enabler: VisibleOnScreenNotifier2D = null
@export var score_note_adder: ScoreNoteSpawner = null

var direction := -1
var is_sent_enemy := false:
	set(v):
		is_sent_enemy = v
		if is_node_ready():
			_update_sent_visuals()

var _sent_tween: Tween

func _enter_tree() -> void:
	if is_sent_enemy:
		_update_sent_visuals()

func _ready() -> void:
	_update_sent_visuals()

func _update_sent_visuals() -> void:
	if is_sent_enemy:
		if _sent_tween: _sent_tween.kill()
		_sent_tween = create_tween().set_loops()
		# Fast blink effect
		_sent_tween.tween_property(self, "modulate:a", 0.2, 0.15)
		_sent_tween.tween_property(self, "modulate:a", 0.8, 0.15)
		# Ghostly bluish-white tint
		modulate = Color(0.7, 0.7, 1.5, 0.8)
	else:
		if _sent_tween: _sent_tween.kill()
		_sent_tween = null
		modulate = Color.WHITE

func _check_br_kill(time_reward: int = 2) -> void:
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		Mario35Handler.on_enemy_killed(self, time_reward)

func damage_player(player: Player) -> void:
	player.damage()

func apply_enemy_gravity(delta: float) -> void:
	velocity.y += (Global.entity_gravity / delta) * delta
	velocity.y = clamp(velocity.y, -INF, Global.entity_max_fall_speed)

func die() -> void:
	_check_br_kill(2)
	killed.emit([-1, 1].pick_random())
	DiscoLevel.combo_amount += 1
	DiscoLevel.combo_meter = 100
	queue_free()

func die_from_object(obj: Node2D) -> void:
	var dir = sign(global_position.x - obj.global_position.x)
	if dir == 0:
		dir = [-1, 1].pick_random()
	
	# If killed by a shell or player stomp, time is handled by the attacker to allow combos
	var reward = 0 if (obj is Shell or obj is Player) else 2
	_check_br_kill(reward)
	DiscoLevel.combo_amount += 1
	killed.emit(dir)
	queue_free()

func flag_die() -> void:
	if on_screen_enabler != null:
		if on_screen_enabler.is_on_screen():
			_check_br_kill()
			queue_free()
			if score_note_adder != null:
				if score_note_adder.add_score == false:
					Global.score += 500
				score_note_adder.spawn_note(500)

func die_from_hammer(obj: Node2D) -> void:
	var dir = sign(global_position.x - obj.global_position.x)
	if dir == 0:
		dir = [-1, 1].pick_random()
	_check_br_kill()
	DiscoLevel.combo_amount += 1
	AudioManager.play_sfx("hammer_hit", global_position)
	killed.emit(dir)
	queue_free()
