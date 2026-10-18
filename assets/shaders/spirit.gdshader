shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	vec3 scene = texture(screen_texture, SCREEN_UV).rgb;
	float luminance = dot(scene, vec3(0.299, 0.587, 0.114));
	vec3 spirit = mix(scene, vec3(luminance), 0.85) * vec3(0.78, 0.99, 1.18);
	float edge = smoothstep(0.2, 0.72, length(UV - vec2(0.5)));
	COLOR = vec4(mix(spirit, vec3(0.54, 0.77, 0.9), edge * 0.24), 1.0);
}
