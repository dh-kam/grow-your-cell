extends Node2D

const CELL_SCENE = preload("res://player_cell.tscn")
const PROJECTILE_SCENE = preload("res://acid_projectile.tscn")
const ABSORB_FLASH_SCRIPT = preload("res://absorb_flash.gd")

# Baseline movement constants (applied to sub-cells)
const ACCELERATION = 480.0
const DEFAULT_FRICTION = 0.6
const CILIA_BRAKE_FRICTION = 8.0
const MAX_SPEED = 400.0
const MOVEMENT_MODE_MANUAL = "manual"
const MOVEMENT_MODE_AUTO = "auto"
const AUTO_FOOD_SCAN_RADIUS = 1050.0
const AUTO_ENEMY_SCAN_RADIUS = 850.0
const AUTO_SALT_MARGIN = 520.0
const AUTO_VORTEX_MARGIN = 320.0
const USER_ZOOM_MIN = 0.45
const USER_ZOOM_MAX = 2.2
const USER_ZOOM_STEP = 1.12

# Game system state
var active_cells = []
var merge_timers = {} # maps cell -> float (seconds remaining to merge)
var score = 0
var total_mass = 1.0

# Skill states
var is_spore_mode = false
var is_cilia_braking = false
var movement_mode = MOVEMENT_MODE_MANUAL
var auto_instinct = "growth"
var user_zoom_scale = 1.0
var focused_cell_index = 0
var recombine_primary = null
var recombine_target = null
var recombine_absorbing = false

# Mutation states
var unlocked_mutations = {
    "mitochondria_efficiency": false, # Dash mass cost halved
    "sticky_glycocalyx": false,       # Magnets food in a wider radius
    "rigid_cell_wall": false,         # Speed limit +30%, drag reduced, immune to salt
    "acid_projectile_boost": false    # Lysosome acid does more damage/larger
}
var mutation_milestones = [1.8, 3.5, 6.0]
var triggered_milestones = []

# Symbionts (pets) list
var pets = []

@onready var camera = $Camera2D

func _ready():
    # Spawn the initial player cell
    var first_cell = CELL_SCENE.instantiate()
    add_child(first_cell)
    first_cell.init_cell(1.0, Vector2.ZERO, Vector2.ZERO)
    active_cells.append(first_cell)
    call_deferred("update_movement_mode_ui")

func _process(delta):
    if active_cells.size() == 0:
        return
        
    handle_skills(delta)
    handle_movement(delta)
    handle_cell_interactions(delta)
    handle_camera(delta)
    handle_mutations()
    queue_redraw()

func _unhandled_input(event):
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            adjust_user_zoom(USER_ZOOM_STEP)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            adjust_user_zoom(1.0 / USER_ZOOM_STEP)
        elif event.button_index == MOUSE_BUTTON_LEFT:
            select_focused_cell_at(get_global_mouse_position())

func handle_movement(delta):
    var swarm_center = get_swarm_center()
        
    var friction = CILIA_BRAKE_FRICTION if is_cilia_braking else DEFAULT_FRICTION
    if unlocked_mutations["rigid_cell_wall"] and not is_cilia_braking:
        friction *= 0.6 # Lower drag for rigid walls
        
    # Apply movement forces to each active player cell piece
    for i in range(active_cells.size()):
        var cell = active_cells[i]
        if is_spore_mode:
            # Force stop
            cell.velocity = cell.velocity.move_toward(Vector2.ZERO, 500.0 * delta)
            continue

        var input_dir = get_movement_input_for_cell(cell, i)
            
        # Accelerate based on individual mass
        var cell_accel = ACCELERATION / sqrt(cell.cell_mass)
        cell.velocity += input_dir * cell_accel * delta

        if movement_mode == MOVEMENT_MODE_AUTO and active_cells.size() > 1:
            var cohesion = swarm_center - cell.global_position
            if cohesion.length() > 120.0:
                var cohesion_force = min(cohesion.length() * 0.45, 220.0) / sqrt(cell.cell_mass)
                cell.velocity += cohesion.normalized() * cohesion_force * delta
        
        # Apply fluid drag/friction
        cell.velocity -= cell.velocity * friction * delta
        
        # Apply min/max speed limits
        var min_speed = 80.0 / sqrt(cell.cell_mass)
        var max_speed = MAX_SPEED / sqrt(cell.cell_mass)
        if unlocked_mutations["rigid_cell_wall"]:
            max_speed *= 1.3
            
        var spd = cell.velocity.length()
        if spd < min_speed:
            if spd == 0.0:
                cell.velocity = Vector2(cos(randf()*TAU), sin(randf()*TAU)) * min_speed
            else:
                cell.velocity = cell.velocity.normalized() * min_speed
        elif spd > max_speed:
            cell.velocity = cell.velocity.limit_length(max_speed)

