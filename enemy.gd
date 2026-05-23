extends Area2D

# AI Enemy cells - can be predators (large, hunt player) or runners (small, flee player)
enum Type { PREDATOR, RUNNER }

var enemy_type = Type.PREDATOR
var cell_mass = 1.2
var velocity = Vector2.ZERO
var last_velocity = Vector2.ZERO
var steering = Vector2.ZERO
var steering_timer = 0.0

# Colors based on type
var cell_color = Color(0.7, 0.2, 0.4) # Dark purple/red
var nucleus_color = Color(0.4, 0.1, 0.2)

# Spring-Damper for nucleus physics
var nucleus_pos = Vector2(0.0, 0.0)
var nucleus_vel = Vector2.ZERO
const N_SPRING = 40.0
const N_DAMPING = 5.0
const N_INERTIA = 0.0006

# Squish physics
var squish_dir = Vector2(1.0, 0.0)
var squish_amount = 0.0
var squish_vel = 0.0
const S_SPRING = 35.0
const S_DAMPING = 5.0
const S_INERTIA = 0.0012

@onready var color_rect = $ColorRect
@onready var collision_shape = $CollisionShape2D

func _ready():
    # Make material instance unique
    color_rect.material = color_rect.material.duplicate()
    
    # Connect signals
    area_entered.connect(_on_area_entered)
    
    # Configure parameters based on type
    if randf() > 0.6:
        enemy_type = Type.RUNNER
        cell_mass = randf_range(0.5, 0.8)
        cell_color = Color(0.2, 0.8, 0.4) # Bright green
        nucleus_color = Color(0.1, 0.4, 0.2)
        $ColorRect.material.set_shader_parameter("wobble_speed", 5.0) # Faster wiggles
    else:
        enemy_type = Type.PREDATOR
        cell_mass = randf_range(1.5, 3.0) # Large
        cell_color = Color(0.8, 0.1, 0.3) # Crimson
        nucleus_color = Color(0.4, 0.0, 0.1)
        $ColorRect.material.set_shader_parameter("wobble_speed", 2.0)
        
    $ColorRect.material.set_shader_parameter("cell_color", cell_color)
    $ColorRect.material.set_shader_parameter("nucleus_color", nucleus_color)
    
    update_scale()
    select_steering()

func update_scale():
    var cell_scale = sqrt(cell_mass)
    scale = Vector2(cell_scale, cell_scale)
    if collision_shape and collision_shape.shape:
        collision_shape.shape.radius = 38.0

func select_steering():
    # Wander steering vector
    var angle = randf_range(0, PI * 2)
    var force = randf_range(100.0, 250.0)
    steering = Vector2(cos(angle), sin(angle)) * force
    steering_timer = randf_range(1.0, 3.0)

func _process(delta):
    handle_ai(delta)
    handle_physics(delta)

func handle_ai(delta):
    steering_timer -= delta
    
    # 1. Target evaluation
    var player = get_tree().get_first_node_in_group("player_cells")
    var target_cell = null
    var target_dist = 999999.0
    
    # Find closest player cell
    var player_cells = get_tree().get_nodes_in_group("player_cells")
    for cell in player_cells:
        # Ignore if player is in Spore Mode (invisible/invulnerable)
        var p_controller = cell.get_parent()
        if p_controller and p_controller.get("is_spore_mode") == true:
            continue
            
        var dist = global_position.distance_to(cell.global_position)
        if dist < target_dist and dist < 650.0:
            target_dist = dist
            target_cell = cell
            
    # 2. Steer direction
    if target_cell:
        var diff = target_cell.global_position - global_position
        var is_player_larger = target_cell.cell_mass > cell_mass
        
        if enemy_type == Type.PREDATOR:
            if is_player_larger:
                # Flee from larger player
                steering = -diff.normalized() * 300.0
            else:
                # Chase smaller player
                steering = diff.normalized() * 350.0
        elif enemy_type == Type.RUNNER:
            # Flee from player if they are close
            if target_dist < 400.0:
                steering = -diff.normalized() * 400.0
            else:
                # Roam towards food
                if steering_timer <= 0:
                    select_steering()
    else:
        # No player in sight, wander randomly
        if steering_timer <= 0:
            select_steering()

