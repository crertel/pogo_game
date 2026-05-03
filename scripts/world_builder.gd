extends Node3D

signal goal_reached

const VoidFogShader := preload("res://shaders/void_fog.gdshader")
const CliffRippleShader := preload("res://shaders/cliff_ripple.gdshader")
const TentacleNoiseShader := preload("res://shaders/tentacle_noise.gdshader")

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
const BACKGROUND_NONE := 0
const BACKGROUND_FLOCK := 1
const BACKGROUND_LIGHTNING := 2
const BACKGROUND_CHAIN_CREATURE := 3
const BACKGROUND_TENTACLE_BUNDLE := 4
const FLOCK_BOID_COUNT := 72
const FLOCK_MAX_SPEED := 12.5
const FLOCK_MAX_FORCE := 10.0
const FLOCK_NEIGHBOR_RADIUS := 42.0
const FLOCK_SEPARATION_RADIUS := 15.0
const FLOCK_PLAYER_INTEREST_RADIUS := 62.0
const FLOCK_PLAYER_AVOID_RADIUS := 12.0
const FLOCK_SIDE_SPREAD := 90.0
const FLOCK_DEPTH_MIN := 118.0
const FLOCK_DEPTH_MAX := 168.0
const FLOCK_TARGET_LIMIT := 260.0
const FLOCK_WALL_LIMIT := 74.0
const FLOCK_WALL_REPEL_RADIUS := 24.0
const FLOCK_HEX_REPEL_RADIUS := 28.0
const FLOCK_REPULSION_BANK := 0.72
const TENTACLE_TARGET_MAX_SPEED := 13.0
const TENTACLE_JOINT_MAX_ROTATION := 1.8
const TENTACLE_JOINT_MAX_BEND := deg_to_rad(42.0)
const COMPANIONS_ENABLED := false

var player: CharacterBody3D
var debug_visible := false
var bridge_points: Array[Vector3] = []
var level_tuning := {}
var level_seed := 0

var _platform_materials: Array[StandardMaterial3D] = []
var _fog_bands: Array[Node3D] = []
var _void_lights: Array[Dictionary] = []
var _fireflies: Array[Dictionary] = []
var _goal_sprays: Array[Node3D] = []
var _grapple_rocks: Array[Dictionary] = []
var _background_effect := BACKGROUND_NONE
var _flock_boids: Array[Dictionary] = []
var _flock_target := Vector3.ZERO
var _flock_direction := 1.0
var _flock_speed := 12.0
var _lightning_bolts: Array[Dictionary] = []
var _chain_creature: Dictionary = {}
var _tentacle_bundle: Dictionary = {}
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
	_flock_boids.clear()
	_flock_target = Vector3.ZERO
	_lightning_bolts.clear()
	_chain_creature.clear()
	_tentacle_bundle.clear()

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
	match _background_effect:
		BACKGROUND_FLOCK:
			return "manta flock"
		BACKGROUND_LIGHTNING:
			return "chain lightning"
		BACKGROUND_CHAIN_CREATURE:
			return "chain creature"
		BACKGROUND_TENTACLE_BUNDLE:
			return "tentacle bundle"
		_:
			return "none"


func _build_materials() -> void:
	_platform_materials = [
		_make_material(Color("#caa15a")),
		_make_material(Color("#d6b463")),
		_make_material(Color("#9fbf78")),
	]


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
		var color := _platform_materials[index % _platform_materials.size()].albedo_color.lerp(Color("#e3dba4"), height_ratio * 0.35)
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

	for index in range(4, bridge_points.size() - 4, GRAPPLE_ROCK_STEP):
		var point := bridge_points[index]
		var origin := point + Vector3(
			rng.randf_range(-0.8, 0.8),
			rng.randf_range(4.2, 7.2),
			rng.randf_range(-2.6, 2.6)
		)
		var radius := rng.randf_range(0.55, 0.95)
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

	var visual := MeshInstance3D.new()
	visual.mesh = _make_flat_hex_mesh(radius * 0.86, radius * 0.96, HEX_HEIGHT)
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
		_background_effect = BACKGROUND_NONE
	elif roll < 0.77:
		_background_effect = BACKGROUND_FLOCK
		_add_flock_background(rng)
	elif roll < 0.92:
		_background_effect = BACKGROUND_LIGHTNING
		_add_lightning_background(rng)
	elif roll < 0.97:
		_background_effect = BACKGROUND_CHAIN_CREATURE
		_add_chain_creature_background(rng)
	else:
		_background_effect = BACKGROUND_TENTACLE_BUNDLE
		_add_tentacle_bundle_background(rng)


