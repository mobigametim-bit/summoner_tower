shader_type canvas_item;

uniform bool recolor_enabled = false;
uniform vec4 cloth_color : source_color = vec4(0.44, 0.57, 0.24, 1.0);
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	// Все parts сохраняют исходный canvas. Исключаем зелёное оперение в колчане.
	bool quiver_feathers = UV.x < 82.0 / 256.0 && UV.y < 90.0 / 256.0;
	bool cloth = texel.g > texel.r * 1.08 && texel.g > texel.b * 1.35;
	if (recolor_enabled && cloth && !quiver_feathers) {
		float shade = (texel.r + texel.g + texel.b) / (0.443 + 0.569 + 0.243);
		texel.rgb = clamp(cloth_color.rgb * shade, vec3(0.0), vec3(1.0));
	}
	COLOR = texel * item_color;
}
