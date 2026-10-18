shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
// Bubble / aura around a unit: fresnel rim with rippling bands, for shields, absorbs and buffs.

uniform vec4 color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float energy = 1.6;
uniform float bands = 6.0;
uniform float speed = 1.2;
uniform float strength = 0.9;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
	float ripple = 0.65 + 0.35 * sin(UV.y * bands * 6.2831 - TIME * speed * 3.0 + UV.x * 4.0);
	ALBEDO = color.rgb * energy * (0.4 + fres);
	ALPHA = clamp((0.08 + fres * 0.85) * ripple * strength, 0.0, 1.0);
}
