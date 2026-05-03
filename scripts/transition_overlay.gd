extends Control

const BurnShader := preload("res://shaders/burn_transition.gdshader")

var _material: ShaderMaterial
var _black_rect: ColorRect
var _burn_rect: ColorRect
var _title_label: Label
var _koan_label: Label
var _time_label: Label
var _progress_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_material = ShaderMaterial.new()
	_material.shader = BurnShader
	_material.set_shader_parameter("progress", 0.0)

	_black_rect = ColorRect.new()
	_black_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black_rect.offset_left = 0.0
	_black_rect.offset_top = 0.0
	_black_rect.offset_right = 0.0
	_black_rect.offset_bottom = 0.0
	_black_rect.color = Color(0, 0, 0, 0)
	add_child(_black_rect)

	_burn_rect = ColorRect.new()
	_burn_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_burn_rect.offset_left = 0.0
	_burn_rect.offset_top = 0.0
	_burn_rect.offset_right = 0.0
	_burn_rect.offset_bottom = 0.0
	_burn_rect.material = _material
	add_child(_burn_rect)

	_time_label = _make_label(58, 0.33, -28.0)
	_title_label = _make_label(38, 0.66, -18.0)
	_koan_label = _make_label(22, 0.66, 28.0)
	_progress_label = _make_label(20, 0.66, 62.0)


func set_transition_text(run_time: String, stage_title: String, progress_text: String, koan_text: String) -> void:
	_title_label.text = stage_title
	_time_label.text = run_time
	_koan_label.text = koan_text
	_progress_label.text = progress_text


func burn_to_black() -> void:
	visible = true
	move_to_front()
	_set_label_alpha(0.0)
	_material.set_shader_parameter("progress", 0.0)
	_black_rect.color.a = 0.0
	var tween := create_tween()
	tween.tween_method(_set_progress, 0.0, 1.12, 0.82).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_method(_set_black_alpha, 0.0, 1.0, 0.82).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished


func show_text() -> void:
	var tween := create_tween()
	tween.tween_method(_set_label_alpha, 0.0, 1.0, 0.28)
	await tween.finished


func hide_text() -> void:
	var tween := create_tween()
	tween.tween_method(_set_label_alpha, 1.0, 0.0, 0.22)
	await tween.finished


func burn_from_black() -> void:
	var tween := create_tween()
	tween.tween_method(_set_progress, 1.12, 0.0, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_method(_set_black_alpha, 1.0, 0.0, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	visible = false


func _set_progress(value: float) -> void:
	_material.set_shader_parameter("progress", value)


func _set_black_alpha(value: float) -> void:
	_black_rect.color.a = value


func _set_label_alpha(value: float) -> void:
	for label in [_title_label, _koan_label, _time_label, _progress_label]:
		label.modulate.a = value


func _make_label(font_size: int, y_anchor: float, y_offset: float) -> Label:
	var label := Label.new()
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = y_anchor
	label.anchor_bottom = y_anchor
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = y_offset - 32.0
	label.offset_bottom = y_offset + 32.0
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#f4f0e8"))
	label.modulate.a = 0.0
	add_child(label)
	return label
