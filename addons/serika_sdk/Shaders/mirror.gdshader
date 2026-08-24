// Mirror shader for Serika SDK. Renders the SubViewport texture aligned to screen space.
// Flip X/Y are exposed so world authors can correct if the reflection is reversed.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 color : source_color = vec4(0.95, 0.97, 1.0, 1.0);
uniform sampler2D mirror_texture : source_color, filter_linear_mipmap;
uniform bool flip_x = true;
uniform bool flip_y = false;

void fragment() {
	vec2 uv = SCREEN_UV;
	if (flip_x) uv.x = 1.0 - uv.x;
	if (flip_y) uv.y = 1.0 - uv.y;
	vec4 sample_col = texture(mirror_texture, uv);
	ALBEDO = sample_col.rgb * color.rgb;
	ALPHA = sample_col.a * color.a;
}
