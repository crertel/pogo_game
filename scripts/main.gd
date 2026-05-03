extends Node3D

const PlayerScene := preload("res://scenes/player.tscn")
const VoidFogShader := preload("res://shaders/void_fog.gdshader")
const MechanicHudScript := preload("res://scripts/mechanic_hud.gd")

const HEX_RADIUS := 1.55
const HEX_HEIGHT := 0.55
const HEX_GRID_SPACING := 3.25
const PATH_STEPS := 28
const PATH_POINTS := PATH_STEPS + 1
const START_POINT := Vector3(-7.0, 0.0, 0.0)
const GOAL_POINT := Vector3(84.0, 0.0, 0.0)
const MAX_HORIZONTAL_STEP := 4.4
const MAX_VERTICAL_STEP := 1.35
const MIN_VERTICAL_STEP := -1.65
const HEIGHT_MIN := -4.5
const HEIGHT_MAX := 8.5
const FALL_LIMIT := -18.0
const FIREFLY_COUNT := 46
const VOID_LIGHT_COUNT := 10
const FOG_BAND_COUNT := 10
const TOTAL_LEVELS := 24

var _player: CharacterBody3D
var _status_label: Label
var _debug_label: Label
var _mechanic_hud: Control
var _debug_visible := true
var _has_won := false
var _platform_materials: Array[StandardMaterial3D] = []
var _bridge_points: Array[Vector3] = []
var _fog_bands: Array[Node3D] = []
var _void_lights: Array[Dictionary] = []
var _fireflies: Array[Dictionary] = []
var _world_root: Node3D
var _level_seed := 0
var _level_index := 1
var _run_complete := false
var _level_tuning := {}
var _max_step_distance := 0.0
var _max_step_height := 0.0
var _min_step_drop := 0.0


func _ready() -> void:
	_build_materials()
	_build_world()
	_spawn_player()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed("regenerate_level"):
		_regenerate_level()
	elif event.is_action_pressed("advance_phase"):
		_debug_advance_phase()
	elif event.is_action_pressed("toggle_debug"):
		_toggle_debug()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if _player != null and _player.global_position.y < FALL_LIMIT and not _has_won and not _run_complete:
		_player.respawn()


func _process(delta: float) -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0

	for index in _fog_bands.size():
		var band := _fog_bands[index]
		band.rotate_y(delta * (0.025 + float(index % 4) * 0.007))
		band.position.z = sin(elapsed * 0.12 + float(index)) * 2.2

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

	_update_debug_label()


func _build_materials() -> void:
	_platform_materials = [
		_make_material(Color("#caa15a")),
		_make_material(Color("#d6b463")),
		_make_material(Color("#9fbf78")),
	]


func _build_world() -> void:
	_world_root = Node3D.new()
	_world_root.name = "GeneratedWorld"
	add_child(_world_root)

	_add_environment()
	_regenerate_level()


func _regenerate_level() -> void:
	if _world_root == null:
		return

	_run_complete = false
	_build_level(randi())


func _build_level(seed: int) -> void:
	if _world_root == null:
		return

	for child in _world_root.get_children():
		child.queue_free()

	_fog_bands.clear()
	_void_lights.clear()
	_fireflies.clear()
	_has_won = false
	if _status_label != null:
		_update_status_label()

	_level_seed = seed
	_level_tuning = _get_level_tuning()
	_bridge_points = _generate_bridge_points(_level_seed)
	_add_end_walls()
	_add_start_pad()
	_add_hex_path()
	_add_path_debug_markers()
	_add_goal()
	_add_void_fog()
	_add_void_lights()
	_add_fireflies()

	if _player != null:
		if _player.has_method("set_mechanics"):
			_player.set_mechanics(_level_tuning.get("mechanics", {}))
		_player.position = START_POINT + Vector3(-3.2, 2.2, 0.0)
		_player.respawn()


func _advance_level() -> void:
	if _level_index >= TOTAL_LEVELS:
		_run_complete = true
		_has_won = true
		if _status_label != null:
			_status_label.text = "Run complete. R restarts from level 1."
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	_level_index += 1
	_build_level(randi())


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


