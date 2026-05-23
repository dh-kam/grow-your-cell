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

var absorb_timer = 0.0
var absorb_duration = 0.5
var absorb_strength = 0.0
var absorb_dir = Vector2.RIGHT

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

        if absorb_timer > 0.0:
            absorb_timer = max(absorb_timer - delta, 0.0)
            var absorb_progress = 1.0 - (absorb_timer / max(absorb_duration, 0.001))
            color_rect.material.set_shader_parameter("absorb_dir", absorb_dir)
            color_rect.material.set_shader_parameter("absorb_progress", absorb_progress)
            color_rect.material.set_shader_parameter("absorb_strength", absorb_strength)
        else:
            color_rect.material.set_shader_parameter("absorb_progress", 0.0)
            color_rect.material.set_shader_parameter("absorb_strength", 0.0)

func set_spore_mode(enabled: bool):
    if color_rect and color_rect.material:
        color_rect.material.set_shader_parameter("spore_mode", 1.0 if enabled else 0.0)

# Collided with other cell: trigger a squish impact
func trigger_impact(impact_vector: Vector2, impact_force: float):
    squish_dir = impact_vector.normalized()
    squish_vel = -impact_force * 0.2

func trigger_absorption(direction: Vector2, strength: float, duration: float):
    absorb_dir = direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT
    absorb_strength = strength
    absorb_duration = max(duration, 0.001)
    absorb_timer = absorb_duration
    trigger_impact(absorb_dir, 18.0 + strength * 24.0)

func _on_area_entered(area):
    if area.is_in_group("food"):
        if area.is_queued_for_deletion():
            return
        if area.get("is_absorbing") == true:
            return

        # Detect Spore mode safety
        var p_controller = get_parent()
        if p_controller and p_controller.get("is_spore_mode") == true:
            return # Spore mode cannot eat/react

        if p_controller and p_controller.has_method("start_food_absorb"):
            p_controller.start_food_absorb(self, area)
        else:
            var growth = area.value * 0.08
            area.queue_free()
            add_mass(growth)
