extends CharacterBody2D

# Stats (Upgradable!)
var speed: float = 300.0
var jump_speed: float = 400.0
var climb_speed: float = 150.0
var gravity: float = 980.0
var mine_time: float = 2.0 # Default for Starter Pick (Slowed down)
var max_battery: float = 100.0
var current_battery: float = 100.0
var max_cargo: int = 10
var current_cargo: int = 0

# Mining SFX (assign in Inspector, or place `anvil.mp3` at res://anvil.mp3)
const DEFAULT_MINING_SFX_PATH: String = "res://anvil.mp3"
@export var mining_sfx: AudioStream
var mining_sfx_player: AudioStreamPlayer

# Upgrade tracking
var pickaxe_level: int = 0
const PICKAXE_UPGRADES = [
	{"name": "Starter Pick", "price": 0,     "mine_time": 2.0,  "luck": 1.0, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Stone Pick",   "price": 500,   "mine_time": 1.0,  "luck": 1.1, "color": Color(0.75, 0.7, 0.65)},
	{"name": "Copper Pick",  "price": 1000,  "mine_time": 0.9,  "luck": 1.2, "color": Color(0.9, 0.5, 0.15)},
	{"name": "Silver Pick",  "price": 5000,  "mine_time": 0.5,  "luck": 1.4, "color": Color(0.8, 0.85, 0.95)},
	{"name": "Gold Pick",    "price": 50000, "mine_time": 0.25, "luck": 1.8, "color": Color(1.0, 0.85, 0.1)}
]

@onready var mining_timer: Timer = $MiningTimer
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
var tilemap: TileMapLayer
var money_label: Label
var oxygen_bar: ProgressBar
var money: int = 0
var is_mining: bool = false
var target_tile_coords: Vector2i
var spawn_position: Vector2

# Track which direction the player is facing so we know which block to target
var facing_dir: int = 1  # 1 = right, -1 = left
var is_walking: bool = false
var is_wall_climbing: bool = false

# Highlight state — updated every frame based on mouse position
var highlighted_tile: Vector2i
var highlight_valid: bool = false
# Tile size in world space: tileset is 128px, TileMapLayer scale is 0.5
const TILE_WORLD_SIZE = 64.0

# Ore table: [name, 1-in-N drop chance, value per ore, display color]
const ORE_TABLE = [
	["Stone",  1.8,  2,   Color(0.75, 0.70, 0.65)],
	["Copper", 9, 15,  Color(0.90, 0.50, 0.15)],
	["Silver", 22, 50,  Color(0.80, 0.85, 0.95)],
	["Gold",   45, 200, Color(1.00, 0.85, 0.10)],
]

# Per-ore inventory counts
var ore_counts: Dictionary = {}
# HUD label references keyed by ore name
var ore_labels: Dictionary = {}

func _is_tile_unbreakable(tile_coords: Vector2i) -> bool:
	if tilemap == null:
		return false
	if not tilemap.has_meta("unbreakable_tiles"):
		return false
	var data = tilemap.get_meta("unbreakable_tiles")
	return data is Dictionary and (data as Dictionary).has(tile_coords)

func _ready():
	spawn_position = global_position
	# Find TileMapLayer more robustly
	var main = get_parent()
	tilemap = main.get_node_or_null("Dirt") as TileMapLayer
	
	# Find HUD nodes more robustly
	var hud = main.get_node_or_null("HUD")
	if hud:
		money_label = hud.get_node_or_null("MoneyLabel") as Label
		if money_label:
			money_label.text = "$0"
		
		oxygen_bar = hud.get_node_or_null("ProgressBar") as ProgressBar
		if oxygen_bar:
			oxygen_bar.visible = true
			oxygen_bar.position = Vector2(980, 50)
			oxygen_bar.size = Vector2(250, 30)
			oxygen_bar.max_value = max_battery
			oxygen_bar.value = current_battery
			
			var ox_label = oxygen_bar.get_node_or_null("Label") as Label
			if ox_label:
				ox_label.text = "Oxygen"
				ox_label.position = Vector2(5, -25)
	
	# Mining sound player
	mining_sfx_player = AudioStreamPlayer.new()
	add_child(mining_sfx_player)
	if mining_sfx == null and ResourceLoader.exists(DEFAULT_MINING_SFX_PATH):
		mining_sfx = load(DEFAULT_MINING_SFX_PATH) as AudioStream
	if mining_sfx != null:
		mining_sfx_player.stream = mining_sfx

	mining_timer.timeout.connect(finish_mining)
	add_to_group("player")
	z_index = 1

	# Initialise ore counts and build HUD labels
	if hud:
		var y: float = 68.0
		for ore in ORE_TABLE:
			var nm: String = ore[0]
			ore_counts[nm] = 0

			var lbl := Label.new()
			lbl.text = "%s: 0" % nm
			lbl.modulate = ore[3] as Color
			lbl.add_theme_font_size_override("font_size", 20)
			lbl.position = Vector2(20.0, y)
			hud.add_child(lbl)
			ore_labels[nm] = lbl
			y += 26.0

func _physics_process(delta):
	if not tilemap: return

	# 1. Drain Battery (Oxygen)
	var pos_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	var tile_below = pos_tile + Vector2i(0, 1)
	var on_grass = tilemap.get_cell_source_id(tile_below) == 1
	var tile_at_feet = tilemap.get_cell_source_id(pos_tile) == 1
	
	if (not on_grass and not tile_at_feet) and pos_tile.y > 0:
		current_battery -= delta * 2.0
	else:
		var refill_rate = 60.0 if (on_grass or tile_at_feet) else 15.0
		current_battery = min(max_battery, current_battery + delta * refill_rate)
		
	if oxygen_bar:
		oxygen_bar.value = current_battery

	if current_battery <= 0:
		die_and_respawn()

	# 2. Horizontal input
	var h = Input.get_axis("Left", "Right")
	is_walking = h != 0
	if h != 0:
		facing_dir = sign(h)

	# 3. Wall climbing
	var wall_normal = get_wall_normal()
	is_wall_climbing = (
		is_on_wall()
		and h != 0
		and wall_normal != Vector2.ZERO
		and sign(h) == -sign(wall_normal.x)
	)

	# 4. Gravity
	if not is_on_floor() and not is_wall_climbing:
		velocity.y += gravity * delta

	# 5. Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = -jump_speed

	# 6. Velocity
	velocity.x = h * speed
	if is_wall_climbing:
		velocity.y = -climb_speed

	move_and_slide()

	if is_mining and is_on_floor():
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		var adjacent_tiles = [
			player_tile + Vector2i(1, 0),
			player_tile + Vector2i(-1, 0),
			player_tile + Vector2i(0, 1),
			player_tile + Vector2i(0, -1),
		]
		if not (target_tile_coords in adjacent_tiles):
			cancel_mining()

	_update_highlight()
	_update_animation()
	queue_redraw()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if highlight_valid and not is_mining:
			start_mining(highlighted_tile)
	else:
		if is_mining:
			cancel_mining()

func _update_highlight():
	if is_mining or not tilemap:
		return

	var mouse_world_pos = get_global_mouse_position()
	var mouse_tile = tilemap.local_to_map(tilemap.to_local(mouse_world_pos))
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))

	var adjacent_tiles = [
		player_tile + Vector2i(1, 0),
		player_tile + Vector2i(-1, 0),
		player_tile + Vector2i(0, 1),
		player_tile + Vector2i(0, -1),
	]

	if mouse_tile in adjacent_tiles and tilemap.get_cell_source_id(mouse_tile) != -1 and not _is_tile_unbreakable(mouse_tile):
		highlighted_tile = mouse_tile
		highlight_valid = true
	else:
		highlight_valid = false

