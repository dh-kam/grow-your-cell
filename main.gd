extends Node2D

const WORLD_LIMIT = 2400
const MAX_FOOD = 220
const MAX_ENEMIES = 10

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

func _process(delta):
    # Maintain food population
    var current_food = get_tree().get_nodes_in_group("food").size()
    if current_food < MAX_FOOD:
        spawn_food()
        
    # Maintain enemy population
    var current_enemies = get_tree().get_nodes_in_group("enemies").size()
    if current_enemies < MAX_ENEMIES:
        spawn_enemy()
        
    handle_salt_zones(delta)

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

func spawn_enemy():
    var enemy = enemy_scene.instantiate()
    var px = randf_range(-WORLD_LIMIT + 150, WORLD_LIMIT - 150)
    var py = randf_range(-WORLD_LIMIT + 150, WORLD_LIMIT - 150)
    # Spawn away from player center
    if player and Vector2(px, py).distance_to(player.camera.global_position) < 800.0:
        px += 900.0 * (1.0 if px > 0 else -1.0)
    enemy.position = Vector2(px, py)
    add_child(enemy)

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
        score_label.text = "Score: %d" % score
    if size_label:
        size_label.text = "Size: %.2fx" % size

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
