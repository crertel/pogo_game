extends Control

const SIZE := Vector2(84.0, 84.0)

var state: Dictionary = {}
var _shake_offset := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(next_state: Dictionary) -> void:
	state = next_state
	_update_shake()
	queue_redraw()


func _draw() -> void:
	var center := SIZE * 0.5 + _shake_offset
	var bunny_enabled := bool(state.get("bunny_enabled", false))
	var double_enabled := bool(state.get("double_enabled", false))
	var grapple_enabled := bool(state.get("grapple_enabled", false))

	if double_enabled:
		var charge := clampf(float(state.get("double_charge", 0.0)), 0.0, 1.0)
		var ring_color := Color("#8fd3ff") if bool(state.get("double_ready", false)) else Color("#47637a")
		draw_arc(center, 36.0, 0.0, TAU, 72, Color(0, 0, 0, 0.45), 8.0)
		draw_arc(center, 36.0, 0.0, TAU, 72, Color(1, 1, 1, 0.2), 2.0)
		if charge > 0.0:
			draw_arc(center, 36.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 72, ring_color, 6.0)

	if bunny_enabled:
		var bunny_amount := clampf(float(state.get("bunny_normalized", 0.0)), 0.0, 1.0)
		var bunny_color := Color("#4dff8f").lerp(Color("#ff4d4d"), bunny_amount)
		bunny_color.a = 0.78
		draw_circle(center, 16.0, Color(0, 0, 0, 0.42))
		draw_circle(center, 13.0 + bunny_amount * 4.0, bunny_color)
		draw_arc(center, 19.0, 0.0, TAU, 48, Color(1, 1, 1, 0.24), 2.0)

	if grapple_enabled:
		var cross_color := Color(1, 1, 1, 0.35)
		if bool(state.get("grapple_active", false)):
			cross_color = Color("#ffffff")
		elif bool(state.get("grapple_has_target", false)):
			cross_color = Color("#80e8ff")

		draw_line(center + Vector2(-9.0, 0.0), center + Vector2(9.0, 0.0), cross_color, 3.0)
		draw_line(center + Vector2(0.0, -9.0), center + Vector2(0.0, 9.0), cross_color, 3.0)


func _update_shake() -> void:
	var bunny_amount := clampf(float(state.get("bunny_normalized", 0.0)), 0.0, 1.0)
	if not bool(state.get("bunny_enabled", false)) or bunny_amount < 0.72:
		_shake_offset = Vector2.ZERO
		return

	var intensity := inverse_lerp(0.72, 1.0, bunny_amount)
	var t := Time.get_ticks_msec() / 1000.0
	_shake_offset = Vector2(
		sin(t * 53.0) + sin(t * 97.0) * 0.45,
		cos(t * 61.0) + sin(t * 89.0) * 0.35
	) * intensity * 2.2