func _update_animation():
	var target_anim: StringName
	if is_mining:
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		target_anim = &"mine_down" if target_tile_coords.y > player_tile.y else &"mine_right"
	elif is_wall_climbing:
		target_anim = &"climb"
	elif is_walking:
		target_anim = &"walk" # In SF_miner, walk and idle were swapped.
	else:
		target_anim = &"idle"

	if is_mining:
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		anim_sprite.flip_h = target_tile_coords.x < player_tile.x
	elif is_wall_climbing:
		var wall_normal = get_wall_normal()
		anim_sprite.flip_h = wall_normal.x > 0 
	else:
		anim_sprite.flip_h = facing_dir == -1

	if anim_sprite.animation != target_anim:
		anim_sprite.play(target_anim)

func _draw():
	if not tilemap: return
	
	if highlight_valid and not is_mining:
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(highlighted_tile))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0
		var rect = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		draw_rect(rect, Color(1.0, 1.0, 0.0, 0.45), true)
		draw_rect(rect, Color(1.0, 0.85, 0.0, 1.0), false, 3.0)

	if is_mining:
		var progress = 1.0 - (mining_timer.time_left / mine_time)
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(target_tile_coords))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0

		var rect = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		draw_rect(rect, Color(1.0, 0.5, 0.0, 0.3), true)
		draw_rect(rect, Color(1.0, 0.5, 0.0, 0.9), false, 2.0)

		var bar_w = TILE_WORLD_SIZE
		var bar_h = 6.0
		var bar_pos = tile_center_local - Vector2(bar_w / 2.0, half + bar_h + 4.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.15, 0.15, 0.15, 0.85), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * progress, bar_h)), Color(0.2, 0.85, 0.2, 0.9), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 1.0, 1.0, 0.5), false, 1.0)

func start_mining(tile_coords: Vector2i):
	if _is_tile_unbreakable(tile_coords):
		return
	is_mining = true
	target_tile_coords = tile_coords
	_play_mining_sfx()
	mining_timer.start(mine_time)

