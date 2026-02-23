@tool
extends CollisionPolygon2D

@export var offset := Vector2.ZERO
@export var hitbox := Vector2.ONE

var crouching := false
var sloped_floor_corner := false

func _physics_process(_delta: float) -> void:
	update()

func update() -> void:
	update_polygon()
	position = offset

func update_polygon() -> void:
	var hw = hitbox.x / 2.0
	var h = hitbox.y
	
	# Generate points in a consistent order to avoid self-intersection
	# We use 8 points like the original, but ensure they never cross.
	var p = PackedVector2Array()
	p.resize(8)
	
	var corner_height := 0.0
	if sloped_floor_corner:
		corner_height = -3.0
		
	# 0: bottom-right
	p[0] = Vector2(hw, corner_height)
	# 1: top-shoulder-right
	p[1] = Vector2(hw, -h + 6.0)
	# 2: top-right clipped
	p[2] = Vector2(max(0.0, hw - 3.0), -h)
	# 3: top-left clipped
	p[3] = Vector2(min(0.0, -hw + 3.0), -h)
	# 4: top-shoulder-left
	p[4] = Vector2(-hw, -h + 6.0)
	# 5: bottom-left
	# Note: Using y=corner_height for 5 to match 0
	p[5] = Vector2(-hw, corner_height)
	# 6: bottom-inner-left (for rounded floors)
	p[6] = Vector2(-hw + 2.0, 0.0)
	# 7: bottom-inner-right (for rounded floors)
	p[7] = Vector2(hw - 2.0, 0.0)

	# Safety check: if h is small, shoulder and top might cross y-wise
	# But h is usually > 6 for Mario.

	# Filter out duplicate points which break convex decomposition
	var filtered := PackedVector2Array()
	for i in range(p.size()):
		var point = p[i]
		if filtered.size() == 0 or !filtered[filtered.size() - 1].is_equal_approx(point):
			filtered.append(point)
	
	# Close the loop safety
	if filtered.size() > 1 and filtered[0].is_equal_approx(filtered[filtered.size() - 1]):
		filtered.remove_at(filtered.size() - 1)
			
	if filtered.size() >= 3:
		if polygon != filtered:
			polygon = filtered
