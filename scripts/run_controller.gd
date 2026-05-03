extends RefCounted

const TOTAL_LEVELS := 24

var level_index := 1
var run_complete := false
var started_msec := 0


func start() -> void:
	level_index = 1
	run_complete = false
	started_msec = Time.get_ticks_msec()


func restart() -> void:
	start()


func current_run_time_text() -> String:
	return format_run_time((Time.get_ticks_msec() - started_msec) / 1000.0)


func can_advance() -> bool:
	return level_index < TOTAL_LEVELS


func advance() -> int:
	if can_advance():
		level_index += 1
	else:
		run_complete = true
	return level_index


func transition_summary(next_level: int, next_tuning: Dictionary) -> Dictionary:
	if next_level > TOTAL_LEVELS:
		return {
			"run_time": current_run_time_text(),
			"stage_title": "Run Complete",
			"progress_text": "%d/%d" % [TOTAL_LEVELS, TOTAL_LEVELS],
			"koan": "The bridge remembers every crossing.",
		}

	return {
		"run_time": current_run_time_text(),
		"stage_title": "%s %s" % [
			str(next_tuning.get("arc_name", "")),
			str(next_tuning.get("phase_name", "")),
		],
		"progress_text": "%d/%d" % [next_level, TOTAL_LEVELS],
		"koan": koan_for_tuning(next_tuning),
	}


func format_run_time(seconds: float) -> String:
	var total_centiseconds := int(seconds * 100.0)
	var minutes := int(total_centiseconds / 6000)
	var remaining := total_centiseconds % 6000
	var whole_seconds := int(remaining / 100)
	var centiseconds := remaining % 100
	return "%02d:%02d.%02d" % [minutes, whole_seconds, centiseconds]


func koan_for_tuning(tuning: Dictionary) -> String:
	var mechanic := str(tuning.get("arc_name", ""))
	var phase := str(tuning.get("phase_name", ""))
	var combo := bool(tuning.get("combo", false))

	if combo and phase == "master":
		return "All tools are one motion."

	match mechanic:
		"Double Jump":
			return {
				"new": "The second step begins in empty air.",
				"practice": "Rise after the first answer.",
				"master": "Do not spend the sky too soon.",
			}.get(phase, "The air keeps one promise.")
		"Bunny Hop":
			return {
				"new": "Stillness loses speed.",
				"practice": "The floor is a drum; answer quickly.",
				"master": "Momentum is a path you keep choosing.",
			}.get(phase, "Speed gathers where doubt does not.")
		"Grapple":
			return {
				"new": "Reach before you leap.",
				"practice": "A distant point can be a handhold.",
				"master": "Pull the future toward you.",
			}.get(phase, "The hook finds what the eye believes.")
		"Exploding Hexes":
			return {
				"new": "Some ground is only a moment.",
				"practice": "Trust the step, then abandon it.",
				"master": "Leave nothing behind but falling stone.",
			}.get(phase, "A bridge may burn and still be crossed.")

	return "Crossing changes the crosser."
