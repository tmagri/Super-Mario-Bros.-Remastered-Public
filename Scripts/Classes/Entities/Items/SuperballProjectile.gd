class_name SuperballProjectile
extends CharacterBody2D

const CHARACTERS := ["Mario", "Luigi", "Toad", "Toadette"]

var is_friendly := true

var character := "Mario"
var direction := 1
var LIFETIME := 10.0

@export var COLLECT_COINS := true
@export var MOVE_SPEED := 150

const SMOKE_PARTICLE = preload("res://Scenes/Prefabs/Particles/SmokeParticle.tscn")

func _ready() -> void:
	# Force correct SML mechanics layers
	# SML Ball should bounce off ALL solids (typically Layers 1, 2, 3, etc.)
	collision_layer = 8 # Layer 4 - Projectiles
	# 1 = World, 2 = Blocks, 4 = One-ways/Solids
	collision_mask = 1 | 2 | 4 | 32 | 64 
	
	if has_node("Hitbox"):
		# Set Hitbox to detect enemies (16), coins (1), and specific items
		$Hitbox.collision_layer = 0
		$Hitbox.collision_mask = 1 | 2 | 4 | 16 | 1024 
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	
	# Start lifetime timer
	if LIFETIME > 0:
		await get_tree().create_timer(LIFETIME).timeout
		if is_instance_valid(self):
			hit(false)

func _on_hitbox_area_entered(area: Area2D) -> void:
	# 1. Check for Coins (SML balls collect coins and continue)
	if COLLECT_COINS:
		var coin_target = area
		if area.owner and area.owner.is_in_group("Coins"):
			coin_target = area.owner
		elif area.get_parent() and area.get_parent().is_in_group("Coins"):
			coin_target = area.get_parent()
			
		if coin_target and coin_target.is_in_group("Coins") and not coin_target.is_queued_for_deletion():
			if coin_target.has_method("collect"):
				coin_target.collect()
				# Removed return here! In SML, the ball can pass through a coin and still hit an enemy.
	
	# 2. Check for Enemies
	var potential_enemies = [area, area.get_parent(), area.owner]
	for target in potential_enemies:
		if target and target.is_in_group("Enemies") and not target.is_queued_for_deletion():
			# FIRST: support enemies with multiple health/fireball logic (like Bowser or Bob-Ombs)
			if target.has_method("fireball_hit"):
				if "health" in target:
					target.fireball_hit() # Bowser signature (no args)
				else:
					target.fireball_hit(self) # Bob-Omb signature (takes fireball ref)
				hit()
				return
				
			if target.has_method("die_from_object"):
				target.die_from_object(self)
				hit()
				return
			elif target.has_method("die"):
				target.die()
				hit()
				return

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
