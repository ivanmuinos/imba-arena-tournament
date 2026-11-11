shader_type spatial;
render_mode cull_disabled, shadows_disabled, diffuse_lambert;
// Tufts of grass (and flowers): cards that bend with the wind from the root up. Instance colour = the tuft's own tint;
// UV.y = 1 at the root, 0 at the tip.

uniform vec3 root_color : source_color = vec3(0.09, 0.2, 0.05);
uniform float wind = 0.22;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying float v_tip;

void vertex() {
	v_tip = 1.0 - UV.y;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = texture(noise_tex, wpos.xz * 0.02 + vec2(TIME * 0.05, TIME * 0.03)).r - 0.5;
	float sway = (sin(TIME * 1.7 + wpos.x * 0.6 + wpos.z * 0.4) * 0.4 + gust * 2.0) * wind * v_tip * v_tip;
	// blades right in front of the camera lie down, so they never cover your champion
	VERTEX.y *= smoothstep(1.2, 4.5, distance(wpos, CAMERA_POSITION_WORLD));
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
	NORMAL = vec3(0.0, 1.0, 0.0);  // lit like the ground it grows from: no dark back faces
}

void fragment() {
	ALBEDO = mix(root_color, COLOR.rgb, smoothstep(0.0, 0.75, v_tip));
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
