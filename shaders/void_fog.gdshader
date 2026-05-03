shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled;

uniform vec4 fog_color : source_color = vec4(0.34, 0.48, 0.68, 0.1);
uniform float drift_speed = 0.05;
uniform float swirl_scale = 5.0;
uniform float edge_fade = 0.18;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amplitude;
		p = p * 2.03 + vec2(17.3, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float edge = smoothstep(0.5, 0.5 - edge_fade, max(abs(centered_uv.x), abs(centered_uv.y)));
	vec2 drift = vec2(TIME * drift_speed, -TIME * drift_speed * 0.7);
	float cloud = fbm(UV * swirl_scale + drift + vec2(sin(TIME * 0.08), cos(TIME * 0.07)));
	float alpha = fog_color.a * edge * smoothstep(0.28, 0.85, cloud);

	ALBEDO = fog_color.rgb;
	ALPHA = alpha;
}
