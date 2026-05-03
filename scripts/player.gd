extends CharacterBody3D

const SPEED := 8.6
const AIR_SPEED := 6.8
const JUMP_VELOCITY := 8.2
const GRAVITY := 22.0
const MOUSE_SENSITIVITY := 0.0025
const COYOTE_TIME := 0.11
const JUMP_BUFFER_TIME := 0.12

@onready var _head: Node3D = $Head

var _spawn_transform := Transform3D.IDENTITY
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _pitch := 0.0


func _ready() -> void:
	_spawn_transform = global_transform


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-82.0), deg_to_rad(82.0))
		_head.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if not is_on_floor():
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
	var max_speed := SPEED if is_on_floor() else AIR_SPEED
	var target_velocity := direction * max_speed

	velocity.x = move_toward(velocity.x, target_velocity.x, 28.0 * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, 28.0 * delta)

	if _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_left = 0.0
		_coyote_left = 0.0

	move_and_slide()


func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
