extends Area2D

var direction = Vector2.RIGHT
var speed = 520.0
var lifetime = 3.0
var creator = null
var melt_factor = 0.70
var pushback_force = 220.0
var impact_force = 60.0

func _ready():
    area_entered.connect(_on_area_entered)
    $ColorRect.material = $ColorRect.material.duplicate()

func _process(delta):
    position += direction * speed * delta
    lifetime -= delta
    if lifetime <= 0:
        queue_free()

func _on_area_entered(area):
    # Hit enemy!
    if area.is_in_group("enemies"):
        if area.get("is_absorbing") == true:
            return

        # Apply configured mass shrinkage. Cancer cells are especially vulnerable to lysosome acid.
        var effective_melt = melt_factor
        if area.get("enemy_type") == 2:
            effective_melt = max(0.28, melt_factor - 0.14)
        area.cell_mass *= effective_melt
        area.update_scale()
        
        # Apply pushback and squish impact
        area.velocity += direction * pushback_force
        area.trigger_impact(direction, impact_force)
        
        # Temporarily slow down enemy
        area.velocity *= 0.3

        if area.cell_mass < (0.34 if area.get("enemy_type") == 2 else 0.22):
            area.queue_free()
        
        # Explode projectile
        queue_free()
