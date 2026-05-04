extends Node3D

signal goal_reached

const VoidFogShader := preload("res://shaders/void_fog.gdshader")
const CliffRippleShader := preload("res://shaders/cliff_ripple.gdshader")
const MantaFlockEvent := preload("res://scripts/background_events/manta_flock.gd")
const ChainLightningEvent := preload("res://scripts/background_events/chain_lightning.gd")
const ChainCreatureEvent := preload("res://scripts/background_events/chain_creature.gd")
const TentacleBundleEvent := preload("res://scripts/background_events/tentacle_bundle.gd")

const HEX_RADIUS := 1.55
const HEX_HEIGHT := 0.55
const START_POINT := Vector3(-7.0, 0.0, 0.0)
const GOAL_POINT := Vector3(84.0, 0.0, 0.0)
const MAX_HORIZONTAL_STEP := 4.4
const MAX_VERTICAL_STEP := 1.35
const MIN_VERTICAL_STEP := -1.65
const HEIGHT_MIN := -4.5
const HEIGHT_MAX := 8.5
const FIREFLY_COUNT := 46
const VOID_LIGHT_COUNT := 10
const FOG_BAND_COUNT := 10
const GRAPPLE_ROCK_STEP := 4
const HEX_ROCK_ATLAS_PATH := "res://assets/textures/hex_rock_atlas_512.png"
const CLIFF_BASE_TEXTURE_PATH := "res://assets/textures/cliff_base.png"
const HEX_ATLAS_COLUMNS := 4
const HEX_ATLAS_ROWS := 4
const COMPANIONS_ENABLED := false

var player: CharacterBody3D
var debug_visible := false
var bridge_points: Array[Vector3] = []
var level_tuning := {}
var level_seed := 0

var _platform_colors: Array[Color] = []
var _hex_material_cache: Dictionary = {}
var _hex_rock_atlas: Texture2D
var _cliff_base_texture: Texture2D
var _fog_bands: Array[Node3D] = []
var _void_lights: Array[Dictionary] = []
var _fireflies: Array[Dictionary] = []
var _goal_sprays: Array[Node3D] = []
var _grapple_rocks: Array[Dictionary] = []
var _background_event: Node3D
var _companion_glowbugs: Array[Dictionary] = []
var _world_root: Node3D


func setup_environment() -> void:
	_build_materials()

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#000000")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#030508")
	environment.ambient_light_energy = 0.03
	environment.fog_enabled = true
	environment.fog_light_color = Color("#182030")
	environment.fog_density = 0.028
	environment.fog_sky_affect = 0.82
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.045
	environment.volumetric_fog_albedo = Color("#111827")
	environment.volumetric_fog_emission = Color("#03060a")
	environment.volumetric_fog_length = 96.0
	world.environment = environment
	add_child(world)

	var hex_rim_light := DirectionalLight3D.new()
	hex_rim_light.rotation_degrees = Vector3(-36.0, -72.0, 0.0)
	hex_rim_light.light_color = Color("#9fb8d7")
	hex_rim_light.light_energy = 0.18
	hex_rim_light.shadow_enabled = false
	add_child(hex_rim_light)

	_world_root = Node3D.new()
	_world_root.name = "GeneratedWorld"
	add_child(_world_root)


func set_player(new_player: CharacterBody3D) -> void:
	player = new_player
	if not COMPANIONS_ENABLED:
		return
	if player != null and not player.is_connected("landed", Callable(self, "_on_player_landed")):
		player.connect("landed", Callable(self, "_on_player_landed"))
	_add_companion_glowbugs()


func build_level(level_data: Dictionary, show_debug: bool) -> void:
	if _world_root == null:
		return

	debug_visible = show_debug
	level_seed = int(level_data["seed"])
	level_tuning = level_data["tuning"]
	bridge_points = level_data["bridge_points"]

	for child in _world_root.get_children():
		child.queue_free()

	_fog_bands.clear()
	_void_lights.clear()
	_fireflies.clear()
	_goal_sprays.clear()
	_grapple_rocks.clear()
	_background_event = null

	_add_end_walls()
	_add_start_pad()
	_add_hex_path()
	_add_grapple_rocks()
	_add_path_debug_markers()
	_add_goal()
	_add_void_fog()
	_add_void_lights()
	_add_fireflies()
	_add_background_effect()


