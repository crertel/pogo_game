extends Node3D

const PlayerScene := preload("res://scenes/player.tscn")
const MechanicHudScript := preload("res://scripts/mechanic_hud.gd")
const TransitionOverlayScript := preload("res://scripts/transition_overlay.gd")
const LevelGenerator := preload("res://scripts/level_generator.gd")
const RunController := preload("res://scripts/run_controller.gd")
const WorldBuilder := preload("res://scripts/world_builder.gd")

const START_POINT := Vector3(-7.0, 0.0, 0.0)
const FALL_LIMIT := -18.0

var _player: CharacterBody3D
var _status_label: Label
var _debug_label: Label
var _mechanic_hud: Control
var _transition_overlay: Control
var _debug_visible := false
var _transitioning := false
var _has_won := false
var _bridge_points: Array[Vector3] = []
var _world_builder: Node3D
var _level_seed := 0
var _level_tuning := {}
var _level_generator := LevelGenerator.new()
var _run_controller := RunController.new()
var _max_step_distance := 0.0
var _max_step_height := 0.0
var _min_step_drop := 0.0


func _ready() -> void:
	_run_controller.start()
	_build_world()
	_spawn_player()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return

	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed("regenerate_level"):
		_regenerate_level()
	elif event.is_action_pressed("advance_phase"):
		_debug_advance_phase()
	elif event.is_action_pressed("force_phase_end"):
		_debug_force_phase_end()
	elif event.is_action_pressed("toggle_debug"):
		_toggle_debug()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if _player != null and _player.global_position.y < FALL_LIMIT and not _has_won and not _run_controller.run_complete and not _transitioning:
		_respawn_after_fall()


func _process(delta: float) -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0
	if _world_builder != null:
		_world_builder.process_effects(delta, elapsed)

	_update_mechanic_hud()
	_update_debug_label()


func _build_world() -> void:
	_world_builder = WorldBuilder.new()
	add_child(_world_builder)
	_world_builder.setup_environment()
	_world_builder.goal_reached.connect(_on_goal_reached)
	_regenerate_level()


func _regenerate_level() -> void:
	if _world_builder == null:
		return

	_run_controller.run_complete = false
	_build_level(randi())


func _build_level(seed: int) -> void:
	if _world_builder == null:
		return

	_has_won = false
	if _status_label != null:
		_update_status_label()

	_level_seed = seed
	var level_data := _level_generator.generate(_run_controller.level_index, _level_seed)
	_level_tuning = level_data["tuning"]
	_bridge_points = level_data["bridge_points"]
	var stats: Dictionary = level_data["stats"]
	_max_step_distance = float(stats["max_step_distance"])
	_max_step_height = float(stats["max_step_height"])
	_min_step_drop = float(stats["min_step_drop"])
	_world_builder.build_level(level_data, _debug_visible)

	if _player != null:
		if _player.has_method("set_mechanics"):
			_player.set_mechanics(_level_tuning.get("mechanics", {}))
		if _player.has_method("set_spawn_transform"):
			_player.set_spawn_transform(_get_player_spawn_transform())
		else:
			_player.global_transform = _get_player_spawn_transform()
		_player.respawn()


func _respawn_after_fall() -> void:
	_build_level(_level_seed)


func _advance_level() -> void:
	if not _run_controller.can_advance():
		_run_controller.run_complete = true
		_has_won = true
		if _status_label != null:
			_status_label.text = "Run complete. R restarts from level 1."
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	_run_controller.advance()
	_build_level(randi())


func _transition_to_next_level() -> void:
	_transitioning = true
	var next_level: int = _run_controller.level_index + 1
	var next_tuning := {}
	if next_level <= RunController.TOTAL_LEVELS:
		next_tuning = _level_generator.get_level_tuning(next_level)
	var transition_text := _run_controller.transition_summary(next_level, next_tuning)

	_transition_overlay.set_transition_text(
		str(transition_text["run_time"]),
		str(transition_text["stage_title"]),
		str(transition_text["progress_text"]),
		str(transition_text["koan"])
	)
	await _transition_overlay.burn_to_black()
	await _transition_overlay.show_text()
	await get_tree().create_timer(0.85).timeout

	if not _run_controller.can_advance():
		_run_controller.run_complete = true
		_has_won = true
		if _status_label != null:
			_status_label.text = "Run complete. R restarts from level 1."
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_run_controller.level_index = next_level
		_build_level(randi())

	await _transition_overlay.hide_text()
	await _transition_overlay.burn_from_black()
	_transitioning = false


