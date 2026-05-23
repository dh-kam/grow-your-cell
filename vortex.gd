extends Area2D

# Swirling fluid vortex
const PULL_STRENGTH = 200.0
const SWIRL_STRENGTH = 280.0
var radius = 250.0

@onready var collision_shape = $CollisionShape2D

func _ready():
    if collision_shape and collision_shape.shape:
        radius = collision_shape.shape.radius

func _physics_process(delta):
    # Apply swirling forces to all cells inside the vortex
    var areas = get_overlapping_areas()
    for area in areas:
        if area.has_meta("is_pet"):
            continue # Ignore pet attachments
            
        var area_velocity = area.get("velocity")
        if typeof(area_velocity) == TYPE_VECTOR2:
            var diff = global_position - area.global_position
            var dist = diff.length()
            if dist > 0.001 and dist < radius:
                # 1. Rotational force (swirl)
                var swirl_dir = Vector2(-diff.y, diff.x).normalized()
                # 2. Inward pull force
                var pull_dir = diff.normalized()
                
                # Attenuate force based on proximity to center
                var factor = 1.0 - (dist / radius)
                var force = (pull_dir * PULL_STRENGTH + swirl_dir * SWIRL_STRENGTH) * factor
                
                # Apply force to cell velocity
                area.set("velocity", area_velocity + force * delta)
                
                # Trigger a tiny squish wobble on entry
                if area.has_method("trigger_impact") and randf() > 0.98:
                    area.trigger_impact(swirl_dir, 15.0)
