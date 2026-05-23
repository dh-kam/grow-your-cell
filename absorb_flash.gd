extends Node2D

var duration = 0.5
var elapsed = 0.0
var direction = Vector2.RIGHT
var flash_color = Color(0.7, 1.0, 0.9, 1.0)
var strength = 1.0

func _process(delta):
    elapsed += delta
    if elapsed >= duration:
        queue_free()
        return
    queue_redraw()

func _draw():
    var t = clamp(elapsed / duration, 0.0, 1.0)
    var alpha = 1.0 - t
    var pulse_radius = lerp(18.0, 95.0 * strength, t)
    var ring_color = Color(flash_color.r, flash_color.g, flash_color.b, alpha * 0.85)
    var inner_color = Color(1.0, 1.0, 1.0, alpha * 0.35)

    draw_arc(Vector2.ZERO, pulse_radius, 0.0, TAU, 72, ring_color, 4.0)
    draw_arc(Vector2.ZERO, pulse_radius * 0.62, 0.0, TAU, 72, inner_color, 2.0)

    var dir = direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT
    var cup_center = dir * lerp(12.0, 42.0 * strength, t)
    draw_circle(cup_center, lerp(12.0, 3.0, t), Color(0.82, 1.0, 0.92, alpha * 0.7))

    for i in range(10):
        var angle = (float(i) / 10.0) * TAU + elapsed * 7.0
        var spoke_dir = Vector2(cos(angle), sin(angle))
        var p = spoke_dir * pulse_radius * lerp(0.25, 0.9, t)
        draw_circle(p, lerp(3.2, 0.8, t), Color(flash_color.r, flash_color.g, flash_color.b, alpha * 0.45))