func process_effects(delta: float, elapsed: float) -> void:
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

	for index in _goal_sprays.size():
		_goal_sprays[index].rotate_y(delta * (0.45 + float(index % 3) * 0.08))

	for entry in _grapple_rocks:
		var rock := entry["node"] as Node3D
		var phase: float = elapsed * float(entry["speed"]) + float(entry["phase"])
		var origin := entry["origin"] as Vector3
		rock.position = origin + Vector3(
			sin(phase * 0.73) * float(entry["drift"]),
			sin(phase) * float(entry["bob"]),
			cos(phase * 0.61) * float(entry["drift"])
		)
		rock.rotation_degrees += Vector3(
			delta * float(entry["pitch_speed"]),
			delta * float(entry["yaw_speed"]),
			delta * float(entry["roll_speed"])
		)

	_process_background_effects(delta, elapsed)
	if COMPANIONS_ENABLED:
		_update_companion_glowbugs(delta, elapsed)


func set_debug_visible(value: bool) -> void:
	debug_visible = value
	for marker in get_tree().get_nodes_in_group("debug_markers"):
		if marker is Node3D:
			marker.visible = debug_visible


func get_background_debug_text() -> String:
	if _background_event == null or not _background_event.has_method("get_debug_name"):
		return "none"
	return _background_event.get_debug_name()


func _build_materials() -> void:
	_platform_colors = [
		Color("#caa15a"),
		Color("#d6b463"),
		Color("#9fbf78"),
	]
	_hex_material_cache.clear()
	_load_hex_rock_atlas()
	_load_cliff_base_texture()


func _add_start_pad() -> void:
	_add_hex_platform(START_POINT, HEX_RADIUS * 1.35, Color("#3f8f67"))


func _add_end_walls() -> void:
	_add_end_wall(START_POINT.x - 28.0, Color("#ff3030"), -1.0)
	_add_end_wall(GOAL_POINT.x + 32.0, Color("#2f7bff"), 1.0)


