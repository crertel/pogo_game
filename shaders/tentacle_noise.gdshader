shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.01, 0.03, 0.12, 1.0);
uniform vec4 glow_color : source_color = vec4(0.56, 0.08, 0.95, 1.0);
uniform float noise_scale = 1.8;
uniform float noise_speed = 0.18;
uniform float glow_strength = 1.4;

varying vec3 world_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 sample_pos = world_pos * noise_scale + vec3(0.0, TIME * noise_speed, TIME * noise_speed * 1.7);
	float glow = smoothstep(0.52, 0.94, noise(sample_pos));
	float vein = smoothstep(0.035, 0.0, abs(fract(world_pos.y * 0.21 + TIME * 0.12 + noise(sample_pos * 0.55)) - 0.5));
	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.92;
	EMISSION = glow_color.rgb * (glow * glow_strength + vein * glow_strength * 0.55);
}