func handle_skills(delta):
    # 0. Movement instinct mode toggle (M key)
    if Input.is_physical_key_pressed(KEY_M):
        if not get_meta("movement_mode_key_locked", false):
            set_meta("movement_mode_key_locked", true)
            toggle_movement_mode()
    else:
        set_meta("movement_mode_key_locked", false)

    # 0-1. Focus split cell (Tab key)
    if Input.is_physical_key_pressed(KEY_TAB):
        if not get_meta("focus_key_locked", false):
            set_meta("focus_key_locked", true)
            cycle_focused_cell()
    else:
        set_meta("focus_key_locked", false)

    # 1. Spore mode (E key toggle)
    if Input.is_action_just_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_E):
        # Prevent spamming: toggle state
        if not Input.is_key_pressed(KEY_E): # Simple fallback just in case
            pass
    # We will do physical keyboard polls for toggling to bypass Action Map configs
    if Input.is_physical_key_pressed(KEY_E) and not Engine.get_frames_drawn() % 10 == 0:
        pass # Throttle toggle rate
    
    # Check E key press event (we check physical key states)
    # To prevent rapid toggling, we'll keep a key lock timer
    if Input.is_physical_key_pressed(KEY_E):
        if not get_meta("e_key_locked", false):
            is_spore_mode = not is_spore_mode
            set_meta("e_key_locked", true)
            for cell in active_cells:
                cell.set_spore_mode(is_spore_mode)
    else:
        set_meta("e_key_locked", false)
        
    # Spore mass drain
    if is_spore_mode:
        for cell in active_cells:
            var drain = 0.015 * delta * cell.cell_mass
            if cell.cell_mass > 0.2:
                cell.add_mass(-drain)
        update_total_mass()

    # 2. Cilia Brake (Ctrl key hold)
    is_cilia_braking = Input.is_physical_key_pressed(KEY_CTRL)

    # 3. Mitochondria Dash (Shift key press)
    if Input.is_physical_key_pressed(KEY_SHIFT):
        if not get_meta("shift_key_locked", false):
            set_meta("shift_key_locked", true)
            trigger_dash()
    else:
        set_meta("shift_key_locked", false)

    # 4. Lysosome Projectile (Q key press)
    if Input.is_physical_key_pressed(KEY_Q):
        if not get_meta("q_key_locked", false):
            set_meta("q_key_locked", true)
            trigger_projectile()
    else:
        set_meta("q_key_locked", false)

    # 5. Mitosis Split (Spacebar press)
    if Input.is_physical_key_pressed(KEY_SPACE):
        if not get_meta("space_key_locked", false):
            set_meta("space_key_locked", true)
            trigger_split()
    else:
        set_meta("space_key_locked", false)

    # 6. Focused recombine (R key press)
    if Input.is_physical_key_pressed(KEY_R):
        if not get_meta("recombine_key_locked", false):
            set_meta("recombine_key_locked", true)
            trigger_recombine()
    else:
        set_meta("recombine_key_locked", false)

func trigger_dash():
    if is_spore_mode or active_cells.size() == 0:
        return
        
    # Cost: 4% of total mass (2% if mutation unlocked)
    var cost_factor = 0.02 if unlocked_mutations["mitochondria_efficiency"] else 0.04
    
    # Apply speed burst to all cells that have sufficient mass
    var has_dashed = false
    for cell in active_cells:
        if cell.cell_mass > 0.15:
            cell.add_mass(-cell.cell_mass * cost_factor)
            # Add velocity thrust in current movement direction (or velocity heading)
            var thrust_dir = cell.velocity.normalized()
            if thrust_dir == Vector2.ZERO:
                thrust_dir = Vector2.UP
            cell.velocity += thrust_dir * 380.0
            cell.trigger_impact(-thrust_dir, 60.0) # Organic squish recoil
            has_dashed = true
            
    if has_dashed:
        update_total_mass()

