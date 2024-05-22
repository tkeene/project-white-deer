extends Area3D

static var hit_effect: PackedScene = preload("res://characters/hit_effect.tscn")

func _physics_process(_delta):
	var overlapped_bodies = get_overlapping_bodies()
	for next_body in overlapped_bodies:
		# TODO Hitting something should have a lot more info about owner, direction, damage, and type
		if next_body.can_hit():
			next_body.on_hit()
			var spawned_effect: Node3D = hit_effect.instantiate() as Node3D
			next_body.owner.add_child(spawned_effect)
			spawned_effect.initialize((global_position + next_body.global_position) * 0.5, -transform.basis.z)
