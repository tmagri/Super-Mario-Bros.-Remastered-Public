extends Enemy

const MOVE_SPEED := 30
const BARREL_DESTRUCTION_PARTICLE = preload("res://Scenes/Prefabs/Particles/BarrelDestructionParticle.tscn")

func _ready() -> void:
	super()
	collision_layer = 16
	collision_mask = 50

func _physics_process(delta: float) -> void:
	handle_movement(delta)

func handle_movement(delta: float) -> void:
	if is_on_wall() and is_on_floor() and get_wall_normal().x == -direction:
		die()

func die(style: int = 0) -> void:
	destroy()

func die_from_object(_node: Node2D) -> void:
	_check_br_kill()
	destroy()
	
func die_from_hammer(_node: Node2D) -> void:
	_check_br_kill()
	AudioManager.play_sfx("hammer_hit", global_position)
	destroy()

func summon_particle() -> void:
	var node = BARREL_DESTRUCTION_PARTICLE.instantiate()
	node.global_position = global_position - Vector2(0, 8)
	add_sibling(node)

func destroy() -> void:
	summon_particle()
	AudioManager.play_sfx("block_break", global_position)
	queue_free()

func bounce_up() -> void:
	velocity.y = -200
