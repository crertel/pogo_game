extends Node3D

const TentacleNoiseShader := preload("res://shaders/tentacle_noise.gdshader")

const TARGET_MAX_SPEED := 13.0
const JOINT_MAX_ROTATION := 1.8
const JOINT_MAX_BEND := deg_to_rad(42.0)

var start_point := Vector3.ZERO
var goal_point := Vector3.ZERO

var _bundle: Dictionary = {}


func setup(config: Dictionary, rng: RandomNumberGenerator) -> void:
	start_point = config["start_point"] as Vector3
	goal_point = config["goal_point"] as Vector3

	var material := _make_tentacle_material()
	var center_x := (start_point.x + goal_point.x) * 0.5
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var anchor := Vector3(
		center_x + rng.randf_range(-24.0, 24.0),
		rng.randf_range(-23.5, -18.0),
		side * rng.randf_range(24.0, 36.0)
	)
	var tentacles: Array[Dictionary] = []

	for _tentacle_index in 11:
		var segments: Array[MeshInstance3D] = []
		var points: Array[Vector3] = []
		var length := rng.randf_range(56.0, 76.0)
		var segment_length := length / 10.0
		var root_offset := Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(-2.5, 2.5), rng.randf_range(-12.0, 12.0))
		var angle := rng.randf_range(0.0, TAU)
		var initial_direction := Vector3(cos(angle) * 0.2, 1.0, side * absf(sin(angle)) * 0.16).normalized()
		for point_index in 11:
			points.append(anchor + root_offset + initial_direction * segment_length * float(point_index))

		for segment_index in 10:
			var segment := MeshInstance3D.new()
			segment.name = "TentacleSegment"
			var mesh := CylinderMesh.new()
			var taper := float(segment_index) / 9.0
			mesh.top_radius = lerpf(1.15, 0.34, taper)
			mesh.bottom_radius = lerpf(1.28, 0.4, taper)
			mesh.height = 1.0
			mesh.radial_segments = 10
			segment.mesh = mesh
			segment.material_override = material
			add_child(segment)
			segments.append(segment)

		tentacles.append({
			"segments": segments,
			"points": points,
			"phase": rng.randf_range(0.0, TAU),
			"angle": angle,
			"segment_length": segment_length,
			"target": anchor + root_offset + initial_direction * length,
			"tracking_point": anchor + root_offset + initial_direction * length,
			"target_bias": rng.randf_range(0.0, TAU),
			"sway": rng.randf_range(8.0, 22.0),
			"speed": rng.randf_range(0.22, 0.48),
			"root_offset": root_offset,
		})

	var light := OmniLight3D.new()
	light.light_color = Color("#6f1dff")
	light.light_energy = 3.6
	light.omni_range = 82.0
	add_child(light)

	_bundle = {
		"anchor": anchor,
		"side": side,
		"tentacles": tentacles,
		"light": light,
		"phase": rng.randf_range(0.0, TAU),
	}


func get_debug_name() -> String:
	return "tentacle bundle"


func process_effect(delta: float, elapsed: float, _player: CharacterBody3D) -> void:
	if _bundle.is_empty():
		return

	var anchor := _bundle["anchor"] as Vector3
	var side := float(_bundle["side"])
	var phase := elapsed * 0.16 + float(_bundle["phase"])
	var bundle_anchor := anchor + Vector3(
		sin(phase * 0.7) * 7.0,
		sin(phase * 0.43) * 1.2,
		cos(phase * 0.5) * 6.0
	)
	var tentacles: Array = _bundle["tentacles"]
	for tentacle in tentacles:
		var entry := tentacle as Dictionary
		var segments: Array = entry["segments"]
		var points: Array = entry["points"]
		var tentacle_phase := elapsed * float(entry["speed"]) + float(entry["phase"])
		var sway := float(entry["sway"])
		var root_offset := entry["root_offset"] as Vector3
		var old_root := points[0] as Vector3
		var new_root := bundle_anchor + root_offset
		var root_shift := new_root - old_root
		for point_index in points.size():
			points[point_index] = (points[point_index] as Vector3) + root_shift
		points[0] = new_root

		var target := entry["target"] as Vector3
		if (points[points.size() - 1] as Vector3).distance_to(target) < 2.5:
			target = _choose_target(new_root, side, float(entry["segment_length"]) * float(segments.size()))
			entry["target"] = target

		var wander := Vector3(
			sin(tentacle_phase + float(entry["target_bias"])) * sway,
			sin(tentacle_phase * 1.7) * 2.5,
			cos(tentacle_phase * 0.8 + float(entry["target_bias"])) * sway * 0.55
		)
		var desired_tracking_point := target + wander
		var tracking_point := entry["tracking_point"] as Vector3
		var target_offset := desired_tracking_point - tracking_point
		var max_target_step := TARGET_MAX_SPEED * delta
		if target_offset.length() > max_target_step and target_offset.length() > 0.001:
			tracking_point += target_offset.normalized() * max_target_step
		else:
			tracking_point = desired_tracking_point
		entry["tracking_point"] = tracking_point
		_solve_ccd(points, tracking_point, float(entry["segment_length"]), delta)

		for index in segments.size():
			_place_cylinder_between(segments[index] as Node3D, points[index] as Vector3, points[index + 1] as Vector3)

	var light := _bundle["light"] as OmniLight3D
	light.position = bundle_anchor + Vector3(0.0, 8.0 + sin(phase * 2.2) * 2.0, side * 6.0)
	light.light_energy = 2.8 + absf(sin(phase * 1.7)) * 2.1


