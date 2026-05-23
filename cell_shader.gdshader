shader_type canvas_item;

uniform vec4 cell_color : source_color = vec4(0.3, 0.7, 0.9, 1.0);
uniform vec4 nucleus_color : source_color = vec4(0.15, 0.35, 0.6, 1.0);
uniform vec4 membrane_color : source_color = vec4(0.75, 0.95, 1.0, 0.9);
uniform vec4 granule_color : source_color = vec4(0.95, 1.0, 1.0, 0.35);
uniform vec4 nucleolus_color : source_color = vec4(0.05, 0.14, 0.22, 0.95);
uniform float wobble_speed : hint_range(0.0, 10.0) = 3.0;
uniform float wobble_amplitude : hint_range(0.0, 0.1) = 0.03;
uniform float wobble_frequency : hint_range(1.0, 20.0) = 8.0;
uniform vec2 nucleus_offset = vec2(-0.05, -0.05);
uniform float membrane_thickness : hint_range(0.005, 0.08) = 0.025;
uniform float cytoplasm_noise : hint_range(0.0, 0.25) = 0.08;
uniform float granule_density : hint_range(0.0, 1.0) = 0.35;

// Squish deformation variables
uniform vec2 squish_dir = vec2(1.0, 0.0);
uniform float squish_amount : hint_range(-0.5, 0.5) = 0.0; // Positive stretches along squish_dir, negative squishes

// Spore mode overlay factor (0.0 normal, 1.0 brown spore shell)
uniform float spore_mode : hint_range(0.0, 1.0) = 0.0;

// Absorption / phagocytosis pulse.
uniform vec2 absorb_dir = vec2(1.0, 0.0);
uniform float absorb_progress : hint_range(0.0, 1.0) = 0.0;
uniform float absorb_strength : hint_range(0.0, 1.0) = 0.0;

// Simple pseudo-noise based on sine waves
float get_wobble(float angle, float time) {
    // If in spore mode, wiggling decreases to show rigidity
    float active_wobble_amp = wobble_amplitude * (1.0 - spore_mode * 0.85);
    float w1 = sin(angle * wobble_frequency + time * wobble_speed);
    float w2 = cos(angle * (wobble_frequency * 0.5) - time * (wobble_speed * 0.7));
    return (w1 + w2) * active_wobble_amp;
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
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

    vec2 norm_absorb_dir = vec2(1.0, 0.0);
    if (length(absorb_dir) > 0.0001) {
        norm_absorb_dir = normalize(absorb_dir);
    }
    float absorb_pulse = sin(absorb_progress * 3.14159265) * absorb_strength;
    float absorb_focus = pow(max(dot(dir, norm_absorb_dir), 0.0), 4.0);
    float absorb_lip = pow(abs(dot(dir, norm_absorb_dir)), 10.0);
    
    // Cell shape (outer boundary)
    float wobble = get_wobble(angle, TIME);
    // Base radius is 0.38
    float cell_radius = (0.38 + wobble) * squish_factor;
    cell_radius += absorb_focus * absorb_pulse * 0.08;
    cell_radius -= absorb_lip * absorb_pulse * 0.025;
    
    // Spore mode thickens the membrane and makes the cytoplasm feel compressed.
    float active_membrane_thickness = membrane_thickness + spore_mode * 0.025;
    float cell_mask = smoothstep(cell_radius, cell_radius - 0.018, dist);
    float inner_mask = smoothstep(cell_radius - active_membrane_thickness, cell_radius - active_membrane_thickness - 0.02, dist);
    float membrane_mask = clamp(cell_mask - inner_mask, 0.0, 1.0);
    
    // Spore color interpolation
    // Spore outer shell: brown (#4d382b), spore nucleus: dark brown (#2b1f18)
    vec4 active_cell_color = mix(cell_color, vec4(0.3, 0.22, 0.17, 1.0), spore_mode);
    vec4 active_nucleus_color = mix(nucleus_color, vec4(0.18, 0.12, 0.09, 1.0), spore_mode);
    vec4 active_membrane_color = mix(membrane_color, vec4(0.55, 0.42, 0.32, 1.0), spore_mode);
    
    float absorb_rim = absorb_focus * absorb_pulse * membrane_mask;
    active_membrane_color = mix(active_membrane_color, vec4(0.82, 1.0, 0.92, 1.0), absorb_rim);

    float cytoplasm_grain = hash21(floor(uv * 46.0));
    active_cell_color.rgb += (cytoplasm_grain - 0.5) * cytoplasm_noise;
    
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
    float nucleolus_edge = smoothstep(0.036, 0.026, length(uv - (nucleus_center + vec2(0.028, -0.018))));

    float granule_noise = hash21(floor(uv * 72.0));
    float granule_mask = step(1.0 - granule_density * 0.12, granule_noise) * inner_mask * (1.0 - nucleus_edge);
    float granule_size = smoothstep(0.7, 1.0, hash21(floor(uv * 118.0) + vec2(3.1, 9.7)));
    granule_mask *= granule_size * (1.0 - spore_mode * 0.65);
    
    // Combine colors
    vec4 final_color = vec4(0.0);
    
    // Cytoplasm body, microscopic granules, and membrane.
    final_color = mix(final_color, active_cell_color, inner_mask);
    final_color = mix(final_color, granule_color, granule_mask);
    final_color = mix(final_color, active_membrane_color, membrane_mask);
    
    // Inner nucleus
    final_color = mix(final_color, active_nucleus_color, nucleus_edge);
    final_color = mix(final_color, nucleolus_color, nucleolus_edge * nucleus_edge);
    
    COLOR = final_color;
}
