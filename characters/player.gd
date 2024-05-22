# Project White Deer - https://github.com/tkeene/project-white-deer

extends Node3D
class_name Player

# TODO Consolidate poof spawning

const DEBUG_WALKING: bool = false
const DEBUG_CLIMBING: bool = false
const DEBUG_SHADOW = false
const DEBUG_CAMERA: bool = false

# Constants
const PLAYER_RADIUS: float = 0.3
const PLAYER_HALF_HEIGHT: float = 0.4 # Must be greater than PLAYER_RADIUS
const MAX_SEEK_DOWN_DISTANCE: float = 0.5
const CLAMP_DIAGONAL_INPUT = false
const MOVE_SPEED: float = 4.5
const WALKING_SLOPE_MAXIMUM_RADIANS = 0.3 * PI # That's 54 degrees
const WALKING_DUST_TIMER: float = 0.25
const JUMP_HEIGHT: float = 0.8
const MINIMUM_JUMP_HORIZONTAL_VELOCITY : float = 1.0
const GRAVITY: float = 15.0
const MAX_FALL_SPEED: float = 20.0
const GLIDE_SPEED: float = 5.5
const GLIDE_ACCELERATION: float = 3.0
const GLIDE_FALL_SPEED = 1.0
const DELAY_BEFORE_CLIMBING_SECONDS = 0.33
const CLIMB_WALL_GRAB_DISTANCE: float = 1.75 * PLAYER_RADIUS
const CLIMB_WALL_GRAB_MAXIMUM_NORMAL_ANGLE = 0.2 * PI
const CLIMB_SPEED:float = 2.0
const CLIMB_ROTATE_SPEED_RADIANS_PER_SECOND:float = PI * 2.0
const CLIMB_REGRAB_DELAY:float = 0.7
const LEDGE_GRAB_MAXIMUM_HEIGHT = 2.0 - PLAYER_HALF_HEIGHT
const LEDGE_GRAB_SMALL_HOP_HEIGHT = PLAYER_RADIUS
const LEDGE_GRAB_CLIMB_INWARDS_DISTANCE = PLAYER_RADIUS
const LEDGE_GRAB_CLIMB_TO_CORNER_DURATION: float = 0.3
const LEDGE_GRAB_CLIMB_TO_STANDING_DURATION: float = 0.4
const DODGE_ANIMATION_CANCEL_WINDOW: float = 0.25
const DODGE_HORIZONTAL_VELOCITY: float = 12.0
const DODGE_VERTICAL_VELOCITY: float = 2.0
const DODGE_LANDING_COOLDOWN: float = 0.333
const BASIC_ATTACK_COOLDOWN:float = 0.2
const BASIC_ATTACK_OFFSET:float = 0.5
const CHARGE_ATTACK_WALK_SPEED:float = 1.0
const CHARGE_ATTACK_WINDUP:float = 1.0
const CHARGE_ATTACK_COOLDOWN:float = 1.0
const CAMERA_STANDARD_DISTANCE: float = 4.0
const CAMERA_HEIGHT: float = 2.0
const CAMERA_OVERHEAD_TARGET: float = 0.5
const CAMERA_MOVE_SPEED: float = 12.0
const CAMERA_ROTATE_SPEED: float = 3.0
const CAMERA_WALL_RECOVER_SPEED: float = 1.0
const CAMERA_MINIMUM_DISTANCE: float = 0.1

# Settings
var horizontal_camera_invert = -1.0

# References
static var instance: Player = null
var camera: Camera3D = null
var drop_shadow: Node3D = null
var glider_renderer: Node3D = null
var basic_attack_scene: PackedScene = preload("res://characters/debug_stab_projectile.tscn")
var charge_attack_scene: PackedScene = preload("res://characters/debug_spin_projectile.tscn")
var walking_poof_scene: PackedScene = preload("res://characters/poof.tscn")
var current_sword_charge = 0.0

# Movement Variables
var current_facing: Vector3 = Vector3.FORWARD
var current_velocity: Vector3 = Vector3.ZERO
var current_climbing_delay_timer = 0.0
var stun_duration_on_landing = 0.0
var cached_starting_jump_vertical_velocity: float = 0
var current_walking_dust_timer = 0
var climbing_regrab_cooldown = 0.0
var current_ledgegrab_pull_to: Vector3 = Vector3.ZERO
var current_ledgegrab_player_position: Vector3 = Vector3.ZERO
var current_ledgegrab_facing: Vector3 = Vector3.ZERO

