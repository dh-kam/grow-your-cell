extends Area2D

# Symbiont Pet orbiting the player and pulling food magnetically
var player = null
var angle = 0.0
const ORBIT_SPEED = 1.8
const ORBIT_RADIUS = 95.0
const MAGNET_FORCE = 380.0
const MAGNET_RADIUS = 250.0

@onready var color_rect = $ColorRect

func _ready():
    set_meta("is_pet", true)
    $ColorRect.material = $ColorRect.material.duplicate()
    # Tiny cyan cell
    $ColorRect.material.set_shader_parameter("cell_color", Color(0.2, 0.9, 0.9, 0.85))
    $ColorRect.material.set_shader_parameter("nucleus_color", Color(0.1, 0.5, 0.5, 0.9))
    $ColorRect.material.set_shader_parameter("wobble_speed", 5.0)
    $ColorRect.material.set_shader_parameter("wobble_amplitude", 0.04)

func _process(delta):
    if not player or player.active_cells.size() == 0:
        return
        
    # Orbit around the largest active player cell
    var target_cell = player.active_cells[0]
    for cell in player.active_cells:
        if cell.cell_mass > target_cell.cell_mass:
            target_cell = cell
            
    angle += ORBIT_SPEED * delta
    var target_orbit_radius = ORBIT_RADIUS * sqrt(target_cell.cell_mass)
    var target_pos = target_cell.global_position + Vector2(cos(angle), sin(angle)) * target_orbit_radius
    
    # Smooth position tracking
    global_position = global_position.lerp(target_pos, 8.0 * delta)
    
    # Magnetic pull on nearby food items
    var magnetic_pull = MAGNET_RADIUS
    if player.unlocked_mutations["sticky_glycocalyx"]:
        magnetic_pull *= 1.8 # Sticky mutation booster!
        
    var foods = get_tree().get_nodes_in_group("food")
    for food in foods:
        var dist = global_position.distance_to(food.global_position)
        if dist < magnetic_pull:
            # Pull food towards player cells!
            var pull_dir = (target_cell.global_position - food.global_position).normalized()
            var pull_strength = MAGNET_FORCE * (1.0 - (dist / magnetic_pull))
            food.velocity += pull_dir * pull_strength * delta