func _add_end_wall(x: float, ripple_color: Color, facing: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed + int(absf(x) * 1000.0)
	var cliff_material := _make_cliff_material(ripple_color)

	for index in 17:
		var z := lerpf(-82.0, 82.0, float(index) / 16.0)
		var height := rng.randf_range(220.0, 340.0)
		var width := rng.randf_range(8.0, 16.0)
		var depth := rng.randf_range(11.0, 22.0)
		var y := -110.0 + height * 0.5 + rng.randf_range(-8.0, 8.0)
		var block := _add_box(
			Vector3(x + rng.randf_range(-2.0, 2.0), y, z),
			Vector3(width, height, depth),
			Color.BLACK,
			cliff_material
		)
		block.rotation_degrees.y = rng.randf_range(-4.0, 4.0)

	for index in 9:
		var buttress := _add_box(
			Vector3(x - facing * 8.0, rng.randf_range(28.0, 72.0), lerpf(-72.0, 72.0, float(index) / 8.0)),
			Vector3(rng.randf_range(9.0, 18.0), rng.randf_range(160.0, 260.0), rng.randf_range(7.0, 14.0)),
			Color.BLACK,
			cliff_material
		)
		buttress.rotation_degrees.z = facing * rng.randf_range(1.0, 4.0)


func _add_hex_path() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed + 41017

	for index in bridge_points.size():
		if index == 0:
			continue

		var point := bridge_points[index]
		var height_ratio := inverse_lerp(HEIGHT_MIN, HEIGHT_MAX, point.y)
		var color := _platform_colors[index % _platform_colors.size()].lerp(Color("#e3dba4"), height_ratio * 0.35)
		var exploding := _is_exploding_hex(index, rng)
		if exploding:
			color = Color("#c65c4d")
		_add_hex_platform(point, HEX_RADIUS, color, exploding)

		if index > 3 and index < bridge_points.size() - 4 and rng.randf() < float(level_tuning["branch_chance"]):
			var offset_direction := -1.0 if rng.randf() < 0.5 else 1.0
			var side_step := Vector3(0.0, rng.randf_range(-0.35, 0.35), offset_direction * rng.randf_range(3.1, 3.8))
			_add_hex_platform(point + side_step, HEX_RADIUS * 0.86, Color("#829b67"), false)


func _is_exploding_hex(index: int, rng: RandomNumberGenerator) -> bool:
	if not bool(level_tuning.get("exploding_hexes", false)):
		return false

	var exploding_indices: Array = level_tuning.get("exploding_indices", [])
	if not exploding_indices.is_empty():
		return exploding_indices.has(index)

	if index < 4 or index > bridge_points.size() - 5:
		return false

	return rng.randf() < float(level_tuning.get("exploding_chance", 0.0))


func _add_grapple_rocks() -> void:
	var mechanics: Dictionary = level_tuning.get("mechanics", {})
	if not bool(mechanics.get("grapple", false)):
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed + 90533
	var rock_material := _make_rock_material()
	var anchor_gaps: Array = level_tuning.get("grapple_anchor_gaps", [])

	for gap_index in anchor_gaps:
		var index := int(gap_index)
		if index <= 0 or index >= bridge_points.size():
			continue
		var previous := bridge_points[index - 1]
		var current := bridge_points[index]
		var midpoint := previous.lerp(current, 0.5)
		_add_grapple_rock(
			midpoint + Vector3(0.0, rng.randf_range(5.4, 7.1), rng.randf_range(-0.35, 0.35)),
			rng,
			rock_material,
			rng.randf_range(0.95, 1.25)
		)

	for index in range(4, bridge_points.size() - 4, GRAPPLE_ROCK_STEP):
		var point := bridge_points[index]
		var origin := point + Vector3(
			rng.randf_range(-0.8, 0.8),
			rng.randf_range(4.2, 7.2),
			rng.randf_range(-2.6, 2.6)
		)
		_add_grapple_rock(origin, rng, rock_material, rng.randf_range(0.55, 0.95))


func _add_grapple_rock(origin: Vector3, rng: RandomNumberGenerator, rock_material: StandardMaterial3D, radius: float) -> void:
	var rock := StaticBody3D.new()
	rock.position = origin
	rock.rotation_degrees = Vector3(
		rng.randf_range(-18.0, 18.0),
		rng.randf_range(0.0, 360.0),
		rng.randf_range(-18.0, 18.0)
	)
	_world_root.add_child(rock)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius * 0.95
	shape.shape = sphere
	rock.add_child(shape)

	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * rng.randf_range(1.35, 1.9)
	visual.mesh = mesh
	visual.scale = Vector3(
		rng.randf_range(0.8, 1.25),
		rng.randf_range(0.55, 0.9),
		rng.randf_range(0.8, 1.25)
	)
	visual.material_override = rock_material
	rock.add_child(visual)

	var light := OmniLight3D.new()
	light.light_color = Color("#6f89a8")
	light.light_energy = 0.12
	light.omni_range = 2.4
	rock.add_child(light)

	_grapple_rocks.append({
		"node": rock,
		"origin": origin,
		"phase": rng.randf_range(0.0, TAU),
		"speed": rng.randf_range(0.35, 0.75),
		"bob": rng.randf_range(0.18, 0.45),
		"drift": rng.randf_range(0.08, 0.24),
		"pitch_speed": rng.randf_range(-4.0, 4.0),
		"yaw_speed": rng.randf_range(-8.0, 8.0),
		"roll_speed": rng.randf_range(-4.0, 4.0),
	})


func _add_path_debug_markers() -> void:
	for index in range(1, bridge_points.size()):
		var previous := bridge_points[index - 1]
		var current := bridge_points[index]
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
		marker.visible = debug_visible
		marker.add_to_group("debug_markers")
		_world_root.add_child(marker)
		marker.look_at(current + Vector3(0.0, 0.18, 0.0), Vector3.UP)


func _add_goal() -> void:
	var goal_point := bridge_points[bridge_points.size() - 1]
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

	_add_goal_spray(goal)


func _add_goal_spray(goal: Area3D) -> void:
	var spray_root := Node3D.new()
	goal.add_child(spray_root)
	_goal_sprays.append(spray_root)

	var material := _make_glow_material(Color("#69e38f"))
	for index in 72:
		var t := float(index) / 71.0
		var angle := t * TAU * 5.25
		var radius := lerpf(0.22, 2.2, t)
		var height := lerpf(-0.4, 4.2, t)
		var particle := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = lerpf(0.045, 0.13, t)
		mesh.height = mesh.radius * 2.0
		particle.mesh = mesh
		particle.position = Vector3(cos(angle) * radius, height, sin(angle) * radius)
		particle.material_override = material
		spray_root.add_child(particle)

	for index in 3:
		var light := OmniLight3D.new()
		light.light_color = Color("#69e38f")
		light.light_energy = 0.75
		light.omni_range = 5.5 + float(index) * 1.2
		light.position.y = float(index) * 1.35
		spray_root.add_child(light)


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

	var tile_index := _hex_atlas_tile_for(center, color, exploding)
	var visual := MeshInstance3D.new()
	visual.mesh = _make_flat_hex_mesh(radius * 0.86, radius * 0.96, HEX_HEIGHT, tile_index)
	visual.material_override = _make_hex_material(color)
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

	for index in 5:
		var floor_fog := MeshInstance3D.new()
		var floor_mesh := PlaneMesh.new()
		floor_mesh.size = Vector2(135.0 + float(index) * 18.0, 190.0)
		floor_fog.mesh = floor_mesh
		floor_fog.position = Vector3((START_POINT.x + GOAL_POINT.x) * 0.5, -18.0 - float(index) * 15.0, 0.0)
		floor_fog.rotation_degrees = Vector3(0.0, rng.randf_range(-4.0, 4.0), 0.0)
		floor_fog.material_override = _make_transparent_material(Color(0.08, 0.12, 0.18, 0.22 - float(index) * 0.02), -20 - index)
		_world_root.add_child(floor_fog)
		_fog_bands.append(floor_fog)

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
		fog.material_override = _make_transparent_material(Color(0.34, 0.45, 0.58, rng.randf_range(0.07, 0.13)), -index)
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
		var path_index := rng.randi_range(0, bridge_points.size() - 1)
		var point := bridge_points[path_index]
		var node := Node3D.new()
		node.position = point + Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(1.0, 2.6), rng.randf_range(-1.2, 1.2))
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
		light.light_energy = 0.48
		light.omni_range = 2.4
		node.add_child(light)

		_fireflies.append({
			"node": node,
			"origin": node.position,
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(1.2, 2.4),
		})


