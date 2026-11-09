// Terreno do KelwinSouls: deslocamento por heightmap (R32F) + splatting de 8 camadas.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D splat0 : filter_linear, repeat_disable;
uniform sampler2D splat1 : filter_linear, repeat_disable;
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cell = 4.0;
uniform float half_size = 4096.0;
uniform int n = 2049;
uniform float skirt = 12.0;
uniform float tile = 0.16;
uniform float detail_dist = 140.0;

varying vec3 world_pos;

float h_at(vec2 xz) {
	vec2 g = clamp((xz + half_size) / cell, vec2(0.0), vec2(float(n) - 1.001));
	ivec2 i = ivec2(floor(g));
	vec2 f = g - vec2(i);
	float a = texelFetch(heightmap, i, 0).r;
	float b = texelFetch(heightmap, i + ivec2(1, 0), 0).r;
	float c = texelFetch(heightmap, i + ivec2(0, 1), 0).r;
	float d = texelFetch(heightmap, i + ivec2(1, 1), 0).r;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = h_at(wp.xz);
	VERTEX.y = h - COLOR.r * skirt;
	world_pos = vec3(wp.x, h, wp.z);
	float hl = h_at(wp.xz - vec2(cell, 0.0));
	float hr = h_at(wp.xz + vec2(cell, 0.0));
	float hd = h_at(wp.xz - vec2(0.0, cell));
	float hu = h_at(wp.xz + vec2(0.0, cell));
	NORMAL = normalize(vec3(hl - hr, 2.0 * cell, hd - hu));
}

void fragment() {
	vec2 suv = (world_pos.xz + half_size) / (half_size * 2.0);
	vec4 w0 = texture(splat0, suv);
	vec4 w1 = texture(splat1, suv);
	float ws[8] = float[8](w0.r, w0.g, w0.b, w0.a, w1.r, w1.g, w1.b, w1.a);

	// normal por pixel a partir do heightmap (relevo fino)
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	// rocha extra nas encostas
	float rock_boost = smoothstep(0.25, 0.55, slope);
	for (int k = 0; k < 8; k++) { ws[k] *= (1.0 - rock_boost); }
	ws[2] += rock_boost;

	vec2 uv = world_pos.xz * tile;
	// anti-repetição: segunda escala com rotação
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * world_pos.xz * tile * 0.31;
	float dist = length(VERTEX);
	float near_w = 1.0 - smoothstep(detail_dist * 0.6, detail_dist, dist);

	vec3 col = vec3(0.0);
	vec3 nrm = vec3(0.0);
	float total = 0.0;
	for (int k = 0; k < 8; k++) {
		if (ws[k] > 0.02) {
			vec3 c1 = texture(albedo_arr, vec3(uv, float(k))).rgb;
			vec3 c2 = texture(albedo_arr, vec3(uv2, float(k))).rgb;
			col += mix(c2, mix(c1, c2, 0.35), 0.5 + 0.5 * near_w) * ws[k];
			if (near_w > 0.0) {
				nrm += texture(normal_arr, vec3(uv, float(k))).rgb * ws[k];
			}
			total += ws[k];
		}
	}
	col /= max(total, 0.001);
	// variação macro para quebrar a uniformidade
	float macro = texture(albedo_arr, vec3(world_pos.xz * 0.0021, 0.0)).g;
	col *= 0.78 + macro * 0.55;
	ALBEDO = col;
	if (near_w > 0.0) {
		vec3 nm = nrm / max(total, 0.001);
		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nm, near_w);
		NORMAL_MAP_DEPTH = 1.0;
	}
	ROUGHNESS = mix(0.92, 0.55, ws[3] * 0.6 + ws[5] * 0.5);
	SPECULAR = 0.25;
}
