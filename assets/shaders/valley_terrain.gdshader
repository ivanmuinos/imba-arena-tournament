shader_type spatial;
// The valley's ground: meadow grass in two greens with dry patches, dirt paths, paved floors where a zone is built,
// scorched earth with glowing cracks beside the lava, and triplanar rock on anything steep.
// Vertex colour: r = path, g = paved, b = scorched, a = shade.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 grass_a : source_color = vec3(0.16, 0.33, 0.09);
uniform vec3 grass_b : source_color = vec3(0.33, 0.47, 0.11);
uniform vec3 grass_dry : source_color = vec3(0.55, 0.50, 0.18);
uniform vec3 dirt : source_color = vec3(0.36, 0.25, 0.15);
uniform vec3 stone : source_color = vec3(0.46, 0.4, 0.33);
uniform vec3 scorch : source_color = vec3(0.07, 0.05, 0.045);
uniform vec3 glow_color : source_color = vec3(1.0, 0.4, 0.1);

varying vec3 v_wpos;
varying vec3 v_wn;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	float n1 = texture(noise_tex, v_wpos.xz * 0.019).r;
	float n2 = texture(noise_tex, v_wpos.xz * 0.11 + vec2(0.31, 0.17)).r;
	float n3 = texture(noise_tex, v_wpos.xz * 0.83).r;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.7, n1));
	grass = mix(grass, grass_dry, smoothstep(0.5, 0.8, n2) * 0.45);
	grass *= 0.78 + 0.44 * n3;
	vec3 soil = dirt * (0.72 + 0.5 * n2) * (0.85 + 0.3 * n3);
	float path = smoothstep(0.3, 0.7, COLOR.r + (n2 - 0.5) * 0.55);
	// paving: big worn slabs, darker in the joints
	vec2 cell = fract(v_wpos.xz / 1.7 + vec2(n1 * 0.2));
	float joint = smoothstep(0.0, 0.06, min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y)));
	vec3 slab = stone * (0.8 + 0.4 * n2) * mix(0.68, 1.0, joint);
	float paved = smoothstep(0.35, 0.65, COLOR.g + (n2 - 0.5) * 0.35);
	vec3 base = mix(grass, soil, path);
	base = mix(base, slab, paved);
	float burnt = smoothstep(0.05, 0.9, COLOR.b + (n2 - 0.5) * 0.4 * COLOR.b);
	base = mix(base, scorch * (0.7 + 0.6 * n3), burnt);
	vec3 fn = normalize(cross(dFdx(v_wpos), dFdy(v_wpos)));
	vec3 rn = normalize(mix(v_wn, fn * sign(dot(fn, v_wn)), 0.65));
	float slope = smoothstep(0.38, 0.62, 1.0 - abs(fn.y));
	base = mix(base, triplanar(rock_tex, v_wpos * 0.1, rn) * vec3(0.95, 0.9, 0.82), slope);
	ALBEDO = base * COLOR.a;
	ROUGHNESS = mix(0.96, 0.8, max(slope, paved));
	float crack = smoothstep(0.62, 0.7, n3) * burnt * burnt;
	EMISSION = glow_color * crack * (1.6 + 0.6 * sin(TIME * 1.3 + n1 * 20.0));
}