func _choose_target(root: Vector3, side: float, reach: float) -> Vector3:
	if randf() < 0.16:
		return Vector3(
			randf_range(start_point.x + 10.0, goal_point.x - 10.0),
			randf_range(-0.5, 5.5),
			side * randf_range(7.0, 18.0)
		)

	var angle := randf_range(0.0, TAU)
	var distance := randf_range(reach * 0.45, reach * 0.9)
	return root + Vector3(
		cos(angle) * distance * 0.42,
		randf_range(reach * 0.35, reach * 0.9),
		side * randf_range(4.0, 18.0) + sin(angle) * distance * 0.18
	)


func _solve_ccd(points: Array, target: Vector3, segment_length: float, delta: float) -> void:
	var tip_index := points.size() - 1
	var max_angle := delta * JOINT_MAX_ROTATION
	for _iteration in 4:
		for joint_index in range(tip_index - 1, -1, -1):
			var pivot := points[joint_index] as Vector3
			var to_tip := (points[tip_index] as Vector3) - pivot
			var to_target := target - pivot
			if to_tip.length() <= 0.001 or to_target.length() <= 0.001:
				continue

			var axis := to_tip.cross(to_target)
			if axis.length() <= 0.001:
				continue

			var angle := minf(to_tip.angle_to(to_target), max_angle)
			var rotation := Basis(axis.normalized(), angle)
			for point_index in range(joint_index + 1, points.size()):
				points[point_index] = pivot + rotation * ((points[point_index] as Vector3) - pivot)

		points[0] = points[0] as Vector3
		for point_index in range(1, points.size()):
			var previous := points[point_index - 1] as Vector3
			var current := points[point_index] as Vector3
			var direction := current - previous
			if direction.length() <= 0.001:
				direction = Vector3.UP
			points[point_index] = previous + direction.normalized() * segment_length

		_limit_bends(points, segment_length)


func _limit_bends(points: Array, segment_length: float) -> void:
	for point_index in range(2, points.size()):
		var pivot := points[point_index - 1] as Vector3
		var previous_direction := (pivot - (points[point_index - 2] as Vector3)).normalized()
		var current_direction := ((points[point_index] as Vector3) - pivot).normalized()
		if previous_direction.length() <= 0.001 or current_direction.length() <= 0.001:
			continue

		var bend_angle := previous_direction.angle_to(current_direction)
		if bend_angle <= JOINT_MAX_BEND:
			points[point_index] = pivot + current_direction * segment_length
			continue

		var axis := previous_direction.cross(current_direction)
		if axis.length() <= 0.001:
			current_direction = previous_direction
		else:
			current_direction = Basis(axis.normalized(), JOINT_MAX_BEND) * previous_direction
		points[point_index] = pivot + current_direction.normalized() * segment_length


func _place_cylinder_between(node: Node3D, start: Vector3, end: Vector3) -> void:
	var distance := start.distance_to(end)
	if distance <= 0.001:
		return
	if node is MeshInstance3D:
		var cylinder := (node as MeshInstance3D).mesh as CylinderMesh
		if cylinder != null:
			cylinder.height = distance
	node.position = (start + end) * 0.5
	node.look_at(end, Vector3.UP)
	node.rotate_object_local(Vector3.RIGHT, PI * 0.5)


func _make_tentacle_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TentacleNoiseShader
	material.set_shader_parameter("base_color", Color("#03081d"))
	material.set_shader_parameter("glow_color", Color("#7b16ff"))
	material.set_shader_parameter("noise_scale", 1.35)
	material.set_shader_parameter("noise_speed", 0.16)
	material.set_shader_parameter("glow_strength", 3.4)
	return material
