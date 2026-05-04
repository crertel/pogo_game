shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D base_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 base_tint : source_color = vec4(0.12, 0.15, 0.18, 1.0);
uniform float base_texture_scale = 0.035;
uniform vec4 ripple_color : source_color = vec4(0.9, 0.06, 0.04, 1.0);
uniform float stripe_scale = 0.035;
uniform float stripe_speed = 0.18;
uniform float stripe_width = 0.045;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 rock_uv = world_pos.zy * base_texture_scale;
	vec3 rock = texture(base_texture, rock_uv).rgb * base_tint.rgb;
	float wave = fract(world_pos.y * stripe_scale - TIME * stripe_speed + sin(world_pos.z * 0.08) * 0.08);
	float stripe = smoothstep(stripe_width, 0.0, abs(wave - 0.5));
	ALBEDO = rock;
	ROUGHNESS = 1.0;
	EMISSION = ripple_color.rgb * stripe * 0.75;
}
