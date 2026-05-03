extends Node3D

const PlayerScene := preload("res://scenes/player.tscn")

const HEX_RADIUS := 1.55
const HEX_HEIGHT := 0.55
const PATH_SUBDIVISIONS := 5
const PATH_POINTS := (1 << PATH_SUBDIVISIONS) + 1
const START_POINT := Vector3(-7.0, 0.0, 0.0)
const GOAL_POINT := Vector3(82.0, 0.0, 0.0)
const MAX_HORIZONTAL_STEP := 4.4
const MAX_VERTICAL_STEP := 1.05
const HORIZONTAL_DISPLACEMENT := 11.0
const VERTICAL_DISPLACEMENT := 4.8
const FALL_LIMIT := -18.0
const FIREFLY_COUNT := 46
const VOID_LIGHT_COUNT := 10
const FOG_BAND_COUNT := 18

var _player: CharacterBody3D
var _status_label: Label
var _has_won := false
var _platform_materials: Array[StandardMaterial3D] = []
var _bridge_points: Array[Vector3] = []
var _fog_bands: Array[Node3D] = []
var _void_lights: Array[Dictionary] = []
var _fireflies: Array[Dictionary] = []


func _ready() -> void:
	_build_materials()
	_build_world()
	_spawn_player()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if _player != null and _player.global_position.y < FALL_LIMIT and not _has_won:
		_player.respawn()


func _process(delta: float) -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0

	for index in _fog_bands.size():
		var band := _fog_bands[index]
		band.rotate_y(delta * (0.08 + float(index % 5) * 0.015))
		band.position.z = sin(elapsed * 0.16 + float(index)) * 5.0

	for entry in _void_lights:
		var light := entry["light"] as OmniLight3D
		var glow := entry["glow"] as MeshInstance3D
		var phase: float = elapsed * float(entry["speed"]) + float(entry["phase"])
		var intensity: float = pow(maxf(sin(phase), 0.0), 2.8)
		var drift: Vector3 = Vector3(sin(phase * 0.37), sin(phase * 0.23), cos(phase * 0.31)) * float(entry["drift"])
		light.position = entry["origin"] as Vector3 + drift
		light.light_energy = intensity * float(entry["energy"])
		glow.position = light.position
		glow.scale = Vector3.ONE * (0.35 + intensity * 0.85)

	for entry in _fireflies:
		var bug := entry["node"] as Node3D
		var phase: float = elapsed * float(entry["speed"]) + float(entry["phase"])
		var bob := Vector3(0.0, sin(phase) * 0.22, cos(phase * 0.7) * 0.18)
		bug.position = entry["origin"] as Vector3 + bob


func _build_materials() -> void:
	_platform_materials = [
		_make_material(Color("#caa15a")),
		_make_material(Color("#d6b463")),
		_make_material(Color("#9fbf78")),
	]


func _build_world() -> void:
	_add_environment()
	_bridge_points = _generate_bridge_points()
	_add_start_pad()
	_add_hex_path()
	_add_goal()
	_add_void_fog()
	_add_void_lights()
	_add_fireflies()


func _add_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#020308")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#405268")
	environment.ambient_light_energy = 0.38
	environment.fog_enabled = true
	environment.fog_light_color = Color("#53657b")
	environment.fog_density = 0.028
	environment.fog_sky_affect = 0.82
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _add_start_pad() -> void:
	_add_hex_platform(START_POINT + Vector3(-3.2, 0.0, 0.0), HEX_RADIUS * 1.35, Color("#3f8f67"))
	_add_hex_platform(START_POINT, HEX_RADIUS * 1.35, Color("#3f8f67"))


func _add_hex_path() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for index in _bridge_points.size():
		var point := _bridge_points[index]
		var color := _platform_materials[index % _platform_materials.size()].albedo_color
		_add_hex_platform(point, HEX_RADIUS, color)

		if index > 3 and index < _bridge_points.size() - 4 and rng.randf() < 0.34:
			var offset_direction := -1.0 if rng.randf() < 0.5 else 1.0
			var side_step := Vector3(0.0, rng.randf_range(-0.35, 0.35), offset_direction * rng.randf_range(3.1, 3.8))
			_add_hex_platform(point + side_step, HEX_RADIUS * 0.86, Color("#829b67"))