var current_camera_offset = (Vector3.BACK + Vector3.UP * 0.5).normalized() * CAMERA_STANDARD_DISTANCE
var current_frame_count = 0

enum EPlayerState {GROUNDED, AIRBORNE, CLIMBING, LEDGE_GRAB, PULLING_TO_POINT, SWIMMING, CUTSCENE}
var current_state: EPlayerState = EPlayerState.GROUNDED
var animation_cooldown = 0.0

func _ready():
	instance = self
	camera = $PlayerCamera as Camera3D
	drop_shadow = $DropShadow as Node3D
	glider_renderer = $GliderRenderer as MeshInstance3D
	Player.set_drop_shadow_position(drop_shadow, global_position + Vector3.DOWN * PLAYER_HALF_HEIGHT, Vector3.UP)
	#camera.global_position = transform.global_position + current_camera_position
	# https://medium.com/@brazmogu/physics-for-game-dev-a-platformer-physics-cheatsheet-f34b09064558
	# the initial velocity for the character to jump H high is the square root of 2 * H * g
	cached_starting_jump_vertical_velocity = sqrt(2 * JUMP_HEIGHT * GRAVITY)

func _physics_process(delta):
	current_frame_count += 1
	var input_right_facing = camera.transform.basis.x.normalized()
	var input_forward_facing = input_right_facing.rotated(Vector3.UP, PI * 0.5)
	var using_glider = false
	var world = get_world_3d().direct_space_state
	var input = _process_get_input()
	input.direction = Vector3(input.x * input_right_facing + input.y * input_forward_facing)
	if CLAMP_DIAGONAL_INPUT:
		input.direction = input.direction.limit_length(1.0)
	
	# TODO Refactor into state-specific functions
	
	# Motor
	var should_try_to_start_climbing = false
	if animation_cooldown <= 0.0:
		# GROUNDED State Motor
		if current_state == EPlayerState.GROUNDED:
			var move_output = motor_walk(world, input, input_right_facing, input_forward_facing, delta)
			var should_reset_climbing_timer = true
			# TODO Make jumping respect water and lava. The player should jump onto them no matter what.
			# TODO I guess the player should just fall into grates.
			var floor_check_result = world.intersect_ray(PhysicsRayQueryParameters3D.create(
				global_position, global_position + Vector3.DOWN * KobPhysics.MAX_FALL_CHECK_DISTANCE,
				KobPhysics.PHYSICS_TERRAIN))
			# TODO What if the slope is too steep?
			if floor_check_result:
				var floor_distance = global_position.distance_to(floor_check_result.position)
				if floor_distance > PLAYER_HALF_HEIGHT * 1.01:
					# TODO spawn a poof since we are jumping
					current_state = EPlayerState.AIRBORNE
					if current_velocity.length() < MINIMUM_JUMP_HORIZONTAL_VELOCITY:
						current_velocity = current_velocity.normalized() * MINIMUM_JUMP_HORIZONTAL_VELOCITY
					current_velocity.y = cached_starting_jump_vertical_velocity
					stun_duration_on_landing = 0.0
				Player.set_drop_shadow_position(drop_shadow, floor_check_result.position, floor_check_result.normal)
				if (!input.direction.is_zero_approx()):
					if move_output.facing_wall:
						var wall_normal_ignoring_slope = Vector3(move_output.facing_wall_normal.x, 0.0, move_output.facing_wall_normal.z).normalized()
						var wall_angle = current_facing.angle_to(-wall_normal_ignoring_slope)
						if DEBUG_CLIMBING: print("We are facing a wall at angle " + str(wall_angle) + " - normal " + str(move_output.facing_wall_normal))
						if wall_angle < CLIMB_WALL_GRAB_MAXIMUM_NORMAL_ANGLE:
							if DEBUG_CLIMBING:
								print("Facing wall for " + str(current_climbing_delay_timer))
								DebugDraw.draw_line(global_position, global_position + move_output.facing_wall_normal, Color.GREEN, 0.01)
							current_climbing_delay_timer += delta
							should_reset_climbing_timer = false
							should_try_to_start_climbing = current_climbing_delay_timer >= DELAY_BEFORE_CLIMBING_SECONDS
						else:
							if DEBUG_CLIMBING:
								DebugDraw.draw_line(global_position, global_position + move_output.facing_wall_normal, Color.RED, 0.01)
					current_walking_dust_timer -= delta
					if input.sword && current_sword_charge < CHARGE_ATTACK_WINDUP:
						current_walking_dust_timer = WALKING_DUST_TIMER
					elif current_walking_dust_timer < 0.0:
						current_walking_dust_timer += WALKING_DUST_TIMER
						var spawned_poof = walking_poof_scene.instantiate() as Node3D
						owner.add_child(spawned_poof)
						# TODO This spawns dust particles in the wrong direction when performing a charge attack.
						spawned_poof.look_at_from_position(floor_check_result.position, floor_check_result.position + current_facing)
				else:
					current_walking_dust_timer = 0.0
			else:
				Player.set_drop_shadow_position(drop_shadow, global_position + Vector3.DOWN * PLAYER_HALF_HEIGHT, Vector3.UP)
			if should_reset_climbing_timer:
				if DEBUG_CLIMBING: print("EPlayerState.GROUNDED resetting the climbing timer.")
				current_climbing_delay_timer = 0.0
		# AIRBORNE State Motor
		elif current_state == EPlayerState.AIRBORNE:
			should_try_to_start_climbing = current_velocity.y < 0.0
			current_walking_dust_timer = WALKING_DUST_TIMER
			if current_velocity.y == 0.0: # Make sure KobPhysics.move_actor has something to do if we just started falling.
				current_velocity.y = -0.001
			var movement_offset = current_velocity * delta
			KobPhysics.move_actor(self, world, movement_offset, PLAYER_RADIUS)
			current_velocity.y = move_toward(current_velocity.y, MAX_FALL_SPEED, -GRAVITY * delta)
			if input.dodge && current_velocity.y <= -GLIDE_FALL_SPEED:
				using_glider = true
				current_velocity.y = -GLIDE_FALL_SPEED
				var flight_input: Vector3 = input.direction
				# This allows the player to super-glide by dashing into a glide and not pressing any inputs. This is not a bug, this is a feature!
				if (flight_input.length() > 0.1):
					var target_velocity = flight_input * GLIDE_SPEED
					current_velocity.x = move_toward(current_velocity.x, target_velocity.x, delta * GLIDE_ACCELERATION)
					current_velocity.z = move_toward(current_velocity.z, target_velocity.z, delta * GLIDE_ACCELERATION)
			var floor_check_result = world.intersect_ray(PhysicsRayQueryParameters3D.create(
				global_position, global_position + Vector3.DOWN * KobPhysics.MAX_FALL_CHECK_DISTANCE,
				KobPhysics.PHYSICS_TERRAIN))
			if floor_check_result:
				Player.set_drop_shadow_position(drop_shadow, floor_check_result.position, floor_check_result.normal)
				var floor_distance = global_position.distance_to(floor_check_result.position)
				if floor_distance <= PLAYER_HALF_HEIGHT:
					current_state = EPlayerState.GROUNDED
					if current_velocity.y <= 0.0: # Don't do dodge recovery when dodging up slopes, it feels bad.
						animation_cooldown = stun_duration_on_landing
					stun_duration_on_landing = 0.0
					current_velocity.y = 0.0
					global_position = floor_check_result.position + Vector3.UP * PLAYER_HALF_HEIGHT
					const hexagon_rotation = PI * 0.333
					for i in 6:
						var direction = current_facing.rotated(Vector3.UP, hexagon_rotation * i)
						var spawned_poof = walking_poof_scene.instantiate() as Node3D
						owner.add_child(spawned_poof)
						spawned_poof.look_at_from_position(floor_check_result.position, floor_check_result.position + direction)
			else:
				# The player must be out of bounds, so stop making them fall. It's fine.
				current_state = EPlayerState.GROUNDED
		# CLIMBING State Motor
		elif current_state == EPlayerState.CLIMBING:
			should_try_to_start_climbing = false
			if input.dodge_down:
				current_state = EPlayerState.AIRBORNE
				current_facing = -Vector3(current_facing.x, 0.0, current_facing.z).normalized()
				$Capsule.look_at(global_position + current_facing)
				if input.direction.length() > 0.25:
					# TODO Directional jumping along the cliff face
					current_velocity = current_facing * MOVE_SPEED + Vector3.UP * cached_starting_jump_vertical_velocity
					if DEBUG_CLIMBING: DebugDraw.draw_line(global_position, global_position + current_facing, Color.BLUE, 3.0)
				else:
					current_velocity = Vector3.ZERO
			else:
				var climb_result = motor_climb(world, input, delta)
				if !climb_result.current_surface:
					current_facing = Vector3(current_facing.x, 0.0, current_facing.z)
					if current_facing.length_squared() == 0.0:
						current_facing = Vector3(camera.basis.z.x, 0.0, camera.basis.z.z).normalized()
					else:
						current_facing = current_facing.normalized()
					current_state = EPlayerState.AIRBORNE
					current_velocity = Vector3.ZERO
				else:
					var floor_check_result = world.intersect_ray(PhysicsRayQueryParameters3D.create(
						global_position, global_position + Vector3.DOWN * KobPhysics.MAX_FALL_CHECK_DISTANCE,
						KobPhysics.PHYSICS_TERRAIN))
					if floor_check_result:
						set_drop_shadow_position(drop_shadow, floor_check_result.position, floor_check_result.normal)
						if input.y < -0.1 && global_position.distance_to(floor_check_result.position) <= PLAYER_HALF_HEIGHT:
							current_state = EPlayerState.GROUNDED
				# TODO Climbing up onto ledges
			if current_state != EPlayerState.CLIMBING:
				climbing_regrab_cooldown = CLIMB_REGRAB_DELAY
		# LEDGE_GRAB State Motor
		elif current_state == EPlayerState.LEDGE_GRAB:
			global_position = current_ledgegrab_player_position
			current_facing = current_ledgegrab_facing.normalized()
			if input.dodge_down || input.direction.length() > 0.4:
				if input.dodge_down || input.direction.dot(current_ledgegrab_facing) < 0.0:
					current_state = EPlayerState.AIRBORNE
					current_velocity = Vector3.ZERO
					climbing_regrab_cooldown = CLIMB_REGRAB_DELAY
				else:
					current_state = EPlayerState.PULLING_TO_POINT
		elif current_state == EPlayerState.PULLING_TO_POINT:
			global_position = global_position.move_toward(current_ledgegrab_pull_to, (LEDGE_GRAB_CLIMB_INWARDS_DISTANCE + PLAYER_HALF_HEIGHT) / LEDGE_GRAB_CLIMB_TO_STANDING_DURATION * delta)
			if global_position.is_equal_approx(current_ledgegrab_pull_to):
				current_state = EPlayerState.GROUNDED
			var floor_check_result = world.intersect_ray(PhysicsRayQueryParameters3D.create(
				global_position, global_position + Vector3.DOWN * KobPhysics.MAX_FALL_CHECK_DISTANCE,
				KobPhysics.PHYSICS_TERRAIN))
			var shadow_position: Vector3 = current_ledgegrab_pull_to + Vector3.DOWN * PLAYER_HALF_HEIGHT
			var shadow_normal:Vector3 = Vector3.UP
			if floor_check_result:
				shadow_position = Vector3(floor_check_result.position.x, max(floor_check_result.position.y, shadow_position.y), floor_check_result.position.z)
				shadow_normal = floor_check_result.normal
			set_drop_shadow_position(drop_shadow, shadow_position, shadow_normal)
	else:
		# TODO Oof. EPlayerState.LEDGE_GRAB is weird now. Maybe we should make a process function for each state?
		if current_state == EPlayerState.LEDGE_GRAB:
			current_facing = current_ledgegrab_facing.normalized()
			global_position = global_position.move_toward(current_ledgegrab_player_position, LEDGE_GRAB_CLIMB_INWARDS_DISTANCE / LEDGE_GRAB_CLIMB_TO_CORNER_DURATION * delta)
	if current_state == EPlayerState.LEDGE_GRAB:
		var floor_check_result = world.intersect_ray(PhysicsRayQueryParameters3D.create(
			global_position, global_position + Vector3.DOWN * KobPhysics.MAX_FALL_CHECK_DISTANCE,
			KobPhysics.PHYSICS_TERRAIN))
		if floor_check_result:
			set_drop_shadow_position(drop_shadow, floor_check_result.position, floor_check_result.normal)
	
	if DEBUG_CLIMBING && current_state == EPlayerState.GROUNDED: print("Start climb timer: " + str(current_climbing_delay_timer) + ", regrab timer: " + str(climbing_regrab_cooldown) + ", " + str(current_state))
	if current_state != EPlayerState.GROUNDED:
		current_climbing_delay_timer = 0.0
	if should_try_to_start_climbing && climbing_regrab_cooldown <= 0.0:
		if attempt_climbable_wall_grab(world, input_right_facing, input_forward_facing):
			current_state = EPlayerState.CLIMBING
		else:
			var ledge_grab = attempt_ledge_grab(world)
			if ledge_grab.found_ledge:
				current_ledgegrab_pull_to = ledge_grab.pull_to
				current_ledgegrab_facing = ledge_grab.facing
				current_ledgegrab_player_position = ledge_grab.corner - ledge_grab.facing * PLAYER_RADIUS + Vector3.DOWN * PLAYER_RADIUS
				if (current_ledgegrab_player_position.y - global_position.y) > LEDGE_GRAB_SMALL_HOP_HEIGHT:
					current_state = EPlayerState.LEDGE_GRAB
					animation_cooldown = LEDGE_GRAB_CLIMB_TO_CORNER_DURATION
				else:
					current_state = EPlayerState.PULLING_TO_POINT
	else:
		climbing_regrab_cooldown -= delta
	
	# Actions & Attacks
	if current_state != EPlayerState.PULLING_TO_POINT && current_state != EPlayerState.CUTSCENE:
		if input.sword || input.sword_up:
			current_sword_charge += delta
		else:
			current_sword_charge = 0.0
		var could_dodge = current_state == EPlayerState.GROUNDED
		if animation_cooldown <= 0.0:
			# TODO Drop attack
			# TODO Dash attack
			if current_state == EPlayerState.GROUNDED:
				could_dodge = false
				if current_sword_charge >= CHARGE_ATTACK_WINDUP && input.sword_up:
					animation_cooldown = CHARGE_ATTACK_COOLDOWN
					var spawned_attack: Node3D = charge_attack_scene.instantiate() as Node3D
					owner.add_child(spawned_attack)
					# TODO Track damage ownership
					spawned_attack.look_at_from_position(global_position, global_position + current_facing)
				elif input.sword_down:
					animation_cooldown = BASIC_ATTACK_COOLDOWN
					var spawned_attack: Node3D = basic_attack_scene.instantiate() as Node3D
					owner.add_child(spawned_attack)
					# TODO Track damage ownership
					spawned_attack.look_at_from_position(global_position + current_facing * BASIC_ATTACK_OFFSET,
						global_position + current_facing * (BASIC_ATTACK_OFFSET + 1.0))
				else:
					could_dodge = true
		else:
			animation_cooldown = move_toward(animation_cooldown, 0.0, delta)
		if input.dodge_down && could_dodge && animation_cooldown <= DODGE_ANIMATION_CANCEL_WINDOW && !input.direction.is_zero_approx():
			var dodge_direction: Vector3 = input.direction.normalized()
			current_velocity = dodge_direction * DODGE_HORIZONTAL_VELOCITY
			current_velocity += Vector3.UP * DODGE_VERTICAL_VELOCITY
			current_state = EPlayerState.AIRBORNE
			stun_duration_on_landing = DODGE_LANDING_COOLDOWN
			# TODO Spawn a poof
	
	# Camera
	var camera_horizontal_input = input.camera_horizontal
	current_camera_offset = current_camera_offset.rotated(Vector3.UP, camera_horizontal_input * CAMERA_ROTATE_SPEED * delta)
	# TODO Rotate to follow the player if they start moving for a couple seconds without camera input
	var camera_look_at_target = global_position + Vector3.UP * CAMERA_OVERHEAD_TARGET
	var current_camera_distance = CAMERA_STANDARD_DISTANCE
	var camera_horizontal_direction = Vector2(current_camera_offset.x, current_camera_offset.z).normalized() * current_camera_distance
	var camera_target_offset = Vector3(camera_horizontal_direction.x, CAMERA_HEIGHT, camera_horizontal_direction.y)
	var previous_camera_offset_length = current_camera_offset.length()
	var target_camera_offset_length = camera_target_offset.length()
	var camera_wall_check_length = max(target_camera_offset_length, previous_camera_offset_length)
	var camera_wall_check = PhysicsRayQueryParameters3D.create(camera_look_at_target, camera_look_at_target + camera_target_offset.normalized() * camera_wall_check_length, KobPhysics.PHYSICS_TERRAIN_MINUS_CAMERA_PASSTHROUGH)
	var camera_wall_check_result = world.intersect_ray(camera_wall_check)
	var new_length: float
	var wall_distance = INF
	if camera_wall_check_result:
		if DEBUG_CAMERA: print("camera hitting " + camera_wall_check_result.collider.name + ", length " + str(new_length))
		wall_distance = camera_look_at_target.distance_to(camera_wall_check_result.position) + CAMERA_MINIMUM_DISTANCE
	else:
		if DEBUG_CAMERA: print("camera free, length " + str(new_length))
	if wall_distance <= previous_camera_offset_length || wall_distance <= CAMERA_MINIMUM_DISTANCE:
		new_length = max(wall_distance, CAMERA_MINIMUM_DISTANCE)
	else:
		var target_distance_to_ease_to = min(target_camera_offset_length, wall_distance)
		new_length = move_toward(previous_camera_offset_length, target_distance_to_ease_to, delta * CAMERA_WALL_RECOVER_SPEED)
	current_camera_offset = camera_target_offset.normalized() * new_length
	if !current_camera_offset.is_finite():
		printerr("current_camera_offset is NaN, resetting")
		current_camera_offset = Vector3.ONE
	camera.global_position = camera_look_at_target + current_camera_offset
	camera.look_at(camera_look_at_target)
	
	# Rendering
	glider_renderer.set_visible(using_glider)
	($CanvasGroup/StateLabel as Label).text = (
		EPlayerState.find_key(current_state)
		+ "\n" + KobPhysics.vector3_to_pretty_string(global_position)
		+ "\n" + KobPhysics.vector3_to_pretty_string(current_velocity)
		+ "\n" + "%.2f" % animation_cooldown
	)
	
	# Debug Cheats
	if Input.is_key_pressed(KEY_F4):
		if Input.is_action_just_pressed("ui_up"):
			global_position += input_forward_facing * 20.0
		if Input.is_action_just_pressed("camera_right"):
			global_position += Vector3.UP * 10.0
		if Input.is_action_just_pressed("camera_left"):
			$Capsule.set_visible(!$Capsule.visible)
	if Input.is_action_just_pressed("reset_level"):
		get_tree().reload_current_scene()

