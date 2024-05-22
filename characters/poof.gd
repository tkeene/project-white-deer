extends Node3D

const LIFETIME: float = 2.0
const NUMBER_OF_ADDED_CLOUDS: int = 3
const CLOUD_OFFSET: float = 0.1
const MOVE_SPEED = 1.0

static var rng = RandomNumberGenerator.new()
var remaining_lifetime = 999.9

func _ready():
	remaining_lifetime = LIFETIME
	for i in NUMBER_OF_ADDED_CLOUDS:
		var copy = $Sphere.duplicate()
		add_child(copy)
		copy.position = Vector3(rng.randf_range(-CLOUD_OFFSET, CLOUD_OFFSET),
			rng.randf_range(0.0, CLOUD_OFFSET),
			rng.randf_range(-CLOUD_OFFSET, CLOUD_OFFSET))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	remaining_lifetime -= delta
	if remaining_lifetime <= 0.0:
		queue_free()
	else:
		var progress = remaining_lifetime / LIFETIME
		scale = Vector3.ONE * progress
		global_position += transform.basis.z * delta * progress * MOVE_SPEED