func _add_goal() -> void:
	var goal_point := _bridge_points[_bridge_points.size() - 1]
	_add_hex_platform(goal_point + Vector3(3.2, 0.0, 0.0), HEX_RADIUS * 1.35, Color("#3f8f67"))

	var goal := Area3D.new()
	goal.name = "Goal"
	goal.position = goal_point + Vector3(3.2, 1.4, 0.0)
	goal.body_entered.connect(_on_goal_body_entered)
	add_child(goal)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.4, 2.8, 3.4)
	shape.shape = box
	goal.add_child(shape)

	var marker := MeshInstance3D.new()
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 1.15
	marker_mesh.bottom_radius = 1.15
	marker_mesh.height = 2.5
	marker_mesh.radial_segments = 6
	marker.mesh = marker_mesh
	marker.material_override = _make_material(Color("#69e38f"))
	goal.add_child(marker)


func _add_hex_platform(center: Vector3, radius: float, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius * 0.92
	cylinder.height = HEX_HEIGHT
	shape.shape = cylinder
	body.add_child(shape)

	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.86
	mesh.bottom_radius = radius * 0.96
	mesh.height = HEX_HEIGHT
	mesh.radial_segments = 6
	visual.mesh = mesh
	visual.material_override = _make_material(color)
	body.add_child(visual)

	return body


func _add_void_fog() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for index in FOG_BAND_COUNT:
		var fog := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(rng.randf_range(18.0, 34.0), rng.randf_range(5.0, 11.0))
		fog.mesh = mesh
		fog.position = Vector3(
			lerpf(START_POINT.x - 6.0, GOAL_POINT.x + 8.0, float(index) / float(FOG_BAND_COUNT - 1)),
			rng.randf_range(-9.5, -5.0),
			rng.randf_range(-15.0, 15.0)
		)
		fog.rotation_degrees = Vector3(90.0, rng.randf_range(0.0, 360.0), 0.0)
		fog.material_override = _make_transparent_material(Color(0.34, 0.45, 0.58, rng.randf_range(0.055, 0.12)))
		add_child(fog)
		_fog_bands.append(fog)


func _add_void_lights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for _index in VOID_LIGHT_COUNT:
		var origin := Vector3(
			rng.randf_range(START_POINT.x + 2.0, GOAL_POINT.x - 2.0),
			rng.randf_range(-11.0, -4.5),
			rng.randf_range(-17.0, 17.0)
		)
		var light := OmniLight3D.new()
		light.position = origin
		light.light_color = Color("#86d7ff")
		light.omni_range = rng.randf_range(5.0, 9.0)
		light.light_energy = 0.0
		add_child(light)

		var glow := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.44
		glow.mesh = mesh
		glow.position = origin
		glow.material_override = _make_glow_material(Color("#86d7ff"))
		add_child(glow)

		_void_lights.append({
			"light": light,
			"glow": glow,
			"origin": origin,
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.22, 0.55),
			"energy": rng.randf_range(1.1, 2.6),
			"drift": rng.randf_range(1.0, 3.6),
		})


func _add_fireflies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for index in FIREFLY_COUNT:
		var path_index := rng.randi_range(0, _bridge_points.size() - 1)
		var point := _bridge_points[path_index]
		var node := Node3D.new()
		node.position = point + Vector3(
			rng.randf_range(-1.2, 1.2),
			rng.randf_range(1.0, 2.6),
			rng.randf_range(-1.2, 1.2)
		)
		add_child(node)

		var glow := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.055
		mesh.height = 0.11
		glow.mesh = mesh
		glow.material_override = _make_glow_material(Color("#d5ff85"))
		node.add_child(glow)

		var light := OmniLight3D.new()
		light.light_color = Color("#d5ff85")
		light.light_energy = 0.18
		light.omni_range = 1.4
		node.add_child(light)

		_fireflies.append({
			"node": node,
			"origin": node.position,
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(1.2, 2.4),
		})