func _add_flock_background(rng: RandomNumberGenerator) -> void:
	_flock_direction = -1.0 if rng.randf() < 0.5 else 1.0
	_flock_speed = rng.randf_range(6.8, 9.2)
	var center_x := (START_POINT.x + GOAL_POINT.x) * 0.5
	_flock_target = Vector3(center_x, rng.randf_range(12.0, 30.0), -_flock_direction * FLOCK_DEPTH_MIN)

	for index in FLOCK_BOID_COUNT:
		var position := Vector3(
			center_x + rng.randf_range(-FLOCK_SIDE_SPREAD, FLOCK_SIDE_SPREAD),
			rng.randf_range(8.0, 34.0),
			-_flock_direction * rng.randf_range(FLOCK_DEPTH_MIN, FLOCK_DEPTH_MAX)
		)
		var velocity := Vector3(
			rng.randf_range(-2.0, 2.0),
			rng.randf_range(-0.8, 0.8),
			_flock_direction * rng.randf_range(5.8, 9.0)
		)
		var manta := _make_manta_ray()
		manta.position = position
		_world_root.add_child(manta)
		var age_roll := rng.randf()
		var scale := lerpf(0.85, 2.9, pow(age_roll, 1.75))
		var size_alpha := clampf((scale - 0.85) / (2.9 - 0.85), 0.0, 1.0)
		var playful_chance := lerpf(0.68, 0.16, size_alpha)

		_flock_boids.append({
			"node": manta,
			"position": position,
			"velocity": velocity,
			"flap_phase": rng.randf_range(0.0, TAU),
			"bob_phase": rng.randf_range(0.0, TAU),
			"roll_phase": rng.randf_range(0.0, TAU),
			"flap_speed": rng.randf_range(1.6, 5.8),
			"bob_speed": rng.randf_range(0.7, 2.3),
			"scale": scale,
			"playful": rng.randf() < playful_chance,
			"roll_speed": rng.randf_range(0.32, 1.25),
		})


func _add_lightning_background(rng: RandomNumberGenerator) -> void:
	for index in 3:
		var bolt := Node3D.new()
		_world_root.add_child(bolt)
		var light := OmniLight3D.new()
		light.light_color = Color("#9eeaff")
		light.light_energy = 0.0
		light.omni_range = 70.0
		light.position = Vector3((START_POINT.x + GOAL_POINT.x) * 0.5, -3.0, 0.0)
		bolt.add_child(light)
		_lightning_bolts.append({
			"root": bolt,
			"light": light,
			"next_strike": rng.randf_range(0.6, 4.8) + float(index) * 1.2,
			"flash": 0.0,
			"seed": rng.randi(),
		})


