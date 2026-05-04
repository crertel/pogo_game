extends Node3D

const PlayerScene := preload("res://scenes/player.tscn")
const MechanicHudScript := preload("res://scripts/mechanic_hud.gd")
const TransitionOverlayScript := preload("res://scripts/transition_overlay.gd")
const LevelGenerator := preload("res://scripts/level_generator.gd")
const RunController := preload("res://scripts/run_controller.gd")
const WorldBuilder := preload("res://scripts/world_builder.gd")
const MantaFlockEvent := preload("res://scripts/background_events/manta_flock.gd")

const START_POINT := Vector3(-7.0, 0.0, 0.0)
const FALL_LIMIT := -18.0
const DEFAULT_MOUSE_SENSITIVITY := 0.0025

var _player: CharacterBody3D
var _status_label: Label
var _debug_label: Label
var _mechanic_hud: Control
var _transition_overlay: Control
var _menu_canvas: CanvasLayer
var _menu_root: Control
var _main_menu_panel: Control
var _settings_panel: Control
var _gameplay_canvas: CanvasLayer
var _volume_label: Label
var _sensitivity_label: Label
var _fullscreen_check: CheckButton
var _menu_background: Node3D
var _menu_mantas: Node3D
var _debug_visible := false
var _transitioning := false
var _has_won := false
var _game_started := false
var _menu_open := true
var _settings_open := false
var _bridge_points: Array[Vector3] = []
var _world_builder: Node3D
var _level_seed := 0
var _level_tuning := {}
var _level_generator := LevelGenerator.new()
var _run_controller := RunController.new()
var _max_step_distance := 0.0
var _max_step_height := 0.0
var _min_step_drop := 0.0
var _mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY


func _ready() -> void:
	_build_ui()
	_build_menu_background()
	_show_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return

	if event.is_action_pressed("ui_cancel"):
		_handle_escape()
		get_viewport().set_input_as_handled()
		return

	if _menu_open:
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
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if _menu_open:
		return
	if _player != null and _player.global_position.y < FALL_LIMIT and not _has_won and not _run_controller.run_complete and not _transitioning:
		_respawn_after_fall()


func _process(delta: float) -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0
	if _menu_open and _menu_mantas != null and _menu_mantas.has_method("process_effect"):
		_menu_mantas.process_effect(delta, elapsed, null)
	elif _world_builder != null:
		_world_builder.process_effects(delta, elapsed)

	_update_mechanic_hud()
	_update_debug_label()


func _build_world() -> void:
	if _world_builder != null:
		_world_builder.queue_free()

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
	if _player != null:
		_player.queue_free()

	_player = PlayerScene.instantiate()
	add_child(_player)
	if _player.has_method("set_spawn_transform"):
		_player.set_spawn_transform(_get_player_spawn_transform())
	else:
		_player.global_transform = _get_player_spawn_transform()
	if _player.has_method("set_mechanics"):
		_player.set_mechanics(_level_tuning.get("mechanics", {}))
	if _player.has_method("set_mouse_sensitivity"):
		_player.set_mouse_sensitivity(_mouse_sensitivity)
	if _world_builder != null:
		_world_builder.set_player(_player)


func _get_player_spawn_transform() -> Transform3D:
	var spawn := Transform3D.IDENTITY
	spawn.origin = START_POINT + Vector3(0.0, 2.2, 0.0)
	spawn.basis = Basis(Vector3.UP, deg_to_rad(-90.0))
	return spawn


func _build_ui() -> void:
	_gameplay_canvas = CanvasLayer.new()
	_gameplay_canvas.visible = false
	add_child(_gameplay_canvas)

	_status_label = Label.new()
	_status_label.position = Vector2(24.0, 20.0)
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 22)
	_gameplay_canvas.add_child(_status_label)
	_update_status_label()

	_debug_label = Label.new()
	_debug_label.position = Vector2(24.0, 54.0)
	_debug_label.add_theme_font_size_override("font_size", 16)
	_debug_label.visible = _debug_visible
	_gameplay_canvas.add_child(_debug_label)

	_mechanic_hud = Control.new()
	_mechanic_hud.set_script(MechanicHudScript)
	_mechanic_hud.set_anchors_preset(Control.PRESET_CENTER)
	_mechanic_hud.position = Vector2(-42.0, -42.0)
	_gameplay_canvas.add_child(_mechanic_hud)

	_transition_overlay = Control.new()
	_transition_overlay.set_script(TransitionOverlayScript)
	_transition_overlay.z_index = 100
	_gameplay_canvas.add_child(_transition_overlay)

	_build_menu_ui()


