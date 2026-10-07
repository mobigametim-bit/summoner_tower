shader_type canvas_item;

uniform bool recolor_enabled = false;
uniform vec4 equipment_color : source_color = vec4(0.533, 0.725, 0.420, 1.0);
uniform sampler2D equipment_mask : filter_linear, repeat_disable;
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	// The mask limits brown leather to boots, bracers and loincloth; skin stays green.
	bool leather = texel.r > texel.g * 1.25 && texel.g > texel.b * 1.25 && texel.r > 0.2;
	if (recolor_enabled && leather) {
		float mask = texture(equipment_mask, UV).a;
		float shade = (texel.r + texel.g + texel.b) / (0.612 + 0.392 + 0.176);
		vec3 recolored = clamp(equipment_color.rgb * shade, vec3(0.0), vec3(1.0));
		texel.rgb = mix(texel.rgb, recolored, mask);
	}
	COLOR = texel * item_color;
}
