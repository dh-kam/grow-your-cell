extends Area2D

# Each individual cell body piece (multiple pieces exist when split)
var velocity = Vector2.ZERO
var last_velocity = Vector2.ZERO
var cell_mass = 1.0

# Nucleus physics variables
var nucleus_pos = Vector2(-0.05, -0.05)
var nucleus_vel = Vector2.ZERO
const N_SPRING = 45.0
const N_DAMPING = 6.0
const N_INERTIA = 0.0004

# Squish physics variables (Jello wobble)
var squish_dir = Vector2(1.0, 0.0)
var squish_amount = 0.0
var squish_vel = 0.0
const S_SPRING = 35.0
const S_DAMPING = 5.0
const S_INERTIA = 0.0012

@onready var color_rect = $ColorRect
@onready var collision_shape = $CollisionShape2D

func _ready():
    # Make material instance unique per cell piece
    color_rect.material = color_rect.material.duplicate()
    # Connect collision signal
    area_entered.connect(_on_area_entered)

func init_cell(initial_mass: float, initial_pos: Vector2, initial_vel: Vector2):
    cell_mass = initial_mass
    position = initial_pos
    velocity = initial_vel
    update_scale()

func update_scale():
    var cell_scale = sqrt(cell_mass)
    scale = Vector2(cell_scale, cell_scale)
    if collision_shape and collision_shape.shape:
        collision_shape.shape.radius = 38.0

func add_mass(amount: float):
    cell_mass += amount
    update_scale()

func _process(delta):
    # Apply velocity
    position += velocity * delta
    
    # Bound check individual cell
    position.x = clamp(position.x, -2400, 2400)
    position.y = clamp(position.y, -2400, 2400)
    
    # Calculate cell acceleration
    var cell_accel = (velocity - last_velocity) / (delta if delta > 0 else 0.016)
    last_velocity = velocity
    
    # 1. Jello wobble squish solver
    if cell_accel.length() > 30.0:
        squish_dir = cell_accel.normalized()
        squish_vel += cell_accel.length() * S_INERTIA
        
    var s_force = -S_SPRING * squish_amount - S_DAMPING * squish_vel
    squish_vel += s_force * delta
    squish_amount += squish_vel * delta
    squish_amount = clamp(squish_amount, -0.4, 0.4)
    
    # 2. Nucleus Spring solver
    var default_offset = Vector2(-0.05, -0.05)
    var displacement = nucleus_pos - default_offset
    var n_accel = -N_SPRING * displacement - N_DAMPING * nucleus_vel - cell_accel * N_INERTIA
    
    nucleus_vel += n_accel * delta
    nucleus_pos += nucleus_vel * delta
    
    if nucleus_pos.length() > 0.15:
        nucleus_pos = nucleus_pos.limit_length(0.15)
        nucleus_vel = Vector2.ZERO
        
    # Apply to shader
    if color_rect and color_rect.material:
        color_rect.material.set_shader_parameter("nucleus_offset", nucleus_pos)
        color_rect.material.set_shader_parameter("squish_dir", squish_dir)
        color_rect.material.set_shader_parameter("squish_amount", squish_amount)

func set_spore_mode(enabled: bool):
    if color_rect and color_rect.material:
        color_rect.material.set_shader_parameter("spore_mode", 1.0 if enabled else 0.0)

# Collided with other cell: trigger a squish impact
func trigger_impact(impact_vector: Vector2, impact_force: float):
    squish_dir = impact_vector.normalized()
    squish_vel = -impact_force * 0.2

func _on_area_entered(area):
    if area.is_in_group("food"):
        # Detect Spore mode safety
        var p_controller = get_parent()
        if p_controller and p_controller.get("is_spore_mode") == true:
            return # Spore mode cannot eat/react
            
        var f_type = area.get("food_type")
        var f_val = area.value
        area.queue_free()
        
        # Grow locally
        add_mass(f_val * 0.08)
        trigger_impact(area.global_position - global_position, 15.0)
        
        # Report growth to master controller
        if p_controller and p_controller.has_method("add_player_mass"):
            p_controller.add_player_mass(f_val * 0.08)
            
            # If eaten a symbiotic pet, attach it!
            if f_type == "symbiont" and p_controller.get("pets").size() < 3:
                var pet_scene = load("res://pet.tscn")
                var pet = pet_scene.instantiate()
                p_controller.attach_pet(pet)
