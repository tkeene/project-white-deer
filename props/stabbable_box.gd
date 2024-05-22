extends RigidBody3D

const ON_HIT_VERTICAL_VELOCITY = 10.0
const ON_HIT_HORIZONTAL_VELOCITY = 1.0
const ON_HIT_ROTATE_VELOCITY = 10.0
const REPEAT_HIT_TIME = 0.5

static var rng = RandomNumberGenerator.new()
var drop_shadow: Node3D = null
var should_move_drop_shadow = false

var time_since_last_hit = 999.9

func _ready():
	drop_shadow = $DropShadow as Node3D

func _process(delta):
	time_since_last_hit += delta
	if should_move_drop_shadow:
		var floor_check = get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(
				global_position, global_position + Vector3.DOWN * KobPhysics.MAX_FALL_CHECK_DISTANCE,
				KobPhysics.PHYSICS_TERRAIN))
			# TODO What if the slope is too steep?
		if floor_check:
			Player.set_drop_shadow_position(drop_shadow, floor_check.position, floor_check.normal)

func can_hit():
	return time_since_last_hit > REPEAT_HIT_TIME

# TODO Hitting something should have a lot more info about owner, direction, damage, and type
func on_hit():
	should_move_drop_shadow = true
	time_since_last_hit = 0.0
	linear_velocity = Vector3.UP * ON_HIT_VERTICAL_VELOCITY * rng.randf_range(0.8, 1.2) + Vector3(rng.randf_range(-ON_HIT_HORIZONTAL_VELOCITY, ON_HIT_HORIZONTAL_VELOCITY),
		0.0, rng.randf_range(-ON_HIT_HORIZONTAL_VELOCITY, ON_HIT_HORIZONTAL_VELOCITY))
	angular_velocity = Vector3(rng.randf_range(-ON_HIT_ROTATE_VELOCITY, ON_HIT_ROTATE_VELOCITY),
		rng.randf_range(-ON_HIT_ROTATE_VELOCITY, ON_HIT_ROTATE_VELOCITY),
		rng.randf_range(-ON_HIT_ROTATE_VELOCITY, ON_HIT_ROTATE_VELOCITY))
	($Timer as Timer).start()
	($Timer as Timer).wait_time -= 0.1
	Player.instance.add_juggling_score()

func set_drop_shadow_position(target_position: Vector3, up: Vector3):
	#print("set_drop_shadow_position " + str(target_position) + ", " + str(up))
	drop_shadow.global_position = target_position
	var normal_plane: Plane = Plane(up)
	drop_shadow.look_at(target_position + normal_plane.project(Vector3.FORWARD), up)
