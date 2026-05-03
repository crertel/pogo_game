shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 burn_color : source_color = vec4(1.0, 0.34, 0.08, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(43.17, 289.31))) * 45758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += noise(p) * amplitude;
		p = p * 2.1 + vec2(11.7, 4.3);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	float radial = distance(UV, vec2(0.5));
	float n = fbm(UV * 8.0 + vec2(TIME * 0.35, -TIME * 0.18));
	float burn = n * 0.72 + radial * 0.55;
	float mask = smoothstep(progress - 0.08, progress + 0.03, burn);
	float alpha = 1.0 - mask;
	float edge = smoothstep(0.015, 0.0, abs(burn - progress));

	COLOR = mix(vec4(0.0, 0.0, 0.0, alpha), burn_color, edge * alpha);
}
