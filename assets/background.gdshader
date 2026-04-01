shader_type canvas_item;

uniform sampler2D bg_texture : repeat_enable, filter_linear;
uniform float tile_size : hint_range(1.0, 256.0) = 64.0;
uniform int grid_width = 1000;
uniform int grid_height = 1000;
uniform float time = 0.0;

// --- Helpers ---

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Returns a snow brightness value for a single layer.
// cell_size  — spacing between flakes in pixels
// drift      — vec2(horizontal_px_per_sec, vertical_px_per_sec)
// speed_seed — offsets each layer's timing so they don't sync up
float snow_layer(vec2 world_px, float cell_size, vec2 drift, float speed_seed) {
	// Scroll the coordinate space so flakes appear to move
	vec2 scrolled = world_px + drift * time + speed_seed * 371.5;

	// Divide into a grid of cells
	vec2 cell  = floor(scrolled / cell_size);
	vec2 local = fract(scrolled / cell_size);   // 0..1 within the cell

	// Each cell gets a unique random centre offset so flakes aren't on a grid
	vec2 centre = vec2(hash(cell), hash(cell + vec2(7.3, 2.9)));

	// Distance from this fragment to the flake centre
	float dist = length(local - centre);

	// Flake radius as a fraction of cell_size (tiny)
	float radius = 0.055;

	// Soft circular dot
	return smoothstep(radius, radius * 0.3, dist);
}

void fragment() {
	// World-space pixel position of this fragment
	vec2 world_px = UV * vec2(float(grid_width) * tile_size, float(grid_height) * tile_size);

	// --- Base texture (repeating) ---
	vec2 tex_size = vec2(textureSize(bg_texture, 0));
	vec2 tex_uv   = world_px / tex_size;
	vec4 base     = texture(bg_texture, tex_uv);

	// --- Per-tile brightness variation ---
	vec2  tile_coord = floor(world_px / tile_size);
	float variation  = (hash(tile_coord) - 0.5) * 0.09;
	base.rgb = clamp(base.rgb + variation, 0.0, 1.0);

	// --- Snow layers (3 depths) ---
	// Each layer: different cell size, slightly different angle, different brightness cap
	// drift = vec2(x px/s, y px/s) — gentle diagonal fall
	float s1 = snow_layer(world_px, 38.0, vec2(6.0,  28.0), 0.0)  * 0.30;
	float s2 = snow_layer(world_px, 26.0, vec2(4.0,  20.0), 1.0)  * 0.18;
	float s3 = snow_layer(world_px, 18.0, vec2(8.0,  38.0), 2.0)  * 0.10;

	float snow = clamp(s1 + s2 + s3, 0.0, 1.0);

	// Tint flakes a cool near-white so they read against the dark stone
	base.rgb += snow * vec3(0.82, 0.88, 1.0);

	COLOR = base;
}
