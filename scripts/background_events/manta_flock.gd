extends Node3D

const BOID_COUNT := 72
const MAX_SPEED := 12.5
const MAX_FORCE := 10.0
const NEIGHBOR_RADIUS := 42.0
const SEPARATION_RADIUS := 15.0
const PLAYER_INTEREST_RADIUS := 62.0
const PLAYER_AVOID_RADIUS := 12.0
const SIDE_SPREAD := 90.0
const DEPTH_MIN := 118.0
const DEPTH_MAX := 168.0
const TARGET_LIMIT := 260.0
const WALL_LIMIT := 74.0
const WALL_REPEL_RADIUS := 24.0
const HEX_REPEL_RADIUS := 28.0
const REPULSION_BANK := 0.72

var start_point := Vector3.ZERO
var goal_point := Vector3.ZERO
var bridge_points: Array[Vector3] = []

var _boids: Array[Dictionary] = []
var _target := Vector3.ZERO
var _direction := 1.0
var _speed := 12.0


func setup(config: Dictionary, rng: RandomNumberGenerator) -> void:
	start_point = config["start_point"] as Vector3
	goal_point = config["goal_point"] as Vector3
	bridge_points.clear()
	for point in config["bridge_points"]:
		bridge_points.append(point as Vector3)

	_direction = float(config.get("direction", -1.0 if rng.randf() < 0.5 else 1.0))
	_speed = rng.randf_range(6.8, 9.2)
	var center_x := (start_point.x + goal_point.x) * 0.5
	_target = Vector3(center_x, rng.randf_range(12.0, 30.0), -_direction * DEPTH_MIN)

	for _index in BOID_COUNT:
		var position := Vector3(
			center_x + rng.randf_range(-SIDE_SPREAD, SIDE_SPREAD),
			rng.randf_range(8.0, 34.0),
			-_direction * rng.randf_range(DEPTH_MIN, DEPTH_MAX)
		)
		var velocity := Vector3(
			rng.randf_range(-2.0, 2.0),
			rng.randf_range(-0.8, 0.8),
			_direction * rng.randf_range(5.8, 9.0)
		)
		var manta := _make_manta_ray()
		manta.position = position
		add_child(manta)
		var age_roll := rng.randf()
		var scale := lerpf(0.85, 2.9, pow(age_roll, 1.75))
		var size_alpha := clampf((scale - 0.85) / (2.9 - 0.85), 0.0, 1.0)
		var playful_chance := lerpf(0.68, 0.16, size_alpha)

		_boids.append({
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


func get_debug_name() -> String:
	return "manta flock"


func process_effect(delta: float, elapsed: float, player: CharacterBody3D) -> void:
	var center_x := (start_point.x + goal_point.x) * 0.5
	_target.z += _direction * _speed * delta
	_target.x = center_x + sin(elapsed * 0.19) * 54.0
	_target.y = 19.0 + sin(elapsed * 0.31) * 9.0
	if absf(_target.z) > TARGET_LIMIT:
		_reset_pass()

	var positions: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	for entry in _boids:
		positions.append(entry["position"] as Vector3)
		velocities.append(entry["velocity"] as Vector3)

	for index in _boids.size():
		var entry := _boids[index]
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
			if distance <= 0.001 or distance > NEIGHBOR_RADIUS:
				continue

			neighbor_count += 1
			alignment += velocities[other_index]
			cohesion += other_position
			if distance < SEPARATION_RADIUS:
				separation += offset.normalized() / maxf(distance, 0.2)

		var acceleration := Vector3.ZERO
		var obstacle_repulsion := _obstacle_repulsion(position, float(entry["scale"]))
		if neighbor_count > 0:
			separation = _boid_steer(separation / float(neighbor_count), velocity, MAX_SPEED, MAX_FORCE) * 1.8
			alignment = _boid_steer(alignment / float(neighbor_count), velocity, MAX_SPEED, MAX_FORCE) * 0.85
			cohesion = _boid_steer((cohesion / float(neighbor_count)) - position, velocity, MAX_SPEED, MAX_FORCE) * 0.75
			acceleration += separation + alignment + cohesion

		acceleration += obstacle_repulsion
		acceleration += _boid_steer(_target - position, velocity, MAX_SPEED, MAX_FORCE) * 1.25
		if player != null:
			var player_interest := player.global_position + Vector3(0.0, 8.0, 0.0)
			var player_offset := player_interest - position
			var player_distance := player_offset.length()
			if player_distance < PLAYER_INTEREST_RADIUS:
				var interest_weight := 1.0 - clampf(player_distance / PLAYER_INTEREST_RADIUS, 0.0, 1.0)
				acceleration += _boid_steer(player_offset, velocity, MAX_SPEED, MAX_FORCE) * 0.38 * interest_weight
			if player_distance < PLAYER_AVOID_RADIUS:
				acceleration += _boid_steer(-player_offset, velocity, MAX_SPEED, MAX_FORCE) * 1.65
		acceleration.y += sin(elapsed * float(entry["bob_speed"]) + float(entry["bob_phase"])) * 0.65

		velocity += acceleration * delta
		velocity = _limit_vector(velocity, MAX_SPEED)
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


func _reset_pass() -> void:
	_direction = -1.0 if randf() < 0.5 else 1.0
	var center_x := (start_point.x + goal_point.x) * 0.5
	_target = Vector3(center_x, randf_range(12.0, 30.0), -_direction * DEPTH_MIN)
	for entry in _boids:
		var position := Vector3(
			center_x + randf_range(-SIDE_SPREAD, SIDE_SPREAD),
			randf_range(8.0, 34.0),
			-_direction * randf_range(DEPTH_MIN, DEPTH_MAX)
		)
		entry["position"] = position
		entry["velocity"] = Vector3(randf_range(-2.0, 2.0), randf_range(-0.8, 0.8), _direction * randf_range(5.8, 9.0))
		(entry["node"] as Node3D).position = position


func _obstacle_repulsion(position: Vector3, body_scale: float) -> Vector3:
	var repulsion := Vector3.ZERO
	var size_alpha := clampf((body_scale - 0.85) / (2.9 - 0.85), 0.0, 1.0)
	var hex_avoidance := lerpf(0.75, 2.0, size_alpha)
	var north_distance := WALL_LIMIT - position.z
	if north_distance < WALL_REPEL_RADIUS:
		var strength := pow(1.0 - clampf(north_distance / WALL_REPEL_RADIUS, 0.0, 1.0), 2.0)
		repulsion += Vector3(0.0, 0.0, -1.0) * MAX_FORCE * 1.35 * strength

	var south_distance := position.z + WALL_LIMIT
	if south_distance < WALL_REPEL_RADIUS:
		var strength := pow(1.0 - clampf(south_distance / WALL_REPEL_RADIUS, 0.0, 1.0), 2.0)
		repulsion += Vector3(0.0, 0.0, 1.0) * MAX_FORCE * 1.35 * strength

	for point in bridge_points:
		var offset := position - (point + Vector3(0.0, 1.0, 0.0))
		var horizontal := Vector3(offset.x, 0.0, offset.z)
		var horizontal_distance := horizontal.length()
		var vertical_distance := absf(offset.y)
		if horizontal_distance > HEX_REPEL_RADIUS or vertical_distance > 16.0:
			continue

		var radial_strength := pow(1.0 - horizontal_distance / HEX_REPEL_RADIUS, 2.0)
		var vertical_strength := 1.0 - clampf(vertical_distance / 16.0, 0.0, 1.0)
		var direction := Vector3(offset.x, offset.y * 0.85, 0.0)
		if direction.length() <= 0.001:
			direction = Vector3.UP
		repulsion += direction.normalized() * MAX_FORCE * 1.85 * hex_avoidance * radial_strength * vertical_strength

	return _limit_vector(repulsion, MAX_FORCE * 2.2)


func _orient_manta(manta: Node3D, position: Vector3, forward: Vector3, repulsion: Vector3) -> void:
	var repulsion_strength := clampf(repulsion.length() / (MAX_FORCE * 2.2), 0.0, 1.0)
	var desired_up := Vector3.UP
	if repulsion_strength > 0.001:
		desired_up = (Vector3.UP + repulsion.normalized() * REPULSION_BANK * repulsion_strength).normalized()

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
