extends RefCounted

const HEX_GRID_SPACING := 3.25
const PATH_STEPS := 28
const PATH_POINTS := PATH_STEPS + 1
const START_POINT := Vector3(-7.0, 0.0, 0.0)
const GOAL_POINT := Vector3(84.0, 0.0, 0.0)
const MAX_HORIZONTAL_STEP := 4.4
const MAX_VERTICAL_STEP := 1.35
const MIN_VERTICAL_STEP := -1.65
const HEIGHT_MIN := -4.5
const HEIGHT_MAX := 8.5
const TOTAL_LEVELS := 24


func generate(level_index: int, seed: int) -> Dictionary:
	var tuning := get_level_tuning(level_index)
	var bridge_points := _generate_bridge_points(seed, tuning)
	var stats := _path_stats(bridge_points)

	return {
		"seed": seed,
		"level_index": level_index,
		"tuning": tuning,
		"bridge_points": bridge_points,
		"stats": stats,
	}


func get_level_tuning(level_index: int) -> Dictionary:
	var arc := int((level_index - 1) / 3)
	var phase := int((level_index - 1) % 3)
	var mechanic_index := int(arc / 2)
	var is_combo_arc := arc % 2 == 1
	var mechanic_names := ["Double Jump", "Bunny Hop", "Grapple", "Exploding Hexes"]
	var mechanics := _mechanics_for_arc(mechanic_index, is_combo_arc)

	var tuning := {
		"arc_name": mechanic_names[mechanic_index],
		"phase_name": ["new", "practice", "master"][phase],
		"combo": is_combo_arc,
		"mechanics": mechanics,
		"lane_limit": [1, 2, 2][phase],
		"turn_chance": [0.24, 0.38, 0.52][phase],
		"branch_chance": [0.14, 0.26, 0.36][phase],
		"trend_min": [3, 2, 2][phase],
		"trend_max": [5, 5, 4][phase],
		"reversal_chance": [0.1, 0.18, 0.24][phase],
		"height_min": HEIGHT_MIN,
		"height_max": HEIGHT_MAX,
		"climb_min": 0.45,
		"climb_max": 1.0,
		"drop_min": 0.55,
		"drop_max": 1.05,
		"exploding_hexes": bool(mechanics.get("exploding_hexes", false)),
		"exploding_chance": [0.12, 0.22, 0.34][phase],
	}

	match mechanic_index:
		0:
			tuning["height_min"] = -2.5
			tuning["height_max"] = 7.8 + float(phase) * 0.5
			tuning["climb_min"] = 0.75 + float(phase) * 0.08
			tuning["climb_max"] = 1.2 + float(phase) * 0.1
			tuning["drop_min"] = 0.55
			tuning["drop_max"] = 1.15 + float(phase) * 0.12
		1:
			tuning["height_min"] = -3.2
			tuning["height_max"] = 7.2
			tuning["lane_limit"] = [2, 3, 3][phase]
			tuning["turn_chance"] = [0.42, 0.56, 0.7][phase]
			tuning["branch_chance"] = [0.22, 0.34, 0.48][phase]
			tuning["climb_min"] = 0.45
			tuning["climb_max"] = 0.95
			tuning["drop_min"] = 0.6
			tuning["drop_max"] = 1.2
		2:
			tuning["height_min"] = -5.5 - float(phase) * 0.4
			tuning["height_max"] = 9.5
			tuning["lane_limit"] = [1, 2, 2][phase]
			tuning["turn_chance"] = [0.24, 0.36, 0.5][phase]
			tuning["drop_min"] = 0.9
			tuning["drop_max"] = 1.35 + float(phase) * 0.08
			tuning["climb_min"] = 0.75
			tuning["climb_max"] = 1.35
			tuning["reversal_chance"] = [0.14, 0.2, 0.28][phase]
		3:
			tuning["height_min"] = -6.0
			tuning["height_max"] = 9.0
			tuning["lane_limit"] = [2, 3, 3][phase]
			tuning["turn_chance"] = [0.5, 0.64, 0.76][phase]
			tuning["branch_chance"] = [0.18, 0.3, 0.42][phase]
			tuning["climb_min"] = 0.7
			tuning["climb_max"] = 1.25 + float(phase) * 0.05
			tuning["drop_min"] = 0.9
			tuning["drop_max"] = 1.45 + float(phase) * 0.08
			tuning["reversal_chance"] = [0.2, 0.28, 0.34][phase]

	if is_combo_arc:
		tuning["lane_limit"] = mini(int(tuning["lane_limit"]) + 1, 3)
		tuning["turn_chance"] = minf(float(tuning["turn_chance"]) + 0.12, 0.82)
		tuning["branch_chance"] = minf(float(tuning["branch_chance"]) + 0.12, 0.58)
		tuning["height_min"] = float(tuning["height_min"]) - 0.8
		tuning["height_max"] = float(tuning["height_max"]) + 0.7

	return tuning


