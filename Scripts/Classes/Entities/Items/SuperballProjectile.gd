class_name SuperballProjectile
extends CharacterBody2D

const CHARACTERS := ["Mario", "Luigi", "Toad", "Toadette"]

var character := "Mario"
var direction := 1
var lifetime := 10.0

@export var COLLECT_COINS := false
@export var MOVE_SPEED := 150

const SMOKE_PARTICLE = preload("res://Scenes/Prefabs/Particles/SmokeParticle.tscn")

func _ready() -> void:
	# Start lifetime timer
	if lifetime > 0:
		await get_tree().create_timer(lifetime).timeout
		if is_instance_valid(self):
			hit(false)

func _physics_process(delta: float) -> void:
	$Sprite.scale.x = direction
	
	# Use move_and_collide for proper bounce reflection
	var motion = velocity * delta
	var collision = move_and_collide(motion)
	
	if collision:
		var normal = collision.get_normal()
		# Reflect velocity off the collision normal for right-angle bouncing
		velocity = velocity.bounce(normal)
		# Update direction based on reflected horizontal velocity
		if velocity.x != 0:
			direction = sign(velocity.x)
		# Move remaining distance after bounce
		var remainder = collision.get_remainder()
		move_and_collide(remainder.bounce(normal))

func hit(play_sfx := true) -> void:
	if play_sfx:
		AudioManager.play_sfx("bump", global_position)
	summon_explosion()
	queue_free()

func summon_explosion() -> void:
	var node = SMOKE_PARTICLE.instantiate()
	node.global_position = global_position
	add_sibling(node)