func trigger_projectile():
    if is_spore_mode or active_cells.size() == 0:
        return

    var has_acid_boost = unlocked_mutations["acid_projectile_boost"]
    var target_pos = get_global_mouse_position()
    var has_fired = false

    for cell in active_cells:
        if cell.cell_mass < 0.25:
            continue

        # Cost: 5% mass of each firing cell
        var cost = cell.cell_mass * 0.05
        cell.add_mass(-cost)

        # Calculate fire direction towards mouse cursor from each cell
        var fire_dir = (target_pos - cell.global_position).normalized()
        if fire_dir == Vector2.ZERO:
            fire_dir = Vector2.RIGHT

        var projectile = PROJECTILE_SCENE.instantiate()
        projectile.global_position = cell.global_position + fire_dir * (cell.scale.x * 40.0)
        projectile.direction = fire_dir
        projectile.creator = self
        projectile.scale = Vector2(1.0, 1.0) * (1.5 if has_acid_boost else 1.0)
        projectile.melt_factor = 0.55 if has_acid_boost else 0.70
        projectile.pushback_force = 280.0 if has_acid_boost else 220.0
        projectile.impact_force = 80.0 if has_acid_boost else 60.0
        get_parent().add_child(projectile)

        # Backwards kickback force on firing cell
        cell.velocity -= fire_dir * 180.0
        cell.trigger_impact(fire_dir, 35.0)
        has_fired = true

    if has_fired:
        update_total_mass()

func trigger_split():
    if is_spore_mode or active_cells.size() >= 16:
        return
        
    var new_splits = []
    for cell in active_cells:
        # Minimum mass to split (needs to be reasonably large)
        if cell.cell_mass >= 0.35:
            var half_mass = cell.cell_mass / 2.0
            cell.cell_mass = half_mass
            cell.update_scale()
            
            # Spawn twin cell
            var twin = CELL_SCENE.instantiate()
            add_child(twin)
            
            # Determine split heading direction
            var split_dir = cell.velocity.normalized()
            if split_dir == Vector2.ZERO:
                split_dir = Vector2.UP
                
            # Offset position and project forward
            var offset_dist = sqrt(half_mass) * 45.0
            var twin_pos = cell.global_position + split_dir * offset_dist
            
            # Eject twin forward with speed boost
            var twin_vel = cell.velocity + split_dir * 300.0
            twin.init_cell(half_mass, to_local(twin_pos), twin_vel)
            
            # Recoil original cell backward slightly
            cell.velocity -= split_dir * 80.0
            
            # Apply impact squish to both
            cell.trigger_impact(split_dir, 50.0)
            twin.trigger_impact(-split_dir, 50.0)
            
            new_splits.append(twin)
            
            # Set merge timers (e.g. 15 seconds)
            merge_timers[cell] = 14.0
            merge_timers[twin] = 14.0
            
    for twin in new_splits:
        active_cells.append(twin)
        
    update_total_mass()

func trigger_recombine():
    if is_spore_mode or recombine_absorbing or active_cells.size() < 2:
        return

    focused_cell_index = clamp(focused_cell_index, 0, active_cells.size() - 1)
    var primary = active_cells[focused_cell_index]
    if not is_instance_valid(primary):
        return

    var nearest_cell = null
    var nearest_dist = INF
    for cell in active_cells:
        if cell == primary or not is_instance_valid(cell):
            continue

        var dist = primary.global_position.distance_to(cell.global_position)
        if dist < nearest_dist:
            nearest_dist = dist
            nearest_cell = cell

    if nearest_cell == null:
        return

    merge_timers.erase(primary)
    merge_timers.erase(nearest_cell)
    recombine_primary = primary
    recombine_target = nearest_cell
    update_movement_mode_ui()