func axial_to_world(q: int, r: int) -> Vector3:
	return Vector3(
		START_POINT.x + float(q) * HEX_GRID_SPACING,
		0.0,
		float(r) * HEX_GRID_SPACING * 0.82
	)


func _generate_bridge_points(seed: int, tuning: Dictionary) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var points: Array[Vector3] = []
	var heights := _generate_vertical_profile(rng, tuning)
	var lane := 0
	var lane_limit := int(tuning["lane_limit"])

	for index in PATH_POINTS:
		if index == 0:
			points.append(START_POINT)
			continue

		if index < PATH_POINTS - 3 and rng.randf() < float(tuning["turn_chance"]):
			lane = clampi(lane + rng.randi_range(-1, 1), -lane_limit, lane_limit)

		var point := axial_to_world(index, lane)
		point.y = heights[index]
		points.append(point)

	points[0] = START_POINT
	points[points.size() - 1] = axial_to_world(PATH_STEPS, 0)
	points[points.size() - 1].y = heights[heights.size() - 1]
	return points


func _generate_vertical_profile(rng: RandomNumberGenerator, tuning: Dictionary) -> Array[float]:
	var heights: Array[float] = [0.0]
	var height := 0.0
	var trend := 1.0
	var trend_left := 0
	var climb_min := float(tuning["climb_min"])
	var climb_max := float(tuning["climb_max"])
	var drop_min := float(tuning["drop_min"])
	var drop_max := float(tuning["drop_max"])
	var height_min := float(tuning["height_min"])
	var height_max := float(tuning["height_max"])
	var reversal_chance := float(tuning["reversal_chance"])

	for index in range(1, PATH_POINTS):
		if index <= 2:
			height += rng.randf_range(0.25, 0.75)
		else:
			if trend_left <= 0:
				trend = -1.0 if rng.randf() < 0.5 else 1.0
				trend_left = rng.randi_range(int(tuning["trend_min"]), int(tuning["trend_max"]))

			var step := rng.randf_range(climb_min, climb_max) * trend
			if trend < 0.0:
				step = -rng.randf_range(drop_min, drop_max)
			if rng.randf() < reversal_chance:
				step *= -0.65

			height += step
			trend_left -= 1

		if height > height_max:
			height = height_max - rng.randf_range(0.0, 0.7)
			trend = -1.0
			trend_left = rng.randi_range(2, 4)
		elif height < height_min:
			height = height_min + rng.randf_range(0.0, 0.7)
			trend = 1.0
			trend_left = rng.randi_range(2, 4)

		heights.append(height)

	return heights


func _path_stats(points: Array[Vector3]) -> Dictionary:
	var max_step_distance := 0.0
	var max_step_height := 0.0
	var min_step_drop := 0.0

	for index in range(1, points.size()):
		var previous := points[index - 1]
		var current := points[index]
		var horizontal_distance := Vector2(current.x - previous.x, current.z - previous.z).length()
		var vertical_delta := current.y - previous.y
		var vertical_distance := absf(vertical_delta)
		max_step_distance = maxf(max_step_distance, horizontal_distance)
		max_step_height = maxf(max_step_height, vertical_distance)
		min_step_drop = minf(min_step_drop, vertical_delta)

	return {
		"max_step_distance": max_step_distance,
		"max_step_height": max_step_height,
		"min_step_drop": min_step_drop,
	}


func _mechanics_for_arc(mechanic_index: int, combo: bool) -> Dictionary:
	var mechanics := {
		"double_jump": false,
		"bunny_hop": false,
		"grapple": false,
		"exploding_hexes": false,
	}

	if combo:
		for index in range(mechanic_index + 1):
			_enable_mechanic(mechanics, index)
	else:
		_enable_mechanic(mechanics, mechanic_index)

	return mechanics


func _enable_mechanic(mechanics: Dictionary, index: int) -> void:
	match index:
		0:
			mechanics["double_jump"] = true
		1:
			mechanics["bunny_hop"] = true
		2:
			mechanics["grapple"] = true
		3:
			mechanics["exploding_hexes"] = true