func handle_physics(delta):
    # Apply steering force
    var accel = steering / sqrt(cell_mass)
    velocity += accel * delta
    
    # Apply friction drag
    var friction = 0.8
    velocity -= velocity * friction * delta
    
    # Limit max speed
    var max_speed = 180.0 / sqrt(cell_mass)
    if enemy_type == Type.RUNNER:
        max_speed *= 1.4 # Runners are faster
    if velocity.length() > max_speed:
        velocity = velocity.limit_length(max_speed)
        
    position += velocity * delta
    
    # Boundary reflection
    const LIMIT = 2400
    if abs(position.x) > LIMIT:
        position.x = clamp(position.x, -LIMIT, LIMIT)
        velocity.x *= -1.0
        steering.x *= -1.0
    if abs(position.y) > LIMIT:
        position.y = clamp(position.y, -LIMIT, LIMIT)
        velocity.y *= -1.0
        steering.y *= -1.0
        
    # Calculate cell acceleration
    var cell_accel = (velocity - last_velocity) / (delta if delta > 0 else 0.016)
    last_velocity = velocity
    
    # 1. Elastic squish wobble
    if cell_accel.length() > 20.0:
        squish_dir = cell_accel.normalized()
        squish_vel += cell_accel.length() * S_INERTIA
        
    var s_force = -S_SPRING * squish_amount - S_DAMPING * squish_vel
    squish_vel += s_force * delta
    squish_amount += squish_vel * delta
    squish_amount = clamp(squish_amount, -0.4, 0.4)
    
    # 2. Nucleus Spring solver
    var default_offset = Vector2.ZERO
    var displacement = nucleus_pos - default_offset
    var n_accel = -N_SPRING * displacement - N_DAMPING * nucleus_vel - cell_accel * N_INERTIA
    
    nucleus_vel += n_accel * delta
    nucleus_pos += nucleus_vel * delta
    
    if nucleus_pos.length() > 0.15:
        nucleus_pos = nucleus_pos.limit_length(0.15)
        nucleus_vel = Vector2.ZERO
        
    if color_rect and color_rect.material:
        color_rect.material.set_shader_parameter("nucleus_offset", nucleus_pos)
        color_rect.material.set_shader_parameter("squish_dir", squish_dir)
        color_rect.material.set_shader_parameter("squish_amount", squish_amount)

func _on_area_entered(area):
    # Eating interactions
    if area.is_in_group("player_cells"):
        # Check spore mode safety
        var p_controller = area.get_parent()
        if p_controller and p_controller.get("is_spore_mode") == true:
            return # Spore mode makes immune!
            
        if cell_mass > area.cell_mass * 1.15:
            # Eat player piece
            cell_mass += area.cell_mass * 0.4
            update_scale()
            trigger_impact(area.global_position - global_position, 40.0)
            
            # Delete that piece
            p_controller.active_cells.erase(area)
            area.queue_free()
            p_controller.update_total_mass()
        elif area.cell_mass > cell_mass * 1.15:
            # Player eats this enemy
            area.add_mass(cell_mass * 0.4)
            area.trigger_impact(global_position - area.global_position, 40.0)
            queue_free()

    elif area.is_in_group("food"):
        # Eat food item
        cell_mass += area.value * 0.2
        update_scale()
        area.queue_free()

    elif area.is_in_group("enemies") and area != self:
        # Enemy eats smaller enemy
        if cell_mass > area.cell_mass * 1.15:
            cell_mass += area.cell_mass * 0.4
            update_scale()
            trigger_impact(area.global_position - global_position, 30.0)
            area.queue_free()

func trigger_impact(impact_vector: Vector2, impact_force: float):
    squish_dir = impact_vector.normalized()
    squish_vel = -impact_force * 0.2
