shader_type canvas_item;
// Dark glass: blurs whatever is behind the panel (3D scene or other UI) and tints it.
// The StyleBox fill must be pure black (0,0,0,1): that is what marks "glass" pixels; the border keeps its own colour.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 7.0) = 3.2;
uniform vec4 tint : source_color = vec4(0.035, 0.022, 0.02, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.62;
uniform vec4 glow : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float glow_amount : hint_range(0.0, 1.0) = 0.05;

void fragment() {
	float is_fill = 1.0 - step(0.01, max(COLOR.r, max(COLOR.g, COLOR.b)));
	vec3 blurred = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	vec3 glass = mix(blurred * 0.8, tint.rgb, tint_amount);
	glass += glow.rgb * glow_amount * (1.0 - UV.y);          // warm light from the top edge
	glass += vec3(0.02) * smoothstep(0.0, 1.0, 1.0 - UV.y);  // faint sheen
	COLOR = vec4(mix(COLOR.rgb, glass, is_fill), COLOR.a);
}
