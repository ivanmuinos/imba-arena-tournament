shader_type spatial;
render_mode unshaded, cull_disabled;
// Lava with slow crust plates: dark cooled rock plates drift on a glowing melt, bright cracks between them.
// Everything is low-frequency (plates are ~6 m wide) so large lava surfaces stay calm: no speckles, no high-frequency noise.

uniform float plate_size = 6.0;
uniform float flow_speed = 0.035;
uniform vec2 flow_dir = vec2(0.6, 0.8);
uniform vec3 crust_color : source_color = vec3(0.11, 0.05, 0.035);
uniform vec3 crack_hot : source_color = vec3(1.0, 0.62, 0.12);
uniform vec3 crack_deep : source_color = vec3(0.85, 0.16, 0.02);
uniform float energy = 1.6;
uniform float pulse = 0.18;
varying vec3 v_pos;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void fragment() {
	vec2 p = v_pos.xz / plate_size + flow_dir * TIME * flow_speed;
	// slow domain warp so plate borders wander instead of marching in a straight line
	p += 0.18 * vec2(sin(p.y * 1.7 + TIME * 0.08), cos(p.x * 1.3 - TIME * 0.06));
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 h = hash2(ip + g);
			vec2 pt = g + 0.5 + 0.32 * sin(TIME * 0.12 + 6.2831 * h);
			float d = length(pt - fp);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = ip + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float edge = d2 - d1;                       // 0 on the border between plates
	float crack = 1.0 - smoothstep(0.0, 0.16, edge);
	float core = 1.0 - smoothstep(0.0, 0.06, edge);
	float hs = hash2(id).x;
	float beat = 1.0 + pulse * sin(TIME * 0.8 + hs * 6.2831);
	vec3 plate = crust_color * (0.8 + 0.5 * hs);
	plate += crack_deep * 0.2 * smoothstep(0.4, 0.0, edge);  // plates are lit from the melt around them
	vec3 glow = mix(crack_deep, crack_hot, core);
	vec3 col = mix(plate, glow * beat, crack * 0.9 + core * 0.1);
	ALBEDO = col * energy;
}
