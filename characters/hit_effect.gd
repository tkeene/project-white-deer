extends Node3D

@export var size_over_time : Curve
const LIFETIME_SECONDS = 1.0

var current_time = 0.0

func initialize(position: Vector3, hit_direction: Vector3):
	look_at_from_position(position, position + hit_direction)

func _process(delta):
	current_time += delta
	scale = Vector3.ONE * size_over_time.sample(current_time / LIFETIME_SECONDS)
