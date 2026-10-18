shader_type canvas_item;
// Molten metal text: vertical gold->orange gradient, a bright band sweeping across, and a slow heat pulse.
// Meant for white text with a dark outline: only bright pixels get the gradient.

uniform vec2 area = vec2(400.0, 120.0);
uniform vec4 top : source_color = vec4(1.0, 0.92, 0.66, 1.0);
uniform vec4 bottom : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform float sweep_speed = 0.22;
uniform float sweep_pause = 0.8;
varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 uv = lp / area;
	float lum = dot(COLOR.rgb, vec3(0.3333));
	float fill = smoothstep(0.55, 0.9, lum);
	vec3 grad = mix(top.rgb, bottom.rgb, smoothstep(0.1, 1.0, uv.y));
	float cycle = fract(TIME * sweep_speed) * (1.0 + sweep_pause);
	float pos = cycle * 1.6 - 0.3;
	float band = smoothstep(0.12, 0.0, abs(uv.x - pos + uv.y * 0.35));
	float pulse = 0.92 + 0.08 * sin(TIME * 1.7);
	vec3 col = grad * pulse + vec3(1.0, 0.95, 0.8) * band * 0.85;
	COLOR.rgb = mix(COLOR.rgb, col, fill);
}