func _add_background_effect() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed + 77191
	var roll := rng.randf()
	if roll < 0.5:
		return
	elif roll < 0.77:
		_background_event = MantaFlockEvent.new()
	elif roll < 0.92:
		_background_event = ChainLightningEvent.new()
	elif roll < 0.97:
		_background_event = ChainCreatureEvent.new()
	else:
		_background_event = TentacleBundleEvent.new()

	_world_root.add_child(_background_event)
	_background_event.setup(_get_background_event_config(), rng)


func _process_background_effects(delta: float, elapsed: float) -> void:
	if _background_event != null and _background_event.has_method("process_effect"):
		_background_event.process_effect(delta, elapsed, player)


func _get_background_event_config() -> Dictionary:
	return {
		"start_point": START_POINT,
		"goal_point": GOAL_POINT,
		"bridge_points": bridge_points,
	}


func _add_companion_glowbugs() -> void:
	if not _companion_glowbugs.is_empty():
		return

	var colors := [
		Color("#ff6b7a"),
		Color("#62d9ff"),
		Color("#f6d86b"),
		Color("#c084ff"),
	]
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for index in colors.size():
		var root := Node3D.new()
		add_child(root)

		var glow := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.09
		mesh.height = 0.18
		glow.mesh = mesh
		glow.material_override = _make_glow_material(colors[index])
		root.add_child(glow)

		var light := OmniLight3D.new()
		light.light_color = colors[index]
		light.light_energy = 0.42
		light.omni_range = 2.6
		root.add_child(light)

		_companion_glowbugs.append({
			"node": root,
			"axis": Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.35, 1.0), rng.randf_range(-1.0, 1.0)).normalized(),
			"radius": rng.randf_range(1.15, 2.45),
			"height_bias": rng.randf_range(0.6, 1.8),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(1.1, 2.4),
			"wobble": rng.randf_range(0.25, 0.8),
			"dance": 0.0,
		})


