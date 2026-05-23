extends Area2D

var direction = Vector2.RIGHT
var speed = 520.0
var lifetime = 3.0
var creator = null

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
        # Apply mass shrinkage (melt cell mass by 30%)
        area.cell_mass *= 0.70
        area.update_scale()
        
        # Apply pushback and squish impact
        area.velocity += direction * 220.0
        area.trigger_impact(direction, 60.0)
        
        # Temporarily slow down enemy
        area.velocity *= 0.3
        
        # Explode projectile
        queue_free()