func _play_mining_sfx() -> void:
	if mining_sfx_player == null:
		return
	if mining_sfx_player.stream == null and mining_sfx != null:
		mining_sfx_player.stream = mining_sfx
	if mining_sfx_player.stream == null:
		return
	mining_sfx_player.stop()
	mining_sfx_player.play()

func cancel_mining():
	mining_timer.stop()
	is_mining = false

func die_and_respawn():
	anim_sprite.play("death")
	if is_mining:
		cancel_mining()

	current_battery = max_battery
	current_cargo = 0
	for ore in ORE_TABLE:
		var nm: String = ore[0]
		ore_counts[nm] = 0
		if ore_labels.has(nm):
			ore_labels[nm].text = "%s: 0" % nm

	global_position = spawn_position
	velocity = Vector2.ZERO

func _roll_count() -> int:
	var count = 1
	var n = 2
	while n <= 10 and randi() % n == 0:
		count += 1
		n += 1
	return count

func finish_mining():
	if not tilemap: return
	if _is_tile_unbreakable(target_tile_coords):
		is_mining = false
		return
	var is_grass = tilemap.get_cell_source_id(target_tile_coords) == 1
	tilemap.set_cell(target_tile_coords, -1)
	is_mining = false

	if is_grass:
		return

	var tile_world_pos = tilemap.to_global(tilemap.map_to_local(target_tile_coords))
	var found: Array[Dictionary] = []
	var cargo_remaining = max_cargo - current_cargo
	
	# Current luck bonus based on pickaxe level
	var current_luck = PICKAXE_UPGRADES[pickaxe_level]["luck"]

	for ore in ORE_TABLE:
		if cargo_remaining <= 0:
			break
		# Apply luck to the roll
		var chance_denom = float(ore[1]) / current_luck
		if randf() * chance_denom < 1.0:
			var amount = min(_roll_count(), cargo_remaining)
			cargo_remaining -= amount
			found.append({
				"name":   ore[0] as String,
				"amount": amount,
				"value":  int(ore[2]),
				"color":  ore[3] as Color,
			})

	if found.is_empty():
		_spawn_floating_text("No ore...", tile_world_pos, Color(0.6, 0.6, 0.6, 0.85))
		return

	var delay := 0.0
	for ore_data in found:
		_spawn_ore_fly(ore_data, tile_world_pos, delay)
		delay += 0.22

func _spawn_floating_text(msg: String, world_pos: Vector2, color: Color) -> void:
	var hud = get_parent().get_node_or_null("HUD")
	if not hud: return
	var label := Label.new()
	label.text = msg
	label.modulate = color
	label.add_theme_font_size_override("font_size", 16)
	label.position = get_viewport().get_canvas_transform() * world_pos + Vector2(-30.0, -10.0)
	label.z_index = 10
	hud.add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0.0, -45.0), 1.1)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.1)
	tween.tween_callback(label.queue_free)

func _spawn_ore_fly(ore_data: Dictionary, tile_world_pos: Vector2, delay: float) -> void:
	var hud = get_parent().get_node_or_null("HUD")
	if not hud: return
	
	var fly_node = Node2D.new()
	fly_node.z_index = 10
	
	var tex_path = ""
	match ore_data["name"]:
		"Stone": tex_path = "res://Stones_ores_bars/stone_1.png"
		"Copper": tex_path = "res://Stones_ores_bars/copper_ore.png"
		"Silver": tex_path = "res://Stones_ores_bars/silver_ore.png"
		"Gold": tex_path = "res://Stones_ores_bars/gold_ore.png"
		
	var sprite = Sprite2D.new()
	if tex_path != "" and FileAccess.file_exists(tex_path):
		sprite.texture = load(tex_path)
		sprite.scale = Vector2(2.5, 2.5)
	fly_node.add_child(sprite)

	var label := Label.new()
	label.text = "+%d" % ore_data["amount"]
	label.modulate = ore_data["color"]
	label.add_theme_font_size_override("font_size", 18)
	label.position = Vector2(10.0, -10.0)
	fly_node.add_child(label)

	var ct := get_viewport().get_canvas_transform()
	var screen_start := ct * tile_world_pos
	var screen_end := get_viewport_rect().size * 0.5

	fly_node.position = screen_start
	hud.add_child(fly_node)

	var tween = create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(fly_node, "position", screen_start + Vector2(0.0, -30.0), 0.20)
	tween.tween_property(fly_node, "position", screen_end, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		var nm: String    = ore_data["name"]
		var amt: int      = ore_data["amount"]
		ore_counts[nm] += amt
		current_cargo   += amt
		if ore_labels.has(nm):
			ore_labels[nm].text = "%s: %d" % [nm, ore_counts[nm]]
			var flash = create_tween()
			flash.tween_property(ore_labels[nm], "modulate:a", 0.15, 0.07)
			flash.tween_property(ore_labels[nm], "modulate:a", 1.00, 0.18)
		fly_node.queue_free()
	)