func _process_get_input():
	var input = {}
	input.x = Input.get_axis("ui_left", "ui_right")
	input.y = Input.get_axis("ui_down", "ui_up")
	if Input.is_key_pressed(KEY_SHIFT):
		input.x *= 0.5
		input.y *= 0.5
	input.camera_horizontal = horizontal_camera_invert * Input.get_axis("camera_left", "camera_right")
	input.sword = Input.is_action_pressed("sword")
	input.sword_down = Input.is_action_just_pressed("sword")
	input.sword_up = Input.is_action_just_released("sword")
	input.context = Input.is_action_pressed("context_parry")
	input.context_down = Input.is_action_just_pressed("context_parry")
	input.dodge = Input.is_action_pressed("dodge")
	input.dodge_down = Input.is_action_just_pressed("dodge")
	input.bow = Input.is_action_pressed("bow")
	input.bow_down = Input.is_action_just_pressed("bow")
	return input

func motor_walk(world: PhysicsDirectSpaceState3D, input, input_right_facing, input_forward_facing, delta):
	current_velocity = input.direction
	var is_sword_charging = current_sword_charge > 0.0
	if is_sword_charging:
		current_velocity *= CHARGE_ATTACK_WALK_SPEED
	else:
		current_velocity *= MOVE_SPEED
	var movement_offset: Vector3 = current_velocity * delta
	if !movement_offset.is_zero_approx():
		if !is_sword_charging:
			current_facing = movement_offset.normalized()
			$Capsule.look_at(global_position + movement_offset)
	else:
		# Jitter the player so that pushing off of nearby moving objects still works.
		var jitter_sign = 1.0 if (current_frame_count % 2 == 1) else -1.0
		movement_offset = jitter_sign * Vector3(0.0001, 0.0, 0.0001)
	var output = KobPhysics.move_actor(self, world, movement_offset, PLAYER_RADIUS, PLAYER_HALF_HEIGHT)
	return output

