shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Burn mark on the ground: sooty blotch with a glowing core that cools down; `fade` 1 -> 0 removes it.

uniform float fade = 1.0;
uniform float heat = 1.0;
uniform vec4 glow : source_color = vec4(1.0, 0.4, 0.05, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float n = texture(noise_tex, UV * 1.5).r;
	float blot = smoothstep(1.0, 0.25, r + (n - 0.5) * 0.7);
	float ember = smoothstep(0.55, 0.0, r + (n - 0.5) * 0.5) * heat;
	ALBEDO = mix(vec3(0.02, 0.015, 0.012), glow.rgb * 2.0, ember);
	ALPHA = clamp(blot * 0.72 * fade + ember * 0.6 * fade, 0.0, 1.0);
}