func _add_end_walls() -> void:
	_add_end_wall(START_POINT.x - 15.0, Color("#171b22"), -1.0)
	_add_end_wall(GOAL_POINT.x + 15.0, Color("#1b1720"), 1.0)


func _add_end_wall(x: float, color: Color, facing: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _level_seed + int(absf(x) * 1000.0)

	for index in 9:
		var z := lerpf(-22.0, 22.0, float(index) / 8.0)
		var height := rng.randf_range(22.0, 34.0)
		var width := rng.randf_range(3.6, 7.5)
		var depth := rng.randf_range(5.0, 9.0)
		var y := -11.0 + height * 0.5 + rng.randf_range(-1.5, 1.8)
		var block := _add_box(
			Vector3(x + rng.randf_range(-1.1, 1.1), y, z),
			Vector3(width, height, depth),
			color.lightened(rng.randf_range(0.0, 0.12))
		)
		block.rotation_degrees.y = rng.randf_range(-4.0, 4.0)

	for index in 5:
		var buttress := _add_box(
			Vector3(x - facing * 3.0, rng.randf_range(2.0, 8.0), lerpf(-17.0, 17.0, float(index) / 4.0)),
			Vector3(rng.randf_range(5.0, 8.0), rng.randf_range(18.0, 28.0), rng.randf_range(2.8, 4.6)),
			color.lightened(0.08)
		)
		buttress.rotation_degrees.z = facing * rng.randf_range(1.0, 4.0)


func _add_hex_path() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _level_seed + 41017

	for index in _bridge_points.size():
		var point := _bridge_points[index]
		var height_ratio := inverse_lerp(HEIGHT_MIN, HEIGHT_MAX, point.y)
		var color := _platform_materials[index % _platform_materials.size()].albedo_color.lerp(Color("#e3dba4"), height_ratio * 0.35)
		var exploding := _is_exploding_hex(index, rng)
		if exploding:
			color = Color("#c65c4d")
		_add_hex_platform(point, HEX_RADIUS, color, exploding)

		if index > 3 and index < _bridge_points.size() - 4 and rng.randf() < float(_level_tuning["branch_chance"]):
			var offset_direction := -1.0 if rng.randf() < 0.5 else 1.0
			var side_step := Vector3(0.0, rng.randf_range(-0.35, 0.35), offset_direction * rng.randf_range(3.1, 3.8))
			_add_hex_platform(point + side_step, HEX_RADIUS * 0.86, Color("#829b67"), false)


func _is_exploding_hex(index: int, rng: RandomNumberGenerator) -> bool:
	if not bool(_level_tuning.get("exploding_hexes", false)):
		return false
	if index < 4 or index > _bridge_points.size() - 5:
		return false

	return rng.randf() < float(_level_tuning.get("exploding_chance", 0.0))


func _add_path_debug_markers() -> void:
	for index in range(1, _bridge_points.size()):
		var previous := _bridge_points[index - 1]
		var current := _bridge_points[index]
		var horizontal_distance := Vector2(current.x - previous.x, current.z - previous.z).length()
		var vertical_delta := current.y - previous.y
		var stress := maxf(horizontal_distance / MAX_HORIZONTAL_STEP, absf(vertical_delta) / maxf(MAX_VERTICAL_STEP, absf(MIN_VERTICAL_STEP)))
		var color := Color("#4dff8f").lerp(Color("#ffcc4d"), clampf(stress, 0.0, 1.0))
		if stress > 0.92:
			color = Color("#ff5a4d")

		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var midpoint := (previous + current) * 0.5 + Vector3(0.0, 0.18, 0.0)
		var segment := current - previous
		mesh.size = Vector3(0.08, 0.08, maxf(segment.length(), 0.1))
		marker.mesh = mesh
		marker.position = midpoint
		marker.material_override = _make_glow_material(color)
		marker.visible = _debug_visible
		marker.add_to_group("debug_markers")
		_world_root.add_child(marker)
		marker.look_at(current + Vector3(0.0, 0.18, 0.0), Vector3.UP)


func _add_goal() -> void:
	var goal_point := _bridge_points[_bridge_points.size() - 1]
	_add_hex_platform(goal_point + Vector3(3.2, 0.0, 0.0), HEX_RADIUS * 1.35, Color("#3f8f67"))

	var goal := Area3D.new()
	goal.name = "Goal"
	goal.position = goal_point + Vector3(3.2, 1.4, 0.0)
	goal.body_entered.connect(_on_goal_body_entered)
	_world_root.add_child(goal)

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


func _add_hex_platform(center: Vector3, radius: float, color: Color, exploding := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	_world_root.add_child(body)

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

	if exploding:
		body.set_meta("armed", true)
		var trigger := Area3D.new()
		trigger.body_entered.connect(_on_exploding_hex_entered.bind(body))
		body.add_child(trigger)

		var trigger_shape := CollisionShape3D.new()
		var trigger_cylinder := CylinderShape3D.new()
		trigger_cylinder.radius = radius
		trigger_cylinder.height = HEX_HEIGHT + 0.9
		trigger_shape.position.y = 0.25
		trigger_shape.shape = trigger_cylinder
		trigger.add_child(trigger_shape)

	return body


func _add_void_fog() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for index in FOG_BAND_COUNT:
		var fog := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(rng.randf_range(22.0, 38.0), rng.randf_range(8.0, 15.0))
		fog.mesh = mesh
		var depth := -11.0 - float(index) * 0.9
		fog.position = Vector3(
			lerpf(START_POINT.x - 6.0, GOAL_POINT.x + 8.0, float(index) / float(FOG_BAND_COUNT - 1)),
			depth,
			rng.randf_range(-7.0, 7.0)
		)
		fog.rotation_degrees = Vector3(0.0, rng.randf_range(-8.0, 8.0), 0.0)
		fog.material_override = _make_transparent_material(
			Color(0.34, 0.45, 0.58, rng.randf_range(0.07, 0.13)),
			-index
		)
		_world_root.add_child(fog)
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
		_world_root.add_child(light)

		var glow := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.44
		glow.mesh = mesh
		glow.position = origin
		glow.material_override = _make_glow_material(Color("#86d7ff"))
		_world_root.add_child(glow)

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
		_world_root.add_child(node)

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
	if _player.has_method("set_mechanics"):
		_player.set_mechanics(_level_tuning.get("mechanics", {}))


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_status_label = Label.new()
	_status_label.position = Vector2(24.0, 20.0)
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(_status_label)
	_update_status_label()

	_debug_label = Label.new()
	_debug_label.position = Vector2(24.0, 54.0)
	_debug_label.add_theme_font_size_override("font_size", 16)
	_debug_label.visible = _debug_visible
	canvas.add_child(_debug_label)

	_mechanic_hud = Control.new()
	_mechanic_hud.set_script(MechanicHudScript)
	_mechanic_hud.set_anchors_preset(Control.PRESET_CENTER)
	_mechanic_hud.position = Vector2(-42.0, -42.0)
	canvas.add_child(_mechanic_hud)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	return material


func _make_transparent_material(color: Color, render_priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = VoidFogShader
	material.set_shader_parameter("fog_color", color)
	material.set_shader_parameter("drift_speed", 0.035 + float(abs(render_priority)) * 0.006)
	material.set_shader_parameter("swirl_scale", 3.7 + float(abs(render_priority) % 4) * 0.55)
	material.render_priority = render_priority
	return material


func _make_glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	return material


func _generate_bridge_points(seed: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var points: Array[Vector3] = []
	var heights := _generate_vertical_profile(rng)
	var lane := 0
	var lane_limit := int(_level_tuning["lane_limit"])

	for index in PATH_POINTS:
		if index == 0:
			points.append(START_POINT)
			continue

		if index < PATH_POINTS - 3 and rng.randf() < float(_level_tuning["turn_chance"]):
			lane = clampi(lane + rng.randi_range(-1, 1), -lane_limit, lane_limit)

		var point := _axial_to_world(index, lane)
		point.y = heights[index]
		points.append(point)

	points[0] = START_POINT
	points[points.size() - 1] = _axial_to_world(PATH_STEPS, 0)
	points[points.size() - 1].y = heights[heights.size() - 1]
	_update_path_stats(points)
	return points


func _generate_vertical_profile(rng: RandomNumberGenerator) -> Array[float]:
	var heights: Array[float] = [0.0]
	var height := 0.0
	var trend := 1.0
	var trend_left := 0
	var climb_min := float(_level_tuning["climb_min"])
	var climb_max := float(_level_tuning["climb_max"])
	var drop_min := float(_level_tuning["drop_min"])
	var drop_max := float(_level_tuning["drop_max"])
	var height_min := float(_level_tuning["height_min"])
	var height_max := float(_level_tuning["height_max"])
	var reversal_chance := float(_level_tuning["reversal_chance"])

	for index in range(1, PATH_POINTS):
		if index <= 2:
			height += rng.randf_range(0.25, 0.75)
		else:
			if trend_left <= 0:
				trend = -1.0 if rng.randf() < 0.5 else 1.0
				trend_left = rng.randi_range(int(_level_tuning["trend_min"]), int(_level_tuning["trend_max"]))

			var step := rng.randf_range(climb_min, climb_max) * trend
			if trend < 0.0:
				step = -rng.randf_range(drop_min, drop_max)
			if rng.randf() < reversal_chance:
				step *= -0.65

			height += step
			trend_left -= 1

		if height > height_max:
			height = height_max - rng.randf_range(0.0, 0.7)
			trend = -1.0
			trend_left = rng.randi_range(2, 4)
		elif height < height_min:
			height = height_min + rng.randf_range(0.0, 0.7)
			trend = 1.0
			trend_left = rng.randi_range(2, 4)

		heights.append(height)

	return heights


func _get_level_tuning() -> Dictionary:
	var arc := int((_level_index - 1) / 3)
	var phase := int((_level_index - 1) % 3)
	var mechanic_index := int(arc / 2)
	var is_combo_arc := arc % 2 == 1
	var mechanic_names := ["Double Jump", "Bunny Hop", "Grapple", "Exploding Hexes"]
	var mechanics := _mechanics_for_arc(mechanic_index, is_combo_arc)

	var tuning := {
		"arc_name": mechanic_names[mechanic_index],
		"phase_name": ["new", "practice", "master"][phase],
		"combo": is_combo_arc,
		"mechanics": mechanics,
		"lane_limit": [1, 2, 2][phase],
		"turn_chance": [0.24, 0.38, 0.52][phase],
		"branch_chance": [0.14, 0.26, 0.36][phase],
		"trend_min": [3, 2, 2][phase],
		"trend_max": [5, 5, 4][phase],
		"reversal_chance": [0.1, 0.18, 0.24][phase],
		"height_min": HEIGHT_MIN,
		"height_max": HEIGHT_MAX,
		"climb_min": 0.45,
		"climb_max": 1.0,
		"drop_min": 0.55,
		"drop_max": 1.05,
		"exploding_hexes": bool(mechanics.get("exploding_hexes", false)),
		"exploding_chance": [0.12, 0.22, 0.34][phase],
	}

	match mechanic_index:
		0:
			tuning["height_min"] = -2.5
			tuning["height_max"] = 7.8 + float(phase) * 0.5
			tuning["climb_min"] = 0.75 + float(phase) * 0.08
			tuning["climb_max"] = 1.2 + float(phase) * 0.1
			tuning["drop_min"] = 0.55
			tuning["drop_max"] = 1.15 + float(phase) * 0.12
		1:
			tuning["height_min"] = -3.2
			tuning["height_max"] = 7.2
			tuning["lane_limit"] = [2, 3, 3][phase]
			tuning["turn_chance"] = [0.42, 0.56, 0.7][phase]
			tuning["branch_chance"] = [0.22, 0.34, 0.48][phase]
			tuning["climb_min"] = 0.45
			tuning["climb_max"] = 0.95
			tuning["drop_min"] = 0.6
			tuning["drop_max"] = 1.2
		2:
			tuning["height_min"] = -5.5 - float(phase) * 0.4
			tuning["height_max"] = 9.5
			tuning["lane_limit"] = [1, 2, 2][phase]
			tuning["turn_chance"] = [0.24, 0.36, 0.5][phase]
			tuning["drop_min"] = 0.9
			tuning["drop_max"] = 1.35 + float(phase) * 0.08
			tuning["climb_min"] = 0.75
			tuning["climb_max"] = 1.35
			tuning["reversal_chance"] = [0.14, 0.2, 0.28][phase]
		3:
			tuning["height_min"] = -6.0
			tuning["height_max"] = 9.0
			tuning["lane_limit"] = [2, 3, 3][phase]
			tuning["turn_chance"] = [0.5, 0.64, 0.76][phase]
			tuning["branch_chance"] = [0.18, 0.3, 0.42][phase]
			tuning["climb_min"] = 0.7
			tuning["climb_max"] = 1.25 + float(phase) * 0.05
			tuning["drop_min"] = 0.9
			tuning["drop_max"] = 1.45 + float(phase) * 0.08
			tuning["reversal_chance"] = [0.2, 0.28, 0.34][phase]

	if is_combo_arc:
		tuning["lane_limit"] = mini(int(tuning["lane_limit"]) + 1, 3)
		tuning["turn_chance"] = minf(float(tuning["turn_chance"]) + 0.12, 0.82)
		tuning["branch_chance"] = minf(float(tuning["branch_chance"]) + 0.12, 0.58)
		tuning["height_min"] = float(tuning["height_min"]) - 0.8
		tuning["height_max"] = float(tuning["height_max"]) + 0.7

	return tuning


func _mechanics_for_arc(mechanic_index: int, combo: bool) -> Dictionary:
	var mechanics := {
		"double_jump": false,
		"bunny_hop": false,
		"grapple": false,
		"exploding_hexes": false,
	}

	if combo:
		for index in range(mechanic_index + 1):
			_enable_mechanic(mechanics, index)
	else:
		_enable_mechanic(mechanics, mechanic_index)

	return mechanics


func _enable_mechanic(mechanics: Dictionary, index: int) -> void:
	match index:
		0:
			mechanics["double_jump"] = true
		1:
			mechanics["bunny_hop"] = true
		2:
			mechanics["grapple"] = true
		3:
			mechanics["exploding_hexes"] = true


func _axial_to_world(q: int, r: int) -> Vector3:
	return Vector3(
		START_POINT.x + float(q) * HEX_GRID_SPACING,
		0.0,
		float(r) * HEX_GRID_SPACING * 0.82
	)


func _add_box(center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	_world_root.add_child(body)

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


func _update_path_stats(points: Array[Vector3]) -> void:
	_max_step_distance = 0.0
	_max_step_height = 0.0
	_min_step_drop = 0.0

	for index in range(1, points.size()):
		var previous := points[index - 1]
		var current := points[index]
		var horizontal_distance := Vector2(current.x - previous.x, current.z - previous.z).length()
		var vertical_delta := current.y - previous.y
		var vertical_distance := absf(vertical_delta)
		_max_step_distance = maxf(_max_step_distance, horizontal_distance)
		_max_step_height = maxf(_max_step_height, vertical_distance)
		_min_step_drop = minf(_min_step_drop, vertical_delta)


func _update_debug_label() -> void:
	if _debug_label == null or not _debug_visible:
		return

	var player_position := Vector3.ZERO
	var player_velocity := Vector3.ZERO
	var is_grounded := false
	var player_state := {}
	if _player != null:
		player_position = _player.global_position
		player_velocity = _player.velocity
		is_grounded = _player.is_on_floor()
		if _player.has_method("get_debug_state"):
			player_state = _player.get_debug_state()
	if _mechanic_hud != null:
		_mechanic_hud.set_state(player_state)

	_debug_label.text = (
		"F3/Tab debug  G regenerate  N advance\n"
		+ "level: %d/%d %s/%s  %s  seed: %d  hexes: %d  fps: %d\n"
		+ "max step: %.2fm  max climb/drop: %.2f/%.2fm\n"
		+ "player: %.1f, %.1f, %.1f  vel: %.1f  grounded: %s\n"
		+ "double: %s  bunny: x%.2f  grapple: %s"
	) % [
		_level_index,
		TOTAL_LEVELS,
		str(_level_tuning.get("arc_name", "")),
		str(_level_tuning.get("phase_name", "")),
		_active_mechanics_text(),
		_level_seed,
		_bridge_points.size(),
		Engine.get_frames_per_second(),
		_max_step_distance,
		_max_step_height,
		_min_step_drop,
		player_position.x,
		player_position.y,
		player_position.z,
		player_velocity.length(),
		str(is_grounded),
		_double_debug_text(player_state),
		float(player_state.get("bunny_multiplier", 1.0)),
		_grapple_debug_text(player_state),
	]


func _double_debug_text(player_state: Dictionary) -> String:
	if not bool(player_state.get("double_enabled", false)):
		return "off"
	return "ready" if bool(player_state.get("double_ready", false)) else "spent"


func _grapple_debug_text(player_state: Dictionary) -> String:
	if not bool(player_state.get("grapple_enabled", false)):
		return "off"
	if bool(player_state.get("grapple_active", false)):
		return "pulling"
	if bool(player_state.get("grapple_has_target", false)):
		return "target"
	return "no target"


func _toggle_debug() -> void:
	_debug_visible = not _debug_visible
	if _debug_label != null:
		_debug_label.visible = _debug_visible

	for marker in get_tree().get_nodes_in_group("debug_markers"):
		if marker is Node3D:
			marker.visible = _debug_visible


func _debug_advance_phase() -> void:
	if _run_complete:
		_level_index = 1
		_run_complete = false
	elif _level_index < TOTAL_LEVELS:
		_level_index += 1
	else:
		_run_complete = true
		if _status_label != null:
			_status_label.text = "Run complete. R restarts from level 1."
		return

	_build_level(randi())


func _update_status_label() -> void:
	if _status_label == null:
		return

	_status_label.text = "Level %d/%d: %s %s. %s N skips." % [
		_level_index,
		TOTAL_LEVELS,
		str(_level_tuning.get("arc_name", "")),
		str(_level_tuning.get("phase_name", "")),
		_controls_hint(),
	]


func _active_mechanics_text() -> String:
	var mechanics: Dictionary = _level_tuning.get("mechanics", {})
	var active: Array[String] = []
	if bool(mechanics.get("double_jump", false)):
		active.append("double")
	if bool(mechanics.get("bunny_hop", false)):
		active.append("bunny")
	if bool(mechanics.get("grapple", false)):
		active.append("grapple")
	if bool(mechanics.get("exploding_hexes", false)):
		active.append("boom")

	return ",".join(active) if not active.is_empty() else "basic"


func _controls_hint() -> String:
	var mechanics: Dictionary = _level_tuning.get("mechanics", {})
	var hint := "WASD, Space"
	if bool(mechanics.get("double_jump", false)):
		hint += ", Space again"
	if bool(mechanics.get("bunny_hop", false)):
		hint += ", chain jumps"
	if bool(mechanics.get("grapple", false)):
		hint += ", RMB/E grapple"
	if bool(mechanics.get("exploding_hexes", false)):
		hint += ", red hexes break"
	return hint + "."


func _on_goal_body_entered(body: Node3D) -> void:
	if body == _player and not _has_won:
		_has_won = true
		_status_label.text = "Level %d clear." % _level_index
		call_deferred("_advance_level")


func _on_exploding_hex_entered(body: Node3D, platform: StaticBody3D) -> void:
	if body != _player or not bool(platform.get_meta("armed", false)):
		return

	platform.set_meta("armed", false)
	var visual := platform.get_child(1) as MeshInstance3D
	if visual != null:
		visual.material_override = _make_glow_material(Color("#ff6b4a"))
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(platform):
		platform.queue_free()