func motor_climb(world: PhysicsDirectSpaceState3D, input, delta):
	var output = {}
	output.current_surface = null
	# We don't care where the camera is. Climb based on the normal plane of the surface we're on.
	var has_input = !input.direction.is_zero_approx()
	var input_forward_facing = current_facing.normalized()
	var climbing_plane = Plane(-input_forward_facing)
	var input_up_facing = climbing_plane.project(Vector3.UP).normalized()
	var input_right_facing = input_forward_facing.cross(input_up_facing)
	var climbing_raycast_target = global_position + input_forward_facing * (CLIMB_WALL_GRAB_DISTANCE + PLAYER_RADIUS * 0.5)
	var center_check = PhysicsRayQueryParameters3D.create(global_position, climbing_raycast_target, KobPhysics.PHYSICS_CLIMBABLE)
	var horizontal_normals = []
	var vertical_normals = []
	var center_result = world.intersect_ray(center_check)
	# Check above the player and to their sides to gradually match changes in the surface and allow them to climb around corners
	# Because we're casting to the point in front of the player, the side casts come in at an angle and can detect the wall edges of 90 degree corners.
	if center_result && center_result.normal.y != 1.0 && center_result.normal.y != -1.0:
		output.current_surface = center_result.collider
		horizontal_normals.append(center_result.normal)
		vertical_normals.append(center_result.normal)
		var wall_to_self = global_position - center_result.position
		global_position = center_result.position + wall_to_self.normalized() * PLAYER_RADIUS
	var up_offset = input_up_facing * CLIMB_WALL_GRAB_DISTANCE
	for i in 4:
		var this_check_offset = up_offset.rotated(input_forward_facing, i * PI * 0.5)
		var check_start = global_position + this_check_offset
		# Look past the raycast target so that if we're on one side of a 90-degree corner and our center raycast misses, the right raycast will still be able to hit the next side.
		var to_raycast_target = climbing_raycast_target - check_start
		var raycast = PhysicsRayQueryParameters3D.create(check_start, check_start + to_raycast_target * 2.0, KobPhysics.PHYSICS_CLIMBABLE)
		var raycast_result = world.intersect_ray(raycast)
		if raycast_result:
			#DebugDraw.draw_line(raycast_result.position, raycast_result.position + raycast_result.normal * 0.25, Color.CYAN, 0.5)
			if output.current_surface == null:
				output.current_surface = raycast_result.collider
			if i % 2 == 0:
				vertical_normals.append(raycast_result.normal)
			else:
				horizontal_normals.append(raycast_result.normal)
	# The above stuff happens because we need to be sure the surface we're on still exists. Now check movement and facing.
	if has_input:
		if horizontal_normals.size() > 0 || vertical_normals.size() > 0:
			var average_surface_normal = Vector3.ZERO
			if horizontal_normals.size() > 0:
				for i in horizontal_normals.size():
					var this_part_fraction = 0.5 / horizontal_normals.size()
					average_surface_normal += horizontal_normals[i] * this_part_fraction
			if vertical_normals.size() > 0:
				for i in vertical_normals.size():
					var this_part_fraction = 0.5 / vertical_normals.size()
					average_surface_normal += vertical_normals[i] * this_part_fraction
			if horizontal_normals.size() == 0 || vertical_normals.size() == 0:
				average_surface_normal *= 2.0
			current_facing = current_facing.move_toward(-average_surface_normal, delta * CLIMB_ROTATE_SPEED_RADIANS_PER_SECOND).normalized()
			if !current_facing.is_equal_approx(Vector3.UP) && !current_facing.is_equal_approx(Vector3.DOWN):
				if DEBUG_CLIMBING: DebugDraw.draw_line(climbing_raycast_target, climbing_raycast_target + average_surface_normal * CLIMB_WALL_GRAB_DISTANCE * 2.0, Color.BLUE, 1.0)
				var movement_offset = (input.x * input_right_facing + input.y * input_up_facing) * CLIMB_SPEED
				#print("currently climbing in direction " + str(movement_offset))
				movement_offset *= delta
				KobPhysics.move_actor(self, world, movement_offset, PLAYER_RADIUS)
				#print("climbing position is now " + str(global_position) + " facing " + str(average_surface_normal) + " => (" + str(current_facing) + ")")
			else:
				printerr("TODO: What to do if they're crawling on the ground or on a flat ceiling?")
				output.current_surface = null
				current_facing = -camera.basis.z.normalized()
				current_facing.y = 0.0
				current_facing = current_facing.normalized()
				if current_facing.is_zero_approx():
					current_facing = Vector3.FORWARD
				animation_cooldown = DODGE_LANDING_COOLDOWN
			$Capsule.look_at(global_position + current_facing)
		else:
			output.current_surface = null
	#if output.current_surface == null:
	#	DebugDraw.draw_line(global_position, climbing_raycast_target, Color.RED, 5.0)
	return output