func _update_companion_glowbugs(delta: float, elapsed: float) -> void:
	if player == null:
		return

	for entry in _companion_glowbugs:
		var bug := entry["node"] as Node3D
		var dance := maxf(float(entry["dance"]) - delta * 1.6, 0.0)
		entry["dance"] = dance

		var axis := entry["axis"] as Vector3
		var radius := float(entry["radius"])
		var height_bias := float(entry["height_bias"])
		var phase := float(entry["phase"])
		var speed := float(entry["speed"]) * (1.0 + dance * 2.8)
		var wobble := float(entry["wobble"]) + dance * 0.75
		var angle := elapsed * speed + phase
		var basis := Basis(axis, angle)
		var orbit := basis * Vector3(radius, sin(angle * 1.7 + phase) * wobble, 0.0)
		var target := player.global_position + Vector3(0.0, height_bias, 0.0) + orbit
		bug.global_position = bug.global_position.lerp(target, 1.0 - pow(0.018, delta))


func _on_player_landed() -> void:
	for entry in _companion_glowbugs:
		entry["dance"] = 1.0


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	return material


func _make_hex_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if _hex_material_cache.has(key):
		return _hex_material_cache[key]

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	if _hex_rock_atlas != null:
		material.albedo_texture = _hex_rock_atlas
	_hex_material_cache[key] = material
	return material


func _load_hex_rock_atlas() -> void:
	if _hex_rock_atlas != null:
		return
	var image := Image.load_from_file(HEX_ROCK_ATLAS_PATH)
	if image == null or image.is_empty():
		return
	_hex_rock_atlas = ImageTexture.create_from_image(image)


func _load_cliff_base_texture() -> void:
	if _cliff_base_texture != null:
		return
	var image := Image.load_from_file(CLIFF_BASE_TEXTURE_PATH)
	if image == null or image.is_empty():
		return
	_cliff_base_texture = ImageTexture.create_from_image(image)


func _hex_atlas_tile_for(center: Vector3, color: Color, exploding: bool) -> int:
	if exploding:
		return 6
	if color.g > color.r and color.g > color.b:
		return 3

	var candidates := [0, 1, 2, 4, 5, 8, 9, 11, 12, 13, 15]
	var hash_value := int(absf(center.x * 37.0 + center.z * 53.0 + center.y * 29.0 + float(level_seed % 997)))
	return candidates[hash_value % candidates.size()]


