shader_type canvas_item;

uniform sampler2D palette_texture : filter_nearest;
uniform int palette_idx = 0; // 0 for Small
uniform int palette_height = 5;
uniform int palette_size = 3;

void fragment() {
    vec4 color = texture(TEXTURE, UV);
    if (color.a < 0.01) {
        discard;
    }

    float closest_dist = 1.0;
    int best_idx = -1;
    
    for (int i = 0; i < palette_size; i++) {
        float x = (float(i) + 0.5) / float(palette_size);
        vec4 p_color = texture(palette_texture, vec2(x, 0.5 / float(palette_height))); // Sample row 0 (Small)
        float d = distance(p_color, color);
        if (d < closest_dist && d < 0.1) {
            closest_dist = d;
            best_idx = i;
        }
    }
    
    if (best_idx != -1) {
        float x = (float(best_idx) + 0.5) / float(palette_size);
        float y = (float(palette_idx) + 0.5) / float(palette_height);
        COLOR = texture(palette_texture, vec2(x, y));
    } else {
        COLOR = color;
    }
}
