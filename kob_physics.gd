# It's called KobPhysics because @koboldskeep made it. See https://github.com/tkeene/ for details.

class_name KobPhysics

const MAX_FALL_CHECK_DISTANCE : float = 1000.0
# See Project>Project Settings>Layer Names>3D Physics
const PHYSICS_TERRAIN = 0b00000000_00000000_00000000_00000011
const PHYSICS_TERRAIN_MINUS_CAMERA_PASSTHROUGH = 0b00000000_00000000_00000000_00000001
const PHYSICS_CLIMBABLE = 0b00000000_00000000_00000000_00010000
const PHYSICS_WATER = 0b00000000_00000000_00000000_00100000
const PHYSICS_PROJECTILE = 0b00000000_00000000_00000001_00000000

static func move_actor(actor: Node3D, world: PhysicsDirectSpaceState3D,
	offset: Vector3, radius: float = 0.0, height_above_ground: float = 0.0):
	var output = {}
	output.standing_on = null
	output.facing_wall = null
	output.facing_wall_normal = Vector3.ZERO
	if offset.length_squared() == 0.0:
		printerr("move() was called with a vector of length 0.0")
	else:
		# TODO Break this up into smaller movement steps for better precision along slopes and obstacles.
		# TODO Also check for ceilings, if there's nothing beneath then get pushed down, otherwise don't move there
		# TODO Physics layers for water
		# TODO Physics layers for grates
		# TODO Query a spherecast?
		const ANGLE_PER_CHECK = PI * 0.06
		const MAX_ANGLE = PI * 0.33
		var has_solution = false
		var check_index = 0
		var current_position = actor.global_position
		var new_position = current_position
		var horizontal_offset = Vector3(offset.x, 0.0, offset.z)
		var has_horizontal_offset = horizontal_offset.length_squared() > 0.0
		var vertical_offset = Vector3(0.0, offset.y, 0.0)
		if has_horizontal_offset:
			while (!has_solution):
				var angle_index = roundi((check_index + 0.9) / 2)
				var angle_sign = 1.0 if (check_index % 2 == 1) else -1.0
				var current_angle = ANGLE_PER_CHECK * angle_index * angle_sign
				if abs(current_angle) > MAX_ANGLE:
					has_solution = true
				else:
					var this_check_length = pow(cos(current_angle), 2.0) # Move a bit more slowly along walls than the normal forces would suggest.
					var this_check_offset = this_check_length * horizontal_offset.rotated(Vector3.UP, current_angle)
					var movement_target = current_position + this_check_offset
					var check_target = current_position + this_check_offset.normalized() * (this_check_offset.length() + radius)
					#print("checking movement to " + str(target))
					var wall_check = PhysicsRayQueryParameters3D.create(current_position, check_target, KobPhysics.PHYSICS_TERRAIN)
					var wall_result = world.intersect_ray(wall_check)
					if !wall_result:
						if Player.DEBUG_WALKING: DebugDraw3D.draw_line(wall_check.from, wall_check.to, Color.YELLOW, 1.0)
						new_position = movement_target
						has_solution = true
					else:
						if Player.DEBUG_WALKING: DebugDraw3D.draw_line(wall_check.from, wall_check.to, Color.RED, 3.0)
						if output.facing_wall == null:
							output.facing_wall = wall_result.collider
							output.facing_wall_normal = wall_result.normal
						check_index += 1
		# We must do the vertical check separately because if we do it as a single vector and the player jumps into a wall, they will get stuck and be unable to fall.
		# This wouldn't be as much of a problem if we were using move_and_slide, but I want to stick to raycasts for all of this because I'm a control freak
		if vertical_offset.length_squared() > 0.0:
			var vertical_radius = max(radius, height_above_ground, 0.01)
			var vertical_target = new_position + vertical_offset
			var vertical_target_plus_radius = vertical_target + vertical_offset.normalized() * vertical_radius
			var vertical_check = PhysicsRayQueryParameters3D.create(new_position, vertical_target_plus_radius, KobPhysics.PHYSICS_TERRAIN)
			var vertical_result = world.intersect_ray(vertical_check)
			if !vertical_result:
				new_position = vertical_target
				if Player.DEBUG_WALKING: DebugDraw3D.draw_line(new_position, vertical_target, Color.LIME, 3.0)
			else:
				new_position = vertical_result.position - vertical_offset.normalized() * vertical_radius
				if Player.DEBUG_WALKING: DebugDraw3D.draw_line(vertical_result.position, new_position, Color.LIME, 3.0)
		if has_horizontal_offset && radius > 0:
			var right = horizontal_offset.rotated(Vector3.UP, -PI * 0.5).normalized()
			var right_wall_check = PhysicsRayQueryParameters3D.create(new_position, new_position + right * radius, KobPhysics.PHYSICS_TERRAIN)
			var right_wall_result = world.intersect_ray(right_wall_check)
			var left_wall_check = PhysicsRayQueryParameters3D.create(new_position, new_position - right * radius, KobPhysics.PHYSICS_TERRAIN)
			var left_wall_result = world.intersect_ray(left_wall_check)
			const WALL_PUSH_PER_STEP = 0.05
			if right_wall_result && left_wall_result:
				if Player.DEBUG_WALKING: print("centering between walls at " + str(right_wall_result.position) + " and " + str(left_wall_result.position))
				new_position = (right_wall_result.position + left_wall_result.position) * 0.5
			elif right_wall_result:
				if Player.DEBUG_WALKING: print("ejecting from right wall at " + str(right_wall_result.position))
				new_position = new_position.move_toward(right_wall_result.position - right * radius, WALL_PUSH_PER_STEP)
			elif left_wall_result:
				if Player.DEBUG_WALKING: print("ejecting from left wall at " + str(left_wall_result.position))
				new_position = new_position.move_toward(left_wall_result.position + right * radius, WALL_PUSH_PER_STEP)
		# TODO Ledge jumping
		if height_above_ground > 0.0:
			var expected_distance_to_ground = height_above_ground * 1.25 # TODO We should check their lateral movement and expected maximum slope
			var ground_check = PhysicsRayQueryParameters3D.create(new_position, new_position + Vector3.DOWN * expected_distance_to_ground, KobPhysics.PHYSICS_TERRAIN)
			var ground_result = world.intersect_ray(ground_check)
			if ground_result:
				new_position.y = ground_result.position.y + height_above_ground
				output.standing_on = ground_result.collider
		if Player.DEBUG_WALKING: DebugDraw3D.draw_line(actor.global_position, new_position, Color.CYAN, 5.0)
		actor.global_position = new_position
	return output

static func vector3_to_pretty_string(input: Vector3, digits: int = 2):
	var format_string = "%." + str(digits) + "f"
	var x = format_string % input.x
	var y = format_string % input.y
	var z = format_string % input.z
	return "(" + x + "," + y + "," + z + ")"