func _add_chain_creature_background(rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	_world_root.add_child(root)
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
		root.add_child(segment)
		segments.append(segment)

	var light := OmniLight3D.new()
	light.light_color = Color("#74ffd6")
	light.light_energy = 1.1
	light.omni_range = 10.0
	root.add_child(light)

	_chain_creature = {
		"root": root,
		"segments": segments,
		"light": light,
		"west": rng.randf() < 0.5,
		"phase": rng.randf_range(0.0, TAU),
		"speed": rng.randf_range(0.42, 0.7),
		"z": rng.randf_range(-58.0, 58.0),
		"height": rng.randf_range(20.0, 54.0),
		"reach": rng.randf_range(7.0, 13.0),
	}


func _add_tentacle_bundle_background(rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	_world_root.add_child(root)
	var material := _make_tentacle_material()
	var center_x := (START_POINT.x + GOAL_POINT.x) * 0.5
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var anchor := Vector3(
		center_x + rng.randf_range(-24.0, 24.0),
		rng.randf_range(-23.5, -18.0),
		side * rng.randf_range(24.0, 36.0)
	)
	var tentacles: Array[Dictionary] = []

	for tentacle_index in 11:
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
			root.add_child(segment)
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
	root.add_child(light)

	_tentacle_bundle = {
		"root": root,
		"anchor": anchor,
		"side": side,
		"tentacles": tentacles,
		"light": light,
		"phase": rng.randf_range(0.0, TAU),
	}


func _process_background_effects(delta: float, elapsed: float) -> void:
	match _background_effect:
		BACKGROUND_FLOCK:
			_process_flock_background(delta, elapsed)
		BACKGROUND_LIGHTNING:
			_process_lightning_background(delta)
		BACKGROUND_CHAIN_CREATURE:
			_process_chain_creature_background(elapsed)
		BACKGROUND_TENTACLE_BUNDLE:
			_process_tentacle_bundle_background(delta, elapsed)


func _process_flock_background(delta: float, elapsed: float) -> void:
	var center_x := (START_POINT.x + GOAL_POINT.x) * 0.5
	_flock_target.z += _flock_direction * _flock_speed * delta
	_flock_target.x = center_x + sin(elapsed * 0.19) * 54.0
	_flock_target.y = 19.0 + sin(elapsed * 0.31) * 9.0
	if absf(_flock_target.z) > FLOCK_TARGET_LIMIT:
		_reset_flock_pass()

	var positions: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	for entry in _flock_boids:
		positions.append(entry["position"] as Vector3)
		velocities.append(entry["velocity"] as Vector3)

	for index in _flock_boids.size():
		var entry := _flock_boids[index]
		var position := positions[index]
		var velocity := velocities[index]
		var separation := Vector3.ZERO
		var alignment := Vector3.ZERO
		var cohesion := Vector3.ZERO
		var neighbor_count := 0

		for other_index in positions.size():
			if other_index == index:
				continue
			var other_position := positions[other_index]
			var offset := position - other_position
			var distance := offset.length()
			if distance <= 0.001 or distance > FLOCK_NEIGHBOR_RADIUS:
				continue

			neighbor_count += 1
			alignment += velocities[other_index]
			cohesion += other_position
			if distance < FLOCK_SEPARATION_RADIUS:
				separation += offset.normalized() / maxf(distance, 0.2)

		var acceleration := Vector3.ZERO
		var obstacle_repulsion := _flock_obstacle_repulsion(position, float(entry["scale"]))
		if neighbor_count > 0:
			separation = _boid_steer(separation / float(neighbor_count), velocity, FLOCK_MAX_SPEED, FLOCK_MAX_FORCE) * 1.8
			alignment = _boid_steer(alignment / float(neighbor_count), velocity, FLOCK_MAX_SPEED, FLOCK_MAX_FORCE) * 0.85
			cohesion = _boid_steer((cohesion / float(neighbor_count)) - position, velocity, FLOCK_MAX_SPEED, FLOCK_MAX_FORCE) * 0.75
			acceleration += separation + alignment + cohesion

		acceleration += obstacle_repulsion
		acceleration += _boid_steer(_flock_target - position, velocity, FLOCK_MAX_SPEED, FLOCK_MAX_FORCE) * 1.25
		if player != null:
			var player_interest := player.global_position + Vector3(0.0, 8.0, 0.0)
			var player_offset := player_interest - position
			var player_distance := player_offset.length()
			if player_distance < FLOCK_PLAYER_INTEREST_RADIUS:
				var interest_weight := 1.0 - clampf(player_distance / FLOCK_PLAYER_INTEREST_RADIUS, 0.0, 1.0)
				acceleration += _boid_steer(player_offset, velocity, FLOCK_MAX_SPEED, FLOCK_MAX_FORCE) * 0.38 * interest_weight
			if player_distance < FLOCK_PLAYER_AVOID_RADIUS:
				acceleration += _boid_steer(-player_offset, velocity, FLOCK_MAX_SPEED, FLOCK_MAX_FORCE) * 1.65
		acceleration.y += sin(elapsed * float(entry["bob_speed"]) + float(entry["bob_phase"])) * 0.65

		velocity += acceleration * delta
		velocity = _limit_vector(velocity, FLOCK_MAX_SPEED)
		position += velocity * delta
		entry["position"] = position
		entry["velocity"] = velocity

		var manta := entry["node"] as Node3D
		manta.position = position
		var forward := velocity.normalized()
		if forward.length() > 0.01:
			_orient_manta(manta, position, forward, obstacle_repulsion)
		var flap := sin(elapsed * float(entry["flap_speed"]) + float(entry["flap_phase"]))
		var scale := float(entry["scale"])
		manta.scale = Vector3.ONE * scale
		var left_wing := manta.get_node("LeftWing") as Node3D
		var right_wing := manta.get_node("RightWing") as Node3D
		left_wing.rotation_degrees.z = 11.0 + flap * 24.0
		right_wing.rotation_degrees.z = -11.0 - flap * 24.0
		var roll := -flap * 7.0
		if bool(entry["playful"]):
			var roll_wave := sin(elapsed * float(entry["roll_speed"]) + float(entry["roll_phase"]))
			if roll_wave > 0.42:
				roll += smoothstep(0.42, 1.0, roll_wave) * 360.0
		manta.rotate_object_local(Vector3.FORWARD, deg_to_rad(roll))


func _reset_flock_pass() -> void:
	_flock_direction = -1.0 if randf() < 0.5 else 1.0
	var center_x := (START_POINT.x + GOAL_POINT.x) * 0.5
	_flock_target = Vector3(center_x, randf_range(12.0, 30.0), -_flock_direction * FLOCK_DEPTH_MIN)
	for entry in _flock_boids:
		var position := Vector3(
			center_x + randf_range(-FLOCK_SIDE_SPREAD, FLOCK_SIDE_SPREAD),
			randf_range(8.0, 34.0),
			-_flock_direction * randf_range(FLOCK_DEPTH_MIN, FLOCK_DEPTH_MAX)
		)
		entry["position"] = position
		entry["velocity"] = Vector3(randf_range(-2.0, 2.0), randf_range(-0.8, 0.8), _flock_direction * randf_range(5.8, 9.0))
		(entry["node"] as Node3D).position = position


func _flock_obstacle_repulsion(position: Vector3, body_scale: float) -> Vector3:
	var repulsion := Vector3.ZERO
	var size_alpha := clampf((body_scale - 0.85) / (2.9 - 0.85), 0.0, 1.0)
	var hex_avoidance := lerpf(0.75, 2.0, size_alpha)
	var north_distance := FLOCK_WALL_LIMIT - position.z
	if north_distance < FLOCK_WALL_REPEL_RADIUS:
		var strength := pow(1.0 - clampf(north_distance / FLOCK_WALL_REPEL_RADIUS, 0.0, 1.0), 2.0)
		repulsion += Vector3(0.0, 0.0, -1.0) * FLOCK_MAX_FORCE * 1.35 * strength

	var south_distance := position.z + FLOCK_WALL_LIMIT
	if south_distance < FLOCK_WALL_REPEL_RADIUS:
		var strength := pow(1.0 - clampf(south_distance / FLOCK_WALL_REPEL_RADIUS, 0.0, 1.0), 2.0)
		repulsion += Vector3(0.0, 0.0, 1.0) * FLOCK_MAX_FORCE * 1.35 * strength

	for point in bridge_points:
		var offset := position - (point + Vector3(0.0, 1.0, 0.0))
		var horizontal := Vector3(offset.x, 0.0, offset.z)
		var horizontal_distance := horizontal.length()
		var vertical_distance := absf(offset.y)
		if horizontal_distance > FLOCK_HEX_REPEL_RADIUS or vertical_distance > 16.0:
			continue

		var radial_strength := pow(1.0 - horizontal_distance / FLOCK_HEX_REPEL_RADIUS, 2.0)
		var vertical_strength := 1.0 - clampf(vertical_distance / 16.0, 0.0, 1.0)
		var direction := Vector3(offset.x, offset.y * 0.85, 0.0)
		if direction.length() <= 0.001:
			direction = Vector3.UP
		repulsion += direction.normalized() * FLOCK_MAX_FORCE * 1.85 * hex_avoidance * radial_strength * vertical_strength

	return _limit_vector(repulsion, FLOCK_MAX_FORCE * 2.2)


func _orient_manta(manta: Node3D, position: Vector3, forward: Vector3, repulsion: Vector3) -> void:
	var repulsion_strength := clampf(repulsion.length() / (FLOCK_MAX_FORCE * 2.2), 0.0, 1.0)
	var desired_up := Vector3.UP
	if repulsion_strength > 0.001:
		desired_up = (Vector3.UP + repulsion.normalized() * FLOCK_REPULSION_BANK * repulsion_strength).normalized()

	var right := desired_up.cross(forward).normalized()
	if right.length() <= 0.001:
		right = Vector3.RIGHT
	var up := right.cross(forward).normalized()
	manta.global_basis = Basis(right, up, -forward).orthonormalized()
	manta.global_position = position


func _boid_steer(desired: Vector3, velocity: Vector3, max_speed: float, max_force: float) -> Vector3:
	if desired.length() <= 0.001:
		return Vector3.ZERO
	return _limit_vector(desired.normalized() * max_speed - velocity, max_force)


func _limit_vector(value: Vector3, maximum: float) -> Vector3:
	var length := value.length()
	if length > maximum and length > 0.0:
		return value / length * maximum
	return value


func _process_lightning_background(delta: float) -> void:
	for entry in _lightning_bolts:
		entry["next_strike"] = float(entry["next_strike"]) - delta
		entry["flash"] = maxf(float(entry["flash"]) - delta * 2.8, 0.0)
		if float(entry["next_strike"]) <= 0.0:
			_strike_lightning(entry)

		var light := entry["light"] as OmniLight3D
		var flash := float(entry["flash"])
		light.light_energy = flash * flash * 14.0
		for child in (entry["root"] as Node3D).get_children():
			if child is MeshInstance3D:
				child.transparency = 1.0 - flash


func _strike_lightning(entry: Dictionary) -> void:
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
		rng.randf_range(START_POINT.x + 14.0, GOAL_POINT.x - 14.0),
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
		candidate.x = clampf(candidate.x, START_POINT.x + 5.0, GOAL_POINT.x - 5.0)
		candidate.y = clampf(candidate.y, -16.5, -9.0)
		candidate.z = clampf(candidate.z, -58.0, 58.0)
		hits.append(candidate)

	for point in hits:
		_add_lightning_impact(root, point, rng.randf_range(2.4, 5.8))

	for index in range(1, hits.size()):
		var parent_index := maxi(0, index - rng.randi_range(1, mini(index, 3)))
		_add_lightning_path(root, hits[parent_index], hits[index], rng, rng.randf_range(0.09, 0.16))
		if index > 2 and rng.randf() < 0.36:
			_add_lightning_path(root, hits[index], hits[rng.randi_range(0, index - 1)], rng, rng.randf_range(0.055, 0.1))

	for point in hits:
		if rng.randf() < 0.24:
			var side := -1.0 if point.z < 0.0 else 1.0
			var cliff_point := Vector3(
				point.x + rng.randf_range(-6.0, 6.0),
				rng.randf_range(6.0, 38.0),
				side * rng.randf_range(68.0, 82.0)
			)
			_add_lightning_path(root, point, cliff_point, rng, rng.randf_range(0.06, 0.12))


func _add_lightning_path(root: Node3D, start: Vector3, end: Vector3, rng: RandomNumberGenerator, radius: float) -> void:
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
		_add_lightning_segment(root, previous, current, radius)
		previous = current


func _add_lightning_segment(root: Node3D, a: Vector3, b: Vector3, radius: float) -> void:
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


func _add_lightning_impact(root: Node3D, position: Vector3, radius: float) -> void:
	var impact := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(radius, radius)
	impact.mesh = mesh
	impact.position = position + Vector3(0.0, 0.04, 0.0)
	impact.rotation_degrees.x = -90.0
	impact.material_override = _make_lightning_impact_material(radius)
	root.add_child(impact)


func _process_chain_creature_background(elapsed: float) -> void:
	if _chain_creature.is_empty():
		return

	var west := bool(_chain_creature["west"])
	var wall_x := START_POINT.x - 22.0 if west else GOAL_POINT.x + 26.0
	var face := 1.0 if west else -1.0
	var phase := elapsed * float(_chain_creature["speed"]) + float(_chain_creature["phase"])
	var z := float(_chain_creature["z"]) + sin(phase * 0.37) * 18.0
	var height := float(_chain_creature["height"]) + sin(phase * 0.53) * 8.0
	var reach := float(_chain_creature["reach"])
	var anchor_a := Vector3(wall_x, height, z)
	var anchor_b := Vector3(
		wall_x + face * (reach + sin(phase) * 5.5),
		height - 9.0 + cos(phase * 1.4) * 7.0,
		z + sin(phase * 0.9) * 13.0
	)
	var segments: Array = _chain_creature["segments"]
	for index in segments.size():
		var t := float(index) / float(segments.size() - 1)
		var sag := sin(t * PI) * (5.5 + absf(sin(phase)) * 3.0)
		var sway := sin(phase * 1.7 + t * TAU) * 1.2
		var segment := segments[index] as Node3D
		segment.position = anchor_a.lerp(anchor_b, t) + Vector3(0.0, -sag, sway)

	var light := _chain_creature["light"] as OmniLight3D
	light.position = anchor_a.lerp(anchor_b, 0.65) + Vector3(0.0, -3.0, 0.0)
	light.light_energy = 0.8 + absf(sin(phase * 2.0)) * 0.7


func _process_tentacle_bundle_background(delta: float, elapsed: float) -> void:
	if _tentacle_bundle.is_empty():
		return

	var anchor := _tentacle_bundle["anchor"] as Vector3
	var side := float(_tentacle_bundle["side"])
	var phase := elapsed * 0.16 + float(_tentacle_bundle["phase"])
	var bundle_anchor := anchor + Vector3(
		sin(phase * 0.7) * 7.0,
		sin(phase * 0.43) * 1.2,
		cos(phase * 0.5) * 6.0
	)
	var tentacles: Array = _tentacle_bundle["tentacles"]
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
			target = _choose_tentacle_target(new_root, side, float(entry["segment_length"]) * float(segments.size()))
			entry["target"] = target

		var wander := Vector3(
			sin(tentacle_phase + float(entry["target_bias"])) * sway,
			sin(tentacle_phase * 1.7) * 2.5,
			cos(tentacle_phase * 0.8 + float(entry["target_bias"])) * sway * 0.55
		)
		var desired_tracking_point := target + wander
		var tracking_point := entry["tracking_point"] as Vector3
		var target_offset := desired_tracking_point - tracking_point
		var max_target_step := TENTACLE_TARGET_MAX_SPEED * delta
		if target_offset.length() > max_target_step and target_offset.length() > 0.001:
			tracking_point += target_offset.normalized() * max_target_step
		else:
			tracking_point = desired_tracking_point
		entry["tracking_point"] = tracking_point
		_solve_tentacle_ccd(points, tracking_point, float(entry["segment_length"]), delta)

		for index in segments.size():
			_place_cylinder_between(segments[index] as Node3D, points[index] as Vector3, points[index + 1] as Vector3)

	var light := _tentacle_bundle["light"] as OmniLight3D
	light.position = bundle_anchor + Vector3(0.0, 8.0 + sin(phase * 2.2) * 2.0, side * 6.0)
	light.light_energy = 2.8 + absf(sin(phase * 1.7)) * 2.1


func _choose_tentacle_target(root: Vector3, side: float, reach: float) -> Vector3:
	if randf() < 0.16:
		return Vector3(
			randf_range(START_POINT.x + 10.0, GOAL_POINT.x - 10.0),
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


func _solve_tentacle_ccd(points: Array, target: Vector3, segment_length: float, delta: float) -> void:
	var tip_index := points.size() - 1
	var max_angle := delta * TENTACLE_JOINT_MAX_ROTATION
	for iteration in 4:
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

		_limit_tentacle_bends(points, segment_length)


func _limit_tentacle_bends(points: Array, segment_length: float) -> void:
	for point_index in range(2, points.size()):
		var pivot := points[point_index - 1] as Vector3
		var previous_direction := (pivot - (points[point_index - 2] as Vector3)).normalized()
		var current_direction := ((points[point_index] as Vector3) - pivot).normalized()
		if previous_direction.length() <= 0.001 or current_direction.length() <= 0.001:
			continue

		var bend_angle := previous_direction.angle_to(current_direction)
		if bend_angle <= TENTACLE_JOINT_MAX_BEND:
			points[point_index] = pivot + current_direction * segment_length
			continue

		var axis := previous_direction.cross(current_direction)
		if axis.length() <= 0.001:
			current_direction = previous_direction
		else:
			current_direction = Basis(axis.normalized(), TENTACLE_JOINT_MAX_BEND) * previous_direction
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


func _make_manta_ray() -> Node3D:
	var root := Node3D.new()
	root.name = "MantaRay"

	var spine := MeshInstance3D.new()
	spine.name = "Spine"
	var spine_mesh := CylinderMesh.new()
	spine_mesh.top_radius = 0.07
	spine_mesh.bottom_radius = 0.09
	spine_mesh.height = 2.05
	spine.mesh = spine_mesh
	spine.position = Vector3(0.0, 0.0, 0.22)
	spine.rotation_degrees.x = 90.0
	spine.material_override = _make_manta_back_material()
	root.add_child(spine)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.42
	head_mesh.height = 0.16
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.0, -0.74)
	head.scale = Vector3(0.58, 0.2, 0.38)
	head.material_override = _make_manta_back_material()
	root.add_child(head)

	var left_wing := MeshInstance3D.new()
	left_wing.name = "LeftWing"
	left_wing.mesh = _make_manta_wing_mesh(-1.0)
	left_wing.material_override = _make_manta_back_material()
	root.add_child(left_wing)

	var right_wing := MeshInstance3D.new()
	right_wing.name = "RightWing"
	right_wing.mesh = _make_manta_wing_mesh(1.0)
	right_wing.material_override = _make_manta_back_material()
	root.add_child(right_wing)

	var left_belly := MeshInstance3D.new()
	left_belly.name = "LeftBellyWing"
	left_belly.mesh = _make_manta_belly_wing_mesh(-1.0)
	left_belly.material_override = _make_manta_belly_material()
	left_wing.add_child(left_belly)

	var right_belly := MeshInstance3D.new()
	right_belly.name = "RightBellyWing"
	right_belly.mesh = _make_manta_belly_wing_mesh(1.0)
	right_belly.material_override = _make_manta_belly_material()
	right_wing.add_child(right_belly)

	var tail := MeshInstance3D.new()
	tail.name = "Tail"
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = 0.025
	tail_mesh.bottom_radius = 0.04
	tail_mesh.height = 2.4
	tail.mesh = tail_mesh
	tail.position = Vector3(0.0, -0.03, 1.45)
	tail.rotation_degrees.x = 90.0
	tail.material_override = _make_manta_back_material()
	root.add_child(tail)

	return root


func _make_manta_wing_mesh(side: float) -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(0.0, 0.0, 0.42),
		Vector3(side * 2.2, 0.0, 0.18),
		Vector3(side * 1.7, 0.0, -0.72),
		Vector3(0.0, 0.0, -0.62),
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3] if side > 0.0 else [0, 2, 1, 0, 3, 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_manta_belly_wing_mesh(side: float) -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(side * 0.18, -0.035, 0.22),
		Vector3(side * 1.45, -0.035, 0.05),
		Vector3(side * 1.0, -0.035, -0.42),
		Vector3(side * 0.18, -0.035, -0.34),
	])
	var normals := PackedVector3Array([Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN])
	var indices := PackedInt32Array([0, 2, 1, 0, 3, 2] if side > 0.0 else [0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_manta_back_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#07162a")
	material.roughness = 0.85
	material.emission_enabled = true
	material.emission = Color("#0a274f")
	material.emission_energy_multiplier = 0.32
	return material


func _make_manta_belly_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#58ff7a")
	material.emission_enabled = true
	material.emission = Color("#58ff7a")
	material.emission_energy_multiplier = 3.2
	return material


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


func _make_cliff_material(ripple_color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CliffRippleShader
	material.set_shader_parameter("ripple_color", ripple_color)
	return material


func _make_tentacle_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TentacleNoiseShader
	material.set_shader_parameter("base_color", Color("#03081d"))
	material.set_shader_parameter("glow_color", Color("#7b16ff"))
	material.set_shader_parameter("noise_scale", 1.35)
	material.set_shader_parameter("noise_speed", 0.16)
	material.set_shader_parameter("glow_strength", 3.4)
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


func _make_lightning_impact_material(radius: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.55, 0.9, 1.0, 0.2)
	material.emission_enabled = true
	material.emission = Color("#aef4ff")
	material.emission_energy_multiplier = 1.8 + radius * 0.35
	return material


func _make_flat_hex_mesh(top_radius: float, bottom_radius: float, height: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var half_height := height * 0.5

	var top_center := Vector3(0.0, half_height, 0.0)
	var bottom_center := Vector3(0.0, -half_height, 0.0)
	var top_points: Array[Vector3] = []
	var bottom_points: Array[Vector3] = []

	for index in 6:
		var angle := TAU * float(index) / 6.0 + PI / 6.0
		top_points.append(Vector3(cos(angle) * top_radius, half_height, sin(angle) * top_radius))
		bottom_points.append(Vector3(cos(angle) * bottom_radius, -half_height, sin(angle) * bottom_radius))

	for index in 6:
		_add_flat_triangle(vertices, normals, indices, top_center, top_points[index], top_points[(index + 1) % 6], Vector3.UP)
		_add_flat_triangle(vertices, normals, indices, bottom_center, bottom_points[(index + 1) % 6], bottom_points[index], Vector3.DOWN)

	for index in 6:
		var next := (index + 1) % 6
		var a := bottom_points[index]
		var b := bottom_points[next]
		var c := top_points[next]
		var d := top_points[index]
		var normal := (b - a).cross(d - a).normalized()
		_add_flat_triangle(vertices, normals, indices, a, b, c, normal)
		_add_flat_triangle(vertices, normals, indices, a, c, d, normal)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_flat_triangle(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3
) -> void:
	var start := vertices.size()
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	indices.append(start)
	indices.append(start + 1)
	indices.append(start + 2)


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