func attempt_climbable_wall_grab(world: PhysicsDirectSpaceState3D, input_right_facing: Vector3, input_forward_facing: Vector3):
	var found_wall = false
	var wall_check_start = global_position
	var forward_wall_check = PhysicsRayQueryParameters3D.create(wall_check_start, wall_check_start + input_forward_facing * CLIMB_WALL_GRAB_DISTANCE, KobPhysics.PHYSICS_CLIMBABLE)
	var forward_wall_result = world.intersect_ray(forward_wall_check)
	if forward_wall_result:
		found_wall = true
		current_facing = -forward_wall_result.normal
	return found_wall

func attempt_ledge_grab(world: PhysicsDirectSpaceState3D):
	var output = {}
	output.found_ledge = false
	var wall_check_target = global_position + current_facing * CLIMB_WALL_GRAB_DISTANCE
	var facing_wall_result = world.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, wall_check_target, KobPhysics.PHYSICS_TERRAIN))
	if facing_wall_result:
		var start = facing_wall_result.position + facing_wall_result.normal * LEDGE_GRAB_CLIMB_INWARDS_DISTANCE
		if DEBUG_CLIMBING: DebugDraw.draw_line(facing_wall_result.position, start, Color.LIME, 1.0)
		var over_head_target = start + Vector3.UP * LEDGE_GRAB_MAXIMUM_HEIGHT
		var over_ledge_target = over_head_target - facing_wall_result.normal * LEDGE_GRAB_CLIMB_INWARDS_DISTANCE * 2.0
		var on_ledge_target = over_ledge_target - Vector3.UP * (LEDGE_GRAB_MAXIMUM_HEIGHT)
		if !world.intersect_ray(PhysicsRayQueryParameters3D.create(start, over_head_target, KobPhysics.PHYSICS_TERRAIN)):
			if DEBUG_CLIMBING: DebugDraw.draw_line(start, over_head_target, Color.LIME, 1.0)
			if !world.intersect_ray(PhysicsRayQueryParameters3D.create(over_head_target, over_ledge_target, KobPhysics.PHYSICS_TERRAIN)):
				if DEBUG_CLIMBING: DebugDraw.draw_line(over_head_target, over_ledge_target, Color.LIME, 1.0)
				var ledge_result = world.intersect_ray(PhysicsRayQueryParameters3D.create(over_ledge_target, on_ledge_target, KobPhysics.PHYSICS_TERRAIN))
				if ledge_result && Vector3.UP.angle_to(ledge_result.normal) < WALKING_SLOPE_MAXIMUM_RADIANS:
					if DEBUG_CLIMBING: DebugDraw.draw_line(over_ledge_target, ledge_result.position, Color.LIME, 1.0)
					output.found_ledge = true
					output.pull_to = ledge_result.position + Vector3.UP * PLAYER_HALF_HEIGHT
					output.corner = facing_wall_result.position
					output.corner.y = ledge_result.position.y
					var corner_to_pull_target = output.pull_to - output.corner
					output.facing = Vector3(corner_to_pull_target.x, 0.0, corner_to_pull_target.z).normalized()
				else:
					if DEBUG_CLIMBING: print("Discarding ledge result, could not find a place to stand on top")
			else:
				if DEBUG_CLIMBING: DebugDraw.draw_line(over_head_target, over_ledge_target, Color.RED, 1.0)
		else:
			if DEBUG_CLIMBING: DebugDraw.draw_line(start, over_head_target, Color.RED, 1.0)
	else:
		if DEBUG_CLIMBING: DebugDraw.draw_line(global_position, wall_check_target, Color.RED, 1.0)
	return output

var current_juggling_score = 0

func add_juggling_score():
	current_juggling_score += 1
	$CanvasGroup/ScoreLabel.text = "SCORE: %d" % current_juggling_score

static func set_drop_shadow_position(next_shadow: Node3D, target_position: Vector3, up: Vector3):
	if DEBUG_SHADOW: print("set_drop_shadow_position " + str(target_position) + ", " + str(up))
	next_shadow.global_position = target_position
	if up.is_equal_approx(Vector3.UP):
		next_shadow.scale.z = next_shadow.scale.x
		next_shadow.look_at(target_position + Vector3.FORWARD)
	else:
		var shadow_facing = Vector3(up.x, 0.0, up.z).normalized()
		var normal_plane: Plane = Plane(up)
		next_shadow.look_at(target_position + normal_plane.project(shadow_facing), up)
		var shadow_length = clampf(tan(up.angle_to(Vector3.UP)), 1.0, 10.0) * next_shadow.scale.x
		next_shadow.scale.z = shadow_length
