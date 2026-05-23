extends Area2D

# Food types
var food_type = "standard"
var value = 1.0
var color = Color(0.8, 0.3, 0.3)

# Wandering steering physics
var velocity = Vector2.ZERO
var last_velocity = Vector2.ZERO
var target_steering = Vector2.ZERO
var steering_timer = 0.0
const MAX_STEERING_FORCE = 120.0
const FRICTION = 0.8
const MAX_NPC_SPEED = 70.0

# Spring-Damper for nucleus physics
var nucleus_pos = Vector2(0.0, 0.0)
var nucleus_vel = Vector2.ZERO
const N_SPRING = 40.0
const N_DAMPING = 5.0
const N_INERTIA = 0.0006

func _ready():
    # Separate material instance
    var mat = $ColorRect.material.duplicate()
    
    # 1. Randomize food type
    var roll = randf()
    if roll < 0.05:
        food_type = "symbiont"
        value = 1.0
        color = Color(0.2, 0.9, 0.9) # Cyan
        mat.set_shader_parameter("cell_color", color)
        mat.set_shader_parameter("nucleus_color", Color(0.1, 0.5, 0.5))
        mat.set_shader_parameter("wobble_speed", 5.0)
    elif roll < 0.20:
        food_type = "golden"
        value = 2.8
        color = Color(1.0, 0.85, 0.2) # Gold
        mat.set_shader_parameter("cell_color", color)
        mat.set_shader_parameter("nucleus_color", Color(0.7, 0.4, 0.0))
        mat.set_shader_parameter("wobble_speed", 3.8)
    else:
        food_type = "standard"
        value = 1.0
        var r = randf_range(0.4, 0.95)
        var g = randf_range(0.3, 0.85)
        var b = randf_range(0.3, 0.85)
        color = Color(r, g, b)
        mat.set_shader_parameter("cell_color", color)
        mat.set_shader_parameter("nucleus_color", Color(r * 0.5, g * 0.5, b * 0.5))
        mat.set_shader_parameter("wobble_speed", randf_range(2.0, 5.0))
        
    mat.set_shader_parameter("wobble_amplitude", randf_range(0.02, 0.05))
    mat.set_shader_parameter("wobble_frequency", randf_range(4.0, 9.0))
    
    # Initialize random starting nucleus position
    nucleus_pos = Vector2(randf_range(-0.06, 0.06), randf_range(-0.06, 0.06))
    mat.set_shader_parameter("nucleus_offset", nucleus_pos)
    $ColorRect.material = mat
    
    # Randomize scale/size
    var size_multiplier = randf_range(0.6, 1.2)
    if food_type == "golden":
        size_multiplier *= 1.4 # Golden food is visibly larger
    scale = Vector2(size_multiplier, size_multiplier)
    value = size_multiplier * value
    
    # Initialize wandering force
    select_new_steering()

func select_new_steering():
    var angle = randf_range(0, PI * 2)
    target_steering = Vector2(cos(angle), sin(angle)) * randf_range(20.0, MAX_STEERING_FORCE)
    steering_timer = randf_range(1.5, 4.0)

func _process(delta):
    # 1. Wandering behavior
    steering_timer -= delta
    if steering_timer <= 0:
        select_new_steering()
        
    # Apply steering force
    velocity += target_steering * delta
    
    # Apply fluid drag/friction
    velocity -= velocity * FRICTION * delta
    
    # Enforce minimum speed
    var min_speed = 20.0
    if velocity.length() < min_speed:
        if velocity.length() == 0.0:
            var random_angle = randf_range(0.0, PI * 2.0)
            velocity = Vector2(cos(random_angle), sin(random_angle)) * min_speed
        else:
            velocity = velocity.normalized() * min_speed
            
    # Limit max velocity
    if velocity.length() > MAX_NPC_SPEED:
        velocity = velocity.limit_length(MAX_NPC_SPEED)
        
    # Move position
    position += velocity * delta
    
    # Boundary reflection
    const LIMIT = 2400
    if abs(position.x) > LIMIT:
        position.x = clamp(position.x, -LIMIT, LIMIT)
        velocity.x *= -1.0
        target_steering.x *= -1.0
    if abs(position.y) > LIMIT:
        position.y = clamp(position.y, -LIMIT, LIMIT)
        velocity.y *= -1.0
        target_steering.y *= -1.0
        
    # 2. Nucleus Spring-Mass physics simulation
    var npc_accel = (velocity - last_velocity) / (delta if delta > 0 else 0.016)
    last_velocity = velocity
    
    var n_accel = -N_SPRING * nucleus_pos - N_DAMPING * nucleus_vel - npc_accel * N_INERTIA
    
    nucleus_vel += n_accel * delta
    nucleus_pos += nucleus_vel * delta
    
    if nucleus_pos.length() > 0.15:
        nucleus_pos = nucleus_pos.limit_length(0.15)
        nucleus_vel = Vector2.ZERO
        
    if $ColorRect and $ColorRect.material:
        $ColorRect.material.set_shader_parameter("nucleus_offset", nucleus_pos)
