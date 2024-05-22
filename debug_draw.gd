class_name DebugDraw

signal draw

static func draw_line(start, end, color, duration):
	# Unfortunately this plugin freezes HTML5 builds in Firefox. :(
	# https://github.com/DmitriySalnikov/godot_debug_draw_3d
	# You can test it in builds by
	# 1) uncommenting the following line
	# and 2) adding DebugDrawManager as a child of player.tscn
	#DebugDraw3D.draw_line(start, end, color, duration)
	# TODO Is there any way to bind the call using strings so we can use it in editor, check for builds, and ensure it doesn't cause runtime errors?
	pass
