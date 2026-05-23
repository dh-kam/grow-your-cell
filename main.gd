extends Node2D

const WORLD_LIMIT = 2400
const MAX_FOOD = 220
const MAX_ENEMIES = 10
const STAGE_MASS_EPSILON = 0.001

var food_scene = preload("res://food.tscn")
var enemy_scene = preload("res://enemy.tscn")
var vortex_scene = preload("res://vortex.tscn")

# Salt zones coordinates and radii
var salt_zones = [
    {"pos": Vector2(-900, -800), "radius": 400.0},
    {"pos": Vector2(900, 800), "radius": 400.0}
]

# UI elements
@onready var player = $Player
@onready var score_label = $CanvasLayer/Control/MarginContainer/VBoxContainer/ScoreLabel
@onready var size_label = $CanvasLayer/Control/MarginContainer/VBoxContainer/SizeLabel
@onready var move_mode_label = $CanvasLayer/Control/MarginContainer/VBoxContainer/MoveModeLabel
@onready var instructions_label = $CanvasLayer/Control/MarginContainer/VBoxContainer/Instructions
@onready var mutation_ui = $CanvasLayer/Control/MutationUI
@onready var card_container = $CanvasLayer/Control/MutationUI/CenterContainer/VBoxContainer/CardContainer

# Available mutations pool
var mutation_pool = [
    {"id": "mitochondria_efficiency", "title": "에너지 효율 (미토콘드리아)", "desc": "Shift 돌진 시 소모되는 세포 질량 절반 감소"},
    {"id": "sticky_glycocalyx", "title": "점착성 섬모 (당외피)", "desc": "주변 먹이를 자성으로 끌어당기는 범위 80% 증가"},
    {"id": "rigid_cell_wall", "title": "단단한 세포벽", "desc": "최대 이동 속도 30% 증가 및 삼투압 위험지대 탈수 면역"},
    {"id": "acid_projectile_boost", "title": "강력한 리소좀", "desc": "Q 산성 포탄 크기 50% 증가 및 타격 효과 증대"}
]
var chosen_options = []
var help_visible = true
var current_stage = 1
var stage_tokens = 0
var stage_clear_locked = false
var cancer_spawn_timer = 9.0
var game_over_active = false

func _ready():
    randomize()
    
    # Spawn vortices
    for i in range(3):
        var v = vortex_scene.instantiate()
        v.position = Vector2(randf_range(-1400, 1400), randf_range(-1400, 1400))
        add_child(v)
        
    # Spawn initial food & enemies
    for i in range(MAX_FOOD):
        spawn_food()
    for i in range(MAX_ENEMIES):
        spawn_enemy()
        
    update_score(0, 1.0)
    if mutation_ui:
        mutation_ui.visible = false
    get_tree().create_timer(5.0).timeout.connect(_hide_help_panel)

func _input(event):
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_H or event.keycode == KEY_H or event.keycode == KEY_F1:
            get_viewport().set_input_as_handled()
            toggle_help_panel()

func _process(delta):
    if game_over_active:
        return

    # Maintain food population
    var current_food = get_tree().get_nodes_in_group("food").size()
    if current_food < MAX_FOOD:
        spawn_food()
        
    # Maintain enemy population
    var current_enemies = get_tree().get_nodes_in_group("enemies").size()
    if current_enemies < MAX_ENEMIES:
        spawn_enemy()
        
    handle_cancer_spawns(delta)
    handle_salt_zones(delta)
    check_stage_clear()

func spawn_food():
    var food = food_scene.instantiate()
    # Higher probability to spawn inside salt zones for high-value food
    if randf() < 0.35:
        var zone = salt_zones[randi() % salt_zones.size()]
        var angle = randf() * TAU
        var dist = randf() * zone["radius"]
        food.position = zone["pos"] + Vector2(cos(angle), sin(angle)) * dist
    else:
        var px = randf_range(-WORLD_LIMIT + 80, WORLD_LIMIT - 80)
        var py = randf_range(-WORLD_LIMIT + 80, WORLD_LIMIT - 80)
        food.position = Vector2(px, py)
    add_child(food)

func spawn_enemy(as_cancer := false, spawn_pos = null, spawn_mass := 0.0):
    var enemy = enemy_scene.instantiate()
    enemy.force_cancer = as_cancer
    if as_cancer and spawn_mass > 0.0:
        enemy.cell_mass = spawn_mass

    var px = randf_range(-WORLD_LIMIT + 150, WORLD_LIMIT - 150)
    var py = randf_range(-WORLD_LIMIT + 150, WORLD_LIMIT - 150)
    if spawn_pos != null:
        px = spawn_pos.x
        py = spawn_pos.y

    # Spawn away from player center
    if spawn_pos == null and player and Vector2(px, py).distance_to(player.camera.global_position) < 800.0:
        px += 900.0 * (1.0 if px > 0 else -1.0)
    enemy.position = Vector2(px, py)
    add_child(enemy)
    return enemy

