extends Node3D

var start_point := Vector3.ZERO
var goal_point := Vector3.ZERO

var _bolts: Array[Dictionary] = []


func setup(config: Dictionary, rng: RandomNumberGenerator) -> void:
	start_point = config["start_point"] as Vector3
	goal_point = config["goal_point"] as Vector3

	for index in 3:
		var bolt := Node3D.new()
		add_child(bolt)
		var light := OmniLight3D.new()
		light.light_color = Color("#9eeaff")
		light.light_energy = 0.0
		light.omni_range = 70.0
		light.position = Vector3((start_point.x + goal_point.x) * 0.5, -3.0, 0.0)
		bolt.add_child(light)
		_bolts.append({
			"root": bolt,
			"light": light,
			"next_strike": rng.randf_range(0.6, 4.8) + float(index) * 1.2,
			"flash": 0.0,
			"seed": rng.randi(),
		})


func get_debug_name() -> String:
	return "chain lightning"


func process_effect(delta: float, _elapsed: float, _player: CharacterBody3D) -> void:
	for entry in _bolts:
		entry["next_strike"] = float(entry["next_strike"]) - delta
		entry["flash"] = maxf(float(entry["flash"]) - delta * 2.8, 0.0)
		if float(entry["next_strike"]) <= 0.0:
			_strike(entry)

		var light := entry["light"] as OmniLight3D
		var flash := float(entry["flash"])
		light.light_energy = flash * flash * 14.0
		for child in (entry["root"] as Node3D).get_children():
			if child is MeshInstance3D:
				child.transparency = 1.0 - flash


func _strike(entry: Dictionary) -> void:
	var root := entry["root"] as Node3D
	for child in root.get_children():
		if child is MeshInstance3D:
			child.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry["seed"]) + Time.get_ticks_msec()
	entry["seed"] = rng.randi()
	entry["flash"] = 1.0
	entry["next_strike"] = rng.randf_range(1.7, 5.2)

	var center := Vector3(
		rng.randf_range(start_point.x + 14.0, goal_point.x - 14.0),
		rng.randf_range(-15.5, -11.0),
		rng.randf_range(-15.0, 15.0)
	)
	(entry["light"] as OmniLight3D).position = center + Vector3(0.0, 9.0, 0.0)

	var hits: Array[Vector3] = [center]
	var hit_count := rng.randi_range(5, 9)
	for index in range(1, hit_count):
		var previous := hits[rng.randi_range(0, hits.size() - 1)]
		var candidate := previous + Vector3(
			rng.randf_range(-18.0, 18.0),
			rng.randf_range(-1.2, 1.2),
			rng.randf_range(-20.0, 20.0)
		)
		candidate.x = clampf(candidate.x, start_point.x + 5.0, goal_point.x - 5.0)
		candidate.y = clampf(candidate.y, -16.5, -9.0)
		candidate.z = clampf(candidate.z, -58.0, 58.0)
		hits.append(candidate)

	for point in hits:
		_add_impact(root, point, rng.randf_range(2.4, 5.8))

	for index in range(1, hits.size()):
		var parent_index := maxi(0, index - rng.randi_range(1, mini(index, 3)))
		_add_path(root, hits[parent_index], hits[index], rng, rng.randf_range(0.09, 0.16))
		if index > 2 and rng.randf() < 0.36:
			_add_path(root, hits[index], hits[rng.randi_range(0, index - 1)], rng, rng.randf_range(0.055, 0.1))

	for point in hits:
		if rng.randf() < 0.24:
			var side := -1.0 if point.z < 0.0 else 1.0
			var cliff_point := Vector3(
				point.x + rng.randf_range(-6.0, 6.0),
				rng.randf_range(6.0, 38.0),
				side * rng.randf_range(68.0, 82.0)
			)
			_add_path(root, point, cliff_point, rng, rng.randf_range(0.06, 0.12))


func _add_path(root: Node3D, start: Vector3, end: Vector3, rng: RandomNumberGenerator, radius: float) -> void:
	var previous := start
	var steps := rng.randi_range(4, 8)
	for index in steps:
		var t := float(index + 1) / float(steps)
		var current := start.lerp(end, t) + Vector3(
			rng.randf_range(-2.2, 2.2),
			rng.randf_range(-0.8, 0.8),
			rng.randf_range(-2.2, 2.2)
		)
		if index == steps - 1:
			current = end
		_add_segment(root, previous, current, radius)
		previous = current


func _add_segment(root: Node3D, a: Vector3, b: Vector3, radius: float) -> void:
	var segment := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	segment.mesh = mesh
	var material := _make_glow_material(Color("#bff6ff"))
	material.emission_energy_multiplier = 5.5
	segment.material_override = material
	segment.position = (a + b) * 0.5
	root.add_child(segment)
	segment.look_at(b, Vector3.UP)
	segment.rotate_object_local(Vector3.RIGHT, PI * 0.5)


func _add_impact(root: Node3D, position: Vector3, radius: float) -> void:
	var impact := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(radius, radius)
	impact.mesh = mesh
	impact.position = position + Vector3(0.0, 0.04, 0.0)
	impact.rotation_degrees.x = -90.0
	impact.material_override = _make_impact_material(radius)
	root.add_child(impact)


func _make_glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	return material


func _make_impact_material(radius: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.55, 0.9, 1.0, 0.2)
	material.emission_enabled = true
	material.emission = Color("#aef4ff")
	material.emission_energy_multiplier = 1.8 + radius * 0.35
	return material