func _build_menu_background() -> void:
	_menu_background = Node3D.new()
	_menu_background.name = "MenuBackground"
	add_child(_menu_background)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#000000")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#07111f")
	environment.ambient_light_energy = 0.32
	environment.fog_enabled = true
	environment.fog_light_color = Color("#102033")
	environment.fog_density = 0.012
	world.environment = environment
	_menu_background.add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-18.0, 35.0, 0.0)
	light.light_color = Color("#9fb8d7")
	light.light_energy = 0.55
	_menu_background.add_child(light)

	var camera := Camera3D.new()
	camera.transform = Transform3D(Basis(), Vector3(38.0, 22.0, 18.0)).looking_at(Vector3(38.0, 21.0, -118.0), Vector3.UP)
	camera.fov = 68.0
	camera.far = 420.0
	camera.current = true
	_menu_background.add_child(camera)

	var rng := RandomNumberGenerator.new()
	rng.seed = 173
	_menu_mantas = MantaFlockEvent.new()
	_menu_background.add_child(_menu_mantas)
	_menu_mantas.setup({
		"start_point": Vector3(-7.0, 0.0, 0.0),
		"goal_point": Vector3(84.0, 0.0, 0.0),
		"bridge_points": [],
		"direction": 1.0,
	}, rng)


func _build_menu_ui() -> void:
	_menu_canvas = CanvasLayer.new()
	_menu_canvas.layer = 50
	add_child(_menu_canvas)

	_menu_root = Control.new()
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_canvas.add_child(_menu_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.42)
	_menu_root.add_child(shade)

	_main_menu_panel = _make_menu_panel()
	_menu_root.add_child(_main_menu_panel)

	var title := Label.new()
	title.text = "Pogo Chasm"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	_main_menu_panel.add_child(title)

	var new_game := _make_menu_button("New Game")
	new_game.pressed.connect(_start_new_game)
	_main_menu_panel.add_child(new_game)

	var settings := _make_menu_button("Settings")
	settings.pressed.connect(_show_settings_menu)
	_main_menu_panel.add_child(settings)

	var quit := _make_menu_button("Quit")
	quit.pressed.connect(_quit_game)
	_main_menu_panel.add_child(quit)

	_settings_panel = _make_menu_panel()
	_settings_panel.visible = false
	_menu_root.add_child(_settings_panel)

	var settings_title := Label.new()
	settings_title.text = "Settings"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 42)
	_settings_panel.add_child(settings_title)

	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = "Fullscreen"
	_fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_fullscreen_check.toggled.connect(_set_fullscreen)
	_settings_panel.add_child(_fullscreen_check)

	_volume_label = Label.new()
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_panel.add_child(_volume_label)

	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 100.0
	volume.step = 1.0
	volume.value = 100.0
	volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume.value_changed.connect(_set_master_volume)
	_settings_panel.add_child(volume)
	_set_master_volume(volume.value)

	_sensitivity_label = Label.new()
	_sensitivity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_panel.add_child(_sensitivity_label)

	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.8
	sensitivity.max_value = 6.0
	sensitivity.step = 0.1
	sensitivity.value = _mouse_sensitivity * 1000.0
	sensitivity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensitivity.value_changed.connect(_set_mouse_sensitivity)
	_settings_panel.add_child(sensitivity)
	_set_mouse_sensitivity(sensitivity.value)

	var back := _make_menu_button("Back")
	back.pressed.connect(_show_main_menu)
	_settings_panel.add_child(back)


func _make_menu_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360.0, 0.0)
	panel.position = Vector2(-180.0, -190.0)
	panel.add_theme_constant_override("separation", 16)
	return panel


func _make_menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320.0, 46.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 24)
	return button


func _show_main_menu() -> void:
	_menu_open = true
	_settings_open = false
	if _menu_canvas != null:
		_menu_canvas.visible = true
	if _main_menu_panel != null:
		_main_menu_panel.visible = true
	if _settings_panel != null:
		_settings_panel.visible = false
	if _gameplay_canvas != null:
		_gameplay_canvas.visible = false
	if _player != null:
		_player.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_settings_menu() -> void:
	_settings_open = true
	_main_menu_panel.visible = false
	_settings_panel.visible = true


func _hide_menu() -> void:
	_menu_open = false
	_settings_open = false
	if _menu_canvas != null:
		_menu_canvas.visible = false
	if _gameplay_canvas != null:
		_gameplay_canvas.visible = true
	if _player != null:
		_player.process_mode = Node.PROCESS_MODE_INHERIT
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _start_new_game() -> void:
	if _menu_background != null:
		_menu_background.queue_free()
		_menu_background = null
		_menu_mantas = null

	_run_controller.start()
	_game_started = true
	_build_world()
	_spawn_player()
	_hide_menu()
	_update_status_label()


func _handle_escape() -> void:
	if _settings_open:
		_show_main_menu()
	elif _menu_open:
		if _game_started:
			_hide_menu()
	else:
		_show_main_menu()


func _set_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)


func _set_master_volume(value: float) -> void:
	var normalized := clampf(value / 100.0, 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, -80.0 if normalized <= 0.001 else linear_to_db(normalized))
	if _volume_label != null:
		_volume_label.text = "Master Volume: %d%%" % int(round(value))


func _set_mouse_sensitivity(value: float) -> void:
	_mouse_sensitivity = clampf(value / 1000.0, 0.0008, 0.006)
	if _player != null and _player.has_method("set_mouse_sensitivity"):
		_player.set_mouse_sensitivity(_mouse_sensitivity)
	if _sensitivity_label != null:
		_sensitivity_label.text = "Mouse Sensitivity: %.1f" % value


func _quit_game() -> void:
	get_tree().quit()


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
