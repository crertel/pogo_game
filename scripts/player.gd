extends CharacterBody3D

const SPEED := 8.6
const AIR_SPEED := 6.8
const JUMP_VELOCITY := 8.2
const GRAVITY := 22.0
const MOUSE_SENSITIVITY := 0.0025
const COYOTE_TIME := 0.11
const JUMP_BUFFER_TIME := 0.12
const BUNNY_WINDOW := 0.2
const BUNNY_BOOST := 1.10
const BUNNY_CHAIN_BOOST := 1.16
const BUNNY_MAX_MULTIPLIER := 1.65
const BUNNY_MIN_SPEED := 4.2
const DOUBLE_RECHARGE_TIME := 0.35
const GRAPPLE_PULL := 84.0
const GRAPPLE_UPWARD_LIFT := 4.5
const GRAPPLE_RANGE := 28.0
const GRAPPLE_MISS_FLASH_TIME := 0.16

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D

var _spawn_transform := Transform3D.IDENTITY
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _pitch := 0.0
var _double_jump_enabled := false
var _bunny_hop_enabled := false
var _grapple_enabled := false
var _double_jump_available := false
var _was_on_floor := false
var _time_since_landing := 999.0
var _bunny_multiplier := 1.0
var _double_charge := 1.0
var _grapple_active := false
var _grapple_has_target := false
var _grapple_attached := false
var _grapple_target := Vector3.ZERO
var _grapple_miss_left := 0.0
var _rope_mesh: MeshInstance3D
var _rope_material: StandardMaterial3D


func _ready() -> void:
	_spawn_transform = global_transform
	_rope_material = StandardMaterial3D.new()
	_rope_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rope_material.albedo_color = Color("#80e8ff")
	_rope_material.emission_enabled = true
	_rope_material.emission = Color("#80e8ff")
	_rope_material.emission_energy_multiplier = 2.2

	_rope_mesh = MeshInstance3D.new()
	_rope_mesh.visible = false
	get_tree().current_scene.call_deferred("add_child", _rope_mesh)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-82.0), deg_to_rad(82.0))
		_head.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	_grapple_active = false
	var on_floor := is_on_floor()
	if on_floor:
		_double_charge = move_toward(_double_charge, 1.0, delta / DOUBLE_RECHARGE_TIME)
		_double_jump_available = _double_jump_enabled and _double_charge >= 1.0
	if on_floor and not _was_on_floor:
		_time_since_landing = 0.0
	elif on_floor:
		_time_since_landing += delta
	else:
		_time_since_landing = 999.0

	if not on_floor:
		velocity.y -= GRAVITY * delta
		_coyote_left = maxf(_coyote_left - delta, 0.0)
	else:
		_coyote_left = COYOTE_TIME

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = JUMP_BUFFER_TIME
	else:
		_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := global_transform.basis
	var direction := (basis.x * input_dir.x + basis.z * input_dir.y).normalized()
	var max_speed := (SPEED if on_floor else AIR_SPEED) * _bunny_multiplier
	var target_velocity := direction * max_speed

	velocity.x = move_toward(velocity.x, target_velocity.x, 28.0 * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, 28.0 * delta)

	if _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		_apply_bunny_hop_boost()
		velocity.y = JUMP_VELOCITY
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
	elif _jump_buffer_left > 0.0 and _double_jump_available:
		velocity.y = JUMP_VELOCITY * 0.92
		_double_jump_available = false
		_double_charge = 0.0
		_jump_buffer_left = 0.0

	if _grapple_enabled:
		_update_grapple_target()
		if Input.is_action_just_pressed("grapple"):
			_fire_grapple()
		if Input.is_action_just_released("grapple"):
			_detach_grapple()
		if _grapple_attached and Input.is_action_pressed("grapple"):
			_apply_grapple(delta)
	else:
		_detach_grapple()
		_grapple_has_target = false

	_grapple_miss_left = maxf(_grapple_miss_left - delta, 0.0)
	_update_rope_visual()

	move_and_slide()
	_was_on_floor = is_on_floor()


func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_double_jump_available = _double_jump_enabled
	_double_charge = 1.0
	_bunny_multiplier = 1.0
	_detach_grapple()


func set_mechanics(mechanics: Dictionary) -> void:
	_double_jump_enabled = bool(mechanics.get("double_jump", false))
	_bunny_hop_enabled = bool(mechanics.get("bunny_hop", false))
	_grapple_enabled = bool(mechanics.get("grapple", false))
	_double_charge = 1.0
	_double_jump_available = _double_jump_enabled
	if not _bunny_hop_enabled:
		_bunny_multiplier = 1.0


func _apply_bunny_hop_boost() -> void:
	if not _bunny_hop_enabled:
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed >= BUNNY_MIN_SPEED:
		var boost := BUNNY_CHAIN_BOOST if _time_since_landing <= BUNNY_WINDOW else BUNNY_BOOST
		_bunny_multiplier = minf(_bunny_multiplier * boost, BUNNY_MAX_MULTIPLIER)
	else:
		_bunny_multiplier = maxf(_bunny_multiplier * 0.82, 1.0)


func _apply_grapple(delta: float) -> void:
	if not _grapple_attached:
		return

	_grapple_active = true
	var pull := (_grapple_target - global_position).normalized()
	velocity += pull * GRAPPLE_PULL * delta
	velocity.y += GRAPPLE_UPWARD_LIFT * delta


func _fire_grapple() -> void:
	if _grapple_has_target:
		_grapple_attached = true
		_grapple_active = true
	else:
		_grapple_miss_left = GRAPPLE_MISS_FLASH_TIME


func _detach_grapple() -> void:
	_grapple_attached = false
	_grapple_active = false


func _update_grapple_target() -> void:
	var space_state := get_world_3d().direct_space_state
	var origin := _camera.global_position
	var target := origin + -_camera.global_transform.basis.z * GRAPPLE_RANGE
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [get_rid()]
	query.collision_mask = 0xFFFFFFFF
	var result := space_state.intersect_ray(query)
	_grapple_has_target = not result.is_empty()
	if _grapple_has_target and not _grapple_attached:
		_grapple_target = result["position"]


func _update_rope_visual() -> void:
	if _rope_mesh == null:
		return

	if _grapple_attached:
		_rope_material.albedo_color = Color("#80e8ff")
		_rope_material.emission = Color("#80e8ff")
		_draw_rope(_camera.global_position, _grapple_target)
	elif _grapple_miss_left > 0.0:
		_rope_material.albedo_color = Color("#ff5a4d")
		_rope_material.emission = Color("#ff5a4d")
		_draw_rope(_camera.global_position, _camera.global_position + -_camera.global_transform.basis.z * 7.0)
	else:
		_rope_mesh.visible = false


func _draw_rope(start: Vector3, end: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(end)
	mesh.surface_end()
	_rope_mesh.mesh = mesh
	_rope_mesh.material_override = _rope_material
	_rope_mesh.visible = true


func get_debug_state() -> Dictionary:
	return {
		"double_enabled": _double_jump_enabled,
		"double_ready": _double_jump_available,
		"double_charge": _double_charge,
		"bunny_enabled": _bunny_hop_enabled,
		"bunny_multiplier": _bunny_multiplier,
		"bunny_normalized": inverse_lerp(1.0, BUNNY_MAX_MULTIPLIER, _bunny_multiplier),
		"grapple_enabled": _grapple_enabled,
		"grapple_active": _grapple_active,
		"grapple_has_target": _grapple_has_target,
		"grapple_attached": _grapple_attached,
	}


func _exit_tree() -> void:
	if _rope_mesh != null:
		_rope_mesh.queue_free()