func handle_cell_interactions(delta):
    # 1. Repel split cells from each other so they do not overlap completely
    for i in range(active_cells.size()):
        for j in range(i + 1, active_cells.size()):
            var cell_a = active_cells[i]
            var cell_b = active_cells[j]
            
            var diff = cell_b.global_position - cell_a.global_position
            var dist = diff.length()
            var radius_a = sqrt(cell_a.cell_mass) * 38.0
            var radius_b = sqrt(cell_b.cell_mass) * 38.0
            var min_dist = (radius_a + radius_b) * 0.85
            
            if dist < min_dist:
                # Calculate overlap
                var overlap = min_dist - dist
                var push_dir = diff.normalized() if dist > 0.001 else Vector2(1, 0)
                
                # Push cells apart (smoothly)
                var push_factor = 320.0 * (1.0 - (dist / min_dist)) * delta
                cell_a.velocity -= push_dir * push_factor * (cell_b.cell_mass / (cell_a.cell_mass + cell_b.cell_mass))
                cell_b.velocity += push_dir * push_factor * (cell_a.cell_mass / (cell_a.cell_mass + cell_b.cell_mass))
                
                # Directly offset positions slightly to prevent locking
                var pos_offset = push_dir * overlap * 0.15
                cell_a.position -= pos_offset
                cell_b.position += pos_offset

    process_recombine_pair(delta)

    # 2. Update merge timers and merge cells back together
    var cells_to_remove = []
    for cell in active_cells:
        if merge_timers.has(cell):
            merge_timers[cell] -= delta
            if merge_timers[cell] <= 0:
                merge_timers.erase(cell)
                
    # Recombine cells that overlap and are ready to merge
    for i in range(active_cells.size()):
        var cell_a = active_cells[i]
        if merge_timers.has(cell_a):
            continue # Not ready
            
        for j in range(i + 1, active_cells.size()):
            var cell_b = active_cells[j]
            if merge_timers.has(cell_b) or cells_to_remove.has(cell_b):
                continue
            if is_recombine_pair(cell_a, cell_b):
                continue
                
            var dist = cell_a.global_position.distance_to(cell_b.global_position)
            var radius_a = sqrt(cell_a.cell_mass) * 38.0
            var radius_b = sqrt(cell_b.cell_mass) * 38.0
            
            # Merge if centers are very close
            if dist < (radius_a + radius_b) * 0.45:
                # Merge cell B into A
                cell_a.add_mass(cell_b.cell_mass)
                cell_a.trigger_impact(cell_b.global_position - cell_a.global_position, 30.0)
                cell_b.queue_free()
                cells_to_remove.append(cell_b)
                
    for cell in cells_to_remove:
        active_cells.erase(cell)

    if cells_to_remove.size() > 0:
        focused_cell_index = clamp(focused_cell_index, 0, max(active_cells.size() - 1, 0))
        update_movement_mode_ui()
        update_total_mass()

func is_recombine_pair(cell_a, cell_b) -> bool:
    if recombine_primary == null or recombine_target == null:
        return false
    if not is_instance_valid(recombine_primary) or not is_instance_valid(recombine_target):
        return false

    return (cell_a == recombine_primary and cell_b == recombine_target) or (cell_a == recombine_target and cell_b == recombine_primary)

func process_recombine_pair(delta):
    if recombine_primary == null or recombine_target == null or recombine_absorbing:
        return

    if not is_instance_valid(recombine_primary) or not is_instance_valid(recombine_target):
        recombine_primary = null
        recombine_target = null
        update_movement_mode_ui()
        return

    if not active_cells.has(recombine_primary) or not active_cells.has(recombine_target):
        recombine_primary = null
        recombine_target = null
        update_movement_mode_ui()
        return

    var diff = recombine_target.global_position - recombine_primary.global_position
    var dist = diff.length()
    if dist <= 0.001:
        start_recombine_absorb(recombine_primary, recombine_target, Vector2.RIGHT)
        return

    var dir = diff / dist
    var pull_force = min(520.0, 160000.0 / max(dist, 120.0))
    recombine_primary.velocity += dir * pull_force * delta / sqrt(recombine_primary.cell_mass)
    recombine_target.velocity -= dir * pull_force * delta / sqrt(recombine_target.cell_mass)

    var primary_radius = sqrt(recombine_primary.cell_mass) * 38.0
    var target_radius = sqrt(recombine_target.cell_mass) * 38.0
    if dist <= (primary_radius + target_radius) * 0.62:
        start_recombine_absorb(recombine_primary, recombine_target, dir)

