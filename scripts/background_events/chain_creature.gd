extends Node3D

var start_point := Vector3.ZERO
var goal_point := Vector3.ZERO

var _creature: Dictionary = {}


func setup(config: Dictionary, rng: RandomNumberGenerator) -> void:
	start_point = config["start_point"] as Vector3
	goal_point = config["goal_point"] as Vector3

	var material := _make_glow_material(Color("#74ffd6"))
	material.emission_energy_multiplier = 1.8
	var segments: Array[Node3D] = []

	for index in 18:
		var segment := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = lerpf(0.18, 0.09, float(index) / 17.0)
		mesh.height = mesh.radius * 2.0
		segment.mesh = mesh
		segment.material_override = material
		add_child(segment)
		segments.append(segment)

	var light := OmniLight3D.new()
	light.light_color = Color("#74ffd6")
	light.light_energy = 1.1
	light.omni_range = 10.0
	add_child(light)

	_creature = {
		"segments": segments,
		"light": light,
		"west": rng.randf() < 0.5,
		"phase": rng.randf_range(0.0, TAU),
		"speed": rng.randf_range(0.42, 0.7),
		"z": rng.randf_range(-58.0, 58.0),
		"height": rng.randf_range(20.0, 54.0),
		"reach": rng.randf_range(7.0, 13.0),
	}


func get_debug_name() -> String:
	return "chain creature"


func process_effect(_delta: float, elapsed: float, _player: CharacterBody3D) -> void:
	if _creature.is_empty():
		return

	var west := bool(_creature["west"])
	var wall_x := start_point.x - 22.0 if west else goal_point.x + 26.0
	var face := 1.0 if west else -1.0
	var phase := elapsed * float(_creature["speed"]) + float(_creature["phase"])
	var z := float(_creature["z"]) + sin(phase * 0.37) * 18.0
	var height := float(_creature["height"]) + sin(phase * 0.53) * 8.0
	var reach := float(_creature["reach"])
	var anchor_a := Vector3(wall_x, height, z)
	var anchor_b := Vector3(
		wall_x + face * (reach + sin(phase) * 5.5),
		height - 9.0 + cos(phase * 1.4) * 7.0,
		z + sin(phase * 0.9) * 13.0
	)
	var segments: Array = _creature["segments"]
	for index in segments.size():
		var t := float(index) / float(segments.size() - 1)
		var sag := sin(t * PI) * (5.5 + absf(sin(phase)) * 3.0)
		var sway := sin(phase * 1.7 + t * TAU) * 1.2
		var segment := segments[index] as Node3D
		segment.position = anchor_a.lerp(anchor_b, t) + Vector3(0.0, -sag, sway)

	var light := _creature["light"] as OmniLight3D
	light.position = anchor_a.lerp(anchor_b, 0.65) + Vector3(0.0, -3.0, 0.0)
	light.light_energy = 0.8 + absf(sin(phase * 2.0)) * 0.7


func _make_glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	return material