func handle_cancer_spawns(delta):
    cancer_spawn_timer -= delta
    if cancer_spawn_timer > 0.0:
        return

    var cancer_count = 0
    for enemy in get_tree().get_nodes_in_group("enemies"):
        if enemy.get("enemy_type") == 2:
            cancer_count += 1

    var max_cancer = min(8, 1 + int(current_stage / 2))
    if cancer_count < max_cancer and randf() < min(0.86, 0.22 + current_stage * 0.07):
        spawn_enemy(true, null, randf_range(0.8, 1.25) + current_stage * 0.16)

    cancer_spawn_timer = max(2.5, 12.0 - current_stage * 0.75) + randf_range(0.0, 4.0)

func get_stage_target_mass() -> float:
    return 1.75 + float(current_stage - 1) * 1.05 + pow(float(current_stage - 1), 1.25) * 0.38

func clamp_player_growth(amount: float) -> float:
    if not player or amount <= 0.0:
        return 0.0
    var room = max(get_stage_target_mass() - player.total_mass, 0.0)
    return min(amount, room)

func assert_stage_mass_limit(size: float = -1.0) -> bool:
    if game_over_active:
        return false

    var checked_size = size
    if checked_size < 0.0 and player:
        checked_size = player.total_mass

    var limit = get_stage_target_mass()
    if checked_size > limit + STAGE_MASS_EPSILON:
        game_over("세포가 Stage %d 안전 한계 %.2fx를 넘어 파열되었습니다." % [current_stage, limit])
        return false
    return true

func get_cancer_infection_chance() -> float:
    return clamp(0.24 + current_stage * 0.055, 0.12, 0.84)

func handle_salt_zones(delta):
    # Apply osmotic dehydration to player cells inside salt zones
    if not player or player.unlocked_mutations["rigid_cell_wall"]:
        return
        
    for cell in player.active_cells:
        for zone in salt_zones:
            var dist = cell.global_position.distance_to(zone["pos"])
            if dist < zone["radius"]:
                # Dehydrate: lose 6% of mass per second
                var drain = cell.cell_mass * 0.06 * delta
                if cell.cell_mass > 0.15:
                    cell.add_mass(-drain)
                    
    player.update_total_mass()

func update_score(score: int, size: float):
    if score_label:
        score_label.text = "Score: %d | Stage: %d | Tokens: %d" % [score, current_stage, stage_tokens]
    if size_label:
        size_label.text = "Size: %.2fx / Limit %.2fx" % [size, get_stage_target_mass()]

func check_stage_clear():
    if stage_clear_locked or not player:
        return
    if not assert_stage_mass_limit(player.total_mass):
        return
    if player.total_mass < get_stage_target_mass() - STAGE_MASS_EPSILON:
        return

    stage_clear_locked = true
    stage_tokens += max(1, current_stage)
    current_stage += 1
    cancer_spawn_timer = max(2.5, 12.0 - current_stage * 0.75)
    stage_clear_locked = false
    update_score(player.score, player.total_mass)

func spawn_cancer_from_cell(cell_pos: Vector2, cell_mass: float, cell_velocity := Vector2.ZERO):
    var spawned = spawn_enemy(true, cell_pos, max(0.65, cell_mass))
    if spawned and spawned.get("enemy_type") == 2:
        spawned.velocity = cell_velocity * 0.35

func game_over(reason: String):
    game_over_active = true
    if score_label:
        score_label.text = "GAME OVER | Stage: %d | Tokens: %d" % [current_stage, stage_tokens]
    if size_label:
        size_label.text = reason
    if player:
        player.set_process(false)

func update_movement_mode(mode_name: String, intent_name: String, focus_index: int = 1, focus_total: int = 1):
    if move_mode_label:
        move_mode_label.text = "Mode: %s\nInstinct: %s\nFocus: %d / %d" % [mode_name, intent_name, focus_index, focus_total]

func toggle_help_panel():
    help_visible = not help_visible
    if instructions_label:
        instructions_label.visible = help_visible

func _hide_help_panel():
    help_visible = false
    if instructions_label:
        instructions_label.visible = false

func open_mutation_ui():
    # Show mutation UI selection, pause game
    get_tree().paused = true
    mutation_ui.visible = true
    
    # Select 3 random mutations
    var available = []
    for mut in mutation_pool:
        if player and not player.unlocked_mutations[mut["id"]]:
            available.append(mut)
            
    # Fallback if all mutations unlocked
    if available.size() == 0:
        close_mutation_ui()
        return
        
    available.shuffle()
    chosen_options = []
    for i in range(min(3, available.size())):
        chosen_options.append(available[i])
        
    # Build selection buttons/cards in UI
    # Clear old children first
    for child in card_container.get_children():
        child.queue_free()
        
    for i in range(chosen_options.size()):
        var opt = chosen_options[i]
        
        # Create a beautiful Button for each mutation card
        var btn = Button.new()
        btn.text = "%s\n- %s" % [opt["title"], opt["desc"]]
        btn.custom_minimum_size = Vector2(300, 80)
        btn.pressed.connect(Callable(self, "_on_mutation_selected").bind(opt["id"]))
        card_container.add_child(btn)

func _on_mutation_selected(mut_id: String):
    # Apply mutation to player
    if player:
        player.apply_mutation(mut_id)
    close_mutation_ui()

func close_mutation_ui():
    mutation_ui.visible = false
    get_tree().paused = false