func start_recombine_absorb(primary, target, absorb_dir: Vector2):
    if recombine_absorbing:
        return
    if not is_instance_valid(primary) or not is_instance_valid(target):
        recombine_primary = null
        recombine_target = null
        return
    if not active_cells.has(primary) or not active_cells.has(target):
        recombine_primary = null
        recombine_target = null
        return

    recombine_absorbing = true
    recombine_primary = null
    recombine_target = null
    merge_timers.erase(primary)
    merge_timers.erase(target)

    var primary_mass = primary.cell_mass
    var target_mass = target.cell_mass
    var target_velocity = target.velocity
    var target_index = active_cells.find(target)
    active_cells.erase(target)
    focused_cell_index = active_cells.find(primary)
    if focused_cell_index < 0:
        focused_cell_index = clamp(target_index - 1, 0, max(active_cells.size() - 1, 0))

    var duration = 0.58
    var direction = absorb_dir.normalized() if absorb_dir.length() > 0.001 else Vector2.RIGHT
    if primary.has_method("trigger_absorption"):
        primary.trigger_absorption(direction, 1.18, duration)

    target.set_process(false)
    target.set_physics_process(false)
    target.set_deferred("monitoring", false)
    target.set_deferred("monitorable", false)
    target.z_index = primary.z_index + 3
    target.modulate = Color(1.0, 1.0, 1.0, 1.0)
    spawn_absorb_flash((target.global_position + primary.global_position) * 0.5, direction, Color(0.72, 1.0, 0.86, 1.0), 1.25)

    var target_start_scale = target.scale
    var tween = create_tween()
    tween.set_parallel(true)
    tween.tween_property(target, "global_position", primary.global_position + direction * 6.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    tween.tween_property(target, "scale", target_start_scale * 0.08, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
    tween.tween_property(target, "modulate:a", 0.0, duration * 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    await tween.finished

    if is_instance_valid(primary):
        primary.add_mass(target_mass)
        primary.velocity = (primary.velocity * primary_mass + target_velocity * target_mass) / max(primary.cell_mass, 0.001)
        primary.trigger_impact(direction, 48.0)

    if is_instance_valid(target):
        target.queue_free()

    focused_cell_index = clamp(focused_cell_index, 0, max(active_cells.size() - 1, 0))
    recombine_absorbing = false
    update_total_mass()
    update_movement_mode_ui()

func handle_camera(delta):
    # Camera follows center of mass of all active cells
    var center_pos = Vector2.ZERO
    for cell in active_cells:
        center_pos += cell.global_position
    center_pos /= active_cells.size()
    
    # Calculate bounding size of active cells to adjust zoom out
    var max_dist = 0.0
    for cell in active_cells:
        var dist = cell.global_position.distance_to(center_pos) + (sqrt(cell.cell_mass) * 38.0)
        if dist > max_dist:
            max_dist = dist
            
    # Lerp position of camera parent
    camera.global_position = camera.global_position.lerp(center_pos, 5.0 * delta)
    
    # Calculate target zoom based on total mass and cell spread
    var zoom_factor = 1.0 / sqrt(total_mass)
    if max_dist > 250.0:
        # Zoom out further if cells are split and spread out
        zoom_factor *= (250.0 / max_dist)
        
    var target_zoom = clamp(zoom_factor * user_zoom_scale, 0.12, 2.4)
    camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), 3.0 * delta)

func handle_mutations():
    # Trigger mutation selection cards at milestones
    for i in range(mutation_milestones.size()):
        var threshold = mutation_milestones[i]
        if total_mass >= threshold and not triggered_milestones.has(threshold):
            triggered_milestones.append(threshold)
            var main = get_parent()
            if main and main.has_method("open_mutation_ui"):
                main.open_mutation_ui()

func add_player_mass(amount: float, target_cell = null):
    # Add growth to the cell that actually consumed the target.
    if active_cells.size() > 0:
        var main = get_parent()
        var applied_amount = amount
        if main and main.has_method("clamp_player_growth"):
            applied_amount = main.clamp_player_growth(amount)

        var recipient = target_cell
        if recipient == null or not is_instance_valid(recipient) or not active_cells.has(recipient):
            recipient = active_cells[0]
            for cell in active_cells:
                if cell.cell_mass > recipient.cell_mass:
                    recipient = cell

        if applied_amount > 0.0:
            recipient.add_mass(applied_amount)
        update_total_mass()
        score += int(amount * 10)
        
        # UI update
        if main and main.has_method("update_score"):
            main.update_score(score, total_mass)

func update_total_mass():
    var sum = 0.0
    for cell in active_cells:
        sum += cell.cell_mass
    total_mass = sum
    
    # Sync score with mass slightly
    var main = get_parent()
    if main and main.has_method("assert_stage_mass_limit"):
        if not main.assert_stage_mass_limit(total_mass):
            return
    if main and main.has_method("update_score"):
        main.update_score(score, total_mass)
    focused_cell_index = clamp(focused_cell_index, 0, max(active_cells.size() - 1, 0))
    update_movement_mode_ui()

func apply_mutation(mut_id: String):
    if unlocked_mutations.has(mut_id):
        unlocked_mutations[mut_id] = true
        # Apply specific instant updates
        if mut_id == "sticky_glycocalyx":
            # Magnetic attraction setup
            pass

func attach_pet(pet_node):
    # Orbiting pet
    add_child(pet_node)
    pets.append(pet_node)
    pet_node.player = self
    pet_node.position = Vector2(100.0, 0.0) # Start offset

func start_food_absorb(consumer_cell, food):
    if not is_instance_valid(consumer_cell) or not is_instance_valid(food):
        return
    if food.get("is_absorbing") == true:
        return

    var food_type = food.food_type
    var growth = food.value * 0.08
    await play_absorption_effect(consumer_cell, food, 0.42, 0.75, Color(0.72, 1.0, 0.86, 1.0))

    if not is_instance_valid(consumer_cell):
        return

    add_player_mass(growth, consumer_cell)
    if food_type == "symbiont" and pets.size() < 3:
        var pet_scene = load("res://pet.tscn")
        var pet = pet_scene.instantiate()
        attach_pet(pet)

func start_enemy_absorb(consumer_cell, enemy):
    if not is_instance_valid(consumer_cell) or not is_instance_valid(enemy):
        return
    if enemy.get("is_absorbing") == true:
        return

    var growth = enemy.cell_mass * 0.4
    await play_absorption_effect(consumer_cell, enemy, 0.68, 1.15, Color(0.8, 1.0, 0.95, 1.0))

    if not is_instance_valid(consumer_cell):
        return

    add_player_mass(growth, consumer_cell)

func handle_cancer_contact(touched_cell, cancer):
    if not is_instance_valid(touched_cell) or not active_cells.has(touched_cell):
        return
    if not is_instance_valid(cancer):
        return

    var main = get_parent()
    if active_cells.size() <= 1:
        active_cells.erase(touched_cell)
        merge_timers.erase(touched_cell)
        touched_cell.queue_free()
        update_total_mass()
        if main and main.has_method("game_over"):
            main.game_over("단일 세포가 암세포와 접촉해 실험이 종료되었습니다.")
        return

    var infection_chance = 0.32
    if main and main.has_method("get_cancer_infection_chance"):
        infection_chance = main.get_cancer_infection_chance()

    var cell_pos = touched_cell.global_position
    var cell_mass_before = touched_cell.cell_mass
    var cell_velocity = touched_cell.velocity
    active_cells.erase(touched_cell)
    merge_timers.erase(touched_cell)
    if recombine_primary == touched_cell or recombine_target == touched_cell:
        recombine_primary = null
        recombine_target = null

    if randf() < infection_chance:
        if main and main.has_method("spawn_cancer_from_cell"):
            main.spawn_cancer_from_cell(cell_pos, cell_mass_before * 0.9, cell_velocity)
    else:
        cancer.cell_mass += cell_mass_before * 0.18
        cancer.update_scale()
        cancer.trigger_impact(cell_pos - cancer.global_position, 48.0)

    touched_cell.queue_free()
    focused_cell_index = clamp(focused_cell_index, 0, max(active_cells.size() - 1, 0))
    update_total_mass()

func play_absorption_effect(consumer_cell, target, duration: float, strength: float, flash_color: Color):
    if not is_instance_valid(consumer_cell) or not is_instance_valid(target):
        return

    target.set("is_absorbing", true)
    target.set_process(false)
    target.set_physics_process(false)
    target.set_deferred("monitoring", false)
    target.set_deferred("monitorable", false)

    var direction = target.global_position - consumer_cell.global_position
    var absorb_dir = direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT
    if consumer_cell.has_method("trigger_absorption"):
        consumer_cell.trigger_absorption(absorb_dir, strength, duration)

    spawn_absorb_flash((target.global_position + consumer_cell.global_position) * 0.5, absorb_dir, flash_color, strength)

    target.z_index = consumer_cell.z_index + 2
    target.modulate = Color(1.0, 1.0, 1.0, 1.0)
    var start_scale = target.scale
    var tween = create_tween()
    tween.set_parallel(true)
    tween.tween_property(target, "global_position", consumer_cell.global_position + absorb_dir * 8.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    tween.tween_property(target, "scale", start_scale * 0.12, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
    tween.tween_property(target, "modulate:a", 0.0, duration * 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    await tween.finished

    if is_instance_valid(consumer_cell):
        consumer_cell.trigger_impact(absorb_dir, 24.0 + strength * 18.0)
    if is_instance_valid(target):
        target.queue_free()

func spawn_absorb_flash(effect_pos: Vector2, direction: Vector2, flash_color: Color, strength: float):
    var flash = ABSORB_FLASH_SCRIPT.new()
    flash.global_position = effect_pos
    flash.direction = direction
    flash.flash_color = flash_color
    flash.strength = strength
    get_parent().add_child(flash)

func get_movement_input_for_cell(cell, cell_index: int) -> Vector2:
    if is_spore_mode:
        return Vector2.ZERO
    if movement_mode == MOVEMENT_MODE_AUTO:
        return calculate_auto_movement(cell)
    if active_cells.size() == 1 or cell_index == focused_cell_index:
        return get_manual_movement_input()
    return Vector2.ZERO

func get_movement_input() -> Vector2:
    if active_cells.size() == 0:
        return Vector2.ZERO
    return get_movement_input_for_cell(active_cells[focused_cell_index], focused_cell_index)
    return get_manual_movement_input()

func get_manual_movement_input() -> Vector2:
    var input_dir = Vector2.ZERO
    if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
    if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
    if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
    if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1

    if Input.is_physical_key_pressed(KEY_UP): input_dir.y -= 1
    if Input.is_physical_key_pressed(KEY_DOWN): input_dir.y += 1
    if Input.is_physical_key_pressed(KEY_LEFT): input_dir.x -= 1
    if Input.is_physical_key_pressed(KEY_RIGHT): input_dir.x += 1

    return input_dir.normalized() if input_dir != Vector2.ZERO else Vector2.ZERO

func calculate_auto_movement(target_cell = null) -> Vector2:
    if active_cells.size() == 0:
        return Vector2.ZERO

    if target_cell == null or not is_instance_valid(target_cell):
        target_cell = get_largest_cell()

    var center = target_cell.global_position
    var desired = Vector2.ZERO
    desired += score_food_instinct(center)
    desired += score_enemy_instinct(center, target_cell.cell_mass)
    desired += score_salt_instinct(center)
    desired += score_vortex_instinct(center)

    if desired.length() < 0.001:
        var drift = target_cell.velocity.normalized()
        return drift if drift != Vector2.ZERO else Vector2.RIGHT
    return desired.normalized()

func score_food_instinct(center: Vector2) -> Vector2:
    var desired = Vector2.ZERO
    var foods = get_tree().get_nodes_in_group("food")
    for food in foods:
        if food.is_queued_for_deletion() or food.get("is_absorbing") == true:
            continue

        var diff = food.global_position - center
        var dist = diff.length()
        if dist <= 0.001 or dist > AUTO_FOOD_SCAN_RADIUS:
            continue

        var proximity = 1.0 - (dist / AUTO_FOOD_SCAN_RADIUS)
        var food_value = food.get("value")
        if typeof(food_value) != TYPE_FLOAT and typeof(food_value) != TYPE_INT:
            food_value = 1.0
        desired += diff.normalized() * food_value * proximity * proximity * 2.0
    return desired

func score_enemy_instinct(center: Vector2, largest_mass: float) -> Vector2:
    var desired = Vector2.ZERO
    var enemies = get_tree().get_nodes_in_group("enemies")
    for enemy in enemies:
        if enemy.is_queued_for_deletion():
            continue

        var diff = enemy.global_position - center
        var dist = diff.length()
        if dist <= 0.001 or dist > AUTO_ENEMY_SCAN_RADIUS:
            continue

        var enemy_mass = enemy.cell_mass
        var proximity = 1.0 - (dist / AUTO_ENEMY_SCAN_RADIUS)
        var dir = diff.normalized()

        if enemy.get("enemy_type") == 2:
            desired -= dir * (6.0 + get_parent().get("current_stage") * 0.45) * proximity * proximity
        elif largest_mass > enemy_mass * 1.15:
            var prey_value = clamp(enemy_mass / max(largest_mass, 0.1), 0.2, 2.0)
            desired += dir * prey_value * proximity * 1.6
        elif enemy_mass > largest_mass * 0.95:
            var danger = clamp(enemy_mass / max(largest_mass, 0.1), 0.8, 4.0)
            desired -= dir * danger * proximity * proximity * 4.2
    return desired

func score_salt_instinct(center: Vector2) -> Vector2:
    if unlocked_mutations["rigid_cell_wall"]:
        return Vector2.ZERO

    var main = get_parent()
    if not main:
        return Vector2.ZERO

    var salt_zones_data = main.get("salt_zones")
    if typeof(salt_zones_data) != TYPE_ARRAY:
        return Vector2.ZERO

    var desired = Vector2.ZERO
    for zone in salt_zones_data:
        var zone_pos = zone["pos"]
        var radius = zone["radius"]
        var diff = center - zone_pos
        var dist = diff.length()
        var outer_radius = radius + AUTO_SALT_MARGIN
        if dist > outer_radius:
            continue

        var away = diff.normalized() if dist > 0.001 else Vector2.RIGHT
        var risk = 1.0 - (dist / outer_radius)
        desired += away * risk * risk * 5.0
    return desired

func score_vortex_instinct(center: Vector2) -> Vector2:
    var desired = Vector2.ZERO
    var vortices = get_tree().get_nodes_in_group("vortices")
    for vortex in vortices:
        var radius = vortex.get("radius")
        if typeof(radius) != TYPE_FLOAT and typeof(radius) != TYPE_INT:
            radius = 250.0

        var diff = center - vortex.global_position
        var dist = diff.length()
        var outer_radius = radius + AUTO_VORTEX_MARGIN
        if dist <= 0.001 or dist > outer_radius:
            continue

        var away = diff.normalized()
        var tangent = Vector2(-away.y, away.x)
        var force = 1.0 - (dist / outer_radius)
        if total_mass >= 2.4:
            desired += tangent * force * 1.4 + away * force * 0.6
        else:
            desired += away * force * 2.4
    return desired

func get_swarm_center() -> Vector2:
    if active_cells.size() == 0:
        return global_position

    var center = Vector2.ZERO
    for cell in active_cells:
        center += cell.global_position
    return center / active_cells.size()

func get_largest_cell():
    if active_cells.size() == 0:
        return null

    var largest_cell = active_cells[0]
    for cell in active_cells:
        if cell.cell_mass > largest_cell.cell_mass:
            largest_cell = cell
    return largest_cell

func toggle_movement_mode():
    movement_mode = MOVEMENT_MODE_AUTO if movement_mode == MOVEMENT_MODE_MANUAL else MOVEMENT_MODE_MANUAL
    update_movement_mode_ui()

func update_movement_mode_ui():
    var main = get_parent()
    if main and main.has_method("update_movement_mode"):
        var mode_name = "Auto" if movement_mode == MOVEMENT_MODE_AUTO else "Manual"
        var intent_name = auto_instinct.capitalize()
        if recombine_primary != null and recombine_target != null:
            intent_name += " / Recombine"
        main.update_movement_mode(mode_name, intent_name, focused_cell_index + 1, active_cells.size())

func adjust_user_zoom(factor: float):
    user_zoom_scale = clamp(user_zoom_scale * factor, USER_ZOOM_MIN, USER_ZOOM_MAX)

func cycle_focused_cell():
    if active_cells.size() == 0:
        return
    focused_cell_index = (focused_cell_index + 1) % active_cells.size()
    update_movement_mode_ui()

func select_focused_cell_at(world_pos: Vector2):
    if active_cells.size() == 0:
        return

    var best_index = -1
    var best_dist = INF
    for i in range(active_cells.size()):
        var cell = active_cells[i]
        var dist = cell.global_position.distance_to(world_pos)
        var pick_radius = max(sqrt(cell.cell_mass) * 52.0, 44.0)
        if dist <= pick_radius and dist < best_dist:
            best_dist = dist
            best_index = i

    if best_index >= 0:
        focused_cell_index = best_index
        update_movement_mode_ui()

func _draw():
    if active_cells.size() == 0:
        return
    if recombine_primary != null and recombine_target != null and is_instance_valid(recombine_primary) and is_instance_valid(recombine_target):
        draw_line(recombine_primary.position, recombine_target.position, Color(0.49, 1.0, 0.82, 0.62), 4.0)

    focused_cell_index = clamp(focused_cell_index, 0, max(active_cells.size() - 1, 0))
    var cell = active_cells[focused_cell_index]
    if not is_instance_valid(cell):
        return

    var ring_color = Color(1.0, 0.68, 0.12, 0.95) if movement_mode == MOVEMENT_MODE_AUTO else Color(0.25, 0.8, 1.0, 0.95)
    var radius = sqrt(cell.cell_mass) * 48.0
    draw_arc(cell.position, radius, 0.0, TAU, 96, ring_color, 3.0)
