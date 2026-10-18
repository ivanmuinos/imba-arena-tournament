shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
// Fresnel rim light used as a selection/hover outline on character models (material_overlay).

uniform vec4 rim_color : source_color = vec4(1.0, 0.2, 0.15, 1.0);
uniform float power = 2.2;
uniform float strength = 2.0;

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	ALBEDO = rim_color.rgb * strength;
	ALPHA = clamp(f, 0.0, 1.0);
}
