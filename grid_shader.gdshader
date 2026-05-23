shader_type canvas_item;

uniform vec4 bg_color : source_color = vec4(0.08, 0.09, 0.12, 1.0);
uniform vec4 grid_color : source_color = vec4(0.16, 0.18, 0.23, 1.0);
uniform float grid_size = 100.0;
uniform float line_thickness = 1.5;

void fragment() {
    // Assuming the ColorRect covers the playable arena from -2500 to 2500 (total size 5000x5000)
    vec2 pos = UV * vec2(5000.0);
    
    vec2 grid = abs(fract(pos / grid_size - 0.5) - 0.5) / (line_thickness / grid_size);
    float line = min(grid.x, grid.y);
    float grid_mask = 1.0 - min(line, 1.0);
    
    vec4 final_color = mix(bg_color, grid_color, grid_mask);
    
    // Draw boundary line at the outer edges
    float boundary_mask = 0.0;
    if (pos.x < 15.0 || pos.x > 4985.0 || pos.y < 15.0 || pos.y > 4985.0) {
        boundary_mask = 1.0;
    }
    final_color = mix(final_color, vec4(0.8, 0.3, 0.3, 1.0), boundary_mask);
    
    // --- DRAW OSMOTIC SALT ZONES ---
    // Salt Zone 1: World position (2500 - 900, 2500 - 800) = (1600, 1700), Radius = 400
    float d1 = distance(pos, vec2(1600.0, 1700.0));
    float fill1 = (1.0 - smoothstep(400.0, 385.0, d1)) * 0.15;
    float ring1 = (smoothstep(403.0, 400.0, d1) - smoothstep(400.0, 397.0, d1)) * 0.4;
    
    // Salt Zone 2: World position (2500 + 900, 2500 + 800) = (3400, 3300), Radius = 400
    float d2 = distance(pos, vec2(3400.0, 3300.0));
    float fill2 = (1.0 - smoothstep(400.0, 385.0, d2)) * 0.15;
    float ring2 = (smoothstep(403.0, 400.0, d2) - smoothstep(400.0, 397.0, d2)) * 0.4;
    
    // Blend osmotic zones (Vibrant glowing orange)
    vec4 salt_color = vec4(0.9, 0.35, 0.1, 1.0);
    final_color = mix(final_color, salt_color, fill1 + ring1);
    final_color = mix(final_color, salt_color, fill2 + ring2);
    
    COLOR = final_color;
}
