shader_type spatial;
render_mode cull_back, shadows_disabled;
// Still water of the pond: deep teal that clears toward the shore, with slow ripples of light.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 deep : source_color = vec3(0.02, 0.16, 0.24);
uniform vec3 shallow : source_color = vec3(0.1, 0.4, 0.42);
uniform float radius = 7.5;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float shore = smoothstep(radius * 0.55, radius, length(v_local.xz));
	vec2 uv = v_local.xz * 0.11;
	float a = texture(noise_tex, uv + vec2(TIME * 0.02, TIME * 0.013)).r;
	float b = texture(noise_tex, uv * 1.7 - vec2(TIME * 0.017, TIME * 0.022)).r;
	float ripple = smoothstep(0.66, 0.74, a * b * 2.2);
	vec3 c = mix(deep, shallow, shore) + vec3(0.5, 0.8, 0.75) * ripple * 0.18;
	ALBEDO = c;
	EMISSION = c * 0.25;
	ROUGHNESS = 0.3;
	METALLIC = 0.0;
	SPECULAR = 0.15;
	ALPHA = mix(0.9, 0.0, smoothstep(0.88, 1.0, length(v_local.xz) / radius));
}