func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	add_child(_player)
	if _player.has_method("set_spawn_transform"):
		_player.set_spawn_transform(_get_player_spawn_transform())
	else:
		_player.global_transform = _get_player_spawn_transform()
	if _player.has_method("set_mechanics"):
		_player.set_mechanics(_level_tuning.get("mechanics", {}))
	if _world_builder != null:
		_world_builder.set_player(_player)


func _get_player_spawn_transform() -> Transform3D:
	var spawn := Transform3D.IDENTITY
	spawn.origin = START_POINT + Vector3(0.0, 2.2, 0.0)
	spawn.basis = Basis(Vector3.UP, deg_to_rad(-90.0))
	return spawn


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

	_transition_overlay = Control.new()
	_transition_overlay.set_script(TransitionOverlayScript)
	_transition_overlay.z_index = 100
	canvas.add_child(_transition_overlay)


func _update_debug_label() -> void:
	if _debug_label == null or not _debug_visible:
		return

	var player_position := Vector3.ZERO
	var player_velocity := Vector3.ZERO
	var is_grounded := false
	var player_state := _get_player_debug_state()
	if _player != null:
		player_position = _player.global_position
		player_velocity = _player.velocity
		is_grounded = _player.is_on_floor()

	var background_text := "none"
	if _world_builder != null and _world_builder.has_method("get_background_debug_text"):
		background_text = _world_builder.get_background_debug_text()

	_debug_label.text = (
		"F3/Tab debug  G regenerate  N advance  M transition\n"
		+ "level: %d/%d %s/%s  %s  bg: %s  seed: %d  hexes: %d  fps: %d\n"
		+ "max step: %.2fm  max climb/drop: %.2f/%.2fm\n"
		+ "player: %.1f, %.1f, %.1f  vel: %.1f  grounded: %s\n"
			+ "double: %s  bunny: x%.2f  grapple: %s"
		) % [
			_run_controller.level_index,
			RunController.TOTAL_LEVELS,
		str(_level_tuning.get("arc_name", "")),
		str(_level_tuning.get("phase_name", "")),
		_active_mechanics_text(),
		background_text,
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


func _update_mechanic_hud() -> void:
	if _mechanic_hud != null:
		_mechanic_hud.set_state(_get_player_debug_state())


func _get_player_debug_state() -> Dictionary:
	if _player != null and _player.has_method("get_debug_state"):
		return _player.get_debug_state()
	return {}


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
	if _world_builder != null:
		_world_builder.set_debug_visible(_debug_visible)


func _debug_advance_phase() -> void:
	if _transitioning:
		return

	if _run_controller.run_complete:
		_run_controller.restart()
	elif _run_controller.can_advance():
		_run_controller.advance()
	else:
		_run_controller.run_complete = true
		if _status_label != null:
			_status_label.text = "Run complete. R restarts from level 1."
		return

	_build_level(randi())


func _debug_force_phase_end() -> void:
	if _transitioning or _run_controller.run_complete:
		return

	_has_won = true
	if _status_label != null:
		_status_label.text = "Debug phase end."
	call_deferred("_transition_to_next_level")


func _update_status_label() -> void:
	if _status_label == null:
		return

	_status_label.text = "Level %d/%d: %s %s. %s N skips, M transitions." % [
		_run_controller.level_index,
		RunController.TOTAL_LEVELS,
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


func _on_goal_reached() -> void:
	if not _has_won:
		_has_won = true
		_status_label.text = "Level %d clear." % _run_controller.level_index
		call_deferred("_transition_to_next_level")
