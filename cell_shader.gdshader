shader_type canvas_item;

uniform vec4 cell_color : source_color = vec4(0.3, 0.7, 0.9, 1.0);
uniform vec4 nucleus_color : source_color = vec4(0.15, 0.35, 0.6, 1.0);
uniform float wobble_speed : hint_range(0.0, 10.0) = 3.0;
uniform float wobble_amplitude : hint_range(0.0, 0.1) = 0.03;
uniform float wobble_frequency : hint_range(1.0, 20.0) = 8.0;
uniform vec2 nucleus_offset = vec2(-0.05, -0.05);

// Squish deformation variables
uniform vec2 squish_dir = vec2(1.0, 0.0);
uniform float squish_amount : hint_range(-0.5, 0.5) = 0.0; // Positive stretches along squish_dir, negative squishes

// Spore mode overlay factor (0.0 normal, 1.0 brown spore shell)
uniform float spore_mode : hint_range(0.0, 1.0) = 0.0;

// Simple pseudo-noise based on sine waves
float get_wobble(float angle, float time) {
    // If in spore mode, wiggling decreases to show rigidity
    float active_wobble_amp = wobble_amplitude * (1.0 - spore_mode * 0.85);
    float w1 = sin(angle * wobble_frequency + time * wobble_speed);
    float w2 = cos(angle * (wobble_frequency * 0.5) - time * (wobble_speed * 0.7));
    return (w1 + w2) * active_wobble_amp;
}

void fragment() {
    vec2 center = vec2(0.5);
    vec2 uv = UV;
    
    // Convert to polar coordinates relative to center
    vec2 diff = uv - center;
    float dist = length(diff);
    
    // Safety check for division by zero
    vec2 dir = vec2(1.0, 0.0);
    if (dist > 0.0001) {
        dir = diff / dist;
    }
    
    float angle = atan(diff.y, diff.x);
    
    // Calculate ellipse squish factor along squish_dir
    vec2 norm_squish_dir = vec2(1.0, 0.0);
    if (length(squish_dir) > 0.0001) {
        norm_squish_dir = normalize(squish_dir);
    }
    
    float cos_angle = dot(dir, norm_squish_dir);
    // Dynamic ellipse stretch/squeeze factor
    float squish_factor = 1.0 + (cos_angle * cos_angle * 2.0 - 1.0) * squish_amount;
    
    // Cell shape (outer boundary)
    float wobble = get_wobble(angle, TIME);
    // Base radius is 0.38
    float cell_radius = (0.38 + wobble) * squish_factor;
    
    // Spore mode cell shell rendering (draws a darker border ring)
    float cell_edge = smoothstep(cell_radius, cell_radius - 0.015, dist);
    
    // Spore color interpolation
    // Spore outer shell: brown (#4d382b), spore nucleus: dark brown (#2b1f18)
    vec4 active_cell_color = mix(cell_color, vec4(0.3, 0.22, 0.17, 1.0), spore_mode);
    vec4 active_nucleus_color = mix(nucleus_color, vec4(0.18, 0.12, 0.09, 1.0), spore_mode);
    
    // Add thick border line if in spore mode
    if (spore_mode > 0.1) {
        float border_mask = smoothstep(cell_radius, cell_radius - 0.01, dist) - smoothstep(cell_radius - 0.03, cell_radius - 0.04, dist);
        active_cell_color = mix(active_cell_color, vec4(0.48, 0.35, 0.27, 1.0), border_mask * spore_mode);
    }
    
    // Nucleus shape (inner part)
    vec2 nucleus_center = center + nucleus_offset;
    // Organic floating movement (diminished in spore mode)
    float floating_speed = 1.5 * (1.0 - spore_mode * 0.9);
    nucleus_center.x += sin(TIME * floating_speed) * 0.005;
    nucleus_center.y += cos(TIME * floating_speed) * 0.005;
    
    vec2 n_diff = uv - nucleus_center;
    float n_dist = length(n_diff);
    
    vec2 n_dir = vec2(1.0, 0.0);
    if (n_dist > 0.0001) {
        n_dir = n_diff / n_dist;
    }
    float n_angle = atan(n_diff.y, n_diff.x);
    
    // Apply squish factor to nucleus as well
    float n_cos_angle = dot(n_dir, norm_squish_dir);
    float n_squish_factor = 1.0 + (n_cos_angle * n_cos_angle * 2.0 - 1.0) * squish_amount * 0.6;
    
    float n_wobble = sin(n_angle * 4.0 - TIME * wobble_speed * 0.8) * 0.006 * (1.0 - spore_mode);
    float nucleus_radius = (0.12 + n_wobble) * n_squish_factor;
    float nucleus_edge = smoothstep(nucleus_radius, nucleus_radius - 0.01, n_dist);
    
    // Combine colors
    vec4 final_color = vec4(0.0);
    
    // Outer cell body
    final_color = mix(final_color, active_cell_color, cell_edge);
    
    // Inner nucleus
    final_color = mix(final_color, active_nucleus_color, nucleus_edge);
    
    COLOR = final_color;
}
