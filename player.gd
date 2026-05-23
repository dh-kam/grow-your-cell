extends Node2D

const CELL_SCENE = preload("res://player_cell.tscn")
const PROJECTILE_SCENE = preload("res://acid_projectile.tscn")

# Baseline movement constants (applied to sub-cells)
const ACCELERATION = 480.0
const DEFAULT_FRICTION = 0.6
const CILIA_BRAKE_FRICTION = 8.0
const MAX_SPEED = 400.0

# Game system state
var active_cells = []
var merge_timers = {} # maps cell -> float (seconds remaining to merge)
var score = 0
var total_mass = 1.0

# Skill states
var is_spore_mode = false
var is_cilia_braking = false

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

func _process(delta):
    if active_cells.size() == 0:
        return
        
    handle_skills(delta)
    handle_movement(delta)
    handle_cell_interactions(delta)
    handle_camera(delta)
    handle_mutations()

func handle_movement(delta):
    # Keyboard movement acceleration direction
    var input_dir = Vector2.ZERO
    if not is_spore_mode:
        if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
        if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
        if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
        if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
        
        if Input.is_physical_key_pressed(KEY_UP): input_dir.y -= 1
        if Input.is_physical_key_pressed(KEY_DOWN): input_dir.y += 1
        if Input.is_physical_key_pressed(KEY_LEFT): input_dir.x -= 1
        if Input.is_physical_key_pressed(KEY_RIGHT): input_dir.x += 1

    if input_dir != Vector2.ZERO:
        input_dir = input_dir.normalized()
        
    var friction = CILIA_BRAKE_FRICTION if is_cilia_braking else DEFAULT_FRICTION
    if unlocked_mutations["rigid_cell_wall"] and not is_cilia_braking:
        friction *= 0.6 # Lower drag for rigid walls
        
    # Apply movement forces to each active player cell piece
    for cell in active_cells:
        if is_spore_mode:
            # Force stop
            cell.velocity = cell.velocity.move_toward(Vector2.ZERO, 500.0 * delta)
            continue
            
        # Accelerate based on individual mass
        var cell_accel = ACCELERATION / sqrt(cell.cell_mass)
        cell.velocity += input_dir * cell_accel * delta
        
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
        
    # Find the largest cell to fire from
    var largest_cell = active_cells[0]
    for cell in active_cells:
        if cell.cell_mass > largest_cell.cell_mass:
            largest_cell = cell
            
    # Need minimum mass to fire
    if largest_cell.cell_mass < 0.25:
        return
        
    # Cost: 5% mass of largest cell
    var cost = largest_cell.cell_mass * 0.05
    largest_cell.add_mass(-cost)
    update_total_mass()
    
    # Calculate fire direction towards mouse cursor
    var target_pos = get_global_mouse_position()
    var fire_dir = (target_pos - largest_cell.global_position).normalized()
    if fire_dir == Vector2.ZERO:
        fire_dir = Vector2.RIGHT
        
    var projectile = PROJECTILE_SCENE.instantiate()
    projectile.global_position = largest_cell.global_position + fire_dir * (largest_cell.scale.x * 40.0)
    projectile.direction = fire_dir
    projectile.creator = self
    projectile.scale = Vector2(1.0, 1.0) * (1.5 if unlocked_mutations["acid_projectile_boost"] else 1.0)
    get_parent().add_child(projectile)
    
    # Backwards kickback force on firing cell
    largest_cell.velocity -= fire_dir * 180.0
    largest_cell.trigger_impact(fire_dir, 35.0)

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
            get_parent().add_child(twin)
            
            # Determine split heading direction
            var split_dir = cell.velocity.normalized()
            if split_dir == Vector2.ZERO:
                split_dir = Vector2.UP
                
            # Offset position and project forward
            var offset_dist = sqrt(half_mass) * 45.0
            var twin_pos = cell.global_position + split_dir * offset_dist
            
            # Eject twin forward with speed boost
            var twin_vel = cell.velocity + split_dir * 300.0
            twin.init_cell(half_mass, twin_pos, twin_vel)
            
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
        update_total_mass()

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
        
    var target_zoom = clamp(zoom_factor, 0.22, 1.2)
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

func add_player_mass(amount: float):
    # Distribute mass among cells, or add to largest
    if active_cells.size() > 0:
        # Add to the cell that triggered overlap (represented by adding to first/largest for simplicity)
        active_cells[0].add_mass(amount)
        update_total_mass()
        score += int(amount * 10)
        
        # UI update
        var main = get_parent()
        if main and main.has_method("update_score"):
            main.update_score(score, total_mass)

func update_total_mass():
    var sum = 0.0
    for cell in active_cells:
        sum += cell.cell_mass
    total_mass = sum
    
    # Sync score with mass slightly
    var main = get_parent()
    if main and main.has_method("update_score"):
        main.update_score(score, total_mass)

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