func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	_player.position = START_POINT + Vector3(-3.2, 2.2, 0.0)
	add_child(_player)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_status_label = Label.new()
	_status_label.position = Vector2(24.0, 20.0)
	_status_label.text = "Cross the hex chasm. WASD moves, mouse looks, Space jumps, R restarts."
	_status_label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(_status_label)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	return material


func _make_transparent_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material


func _make_glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	return material


func _generate_bridge_points() -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var points: Array[Vector3] = []
	points.resize(PATH_POINTS)
	points[0] = START_POINT
	points[PATH_POINTS - 1] = GOAL_POINT

	_displace_horizontal(points, 0, PATH_POINTS - 1, HORIZONTAL_DISPLACEMENT, rng)
	_displace_vertical(points, 0, PATH_POINTS - 1, VERTICAL_DISPLACEMENT, rng)
	_clamp_bridge_steps(points)
	return points


func _displace_horizontal(points: Array[Vector3], start: int, end: int, amount: float, rng: RandomNumberGenerator) -> void:
	if end - start <= 1:
		return

	var middle := (start + end) / 2
	var midpoint := (points[start] + points[end]) * 0.5
	midpoint.z += rng.randf_range(-amount, amount)
	midpoint.z = clampf(midpoint.z, -9.5, 9.5)
	points[middle] = midpoint

	var next_amount := minf(amount * 0.54, MAX_HORIZONTAL_STEP)
	_displace_horizontal(points, start, middle, next_amount, rng)
	_displace_horizontal(points, middle, end, next_amount, rng)


func _displace_vertical(points: Array[Vector3], start: int, end: int, amount: float, rng: RandomNumberGenerator) -> void:
	if end - start <= 1:
		return

	var middle := (start + end) / 2
	var midpoint := (points[start] + points[end]) * 0.5
	midpoint.y += rng.randf_range(-amount, amount)
	midpoint.y = clampf(midpoint.y, -3.2, 3.8)
	points[middle] = midpoint

	var next_amount := minf(amount * 0.52, MAX_VERTICAL_STEP)
	_displace_vertical(points, start, middle, next_amount, rng)
	_displace_vertical(points, middle, end, next_amount, rng)


func _clamp_bridge_steps(points: Array[Vector3]) -> void:
	points[0] = START_POINT
	points[points.size() - 1] = GOAL_POINT

	for _pass in 3:
		for index in range(1, points.size() - 1):
			points[index] = _clamp_point_from_previous(points[index - 1], points[index])

		for index in range(points.size() - 2, 0, -1):
			points[index] = _clamp_point_from_next(points[index], points[index + 1])


func _clamp_point_from_previous(previous: Vector3, current: Vector3) -> Vector3:
	var horizontal_delta := Vector2(current.x - previous.x, current.z - previous.z)
	if horizontal_delta.length() > MAX_HORIZONTAL_STEP:
		horizontal_delta = horizontal_delta.normalized() * MAX_HORIZONTAL_STEP
		current.x = previous.x + horizontal_delta.x
		current.z = previous.z + horizontal_delta.y

	current.y = clampf(current.y, previous.y - MAX_VERTICAL_STEP, previous.y + MAX_VERTICAL_STEP)
	return current


func _clamp_point_from_next(current: Vector3, next: Vector3) -> Vector3:
	var horizontal_delta := Vector2(current.x - next.x, current.z - next.z)
	if horizontal_delta.length() > MAX_HORIZONTAL_STEP:
		horizontal_delta = horizontal_delta.normalized() * MAX_HORIZONTAL_STEP
		current.x = next.x + horizontal_delta.x
		current.z = next.z + horizontal_delta.y

	current.y = clampf(current.y, next.y - MAX_VERTICAL_STEP, next.y + MAX_VERTICAL_STEP)
	return current


func _add_box(center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _make_material(color)
	body.add_child(visual)

	return body


func _on_goal_body_entered(body: Node3D) -> void:
	if body == _player and not _has_won:
		_has_won = true
		_status_label.text = "Goal reached. R restarts."
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