func _make_transparent_material(color: Color, render_priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = VoidFogShader
	material.set_shader_parameter("fog_color", color)
	material.set_shader_parameter("drift_speed", 0.035 + float(abs(render_priority)) * 0.006)
	material.set_shader_parameter("swirl_scale", 3.7 + float(abs(render_priority) % 4) * 0.55)
	material.render_priority = render_priority
	return material


func _make_cliff_material(ripple_color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CliffRippleShader
	if _cliff_base_texture != null:
		material.set_shader_parameter("base_texture", _cliff_base_texture)
	material.set_shader_parameter("ripple_color", ripple_color)
	return material


func _make_glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	return material


func _make_rock_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#161a20")
	material.roughness = 0.94
	material.emission_enabled = true
	material.emission = Color("#263140")
	material.emission_energy_multiplier = 0.18
	return material


func _make_flat_hex_mesh(top_radius: float, bottom_radius: float, height: float, atlas_tile_index: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half_height := height * 0.5
	var uv_radius := maxf(top_radius, bottom_radius)

	var top_center := Vector3(0.0, half_height, 0.0)
	var bottom_center := Vector3(0.0, -half_height, 0.0)
	var top_points: Array[Vector3] = []
	var bottom_points: Array[Vector3] = []

	for index in 6:
		var angle := TAU * float(index) / 6.0 + PI / 6.0
		top_points.append(Vector3(cos(angle) * top_radius, half_height, sin(angle) * top_radius))
		bottom_points.append(Vector3(cos(angle) * bottom_radius, -half_height, sin(angle) * bottom_radius))

	for index in 6:
		_add_flat_triangle(vertices, normals, uvs, indices, top_center, top_points[index], top_points[(index + 1) % 6], Vector3.UP, uv_radius, atlas_tile_index)
		_add_flat_triangle(vertices, normals, uvs, indices, bottom_center, bottom_points[(index + 1) % 6], bottom_points[index], Vector3.DOWN, uv_radius, atlas_tile_index)

	for index in 6:
		var next := (index + 1) % 6
		var a := bottom_points[index]
		var b := bottom_points[next]
		var c := top_points[next]
		var d := top_points[index]
		var normal := (b - a).cross(d - a).normalized()
		_add_flat_triangle(vertices, normals, uvs, indices, a, b, c, normal, uv_radius, atlas_tile_index)
		_add_flat_triangle(vertices, normals, uvs, indices, a, c, d, normal, uv_radius, atlas_tile_index)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_flat_triangle(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	uv_radius: float,
	atlas_tile_index: int
) -> void:
	var start := vertices.size()
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	uvs.append(_hex_uv(a, uv_radius, atlas_tile_index))
	uvs.append(_hex_uv(b, uv_radius, atlas_tile_index))
	uvs.append(_hex_uv(c, uv_radius, atlas_tile_index))
	indices.append(start)
	indices.append(start + 1)
	indices.append(start + 2)


func _hex_uv(point: Vector3, radius: float, atlas_tile_index: int) -> Vector2:
	var diameter := maxf(radius * 2.0, 0.001)
	var base_uv := Vector2(point.x / diameter + 0.5, point.z / diameter + 0.5)
	var cell_size := Vector2(1.0 / float(HEX_ATLAS_COLUMNS), 1.0 / float(HEX_ATLAS_ROWS))
	var tile := Vector2(
		float(atlas_tile_index % HEX_ATLAS_COLUMNS),
		float(floori(float(atlas_tile_index) / float(HEX_ATLAS_COLUMNS)))
	)
	return base_uv * cell_size + tile * cell_size


func _add_box(center: Vector3, size: Vector3, color: Color, material_override: Material = null) -> StaticBody3D:
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
	visual.material_override = material_override if material_override != null else _make_material(color)
	body.add_child(visual)

	return body


func _on_goal_body_entered(body: Node3D) -> void:
	if body == player:
		goal_reached.emit()


func _on_exploding_hex_entered(body: Node3D, platform: StaticBody3D) -> void:
	if body != player or not bool(platform.get_meta("armed", false)):
		return

	platform.set_meta("armed", false)
	var visual := platform.get_child(1) as MeshInstance3D
	if visual != null:
		visual.material_override = _make_glow_material(Color("#ff6b4a"))
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(platform):
		platform.queue_free()
